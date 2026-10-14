// Učitelé v ostrém provozu (ředitelna): seznam jde ze serveru, lokální
// prvky (úvazek, telefon, úprava profilu, dnešní nepřítomnost) se neukazují
// a přidání učitele vede do Přístupů, kde se pozvánka skutečně odešle.
const { sql, stranka, konec, prihlas, kontrola } = require('./spolecne');
module.exports = async () => {
  const jmeno = sql(`select jmeno from uzivatele where email='ucitelka@test.cz'`).trim();
  const r = await stranka({ width: 1194, height: 834 });
  await prihlas(r, 'Ředitelna', 'reditelka@test.cz'); await r.waitForTimeout(800);
  await r.click('nav button:has-text("Učitelé")'); await r.waitForTimeout(500);
  let telo = await r.locator('body').innerText();
  kontrola('učitelé: učitelka ze serveru je v seznamu', !!jmeno && telo.includes(jmeno.split(' ')[0]), jmeno);
  kontrola('učitelé: bez úpravy profilu a úvazků', !(await r.locator('button:has-text("Upravit profil")').count()) && !telo.includes('Úvazek'));
  kontrola('učitelé: bez přepínače „Dnes chybí“', !(await r.locator('button:has-text("Dnes ve školce"), button:has-text("Dnes chybí")').count()));
  kontrola('učitelé: tlačítko vede k pozvánce zaměstnance', (await r.locator('button:has-text("+ Pozvat zaměstnance")').count()) === 1);
  await r.click('button:has-text("+ Pozvat zaměstnance")'); await r.waitForTimeout(600);
  const aktivni = await r.locator('nav button[aria-current="page"]').innerText();
  kontrola('tlačítko přepne do Přístupů', /Přístupy/.test(aktivni), aktivni.replace(/\n/g, ' '));
  kontrola('učitelé: bez chyb na stránce', !r.chyby.length, r.chyby.join(' / '));
  await konec();
};
