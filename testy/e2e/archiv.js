// Archiv v ostrém provozu: skartační plán se ukládá ke školce, historie změn
// jde z databáze (kdo, kdy, co) a vidí ji jen vedení.
const { sql, sqlJako, stranka, konec, prihlas, kontrola } = require('./spolecne');
const EMA = '00000000-0000-4000-8000-000000000101', RA = 'aaaaaaaa-0000-4000-8000-000000000001', A = '00000000-0000-4000-8000-000000000001';
module.exports = async () => {
  sqlJako(RA, 'reditelka@test.cz', `update deti set alergie = 'pyl' where id = '${EMA}';`);
  const p = await stranka({ width: 1366, height: 900 });
  await prihlas(p, 'Ředitelna', 'reditelka@test.cz'); await p.waitForTimeout(800);
  await p.click('nav button:has-text("Archiv")'); await p.waitForTimeout(1000);
  let hist = await p.locator('section[aria-label="Historie změn"]').innerText();
  kontrola('historie změn z databáze: úprava karty Emy, kdo ji udělal', hist.includes('Karta dítěte — úprava · Ema Testová') && hist.includes('Ivana Pokorná'), hist.slice(0, 160).replace(/\n/g, ' | '));
  await p.fill('input[aria-label="Lhůta pro Třídní knihy"]', '15'); await p.waitForTimeout(1500);
  kontrola('skartační plán uložen ke školce', sql(`select skartacni_plan ->> 'Třídní knihy' from skoly where id = '${A}'`) === '15');
  // nová změna se po návratu na stránku načte
  sqlJako(RA, 'reditelka@test.cz', `select reg_cislo from nova_zadost(2027, 'Eva', 'Nová', '225707/0002', '2022-07-07', 'F', true, false, '');`);
  await p.click('nav button:has-text("Přehled")'); await p.waitForTimeout(400);
  await p.click('nav button:has-text("Archiv")'); await p.waitForTimeout(1200);
  hist = await p.locator('section[aria-label="Historie změn"]').innerText();
  kontrola('po návratu: nová žádost v historii', hist.includes('Žádost o přijetí — nový záznam · Z001'), hist.slice(0, 120).replace(/\n/g, ' | '));
  kontrola('rodné číslo se v historii neukazuje', !hist.includes('225707'));
  // po obnovení drží plán
  await p.reload(); await prihlas(p, 'Ředitelna', 'reditelka@test.cz').catch(() => {}); await p.waitForTimeout(800);
  await p.click('nav button:has-text("Archiv")'); await p.waitForTimeout(800);
  kontrola('po obnovení: lhůta 15 let', (await p.locator('input[aria-label="Lhůta pro Třídní knihy"]').inputValue()) === '15');
  kontrola('archiv bez chyb na stránce', !p.chyby.length, p.chyby.join(' / '));
  const h = await stranka({ width: 1366, height: 900 });
  await prihlas(h, 'Ředitelna', 'hospodarka@test.cz'); await h.waitForTimeout(800);
  await h.click('nav button:has-text("Archiv")'); await h.waitForTimeout(800);
  const hh = await h.locator('section[aria-label="Historie změn"]').innerText();
  kontrola('hospodářka historii nevidí (jen upozornění)', hh.includes('Záznam změn vidí vedení školy.') && !hh.includes('Ema Testová'));
  kontrola('hospodářka bez chyb', !h.chyby.length, h.chyby.join(' / '));
  await konec();
};
