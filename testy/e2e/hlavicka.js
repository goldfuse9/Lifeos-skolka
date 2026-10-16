// Hlavička a patička dokumentů: ředitelka nahraje logo v Nastavení, uloží se
// na server jako malý obrázek a objeví se vlevo nahoře na tisku porad,
// záznamu o úrazu i jídelníčku (kuchařka). Patička nese kontakty a datum.
const path = require('path');
const { sql, stranka, konec, prihlas, kontrola } = require('./spolecne');
const A = '00000000-0000-4000-8000-000000000001';
const zachytTisk = async (p, sel) => {
  await p.evaluate(() => { window.__tisk = ''; window.open = () => ({ document: { open() {}, write(h) { window.__tisk += h; }, close() {} }, focus() {}, print() {} }); });
  await p.click(sel); await p.waitForTimeout(700);
  return p.evaluate(() => window.__tisk);
};
module.exports = async () => {
  sql(`update skoly set logo = null, telefon = '220 000 111', email = 'skolka@test.cz' where id = '${A}'`);
  const p = await stranka({ width: 1366, height: 900 });
  await prihlas(p, 'Ředitelna', 'reditelka@test.cz'); await p.waitForTimeout(800);
  await p.click('nav button:has-text("Nastavení školky")'); await p.waitForTimeout(600);
  kontrola('nastavení: pole Logo školky, zatím bez loga', (await p.locator('body').innerText()).includes('bez loga'));
  await p.setInputFiles('input[aria-label="Nahrát logo školky"]', path.join(__dirname, 'data', 'logo-test.png')); await p.waitForTimeout(2000);
  const ulozene = sql(`select coalesce(length(logo), 0) || '|' || coalesce(left(logo, 22), '') from skoly where id = '${A}'`);
  const delka = +ulozene.split('|')[0];
  kontrola('logo uloženo na server jako malý PNG/JPEG', delka > 100 && delka <= 200000 && /^data:image\/(png|jpeg)/.test(ulozene.split('|')[1]), ulozene.slice(0, 60));
  kontrola('náhled loga v nastavení', await p.locator('img[alt="Logo školky"]').count() === 1);
  // tisk zápisu z porady
  sql(`insert into porady (skola_id, den, druh, program, pritomni) values ('${A}', current_date, 'Provozní porada', 'Kontrola hlavičky', '{}')`);
  await p.reload(); await prihlas(p, 'Ředitelna', 'reditelka@test.cz').catch(() => {}); await p.waitForTimeout(900);
  await p.click('nav button:has-text("Porady")'); await p.waitForTimeout(500);
  const tisk = await zachytTisk(p, 'article button:has-text("Tisk / PDF")');
  kontrola('tisk porady: logo vlevo nahoře v hlavičce', /<div class="hd"><img class="hd-logo" src="data:image\/(png|jpeg);base64,/.test(tisk));
  kontrola('tisk porady: patička s kontakty a datem', tisk.includes('class="ft"') && tisk.includes('220 000 111') && tisk.includes('skolka@test.cz') && tisk.includes('Vytištěno'));
  kontrola('tisk porady: hlavička a patička na každé stránce (thead/tfoot)', tisk.includes('<thead><tr><td><div class="hd-sp">') && tisk.includes('<tfoot><tr><td><div class="ft-sp">'));
  // dokument ke stažení
  await p.click('nav button:has-text("Dokumenty")'); await p.waitForTimeout(600);
  const stazeni = await p.evaluate(() => new Promise((res) => {
    const puv = URL.createObjectURL; URL.createObjectURL = (b) => { b.text().then(res); return puv.call(URL, b); };
    [...document.querySelectorAll('button')].filter((x) => x.textContent.trim() === 'Stáhnout').pop().click();
    setTimeout(() => res(''), 2000);
  }));
  kontrola('stažený dokument má hlavičku s logem a patičku', stazeni.includes('class="hd-logo"') && stazeni.includes('class="ft"'));
  kontrola('hlavička bez chyb na stránce', !p.chyby.length, p.chyby.join(' / '));
  // jídelníček kuchařky
  const k = await stranka();
  await prihlas(k, 'Jídelna', 'kucharka@test.cz'); await k.waitForTimeout(600);
  await k.click('nav button:has-text("Jídelníček")'); await k.waitForTimeout(500);
  const jid = await zachytTisk(k, 'button:has-text("Vytisknout na nástěnku")');
  kontrola('jídelníček: logo a kontakty školky v hlavičce/patičce', jid.includes('class="hd-logo"') && jid.includes('class="pata"') && jid.includes('220 000 111'));
  kontrola('jídelna bez chyb na stránce', !k.chyby.length, k.chyby.join(' / '));
  sql(`update skoly set logo = null where id = '${A}'`);
  await konec();
};
