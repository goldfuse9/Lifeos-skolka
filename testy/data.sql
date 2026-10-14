-- =============================================================================
-- Testovací data (SMYŠLENÁ) pro lokální testovací režim. Spouští reset.sh po
-- setup.sql. Pevná ID, aby testy věděly, koho čekat. Hesla: lokální proxy
-- přijme libovolné heslo (auth.users.heslo = NULL).
--
--   Školka A „MŠ Sluníčko (test)“  …0001 — třídy Sluníčka (…0011), Berušky (…0012)
--   Školka B „MŠ Dejvice (test)“   …0002 — třída Žabky (…0021)
--
--   a1 reditelka@test.cz  ředitelka A        b1 reditelka.b@test.cz  ředitelka B
--   a4 zastupce@test.cz   zástupkyně A       b2 ucitelka.b@test.cz   učitelka B (Žabky)
--   a2 ucitelka@test.cz   učitelka A Sluníčka  b3 (anonym) rodič Adama (B)
--   a5 ucitelka2@test.cz  učitelka A Berušky
--   a6 hospodarka@test.cz hospodářka A       aa roman@lifeos.cz      superadmin
--   a7 kucharka@test.cz   kuchařka A         cc bezrole@test.cz      účet bez školky
--   a3 (anonym) rodič Emy (A)                a8 (anonym) rodič Olivera (A)
-- =============================================================================
\set ON_ERROR_STOP 1
insert into auth.users (id, email, is_anonymous) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'reditelka@test.cz', false),
  ('aaaaaaaa-0000-4000-8000-000000000002', 'ucitelka@test.cz', false),
  ('aaaaaaaa-0000-4000-8000-000000000003', null, true),
  ('aaaaaaaa-0000-4000-8000-000000000004', 'zastupce@test.cz', false),
  ('aaaaaaaa-0000-4000-8000-000000000005', 'ucitelka2@test.cz', false),
  ('aaaaaaaa-0000-4000-8000-000000000006', 'hospodarka@test.cz', false),
  ('aaaaaaaa-0000-4000-8000-000000000007', 'kucharka@test.cz', false),
  ('aaaaaaaa-0000-4000-8000-000000000008', null, true),
  ('bbbbbbbb-0000-4000-8000-000000000001', 'reditelka.b@test.cz', false),
  ('bbbbbbbb-0000-4000-8000-000000000002', 'ucitelka.b@test.cz', false),
  ('bbbbbbbb-0000-4000-8000-000000000003', null, true),
  ('aaaaaaaa-0000-4000-8000-0000000000aa', 'roman@lifeos.cz', false),
  ('cccccccc-0000-4000-8000-0000000000cc', 'bezrole@test.cz', false);

-- školka A: stejný základ jako supabase/seed-pilot.sql (třídy, Ema, Oliver, jídelníček, akce)
\ir ../supabase/seed-pilot.sql

insert into uzivatele (id, skola_id, jmeno, role, email) values
  ('aaaaaaaa-0000-4000-8000-000000000004', '00000000-0000-4000-8000-000000000001', 'Alena Benešová', 'zastupce', 'zastupce@test.cz'),
  ('aaaaaaaa-0000-4000-8000-000000000005', '00000000-0000-4000-8000-000000000001', 'Lucie Malá', 'ucitelka', 'ucitelka2@test.cz'),
  ('aaaaaaaa-0000-4000-8000-000000000006', '00000000-0000-4000-8000-000000000001', 'Marta Svobodová', 'hospodarka', 'hospodarka@test.cz'),
  ('aaaaaaaa-0000-4000-8000-000000000007', '00000000-0000-4000-8000-000000000001', 'Jana Králová', 'kucharka', 'kucharka@test.cz');
update uzivatele set email = 'reditelka@test.cz' where id = 'aaaaaaaa-0000-4000-8000-000000000001';
update uzivatele set email = 'ucitelka@test.cz' where id = 'aaaaaaaa-0000-4000-8000-000000000002';
insert into ucitel_trida values ('aaaaaaaa-0000-4000-8000-000000000005', '00000000-0000-4000-8000-000000000012');
insert into deti (id, skola_id, trida_id, jmeno, prijmeni, datum_narozeni, pohlavi, zahajeni, alergie, variabilni_symbol, rodne_cislo) values
  ('00000000-0000-4000-8000-000000000103', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000012',
   'Tobiáš', 'Ukázkový', '2022-01-20', 'M', '2025-09-01', 'vejce', '260003', '220120/0000');
insert into zastupci (dite_id, jmeno, telefon, email, poradi) values
  ('00000000-0000-4000-8000-000000000103', 'Eva Ukázková', '+420 600 000 003', 'eva@test.cz', 1);
-- rodiče A spárovaní s dětmi (jako po uplatnění kódu)
insert into uzivatele (id, skola_id, jmeno, role) values
  ('aaaaaaaa-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000001', 'Jana Testová', 'rodic'),
  ('aaaaaaaa-0000-4000-8000-000000000008', '00000000-0000-4000-8000-000000000001', 'Tomáš Zkušební', 'rodic');
update zastupci set uzivatel_id = 'aaaaaaaa-0000-4000-8000-000000000003' where dite_id = '00000000-0000-4000-8000-000000000101';
update zastupci set uzivatel_id = 'aaaaaaaa-0000-4000-8000-000000000008' where dite_id = '00000000-0000-4000-8000-000000000102';

-- školka B
insert into skoly (id, nazev, izo, red_izo, kontakt) values
  ('00000000-0000-4000-8000-000000000002', 'MŠ Dejvice (test)', '000000002', '600000002', '+420 220 000 002');
insert into financni_nastaveni (skola_id, ucet, skolkovne) values ('00000000-0000-4000-8000-000000000002', '', 0);
insert into tridy (id, skola_id, nazev, kod, barva, kapacita) values
  ('00000000-0000-4000-8000-000000000021', '00000000-0000-4000-8000-000000000002', 'Žabky', 'ZA', '#3E9B4F', 20);
insert into uzivatele (id, skola_id, jmeno, role, email) values
  ('bbbbbbbb-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000002', 'Jana Nová', 'reditelka', 'reditelka.b@test.cz'),
  ('bbbbbbbb-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000002', 'Eva Učitelka', 'ucitelka', 'ucitelka.b@test.cz'),
  ('bbbbbbbb-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000002', 'Petr Rodič', 'rodic', null);
insert into ucitel_trida values ('bbbbbbbb-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000021');
insert into deti (id, skola_id, trida_id, jmeno, prijmeni, datum_narozeni, pohlavi, zahajeni, alergie, variabilni_symbol, rodne_cislo) values
  ('00000000-0000-4000-8000-000000000201', '00000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000021',
   'Adam', 'Cizí', '2021-11-02', 'M', '2024-09-01', 'arašídy', '250201', '211102/0000');
insert into zastupci (dite_id, uzivatel_id, jmeno, telefon, email, poradi) values
  ('00000000-0000-4000-8000-000000000201', 'bbbbbbbb-0000-4000-8000-000000000003', 'Petr Cizí', '+420 600 000 201', 'petr@test.cz', 1);
insert into urazy (skola_id, cislo, rok, dite_id, kdy, kde, co, osetreni, zapsal) values
  ('00000000-0000-4000-8000-000000000002', 1, extract(year from now())::int, '00000000-0000-4000-8000-000000000201', now() - interval '1 day',
   'zahrada', 'odřené koleno (B)', 'dezinfekce', 'bbbbbbbb-0000-4000-8000-000000000002');
insert into udalosti_ditete (skola_id, dite_id, druh, titulek, hodnota, zapsal_jmeno) values
  ('00000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000201', 'teplota', 'Zvýšená teplota (B)', '37,8 °C', 'Eva Učitelka');

insert into superadmini (uzivatel_id, jmeno) values ('aaaaaaaa-0000-4000-8000-0000000000aa', 'Správce (test)');
