// Majetek v ostrém provozu: nová položka (i více kusů) s číslem KAT-ROK-POŘADÍ,
// přesun, závada, tisk QR štítků, import z CSV, inventura (ředitelna + tablet
// učitelky), odkaz z QR štítku a práva rolí.
const { sql, sqlJako, stranka, konec, prihlas, kontrola, URL } = require('./spolecne');
const RA = 'aaaaaaaa-0000-4000-8000-000000000001', UA = 'aaaaaaaa-0000-4000-8000-000000000002', HA = 'aaaaaaaa-0000-4000-8000-000000000006', KA = 'aaaaaaaa-0000-4000-8000-000000000007';
const RODA = 'aaaaaaaa-0000-4000-8000-000000000003', RB = 'bbbbbbbb-0000-4000-8000-000000000001';
const ROK = new Date().getFullYear();
const dlg = (p) => p.locator('[role=dialog]');
const pole = (p, label) => dlg(p).locator(`label:has-text("${label}") input`).first();

module.exports = async () => {
  const p = await stranka({ width: 1440, height: 900 });
  await prihlas(p, 'Ředitelna', 'reditelka@test.cz'); await p.waitForTimeout(800);
  await p.click('nav button:has-text("Majetek")'); await p.waitForTimeout(1500);
  kontrola('majetek: výchozí kategorie a místnosti založené', sql(`select count(*) from majetek_kategorie where skola_id = '00000000-0000-4000-8000-000000000001'`) === '8'
    && +sql(`select count(*) from mistnosti where skola_id = '00000000-0000-4000-8000-000000000001'`) >= 6);
  kontrola('prázdná evidence radí import', (await p.locator('main').innerText()).includes('Evidence je prázdná'));

  // nová položka — 3 židle do Sluníček
  await p.click('header button:has-text("+ Nová položka")'); await p.waitForTimeout(300);
  await pole(p, 'Název').fill('Židle dětská Tom-Tom');
  await pole(p, 'Počet kusů').fill('3');
  await dlg(p).locator('button:has-text("NAB · Nábytek")').click();
  await dlg(p).locator('button[aria-pressed]:has-text("Sluníčka")').click();
  await pole(p, 'Cena za kus').fill('1 290');
  const shrnuti = await dlg(p).innerText();
  kontrola('dialog ukáže čísla předem', shrnuti.includes(`NAB-${ROK}-0001 až NAB-${ROK}-0003`), shrnuti.split('\n').filter((r) => r.includes('NAB-')).join(' | '));
  kontrola('účetní druh podle ceny = drobný', (await dlg(p).locator('button[aria-pressed="true"]:has-text("Drobný dlouhodobý")').count()) === 1);
  await dlg(p).locator('button:has-text("Uložit")').last().click(); await p.waitForTimeout(1500);
  kontrola('3 kusy s čísly KAT-ROK-POŘADÍ', sql(`select string_agg(cislo || ':' || ucetni_druh || ':' || cena, ',' order by cislo) from majetek`) === `NAB-${ROK}-0001:ddhm:1290.00,NAB-${ROK}-0002:ddhm:1290.00,NAB-${ROK}-0003:ddhm:1290.00`);
  kontrola('položky v seznamu', (await p.locator('section[aria-label="Seznam majetku"]').innerText()).includes(`NAB-${ROK}-0003`));

  // karta: přesun a závada
  await p.click(`section[aria-label="Seznam majetku"] button:has-text("NAB-${ROK}-0003")`); await p.waitForTimeout(400);
  kontrola('karta položky s QR', (await p.locator('section[aria-label="QR štítek"] svg path').getAttribute('d') || '').length > 100);
  await p.click('section[aria-label="Co s položkou"] button:has-text("Přesunout")'); await p.waitForTimeout(300);
  await dlg(p).locator('button[aria-pressed]:has-text("Berušky")').click();
  await dlg(p).locator('button:has-text("Přesunout")').last().click(); await p.waitForTimeout(1500);
  kontrola('přesun do Berušek', sql(`select m.nazev from majetek x join mistnosti m on m.id = x.mistnost_id where cislo = 'NAB-${ROK}-0003'`) === 'Berušky');
  await p.click('section[aria-label="Co s položkou"] button:has-text("Nahlásit závadu")'); await p.waitForTimeout(300);
  await dlg(p).locator('textarea').fill('prasklá noha');
  await dlg(p).locator('button:has-text("Nahlásit")').last().click(); await p.waitForTimeout(1500);
  kontrola('závada: stav poškozeno + historie', sql(`select stav from majetek where cislo = 'NAB-${ROK}-0003'`) === 'poskozeno'
    && (await p.locator('section[aria-label="Historie"]').innerText()).includes('prasklá noha'));
  await p.click('button[aria-label="Zpět na seznam majetku"]'); await p.waitForTimeout(300);
  kontrola('závada je ve „Vyžaduje pozornost“', (await p.locator('section[aria-label="Vyžaduje pozornost"]').innerText()).includes('závada'));

  // tisk štítků
  await p.evaluate(() => { window.__tisk = ''; window.open = () => ({ document: { open() {}, write(h) { window.__tisk += h; }, close() {} }, focus() {}, print() {} }); });
  await p.click('button:has-text("Tisk štítků ·")'); await p.waitForTimeout(400);
  await p.click('section[aria-label="Nastavení tisku"] button:has-text("4 × 10")');
  await p.click('section[aria-label="Náhled archu"] button[aria-label^="Štítek 5,"]'); await p.waitForTimeout(200);
  kontrola('náhled: začátek na 5. štítku (4 použité)', (await p.locator('section[aria-label="Náhled archu"] button:has-text("použito")').count()) === 4);
  await p.click('button:has-text("Tisk / uložit PDF")'); await p.waitForTimeout(1500);
  const tisk = await p.evaluate(() => window.__tisk);
  kontrola('tisk: arch A4 4×10 s QR a čísly', tisk.includes('size:A4') && tisk.includes('repeat(4,52.5mm)') && (tisk.match(/<svg/g) || []).length === 3 && tisk.includes(`NAB-${ROK}-0001`), tisk.slice(0, 120));
  kontrola('štítky označené jako vytištěné', sql(`select count(*) from majetek where stitek_tisk is not null`) === '3');
  await p.click('button[aria-label="Zpět na majetek"]'); await p.waitForTimeout(300);

  // import ze staré evidence
  const csv = '﻿Inv. č.;Název;Umístění;Druh;Pořizovací cena;Datum pořízení;Ks\r\nT/1;Interaktivní tabule;Třída 1;elektro;46 800;2.9.2024;1\r\nL/1;Lehátko;sklep;textil;1150;2025;3\r\nX/9;Koberec;Třída 1;textil;;08/2023;1\r\n';
  await p.click('button:has-text("Import z Excelu")'); await p.waitForTimeout(300);
  await p.setInputFiles('#maj-import-soubor', { name: 'stara-evidence.csv', mimeType: 'text/csv', buffer: Buffer.from(csv) }); await p.waitForTimeout(800);
  const imp = () => p.locator('main');
  kontrola('import: poznané sloupce', (await imp().innerText()).includes('→ Původní číslo') && (await imp().innerText()).includes('→ Počet kusů'));
  const radek = (txt) => p.locator(`section[aria-label="${txt}"]`);
  await radek('Kategorie').locator('div:has(> span:has-text("„elektro“")) button:has-text("VYB")').click(); await p.waitForTimeout(150);
  await radek('Kategorie').locator('div:has(> span:has-text("„textil“")) button:has-text("TEX")').click(); await p.waitForTimeout(150);
  await radek('Místnosti').locator('div:has(> span:has-text("„Třída 1“")) button:has-text("Sluníčka")').click(); await p.waitForTimeout(150);
  await radek('Místnosti').locator('div:has(> span:has-text("„sklep“")) button:has-text("Sklad")').click(); await p.waitForTimeout(150);
  await p.click('button:has-text("Importovat 5 položek")'); await p.waitForTimeout(2500);
  kontrola('import: 5 kusů (lehátka rozdělená), čísla podle roku pořízení', sql(`select string_agg(cislo || '|' || puvodni_cislo, ',' order by cislo) from majetek where puvodni_cislo <> ''`)
    === 'TEX-2023-0001|X/9,TEX-2025-0001|L/1,TEX-2025-0002|L/1,TEX-2025-0003|L/1,VYB-2024-0001|T/1');
  kontrola('po importu je otevřený tisk štítků', (await p.locator('main').innerText()).includes('Tisk QR štítků'));
  await p.click('button[aria-label="Zpět na majetek"]'); await p.waitForTimeout(300);

  // inventura
  await p.click('[role=tab]:has-text("Inventury")'); await p.waitForTimeout(300);
  await p.click('button:has-text("Zahájit inventuru")'); await p.waitForTimeout(300);
  await pole(p, 'Inventarizační komise').fill('Ivana Pokorná, Hana Veselá');
  await dlg(p).locator('button:has-text("Zahájit")').last().click(); await p.waitForTimeout(1500);
  kontrola('inventura zahájena', sql(`select count(*) from inventury where uzavrena is null`) === '1' && (await p.locator('main').innerText()).includes('Rozdíly k vyřešení'));

  // učitelka Sluníček na tabletu
  const t = await stranka({ width: 1194, height: 834 });
  await prihlas(t, 'Třída', 'ucitelka@test.cz'); await t.waitForTimeout(1500);
  kontrola('tablet: záložka Inventura', (await t.locator('[role=tablist][aria-label="Části"]').innerText()).includes('Inventura'));
  await t.click('[role=tab]:has-text("Inventura")'); await t.waitForTimeout(400);
  kontrola('tablet: vidí jen majetek své místnosti', (await t.locator('section[aria-label="Majetek místnosti"]').innerText()).includes(`NAB-${ROK}-0001`) && !(await t.locator('section[aria-label="Majetek místnosti"]').innerText()).includes('Lehátko'));
  await t.fill('#mj-kod', `${URL}#majetek/NAB-${ROK}-0001`); await t.waitForTimeout(1500);
  kontrola('tablet: sken odkazu ze štítku = nalezeno', (await t.locator('section[aria-label="Skenování"]').innerText()).includes('Nalezeno'));
  await t.fill('#mj-kod', 'tex-2025-0002'); await t.click('section[aria-label="Skenování"] button:has-text("Zapsat")'); await t.waitForTimeout(1500);
  kontrola('tablet: věc z jiné místnosti = jinde', sql(`select z.vysledek from inventura_zaznamy z join majetek m on m.id = z.polozka_id where m.cislo = 'TEX-2025-0002'`) === 'jinde');
  await t.fill('#mj-bez', 'Koloběžka'); await t.click('section[aria-label="Skenování"] button:has-text("Zapsat") >> nth=1'); await t.waitForTimeout(1200);
  await t.click('button:has-text("Hotovo s místností")'); await t.click('[role=alertdialog] button:has-text("Hotovo")'); await t.waitForTimeout(1500);
  kontrola('tablet: místnost hotová, neoskenované chybí', sql(`select string_agg(m.cislo, ',' order by m.cislo) from inventura_zaznamy z join majetek m on m.id = z.polozka_id where z.vysledek = 'chybi'`) === `NAB-${ROK}-0002,TEX-2023-0001,VYB-2024-0001`);
  kontrola('tablet bez chyb', !t.chyby.length, t.chyby.join(' / '));

  // ředitelna dokončí ostatní místnosti skenem v dialogu
  await p.reload(); await p.waitForTimeout(2500);
  await p.click('nav button:has-text("Majetek")'); await p.waitForTimeout(1200); await p.click('[role=tab]:has-text("Inventura")'); await p.waitForTimeout(400);
  const mistnosti = await p.locator('section[aria-label="Místnosti"] button:has-text("Skenovat")').count();
  for (let i = 0; i < mistnosti; i++) {
    await p.locator('section[aria-label="Místnosti"] button:has-text("Skenovat")').first().click(); await p.waitForTimeout(300);
    const nazev = (await dlg(p).getAttribute('aria-label')) || '';
    if (nazev.includes('Berušky')) { await pole(p, 'Štítek').fill(`NAB-${ROK}-0003`); await p.waitForTimeout(1200); }
    await dlg(p).locator('button:has-text("Místnost hotová")').click(); await p.waitForTimeout(1500);
  }
  kontrola('všechny místnosti hotové', sql(`select count(*) from inventura_mistnosti where hotovo is null`) === '0');
  const rozdily = await p.locator('section[aria-label="Rozdíly k vyřešení"]').innerText();
  kontrola('rozdíly: chybí, jinde i bez štítku', /chybí/i.test(rozdily) && /jinde/i.test(rozdily) && rozdily.includes('Koloběžka'), rozdily.replace(/\n/g, ' | ').slice(0, 300));
  // vyřešit: jinde → přesunout, chybějící → ponechat / vyřadit, nález → zrušit
  await p.locator('section[aria-label="Rozdíly k vyřešení"] button:has-text("Přesunout sem")').first().click(); await p.waitForTimeout(1500);
  kontrola('jinde → přesunuto do Sluníček', sql(`select m.nazev from majetek x join mistnosti m on m.id = x.mistnost_id where cislo = 'TEX-2025-0002'`) === 'Sluníčka');
  await p.locator('section[aria-label="Rozdíly k vyřešení"] button:has-text("Vyřadit (manko)")').first().click(); await p.waitForTimeout(1500);
  for (let i = 0; i < 12 && await p.locator('section[aria-label="Rozdíly k vyřešení"] button:has-text("Ponechat")').count(); i++) { await p.locator('section[aria-label="Rozdíly k vyřešení"] button:has-text("Ponechat")').first().click(); await p.waitForTimeout(1200); }
  await p.locator('section[aria-label="Rozdíly k vyřešení"] button:has-text("Zrušit")').first().click(); await p.waitForTimeout(1500);
  kontrola('manko vyřazeno s důvodem', +sql(`select count(*) from majetek where stav = 'vyrazeno' and duvod_vyrazeni like 'Manko%'`) === 1);
  await p.evaluate(() => { window.__tisk = ''; window.open = () => ({ document: { open() {}, write(h) { window.__tisk += h; }, close() {} }, focus() {}, print() {} }); });
  await p.click('button:has-text("Inventurní soupis (PDF)")'); await p.waitForTimeout(800);
  kontrola('inventurní soupis k tisku', (await p.evaluate(() => window.__tisk)).includes('Inventurní soupis k'));
  await p.click('button:has-text("Uzavřít inventuru")'); await p.waitForTimeout(300);
  await dlg(p).locator('button:has-text("Uzavřít")').last().click(); await p.waitForTimeout(1500);
  kontrola('inventura uzavřena', sql(`select count(*) from inventury where uzavrena is not null`) === '1' && (await p.locator('main').innerText()).includes('Inventura teď neprobíhá'));
  kontrola('nalezené mají v historii inventuru', +sql(`select count(*) from majetek_pohyby where druh = 'inventura' and popis like 'Inventura k%nalezeno%'`) >= 2);

  // odkaz z QR štítku otevře kartu
  await p.goto(`${URL}#majetek/NAB-${ROK}-0001`); await p.waitForTimeout(3000);
  kontrola('odkaz ze štítku otevře kartu položky', (await p.locator('main').innerText()).includes(`NAB-${ROK}-0001`) && (await p.locator('section[aria-label="QR štítek"]').count()) === 1);
  kontrola('ředitelna bez chyb', !p.chyby.length, p.chyby.join(' / '));

  // práva
  kontrola('hospodářka vidí majetek', +sqlJako(HA, 'hospodarka@test.cz', 'select count(*) from majetek;') > 5);
  kontrola('učitelka vidí jen svou místnost', +sqlJako(UA, 'ucitelka@test.cz', 'select count(*) from majetek;') < +sql('select count(*) from majetek') && +sqlJako(UA, 'ucitelka@test.cz', 'select count(*) from majetek;') > 0);
  const pocet = sql('select count(*) from majetek');
  try { sqlJako(UA, 'ucitelka@test.cz', `select nova_polozka('{"nazev":"x","kategorie":"IT"}');`); } catch (e) { /* chyba je v pořádku */ }
  kontrola('učitelka nezaloží položku', sql('select count(*) from majetek') === pocet);
  kontrola('kuchařka, rodič a jiná školka nevidí nic', sqlJako(KA, 'kucharka@test.cz', 'select count(*) from majetek;') === '0' && sqlJako(RODA, '', 'select count(*) from majetek;') === '0' && sqlJako(RB, 'reditelka.b@test.cz', 'select count(*) from majetek;') === '0');
  try { sqlJako(RA, 'reditelka@test.cz', 'update majetek set cena = 1;'); } catch (e) { /* chyba je v pořádku */ }
  kontrola('přímý zápis do tabulky nejde', sql('select count(*) from majetek where cena = 1') === '0');
  await konec();
};
