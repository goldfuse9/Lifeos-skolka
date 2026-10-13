-- =============================================================================
-- Školka — TESTOVACÍ REŽIM: výchozí testovací data (jen smyšlená)
-- -----------------------------------------------------------------------------
-- Dvě testovací školky (A = „MŠ Sluníčko (test A)“, B = „MŠ Dejvice (test B)“),
-- třídy, děti, rodiče, zaměstnanci všech rolí, jídelníček na tento týden,
-- dnešní docházka, událost, úraz, akce, zpráva.
--
-- Skript jde spustit kdykoli znovu: NEJDŘÍV SMAŽE vše, co patří těmto dvěma
-- testovacím školkám (pevná ID eeeeeeee-…), a založí je znovu. Jiných školek
-- se nedotkne. Ostrá data sem nepatří — spouštějte v testovacím projektu.
--
-- Účty: založte je předem (lokálně to dělá tests/reset.sh; v Supabase
-- Authentication → Users → Add user, Auto Confirm). Bez účtu se daná osoba
-- přeskočí (vypíše se NOTICE). Seznam je v tests/README.md.
-- =============================================================================
do $$
declare
  sa uuid := 'eeeeeeee-0000-4000-8000-00000000000a';
  sb uuid := 'eeeeeeee-0000-4000-8000-00000000000b';
  a1 uuid := 'eeeeeeee-0000-4000-8000-0000000000a1';   -- Sluníčka (A)
  a2 uuid := 'eeeeeeee-0000-4000-8000-0000000000a2';   -- Berušky (A)
  b1 uuid := 'eeeeeeee-0000-4000-8000-0000000000b1';   -- Žabky (B)
  ema uuid := 'eeeeeeee-0000-4000-8000-000000000101';
  oli uuid := 'eeeeeeee-0000-4000-8000-000000000102';
  sof uuid := 'eeeeeeee-0000-4000-8000-000000000103';
  jak uuid := 'eeeeeeee-0000-4000-8000-000000000104';
  ann uuid := 'eeeeeeee-0000-4000-8000-000000000105';
  mat uuid := 'eeeeeeee-0000-4000-8000-000000000106';
  ada uuid := 'eeeeeeee-0000-4000-8000-000000000201';
  ell uuid := 'eeeeeeee-0000-4000-8000-000000000202';
  skoly_t uuid[] := array['eeeeeeee-0000-4000-8000-00000000000a', 'eeeeeeee-0000-4000-8000-00000000000b']::uuid[];
  deti_t uuid[];
  lide_t uuid[];
  dnes date := (now() at time zone 'Europe/Prague')::date;
  po date := date_trunc('week', now() at time zone 'Europe/Prague')::date;
  menu text[][] := array[
    array['Chléb s tuňákovou pomazánkou', 'Hovězí vývar s nudlemi', 'Kuřecí plátek, bramborová kaše', 'Rohlík s máslem, jablko'],
    array['Ovesná kaše s ovocem', 'Brokolicová polévka', 'Rizoto se sýrem a zeleninou', 'Chléb s vaječnou pomazánkou'],
    array['Rohlík s medem, kakao', 'Čočková polévka', 'Rybí filé, brambory, mrkvový salát', 'Jogurt, piškoty'],
    array['Chléb s lučinou a pažitkou', 'Zeleninová polévka s kapáním', 'Špagety s boloňskou omáčkou', 'Chléb s arašídovým krémem'],
    array['Sýrová pomazánka, rohlík', 'Rajská polévka s rýží', 'Kuře na paprice, těstoviny', 'Makovec, mléko']];
  al text[][] := array[
    array['{1,4,7}', '{1,3,9}', '{7}', '{1,7}'],
    array['{1,7}', '{1,7,9}', '{7,9}', '{1,3,7}'],
    array['{1,7}', '{1,9}', '{4,7}', '{1,3,7}'],
    array['{1,7}', '{1,3,9}', '{1,3,9}', '{1,5}'],
    array['{1,7}', '{1,9}', '{1,3,7}', '{1,3,7}']];
  chody text[] := array['prs', 'pol', 'obed', 'sv'];
  druhy text[] := array['svacina', 'polevka', 'obed', 'svacina'];
  j uuid; s uuid; i int; c int; sk uuid; tb text;
  u record;
  ucet uuid;
  ucitelka_a uuid;
begin
  -- ------------------------------------------------------------- úklid
  -- Triggery (audit, „jen přidávat“ u účetních pohybů) a cizí klíče se na
  -- dobu úklidu vypnou — maže se jen to, co patří testovacím školkám.
  set local session_replication_role = replica;
  select array_agg(id) into deti_t from deti where skola_id = any (skoly_t);
  select array_agg(id) into lide_t from uzivatele where skola_id = any (skoly_t);
  deti_t := coalesce(deti_t, '{}'); lide_t := coalesce(lide_t, '{}');
  delete from jidlo_suroviny where jidlo_id in (select id from jidla where skola_id = any (skoly_t));
  delete from nahrady where jidlo_id in (select id from jidla where skola_id = any (skoly_t));
  delete from predpis_polozky where predpis_id in (select id from predpisy where dite_id = any (deti_t));
  delete from ucitel_trida where trida_id in (select id from tridy where skola_id = any (skoly_t)) or ucitel_id = any (lide_t);
  delete from tridni_kniha where trida_id in (select id from tridy where skola_id = any (skoly_t));
  foreach tb in array array['diety', 'dochazka', 'konta', 'poverene_osoby', 'predpisy', 'souhlasy', 'upominky', 'vyzvednuti', 'zastupci'] loop
    execute format('delete from %I where dite_id = any ($1)', tb) using deti_t;
  end loop;
  foreach tb in array array['akce', 'alba', 'audit_log', 'financni_nastaveni', 'jidelnicek', 'jidla', 'parovaci_kody', 'platby', 'porady',
                            'pozvanky', 'sazby_stravneho', 'skoly_admin', 'suroviny', 'ucetni_pohyby', 'udalosti_ditete', 'urazy', 'zadosti', 'zpravy'] loop
    execute format('delete from %I where skola_id = any ($1)', tb) using skoly_t;
  end loop;
  delete from deti where skola_id = any (skoly_t);
  delete from uzivatele where skola_id = any (skoly_t);
  delete from tridy where skola_id = any (skoly_t);
  delete from skoly where id = any (skoly_t);
  delete from superadmini where uzivatel_id in (select id from auth.users where email = 'superadmin@test.lifeos.cz');
  set local session_replication_role = origin;

  -- ------------------------------------------------------------- školky a třídy
  insert into skoly (id, nazev, izo, red_izo, kontakt, stav, tarif, predplatne_do) values
    (sa, 'MŠ Sluníčko (test A)', '000000101', '600000101', '+420 220 000 101', 'aktivni', 'pilot', dnes + 60),
    (sb, 'MŠ Dejvice (test B)',  '000000102', '600000102', '+420 220 000 102', 'aktivni', 'hybrid', dnes + 10);
  insert into financni_nastaveni (skola_id, ucet, skolkovne) values (sa, '19-2000145399/0800', 900), (sb, '19-2000145400/0800', 1100);
  insert into sazby_stravneho values (sa, '3-6', 48), (sa, '7+', 52), (sb, '3-6', 50), (sb, '7+', 54);
  insert into tridy (id, skola_id, nazev, kod, barva, kapacita) values
    (a1, sa, 'Sluníčka', 'SL', '#F5B400', 24), (a2, sa, 'Berušky', 'BE', '#E5484D', 24), (b1, sb, 'Žabky', 'ZA', '#4CAF50', 20);

  -- ------------------------------------------------------------- lidé
  for u in select * from (values
      ('superadmin@test.lifeos.cz',   null::uuid, 'Správce Test',        null::text,   null::uuid, true),
      ('reditelka.a@test.lifeos.cz',  sa, 'Ivana Pokorná (test)',        'reditelka',  null, true),
      ('zastupce.a@test.lifeos.cz',   sa, 'Alena Benešová (test)',       'zastupce',   a2,   true),
      ('ucitelka.a@test.lifeos.cz',   sa, 'Petra Horáková (test)',       'ucitelka',   a1,   true),
      ('ucitelka2.a@test.lifeos.cz',  sa, 'Lucie Malá (test)',           'ucitelka',   a2,   true),
      ('hospodarka.a@test.lifeos.cz', sa, 'Marta Svobodová (test)',      'hospodarka', null, true),
      ('kucharka.a@test.lifeos.cz',   sa, 'Jana Králová (test)',         'kucharka',   null, true),
      ('zablokovana.a@test.lifeos.cz',sa, 'Blanka Zablokovaná (test)',   'ucitelka',   a1,   false),
      ('rodic.a@test.lifeos.cz',      sa, 'Jana Testová (test)',         'rodic',      null, true),
      ('rodic2.a@test.lifeos.cz',     sa, 'Tomáš Zkušební (test)',       'rodic',      null, true),
      ('reditelka.b@test.lifeos.cz',  sb, 'Hana Dvořáková (test)',       'reditelka',  null, true),
      ('ucitelka.b@test.lifeos.cz',   sb, 'Eva Učitelka (test)',         'ucitelka',   b1,   true),
      ('rodic.b@test.lifeos.cz',      sb, 'Karel Béčko (test)',          'rodic',      null, true)
    ) as t(email, skola, jmeno, role, trida, aktivni) loop
    select id into ucet from auth.users where email = u.email;
    if ucet is null then raise notice 'Účet % neexistuje — přeskakuji.', u.email; continue; end if;
    if u.skola is null then
      insert into superadmini (uzivatel_id, jmeno) values (ucet, u.jmeno) on conflict do nothing;
      continue;
    end if;
    -- účet mohl být v pilotní školce → přesunout do testovací
    delete from ucitel_trida where ucitel_id = ucet;
    insert into uzivatele (id, skola_id, jmeno, role, email, aktivni) values (ucet, u.skola, u.jmeno, u.role::role_t, u.email, u.aktivni)
      on conflict (id) do update set skola_id = excluded.skola_id, jmeno = excluded.jmeno, role = excluded.role, email = excluded.email, aktivni = excluded.aktivni;
    if u.trida is not null then insert into ucitel_trida values (ucet, u.trida) on conflict do nothing; end if;
  end loop;

  -- ------------------------------------------------------------- děti
  insert into deti (id, skola_id, trida_id, jmeno, prijmeni, datum_narozeni, pohlavi, zahajeni, alergie, variabilni_symbol, znacka, rodne_cislo) values
    (ema, sa, a1, 'Ema',    'Testová',   '2022-03-05', 'F', '2025-09-01', 'mléko', '900101', 'jablko',    '225305/0001'),
    (oli, sa, a1, 'Oliver', 'Zkušební',  '2021-06-12', 'M', '2024-09-01', null,    '900102', 'snehulak',  '210612/0002'),
    (sof, sa, a1, 'Sofie',  'Testová',   '2023-01-20', 'F', '2026-09-01', 'arašídy', '900103', 'kytka',   '235120/0003'),
    (jak, sa, a1, 'Jakub',  'Pokusný',   '2021-11-02', 'M', '2024-09-01', null,    '900104', 'auticko',   '211102/0004'),
    (ann, sa, a2, 'Anna',   'Vzorová',   '2022-07-14', 'F', '2025-09-01', 'lepek', '900105', 'motyl',     '225714/0005'),
    (mat, sa, a2, 'Matyáš', 'Ukázkový',  '2022-02-28', 'M', '2025-09-01', null,    '900106', 'micek',     '220228/0006'),
    (ada, sb, b1, 'Adam',   'Béčko',     '2021-09-09', 'M', '2024-09-01', 'vejce', '900201', 'lodicka',   '210909/0007'),
    (ell, sb, b1, 'Ella',   'Béčková',   '2022-12-01', 'F', '2025-09-01', null,    '900202', 'srdce',     '226201/0008');

  insert into zastupci (dite_id, jmeno, telefon, email, poradi, uzivatel_id) values
    (ema, 'Jana Testová', '+420 600 000 101', 'rodic.a@test.lifeos.cz', 1, (select id from uzivatele where email = 'rodic.a@test.lifeos.cz')),
    (sof, 'Jana Testová', '+420 600 000 101', 'rodic.a@test.lifeos.cz', 1, (select id from uzivatele where email = 'rodic.a@test.lifeos.cz')),
    (oli, 'Tomáš Zkušební', '+420 600 000 102', 'rodic2.a@test.lifeos.cz', 1, (select id from uzivatele where email = 'rodic2.a@test.lifeos.cz')),
    (jak, 'Klára Pokusná', '+420 600 000 104', 'klara@test.lifeos.cz', 1, null),
    (ann, 'Petr Vzorový', '+420 600 000 105', 'petr@test.lifeos.cz', 1, null),
    (mat, 'Lenka Ukázková', '+420 600 000 106', 'lenka@test.lifeos.cz', 1, null),
    (ada, 'Karel Béčko', '+420 600 000 201', 'rodic.b@test.lifeos.cz', 1, (select id from uzivatele where email = 'rodic.b@test.lifeos.cz')),
    (ell, 'Iva Béčková', '+420 600 000 202', 'iva@test.lifeos.cz', 1, null);
  insert into poverene_osoby (dite_id, jmeno) values (ema, 'babička Marie (test)'), (ada, 'děda Josef (test)');

  -- ------------------------------------------------------------- dnešek
  if extract(isodow from dnes) <= 5 then
    insert into dochazka (dite_id, den, stav, prichod, trida_dnes) values
      (oli, dnes, 'pritomen', '07:45', a1), (jak, dnes, 'pritomen', '08:05', a1), (ann, dnes, 'pritomen', '07:55', a2), (ada, dnes, 'pritomen', '08:10', b1);
    insert into dochazka (dite_id, den, stav, omluvenka, omluva_zadana, strava_prihlasena) values
      (sof, dnes, 'omluven', 'nemoc', now() - interval '1 day', false);
  end if;
  select id into ucitelka_a from uzivatele where email = 'ucitelka.a@test.lifeos.cz';
  if ucitelka_a is not null then
    insert into udalosti_ditete (dite_id, skola_id, druh, titulek, text, zapsal, zapsal_jmeno)
      values (oli, sa, 'jidlo', 'Dobře se najedl', 'Snědl celý oběd.', ucitelka_a, 'Petra Horáková (test)');
    insert into urazy (skola_id, cislo, rok, dite_id, kdy, kde, co, osetreni, zapsal)
      values (sa, 1, extract(year from dnes)::int, jak, now() - interval '2 hours', 'zahrada', 'odřené koleno (test)', 'vydezinfikováno', ucitelka_a);
  end if;

  -- ------------------------------------------------------------- jídelníček na tento týden (obě školky)
  foreach sk in array skoly_t loop
    for i in 1..5 loop
      for c in 1..4 loop
        insert into jidla (skola_id, nazev, druh) values (sk, menu[i][c], druhy[c]) returning id into j;
        insert into suroviny (skola_id, nazev, alergeny) values (sk, 'suroviny: ' || menu[i][c], al[i][c]::smallint[]) returning id into s;
        insert into jidlo_suroviny values (j, s);
        if 7 = any(al[i][c]::smallint[]) then insert into nahrady values (j, 7, 'bezmléčná varianta'); end if;
        insert into jidelnicek (skola_id, den, chod, jidlo_id, zverejneno) values (sk, po + (i - 1), chody[c], j, true);
      end loop;
    end loop;
  end loop;

  -- ------------------------------------------------------------- akce a zprávy
  insert into akce (skola_id, den, cas, nazev, misto, poznamka) values (sa, po + 9, '15:30', 'Drakiáda (test)', 'zahrada školky', 'draka z domu');
  insert into akce (skola_id, trida_id, den, cas, nazev, misto, poznamka, cena) values (sa, a1, po + 15, '08:00', 'Výlet do ZOO (test)', 'sraz před školkou', 'batoh, pití', 250);
  insert into akce (skola_id, den, cas, nazev, misto) values (sb, po + 8, '16:00', 'Dýňování (test B)', 'třída Žabky');
  insert into zpravy (skola_id, komu, predmet, text, odeslal)
    select sa, 'vse', 'Vítejte v testu A', 'Testovací školka A — data jsou smyšlená.', id from uzivatele where email = 'reditelka.a@test.lifeos.cz';
  insert into zpravy (skola_id, komu, predmet, text, odeslal)
    select sb, 'vse', 'Vítejte v testu B', 'Testovací školka B — data jsou smyšlená.', id from uzivatele where email = 'reditelka.b@test.lifeos.cz';
end $$;
