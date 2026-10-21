// Zkušební provoz (bez serveru) dál funguje: ukázková data, hesla „skolka“, ukládání v prohlížeči.
const { stranka, konec, prihlas, kontrola } = require('./spolecne');
module.exports = async () => {
  const r = await stranka(undefined, true);
  await prihlas(r, 'Ředitelna', 'reditelka@ms-slunicko.cz', 'skolka');
  kontrola('zkušební ředitelna se otevře', (await r.evaluate(() => location.hash)) === '#reditel');
  const nav = await r.locator('nav[aria-label="Ředitelna"]').innerText();
  kontrola('zkušební provoz: všechny stránky (Platby, Matrika…)', /Platby/.test(nav) && /Matrika/.test(nav) && /Zkušební provoz/.test(nav));
  for (const n of ['Kartotéka dětí', 'Platby', 'Matrika MŠMT', 'Kniha úrazů', 'Zdraví a léky', 'Dokumenty', 'Nastavení školky']) { await r.click(`nav button:has-text("${n}")`); await r.waitForTimeout(300); }
  await r.waitForTimeout(600);
  kontrola('zkušební provoz ukládá do prohlížeče', await r.evaluate(() => !!localStorage.getItem('skolka-reditel-v1')));
  const t = await stranka({ width: 1194, height: 834 }, true);
  await prihlas(t, 'Třída', 'benesova@ms-slunicko.cz', 'skolka');
  kontrola('zkušební tablet se otevře', (await t.evaluate(() => location.hash)) === '#trida');
  const j = await stranka(undefined, true);
  await prihlas(j, 'Jídelna', 'dvorakova@ms-slunicko.cz', 'skolka');
  kontrola('zkušební jídelna se otevře', (await j.evaluate(() => location.hash)) === '#jidelna');
  kontrola('bez chyb JS', [r, t, j].every((p) => !p.chyby.length), [r, t, j].flatMap((p) => p.chyby).join('; '));
  await konec();
};
