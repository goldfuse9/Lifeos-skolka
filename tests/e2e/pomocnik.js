// Společné pomůcky pro E2E testy školky (Playwright + lokální Supabase).
const { chromium } = require('playwright');
const { execFileSync, spawnSync } = require('child_process');
const path = require('path');
const WEB = 'http://localhost:' + (process.env.WEB_PORT || 8801) + '/index.html';
const SUPA = 'http://localhost:' + (process.env.PROXY_PORT || 3102);
const DB = process.env.DB || 'skolka_test';
const HESLO = process.env.TEST_HESLO || 'Test-heslo-2026';
const OUT = path.join(__dirname, '..', 'vysledky');
require('fs').mkdirSync(OUT, { recursive: true });
const psqlArgs = ['-h', process.env.PGHOST || '/home/claude/.pgtest', '-p', process.env.PGPORT || '5499', '-U', 'postgres', '-d', DB, '-tAq'];
/** SQL jako správce databáze (jen ke kontrole výsledků). */
const sql = (q) => execFileSync('psql', psqlArgs.concat(['-c', q])).toString().trim();
/** SQL jako konkrétní testovací účet (RLS platí). */
const sqlJako = (email, q) => {
  const uid = sql(`select id from auth.users where email = '${email}'`);
  const r = spawnSync('psql', psqlArgs, { input: `set role authenticated;\nselect set_config('request.jwt.claim.sub','${uid}',false), set_config('request.jwt.claims','{"sub":"${uid}","email":"${email}"}',false) \\g /dev/null\n${q}\n` });
  return (r.stdout.toString() + r.stderr.toString()).trim();
};
const ucet = (k) => k + '@test.lifeos.cz';

let vysledky = [];
function over(nazev, podminka, detail) {
  vysledky.push({ nazev, ok: !!podminka, detail: detail === undefined ? '' : String(detail) });
  console.log((podminka ? 'PASS  ' : 'FAIL  ') + nazev + (detail !== undefined ? '  →  ' + detail : ''));
}

async function prohlizec() {
  return chromium.launch({ executablePath: process.env.CHROMIUM || '/opt/pw-browsers/chromium' });
}
/** Nový kontext napojený na lokální Supabase; sbírá chyby stránky. */
async function stranka(b, velikost, opts) {
  const ctx = await b.newContext({ viewport: velikost || { width: 1440, height: 900 }, serviceWorkers: 'block' });
  const supa = (opts && opts.supa) || SUPA;
  await ctx.route('**/config.js', (r) => r.fulfill({ contentType: 'text/javascript', body: `window.SKOLKA_SERVER = { url: '${supa}', key: 'test' };` }));
  await ctx.route('**/realtime/**', (r) => r.abort());
  await ctx.route(/fonts\.(googleapis|gstatic)\.com/, (r) => r.abort());
  const p = await ctx.newPage();
  p.chyby = [];
  p.on('pageerror', (e) => p.chyby.push('PAGEERROR ' + e.message));
  return p;
}
async function prihlas(p, oblast, email, heslo) {
  await p.goto(WEB + '#prihlaseni'); await p.waitForTimeout(1200);
  if (oblast) await p.click(`[aria-label="Kam se přihlásit"] button:has-text("${oblast}")`).catch(() => {});
  await p.fill('#prihlaseni-email', email); await p.fill('#prihlaseni-heslo', heslo || HESLO);
  await p.click('section[aria-label="Přihlášení"] >> button:has-text("Přihlásit")');
  await p.waitForTimeout(2500);
}
const hlaska = async (p) => (await p.locator('[role=status], [role=alert]').allTextContents()).join(' / ');
const hash = (p) => p.evaluate(() => location.hash);
async function snimek(p, jmeno) { await p.screenshot({ path: path.join(OUT, jmeno + '.png') }); }
function konec(nazev) {
  const f = vysledky.filter((v) => !v.ok).length;
  console.log(`---- ${nazev}: PASS ${vysledky.length - f} · FAIL ${f}`);
  const r = vysledky; vysledky = [];
  return r;
}
module.exports = { WEB, SUPA, DB, HESLO, OUT, sql, sqlJako, ucet, over, prohlizec, stranka, prihlas, hlaska, hash, snimek, konec };
