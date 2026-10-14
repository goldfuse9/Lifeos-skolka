// Superadmin: založí školku, pozve ředitelku, ta se zaregistruje kódem,
// školka se aktivuje; blokace školky zabrání přihlášení; ředitelka nesmí do #admin.
const { URL, sql, stranka, konec, prihlas, hlaska, kontrola, souhrn } = require('./spolecne');
module.exports = async () => {
  const s = Date.now().toString(36), mail = 'red.' + s + '@test.cz', nazev = 'MŠ E2E ' + s;
  const a = await stranka();
  await a.goto(URL + '#admin'); await a.waitForTimeout(1200);
  await a.fill('#prihlaseni-email', 'roman@lifeos.cz'); await a.fill('#prihlaseni-heslo', 'heslo12345');
  await a.click('section[aria-label="Přihlášení"] >> button:has-text("Přihlásit")'); await a.waitForTimeout(2500);
  kontrola('superadmin se dostane do #admin', (await a.evaluate(() => location.hash)) === '#admin');
  await a.click('button:has-text("Přidat školku")');
  await a.fill('#nova-nazev', nazev); await a.fill('#nova-izo', '9' + s.slice(-6));
  await a.click('[role=dialog][aria-label="Nová školka"] button:has-text("Založit školku")'); await a.waitForTimeout(1500);
  kontrola('školka založena jako „čeká“', sql(`select stav from skoly where nazev='${nazev}'`) === 'ceka');
  await a.fill('[aria-label="Jméno ředitelky"]', 'Jana E2E'); await a.fill('[aria-label="E-mail ředitelky"]', mail);
  await a.click('button:has-text("Vytvořit pozvánku")'); await a.waitForTimeout(1500);
  const kod = (await a.locator('[role=dialog][aria-label="Pozvánka"] span').nth(3).textContent()).trim();
  kontrola('kód pozvánky ve tvaru ABCD-EFGH', /^[A-Z0-9]{4}-[A-Z0-9]{4}$/.test(kod), kod);
  await a.click('[role=dialog][aria-label="Pozvánka"] button:has-text("Hotovo")');

  const r = await stranka();
  await r.goto(URL + '#prihlaseni'); await r.waitForTimeout(1200);
  await r.click('button:has-text("Mám pozvánku")');
  await r.fill('#prihlaseni-email', mail); await r.fill('#prihlaseni-heslo', 'kratke'); await r.fill('#prihlaseni-kod', kod);
  await r.click('section[aria-label="Přihlášení"] >> button:has-text("Vytvořit")'); await r.waitForTimeout(1200);
  kontrola('krátké heslo odmítnuto', /8 znaků/.test(await hlaska(r)));
  await r.fill('#prihlaseni-heslo', 'heslo12345'); await r.fill('#prihlaseni-kod', 'XXXX-YYYY');
  await r.click('section[aria-label="Přihlášení"] >> button:has-text("Vytvořit")'); await r.waitForTimeout(1800);
  kontrola('špatný kód odmítnut', /neplatí/.test(await hlaska(r)));
  await r.fill('#prihlaseni-kod', kod);
  await r.click('section[aria-label="Přihlášení"] >> button:has-text("Vytvořit")'); await r.waitForTimeout(3000);
  kontrola('ředitelka v ředitelně', (await r.evaluate(() => location.hash)) === '#reditel');
  kontrola('hlavička ukazuje novou školku', (await r.locator('nav[aria-label="Ředitelna"]').innerText()).includes(nazev));
  kontrola('školka aktivní po přijetí', sql(`select stav from skoly where nazev='${nazev}'`) === 'aktivni');
  kontrola('kód nejde použít podruhé', sql(`select prijato is not null from pozvanky where email='${mail}'`) === 't');

  await a.reload(); await a.waitForTimeout(2500);
  await a.click(`button:has-text("${nazev}")`);
  await a.click('aside[aria-label="Detail školky"] button:has-text("Blokovaná")'); await a.waitForTimeout(1500);
  kontrola('blokace uložena', sql(`select stav from skoly where nazev='${nazev}'`) === 'blokovana');
  const r2 = await stranka();
  await prihlas(r2, 'Ředitelna', mail);
  kontrola('blokovaná školka: přihlášení odmítnuto', /pozastaven/.test(await hlaska(r2)) && (await r2.evaluate(() => location.hash)) === '#prihlaseni');
  await r.goto(URL + '#admin'); await r.waitForTimeout(1800);
  kontrola('ředitelka nesmí do #admin', (await r.evaluate(() => location.hash)) !== '#admin');
  kontrola('bez chyb JS', [a, r, r2].every((p) => !p.chyby.length), [a, r, r2].flatMap((p) => p.chyby).join('; '));
  await konec();
};
