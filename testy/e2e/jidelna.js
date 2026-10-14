// Jídelna v ostrém provozu: jídelníček, počty a diety ze serveru; změny se
// promítnou rodičům; vyprázdnění chodu; náhrady jen skryté, ne smazané.
const { sql, sqlJako, stranka, konec, prihlas, kontrola } = require('./spolecne');
const RODA = 'aaaaaaaa-0000-4000-8000-000000000003', EMA = '00000000-0000-4000-8000-000000000101';
const rodicVidi = (q) => sqlJako(RODA, '', q);
module.exports = async () => {
  // den výdeje (o víkendu pondělí) — rodič Emy ho omluví
  const den = sql(`select (case extract(isodow from (now() at time zone 'Europe/Prague')::date) when 6 then (now() at time zone 'Europe/Prague')::date + 2 when 7 then (now() at time zone 'Europe/Prague')::date + 1 else (now() at time zone 'Europe/Prague')::date end)`);
  sql(`insert into dochazka (dite_id, den, stav, strava_prihlasena) values ('${EMA}', '${den}', 'omluven', false) on conflict (dite_id, den) do update set strava_prihlasena = false, stav = 'omluven'`);
  const p = await stranka();
  await prihlas(p, 'Jídelna', 'kucharka@test.cz');
  let t = await p.locator('body').innerText();
  kontrola('jídelna: skutečná školka, „Ostrý provoz“', t.includes('MŠ Sluníčko (test)') && t.includes('Ostrý provoz'));
  kontrola('počty podle skutečných tříd (Berušky, Sluníčka; ne Motýlci)', t.includes('Berušky') && t.includes('Sluníčka') && !t.includes('Motýlci'));
  kontrola('odhlášený oběd od rodiče se promítl (Odhlášeno 1)', /ODHLÁŠENO\s*\n?\s*1/i.test(t));
  kontrola('stránka Kuchařky (ukázková) skrytá', !(await p.locator('nav[aria-label="Jídelna"]').innerText()).includes('Kuchařky'));
  await p.click('nav button:has-text("Jídelníček")'); await p.waitForTimeout(500);
  t = await p.locator('body').innerText();
  const pondeli = sql(`select nazev from jidelnicek_kuchyne(date_trunc('week', '${den}'::date)::date, date_trunc('week', '${den}'::date)::date) k where chod = 'obed'`.replace('jidelnicek_kuchyne', 'jidelnicek_tyden'));
  kontrola('jídelníček desky = jídelníček na serveru (ne ukázkový)', t.includes('Zveřejněno rodičům') && !t.includes('Rizoto se sýrem, okurkový salát'));
  // změna jídla v zveřejněném týdnu (pondělní polévka)
  const po = sql(`select to_char(date_trunc('week', '${den}'::date), 'YYYY-MM-DD')`);
  const stara = rodicVidi(`select nazev from jidelnicek_tyden('${po}', '${po}') where chod='pol';`);
  await p.locator(`button:has-text("${stara}")`).first().click(); await p.waitForTimeout(400);
  await p.locator('[role=dialog] button:has-text("Dýňový krém")').first().click();
  await p.locator('[role=dialog] button:has-text("Vybrat")').last().click(); await p.waitForTimeout(1800);
  kontrola('změna jídla po zveřejnění se ukáže rodiči', rodicVidi(`select nazev from jidelnicek_tyden('${po}', '${po}') where chod='pol';`) === 'Dýňový krém', stara);
  kontrola('alergeny nového jídla rodiči sedí (mléko 7, celer 9)', rodicVidi(`select alergeny::text from jidelnicek_tyden('${po}', '${po}') where chod='pol';`) === '{7,9}');
  // vyprázdnění chodu
  await p.locator('button:has-text("Dýňový krém")').first().click(); await p.waitForTimeout(400);
  await p.locator('[role=dialog] button:has-text("Vyprázdnit")').click(); await p.waitForTimeout(1800);
  kontrola('vyprázdněný chod rodič nevidí', rodicVidi(`select count(*) from jidelnicek_tyden('${po}', '${po}') where chod='pol';`) === '0');
  // diety
  await p.click('nav button:has-text("Diety a náhrady")'); await p.waitForTimeout(500);
  t = await p.locator('body').innerText();
  kontrola('diety: skutečné děti (Ema mléko, Tobiáš vejce), ne ukázkové', t.includes('Ema T.') && t.includes('Tobiáš U.') && !t.includes('Jonáš'));
  await p.locator('button:has-text("Chybí doporučení lékaře")').first().click(); await p.waitForTimeout(1500);
  kontrola('doložení diety uloženo na server', sql(`select count(*) from diety where doporuceni_lekare`) === '1');
  const sNahradou = rodicVidi(`select count(*) from jidelnicek_tyden('${po}', ('${po}'::date + 4)) where nahrady <> '{}';`);
  await p.click('button:has-text("Náhrady děláme")'); await p.waitForTimeout(1500);
  kontrola('vypnuté náhrady: rodič je nevidí', rodicVidi(`select count(*) from jidelnicek_tyden('${po}', ('${po}'::date + 4)) where nahrady <> '{}';`) === '0');
  await p.click('button:has-text("Náhrady neděláme")'); await p.waitForTimeout(1500);
  kontrola('znovu zapnuté náhrady: nic se neztratilo', rodicVidi(`select count(*) from jidelnicek_tyden('${po}', ('${po}'::date + 4)) where nahrady <> '{}';`) === sNahradou, sNahradou);
  kontrola('suroviny se při zveřejnění nezdvojují', +sql(`select count(*) from suroviny where nazev like 'alergeny: %'`) <= 20);
  kontrola('bez chyb JS', !p.chyby.length, p.chyby.join('; '));
  await konec();
};
