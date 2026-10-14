// Společné pomůcky pro E2E testy školky proti lokální náhradě Supabase.
// Proměnné: TEST_DB, PROXY_PORT, WEB_PORT (výchozí skolka_lokal, 3002, 8767).
const { chromium } = require('playwright');
const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const DB = process.env.TEST_DB || 'skolka_lokal';
const PROXY = process.env.PROXY_PORT || '3002';
const WEB = process.env.WEB_PORT || '8767';
const URL = `http://localhost:${WEB}/index.html`;
const PGH = process.env.PGHOST_TEST || '/home/claude/.pgtest', PGP = process.env.PGPORT_TEST || '5499';
const VYSL = path.join(__dirname, '..', 'vysledky'); fs.mkdirSync(VYSL, { recursive: true });

/** SQL jako správce databáze (jen ověření výsledků v testech). */
const sql = (q) => execSync(`psql -h ${PGH} -p ${PGP} -U postgres -d ${DB} -tAq`, { input: q + '\n' }).toString().trim();
/** SQL jako konkrétní přihlášená identita (RLS platí). */
const sqlJako = (uid, email, q) => sql(`set role authenticated;\nselect set_config('request.jwt.claim.sub','${uid}',false), set_config('request.jwt.claims','{"sub":"${uid}","email":"${email || ''}"}',false) \\g /dev/null\n${q}`);

let prohlizec = null;
async function stranka(rozmer = { width: 1440, height: 900 }, zkusebni = false) {
  prohlizec = prohlizec || await chromium.launch({ executablePath: process.env.CHROMIUM || '/opt/pw-browsers/chromium' });
  const ctx = await prohlizec.newContext({ viewport: rozmer, serviceWorkers: 'block' });
  // config.js → lokální proxy (NIKDY skutečný Supabase projekt)
  // zkušební provoz = bez serveru (ukázková data v prohlížeči)
  await ctx.route('**/config.js', (r) => r.fulfill({ contentType: 'text/javascript', body: zkusebni ? '/* zkušební provoz */' : `window.SKOLKA_SERVER = { url: 'http://localhost:${PROXY}', key: 'lokalni-test' };` }));
  await ctx.route('**/realtime/**', (r) => r.abort());
  await ctx.route(/fonts\.(googleapis|gstatic)\.com/, (r) => r.abort());
  const p = await ctx.newPage();
  p.chyby = []; p.http = [];
  p.on('pageerror', (e) => p.chyby.push('PAGEERROR ' + e.message));
  // chyby v konzoli aplikace (bez šumu testovacího prostředí: písma, SW, realtime, načítání zdrojů)
  p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|ERR_|fonts|Service Worker|realtime|WebSocket/i.test(m.text())) p.chyby.push('CONSOLE ' + m.text().slice(0, 200)); });
  p.on('response', (r) => { if (r.status() >= 500 && /\/rest\/v1|\/auth\/v1/.test(r.url())) p.chyby.push('HTTP ' + r.status() + ' ' + r.url().split('/v1/')[1]); else if (r.status() >= 400 && /\/rest\/v1/.test(r.url())) p.http.push(r.status() + ' ' + r.url().split('/v1/')[1]); });
  return p;
}
async function konec() { if (prohlizec) await prohlizec.close(); prohlizec = null; }

async function prihlas(p, oblast, email, heslo = 'heslo12345') {
  await p.goto(URL + '#prihlaseni'); await p.waitForTimeout(1200);
  if (oblast) await p.click(`[aria-label="Kam se přihlásit"] button:has-text("${oblast}")`);
  await p.fill('#prihlaseni-email', email); await p.fill('#prihlaseni-heslo', heslo);
  await p.click('section[aria-label="Přihlášení"] >> button:has-text("Přihlásit")'); await p.waitForTimeout(2500);
}
const hlaska = async (p) => (await p.locator('[role=status], [role=alert]').allTextContents()).join(' / ');

/** Mini běhová kostra: kontrola(nazev, podminka, detail) → PASS/FAIL. */
const vysledky = [];
function kontrola(nazev, ok, detail = '') { vysledky.push({ nazev, ok: !!ok, detail }); console.log((ok ? 'PASS  ' : 'FAIL  ') + nazev + (detail ? '  →  ' + detail : '')); }
const souhrn = () => { const ko = vysledky.filter((v) => !v.ok).length; console.log(`---- ${vysledky.length - ko} PASS, ${ko} FAIL`); return ko; };

module.exports = { DB, URL, VYSL, sql, sqlJako, stranka, konec, prihlas, hlaska, kontrola, souhrn };
