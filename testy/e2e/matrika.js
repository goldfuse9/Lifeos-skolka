// Matrika v ostrém provozu: chyby z údajů na serveru (dítě bez třídy, třída
// bez označení, chybějící údaje), soubory XML se vytvoří až bez chyb a
// obsahují rodná čísla ze serveru. Nic se neodesílá — soubor se stáhne.
const { sql, stranka, konec, prihlas, kontrola } = require('./spolecne');
const EMA = '00000000-0000-4000-8000-000000000101', OLI = '00000000-0000-4000-8000-000000000102', TOB = '00000000-0000-4000-8000-000000000103';
module.exports = async () => {
  const p = await stranka({ width: 1366, height: 900 });
  await prihlas(p, 'Ředitelna', 'reditelka@test.cz'); await p.waitForTimeout(800);
  await p.click('nav button:has-text("Matrika")'); await p.waitForTimeout(600);
  let telo = await p.locator('body').innerText();
  kontrola('matrika: v ostrém provozu, s chybami nejde vytvořit soubory', telo.includes('Nejdřív opravte') && telo.includes('rodné číslo'));
  // doplnit údaje na serveru, jedno dítě bez třídy, jedna třída bez označení
  sql(`update deti set rodne_cislo = case id when '${EMA}' then '225305/0019' when '${OLI}' then '210612/0005' else '220120/0001' end,
        obec = 'Praha', adresa = 'Školní 1', kod_zahajeni = 'Nástup' where id in ('${EMA}', '${OLI}', '${TOB}');
       update deti set trida_id = null where id = '${OLI}';
       update tridy set kod = '' where nazev = 'Berušky' and skola_id = '00000000-0000-4000-8000-000000000001';`);
  await p.reload(); await prihlas(p, 'Ředitelna', 'reditelka@test.cz').catch(() => {}); await p.waitForTimeout(800);
  await p.click('nav button:has-text("Matrika")'); await p.waitForTimeout(600);
  telo = await p.locator('body').innerText();
  kontrola('dítě bez třídy je chyba', /Oliver Zkušební[\s\S]{0,80}třída/.test(telo), telo.slice(0, 0));
  kontrola('třída bez označení je chyba', telo.includes('Třída Berušky') && telo.includes('označení třídy'));
  kontrola('bez chyb na stránce i s dítětem bez třídy', !p.chyby.length, p.chyby.join(' / '));
  sql(`update deti set trida_id = '00000000-0000-4000-8000-000000000011' where id = '${OLI}';
       update tridy set kod = 'BE' where nazev = 'Berušky' and skola_id = '00000000-0000-4000-8000-000000000001';`);
  await p.reload(); await prihlas(p, 'Ředitelna', 'reditelka@test.cz').catch(() => {}); await p.waitForTimeout(800);
  await p.click('nav button:has-text("Matrika")'); await p.waitForTimeout(600);
  await p.click('button:has-text("Vytvořit soubory XML")'); await p.waitForTimeout(800);
  telo = await p.locator('body').innerText();
  kontrola('soubory vytvořené: M000000001_01.xml se 3 dětmi', telo.includes('M000000001_01.xml') && telo.includes('3 děti'));
  kontrola('náhled obsahuje RČ ze serveru a IZO', telo.includes('2253050019') && telo.includes('IZO="000000001"'));
  kontrola('matrika bez chyb na stránce', !p.chyby.length, p.chyby.join(' / '));
  await konec();
};
