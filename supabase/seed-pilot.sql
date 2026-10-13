-- =============================================================================
-- Školka — testovací školka pro pilot (jen smyšlená data)
-- -----------------------------------------------------------------------------
-- Před spuštěním založte v Supabase → Authentication → Users → Add user
-- dva účty (s heslem, „Auto Confirm User“ zapnuté):
--     reditelka@test.cz   — ředitelka (ředitelna, jídelna)
--     ucitelka@test.cz    — učitelka třídy Sluníčka (tablet)
-- E-maily jdou změnit níže. Skript jde spustit znovu — nic nezdvojí.
-- =============================================================================
do $$
declare
  e_reditelka constant text := 'reditelka@test.cz';
  e_ucitelka  constant text := 'ucitelka@test.cz';
  r uuid; u uuid;
  sk uuid := '00000000-0000-4000-8000-000000000001';
  t1 uuid := '00000000-0000-4000-8000-000000000011';
  t2 uuid := '00000000-0000-4000-8000-000000000012';
  ema uuid := '00000000-0000-4000-8000-000000000101';
  oli uuid := '00000000-0000-4000-8000-000000000102';
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
  j uuid; s uuid; i int; c int;
begin
  select id into r from auth.users where email = e_reditelka;
  select id into u from auth.users where email = e_ucitelka;
  if r is null or u is null then
    raise exception 'Nejdřív založte účty % a % (Authentication → Users → Add user).', e_reditelka, e_ucitelka;
  end if;

  insert into skoly (id, nazev, izo, red_izo, kontakt) values (sk, 'MŠ Sluníčko (test)', '000000001', '600000001', '+420 220 123 456')
    on conflict (id) do nothing;
  insert into financni_nastaveni (skola_id, ucet, skolkovne) values (sk, '19-2000145399/0800', 900) on conflict do nothing;
  insert into sazby_stravneho values (sk, '3-6', 48), (sk, '7+', 52) on conflict do nothing;
  insert into tridy (id, skola_id, nazev, kod, barva, kapacita) values
    (t1, sk, 'Sluníčka', 'SL', '#F5B400', 24), (t2, sk, 'Berušky', 'BE', '#E5484D', 24) on conflict (id) do nothing;
  insert into uzivatele (id, skola_id, jmeno, role) values (r, sk, 'Ivana Pokorná', 'reditelka'), (u, sk, 'Petra Horáková', 'ucitelka')
    on conflict (id) do update set skola_id = excluded.skola_id, role = excluded.role;
  insert into ucitel_trida values (u, t1) on conflict do nothing;

  insert into deti (id, skola_id, trida_id, jmeno, prijmeni, datum_narozeni, pohlavi, zahajeni, alergie, variabilni_symbol) values
    (ema, sk, t1, 'Ema', 'Testová', '2022-03-05', 'F', '2025-09-01', 'mléko', '260001'),
    (oli, sk, t1, 'Oliver', 'Zkušební', '2021-06-12', 'M', '2024-09-01', null, '250002')
    on conflict (id) do nothing;
  insert into zastupci (dite_id, jmeno, telefon, email, poradi)
    select ema, 'Jana Testová', '+420 600 000 001', 'jana@test.cz', 1 where not exists (select 1 from zastupci where dite_id = ema);
  insert into zastupci (dite_id, jmeno, telefon, email, poradi)
    select oli, 'Tomáš Zkušební', '+420 600 000 002', 'tomas@test.cz', 1 where not exists (select 1 from zastupci where dite_id = oli);
  insert into poverene_osoby (dite_id, jmeno)
    select ema, 'babička Marie' where not exists (select 1 from poverene_osoby where dite_id = ema);

  -- jídelníček na tento týden (zveřejněný) s alergeny přes suroviny
  for i in 1..5 loop
    for c in 1..4 loop
      if exists (select 1 from jidelnicek where skola_id = sk and den = po + (i - 1) and chod = chody[c]) then continue; end if;
      insert into jidla (skola_id, nazev, druh) values (sk, menu[i][c], druhy[c]) returning id into j;
      insert into suroviny (skola_id, nazev, alergeny) values (sk, 'suroviny: ' || menu[i][c], al[i][c]::smallint[]) returning id into s;
      insert into jidlo_suroviny values (j, s);
      if 7 = any(al[i][c]::smallint[]) then insert into nahrady values (j, 7, 'bezmléčná varianta'); end if;
      insert into jidelnicek (skola_id, den, chod, jidlo_id, zverejneno) values (sk, po + (i - 1), chody[c], j, true);
    end loop;
  end loop;

  insert into akce (skola_id, den, cas, nazev, misto, poznamka)
    select sk, po + 9, '15:30', 'Drakiáda', 'zahrada školky', 'draka z domu'
    where not exists (select 1 from akce where skola_id = sk and nazev = 'Drakiáda');
  insert into akce (skola_id, trida_id, den, cas, nazev, misto, poznamka, cena)
    select sk, t1, po + 15, '08:00', 'Výlet do ZOO', 'sraz před školkou', 'batoh, pití, pláštěnka', 250
    where not exists (select 1 from akce where skola_id = sk and nazev = 'Výlet do ZOO');
  insert into zpravy (skola_id, komu, predmet, text, odeslal)
    select sk, 'vse', 'Vítejte v testu', 'Tohle je testovací školka. Všechna data jsou smyšlená.', r
    where not exists (select 1 from zpravy where skola_id = sk);
end $$;
