-- =============================================================================
-- Školka — doplněk 22. 10. 2026: ZDRAVÍ DÍTĚTE — léky ve školce a kniha podání.
-- Spusťte v Supabase → SQL Editor po migraci 2026-10-21-finance. Jde spustit opakovaně.
--
--   leky_ve_skolce   léky, které rodič v LifeOS sám poslal školce (přepínač
--                    „Podávat ve školce“) — název, dávka, časy nebo „při
--                    potížích“, pokyn, do kdy; s potvrzením dohody (jméno, čas)
--   podani_leku      kniha podání: kdo, komu, co, kdy, podáno / nepodáno + důvod;
--                    záznam nejde smazat ani přepsat (omyl jde do 15 minut
--                    označit jako zrušený, řádek zůstává)
--   zdravi_ditete    zdravotní omezení a postup při potížích od rodiče
--
-- Kdo co vidí:
--   rodič … jen své dítě (a posílá / ruší jen léky svého dítěte)
--   učitelka … děti svých tříd (i dnes přesunuté), zapisuje podání
--   ředitelka, zástupkyně … celá školka, kniha podání
--   hospodářka, kuchařka … nic (kuchyně dál jen alergeny jídel)
-- Z aplikací se tabulky jen čtou; mění se výhradně funkcemi níže.
-- =============================================================================

-- Kdo smí vidět zdraví dítěte (vždy true/false, i pro účet bez role).
create or replace function vidi_zdravi(d uuid) returns boolean language sql stable security definer set search_path = public as
  $$ select coalesce(moje_role() in ('reditelka', 'zastupce', 'ucitelka', 'rodic'), false) and moje_dite(d) $$;

-- ---------------------------------------------------------------- tabulky
create table if not exists leky_ve_skolce (
  id uuid primary key default gen_random_uuid(),
  skola_id uuid not null references skoly on delete cascade,
  dite_id uuid not null references deti on delete cascade,
  klic text not null check (length(klic) between 1 and 64),            -- id léku v LifeOS (posílá se znovu při úpravě)
  nazev text not null check (length(btrim(nazev)) between 1 and 80),
  davka text check (davka is null or length(davka) <= 60),
  casy time[] not null default '{}' check (cardinality(casy) <= 6),    -- kdy ve školce; prázdné = jen při potížích
  pri_potizich boolean not null default false,
  pokyn text check (pokyn is null or length(pokyn) <= 500),           -- co dělat při potížích
  do_dne date,                                                         -- konec léčby (null = bez konce)
  ulozeni text check (ulozeni is null or length(ulozeni) <= 80),      -- kde lék ve školce je (vyplní školka)
  souhlas_jmeno text not null check (length(btrim(souhlas_jmeno)) between 1 and 80),
  souhlas_kdy timestamptz not null default now(),
  zmeneno timestamptz not null default now(),
  unique (dite_id, klic),
  check (cardinality(casy) > 0 or pri_potizich)
);
create index if not exists leky_ve_skolce_skola on leky_ve_skolce (skola_id);

create table if not exists podani_leku (
  id uuid primary key default gen_random_uuid(),
  skola_id uuid not null references skoly on delete cascade,
  dite_id uuid not null references deti on delete cascade,
  lek_id uuid references leky_ve_skolce on delete set null,            -- lék může rodič později vypnout; záznam zůstává
  nazev text not null,
  davka text,
  den date not null default (now() at time zone 'Europe/Prague')::date,
  planovano time,                                                       -- čas z rozpisu; null = podáno při potížích
  stav text not null check (stav in ('podano', 'nepodano')),
  duvod text check (duvod in ('odmitlo', 'neni', 'chybi')),
  poznamka text check (poznamka is null or length(poznamka) <= 300),
  cas timestamptz not null default now(),
  zapsal uuid default auth.uid(),
  zapsal_jmeno text,
  zruseno timestamptz,
  check ((stav = 'nepodano') = (duvod is not null))
);
create index if not exists podani_leku_dite on podani_leku (dite_id, den);
create index if not exists podani_leku_skola on podani_leku (skola_id, den);
-- Jedno platné podání pro lék a čas z rozpisu (dva tablety neklepnou dvakrát).
create unique index if not exists podani_leku_jednou on podani_leku (lek_id, den, planovano) where planovano is not null and zruseno is null;

create table if not exists zdravi_ditete (
  dite_id uuid primary key references deti on delete cascade,
  skola_id uuid not null references skoly on delete cascade,
  omezeni text check (omezeni is null or length(omezeni) <= 300),      -- „bez sportu do 30. 10.“
  postup text check (postup is null or length(postup) <= 500),         -- „při otoku rtů podat Epipen a volat 155“
  zmeneno timestamptz not null default now()
);

alter table leky_ve_skolce enable row level security;
alter table podani_leku enable row level security;
alter table zdravi_ditete enable row level security;
drop policy if exists lvs_cist on leky_ve_skolce;
create policy lvs_cist on leky_ve_skolce for select using (vidi_zdravi(dite_id));
drop policy if exists pl_cist on podani_leku;
create policy pl_cist on podani_leku for select using (vidi_zdravi(dite_id));
drop policy if exists zd_cist on zdravi_ditete;
create policy zd_cist on zdravi_ditete for select using (vidi_zdravi(dite_id));
-- Žádné zásady pro zápis: mění se jen funkcemi (security definer) níže.
revoke insert, update, delete, truncate on leky_ve_skolce, podani_leku, zdravi_ditete from authenticated, anon;

drop trigger if exists a_leky_ve_skolce on leky_ve_skolce;
create trigger a_leky_ve_skolce after insert or update or delete on leky_ve_skolce for each row execute function zapis_audit();
drop trigger if exists a_podani_leku on podani_leku;
create trigger a_podani_leku after insert or update or delete on podani_leku for each row execute function zapis_audit();
drop trigger if exists a_zdravi_ditete on zdravi_ditete;
create trigger a_zdravi_ditete after insert or update or delete on zdravi_ditete for each row execute function zapis_audit();

-- ---------------------------------------------------------------- rodič (LifeOS)
-- Pošle (nebo upraví) lék, který má školka podávat. p_souhlas = jméno rodiče,
-- který dohodu potvrdil; bez něj školka lék nepřijme. Při změně názvu, dávky,
-- časů nebo pokynu se čas dohody obnoví.
create or replace function posli_lek_skolce(p_dite uuid, p_klic text, p_nazev text, p_davka text, p_casy time[],
  p_pri_potizich boolean, p_pokyn text, p_do date, p_souhlas text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_skola uuid; v_casy time[];
begin
  if not (coalesce(moje_role() = 'rodic', false) and moje_dite(p_dite)) then raise exception 'Léky tohoto dítěte posílat nemůžete.'; end if;
  if nullif(btrim(coalesce(p_souhlas, '')), '') is null then raise exception 'Chybí potvrzení dohody se školkou.'; end if;
  select skola_id into v_skola from deti where id = p_dite and ukonceno is null;
  if v_skola is null then raise exception 'Dítě už školku nenavštěvuje.'; end if;
  select coalesce(array_agg(distinct date_trunc('minute', c::interval)::time order by date_trunc('minute', c::interval)::time), '{}')
    into v_casy from unnest(coalesce(p_casy, '{}')) c;
  if (select count(*) from leky_ve_skolce where dite_id = p_dite and klic <> p_klic) >= 10 then raise exception 'Školce lze poslat nejvýš 10 léků.'; end if;
  insert into leky_ve_skolce as l (skola_id, dite_id, klic, nazev, davka, casy, pri_potizich, pokyn, do_dne, souhlas_jmeno)
  values (v_skola, p_dite, p_klic, btrim(p_nazev), nullif(btrim(coalesce(p_davka, '')), ''), v_casy, coalesce(p_pri_potizich, false),
          nullif(btrim(coalesce(p_pokyn, '')), ''), p_do, btrim(p_souhlas))
  on conflict (dite_id, klic) do update set
    nazev = excluded.nazev, davka = excluded.davka, casy = excluded.casy, pri_potizich = excluded.pri_potizich,
    pokyn = excluded.pokyn, do_dne = excluded.do_dne, souhlas_jmeno = excluded.souhlas_jmeno, zmeneno = now(),
    souhlas_kdy = case when (l.nazev, l.davka, l.casy, l.pri_potizich, l.pokyn, l.do_dne)
                         is distinct from (excluded.nazev, excluded.davka, excluded.casy, excluded.pri_potizich, excluded.pokyn, excluded.do_dne)
                       then now() else l.souhlas_kdy end
  returning id into v_id;
  return v_id;
end $$;

-- Vypnutí přepínače: lék ze školky zmizí (kniha podání zůstane).
create or replace function zrus_lek_ve_skolce(p_dite uuid, p_klic text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (coalesce(moje_role() = 'rodic', false) and moje_dite(p_dite)) then raise exception 'Léky tohoto dítěte měnit nemůžete.'; end if;
  delete from leky_ve_skolce where dite_id = p_dite and klic = p_klic;
end $$;

-- Omezení a postup při potížích. null = nechat, '' = smazat.
create or replace function uprav_zdravi_rodicem(p_dite uuid, p_omezeni text default null, p_postup text default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_skola uuid;
begin
  if not (coalesce(moje_role() = 'rodic', false) and moje_dite(p_dite)) then raise exception 'Údaje tohoto dítěte měnit nemůžete.'; end if;
  select skola_id into v_skola from deti where id = p_dite;
  insert into zdravi_ditete as z (dite_id, skola_id, omezeni, postup)
  values (p_dite, v_skola, nullif(btrim(coalesce(p_omezeni, '')), ''), nullif(btrim(coalesce(p_postup, '')), ''))
  on conflict (dite_id) do update set
    omezeni = case when p_omezeni is null then z.omezeni else nullif(btrim(p_omezeni), '') end,
    postup = case when p_postup is null then z.postup else nullif(btrim(p_postup), '') end,
    zmeneno = now();
  delete from zdravi_ditete where dite_id = p_dite and omezeni is null and postup is null;
end $$;

-- ---------------------------------------------------------------- školka (tablet, ředitelna)
-- Podání nebo nepodání léku. p_planovano = čas z rozpisu; bez něj jde jen o lék „při potížích“.
create or replace function zapis_podani(p_lek uuid, p_stav text, p_duvod text default null, p_poznamka text default null, p_planovano time default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare l leky_ve_skolce; v_id uuid;
begin
  select * into l from leky_ve_skolce where id = p_lek;
  if l.id is null or not (coalesce(moje_role() in ('reditelka', 'zastupce', 'ucitelka'), false) and moje_dite(l.dite_id)) then
    raise exception 'Podání tohoto léku zapsat nemůžete.';
  end if;
  if l.do_dne is not null and l.do_dne < dnes_praha() then raise exception 'Podávání tohoto léku už skončilo.'; end if;
  if p_planovano is null and not l.pri_potizich then raise exception 'Tento lék se podává jen v časy z rozpisu.'; end if;
  if p_planovano is not null and not (p_planovano = any (l.casy)) then raise exception 'Takový čas lék v rozpisu nemá.'; end if;
  if p_planovano is not null and exists (select 1 from podani_leku where lek_id = l.id and den = dnes_praha() and planovano = p_planovano and zruseno is null) then
    raise exception 'Tohle podání už někdo zapsal.';
  end if;
  insert into podani_leku (skola_id, dite_id, lek_id, nazev, davka, den, planovano, stav, duvod, poznamka, zapsal_jmeno)
  values (l.skola_id, l.dite_id, l.id, l.nazev, l.davka, dnes_praha(), p_planovano, p_stav,
          case when p_stav = 'nepodano' then p_duvod end, nullif(btrim(coalesce(p_poznamka, '')), ''),
          (select jmeno from uzivatele where id = auth.uid()))
  returning id into v_id;
  return v_id;
end $$;

-- Omyl: kdo zapsal, může do 15 minut záznam zrušit (zůstane v knize jako zrušený).
create or replace function zrus_podani(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update podani_leku set zruseno = now()
   where id = p_id and zapsal = auth.uid() and zruseno is null and cas > now() - interval '15 minutes'
     and coalesce(moje_role() in ('reditelka', 'zastupce', 'ucitelka'), false);
  if not found then raise exception 'Záznam už zrušit nejde (jen vlastní a do 15 minut).'; end if;
end $$;

-- Kde lék ve školce je (skříňka ve třídě, lednice v kuchyni).
create or replace function uloz_ulozeni_leku(p_lek uuid, p_ulozeni text) returns void
language plpgsql security definer set search_path = public as $$
declare v_dite uuid;
begin
  select dite_id into v_dite from leky_ve_skolce where id = p_lek;
  if v_dite is null or not (coalesce(moje_role() in ('reditelka', 'zastupce', 'ucitelka'), false) and moje_dite(v_dite)) then
    raise exception 'Tento lék upravit nemůžete.';
  end if;
  update leky_ve_skolce set ulozeni = nullif(btrim(coalesce(p_ulozeni, '')), '') where id = p_lek;
end $$;

revoke execute on function vidi_zdravi(uuid), posli_lek_skolce(uuid, text, text, text, time[], boolean, text, date, text),
  zrus_lek_ve_skolce(uuid, text), uprav_zdravi_rodicem(uuid, text, text), zapis_podani(uuid, text, text, text, time),
  zrus_podani(uuid), uloz_ulozeni_leku(uuid, text) from public, anon;
grant execute on function vidi_zdravi(uuid), posli_lek_skolce(uuid, text, text, text, time[], boolean, text, date, text),
  zrus_lek_ve_skolce(uuid, text), uprav_zdravi_rodicem(uuid, text, text), zapis_podani(uuid, text, text, text, time),
  zrus_podani(uuid), uloz_ulozeni_leku(uuid, text) to authenticated;
grant select on leky_ve_skolce, podani_leku, zdravi_ditete to authenticated;

-- Druhý tablet ve třídě uvidí podání hned (realtime).
do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'podani_leku') then
      alter publication supabase_realtime add table podani_leku;
    end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'leky_ve_skolce') then
      alter publication supabase_realtime add table leky_ve_skolce;
    end if;
  end if;
end $$;
