-- =============================================================================
-- Školka — bezpečnostní opravy z auditu 14. 10. 2026 (nálezy E1–E19, F1–F12,
-- C10–C11, D3–D9, A9, E14–E15). Spusťte jednou v Supabase → SQL Editor po
-- migraci 2026-10-13c. Jde spustit opakovaně.
--
-- POZOR do budoucna: tabulka deti a uzivatele mají práva po sloupcích. Řádek
-- „grant select, insert, update, delete on all tables … to authenticated“
-- v novějších migracích by je zase otevřel — po něm je nutné tento soubor
-- (část E5/E7) spustit znovu. Hlídá to testy/bezpecnost.sh.
-- =============================================================================

-- E1: pohledy nesmí jít zapisovat (deti_jidelna běží s právy vlastníka → obchází RLS)
revoke insert, update, delete, truncate on deti_jidelna, deti_trida from authenticated, anon;
alter view deti_jidelna set (security_barrier = true);

-- E2: pozvánka — e-mail musí být známý a neprázdný, anonymní účet pozvánku nepřijme
create or replace function prijmi_pozvanku(p_kod text) returns table (role text, skola text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  me uuid := auth.uid();
  mail text := lower(nullif(coalesce(nullif(auth.jwt() ->> 'email', ''), (select email from auth.users where id = auth.uid())), ''));
  p pozvanky;
begin
  if me is null then raise exception 'Nejste přihlášeni.'; end if;
  if mail is null or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'Pozvánku přijme jen účet s e-mailem.';
  end if;
  if exists (select 1 from uzivatele where id = me) then raise exception 'Tento účet už ve školce je.'; end if;
  select * into p from pozvanky
   where kod = upper(regexp_replace(coalesce(p_kod, ''), '[^A-Za-z0-9]', '', 'g')) and prijato is null and zruseno is null and plati_do > now()
   for update;
  if not found then raise exception 'Kód pozvánky neplatí — je překlepnutý, použitý nebo propadlý.'; end if;
  if lower(p.email) is distinct from mail then raise exception 'Pozvánka patří jinému e-mailu — zaregistrujte se e-mailem, na který přišla.'; end if;
  insert into uzivatele (id, skola_id, jmeno, role, email) values (me, p.skola_id, p.jmeno, p.role, p.email);
  if p.trida_id is not null then insert into ucitel_trida values (me, p.trida_id) on conflict do nothing; end if;
  if p.role = 'reditelka' then update skoly set stav = 'aktivni' where id = p.skola_id and stav = 'ceka'; end if;
  update pozvanky set prijato = now(), prijal = me where kod = p.kod;
  return query select p.role::text, (select nazev from skoly where id = p.skola_id);
end $$;

-- E3: jídelna — diety, vazby jídlo–surovina a náhrady jen ve vlastní školce
create or replace function skola_ditete(d uuid) returns uuid language sql stable security definer set search_path = public as
  $$ select skola_id from deti where id = d $$;
drop policy if exists die on diety;
create policy die on diety for all using (je_kuchyne() and skola_ditete(dite_id) = moje_skola())
  with check (je_kuchyne() and skola_ditete(dite_id) = moje_skola());
drop policy if exists js on jidlo_suroviny;
create policy js on jidlo_suroviny for all
  using (je_kuchyne() and exists (select 1 from jidla j where j.id = jidlo_id and j.skola_id = moje_skola()))
  with check (je_kuchyne() and exists (select 1 from jidla j where j.id = jidlo_id and j.skola_id = moje_skola())
              and exists (select 1 from suroviny s where s.id = surovina_id and s.skola_id = moje_skola()));
drop policy if exists nah_cist on nahrady;
create policy nah_cist on nahrady for select using (exists (select 1 from jidla j where j.id = jidlo_id and j.skola_id = moje_skola()));
drop policy if exists nah_menit on nahrady;
create policy nah_menit on nahrady for all using (je_kuchyne() and exists (select 1 from jidla j where j.id = jidlo_id and j.skola_id = moje_skola()));

-- E4: třídní kniha — vedení jen vlastní školky, učitelka jen své třídy
drop policy if exists kniha on tridni_kniha;
create policy kniha on tridni_kniha for all using (
  (je_vedeni() and exists (select 1 from tridy t where t.id = trida_id and t.skola_id = moje_skola()))
  or (moje_role() = 'ucitelka' and je_ucitelka_tridy(trida_id)));

-- E5: citlivé sloupce dětí — učitelka a hospodářka je přímo nečtou
-- (RLS je řádková; sloupce se omezí právy a vedení/rodič čtou citlivé údaje přes funkci)
revoke select on deti from authenticated;
grant select (id, skola_id, trida_id, jmeno, prijmeni, datum_narozeni, pohlavi, obcanstvi, znalost_cj, spadovy, zahajeni,
  po_stupen, ivp, asistent, plpp_do, alergie, variabilni_symbol, osvobozen_od_skolkovneho, ukonceno, vytvoreno, znacka) on deti to authenticated;
create or replace function deti_osobni(p_dite uuid default null)
returns table (id uuid, rodne_cislo text, kod_cizince text, obec text, adresa text, dorucovaci_adresa text, pojistovna text, ockovani boolean,
               spz text, spz_plati_do date, kod_zahajeni text, zpusob_ppv text, odklad boolean, iv_overeni text, duvod_ukonceni text)
language sql stable security definer set search_path = public as $$
  select d.id, d.rodne_cislo, d.kod_cizince, d.obec, d.adresa, d.dorucovaci_adresa, d.pojistovna, d.ockovani, d.spz, d.spz_plati_do,
         d.kod_zahajeni, d.zpusob_ppv, d.odklad, d.iv_overeni, d.duvod_ukonceni
  from deti d
  where (p_dite is null or d.id = p_dite)
    and ((je_vedeni() and d.skola_id = moje_skola()) or (moje_role() = 'rodic' and moje_dite(d.id)))
$$;

-- E6: účetní pohyb do konta dítěte (trigger s právy vlastníka + kontrola školky)
create or replace function pohyb_do_konta() returns trigger language plpgsql security definer set search_path = public as $$
declare d uuid;
begin
  foreach d in array array[case when new.md like 'dite:%' then substr(new.md, 6)::uuid end, case when new.dal like 'dite:%' then substr(new.dal, 6)::uuid end] loop
    if d is not null and not exists (select 1 from deti where id = d and skola_id = new.skola_id) then
      raise exception 'Dítě do této školky nepatří.';
    end if;
  end loop;
  if new.md like 'dite:%' then
    insert into konta (dite_id, saldo) values (substr(new.md, 6)::uuid, -new.castka)
      on conflict (dite_id) do update set saldo = konta.saldo - new.castka;
  end if;
  if new.dal like 'dite:%' then
    insert into konta (dite_id, saldo) values (substr(new.dal, 6)::uuid, new.castka)
      on conflict (dite_id) do update set saldo = konta.saldo + new.castka;
  end if;
  return new;
end $$;
alter table ucetni_pohyby drop constraint if exists ucetni_pohyby_ucty;
alter table ucetni_pohyby add constraint ucetni_pohyby_ucty check (
  md ~ '^(dite:[0-9a-f-]{36}|banka|pokladna|vynosy:[a-z_]+)$' and dal ~ '^(dite:[0-9a-f-]{36}|banka|pokladna|vynosy:[a-z_]+)$') not valid;

-- E7: ředitelka mění jen „měkké“ údaje zaměstnanců; role, id, e-mail a blokace jen přes funkce
drop policy if exists uziv_menit on uzivatele;
create policy uziv_menit on uzivatele for update
  using (moje_role() = 'reditelka' and skola_id = moje_skola() and id <> auth.uid() and role not in ('reditelka', 'rodic'))
  with check (moje_role() = 'reditelka' and skola_id = moje_skola() and role not in ('reditelka', 'rodic'));
revoke update on uzivatele from authenticated;
grant update (jmeno, uvazek, zdravotni_prukaz, skoleni_hygieny) on uzivatele to authenticated;

-- E8: vazby napříč školkami (třída, učitelka, přesun na den, úraz)
drop policy if exists ut_menit on ucitel_trida;
create policy ut_menit on ucitel_trida for all
  using (je_vedeni() and exists (select 1 from tridy t where t.id = trida_id and t.skola_id = moje_skola()))
  with check (je_vedeni() and exists (select 1 from tridy t where t.id = trida_id and t.skola_id = moje_skola())
              and exists (select 1 from uzivatele u where u.id = ucitel_id and u.skola_id = moje_skola() and u.role in ('ucitelka', 'zastupce', 'reditelka')));
drop policy if exists deti_menit on deti;
create policy deti_menit on deti for all using (je_vedeni() and skola_id = moje_skola())
  with check (je_vedeni() and skola_id = moje_skola() and (trida_id is null or exists (select 1 from tridy t where t.id = trida_id and t.skola_id = moje_skola())));
drop policy if exists doch_menit on dochazka;
create policy doch_menit on dochazka for all using (moje_role() in ('reditelka', 'zastupce', 'ucitelka') and moje_dite(dite_id))
  with check (moje_role() in ('reditelka', 'zastupce', 'ucitelka') and moje_dite(dite_id)
              and (trida_dnes is null or exists (select 1 from tridy t where t.id = trida_dnes and t.skola_id = moje_skola())));
drop policy if exists uraz_zapsat on urazy;
create policy uraz_zapsat on urazy for insert with check (moje_role() in ('reditelka', 'zastupce', 'ucitelka') and moje_dite(dite_id)
  and skola_id = moje_skola() and zapsal = auth.uid());

-- E9: rodič neomlouvá zpětně a nepřepisuje „neomluven“
create or replace function omluv_dite(p_dite uuid, p_od date, p_do date, p_duvod text default null)
returns table (den date, obed_odhlasen boolean)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  ted timestamp := now() at time zone 'Europe/Prague';
  dni int := 1; do_ time := '08:00';
  d date; rodic boolean := coalesce(moje_role() = 'rodic', false);
begin
  if not (moje_role() in ('rodic', 'reditelka', 'zastupce', 'ucitelka') and moje_dite(p_dite)) then
    raise exception 'Toto dítě omluvit nemůžete.';
  end if;
  if p_do < p_od or p_do > p_od + 31 then raise exception 'Omluvit jde nejvýš měsíc dopředu.'; end if;
  if rodic and p_od < ted::date then raise exception 'Zpětně omlouvá jen školka.'; end if;
  select f.omluva_dni_predem, f.omluva_do into dni, do_
    from financni_nastaveni f join deti x on x.skola_id = f.skola_id where x.id = p_dite;
  dni := coalesce(dni, 1); do_ := coalesce(do_, '08:00');
  d := p_od;
  while d <= p_do loop
    if extract(isodow from d) < 6 then
      insert into dochazka (dite_id, den, stav, omluvenka, omluva_zadana, strava_prihlasena, omluva_potvrzena, omluvu_potvrdil)
      values (p_dite, d, 'omluven', p_duvod, now(), not (ted < (d - dni) + do_), null, null)
      on conflict (dite_id, den) do update
        set stav = 'omluven', omluvenka = excluded.omluvenka, omluva_zadana = excluded.omluva_zadana,
            strava_prihlasena = excluded.strava_prihlasena, omluva_potvrzena = null, omluvu_potvrdil = null
        where dochazka.stav <> 'pritomen' and not (rodic and dochazka.stav = 'neomluven');
      den := d; obed_odhlasen := ted < (d - dni) + do_;
      return next;
    end if;
    d := d + 1;
  end loop;
end $$;

-- E10: číslo úrazu přiděluje databáze (učitelka nevidí úrazy jiných tříd)
create or replace function cislo_urazu() returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform pg_advisory_xact_lock(hashtext('urazy:' || new.skola_id || ':' || new.rok));
  new.cislo := coalesce((select max(cislo) from urazy where skola_id = new.skola_id and rok = new.rok), 0) + 1;
  return new;
end $$;
drop trigger if exists b_cislo_urazu on urazy;
create trigger b_cislo_urazu before insert on urazy for each row execute function cislo_urazu();

-- E17: SECURITY DEFINER / triggery s pevnou search_path
alter function zapis_audit() set search_path = public;
alter function pohyby_jen_pridavat() set search_path = public;
alter function je_kuchyne() set search_path = public;
alter function je_finance() set search_path = public;
alter function novy_kod() set search_path = public;

-- E19: audit změn účtů, přiřazení tříd a diet
drop trigger if exists a_uzivatele on uzivatele;
create trigger a_uzivatele after insert or update or delete on uzivatele for each row execute function zapis_audit();
drop trigger if exists a_ucitel_trida on ucitel_trida;
create trigger a_ucitel_trida after insert or update or delete on ucitel_trida for each row execute function zapis_audit();
drop trigger if exists a_diety on diety;
create trigger a_diety after insert or update or delete on diety for each row execute function zapis_audit();

-- E11/E12: smazání účtu / dítěte
alter table zastupci drop constraint if exists zastupci_uzivatel_id_fkey,
  add constraint zastupci_uzivatel_id_fkey foreign key (uzivatel_id) references uzivatele on delete set null;
alter table predpisy drop constraint if exists predpisy_dite_id_fkey, add constraint predpisy_dite_id_fkey foreign key (dite_id) references deti on delete restrict;
alter table konta drop constraint if exists konta_dite_id_fkey, add constraint konta_dite_id_fkey foreign key (dite_id) references deti on delete restrict;
revoke delete on deti from authenticated;   -- dítě se ukončuje (deti.ukonceno), nemaže

-- E18: obrana do hloubky proti výchozím grantům Supabase
revoke all on all tables in schema public from anon;
revoke truncate, references, trigger on all tables in schema public from authenticated;
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke all on functions from anon, public;

-- E14 + E15/F11: uplatnění kódu rodiče — jedna školka na účet, omezený počet pokusů.
-- Neplatný kód nevyhazuje výjimku (ta by smazala i záznam o pokusu), ale vrátí
-- prázdný výsledek; LifeOS pak ukáže „Kód neplatí.“ Po 10 chybných pokusech za
-- 15 minut je účet na 15 minut zablokovaný.
create table if not exists pokusy_kodu (
  uzivatel_id uuid not null,
  kdy timestamptz not null default now()
);
create index if not exists pokusy_kodu_kdo on pokusy_kodu (uzivatel_id, kdy);
alter table pokusy_kodu enable row level security;   -- žádné zásady: jen přes funkce

create or replace function hlidej_pokusy_kodu() returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Nejste přihlášeni.'; end if;
  delete from pokusy_kodu where kdy < now() - interval '1 day';
  if (select count(*) from pokusy_kodu where uzivatel_id = auth.uid() and kdy > now() - interval '15 minutes') >= 10 then
    raise exception 'Příliš mnoho chybných pokusů. Zkuste to za 15 minut, nebo požádejte ve školce o nový kód.';
  end if;
end $$;

create or replace function nahled_kodu(p_kod text)
returns table (jmeno text, prijmeni text, datum_narozeni date, skola text, trida text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform hlidej_pokusy_kodu();
  return query
    select d.jmeno, d.prijmeni, d.datum_narozeni, s.nazev, t.nazev
    from parovaci_kody k join deti d on d.id = k.dite_id join skoly s on s.id = k.skola_id left join tridy t on t.id = d.trida_id
    where k.kod = upper(regexp_replace(coalesce(p_kod, ''), '[^A-Za-z0-9]', '', 'g'))
      and k.pouzito is null and k.zruseno is null and k.plati_do > now() and s.stav = 'aktivni';
  if not found then insert into pokusy_kodu (uzivatel_id) values (auth.uid()); end if;
end $$;

create or replace function uplatni_kod(p_kod text, p_jmeno text default null)
returns table (dite_id uuid, jmeno text, prijmeni text, datum_narozeni date, skola text, trida text, telefon_skoly text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  me uuid := auth.uid();
  k parovaci_kody;
begin
  perform hlidej_pokusy_kodu();
  select pk.* into k from parovaci_kody pk join skoly s on s.id = pk.skola_id
   where pk.kod = upper(regexp_replace(coalesce(p_kod, ''), '[^A-Za-z0-9]', '', 'g'))
     and pk.pouzito is null and pk.zruseno is null and pk.plati_do > now() and s.stav = 'aktivni'
   for update of pk;
  if not found then
    insert into pokusy_kodu (uzivatel_id) values (me);
    return;
  end if;
  if exists (select 1 from uzivatele u where u.id = me and u.role <> 'rodic') then
    raise exception 'Tento účet patří zaměstnanci školy, rodičovský kód na něj nejde použít.';
  end if;
  if exists (select 1 from uzivatele u where u.id = me and u.skola_id <> k.skola_id) then
    raise exception 'Tento telefon je už propojený s jinou školkou. Dítě z další školky zatím propojit nejde.';
  end if;
  insert into uzivatele (id, skola_id, jmeno, role)
  values (me, k.skola_id, coalesce(nullif(trim(p_jmeno), ''), 'Rodič'), 'rodic')
  on conflict (id) do nothing;
  if k.zastupce_id is not null then
    update zastupci set uzivatel_id = me where id = k.zastupce_id;
  elsif not exists (select 1 from zastupci z where z.dite_id = k.dite_id and z.uzivatel_id = me) then
    insert into zastupci (dite_id, uzivatel_id, jmeno, poradi)
    values (k.dite_id, me, coalesce(nullif(trim(p_jmeno), ''), 'Rodič (LifeOS)'), 9);
  end if;
  update parovaci_kody set pouzito = now(), pouzil = me where kod = k.kod;
  return query
    select d.id, d.jmeno, d.prijmeni, d.datum_narozeni, s.nazev, t.nazev, s.kontakt
    from deti d join skoly s on s.id = d.skola_id left join tridy t on t.id = d.trida_id
    where d.id = k.dite_id;
end $$;

-- F11: kódy z plně náhodných bajtů (7. bajt UUID v4 nese verzi → jen 16 možností)
create or replace function nahodny_kod() returns text language plpgsql volatile set search_path = public as $$
declare abc constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; b bytea := uuid_send(gen_random_uuid()); k text := ''; i int;
begin
  foreach i in array array[0, 1, 2, 3, 4, 5, 10, 11] loop k := k || substr(abc, get_byte(b, i) % 32 + 1, 1); end loop;
  return k;
end $$;
create or replace function novy_kod() returns text language sql volatile set search_path = public as $$ select nahodny_kod() $$;
create or replace function vytvor_kod_rodice(p_dite uuid, p_zastupce uuid default null) returns text
language plpgsql security definer set search_path = public as $$
declare k text := nahodny_kod();
begin
  if not (je_vedeni() and exists (select 1 from deti where id = p_dite and skola_id = moje_skola())) then
    raise exception 'Kód pro rodiče vydává jen vedení školy.';
  end if;
  if p_zastupce is not null and not exists (select 1 from zastupci where id = p_zastupce and dite_id = p_dite) then
    raise exception 'Zástupce k tomuto dítěti nepatří.';
  end if;
  update parovaci_kody set zruseno = now()
   where dite_id = p_dite and zastupce_id is not distinct from p_zastupce and pouzito is null and zruseno is null;
  insert into parovaci_kody (kod, skola_id, dite_id, zastupce_id, vytvoril, plati_do)
  values (k, moje_skola(), p_dite, p_zastupce, auth.uid(), now() + interval '14 days');
  return substr(k, 1, 4) || '-' || substr(k, 5, 4);
end $$;

-- D9/F12: autor zápisu u dítěte je vždy přihlášený účet (nejde podvrhnout)
create or replace function autor_udalosti() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null then
    new.zapsal := auth.uid();
    new.zapsal_jmeno := coalesce((select jmeno from uzivatele where id = auth.uid()), new.zapsal_jmeno);
  end if;
  return new;
end $$;
drop trigger if exists b_autor_udalosti on udalosti_ditete;
create trigger b_autor_udalosti before insert on udalosti_ditete for each row execute function autor_udalosti();
drop policy if exists ud_psat on udalosti_ditete;
create policy ud_psat on udalosti_ditete for insert with check (moje_role() in ('reditelka', 'zastupce', 'ucitelka')
  and moje_dite(dite_id) and skola_id = moje_skola());

-- F8/A9: zprávy podle adresáta. komu = 'vse' | 'zamestnanci' | 'trida:<uuid>' | 'dite:<uuid>'
create or replace function smi_zpravu(p_komu text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(case
    when moje_role() is null then false
    when p_komu = 'vse' then true
    when moje_role() in ('reditelka', 'zastupce', 'hospodarka') then true
    when p_komu = 'zamestnanci' then moje_role() <> 'rodic'
    when p_komu like 'trida:%' then
      case moje_role()
        when 'ucitelka' then je_ucitelka_tridy(nullif(substr(p_komu, 7), '')::uuid)
        when 'rodic' then exists (select 1 from deti d join zastupci z on z.dite_id = d.id
                                  where z.uzivatel_id = auth.uid() and d.trida_id::text = substr(p_komu, 7))
        else false end
    when p_komu like 'dite:%' then
      case moje_role() when 'rodic' then exists (select 1 from zastupci z where z.uzivatel_id = auth.uid() and z.dite_id::text = substr(p_komu, 6))
                       when 'ucitelka' then moje_dite(nullif(substr(p_komu, 6), '')::uuid)
                       else false end
    else false end, false)
$$;
drop policy if exists zpravy_cist on zpravy;
create policy zpravy_cist on zpravy for select using (skola_id = moje_skola() and smi_zpravu(komu));

-- práva po migraci (bez otevření sloupců deti/uzivatele — viz hlavička)
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
revoke execute on function hlidej_pokusy_kodu(), nahodny_kod() from authenticated;

-- B1/B4: ředitelna v ostrém provozu — měsíční souhrn docházky (Supabase vrací
-- nejvýš 1000 řádků, celý rok docházky by se nevešel).
create or replace function dochazka_souhrn(p_od date, p_do date)
returns table (dite_id uuid, mesic text, pritomen int, omluven int, neomluven int)
language sql stable security definer set search_path = public as $$
  select x.dite_id, to_char(x.den, 'YYYY-MM'),
         count(*) filter (where x.stav = 'pritomen')::int,
         count(*) filter (where x.stav = 'omluven')::int,
         count(*) filter (where x.stav = 'neomluven')::int
  from dochazka x join deti d on d.id = x.dite_id
  where coalesce(moje_role() in ('reditelka', 'zastupce', 'hospodarka'), false)
    and d.skola_id = moje_skola() and x.den between p_od and p_do
  group by x.dite_id, to_char(x.den, 'YYYY-MM')
$$;
grant execute on function dochazka_souhrn(date, date) to authenticated;

-- =============================================================================
-- Jídelna v ostrém provozu (C1–C8, C13, C15, C16)
-- Alergeny a náhrady se ukládají přímo k chodu v jídelníčku (náhrada platí jen
-- pro ten den; vypnutí náhrad je jen skryje, nesmaže). Katalog jídel a surovin
-- kuchyně je pracovní pomůcka → jeden JSON na školku.
-- =============================================================================
alter table jidelnicek add column if not exists alergeny smallint[];
alter table jidelnicek add column if not exists nahrady jsonb;

create table if not exists jidelna_katalog (
  skola_id uuid primary key references skoly on delete cascade,
  data jsonb not null,
  zmeneno timestamptz not null default now(),
  zmenil uuid
);
alter table jidelna_katalog enable row level security;
drop policy if exists katalog on jidelna_katalog;
create policy katalog on jidelna_katalog for all using (coalesce(je_kuchyne(), false) and skola_id = moje_skola())
  with check (coalesce(je_kuchyne(), false) and skola_id = moje_skola());
grant select, insert, update on jidelna_katalog to authenticated;

drop function if exists zverejni_jidelnicek(jsonb);
create or replace function zverejni_jidelnicek(p_dny jsonb, p_od date default null, p_do date default null) returns int
language plpgsql security definer set search_path = public as $$
declare
  sk uuid := moje_skola();
  r jsonb; j uuid; dr text; n int := 0; vden date; a smallint[];
begin
  if not coalesce(moje_role() in ('kucharka', 'reditelka'), false) then raise exception 'Jídelníček zveřejňuje jídelna.'; end if;
  if jsonb_typeof(p_dny) <> 'array' then raise exception 'Chybná data jídelníčku.'; end if;
  for r in select * from jsonb_array_elements(p_dny) loop
    vden := (r->>'den')::date;
    if extract(isodow from vden) > 5 then raise exception 'Jídelníček je jen na pracovní dny (% je víkend).', vden; end if;
    if p_od is not null and (vden < p_od or vden > p_do) then raise exception 'Den % není v zveřejňovaném týdnu.', vden; end if;
    if coalesce(r->>'chod', '') not in ('prs', 'pol', 'obed', 'sv', 'nap') then raise exception 'Neznámý chod.'; end if;
    if coalesce(trim(r->>'nazev'), '') = '' then raise exception 'Chybí název jídla (%).', vden; end if;
    a := coalesce(array(select jsonb_array_elements_text(coalesce(r->'alergeny', '[]'::jsonb))::smallint order by 1), '{}');
    if exists (select 1 from unnest(a) x where x < 1 or x > 14) then raise exception 'Alergeny jsou čísla 1–14.'; end if;
    dr := case r->>'chod' when 'pol' then 'polevka' when 'obed' then 'obed' when 'nap' then 'napoj' else 'svacina' end;
    select id into j from jidla where skola_id = sk and nazev = trim(r->>'nazev') and druh = dr limit 1;
    if j is null then insert into jidla (skola_id, nazev, druh) values (sk, trim(r->>'nazev'), dr) returning id into j; end if;
    insert into jidelnicek (skola_id, den, chod, jidlo_id, zverejneno, alergeny, nahrady)
      values (sk, vden, r->>'chod', j, true, a, coalesce(r->'nahrady', '{}'::jsonb))
      on conflict (skola_id, den, chod) do update set jidlo_id = excluded.jidlo_id, zverejneno = true, alergeny = excluded.alergeny, nahrady = excluded.nahrady;
    n := n + 1;
  end loop;
  -- vyprázdněné chody v zveřejňovaném týdnu zmizí i rodičům
  if p_od is not null then
    delete from jidelnicek x where x.skola_id = sk and x.den between p_od and p_do
      and not exists (select 1 from jsonb_array_elements(p_dny) e where (e->>'den')::date = x.den and e->>'chod' = x.chod);
  end if;
  return n;
end $$;

create or replace function jidelnicek_tyden(p_od date, p_do date)
returns table (den date, chod text, nazev text, alergeny smallint[], nahrady jsonb)
language sql stable security definer set search_path = public as $$
  select j.den, j.chod, x.nazev,
         coalesce(j.alergeny, (select array_agg(distinct a order by a) from jidlo_suroviny js join suroviny s on s.id = js.surovina_id, unnest(s.alergeny) a where js.jidlo_id = x.id), '{}'),
         case when (select nahrady_obedu from skoly where id = moje_skola()) then
           coalesce(j.nahrady, (select jsonb_object_agg(n.alergen, n.text) from nahrady n where n.jidlo_id = x.id), '{}'::jsonb)
         else '{}'::jsonb end
  from jidelnicek j join jidla x on x.id = j.jidlo_id
  where j.skola_id = moje_skola() and j.zverejneno and j.den between p_od and p_do
  order by j.den, array_position(array['prs', 'pol', 'obed', 'sv', 'nap'], j.chod)
$$;

-- kuchyně: celý jídelníček (i se skrytými náhradami) pro desku jídelny
create or replace function jidelnicek_kuchyne(p_od date, p_do date)
returns table (den date, chod text, nazev text, alergeny smallint[], nahrady jsonb, zverejneno boolean)
language sql stable security definer set search_path = public as $$
  select j.den, j.chod, x.nazev,
         coalesce(j.alergeny, (select array_agg(distinct a order by a) from jidlo_suroviny js join suroviny s on s.id = js.surovina_id, unnest(s.alergeny) a where js.jidlo_id = x.id), '{}'),
         coalesce(j.nahrady, (select jsonb_object_agg(n.alergen, n.text) from nahrady n where n.jidlo_id = x.id), '{}'::jsonb), j.zverejneno
  from jidelnicek j join jidla x on x.id = j.jidlo_id
  where coalesce(je_kuchyne(), false) and j.skola_id = moje_skola() and j.den between p_od and p_do
$$;

-- počty jídel na den podle tříd (odhlášené obědy z omluvenek rodičů)
create or replace function obedy_den(p_den date)
returns table (trida_id uuid, trida text, barva text, deti int, odhlaseno int)
language sql stable security definer set search_path = public as $$
  select t.id, t.nazev, t.barva,
         count(d.id)::int,
         count(d.id) filter (where exists (select 1 from dochazka x where x.dite_id = d.id and x.den = p_den and x.strava_prihlasena = false))::int
  from tridy t left join deti d on d.trida_id = t.id and d.ukonceno is null and (d.zahajeni is null or d.zahajeni <= p_den)
  where coalesce(je_kuchyne(), false) and t.skola_id = moje_skola()
  group by t.id, t.nazev, t.barva order by t.nazev
$$;

-- děti s alergií pro kuchyni (jméno, první písmeno příjmení, třída, alergie, dieta)
create or replace function deti_diety()
returns table (dite_id uuid, jmeno text, trida_id uuid, alergie text, doporuceni_lekare boolean, poznamka text)
language sql stable security definer set search_path = public as $$
  select d.id, d.jmeno || ' ' || left(d.prijmeni, 1) || '.', d.trida_id, d.alergie, coalesce(x.doporuceni_lekare, false), x.poznamka
  from deti d left join diety x on x.dite_id = d.id
  where coalesce(je_kuchyne(), false) and d.skola_id = moje_skola() and d.ukonceno is null
    and (coalesce(trim(d.alergie), '') <> '' or x.dite_id is not null)
  order by d.jmeno
$$;
grant execute on function zverejni_jidelnicek(jsonb, date, date), jidelnicek_tyden(date, date), jidelnicek_kuchyne(date, date), obedy_den(date), deti_diety() to authenticated;

-- D14: „dnes“ podle Prahy (Supabase běží v UTC — mezi půlnocí a 2:00 by byl včerejšek)
create or replace function dnes_praha() returns date language sql stable set search_path = public as
  $$ select (now() at time zone 'Europe/Prague')::date $$;
alter table poverene_osoby alter column zmocneni_od set default (now() at time zone 'Europe/Prague')::date;
alter table predpisy alter column vystaveno set default (now() at time zone 'Europe/Prague')::date;
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
      where y.dite_id = d and y.den = dnes_praha() and ut.ucitel_id = auth.uid())
    when 'rodic' then exists (select 1 from zastupci z where z.dite_id = d and z.uzivatel_id = auth.uid())
  end, false) $$;
CREATE OR REPLACE FUNCTION public.uprav_udaje_rodicem(p_dite uuid, p_alergie text DEFAULT NULL::text, p_telefon text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_poverene text[] DEFAULT NULL::text[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not (moje_role() = 'rodic' and moje_dite(p_dite)) then raise exception 'Údaje tohoto dítěte měnit nemůžete.'; end if;
  if p_alergie is not null then update deti set alergie = nullif(trim(p_alergie), '') where id = p_dite; end if;
  if p_telefon is not null or p_email is not null then
    update zastupci set telefon = coalesce(nullif(trim(p_telefon), ''), telefon), email = coalesce(nullif(trim(p_email), ''), email)
     where dite_id = p_dite and uzivatel_id = auth.uid();
  end if;
  if p_poverene is not null then
    update poverene_osoby set zruseno = dnes_praha()
     where dite_id = p_dite and zruseno is null and not (jmeno = any(p_poverene));
    insert into poverene_osoby (dite_id, jmeno)
      select p_dite, x from unnest(p_poverene) x
      where trim(x) <> '' and not exists (select 1 from poverene_osoby o where o.dite_id = p_dite and o.jmeno = x and o.zruseno is null);
  end if;
end $function$;
grant execute on function dnes_praha() to authenticated;

-- A8: rodič odpojí dítě v telefonu (Odpojit / Odebrat kartu / Smazat vše) —
-- zruší se i propojení na serveru; bez dalších dětí zmizí i účet rodiče ve školce.
create or replace function odpoj_rodice(p_dite uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Nejste přihlášeni.'; end if;
  update zastupci set uzivatel_id = null where dite_id = p_dite and uzivatel_id = auth.uid();
  delete from zastupci where dite_id = p_dite and uzivatel_id is null and poradi = 9 and telefon is null and email is null;
  if not exists (select 1 from zastupci where uzivatel_id = auth.uid()) then
    delete from uzivatele where id = auth.uid() and role = 'rodic';
  end if;
end $$;
grant execute on function odpoj_rodice(uuid) to authenticated;
