// Majetek ve zkušebním provozu (bez serveru): ukázková evidence, nová položka,
// inventura z ředitelny a skenování na tabletu — sdílený stav v prohlížeči.
const { stranka, konec, prihlas, kontrola } = require('./spolecne');
const SHOT = process.env.SHOT_DIR || '';
module.exports = async () => {
  const p = await stranka({ width: 1440, height: 900 }, true);
  await prihlas(p, 'Ředitelna', 'reditelka@ms-slunicko.cz', 'skolka');
  await p.click('nav button:has-text("Majetek")'); await p.waitForTimeout(600);
  const telo = await p.locator('main').innerText();
  kontrola('zkušební: ukázková evidence', telo.includes('Interaktivní tabule') && telo.includes('Vyžaduje pozornost'));
  await p.click('header button:has-text("+ Nová položka")'); await p.waitForTimeout(200);
  await p.locator('[role=dialog] label:has-text("Název") input').first().fill('Stavebnice Lego Duplo');
  await p.locator('[role=dialog] button:has-text("HRA · Hračky")').click();
  await p.locator('[role=dialog] button[aria-pressed]:has-text("Sluníčka")').click();
  await p.locator('[role=dialog] button:has-text("Uložit")').last().click(); await p.waitForTimeout(500);
  kontrola('zkušební: položka přidána', (await p.locator('main').innerText()).includes('Stavebnice Lego Duplo'));
  await p.click('[role=tab]:has-text("Inventury")'); await p.waitForTimeout(200);
  await p.click('button:has-text("Zahájit inventuru")'); await p.waitForTimeout(200);
  await p.locator('[role=dialog] button:has-text("Zahájit")').last().click(); await p.waitForTimeout(500);
  kontrola('zkušební: inventura běží', (await p.locator('main').innerText()).includes('Rozdíly k vyřešení'));
  const cislo = (await p.evaluate(() => (window.__skolka.maj.pol.filter((x) => x.nazev === 'Stavebnice Lego Duplo')[0] || {}).cislo)) || '';
  await p.waitForTimeout(500);
  const t = p; // zkušební provoz je jedno zařízení: tablet ve stejném prohlížeči
  await t.setViewportSize({ width: 1194, height: 834 });
  await prihlas(t, 'Třída', 'benesova@ms-slunicko.cz', 'skolka'); await t.waitForTimeout(800);
  kontrola('zkušební tablet: záložka Inventura', (await t.locator('[role=tablist][aria-label="Části"]').innerText()).includes('Inventura'));
  await t.click('[role=tab]:has-text("Inventura")'); await t.waitForTimeout(300);
  await t.fill('#mj-kod', cislo); await t.waitForTimeout(500);
  kontrola('zkušební tablet: sken = nalezeno', (await t.locator('section[aria-label="Skenování"]').innerText()).includes('Nalezeno'), cislo);
  if (SHOT) await t.screenshot({ path: SHOT + '/tablet-inventura.png' });
  await t.click('button:has-text("Skenovat kamerou")'); await t.waitForTimeout(500);
  kontrola('zkušební tablet: bez kamery poradí jinou cestu', /fotoaparátem|Kameru|Namiřte/.test(await t.locator('body').innerText()));
  await t.keyboard.press('Escape');
  kontrola('zkušební bez chyb', !p.chyby.filter((c) => !/getUserMedia|NotFound|NotAllowed/.test(c)).length, p.chyby.join(' / '));
  await konec();
};
