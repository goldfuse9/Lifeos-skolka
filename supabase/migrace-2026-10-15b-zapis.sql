-- =============================================================================
-- Školka — doplněk 15. 10. 2026 (b): ZÁPIS (přijímací řízení) na serveru.
-- Spusťte v Supabase → SQL Editor po migraci 2026-10-15-porady. Jde spustit opakovaně.
--
-- zadosti         žádosti o přijetí (jen vedení — obsahují rodné číslo)
-- zapis_rocnik    stav zápisu pro školní rok: rozhodnuto → zveřejněno →
--                 rozhodnutí odeslána → přijatí převedeni do kartotéky
-- Aplikace sama nic nezveřejňuje ani neodesílá: „zveřejněno“ a „odesláno“
-- jen zaznamenávají, že to vedení udělalo (na dveřích, datovou schránkou…).
-- =============================================================================

alter table zadosti add column if not exists prijmeni text;
alter table zadosti add column if not exists pohlavi char(1);
alter table zadosti add column if not exists email text;
alter table zadosti add column if not exists dite_id uuid references deti on delete set null;
alter table zadosti add column if not exists vytvoreno timestamptz default now();
alter table zadosti drop constraint if exists zadosti_hodnoty;
alter table zadosti add constraint zadosti_hodnoty check (
  (vysledek is null or vysledek in ('prijato', 'neprijato'))
  and (pohlavi is null or pohlavi in ('M', 'F'))
  and length(btrim(jmeno)) between 1 and 80 and length(coalesce(prijmeni, '')) <= 80
  and length(coalesce(email, '')) <= 200
) not valid;

create table if not exists zapis_rocnik (
  skola_id uuid not null references skoly on delete cascade,
  rok int not null,
  rozhodnuto date, zverejneno date, odeslano date, preneseno date,
  primary key (skola_id, rok)
);
alter table zapis_rocnik enable row level security;
drop policy if exists zapis_rocnik_cist on zapis_rocnik;
create policy zapis_rocnik_cist on zapis_rocnik for select using (je_vedeni() and skola_id = moje_skola());
-- stav se mění jen funkcemi níže (hlídají pořadí kroků)
revoke insert, update, delete, truncate on zapis_rocnik from authenticated, anon;
grant select on zapis_rocnik to authenticated;

-- žádost: číst a měnit výsledek smí vedení; zakládá se funkcí nova_zadost (registrační číslo)
drop policy if exists zapis on zadosti;
drop policy if exists zadosti_cist on zadosti;
create policy zadosti_cist on zadosti for select using (je_vedeni() and skola_id = moje_skola());
drop policy if exists zadosti_menit on zadosti;
create policy zadosti_menit on zadosti for update using (je_vedeni() and skola_id = moje_skola()) with check (je_vedeni() and skola_id = moje_skola());
revoke insert, update, delete, truncate on zadosti from authenticated, anon;
grant select on zadosti to authenticated;
grant update (vysledek) on zadosti to authenticated;

-- výsledek jde měnit jen po rozhodnutí a před odesláním rozhodnutí
create or replace function hlidej_zadost() returns trigger language plpgsql security definer set search_path = public as $$
declare r zapis_rocnik;
begin
  if new.vysledek is distinct from old.vysledek then
    select * into r from zapis_rocnik where skola_id = new.skola_id and rok = new.rok;
    if r.rozhodnuto is null then raise exception 'Nejdřív rozhodněte podle kritérií.'; end if;
    if r.odeslano is not null then raise exception 'Rozhodnutí už byla odeslána — výsledek nejde změnit.'; end if;
  end if;
  return new;
end $$;
drop trigger if exists b_hlidej_zadost on zadosti;
create trigger b_hlidej_zadost before update on zadosti for each row execute function hlidej_zadost();

-- nová žádost: přidělí další registrační číslo v roce (Z001, Z002, …)
create or replace function nova_zadost(p_rok int, p_jmeno text, p_prijmeni text, p_rc text, p_narozeni date,
  p_pohlavi text, p_spadovy boolean, p_sourozenec boolean, p_email text)
returns table (id uuid, reg_cislo text, vysledek text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare s uuid := moje_skola(); n int; reg text; r zapis_rocnik; nid uuid; vys text;
begin
  if not je_vedeni() then raise exception 'Žádosti zapisuje vedení školy.'; end if;
  if p_rok is null or p_rok < 2000 or p_rok > 2100 then raise exception 'Neplatný rok zápisu.'; end if;
  if coalesce(btrim(p_jmeno), '') = '' or coalesce(btrim(p_prijmeni), '') = '' then raise exception 'Vyplňte jméno a příjmení dítěte.'; end if;
  if coalesce(btrim(p_rc), '') = '' or p_narozeni is null then raise exception 'Vyplňte rodné číslo.'; end if;
  if exists (select 1 from zadosti z where z.skola_id = s and z.rok = p_rok and replace(z.rodne_cislo, '/', '') = replace(btrim(p_rc), '/', '')) then
    raise exception 'Žádost s tímto rodným číslem už je zapsaná.';
  end if;
  perform pg_advisory_xact_lock(hashtext('zapis:' || s::text || ':' || p_rok));
  select * into r from zapis_rocnik where skola_id = s and rok = p_rok;
  if r.odeslano is not null then raise exception 'Rozhodnutí už byla odeslána — novou žádost zapište do dalšího řízení.'; end if;
  select coalesce(max(nullif(regexp_replace(z.reg_cislo, '\D', '', 'g'), '')::int), 0) + 1 into n from zadosti z where z.skola_id = s and z.rok = p_rok;
  reg := 'Z' || lpad(n::text, 3, '0');
  vys := case when r.rozhodnuto is not null then 'neprijato' end;
  insert into zadosti (skola_id, rok, reg_cislo, jmeno, prijmeni, rodne_cislo, datum_narozeni, pohlavi, spadovy, sourozenec, email, vysledek)
  values (s, p_rok, reg, btrim(p_jmeno), btrim(p_prijmeni), btrim(p_rc), p_narozeni, nullif(p_pohlavi, ''), coalesce(p_spadovy, false), coalesce(p_sourozenec, false), nullif(btrim(coalesce(p_email, '')), ''), vys)
  returning zadosti.id into nid;
  return query select nid, reg, vys;
end $$;

-- rozhodnutí podle kritérií: výsledky a pořadí najednou
create or replace function rozhodni_zapis(p_rok int, p_vysledky jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare s uuid := moje_skola(); r zapis_rocnik; n int;
begin
  if not je_vedeni() then raise exception 'Rozhoduje vedení školy.'; end if;
  select * into r from zapis_rocnik where skola_id = s and rok = p_rok;
  if r.odeslano is not null then raise exception 'Rozhodnutí už byla odeslána.'; end if;
  insert into zapis_rocnik (skola_id, rok, rozhodnuto) values (s, p_rok, dnes_praha())
  on conflict (skola_id, rok) do update set rozhodnuto = coalesce(zapis_rocnik.rozhodnuto, excluded.rozhodnuto);
  update zadosti z set vysledek = x.vysledek, poradi = x.poradi
    from jsonb_to_recordset(coalesce(p_vysledky, '[]')) as x(id uuid, vysledek text, poradi int)
   where z.id = x.id and z.skola_id = s and z.rok = p_rok and x.vysledek in ('prijato', 'neprijato');
  get diagnostics n = row_count;
  return n;
end $$;

-- další krok řízení: jen v pořadí rozhodnuto → zveřejněno → odesláno
create or replace function zapis_krok(p_rok int, p_krok text) returns date
language plpgsql security definer set search_path = public as $$
declare s uuid := moje_skola(); r zapis_rocnik;
begin
  if not je_vedeni() then raise exception 'Zápis řídí vedení školy.'; end if;
  select * into r from zapis_rocnik where skola_id = s and rok = p_rok;
  if p_krok = 'zverejneno' then
    if r.rozhodnuto is null then raise exception 'Nejdřív rozhodněte podle kritérií.'; end if;
    update zapis_rocnik set zverejneno = coalesce(zverejneno, dnes_praha()) where skola_id = s and rok = p_rok;
  elsif p_krok = 'odeslano' then
    if r.zverejneno is null then raise exception 'Nejdřív zveřejněte seznam přijatých.'; end if;
    update zapis_rocnik set odeslano = coalesce(odeslano, dnes_praha()) where skola_id = s and rok = p_rok;
    update zadosti set rozhodnuti_odeslano = coalesce(rozhodnuti_odeslano, dnes_praha()) where skola_id = s and rok = p_rok;
  else
    raise exception 'Neznámý krok zápisu.';
  end if;
  return dnes_praha();
end $$;

-- přijaté děti do kartotéky (nástup 1. 9.); opakované spuštění nic nezdvojí
create or replace function preved_prijate(p_rok int) returns int
language plpgsql security definer set search_path = public as $$
declare s uuid := moje_skola(); r zapis_rocnik; z zadosti; nid uuid; n int := 0;
begin
  if not je_vedeni() then raise exception 'Do kartotéky převádí vedení školy.'; end if;
  select * into r from zapis_rocnik where skola_id = s and rok = p_rok;
  if r.odeslano is null then raise exception 'Nejdřív odešlete rozhodnutí.'; end if;
  for z in select * from zadosti where skola_id = s and rok = p_rok and vysledek = 'prijato' and dite_id is null order by poradi nulls last, reg_cislo loop
    select d.id into nid from deti d where d.skola_id = s and replace(coalesce(d.rodne_cislo, ''), '/', '') = replace(z.rodne_cislo, '/', '') limit 1;
    if nid is null then
      insert into deti (skola_id, jmeno, prijmeni, rodne_cislo, datum_narozeni, pohlavi, spadovy, zahajeni, kod_zahajeni)
      values (s, z.jmeno, coalesce(nullif(z.prijmeni, ''), '—'), z.rodne_cislo, z.datum_narozeni, coalesce(z.pohlavi, 'M'), coalesce(z.spadovy, false), make_date(p_rok, 9, 1), 'Nástup')
      returning id into nid;
      if z.email is not null then insert into zastupci (dite_id, jmeno, email, poradi) values (nid, 'Zákonný zástupce', z.email, 1); end if;
      n := n + 1;
    end if;
    update zadosti set dite_id = nid where id = z.id;
  end loop;
  update zapis_rocnik set preneseno = coalesce(preneseno, dnes_praha()) where skola_id = s and rok = p_rok;
  return n;
end $$;

revoke execute on function nova_zadost(int, text, text, text, date, text, boolean, boolean, text), rozhodni_zapis(int, jsonb), zapis_krok(int, text), preved_prijate(int) from anon, public;
grant execute on function nova_zadost(int, text, text, text, date, text, boolean, boolean, text), rozhodni_zapis(int, jsonb), zapis_krok(int, text), preved_prijate(int) to authenticated;
