-- =============================================================================
-- Školka — doplněk 13. 10. 2026 (c): SUPERADMIN a pozvánky
-- -----------------------------------------------------------------------------
--   • superadmin (provozovatel LifeOS) zakládá školky, zve ředitelky,
--     aktivuje/blokuje školky a vede předplatné; dětská data nevidí
--   • ředitelka zve zaměstnance (učitelky, kuchařky…) a blokuje jejich účty
--   • účet vzniká registrací s kódem pozvánky — bez tajného klíče v aplikaci
--   • blokovaná školka nebo účet = žádný přístup (vynucuje moje_role(), na
--     které stojí všechny zásady RLS)
-- Spusťte jednou v Supabase → SQL Editor. Pak na konci souboru přidejte
-- sebe jako superadmina (řádek „insert into superadmini …“).
-- =============================================================================

-- ------------------------------------------------------------- tabulky
create table if not exists superadmini (
  uzivatel_id uuid primary key references auth.users on delete cascade,
  jmeno text not null,
  vytvoreno timestamptz not null default now()
);
alter table superadmini enable row level security;   -- žádné zásady: čtou se jen přes funkce

alter table skoly add column if not exists stav text not null default 'aktivni';
do $$ begin
  alter table skoly add constraint skoly_stav check (stav in ('ceka', 'aktivni', 'blokovana'));
exception when duplicate_object then null; end $$;
alter table skoly add column if not exists tarif text not null default 'pilot';
alter table skoly add column if not exists predplatne_do date;
-- Poznámka správce je v samostatné tabulce: ředitelka čte celý řádek své
-- školky, poznámku provozovatele vidět nemá.
create table if not exists skoly_admin (
  skola_id uuid primary key references skoly on delete cascade,
  poznamka text
);
alter table skoly_admin enable row level security;   -- žádné zásady: jen přes funkce
do $$ begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'skoly' and column_name = 'poznamka_admin') then
    execute 'insert into skoly_admin (skola_id, poznamka) select id, poznamka_admin from skoly where poznamka_admin is not null on conflict do nothing';
    execute 'alter table skoly drop column poznamka_admin';
  end if;
end $$;
alter table skoly add column if not exists vytvoreno timestamptz not null default now();

alter table uzivatele add column if not exists aktivni boolean not null default true;
alter table uzivatele add column if not exists email text;
update uzivatele u set email = lower(a.email) from auth.users a where a.id = u.id and u.email is null and a.email is not null;

create table if not exists pozvanky (
  kod text primary key,                       -- 8 znaků bez 0/O/1/I (ABCD-EFGH)
  skola_id uuid not null references skoly on delete cascade,
  email text not null,
  jmeno text not null,
  role role_t not null check (role <> 'rodic'),
  trida_id uuid references tridy on delete set null,
  vytvoril uuid,
  vytvoreno timestamptz not null default now(),
  plati_do timestamptz not null default now() + interval '30 days',
  prijato timestamptz, prijal uuid,
  zruseno timestamptz
);
alter table pozvanky enable row level security;     -- čte se jen přes funkce

-- ------------------------------------------------------------- práva
create or replace function je_superadmin() returns boolean language sql stable security definer set search_path = public as
  $$ select exists (select 1 from superadmini where uzivatel_id = auth.uid()) $$;

-- Role platí, jen když je účet aktivní a školka aktivní. Na moje_role()
-- stojí všechny zásady RLS — blokace tak platí pro tablet, ředitelnu,
-- jídelnu i LifeOS najednou.
-- Pozor na NULL: účet bez role (nová registrace, blokovaný účet či školka)
-- má moje_role() = NULL. Kontroly typu „if not (moje_role() in (…) and
-- moje_dite(…))“ by s NULL neprošly jako zákaz — proto obě funkce vracejí
-- vždy true/false.
create or replace function je_vedeni() returns boolean language sql stable set search_path = public as
  $$ select coalesce(moje_role() in ('reditelka', 'zastupce'), false) $$;
create or replace function moje_dite(d uuid) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(case moje_role()
    when 'reditelka' then exists (select 1 from deti where id = d and skola_id = moje_skola())
    when 'zastupce' then exists (select 1 from deti where id = d and skola_id = moje_skola())
    when 'hospodarka' then exists (select 1 from deti where id = d and skola_id = moje_skola())
    when 'ucitelka' then exists (
      select 1 from deti x join ucitel_trida ut on ut.trida_id = x.trida_id
      where x.id = d and ut.ucitel_id = auth.uid()
      union
      select 1 from dochazka y join ucitel_trida ut on ut.trida_id = y.trida_dnes
      where y.dite_id = d and y.den = current_date and ut.ucitel_id = auth.uid())
    when 'rodic' then exists (select 1 from zastupci z where z.dite_id = d and z.uzivatel_id = auth.uid())
  end, false) $$;

create or replace function moje_role() returns role_t language sql stable security definer set search_path = public as
  $$ select u.role from uzivatele u join skoly s on s.id = u.skola_id
     where u.id = auth.uid() and u.aktivni and s.stav = 'aktivni' $$;
create or replace function moje_skola() returns uuid language sql stable security definer set search_path = public as
  $$ select u.skola_id from uzivatele u join skoly s on s.id = u.skola_id
     where u.id = auth.uid() and u.aktivni and s.stav = 'aktivni' $$;

-- Proč účet nemá přístup (pro srozumitelnou hlášku po přihlášení).
create or replace function muj_stav() returns table (role text, skola text, stav_skoly text, aktivni boolean, superadmin boolean)
language sql stable security definer set search_path = public as $$
  select u.role::text, s.nazev, s.stav, u.aktivni, je_superadmin()
  from (select auth.uid() id) me
  left join uzivatele u on u.id = me.id
  left join skoly s on s.id = u.skola_id
$$;

create or replace function novy_kod() returns text language plpgsql volatile as $$
declare abc constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; b bytea := uuid_send(gen_random_uuid()); k text := '';
begin
  for i in 0..7 loop k := k || substr(abc, get_byte(b, i) % 32 + 1, 1); end loop;
  return k;
end $$;

-- ------------------------------------------------- superadmin: školky
create or replace function admin_skoly()
returns table (id uuid, nazev text, izo text, kontakt text, stav text, tarif text, predplatne_do date, poznamka text, vytvoreno timestamptz,
               deti int, tridy int, zamestnanci int, rodice int, reditelky jsonb, pozvanky jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  if not je_superadmin() then raise exception 'Jen pro správce LifeOS.'; end if;
  return query
    select s.id, s.nazev, s.izo, s.kontakt, s.stav, s.tarif, s.predplatne_do, (select a.poznamka from skoly_admin a where a.skola_id = s.id), s.vytvoreno,
      (select count(*)::int from deti d where d.skola_id = s.id and d.ukonceno is null),
      (select count(*)::int from tridy t where t.skola_id = s.id),
      (select count(*)::int from uzivatele u where u.skola_id = s.id and u.role <> 'rodic'),
      (select count(*)::int from uzivatele u where u.skola_id = s.id and u.role = 'rodic'),
      coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'jmeno', u.jmeno, 'email', u.email, 'aktivni', u.aktivni) order by u.jmeno)
                from uzivatele u where u.skola_id = s.id and u.role = 'reditelka'), '[]'),
      coalesce((select jsonb_agg(jsonb_build_object('kod', p.kod, 'jmeno', p.jmeno, 'email', p.email, 'plati_do', p.plati_do) order by p.vytvoreno)
                from pozvanky p where p.skola_id = s.id and p.role = 'reditelka' and p.prijato is null and p.zruseno is null and p.plati_do > now()), '[]')
    from skoly s order by s.nazev;
end $$;

create or replace function admin_zaloz_skolu(p_nazev text, p_izo text default '', p_red_izo text default '', p_kontakt text default null, p_tarif text default 'pilot', p_predplatne_do date default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare id uuid;
begin
  if not je_superadmin() then raise exception 'Jen pro správce LifeOS.'; end if;
  if coalesce(trim(p_nazev), '') = '' then raise exception 'Chybí název školky.'; end if;
  insert into skoly (nazev, izo, red_izo, kontakt, stav, tarif, predplatne_do)
  values (trim(p_nazev), coalesce(p_izo, ''), coalesce(p_red_izo, ''), p_kontakt, 'ceka', coalesce(p_tarif, 'pilot'), p_predplatne_do)
  returning skoly.id into id;
  insert into financni_nastaveni (skola_id, ucet, skolkovne) values (id, '', 0) on conflict do nothing;
  return id;
end $$;

create or replace function admin_uprav_skolu(p_id uuid, p_nazev text default null, p_kontakt text default null, p_stav text default null, p_tarif text default null, p_predplatne_do date default null, p_poznamka text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not je_superadmin() then raise exception 'Jen pro správce LifeOS.'; end if;
  if p_stav is not null and p_stav not in ('ceka', 'aktivni', 'blokovana') then raise exception 'Neznámý stav školky.'; end if;
  update skoly set
    nazev = coalesce(nullif(trim(p_nazev), ''), nazev),
    kontakt = coalesce(p_kontakt, kontakt),
    stav = coalesce(p_stav, stav),
    tarif = coalesce(p_tarif, tarif),
    predplatne_do = case when p_predplatne_do is null then predplatne_do else p_predplatne_do end
  where id = p_id;
  if not found then raise exception 'Školka neexistuje.'; end if;
  if p_poznamka is not null then
    insert into skoly_admin (skola_id, poznamka) values (p_id, p_poznamka)
    on conflict (skola_id) do update set poznamka = excluded.poznamka;
  end if;
end $$;

create or replace function admin_pozvi_reditelku(p_skola uuid, p_jmeno text, p_email text) returns text
language plpgsql security definer set search_path = public as $$
declare k text := novy_kod();
begin
  if not je_superadmin() then raise exception 'Jen pro správce LifeOS.'; end if;
  if not exists (select 1 from skoly where id = p_skola) then raise exception 'Školka neexistuje.'; end if;
  if coalesce(trim(p_jmeno), '') = '' or p_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Vyplňte jméno a platný e-mail.'; end if;
  update pozvanky set zruseno = now() where skola_id = p_skola and lower(email) = lower(trim(p_email)) and prijato is null and zruseno is null;
  insert into pozvanky (kod, skola_id, email, jmeno, role, vytvoril) values (k, p_skola, lower(trim(p_email)), trim(p_jmeno), 'reditelka', auth.uid());
  return substr(k, 1, 4) || '-' || substr(k, 5, 4);
end $$;

create or replace function admin_nastav_ucet(p_uzivatel uuid, p_aktivni boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not je_superadmin() then raise exception 'Jen pro správce LifeOS.'; end if;
  update uzivatele set aktivni = p_aktivni where id = p_uzivatel and role <> 'rodic';
  if not found then raise exception 'Účet neexistuje.'; end if;
end $$;

create or replace function admin_zrus_pozvanku(p_kod text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (je_superadmin() or exists (select 1 from pozvanky p where p.kod = upper(regexp_replace(p_kod, '[^A-Za-z0-9]', '', 'g')) and p.skola_id = moje_skola() and moje_role() in ('reditelka', 'zastupce'))) then
    raise exception 'Pozvánku nemůžete zrušit.';
  end if;
  update pozvanky set zruseno = now() where kod = upper(regexp_replace(p_kod, '[^A-Za-z0-9]', '', 'g')) and prijato is null;
end $$;

-- ------------------------------------------- ředitelka: zaměstnanci školy
create or replace function zamestnanci_skoly()
returns table (id uuid, jmeno text, email text, role text, aktivni boolean, trida text, pozvanka text, plati_do timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not je_vedeni() then raise exception 'Přístupy spravuje vedení školy.'; end if;
  return query
    select u.id, u.jmeno, u.email, u.role::text, u.aktivni,
      (select string_agg(t.nazev, ', ') from ucitel_trida ut join tridy t on t.id = ut.trida_id where ut.ucitel_id = u.id), null::text, null::timestamptz
    from uzivatele u where u.skola_id = moje_skola() and u.role <> 'rodic'
    union all
    select null, p.jmeno, p.email, p.role::text, null, (select t.nazev from tridy t where t.id = p.trida_id),
      substr(p.kod, 1, 4) || '-' || substr(p.kod, 5, 4), p.plati_do
    from pozvanky p where p.skola_id = moje_skola() and p.prijato is null and p.zruseno is null and p.plati_do > now()
    order by 2;
end $$;

create or replace function pozvi_zamestnance(p_jmeno text, p_email text, p_role text, p_trida uuid default null) returns text
language plpgsql security definer set search_path = public as $$
declare k text := novy_kod();
begin
  if not je_vedeni() then raise exception 'Zaměstnance zve vedení školy.'; end if;
  if p_role not in ('zastupce', 'ucitelka', 'hospodarka', 'kucharka') then raise exception 'Tuto roli pozvat nejde.'; end if;
  if p_role = 'ucitelka' and p_trida is null then raise exception 'Vyberte třídu.'; end if;
  if p_trida is not null and not exists (select 1 from tridy where id = p_trida and skola_id = moje_skola()) then raise exception 'Třída do školky nepatří.'; end if;
  if coalesce(trim(p_jmeno), '') = '' or p_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Vyplňte jméno a platný e-mail.'; end if;
  if exists (select 1 from uzivatele where skola_id = moje_skola() and lower(email) = lower(trim(p_email))) then raise exception 'Tento e-mail už ve školce přístup má.'; end if;
  update pozvanky set zruseno = now() where skola_id = moje_skola() and lower(email) = lower(trim(p_email)) and prijato is null and zruseno is null;
  insert into pozvanky (kod, skola_id, email, jmeno, role, trida_id, vytvoril)
  values (k, moje_skola(), lower(trim(p_email)), trim(p_jmeno), p_role::role_t, p_trida, auth.uid());
  return substr(k, 1, 4) || '-' || substr(k, 5, 4);
end $$;

create or replace function nastav_ucet_zamestnance(p_uzivatel uuid, p_aktivni boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not je_vedeni() then raise exception 'Přístupy spravuje vedení školy.'; end if;
  if p_uzivatel = auth.uid() then raise exception 'Sama sebe zablokovat nemůžete.'; end if;
  update uzivatele set aktivni = p_aktivni where id = p_uzivatel and skola_id = moje_skola() and role not in ('rodic', 'reditelka');
  if not found then raise exception 'Účet ve školce není (ředitelku blokuje jen správce LifeOS).'; end if;
end $$;

-- ------------------------------------------------- přijetí pozvánky
-- Nový uživatel se zaregistruje (e-mail + heslo) a zadá kód. E-mail musí
-- sedět s pozvánkou — kód sám nestačí.
create or replace function prijmi_pozvanku(p_kod text) returns table (role text, skola text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  me uuid := auth.uid();
  mail text := lower(coalesce(auth.jwt() ->> 'email', (select email from auth.users where id = auth.uid())));
  p pozvanky;
begin
  if me is null then raise exception 'Nejste přihlášeni.'; end if;
  if exists (select 1 from uzivatele where id = me) then raise exception 'Tento účet už ve školce je.'; end if;
  select * into p from pozvanky
   where kod = upper(regexp_replace(coalesce(p_kod, ''), '[^A-Za-z0-9]', '', 'g')) and prijato is null and zruseno is null and plati_do > now()
   for update;
  if not found then raise exception 'Kód pozvánky neplatí — je překlepnutý, použitý nebo propadlý.'; end if;
  if lower(p.email) <> mail then raise exception 'Pozvánka patří jinému e-mailu — zaregistrujte se e-mailem, na který přišla.'; end if;
  insert into uzivatele (id, skola_id, jmeno, role, email) values (me, p.skola_id, p.jmeno, p.role, p.email);
  if p.trida_id is not null then insert into ucitel_trida values (me, p.trida_id) on conflict do nothing; end if;
  -- první ředitelka školky ji tím aktivuje
  if p.role = 'reditelka' then update skoly set stav = 'aktivni' where id = p.skola_id and stav = 'ceka'; end if;
  update pozvanky set prijato = now(), prijal = me where kod = p.kod;
  return query select p.role::text, (select nazev from skoly where id = p.skola_id);
end $$;

-- Ředitelka už nesmí měnit uzivatele přímo (aktivace jde jen přes funkce).
drop policy if exists uziv_menit on uzivatele;
create policy uziv_menit on uzivatele for update using (moje_role() = 'reditelka' and skola_id = moje_skola() and id <> auth.uid())
  with check (moje_role() = 'reditelka' and skola_id = moje_skola() and role <> 'reditelka');

-- Jídelna: stejná kontrola, odolná vůči NULL (účet bez role nesmí projít).
create or replace function zverejni_jidelnicek(p_dny jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare
  sk uuid := moje_skola();
  r jsonb; j uuid; s uuid; dr text; n int := 0;
begin
  if not coalesce(moje_role() in ('kucharka', 'reditelka'), false) then raise exception 'Jídelníček zveřejňuje jídelna.'; end if;
  for r in select * from jsonb_array_elements(p_dny) loop
    dr := case r->>'chod' when 'pol' then 'polevka' when 'obed' then 'obed' when 'nap' then 'napoj' else 'svacina' end;
    select id into j from jidla where skola_id = sk and nazev = r->>'nazev' and druh = dr limit 1;
    if j is null then insert into jidla (skola_id, nazev, druh) values (sk, r->>'nazev', dr) returning id into j; end if;
    delete from jidlo_suroviny where jidlo_id = j;
    insert into suroviny (skola_id, nazev, alergeny)
      values (sk, 'alergeny: ' || (r->>'nazev'), coalesce(array(select jsonb_array_elements_text(r->'alergeny'))::smallint[], '{}'))
      returning id into s;
    insert into jidlo_suroviny values (j, s);
    delete from nahrady where jidlo_id = j;
    insert into nahrady (jidlo_id, alergen, text)
      select j, k::smallint, v from jsonb_each_text(coalesce(r->'nahrady', '{}'::jsonb)) as e(k, v) where v <> '';
    insert into jidelnicek (skola_id, den, chod, jidlo_id, zverejneno)
      values (sk, (r->>'den')::date, r->>'chod', j, true)
      on conflict (skola_id, den, chod) do update set jidlo_id = excluded.jidlo_id, zverejneno = true;
    n := n + 1;
  end loop;
  return n;
end $$;

create or replace function nastav_nahrady(p boolean) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not coalesce(moje_role() in ('kucharka', 'reditelka'), false) then raise exception 'Náhrady nastavuje jídelna.'; end if;
  update skoly set nahrady_obedu = p where id = moje_skola();
  return p;
end $$;

-- Stav, tarif a předplatné mění jen správce LifeOS (nebo funkce v databázi,
-- např. přijetí pozvánky). Zásada skola_menit pustí vedení k ostatním polím.
create or replace function hlidej_skolu() returns trigger language plpgsql set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon') and not je_superadmin()
     and (new.stav, new.tarif, new.predplatne_do) is distinct from (old.stav, old.tarif, old.predplatne_do) then
    raise exception 'Stav školky a předplatné mění jen správce LifeOS.';
  end if;
  return new;
end $$;
drop trigger if exists b_hlidej_skolu on skoly;
create trigger b_hlidej_skolu before update on skoly for each row execute function hlidej_skolu();

drop trigger if exists a_pozvanky on pozvanky;
create trigger a_pozvanky after insert or update on pozvanky for each row execute function zapis_audit();

revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;

-- -----------------------------------------------------------------------------
-- SEBE jako superadmina (upravte e-mail na svůj účet v Authentication → Users):
-- insert into superadmini (uzivatel_id, jmeno) select id, 'Roman' from auth.users where email = 'vas@email.cz' on conflict do nothing;
-- -----------------------------------------------------------------------------
