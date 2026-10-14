// Účet: nové heslo z odkazu v e-mailu, blokace během práce, srozumitelné chyby.
const { URL, sql, stranka, konec, prihlas, hlaska, kontrola } = require('./spolecne');
const jwt = require('../lokalni/jwt.js');
const UB = 'bbbbbbbb-0000-4000-8000-000000000002';
module.exports = async () => {
  sql(`update auth.users set heslo = null where id = '${UB}'`);
  const p = await stranka({ width: 1194, height: 834 });
  await p.goto(`${URL}#access_token=${jwt(UB, 'ucitelka.b@test.cz')}&refresh_token=r-${UB}&expires_in=3600&token_type=bearer&type=recovery`); await p.waitForTimeout(1800);
  kontrola('odkaz „nové heslo“ otevře formulář nového hesla', (await p.locator('h1').textContent()) === 'Nové heslo', await hlaska(p));
  kontrola('e-mail je předvyplněný', (await p.locator('#prihlaseni-email').inputValue()) === 'ucitelka.b@test.cz');
  await p.fill('#prihlaseni-heslo', 'kratke'); await p.click('section[aria-label="Přihlášení"] >> button:has-text("Uložit nové heslo")'); await p.waitForTimeout(500);
  kontrola('krátké nové heslo odmítnuto', /8 znaků/.test(await hlaska(p)));
  await p.fill('#prihlaseni-heslo', 'noveheslo123'); await p.click('section[aria-label="Přihlášení"] >> button:has-text("Uložit nové heslo")'); await p.waitForTimeout(1500);
  kontrola('heslo změněno', /Heslo je změněné/.test(await hlaska(p)), await hlaska(p));
  const q = await stranka({ width: 1194, height: 834 });
  await prihlas(q, 'Třída', 'ucitelka.b@test.cz', 'stareheslo1');
  kontrola('staré heslo už neplatí', /nesedí/.test(await hlaska(q)));
  await prihlas(q, 'Třída', 'ucitelka.b@test.cz', 'noveheslo123');
  kontrola('nové heslo funguje', (await q.evaluate(() => location.hash)) === '#trida', await hlaska(q));
  // blokace během práce → po obnovení zpět na přihlášení s vysvětlením
  sql(`update uzivatele set aktivni = false where id = '${UB}'`);
  await q.reload(); await q.waitForTimeout(2500);
  kontrola('zablokovaný účet: po obnovení přihlášení s vysvětlením, bez technické chyby', (await q.evaluate(() => location.hash)) === '#prihlaseni' && /zablokovaný/.test(await hlaska(q)) && !(await q.locator('body').innerText()).includes('at '));
  kontrola('technické chyby česky', await q.evaluate(() => /oprávnění/.test(window.SkolkaServer.chyba({ message: 'new row violates row-level security policy for table "dochazka"' })) && !/unexpected/.test(window.SkolkaServer.chyba({ message: 'some unexpected internal failure' }))));
  kontrola('bez chyb JS', [p, q].every((x) => !x.chyby.length), [p, q].flatMap((x) => x.chyby).join('; '));
  await konec();
};
