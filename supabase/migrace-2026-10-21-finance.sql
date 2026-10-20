-- =============================================================================
-- Školka — doplněk 21. 10. 2026: POKROČILÉ FINANCE.
-- Spusťte v Supabase → SQL Editor po migraci 2026-10-20-majetek. Jde spustit opakovaně.
--
--   * Školkovné předem: měsíční předpis na začátku měsíce, splatnost do N. dne
--     téhož měsíce (vyhl. 14/2005 Sb. § 6: do 15. dne, není-li dohodnuto jinak).
--   * Stravné: režim „zálohy“ (měsíční záloha předem + vyúčtování podle skutečně
--     odebraných obědů) nebo „skutečnost“ (dosavadní: zpětně po skončení měsíce).
--   * Slevy a prominutí úplaty (rozhodnutí ředitelky, s platností).
--   * Jednorázové platby (výlety, divadla, pomůcky, kroužky, fond) pro vybrané děti
--     nebo podle přihlášek na akci.
--   * Storno předpisu protizápisem — nic se nemaže.
--   * Pokladna: příjmové a výdajové pokladní doklady s číselnou řadou.
--   * Vratky přeplatků (na účet hromadným příkazem, nebo hotově z pokladny).
--   * Uzávěrka měsíce: každý účetní pohyb dostane účetní období; po uzávěrce
--     už do uzavřeného měsíce nic nepřibude (pozdní pohyby jdou do dalšího
--     otevřeného měsíce) a export pro účetní se nemění.
--   * Předkontace (MD/Dal účty) pro export — nastaví si účetní.
-- =============================================================================

-- ---------------------------------------------------------------- nastavení
-- dosavadní školky zůstanou u stravného podle skutečnosti, dokud to vedení nepřepne; nové začínají zálohami
alter table financni_nastaveni add column if not exists rezim_stravne text not null default 'skutecnost';
alter table financni_nastaveni alter column rezim_stravne set default 'zalohy';
alter table financni_nastaveni drop constraint if exists fn_rezim;
alter table financni_nastaveni add constraint fn_rezim check (rezim_stravne in ('zalohy', 'skutecnost'));
alter table financni_nastaveni add column if not exists zaloha_36 numeric(10,2) check (zaloha_36 is null or zaloha_36 >= 0);
alter table financni_nastaveni add column if not exists zaloha_7 numeric(10,2) check (zaloha_7 is null or zaloha_7 >= 0);
alter table financni_nastaveni add column if not exists predkontace jsonb not null default '{}'::jsonb;
alter table financni_nastaveni add column if not exists pokladna_pocatek numeric(12,2) not null default 0;

-- ---------------------------------------------------------------- předpisy
alter table predpisy add column if not exists druh text not null default 'mesicni';
alter table predpisy drop constraint if exists predpisy_druh;
alter table predpisy add constraint predpisy_druh check (druh in ('mesicni', 'vyuctovani', 'jednorazova'));
alter table predpisy add column if not exists nazev text not null default '';
alter table predpisy add column if not exists cislo text;
alter table predpisy add column if not exists storno timestamptz;
alter table predpisy add column if not exists storno_duvod text;
alter table predpisy add column if not exists akce_id uuid references akce on delete set null;
alter table predpisy drop constraint if exists predpisy_dite_id_obdobi_key;
create unique index if not exists predpisy_mesicni on predpisy (dite_id, obdobi) where druh = 'mesicni' and storno is null;
alter table predpisy drop constraint if exists predpisy_stav_check;
alter table predpisy add constraint predpisy_stav_check check (stav in ('otevreno', 'castecne_zaplaceno', 'zaplaceno', 'storno'));
alter table predpis_polozky drop constraint if exists predpis_polozky_druh_check;
alter table predpis_polozky add constraint predpis_polozky_druh_check check (druh in ('skolkovne', 'stravne', 'stravne_zaloha', 'stravne_vyuctovani', 'akce', 'pomucky', 'krouzek', 'fond', 'jine'));

-- ---------------------------------------------------------------- účetní pohyby
alter table ucetni_pohyby add column if not exists druh text not null default '';
alter table ucetni_pohyby add column if not exists obdobi_uctu char(7);
alter table ucetni_pohyby drop constraint if exists ucetni_pohyby_ucty;
alter table ucetni_pohyby add constraint ucetni_pohyby_ucty check (
  md ~ '^(dite:[0-9a-f-]{36}|banka|pokladna|vynosy:[a-z_]+|ostatni:[a-z_]+)$' and dal ~ '^(dite:[0-9a-f-]{36}|banka|pokladna|vynosy:[a-z_]+|ostatni:[a-z_]+)$') not valid;
create index if not exists ucetni_pohyby_obdobi on ucetni_pohyby (skola_id, obdobi_uctu);

create table if not exists fin_uzaverky (
  skola_id uuid not null references skoly on delete cascade,
  obdobi char(7) not null check (obdobi ~ '^[0-9]{4}-[0-9]{2}$'),
  uzavreno timestamptz not null default now(),
  kdo uuid references uzivatele default auth.uid(),
  primary key (skola_id, obdobi)
);

-- Účetní období pohybu: měsíc data, nebo první otevřený měsíc po něm.
create or replace function fin_obdobi(p_skola uuid, p_datum date) returns char(7)
language plpgsql stable security definer set search_path = public as $$
declare o char(7) := to_char(p_datum, 'YYYY-MM');
begin
  while exists (select 1 from fin_uzaverky where skola_id = p_skola and obdobi = o) loop
    o := to_char(to_date(o || '-01', 'YYYY-MM-DD') + interval '1 month', 'YYYY-MM');
  end loop;
  return o;
end $$;

create or replace function pohyb_obdobi() returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.obdobi_uctu := fin_obdobi(new.skola_id, new.datum);
  return new;
end $$;
drop trigger if exists t_pohyb_obdobi on ucetni_pohyby;
create trigger t_pohyb_obdobi before insert on ucetni_pohyby for each row execute function pohyb_obdobi();
-- starší pohyby: období podle data (jednorázově; trigger zakazuje UPDATE, tak ho na chvíli vypneme)
do $$ begin
  if exists (select 1 from ucetni_pohyby where obdobi_uctu is null) then
    alter table ucetni_pohyby disable trigger t_pohyby_jen_pridavat;
    update ucetni_pohyby set obdobi_uctu = to_char(datum, 'YYYY-MM') where obdobi_uctu is null;
    alter table ucetni_pohyby enable trigger t_pohyby_jen_pridavat;
  end if;
end $$;

-- ---------------------------------------------------------------- číselné řady dokladů
create table if not exists fin_rady (
  skola_id uuid not null references skoly on delete cascade,
  rada text not null, rok int not null, posledni int not null default 0,
  primary key (skola_id, rada, rok)
);
create or replace function fin_cislo(p_skola uuid, p_rada text, p_datum date default null) returns text
language plpgsql security definer set search_path = public as $$
declare r int := extract(year from coalesce(p_datum, dnes_praha()))::int; n int;
begin
  insert into fin_rady (skola_id, rada, rok) values (p_skola, p_rada, r) on conflict do nothing;
  update fin_rady set posledni = posledni + 1 where skola_id = p_skola and rada = p_rada and rok = r returning posledni into n;
  return p_rada || '-' || r || '-' || lpad(n::text, 5, '0');
end $$;

-- ---------------------------------------------------------------- slevy a prominutí
create table if not exists fin_upravy (
  id uuid primary key default gen_random_uuid(),
  skola_id uuid not null references skoly on delete cascade,
  dite_id uuid not null references deti on delete cascade,
  typ text not null check (typ in ('osvobozeni', 'procento', 'castka')),
  hodnota numeric(10,2) not null default 0 check (hodnota >= 0),
  plati_od date not null, plati_do date,
  duvod text not null check (length(btrim(duvod)) between 1 and 200),
  rozhodnuti text not null default '' check (length(rozhodnuti) <= 60),
  vytvoreno timestamptz not null default now(),
  zruseno timestamptz,
  check (typ <> 'procento' or hodnota <= 100),
  check (plati_do is null or plati_do >= plati_od)
);

-- ---------------------------------------------------------------- vyúčtování stravného
create table if not exists fin_vyuctovani (
  id uuid primary key default gen_random_uuid(),
  skola_id uuid not null references skoly on delete cascade,
  dite_id uuid not null references deti on delete cascade,
  od date not null, do_dne date not null,
  zalohy numeric(10,2) not null, obedy int not null, skutecnost numeric(10,2) not null, rozdil numeric(10,2) not null,
  predpis_id uuid references predpisy,
  cislo text, vytvoreno timestamptz not null default now()
);

-- ---------------------------------------------------------------- pokladna a vratky
create table if not exists pokladna (
  id uuid primary key default gen_random_uuid(),
  skola_id uuid not null references skoly on delete cascade,
  cislo text not null,
  datum date not null,
  druh text not null check (druh in ('prijem', 'vydej')),
  castka numeric(12,2) not null check (castka > 0),
  dite_id uuid references deti,
  ucel text not null check (length(btrim(ucel)) between 1 and 200),
  osoba text not null default '' check (length(osoba) <= 80),
  platba_id uuid references platby,
  zapsal uuid references uzivatele default auth.uid(),
  vytvoreno timestamptz not null default now(),
  unique (skola_id, cislo)
);

create table if not exists fin_vratky (
  id uuid primary key default gen_random_uuid(),
  skola_id uuid not null references skoly on delete cascade,
  dite_id uuid not null references deti,
  castka numeric(10,2) not null check (castka > 0),
  zpusob text not null check (zpusob in ('banka', 'pokladna')),
  ucet text not null default '' check (length(ucet) <= 40),
  cislo text not null,
  stav text not null default 'pripraveno' check (stav in ('pripraveno', 'odeslano')),
  vytvoreno timestamptz not null default now(),
  odeslano timestamptz,
  pokladna_id uuid references pokladna
);

-- ---------------------------------------------------------------- práva čtení
alter table fin_uzaverky enable row level security;
alter table fin_rady enable row level security;
alter table fin_upravy enable row level security;
alter table fin_vyuctovani enable row level security;
alter table pokladna enable row level security;
alter table fin_vratky enable row level security;
drop policy if exists fu_cist on fin_uzaverky;   create policy fu_cist on fin_uzaverky for select using (skola_id = moje_skola() and je_finance());
drop policy if exists fup_cist on fin_upravy;    create policy fup_cist on fin_upravy for select using (skola_id = moje_skola() and (je_finance() or (moje_role() = 'rodic' and moje_dite(dite_id))));
drop policy if exists fvy_cist on fin_vyuctovani; create policy fvy_cist on fin_vyuctovani for select using (skola_id = moje_skola() and (je_finance() or (moje_role() = 'rodic' and moje_dite(dite_id))));
drop policy if exists pok_cist on pokladna;      create policy pok_cist on pokladna for select using (skola_id = moje_skola() and je_finance());
drop policy if exists fvr_cist on fin_vratky;    create policy fvr_cist on fin_vratky for select using (skola_id = moje_skola() and (je_finance() or (moje_role() = 'rodic' and moje_dite(dite_id))));
revoke insert, update, delete, truncate on fin_uzaverky, fin_rady, fin_upravy, fin_vyuctovani, pokladna, fin_vratky from authenticated, anon;
revoke all on fin_rady from authenticated, anon;
grant select on fin_uzaverky, fin_upravy, fin_vyuctovani, pokladna, fin_vratky to authenticated;

drop trigger if exists a_fin_upravy on fin_upravy;
create trigger a_fin_upravy after insert or update on fin_upravy for each row execute function zapis_audit();
drop trigger if exists a_pokladna on pokladna;
create trigger a_pokladna after insert on pokladna for each row execute function zapis_audit();
drop trigger if exists a_fin_vratky on fin_vratky;
create trigger a_fin_vratky after insert or update on fin_vratky for each row execute function zapis_audit();

-- ---------------------------------------------------------------- pomocné
create or replace function fin_skola() returns uuid language plpgsql stable security definer set search_path = public as $$
begin
  if not je_finance() then raise exception 'Platby spravuje vedení nebo hospodářka.'; end if;
  return moje_skola();
end $$;

create or replace function fin_otevreno(p_skola uuid, p_obdobi text) returns void language plpgsql stable security definer set search_path = public as $$
begin
  if exists (select 1 from fin_uzaverky where skola_id = p_skola and obdobi = p_obdobi) then
    raise exception 'Měsíc % je uzavřený (předaný účetní) — změny jdou jen do otevřeného měsíce.', p_obdobi;
  end if;
end $$;

-- Věková kategorie stravného ke 31. 8. školního roku.
create or replace function fin_kat(p_narozeni date, p_den date) returns text language sql immutable as $$
  select case when extract(year from age(make_date(extract(year from p_den)::int + case when extract(month from p_den) >= 9 then 1 else 0 end, 8, 31), p_narozeni)) >= 7 then '7+' else '3-6' end
$$;

-- Pracovní dny v měsíci (bez víkendů a státních svátků s pevným datem; Velikonoce zálohu neovlivní).
create or replace function fin_pracovni_dny(p_od date, p_do date) returns int language sql immutable as $$
  select count(*)::int from generate_series(p_od, p_do, interval '1 day') g(d)
   where extract(isodow from d) < 6 and to_char(d, 'MM-DD') not in ('01-01', '05-01', '05-08', '07-05', '07-06', '09-28', '10-28', '11-17', '12-24', '12-25', '12-26')
$$;

-- Úprava školkovného platná v měsíci (nejnovější vyhrává).
create or replace function fin_uprava(p_dite uuid, p_od date, p_do date) returns fin_upravy language sql stable security definer set search_path = public as $$
  select * from fin_upravy where dite_id = p_dite and zruseno is null and plati_od <= p_do and (plati_do is null or plati_do >= p_od)
   order by vytvoreno desc limit 1
$$;

-- Rozpuštění úhrad do předpisů od nejstaršího. Kredit = úhrady a dobropisy (ne storna) minus vratky.
create or replace function fin_vyrovnej(p_dite uuid) returns void
language plpgsql security definer set search_path = public as $$
declare kredit numeric(12,2); p record; u numeric(10,2); st text;
begin
  select coalesce(sum(castka) filter (where dal = 'dite:' || p_dite and druh <> 'storno'), 0)
       - coalesce(sum(castka) filter (where md = 'dite:' || p_dite and druh = 'vratka'), 0)
    into kredit from ucetni_pohyby where dal = 'dite:' || p_dite or md = 'dite:' || p_dite;
  for p in select * from predpisy where dite_id = p_dite and storno is null order by splatnost, vystaveno, obdobi, id loop
    u := least(p.castka, greatest(0, kredit));
    kredit := kredit - u;
    st := case when u >= p.castka then 'zaplaceno' when u > 0 then 'castecne_zaplaceno' else 'otevreno' end;
    if p.uhrazeno is distinct from u or p.stav is distinct from st then
      update predpisy set uhrazeno = u, stav = st where id = p.id;
    end if;
  end loop;
end $$;

-- Zápis předpisu do knihy (MD dítě / Dal výnosy podle položek).
create or replace function fin_zauctuj_predpis(p_predpis uuid, p_datum date) returns void
language plpgsql security definer set search_path = public as $$
declare p predpisy; d deti;
begin
  select * into p from predpisy where id = p_predpis;
  select * into d from deti where id = p.dite_id;
  insert into ucetni_pohyby (skola_id, datum, md, dal, castka, popis, doklad, druh)
  select d.skola_id, p_datum, 'dite:' || d.id, 'vynosy:' || case when q.druh in ('stravne_zaloha', 'stravne_vyuctovani') then 'stravne' else q.druh end,
         q.castka, q.popis || ' — ' || d.jmeno || ' ' || d.prijmeni, coalesce(p.cislo, p.id::text), 'predpis'
    from predpis_polozky q where q.predpis_id = p_predpis and q.castka > 0 order by q.poradi;
end $$;

-- Připsání platby dítěti: banka nebo pokladna podle zdroje platby.
create or replace function fin_pripis(p_platba uuid, p_dite uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pl platby; dluh numeric(10,2); d deti;
begin
  select * into pl from platby where id = p_platba;
  select * into d from deti where id = p_dite;
  select greatest(0, -coalesce((select saldo from konta where dite_id = p_dite), 0)) into dluh;
  update platby set dite_id = p_dite where id = p_platba;
  insert into ucetni_pohyby (skola_id, datum, md, dal, castka, popis, doklad, druh)
  values (pl.skola_id, pl.datum, case when pl.zdroj = 'pokladna' then 'pokladna' else 'banka' end, 'dite:' || p_dite, pl.castka,
          case when pl.zdroj = 'pokladna' then 'Platba hotově ' || pl.doklad else 'Platba VS ' || coalesce(nullif(pl.vs, ''), '—') end || ' — ' || d.jmeno || ' ' || d.prijmeni,
          coalesce(nullif(pl.doklad, ''), pl.id::text), 'platba');
  perform fin_vyrovnej(p_dite);
  return jsonb_build_object('vysledek', case when pl.castka = dluh then 'presne' when pl.castka > dluh then 'preplatek' else 'nedoplatek' end,
    'dite', p_dite, 'preplatek', greatest(0, pl.castka - dluh), 'zbyva', greatest(0, dluh - pl.castka));
end $$;

revoke execute on function fin_obdobi(uuid, date), fin_cislo(uuid, text, date), fin_skola(), fin_otevreno(uuid, text), fin_uprava(uuid, date, date),
  fin_vyrovnej(uuid), fin_zauctuj_predpis(uuid, date), fin_pripis(uuid, uuid) from anon, public, authenticated;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then grant execute on function fin_pripis(uuid, uuid), fin_vyrovnej(uuid), fin_obdobi(uuid, date) to service_role; end if;
end $$;

-- ---------------------------------------------------------------- nastavení plateb
create or replace function uloz_financni_rezim(p_rezim text, p_zaloha_36 numeric, p_zaloha_7 numeric, p_predkontace jsonb, p_pokladna_pocatek numeric)
returns void language plpgsql security definer set search_path = public as $$
declare s uuid := moje_skola();
begin
  if moje_role() not in ('reditelka', 'zastupce') then raise exception 'Nastavení plateb mění vedení školy.'; end if;
  if p_rezim not in ('zalohy', 'skutecnost') then raise exception 'Neznámý režim stravného.'; end if;
  if not exists (select 1 from financni_nastaveni where skola_id = s) then raise exception 'Nejdřív vyplňte účet a ceny.'; end if;
  if jsonb_typeof(coalesce(p_predkontace, '{}'::jsonb)) <> 'object' or length(p_predkontace::text) > 4000 then raise exception 'Neplatná předkontace.'; end if;
  update financni_nastaveni set rezim_stravne = p_rezim, zaloha_36 = round(p_zaloha_36, 2), zaloha_7 = round(p_zaloha_7, 2),
    predkontace = coalesce(p_predkontace, '{}'::jsonb), pokladna_pocatek = round(coalesce(p_pokladna_pocatek, 0), 2) where skola_id = s;
end $$;

-- ---------------------------------------------------------------- měsíční předpisy
-- Režim „zálohy“: na začátku měsíce (od 20. dne předchozího) školkovné + záloha na stravné,
-- splatnost N. den téhož měsíce. Režim „skutečnost“: po skončení měsíce jako dřív.
create or replace function vystav_predpisy(p_obdobi text) returns int
language plpgsql security definer set search_path = public as $$
declare
  s uuid := fin_skola(); nf financni_nastaveni; od date; dokdy date; spl date; d deti; pid uuid; n int := 0;
  celkem numeric(10,2); por int; x record; jmeno text; mesic text; up fin_upravy; sk numeric(10,2); kat text; zal numeric(10,2); cena numeric(10,2); dnes date := dnes_praha();
begin
  if p_obdobi !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then raise exception 'Neplatné období.'; end if;
  select * into nf from financni_nastaveni where skola_id = s;
  if not found then raise exception 'Nejdřív vyplňte nastavení plateb (účet a ceny).'; end if;
  perform fin_otevreno(s, p_obdobi);
  od := to_date(p_obdobi || '-01', 'YYYY-MM-DD');
  dokdy := (od + interval '1 month' - interval '1 day')::date;
  mesic := (array['leden','únor','březen','duben','květen','červen','červenec','srpen','září','říjen','listopad','prosinec'])[extract(month from od)::int] || ' ' || extract(year from od)::int;
  if nf.rezim_stravne = 'zalohy' then
    if od - 12 > dnes then raise exception 'Předpisy na % jde vystavit nejdřív od 20. dne předchozího měsíce.', mesic; end if;
    spl := greatest(make_date(extract(year from od)::int, extract(month from od)::int, nf.splatnost_den), dnes + 7);
  else
    if dokdy >= dnes then raise exception 'V režimu „stravné podle skutečnosti“ se předpisy vystavují až po skončení měsíce.'; end if;
    spl := make_date(extract(year from dokdy + 1)::int, extract(month from dokdy + 1)::int, nf.splatnost_den);
  end if;
  perform pg_advisory_xact_lock(hashtext('predpisy:' || s || ':' || p_obdobi));
  for d in select * from deti where skola_id = s and zahajeni <= dokdy and (ukonceno is null or ukonceno >= od) order by prijmeni, jmeno loop
    continue when exists (select 1 from predpisy where dite_id = d.id and obdobi = p_obdobi and druh = 'mesicni' and storno is null);
    jmeno := d.jmeno || ' ' || d.prijmeni;
    insert into predpisy (dite_id, obdobi, castka, splatnost, vystaveno, druh, nazev, cislo)
    values (d.id, p_obdobi, 0, spl, dnes, 'mesicni', mesic, fin_cislo(s, 'PR')) returning id into pid;
    celkem := 0; por := 1;
    -- školkovné: osvobození (PPV, odklad), nebo úprava ředitelky
    up := fin_uprava(d.id, od, dokdy);
    if d.osvobozen_od_skolkovneho then
      insert into predpis_polozky values (pid, por, 'skolkovne', 'Školkovné ' || mesic || ' — osvobozeno (PPV / odklad)', 1, 0, 0);
    elsif up.id is not null and up.typ = 'osvobozeni' then
      insert into predpis_polozky values (pid, por, 'skolkovne', 'Školkovné ' || mesic || ' — prominuto: ' || up.duvod, 1, 0, 0);
    elsif up.id is not null then
      sk := greatest(0, round(case when up.typ = 'procento' then nf.skolkovne * (100 - up.hodnota) / 100 else nf.skolkovne - up.hodnota end, 2));
      insert into predpis_polozky values (pid, por, 'skolkovne', 'Školkovné ' || mesic || ' — sníženo: ' || up.duvod, 1, sk, sk);
      celkem := celkem + sk;
    else
      insert into predpis_polozky values (pid, por, 'skolkovne', 'Školkovné ' || mesic, 1, nf.skolkovne, nf.skolkovne);
      celkem := celkem + nf.skolkovne;
    end if;
    if nf.rezim_stravne = 'zalohy' then
      kat := fin_kat(d.datum_narozeni, od);
      select sz.cena into cena from sazby_stravneho sz where sz.skola_id = s and sz.kategorie = kat;
      if cena is null then raise exception 'Školka nemá cenu stravného pro kategorii % let.', kat; end if;
      zal := coalesce(case kat when '7+' then nf.zaloha_7 else nf.zaloha_36 end, round(cena * fin_pracovni_dny(greatest(od, d.zahajeni), dokdy), 2));
      if zal > 0 then
        por := por + 1;
        insert into predpis_polozky values (pid, por, 'stravne_zaloha', 'Záloha na stravné ' || mesic || ' (' || kat || ' let)', 1, zal, zal);
        celkem := celkem + zal;
      end if;
    else
      for x in
        select k.kat, count(*)::int as dny, sz.cena from (
          select fin_kat(d.datum_narozeni, y.den) as kat from dochazka y
           where y.dite_id = d.id and y.den between od and dokdy and y.strava_prihlasena
             and not (y.omluva_zadana is not null and (y.omluva_zadana at time zone 'Europe/Prague') <= ((y.den - nf.omluva_dni_predem) + nf.omluva_do))
        ) k left join sazby_stravneho sz on sz.skola_id = s and sz.kategorie = k.kat
        group by k.kat, sz.cena order by k.kat
      loop
        if x.cena is null then raise exception 'Školka nemá cenu stravného pro kategorii % let.', x.kat; end if;
        por := por + 1;
        insert into predpis_polozky values (pid, por, 'stravne', 'Stravné ' || x.kat || ' let', x.dny, x.cena, round(x.cena * x.dny, 2));
        celkem := celkem + round(x.cena * x.dny, 2);
      end loop;
    end if;
    update predpisy set castka = celkem, stav = case when celkem = 0 then 'zaplaceno' else 'otevreno' end where id = pid;
    perform fin_zauctuj_predpis(pid, case when nf.rezim_stravne = 'zalohy' then od else dokdy end);
    perform fin_vyrovnej(d.id);
    n := n + 1;
  end loop;
  return n;
end $$;

-- ---------------------------------------------------------------- jednorázové platby
-- Výlet, divadlo, pomůcky, kroužek, fond… pro vybrané děti. Kdo už předpis k té akci má, přeskočí se.
create or replace function nova_hromadna_platba(p_nazev text, p_druh text, p_castka numeric, p_splatnost date, p_deti uuid[], p_akce uuid default null) returns int
language plpgsql security definer set search_path = public as $$
declare s uuid := fin_skola(); d deti; pid uuid; n int := 0; dnes date := dnes_praha();
begin
  if coalesce(btrim(p_nazev), '') = '' or length(p_nazev) > 80 then raise exception 'Napište, za co se platí.'; end if;
  if p_druh not in ('akce', 'pomucky', 'krouzek', 'fond', 'jine') then raise exception 'Neznámý druh platby.'; end if;
  if p_castka is null or p_castka <= 0 or p_castka > 100000 then raise exception 'Neplatná částka.'; end if;
  if p_splatnost is null then raise exception 'Zadejte splatnost.'; end if;
  if p_akce is not null and not exists (select 1 from akce where id = p_akce and skola_id = s) then raise exception 'Akce do školky nepatří.'; end if;
  perform fin_otevreno(s, to_char(dnes, 'YYYY-MM'));
  for d in select * from deti where id = any(p_deti) and skola_id = s order by prijmeni, jmeno loop
    continue when p_akce is not null and exists (select 1 from predpisy where dite_id = d.id and akce_id = p_akce and storno is null);
    insert into predpisy (dite_id, obdobi, castka, splatnost, vystaveno, druh, nazev, cislo, akce_id)
    values (d.id, to_char(dnes, 'YYYY-MM'), round(p_castka, 2), p_splatnost, dnes, 'jednorazova', btrim(p_nazev), fin_cislo(s, 'PR'), p_akce) returning id into pid;
    insert into predpis_polozky values (pid, 1, p_druh, btrim(p_nazev), 1, round(p_castka, 2), round(p_castka, 2));
    perform fin_zauctuj_predpis(pid, dnes);
    perform fin_vyrovnej(d.id);
    n := n + 1;
  end loop;
  return n;
end $$;

-- ---------------------------------------------------------------- storno předpisu
create or replace function storno_predpisu(p_predpis uuid, p_duvod text) returns void
language plpgsql security definer set search_path = public as $$
declare s uuid := fin_skola(); p predpisy; d deti;
begin
  select x.* into p from predpisy x join deti y on y.id = x.dite_id where x.id = p_predpis and y.skola_id = s;
  if not found then raise exception 'Předpis nenalezen.'; end if;
  if p.storno is not null then raise exception 'Předpis už je stornovaný.'; end if;
  if coalesce(btrim(p_duvod), '') = '' then raise exception 'Napište důvod storna.'; end if;
  if exists (select 1 from fin_vyuctovani v join predpis_polozky q on q.predpis_id = p_predpis and q.druh = 'stravne_zaloha'
              where v.dite_id = p.dite_id and v.od <= (to_date(p.obdobi || '-01', 'YYYY-MM-DD') + interval '1 month' - interval '1 day')::date
                and v.do_dne >= to_date(p.obdobi || '-01', 'YYYY-MM-DD')) then
    raise exception 'Záloha z tohoto předpisu už je ve vyúčtování stravného — místo storna vystavte opravu (jednorázovou platbu nebo vratku).';
  end if;
  if p.druh = 'vyuctovani' then raise exception 'Doplatek z vyúčtování se nestornuje — případně vraťte přeplatek.'; end if;
  perform fin_otevreno(s, to_char(dnes_praha(), 'YYYY-MM'));
  select * into d from deti where id = p.dite_id;
  insert into ucetni_pohyby (skola_id, datum, md, dal, castka, popis, doklad, druh)
  select s, dnes_praha(), 'vynosy:' || case when q.druh in ('stravne_zaloha', 'stravne_vyuctovani') then 'stravne' else q.druh end, 'dite:' || d.id, q.castka,
         'Storno: ' || q.popis || ' — ' || d.jmeno || ' ' || d.prijmeni, coalesce(p.cislo, p.id::text), 'storno'
    from predpis_polozky q where q.predpis_id = p_predpis and q.castka > 0;
  update predpisy set storno = now(), storno_duvod = btrim(p_duvod), stav = 'storno', uhrazeno = 0 where id = p_predpis;
  perform fin_vyrovnej(p.dite_id);
end $$;

-- ---------------------------------------------------------------- slevy a prominutí
create or replace function uloz_upravu(p_dite uuid, p_typ text, p_hodnota numeric, p_od date, p_do date, p_duvod text, p_rozhodnuti text) returns uuid
language plpgsql security definer set search_path = public as $$
declare s uuid; r uuid;
begin
  if moje_role() not in ('reditelka', 'zastupce') then raise exception 'O snížení nebo prominutí úplaty rozhoduje ředitelka.'; end if;
  s := moje_skola();
  if not exists (select 1 from deti where id = p_dite and skola_id = s) then raise exception 'Dítě do školky nepatří.'; end if;
  insert into fin_upravy (skola_id, dite_id, typ, hodnota, plati_od, plati_do, duvod, rozhodnuti)
  values (s, p_dite, p_typ, coalesce(p_hodnota, 0), p_od, p_do, btrim(p_duvod), coalesce(btrim(p_rozhodnuti), '')) returning id into r;
  return r;
end $$;
create or replace function zrus_upravu(p_id uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  if moje_role() not in ('reditelka', 'zastupce') then raise exception 'O snížení nebo prominutí úplaty rozhoduje ředitelka.'; end if;
  update fin_upravy set zruseno = now() where id = p_id and skola_id = moje_skola() and zruseno is null;
  if not found then raise exception 'Úprava nenalezena.'; end if;
end $$;

-- ---------------------------------------------------------------- vyúčtování stravného (režim zálohy)
-- Řádky vyúčtování za období: zálohy předepsané v měsících období × skutečně odebrané obědy.
create or replace function nahled_vyuctovani(p_od date, p_do date)
returns table (dite_id uuid, jmeno text, zalohy numeric, obedy int, skutecnost numeric, rozdil numeric, uz boolean)
language plpgsql stable security definer set search_path = public as $$
declare s uuid := fin_skola(); nf financni_nastaveni;
begin
  if p_od is null or p_do is null or p_do < p_od then raise exception 'Neplatné období.'; end if;
  if p_do > dnes_praha() then raise exception 'Vyúčtovat jde jen dny, které už proběhly.'; end if;
  select * into nf from financni_nastaveni where skola_id = s;
  return query
  with z as (
    select p.dite_id, sum(q.castka) as zal from predpisy p join predpis_polozky q on q.predpis_id = p.id
     where p.storno is null and q.druh = 'stravne_zaloha' and to_date(p.obdobi || '-01', 'YYYY-MM-DD') between date_trunc('month', p_od)::date and p_do
     group by p.dite_id
  ), o as (
    select y.dite_id, count(*)::int as n, sum(sz.cena) as kc from dochazka y join deti dd on dd.id = y.dite_id
      join sazby_stravneho sz on sz.skola_id = s and sz.kategorie = fin_kat(dd.datum_narozeni, y.den)
     where dd.skola_id = s and y.den between p_od and p_do and y.strava_prihlasena
       and not (y.omluva_zadana is not null and (y.omluva_zadana at time zone 'Europe/Prague') <= ((y.den - nf.omluva_dni_predem) + nf.omluva_do))
       -- jen měsíce placené zálohou (měsíce účtované „podle skutečnosti“ už jsou zaplacené)
       and exists (select 1 from predpisy pp join predpis_polozky qq on qq.predpis_id = pp.id
                    where pp.dite_id = y.dite_id and pp.storno is null and qq.druh = 'stravne_zaloha' and pp.obdobi = to_char(y.den, 'YYYY-MM'))
     group by y.dite_id
  )
  select d.id, d.jmeno || ' ' || d.prijmeni, coalesce(z.zal, 0)::numeric, coalesce(o.n, 0), coalesce(o.kc, 0)::numeric, (coalesce(o.kc, 0) - coalesce(z.zal, 0))::numeric,
         exists (select 1 from fin_vyuctovani v where v.dite_id = d.id and v.od <= p_do and v.do_dne >= p_od)
    from deti d left join z on z.dite_id = d.id left join o on o.dite_id = d.id
   where d.skola_id = s and (z.zal is not null or o.n is not null)
   order by d.prijmeni, d.jmeno;
end $$;

create or replace function vyuctuj_stravne(p_od date, p_do date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s uuid := fin_skola(); r record; pid uuid; n int := 0; dopl numeric := 0; prepl numeric := 0; dnes date := dnes_praha(); dd deti; c text;
begin
  perform fin_otevreno(s, to_char(dnes, 'YYYY-MM'));
  perform pg_advisory_xact_lock(hashtext('vyuctovani:' || s));
  for r in select * from nahled_vyuctovani(p_od, p_do) where not uz loop
    select * into dd from deti where id = r.dite_id;
    pid := null; c := fin_cislo(s, 'VY');
    if r.rozdil > 0 then
      insert into predpisy (dite_id, obdobi, castka, splatnost, vystaveno, druh, nazev, cislo)
      values (r.dite_id, to_char(dnes, 'YYYY-MM'), r.rozdil, dnes + 14, dnes, 'vyuctovani', 'Vyúčtování stravného ' || to_char(p_od, 'FMDD. FMMM.') || '–' || to_char(p_do, 'FMDD. FMMM. YYYY'), c)
      returning id into pid;
      insert into predpis_polozky values (pid, 1, 'stravne_vyuctovani', 'Doplatek stravného (' || r.obedy || ' obědů, zálohy ' || r.zalohy || ' Kč)', 1, r.rozdil, r.rozdil);
      perform fin_zauctuj_predpis(pid, dnes);
      dopl := dopl + r.rozdil;
    elsif r.rozdil < 0 then
      insert into ucetni_pohyby (skola_id, datum, md, dal, castka, popis, doklad, druh)
      values (s, dnes, 'vynosy:stravne', 'dite:' || r.dite_id, -r.rozdil, 'Vyúčtování stravného — přeplatek záloh — ' || dd.jmeno || ' ' || dd.prijmeni, c, 'dobropis');
      prepl := prepl - r.rozdil;
    end if;
    insert into fin_vyuctovani (skola_id, dite_id, od, do_dne, zalohy, obedy, skutecnost, rozdil, predpis_id, cislo)
    values (s, r.dite_id, p_od, p_do, r.zalohy, r.obedy, r.skutecnost, r.rozdil, pid, c);
    perform fin_vyrovnej(r.dite_id);
    n := n + 1;
  end loop;
  return jsonb_build_object('deti', n, 'doplatky', dopl, 'preplatky', prepl);
end $$;

-- ---------------------------------------------------------------- pokladna
create or replace function pokladna_zustatek(p_skola uuid) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce((select pokladna_pocatek from financni_nastaveni where skola_id = p_skola), 0)
       + coalesce((select sum(case when druh = 'prijem' then castka else -castka end) from pokladna where skola_id = p_skola), 0)
$$;

-- Příjem hotovosti od rodiče (platba se spáruje s dítětem jako bankovní).
create or replace function pokladna_prijem(p_dite uuid, p_castka numeric, p_datum date, p_ucel text, p_osoba text) returns text
language plpgsql security definer set search_path = public as $$
declare s uuid := fin_skola(); c text; pl uuid; pk uuid; d deti;
begin
  if p_castka is null or p_castka <= 0 or p_castka > 100000 then raise exception 'Neplatná částka.'; end if;
  if p_datum is null or p_datum > dnes_praha() then raise exception 'Neplatné datum.'; end if;
  perform fin_otevreno(s, to_char(p_datum, 'YYYY-MM'));
  select * into d from deti where id = p_dite and skola_id = s;
  if not found then raise exception 'Dítě do školky nepatří.'; end if;
  c := fin_cislo(s, 'PPD', p_datum);
  insert into platby (skola_id, datum, castka, vs, protiucet, nazev, zdroj, doklad) values (s, p_datum, round(p_castka, 2), coalesce(d.variabilni_symbol, ''), '', left(coalesce(btrim(p_osoba), ''), 60), 'pokladna', c)
  returning id into pl;
  insert into pokladna (skola_id, cislo, datum, druh, castka, dite_id, ucel, osoba, platba_id) values (s, c, p_datum, 'prijem', round(p_castka, 2), p_dite, coalesce(nullif(btrim(p_ucel), ''), 'Platba za školku'), coalesce(btrim(p_osoba), ''), pl)
  returning id into pk;
  perform fin_pripis(pl, p_dite);
  return c;
end $$;

-- Výdej z pokladny (ne vratka dítěti — ta jde přes vrat_preplatek).
create or replace function pokladna_vydej(p_castka numeric, p_datum date, p_ucel text, p_osoba text) returns text
language plpgsql security definer set search_path = public as $$
declare s uuid := fin_skola(); c text;
begin
  if p_castka is null or p_castka <= 0 then raise exception 'Neplatná částka.'; end if;
  if p_datum is null or p_datum > dnes_praha() then raise exception 'Neplatné datum.'; end if;
  if coalesce(btrim(p_ucel), '') = '' then raise exception 'Napište účel výdeje.'; end if;
  perform fin_otevreno(s, to_char(p_datum, 'YYYY-MM'));
  perform pg_advisory_xact_lock(hashtext('pokladna:' || s));
  if pokladna_zustatek(s) < p_castka then raise exception 'V pokladně není dost peněz (zůstatek % Kč).', pokladna_zustatek(s); end if;
  c := fin_cislo(s, 'VPD', p_datum);
  insert into pokladna (skola_id, cislo, datum, druh, castka, ucel, osoba) values (s, c, p_datum, 'vydej', round(p_castka, 2), btrim(p_ucel), coalesce(btrim(p_osoba), ''));
  insert into ucetni_pohyby (skola_id, datum, md, dal, castka, popis, doklad, druh) values (s, p_datum, 'ostatni:vydaje', 'pokladna', round(p_castka, 2), btrim(p_ucel), c, 'pokladna');
  return c;
end $$;

-- ---------------------------------------------------------------- vratky přeplatků
create or replace function vrat_preplatek(p_dite uuid, p_castka numeric, p_zpusob text, p_ucet text) returns text
language plpgsql security definer set search_path = public as $$
declare s uuid := fin_skola(); d deti; saldo numeric; c text; pk uuid := null; cp text; dnes date := dnes_praha();
begin
  select * into d from deti where id = p_dite and skola_id = s;
  if not found then raise exception 'Dítě do školky nepatří.'; end if;
  if p_zpusob not in ('banka', 'pokladna') then raise exception 'Neznámý způsob vrácení.'; end if;
  perform fin_otevreno(s, to_char(dnes, 'YYYY-MM'));
  perform pg_advisory_xact_lock(hashtext('pokladna:' || s));
  select coalesce((select k.saldo from konta k where k.dite_id = p_dite), 0) into saldo;
  if p_castka is null or p_castka <= 0 or p_castka > saldo then raise exception 'Vrátit jde nejvýš přeplatek % Kč.', greatest(saldo, 0); end if;
  if p_zpusob = 'banka' and cz_iban(p_ucet) is null then raise exception 'Číslo účtu pro vrácení nesedí.'; end if;
  c := fin_cislo(s, 'VR');
  if p_zpusob = 'pokladna' then
    if pokladna_zustatek(s) < p_castka then raise exception 'V pokladně není dost peněz (zůstatek % Kč).', pokladna_zustatek(s); end if;
    cp := fin_cislo(s, 'VPD');
    insert into pokladna (skola_id, cislo, datum, druh, castka, dite_id, ucel, osoba) values (s, cp, dnes, 'vydej', round(p_castka, 2), p_dite, 'Vrácení přeplatku ' || c, '') returning id into pk;
  end if;
  insert into fin_vratky (skola_id, dite_id, castka, zpusob, ucet, cislo, stav, odeslano, pokladna_id)
  values (s, p_dite, round(p_castka, 2), p_zpusob, coalesce(btrim(p_ucet), ''), c, case when p_zpusob = 'pokladna' then 'odeslano' else 'pripraveno' end, case when p_zpusob = 'pokladna' then now() end, pk);
  insert into ucetni_pohyby (skola_id, datum, md, dal, castka, popis, doklad, druh)
  values (s, dnes, 'dite:' || p_dite, case when p_zpusob = 'pokladna' then 'pokladna' else 'banka' end, round(p_castka, 2), 'Vrácení přeplatku — ' || d.jmeno || ' ' || d.prijmeni, coalesce(cp, c), 'vratka');
  perform fin_vyrovnej(p_dite);
  return c;
end $$;

create or replace function vratky_odeslany(p_ids uuid[]) returns int
language plpgsql security definer set search_path = public as $$
declare s uuid := fin_skola(); n int;
begin
  update fin_vratky set stav = 'odeslano', odeslano = now() where id = any(p_ids) and skola_id = s and stav = 'pripraveno';
  get diagnostics n = row_count;
  return n;
end $$;

-- ---------------------------------------------------------------- uzávěrka
create or replace function uzavri_obdobi(p_obdobi text) returns void
language plpgsql security definer set search_path = public as $$
declare s uuid := fin_skola();
begin
  if p_obdobi !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then raise exception 'Neplatné období.'; end if;
  if to_date(p_obdobi || '-01', 'YYYY-MM-DD') + interval '1 month' > dnes_praha() then raise exception 'Uzavřít jde jen skončený měsíc.'; end if;
  if exists (select 1 from fin_uzaverky where skola_id = s and obdobi = p_obdobi) then raise exception 'Měsíc už je uzavřený.'; end if;
  if exists (select 1 from fin_uzaverky where skola_id = s)
     and not exists (select 1 from fin_uzaverky where skola_id = s and obdobi = to_char(to_date(p_obdobi || '-01', 'YYYY-MM-DD') - interval '1 month', 'YYYY-MM'))
     and not exists (select 1 from fin_uzaverky where skola_id = s and obdobi > p_obdobi) then
    raise exception 'Uzavírá se postupně — nejdřív uzavřete předchozí měsíc.';
  end if;
  if exists (select 1 from fin_uzaverky where skola_id = s and obdobi > p_obdobi) then raise exception 'Pozdější měsíc už je uzavřený.'; end if;
  insert into fin_uzaverky (skola_id, obdobi) values (s, p_obdobi);
end $$;

create or replace function otevri_obdobi(p_obdobi text) returns void
language plpgsql security definer set search_path = public as $$
declare s uuid;
begin
  if moje_role() not in ('reditelka', 'zastupce') then raise exception 'Uzávěrku otevírá jen vedení školy.'; end if;
  s := moje_skola();
  if exists (select 1 from fin_uzaverky where skola_id = s and obdobi > p_obdobi) then raise exception 'Otevřít jde jen poslední uzavřený měsíc.'; end if;
  delete from fin_uzaverky where skola_id = s and obdobi = p_obdobi;
  if not found then raise exception 'Měsíc není uzavřený.'; end if;
end $$;

-- ---------------------------------------------------------------- aplikace rodiče
drop function if exists moje_platby();
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
           (select min(p.splatnost) from predpisy p where p.dite_id = m.id and p.storno is null and p.stav <> 'zaplaceno') as spl,
           (select string_agg(coalesce(nullif(p.nazev, ''), p.obdobi), ', ' order by p.splatnost) from predpisy p where p.dite_id = m.id and p.storno is null and p.stav <> 'zaplaceno') as zaco
      from moje m join skoly s on s.id = m.skola_id
      left join konta k on k.dite_id = m.id
      left join financni_nastaveni f on f.skola_id = m.skola_id
  )
  select x.id, x.jmeno, x.dluh, x.kredit, x.spl, coalesce(x.spl < dnes_praha(), false), nullif(x.vs, ''), x.ucet, x.iban, x.skola,
         spayd_text(coalesce(x.zaco, '') || ' ' || x.jmeno, 60),
         case when x.dluh > 0 and x.iban is not null and x.vs <> '' then
           'SPD*1.0*ACC:' || x.iban || '*AM:' || to_char(x.dluh, 'FM9999990.00') || '*CC:CZK*X-VS:' || x.vs
           || '*RN:' || spayd_text(x.skola, 35) || '*MSG:' || spayd_text(coalesce(x.zaco, '') || ' ' || x.jmeno, 60)
           || case when x.spl >= dnes_praha() then '*DT:' || to_char(x.spl, 'YYYYMMDD') else '' end
         end,
         coalesce((select jsonb_agg(jsonb_build_object('obdobi', p.obdobi, 'nazev', p.nazev, 'druh', p.druh, 'cislo', p.cislo, 'castka', p.castka, 'uhrazeno', p.uhrazeno, 'stav', p.stav, 'splatnost', p.splatnost,
                     'polozky', (select jsonb_agg(jsonb_build_object('popis', q.popis, 'mnozstvi', q.mnozstvi, 'castka', q.castka) order by q.poradi) from predpis_polozky q where q.predpis_id = p.id))
                     order by p.splatnost desc)
                     from (select * from predpisy where dite_id = x.id and storno is null order by splatnost desc limit 24) p), '[]'::jsonb)
    from x order by x.jmeno
$$;

-- ---------------------------------------------------------------- práva na funkce
revoke execute on function uloz_financni_rezim(text, numeric, numeric, jsonb, numeric), vystav_predpisy(text), nova_hromadna_platba(text, text, numeric, date, uuid[], uuid),
  storno_predpisu(uuid, text), uloz_upravu(uuid, text, numeric, date, date, text, text), zrus_upravu(uuid), nahled_vyuctovani(date, date), vyuctuj_stravne(date, date),
  pokladna_zustatek(uuid), pokladna_prijem(uuid, numeric, date, text, text), pokladna_vydej(numeric, date, text, text), vrat_preplatek(uuid, numeric, text, text),
  vratky_odeslany(uuid[]), uzavri_obdobi(text), otevri_obdobi(text), moje_platby(), fin_kat(date, date), fin_pracovni_dny(date, date) from anon, public;
grant execute on function uloz_financni_rezim(text, numeric, numeric, jsonb, numeric), vystav_predpisy(text), nova_hromadna_platba(text, text, numeric, date, uuid[], uuid),
  storno_predpisu(uuid, text), uloz_upravu(uuid, text, numeric, date, date, text, text), zrus_upravu(uuid), nahled_vyuctovani(date, date), vyuctuj_stravne(date, date),
  pokladna_prijem(uuid, numeric, date, text, text), pokladna_vydej(numeric, date, text, text), vrat_preplatek(uuid, numeric, text, text),
  vratky_odeslany(uuid[]), uzavri_obdobi(text), otevri_obdobi(text), moje_platby(), fin_kat(date, date), fin_pracovni_dny(date, date) to authenticated;
