// Dokumenty v ostrém provozu (ředitelna): úpravy textu jdou na server,
// schválení zvýší verzi a uloží znění do archivu, „zveřejnit na webu“
// se nenabízí (web zatím není napojený).
const { sql, stranka, konec, prihlas, kontrola } = require('./spolecne');
module.exports = async () => {
  const p = await stranka({ width: 1366, height: 900 });
  await prihlas(p, 'Ředitelna', 'reditelka@test.cz'); await p.waitForTimeout(800);
  await p.click('nav button:has-text("Dokumenty")'); await p.waitForTimeout(600);
  let telo = await p.locator('body').innerText();
  kontrola('dokumenty: stránka v ostrém provozu, školní řád neschválený', telo.includes('Školní řád') && telo.includes('zatím neschváleno'));
  kontrola('nenabízí „Zveřejnit na webu“', !(await p.locator('button:has-text("Zveřejnit na webu")').count()));
  const ed = p.locator('[contenteditable="true"]').first();
  await ed.click(); await p.keyboard.press('Control+End'); await p.keyboard.type(' Doplněno ředitelkou.'); await p.waitForTimeout(1800);
  kontrola('úprava textu uložena na server', sql(`select count(*) from dokumenty where klic='skolni-rad' and html like '%Doplněno ředitelkou.%'`) === '1');
  await p.click('button:has-text("Schválit")'); await p.waitForTimeout(1500);
  kontrola('schváleno: verze 1 a znění v archivu', sql(`select verze || '|' || (schvaleno is not null) from dokumenty where klic='skolni-rad'`) === '1|true'
    && sql(`select count(*) from dokumenty_verze where klic='skolni-rad' and verze=1 and html like '%Doplněno ředitelkou.%'`) === '1');
  await ed.click(); await p.keyboard.press('Control+End'); await p.keyboard.type(' Druhá úprava.'); await p.waitForTimeout(1800);
  kontrola('úprava po schválení se označí', sql(`select upraveno_po_schvaleni from dokumenty where klic='skolni-rad'`) === 't'
    && (await p.locator('button:has-text("Schválit novou verzi")').count()) === 1);
  await p.click('button:has-text("Schválit novou verzi")'); await p.waitForTimeout(1500);
  kontrola('druhé schválení: verze 2, archiv má obě', sql(`select verze from dokumenty where klic='skolni-rad'`) === '2' && sql(`select count(*) from dokumenty_verze where klic='skolni-rad'`) === '2');
  // po obnovení ze serveru
  await p.reload(); await prihlas(p, 'Ředitelna', 'reditelka@test.cz').catch(() => {}); await p.waitForTimeout(800);
  await p.click('nav button:has-text("Dokumenty")'); await p.waitForTimeout(600);
  telo = await p.locator('body').innerText();
  kontrola('po obnovení: verze 2 a upravený text', /verze 2/.test(telo) && (await ed.innerText()).includes('Druhá úprava.'));
  kontrola('dokumenty bez chyb na stránce', !p.chyby.length, p.chyby.join(' / '));
  await konec();
};
