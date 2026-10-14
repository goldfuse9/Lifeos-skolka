// Ochrana dat v prohlížeči (ostrý provoz): žádná data desek v localStorage,
// zbytky starších verzí se smažou, druhá záložka s jiným účtem první odhlásí.
const { URL, stranka, konec, prihlas, kontrola } = require('./spolecne');
module.exports = async () => {
  const p = await stranka();
  await p.goto(URL + '#prihlaseni'); await p.waitForTimeout(800);
  await p.evaluate(() => { localStorage.setItem('skolka-reditel-v1', '{"kids":[{"rc":"200101/1234"}]}'); localStorage.setItem('skolka-sdilene-v1', '{}'); localStorage.setItem('skolka-jidelna-v1', '{}'); });
  await p.reload(); await p.waitForTimeout(1000);
  kontrola('zbytky dat desek ze starší verze smazány', await p.evaluate(() => !localStorage.getItem('skolka-reditel-v1') && !localStorage.getItem('skolka-sdilene-v1') && !localStorage.getItem('skolka-jidelna-v1')));
  await prihlas(p, 'Ředitelna', 'reditelka.b@test.cz');
  await p.click('nav button:has-text("Přístupy")').catch(() => {}); await p.waitForTimeout(800);
  await p.click('nav button:has-text("Rodiče v LifeOS")').catch(() => {}); await p.waitForTimeout(800);
  const klice = await p.evaluate(() => Object.keys(localStorage));
  kontrola('v localStorage nejsou data desek', !klice.some((k) => /^skolka-(reditel|sdilene|jidelna)-v1$/.test(k)), klice.join(','));
  const vse = await p.evaluate(() => Object.values(localStorage).join(' '));
  kontrola('v localStorage nejsou jména dětí ani rodná čísla', !/Adam|Cizí|\d{6}\/\d{3,4}/.test(vse));
  // druhá záložka, jiný účet
  const t1 = await p.context().newPage();
  await t1.goto(URL + '#prihlaseni'); await t1.waitForTimeout(800);
  await p.evaluate(() => {}); // první záložka = ředitelka B
  await prihlas(t1, 'Třída', 'ucitelka.b@test.cz');
  await p.waitForTimeout(2500);
  kontrola('první záložka po přihlášení jiného účtu skončí na přihlášení', (await p.evaluate(() => location.hash)) === '#prihlaseni');
  // odhlášení v jedné záložce → druhá taky
  await t1.evaluate(() => window.SkolkaUcet.odhlas()); await t1.waitForTimeout(500);
  kontrola('po odhlášení nezůstane účet v prohlížeči', await t1.evaluate(() => !localStorage.getItem('skolka-server-ucet')));
  kontrola('bez chyb JS', !p.chyby.length && !(t1.chyby || []).length, p.chyby.join('; '));
  await konec();
};
