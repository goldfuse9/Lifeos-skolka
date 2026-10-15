// Nastavení školky v ostrém provozu: údaje školy jdou na server (a do
// dokumentů), platby a VS přes funkci, zkušební „ukázková data“ se nenabízí.
const { sql, stranka, konec, prihlas, kontrola } = require('./spolecne');
const A = '00000000-0000-4000-8000-000000000001';
module.exports = async () => {
  const p = await stranka({ width: 1366, height: 900 });
  await prihlas(p, 'Ředitelna', 'reditelka@test.cz'); await p.waitForTimeout(800);
  await p.click('nav button:has-text("Nastavení školky")'); await p.waitForTimeout(600);
  kontrola('nastavení: stránka v ostrém provozu bez „Vrátit ukázková data“', !(await p.locator('button:has-text("Vrátit ukázková data")').count()));
  await p.fill('input[aria-label="Adresa"]', 'Školní 12, 160 00 Praha 6'); await p.waitForTimeout(200);
  await p.fill('input[aria-label="IČO"]', '70123456'); await p.waitForTimeout(200);
  await p.fill('input[aria-label="Úřední hodiny"]', 'Po a St 8–10'); await p.waitForTimeout(1500);
  kontrola('údaje školy uloženy na server', sql(`select adresa || '|' || ico || '|' || uredni_hodiny from skoly where id = '${A}'`) === 'Školní 12, 160 00 Praha 6|70123456|Po a St 8–10');
  await p.click('button[aria-pressed]:has-text("Polodenní")'); await p.waitForTimeout(1500);
  kontrola('druh provozu uložen', sql(`select druh_provozu from skoly where id = '${A}'`) === 'P');
  const nazev = sql(`select nazev from skoly where id = '${A}'`);
  await p.fill('input[aria-label="Úplný název"]', ''); await p.waitForTimeout(1500);
  kontrola('prázdný název se neuloží', sql(`select nazev from skoly where id = '${A}'`) === nazev);
  await p.fill('input[aria-label="Úplný název"]', nazev); await p.waitForTimeout(800);
  // platby a VS
  await p.fill('input[aria-label="Školkovné (Kč / měsíc)"]', '950'); await p.waitForTimeout(1500);
  kontrola('školkovné uloženo přes nastavení plateb', sql(`select skolkovne from financni_nastaveni where skola_id = '${A}'`) === '950.00');
  await p.click('button[aria-pressed]:has-text("10:00")'); await p.waitForTimeout(1500);
  kontrola('uzávěrka omluvenek uložena', sql(`select omluva_do from financni_nastaveni where skola_id = '${A}'`) === '10:00:00');
  // údaje se propíšou do dokumentu (šablona)
  await p.click('nav button:has-text("Dokumenty")'); await p.waitForTimeout(600);
  kontrola('dokumenty berou adresu z nastavení', (await p.locator('[contenteditable="true"]').first().innerText()).includes('Školní 12') || (await p.locator('body').innerText()).includes('Školní 12'));
  // po obnovení
  await p.reload(); await prihlas(p, 'Ředitelna', 'reditelka@test.cz').catch(() => {}); await p.waitForTimeout(800);
  await p.click('nav button:has-text("Nastavení školky")'); await p.waitForTimeout(600);
  kontrola('po obnovení: údaje ze serveru', (await p.locator('input[aria-label="Adresa"]').inputValue()) === 'Školní 12, 160 00 Praha 6' && (await p.locator('input[aria-label="Školkovné (Kč / měsíc)"]').inputValue()).startsWith('950'));
  kontrola('nastavení bez chyb na stránce', !p.chyby.length, p.chyby.join(' / '));
  await konec();
};
