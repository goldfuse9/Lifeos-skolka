// Pozvánka při zapnutém potvrzování e-mailu (výchozí Supabase): vlastní proxy s CONFIRM=1.
const T = require('./pomocnik');
const { spawn } = require('child_process');
const path = require('path');
module.exports = async (b) => {
  const port = +(process.env.PROXY_PORT || 3102) + 10;
  const px = spawn('node', [path.join(__dirname, '..', 'lokalni-supabase', 'proxy.js')], { env: Object.assign({}, process.env, { PROXY_PORT: port, CONFIRM: '1', DB: T.DB }), stdio: 'ignore' });
  await new Promise((r) => setTimeout(r, 800));
  try {
    const mail = 'c.' + Date.now().toString(36) + '@e2e.test';
    const kod = T.sqlJako(T.ucet('reditelka.a'), `select pozvi_zamestnance('Klára Potvrzená', '${mail}', 'ucitelka', 'eeeeeeee-0000-4000-8000-0000000000a1');`);
    const p = await T.stranka(b, { width: 1194, height: 834 }, { supa: 'http://localhost:' + port });
    await p.goto(T.WEB + '#prihlaseni'); await p.waitForTimeout(1200);
    await p.click('button:has-text("Mám pozvánku")');
    await p.fill('#prihlaseni-email', mail); await p.fill('#prihlaseni-heslo', 'heslo12345'); await p.fill('#prihlaseni-kod', kod);
    await p.click('section[aria-label="Přihlášení"] >> button:has-text("Vytvořit")'); await p.waitForTimeout(2000);
    T.over('registrace → výzva k potvrzení e-mailu', /Poslali jsme vám e-mail/.test(await T.hlaska(p)), await T.hlaska(p));
    await p.click('section[aria-label="Přihlášení"] >> button:has-text("Vytvořit")'); await p.waitForTimeout(2000);
    T.over('bez potvrzení znovu → „ještě není potvrzený“', /není potvrzený/.test(await T.hlaska(p)), await T.hlaska(p));
    T.sql(`update auth.users set potvrzeno = true where email = '${mail}'`);
    await p.click('section[aria-label="Přihlášení"] >> button:has-text("Vytvořit")'); await p.waitForTimeout(3500);
    T.over('po potvrzení → tablet třídy', (await T.hash(p)) === '#trida', (await T.hash(p)) + ' ' + (await T.hlaska(p)));
    const q = await T.stranka(b, null, { supa: 'http://localhost:' + port });
    await q.goto(T.WEB + '#prihlaseni'); await q.waitForTimeout(1200);
    await q.click('button:has-text("Mám pozvánku")'); await q.fill('#prihlaseni-email', mail); await q.fill('#prihlaseni-heslo', 'jine-heslo-99'); await q.fill('#prihlaseni-kod', kod);
    await q.click('section[aria-label="Přihlášení"] >> button:has-text("Vytvořit")'); await q.waitForTimeout(2000);
    T.over('existující účet + špatné heslo → srozumitelná hláška', /heslo nesedí/.test(await T.hlaska(q)), await T.hlaska(q));
    const z = await T.stranka(b, null, { supa: 'http://localhost:' + port });
    await z.goto(T.WEB + 'x'.slice(1) + '#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired'); await z.waitForTimeout(1500);
    T.over('propadlý odkaz z e-mailu → vysvětlení', /už neplatí/.test(await T.hlaska(z)), await T.hlaska(z));
  } finally { px.kill(); }
  return T.konec('pozvanka-potvrzeni');
};
