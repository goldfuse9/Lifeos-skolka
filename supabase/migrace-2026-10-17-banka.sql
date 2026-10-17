-- =============================================================================
-- Školka — doplněk 17. 10. 2026: PLATBY Z BANKY SAMY a QR PLATBA PRO RODIČE.
-- Spusťte v Supabase → SQL Editor po migraci 2026-10-16-logo. Jde spustit opakovaně.
--
--   1) banka_napojeni      … API token banky školky (zatím Fio). Token nejde
--                            z aplikace přečíst — vidí ho jen server (service_role).
--   2) fin_zpracuj_platby  … jedno párování pro ruční výpis (.gpc) i pro banku:
--                            VS → dítě, jinak VS ve zprávě pro příjemce, jinak
--                            „nespárováno“. Duplicitu pozná podle dokladu banky
--                            i napříč zdroji (stejná platba z výpisu a z API).
--   3) banka-sync          … Edge Function (supabase/functions/banka-sync) stahuje
--                            pohyby a volá banka_zpracuj(); spouští ji pg_cron
--                            (supabase/banka-cron.sql) nebo tlačítko v ředitelně.
--   4) moje_platby()       … pro aplikaci rodiče: kolik zaplatit, VS, účet a hotový
--                            řetězec QR platby (SPAYD) za každé své dítě.
-- =============================================================================

-- ---------------------------------------------------------------- 1) napojení
create table if not exists banka_napojeni (
  skola_id uuid primary key references skoly on delete cascade,
  banka text not null default 'fio' check (banka in ('fio')),
  token text not null check (length(token) between 20 and 200),
  aktivni boolean not null default true,
  stahovat_dni int not null default 30 check (stahovat_dni between 1 and 89),
  posledni_beh timestamptz,
  posledni_vysledek jsonb,
  posledni_chyba text,
  upraveno timestamptz not null default now(),
  upravil uuid references uzivatele
);
alter table banka_napojeni enable row level security;   -- bez zásad: z aplikace ani řádek
revoke all on banka_napojeni from anon, authenticated, public;

-- Vedení uloží / změní / vypne napojení. Prázdný token = nechat stávající.
create or replace function uloz_napojeni_banky(p_token text, p_aktivni boolean default true) returns void
language plpgsql security definer set search_path = public as $$
declare s uuid := moje_skola(); t text := nullif(btrim(coalesce(p_token, '')), '');
begin
  if moje_role() is null or moje_role() not in ('reditelka', 'zastupce') or s is null then raise exception 'Napojení banky nastavuje vedení školy.'; end if;
  if t is not null and (length(t) < 20 or length(t) > 200 or t !~ '^[A-Za-z0-9]+$') then raise exception 'Token z banky nevypadá správně — zkopírujte ho celý.'; end if;
  if t is null then   -- jen zapnout / vypnout, token zůstává
    update banka_napojeni set aktivni = coalesce(p_aktivni, true), upraveno = now(), upravil = auth.uid() where skola_id = s;
    if not found then raise exception 'Vložte token z internetového bankovnictví.'; end if;
    return;
  end if;
  insert into banka_napojeni (skola_id, token, aktivni, upravil) values (s, t, coalesce(p_aktivni, true), auth.uid())
  on conflict (skola_id) do update set token = t, aktivni = coalesce(p_aktivni, true), upraveno = now(), upravil = auth.uid(), posledni_chyba = null;
end $$;

-- Stav napojení pro ředitelnu — bez tokenu (jen poslední 4 znaky).
create or replace function stav_napojeni_banky() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when je_finance() then (
    select jsonb_build_object('banka', b.banka, 'aktivni', b.aktivni, 'token_konec', right(b.token, 4),
      'posledni_beh', b.posledni_beh, 'posledni_vysledek', b.posledni_vysledek, 'posledni_chyba', b.posledni_chyba)
      from banka_napojeni b where b.skola_id = moje_skola()) end
$$;

-- Ředitelna smí spustit stažení jen pro svou školu (Edge Function si to ověří).
create or replace function muze_stahnout_z_banky() returns uuid
language sql stable security definer set search_path = public as $$
  select case when je_finance() then moje_skola() end
$$;

-- ----------------------------------------------------- 2) společné párování
-- Číslo účtu do porovnatelného tvaru: „předčíslí-číslo/banka“ bez úvodních nul
-- (výpis .gpc, Fio API i ruční zápis tak dají stejný klíč).
create or replace function ucet_klic(p text) returns text
language sql immutable set search_path = public as $$
  select case when m is null then ltrim(regexp_replace(coalesce(p, ''), '\D', '', 'g'), '0')
    else coalesce(nullif(ltrim(coalesce(m[1], ''), '0'), '') || '-', '') || coalesce(nullif(ltrim(m[2], '0'), ''), '0') || coalesce('/' || m[3], '') end
  from regexp_match(regexp_replace(coalesce(p, ''), '\s', '', 'g'), '^(?:([0-9]+)-)?([0-9]+)(?:/([0-9]{4}))?$') m
$$;
-- p_platby: [{datum, castka, vs, protiucet, nazev, zprava, doklad}] — jen příchozí.
create or replace function fin_zpracuj_platby(p_skola uuid, p_platby jsonb, p_zdroj text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  x record; vsn text; did uuid; pid uuid; r jsonb; n int; pu text;
  presne int := 0; preplatek int := 0; nedoplatek int := 0; nesparovano int := 0; duplicita int := 0; celkem numeric(12,2) := 0;
begin
  if p_skola is null then raise exception 'Neznámá školka.'; end if;
  if p_zdroj not in ('gpc', 'api', 'rucne') then raise exception 'Neznámý zdroj plateb.'; end if;
  if jsonb_typeof(p_platby) <> 'array' or jsonb_array_length(p_platby) > 2000 then raise exception 'Neplatný výpis.'; end if;
  perform pg_advisory_xact_lock(hashtext('platby:' || p_skola));   -- cron a ruční import nesmí běžet přes sebe
  for x in select * from jsonb_to_recordset(p_platby) as t(datum date, castka numeric, vs text, protiucet text, nazev text, zprava text, doklad text) loop
    if x.castka is null or x.castka <= 0 or x.castka > 1000000 or x.datum is null then raise exception 'Neplatná platba ve výpisu.'; end if;
    -- tentýž doklad už je načtený
    if coalesce(x.doklad, '') <> '' and exists (select 1 from platby where skola_id = p_skola and doklad = x.doklad) then duplicita := duplicita + 1; continue; end if;
    -- stejná platba z jiného zdroje (výpis .gpc i API za stejné dny) — den, částka, VS a protiúčet
    pu := ucet_klic(x.protiucet);
    if pu <> '' and exists (select 1 from platby where skola_id = p_skola and zdroj <> p_zdroj and datum = x.datum and castka = round(x.castka, 2)
        and ltrim(regexp_replace(vs, '\D', '', 'g'), '0') = ltrim(regexp_replace(coalesce(x.vs, ''), '\D', '', 'g'), '0')
        and ucet_klic(protiucet) = pu) then
      duplicita := duplicita + 1; continue;
    end if;
    -- dítě podle VS …
    vsn := ltrim(regexp_replace(coalesce(x.vs, ''), '\D', '', 'g'), '0');
    did := null;
    if vsn <> '' then select id into did from deti where skola_id = p_skola and ltrim(coalesce(variabilni_symbol, ''), '0') = vsn limit 1; end if;
    -- … nebo podle VS napsaného do zprávy (rodič ho dal do poznámky), jen když sedí na jediné dítě;
    -- krátké VS (1–3 číslice) se ve zprávě nehledají — „1“ nebo „10“ je tam skoro vždycky
    if did is null and coalesce(x.zprava, '') ~ '\d' then
      select count(*), min(id::text)::uuid into n, did from deti
       where skola_id = p_skola and length(ltrim(coalesce(variabilni_symbol, ''), '0')) >= 4
         and x.zprava ~ ('(^|\D)0*' || ltrim(variabilni_symbol, '0') || '(\D|$)');
      if n <> 1 then did := null; end if;
    end if;
    insert into platby (skola_id, datum, castka, vs, protiucet, nazev, zdroj, doklad)
    values (p_skola, x.datum, round(x.castka, 2), left(coalesce(x.vs, ''), 10), left(coalesce(x.protiucet, ''), 40),
            left(coalesce(nullif(x.nazev, ''), x.zprava, ''), 60), p_zdroj, left(coalesce(x.doklad, ''), 80))
    returning id into pid;
    celkem := celkem + round(x.castka, 2);
    if did is null then
      insert into nesparovane_platby (platba_id, duvod) values (pid, case when coalesce(x.vs, '') = '' then 'Platba nemá VS' else 'VS ' || x.vs || ' nepatří žádnému dítěti' end);
      nesparovano := nesparovano + 1;
    else
      r := fin_pripis(pid, did);
      case r->>'vysledek' when 'presne' then presne := presne + 1; when 'preplatek' then preplatek := preplatek + 1; else nedoplatek := nedoplatek + 1; end case;
    end if;
  end loop;
  return jsonb_build_object('presne', presne, 'preplatek', preplatek, 'nedoplatek', nedoplatek, 'nesparovano', nesparovano, 'duplicita', duplicita, 'celkem', celkem);
end $$;
revoke execute on function fin_zpracuj_platby(uuid, jsonb, text) from anon, public, authenticated;

-- Ruční import výpisu z ředitelny — stejné chování jako dřív, jen přes společné párování.
create or replace function zpracuj_platby(p_platby jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not je_finance() then raise exception 'Platby zpracovává vedení nebo hospodářka.'; end if;
  return fin_zpracuj_platby(moje_skola(), p_platby, 'gpc');
end $$;

-- ------------------------------------------------- 3) pro Edge Function banka-sync
-- Aktivní napojení (i s tokenem) — jen server.
create or replace function banka_ke_stazeni(p_skola uuid default null) returns table (skola_id uuid, banka text, token text, stahovat_dni int)
language sql stable security definer set search_path = public as $$
  select b.skola_id, b.banka, b.token, b.stahovat_dni from banka_napojeni b join skoly s on s.id = b.skola_id
   where b.aktivni and s.stav = 'aktivni' and b.token <> '' and (p_skola is null or b.skola_id = p_skola)
$$;

-- Zpracuje stažené platby a zapíše výsledek (nebo chybu) k napojení.
create or replace function banka_zpracuj(p_skola uuid, p_platby jsonb, p_chyba text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  if p_chyba is not null then
    update banka_napojeni set posledni_beh = now(), posledni_chyba = left(p_chyba, 500) where skola_id = p_skola;
    return null;
  end if;
  r := fin_zpracuj_platby(p_skola, coalesce(p_platby, '[]'::jsonb), 'api');
  update banka_napojeni set posledni_beh = now(), posledni_vysledek = r, posledni_chyba = null where skola_id = p_skola;
  return r;
end $$;

revoke execute on function banka_ke_stazeni(uuid), banka_zpracuj(uuid, jsonb, text) from anon, public, authenticated;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function banka_ke_stazeni(uuid), banka_zpracuj(uuid, jsonb, text), fin_zpracuj_platby(uuid, jsonb, text) to service_role;
    grant select, insert, update on banka_napojeni to service_role;
  end if;
end $$;

-- ------------------------------------------------------- 4) QR platba pro rodiče
-- České číslo účtu (předčíslí-číslo/banka) → IBAN; IBAN projde kontrolou. Neplatné → null.
create or replace function cz_iban(p_ucet text) returns text
language plpgsql immutable set search_path = public as $$
declare t text := upper(regexp_replace(coalesce(p_ucet, ''), '\s', '', 'g')); m text[]; pre text; num text; bban text; ck int;
begin
  if t ~ '^CZ[0-9]{22}$' then
    return case when ((substr(t, 5) || '1235' || substr(t, 3, 2))::numeric % 97) = 1 then t end;
  end if;
  m := regexp_match(t, '^(?:([0-9]{1,6})-)?([0-9]{2,10})/([0-9]{4})$');
  if m is null then return null; end if;
  pre := lpad(coalesce(m[1], '0'), 6, '0'); num := lpad(m[2], 10, '0');
  -- vážené kontrolní součty čísel účtů (vyhl. ČNB 169/2011 Sb.)
  if (select sum(substr(pre, i, 1)::int * (array[10,5,8,4,2,1])[i]) from generate_series(1, 6) i) % 11 <> 0
     or (select sum(substr(num, i, 1)::int * (array[6,3,7,9,10,5,8,4,2,1])[i]) from generate_series(1, 10) i) % 11 <> 0 then
    return null;
  end if;
  bban := m[3] || pre || num;
  ck := 98 - ((bban || '123500')::numeric % 97)::int;
  return 'CZ' || lpad(ck::text, 2, '0') || bban;
end $$;

-- Text do QR / zprávy pro příjemce: bez diakritiky, hvězdiček a nových řádků, max. n znaků.
create or replace function spayd_text(p text, n int) returns text
language sql immutable set search_path = public as $$
  select left(upper(btrim(regexp_replace(translate(coalesce(p, ''),
    'áčďéěíňóřšťúůýžÁČĎÉĚÍŇÓŘŠŤÚŮÝŽäöüÄÖÜ', 'acdeeinorstuuyzACDEEINORSTUUYZaouAOU'), '[*\s]+', ' ', 'g'))), n)
$$;

-- Platby mých dětí pro aplikaci rodiče (LifeOS). Vidí jen rodič svoje děti.
-- k_uhrade = celý dluh na kontě (předpisy se hradí od nejstaršího), qr = řetězec SPAYD
-- (null, když není co platit nebo školka nemá platný účet / dítě nemá VS).
create or replace function moje_platby() returns table (
  dite_id uuid, jmeno text, k_uhrade numeric, preplatek numeric, splatnost date, po_splatnosti boolean,
  vs text, ucet text, iban text, prijemce text, zprava text, qr text, predpisy jsonb)
language sql stable security definer set search_path = public as $$
  with moje as (
    select d.* from deti d
     where moje_role() = 'rodic' and moje_dite(d.id) and (d.ukonceno is null or d.ukonceno >= dnes_praha() - 90)
  ), x as (
    select m.id, m.jmeno || ' ' || m.prijmeni as jmeno, ltrim(coalesce(m.variabilni_symbol, ''), '0') as vs,
           greatest(0, -coalesce(k.saldo, 0)) as dluh, greatest(0, coalesce(k.saldo, 0)) as kredit,
           f.ucet, cz_iban(f.ucet) as iban, s.nazev as skola,
           (select min(p.splatnost) from predpisy p where p.dite_id = m.id and p.stav <> 'zaplaceno') as spl,
           (select string_agg(to_char(to_date(p.obdobi || '-01', 'YYYY-MM-DD'), 'MM/YYYY'), ', ' order by p.obdobi)
              from predpisy p where p.dite_id = m.id and p.stav <> 'zaplaceno') as obdobi
      from moje m join skoly s on s.id = m.skola_id
      left join konta k on k.dite_id = m.id
      left join financni_nastaveni f on f.skola_id = m.skola_id
  )
  select x.id, x.jmeno, x.dluh, x.kredit, x.spl, coalesce(x.spl < dnes_praha(), false), nullif(x.vs, ''), x.ucet, x.iban, x.skola,
         spayd_text('Skolka ' || coalesce(x.obdobi, '') || ' ' || x.jmeno, 60),
         case when x.dluh > 0 and x.iban is not null and x.vs <> '' then
           'SPD*1.0*ACC:' || x.iban || '*AM:' || to_char(x.dluh, 'FM9999990.00') || '*CC:CZK*X-VS:' || x.vs
           || '*RN:' || spayd_text(x.skola, 35) || '*MSG:' || spayd_text('Skolka ' || coalesce(x.obdobi, '') || ' ' || x.jmeno, 60)
           || case when x.spl >= dnes_praha() then '*DT:' || to_char(x.spl, 'YYYYMMDD') else '' end
         end,
         coalesce((select jsonb_agg(jsonb_build_object('obdobi', p.obdobi, 'castka', p.castka, 'uhrazeno', p.uhrazeno, 'stav', p.stav, 'splatnost', p.splatnost,
                     'polozky', (select jsonb_agg(jsonb_build_object('popis', q.popis, 'mnozstvi', q.mnozstvi, 'castka', q.castka) order by q.poradi) from predpis_polozky q where q.predpis_id = p.id))
                     order by p.obdobi desc)
                     from (select * from predpisy where dite_id = x.id order by obdobi desc limit 12) p), '[]'::jsonb)
    from x order by x.jmeno
$$;

revoke execute on function uloz_napojeni_banky(text, boolean), stav_napojeni_banky(), muze_stahnout_z_banky(), moje_platby(), zpracuj_platby(jsonb) from anon, public;
grant execute on function uloz_napojeni_banky(text, boolean), stav_napojeni_banky(), muze_stahnout_z_banky(), moje_platby(), zpracuj_platby(jsonb) to authenticated;
grant execute on function cz_iban(text), spayd_text(text, int), ucet_klic(text) to authenticated;
