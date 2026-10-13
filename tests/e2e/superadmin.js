// Superadmin: školka → pozvánka ředitelky → registrace → aktivace → blokace.
const T = require('./pomocnik');
module.exports = async (b) => {
  const stamp = Date.now().toString(36), nazev = 'MŠ E2E ' + stamp, mail = 'red.' + stamp + '@e2e.test';
  const a = await T.stranka(b);
  await a.goto(T.WEB + '#admin'); await a.waitForTimeout(1200);
  T.over('admin: přihlašovací obrazovka „Správa LifeOS“', (await a.locator('h1').textContent()) === 'Správa LifeOS');
  await a.fill('#prihlaseni-email', T.ucet('superadmin')); await a.fill('#prihlaseni-heslo', 'spatne-heslo');
  await a.click('section[aria-label="Přihlášení"] >> button:has-text("Přihlásit")'); await a.waitForTimeout(1500);
  T.over('admin: špatné heslo odmítnuto', /nesedí|Invalid|neplatn/i.test(await T.hlaska(a)), await T.hlaska(a));
  await a.fill('#prihlaseni-heslo', T.HESLO);
  await a.click('section[aria-label="Přihlášení"] >> button:has-text("Přihlásit")'); await a.waitForTimeout(2500);
  T.over('admin: superadmin se přihlásí do #admin', (await T.hash(a)) === '#admin', await T.hash(a));
  await a.click('button:has-text("Přidat školku")');
  await a.click('[role=dialog][aria-label="Nová školka"] button:has-text("Založit školku")'); await a.waitForTimeout(600);
  T.over('admin: školka bez názvu se nezaloží', /název/i.test(await a.locator('[role=dialog] [role=alert]').textContent().catch(() => '')));
  await a.fill('#nova-nazev', nazev); await a.fill('#nova-izo', '9' + stamp.slice(-6));
  await a.click('[role=dialog][aria-label="Nová školka"] button:has-text("Založit školku")'); await a.waitForTimeout(1500);
  T.over('admin: školka založena ve stavu „čeká“', T.sql(`select stav from skoly where nazev = '${nazev}'`) === 'ceka');
  await a.fill('[aria-label="Jméno ředitelky"]', 'Jana E2E'); await a.fill('[aria-label="E-mail ředitelky"]', mail);
  await a.click('button:has-text("Vytvořit pozvánku")'); await a.waitForTimeout(1500);
  const kod = (await a.locator('[role=dialog][aria-label="Pozvánka"] span').nth(3).textContent()).trim();
  T.over('admin: kód pozvánky ve tvaru ABCD-EFGH', /^[A-Z0-9]{4}-[A-Z0-9]{4}$/.test(kod), kod);
  await T.snimek(a, 'superadmin-kod');
  await a.click('[role=dialog][aria-label="Pozvánka"] button:has-text("Hotovo")');

  const r = await T.stranka(b);
  await r.goto(T.WEB + '#prihlaseni'); await r.waitForTimeout(1200);
  T.over('přihlášení: v ostrém provozu bez „heslo skolka“', !(await r.locator('body').innerText()).includes('heslo skolka'));
  await r.click('button:has-text("Mám pozvánku")');
  await r.fill('#prihlaseni-email', mail); await r.fill('#prihlaseni-heslo', 'kratke'); await r.fill('#prihlaseni-kod', kod);
  await r.click('section[aria-label="Přihlášení"] >> button:has-text("Vytvořit")'); await r.waitForTimeout(1200);
  T.over('pozvánka: krátké heslo odmítnuto', /8 znaků/.test(await T.hlaska(r)), await T.hlaska(r));
  await r.fill('#prihlaseni-heslo', 'dlouhe-heslo-123'); await r.fill('#prihlaseni-kod', 'XXXX-YYYY');
  await r.click('section[aria-label="Přihlášení"] >> button:has-text("Vytvořit")'); await r.waitForTimeout(2000);
  T.over('pozvánka: špatný kód odmítnut', /neplatí/.test(await T.hlaska(r)), await T.hlaska(r));
  await r.fill('#prihlaseni-kod', kod);
  await r.click('section[aria-label="Přihlášení"] >> button:has-text("Vytvořit")'); await r.waitForTimeout(3000);
  T.over('pozvánka: ředitelka skončí v Ředitelně', (await T.hash(r)) === '#reditel', await T.hash(r));
  T.over('pozvánka: školka se aktivovala', T.sql(`select stav from skoly where nazev = '${nazev}'`) === 'aktivni');
  T.over('ředitelna: hlavička ukazuje skutečnou školku', (await r.locator('nav[aria-label="Ředitelna"]').innerText()).includes(nazev));
  T.over('pozvánka: kód podruhé nejde použít', /ERROR/.test(T.sqlJako(mail, `select prijmi_pozvanku('${kod}');`)))

  await a.reload(); await a.waitForTimeout(2500);
  await a.click(`button:has-text("${nazev}")`); await a.waitForTimeout(400);
  await a.click('aside[aria-label="Detail školky"] button:has-text("Blokovaná")'); await a.waitForTimeout(1500);
  T.over('admin: školka zablokována', T.sql(`select stav from skoly where nazev = '${nazev}'`) === 'blokovana');
  const r2 = await T.stranka(b);
  await T.prihlas(r2, 'Ředitelna', mail, 'dlouhe-heslo-123');
  T.over('blokace: ředitelka blokované školky se nepřihlásí', (await T.hash(r2)) === '#prihlaseni' && /pozastaven/.test(await T.hlaska(r2)), await T.hlaska(r2));
  await r2.goto(T.WEB + '#admin'); await r2.waitForTimeout(1500);
  T.over('ředitelka se nedostane do #admin', (await T.hash(r2)) !== '#admin' || (await r2.locator('h1').textContent()) === 'Správa LifeOS');
  T.over('bez chyb v konzoli', !a.chyby.length && !r.chyby.length, a.chyby.concat(r.chyby).join(' | '));
  return T.konec('superadmin');
};
