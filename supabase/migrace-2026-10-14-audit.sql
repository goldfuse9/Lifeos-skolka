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
