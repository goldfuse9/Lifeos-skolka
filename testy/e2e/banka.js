// Platby z banky (Fio API) a QR platba pro rodiče.
// Potřebuje běžící Edge Function banka-sync a napodobené Fio API — spustí je
// testy/lokalni/banka.sh (bez nich se test přeskočí). Fio token „DOBRY…“ vrací
// pohyby, jiný token chybu.
const http = require('http');
const { sql, sqlJako, stranka, konec, prihlas, kontrola } = require('./spolecne');
const EMA = '00000000-0000-4000-8000-000000000101', OLI = '00000000-0000-4000-8000-000000000102';
const RA = 'aaaaaaaa-0000-4000-8000-000000000001', ROD_EMA = 'aaaaaaaa-0000-4000-8000-000000000003', ROD_OLI = 'aaaaaaaa-0000-4000-8000-000000000008';
const bezi = (port) => new Promise((ok) => { const r = http.request({ host: '127.0.0.1', port, method: 'OPTIONS', path: '/' }, () => ok(true)); r.on('error', () => ok(false)); r.end(); });

module.exports = async () => {
  if (!(await bezi(+(process.env.FUNCTIONS_PORT || 8000)))) { console.log('SKIP  banka: Edge Function neběží (testy/lokalni/banka.sh)'); return; }
  const pM = sql(`select to_char(date_trunc('month', current_date) - interval '1 month', 'YYYY-MM')`);
  sqlJako(RA, 'reditelka@test.cz', `select vystav_predpisy('${pM}');`);

  const p = await stranka({ width: 1366, height: 900 });
  await prihlas(p, 'Ředitelna', 'reditelka@test.cz'); await p.waitForTimeout(800);
  await p.click('nav button:has-text("Platby")'); await p.waitForTimeout(800);
  const panel = p.locator('section[aria-label="Platby z banky"]');
  kontrola('panel Platby z banky: nenapojeno', (await panel.innerText()).includes('nenapojeno'));

  // napojení banky
  await panel.locator('button:has-text("Napojit")').click(); await p.waitForTimeout(300);
  const d = p.locator('[role=dialog]');
  await d.locator('input[type=password]').fill('kratky');
  kontrola('krátký token neprojde', (await d.innerText()).includes('nevypadá správně'));
  await d.locator('input[type=password]').fill('DOBRYtokenAbCdEfGhIjKlMnOpQrStUvWx0123456789abcdefghijKLMNOP');
  await d.locator('button:has-text("Uložit")').click(); await p.waitForTimeout(1500);
  kontrola('token uložen v databázi', sql(`select aktivni || '|' || right(token, 4) from banka_napojeni where skola_id = '00000000-0000-4000-8000-000000000001'`) === 'true|MNOP');
  kontrola('token nejde z aplikace přečíst', (() => { try { return sqlJako(RA, 'reditelka@test.cz', 'select token from banka_napojeni;') === ''; } catch (e) { return true; } })());
  kontrola('panel ukazuje konec tokenu', (await panel.innerText()).includes('…MNOP'));

  // stažení z banky tlačítkem
  await panel.locator('button:has-text("Načíst platby z banky teď")').click(); await p.waitForTimeout(3000);
  kontrola('z banky načteny 3 příchozí platby (bez odchozí, úroku a eur)', sql(`select count(*) from platby where zdroj = 'api'`) === '3');
  kontrola('Ema zaplaceno podle VS', sql(`select stav from predpisy where dite_id = '${EMA}' and obdobi = '${pM}'`) === 'zaplaceno');
  kontrola('Oliver částečně — VS jen ve zprávě pro příjemce', sql(`select stav from predpisy where dite_id = '${OLI}' and obdobi = '${pM}'`) === 'castecne_zaplaceno');
  const txt = await panel.innerText();
  kontrola('panel ukazuje výsledek', txt.includes('2 spárováno') && txt.includes('1 ručně'), txt.replace(/\n/g, ' | '));
  kontrola('neznámá platba čeká na ruční přiřazení', (await p.locator('section[aria-label="Nespárované platby"]').innerText()).includes('999999'));

  // znovu — nic se nezdvojí
  await panel.locator('button:has-text("Načíst platby z banky teď")').click(); await p.waitForTimeout(3000);
  kontrola('opakované stažení nic nezdvojí', sql(`select count(*) from platby`) === '3');

  // QR pro rodiče
  const qrOli = sqlJako(ROD_OLI, '', `select qr from moje_platby();`);
  kontrola('rodič Olivera má QR na zbytek 400 Kč', /^SPD\*1\.0\*ACC:CZ\d{22}\*AM:400\.00\*CC:CZK\*X-VS:250002\*/.test(qrOli), qrOli);
  kontrola('rodič Emy nemá co platit', sqlJako(ROD_EMA, '', `select coalesce(qr, '-') || '|' || k_uhrade from moje_platby();`) === '-|0');
  kontrola('rodič nevidí stav banky', sqlJako(ROD_OLI, '', `select coalesce(stav_napojeni_banky()::text, '-');`) === '-');

  // kdo smí funkci banka-sync spustit (přímo, bez ředitelny)
  const crypto = require('crypto'), b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const podpis = (pl) => { const h = b64({ alg: 'HS256', typ: 'JWT' }), q = b64(Object.assign({ exp: Math.floor(Date.now() / 1000) + 3600 }, pl)); return h + '.' + q + '.' + crypto.createHmac('sha256', 'tajny-testovaci-klic-pro-postgrest-0123456789').update(h + '.' + q).digest('base64url'); };
  const zavolej = (hl) => new Promise((ok) => {
    const r = http.request({ host: '127.0.0.1', port: +(process.env.PROXY_PORT || 3002), method: 'POST', path: '/functions/v1/banka-sync', headers: Object.assign({ 'Content-Type': 'application/json' }, hl) }, (res) => { let t = ''; res.on('data', (c) => (t += c)); res.on('end', () => ok({ s: res.statusCode, t })); });
    r.on('error', (e) => ok({ s: 0, t: String(e) })); r.end('{}');
  });
  const jako = (uid, role) => ({ Authorization: 'Bearer ' + podpis(uid ? { sub: uid, role: 'authenticated' } : { role: role || 'anon' }) });
  kontrola('funkce bez přihlášení: 401', (await zavolej({})).s === 401);
  kontrola('funkce se špatným heslem cronu: 401', (await zavolej({ 'x-cron-secret': 'hadam' })).s === 401);
  kontrola('funkce s veřejným klíčem (anon): 403', (await zavolej(jako(null, 'anon'))).s === 403);
  kontrola('funkce jako rodič: 403', (await zavolej(jako(ROD_EMA))).s === 403);
  kontrola('funkce jako učitelka: 403', (await zavolej(jako('aaaaaaaa-0000-4000-8000-000000000002'))).s === 403);
  kontrola('funkce s podvrženým podpisem: 403', (await zavolej({ Authorization: 'Bearer ' + podpis({ sub: RA, role: 'authenticated' }).slice(0, -4) + 'AAAA' })).s === 403);
  const cron = await zavolej({ 'x-cron-secret': 'lokalni-cron' });
  kontrola('cron se správným heslem projde všechny napojené školky', cron.s === 200 && /"skolek":1/.test(cron.t), cron.t.slice(0, 120));
  kontrola('odpověď funkce neobsahuje token', !cron.t.includes('DOBRYtoken'));

  // vypnutí
  await panel.locator('button:has-text("Upravit")').click(); await p.waitForTimeout(300);
  await d.locator('button:has-text("Vypnuto")').click();
  await d.locator('button:has-text("Uložit")').click(); await p.waitForTimeout(1500);
  kontrola('vypnuto, token zůstal', sql(`select aktivni || '|' || right(token, 4) from banka_napojeni`) === 'false|MNOP');
  kontrola('vypnuté napojení nemá tlačítko', !(await panel.locator('button:has-text("Načíst platby z banky teď")').count()));
  await konec();
};
