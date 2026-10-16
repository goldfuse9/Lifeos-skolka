// Porady v ostrém provozu (ředitelna): zápis jde na server, vidí ho vedení
// i po obnovení, nejde měnit ani mazat a ostatní role (hospodářka) ho nevidí.
const { sql, sqlJako, stranka, konec, prihlas, kontrola } = require('./spolecne');
module.exports = async () => {
  const r = await stranka({ width: 1194, height: 834 });
  await prihlas(r, 'Ředitelna', 'reditelka@test.cz'); await r.waitForTimeout(800);
  await r.click('nav button:has-text("Porady")'); await r.waitForTimeout(500);
  kontrola('porady: stránka je v menu ostrého provozu a je prázdná', (await r.locator('body').innerText()).includes('0 zápisů'));
  await r.click('button:has-text("+ Nový zápis")'); await r.waitForTimeout(300);
  const dlg = r.locator('[role=dialog]');
  const chips = await dlg.locator('button[aria-pressed]').allInnerTexts();
  kontrola('dialog: výběr přítomných obsahuje ředitelku a učitelky', chips.includes('Petra Horáková') && chips.includes('Ivana Pokorná'), chips.join(' | '));
  // editor s formátováním: tučně uprostřed věty, odrážky v usnesení
  await dlg.locator('#por-ed-program').click();
  await r.keyboard.type('Plán akcí na podzim, ');
  await dlg.locator('button[aria-label="Tučně"]').first().click();
  await r.keyboard.type('kontrola BOZP');
  await dlg.locator('button[aria-label="Tučně"]').first().click();
  await r.keyboard.type('. <img src=x onerror=alert(1)>');
  await dlg.locator('#por-ed-usneseni').click();
  await dlg.locator('button[aria-label="Odrážky"]').nth(1).click();
  await r.keyboard.type('Besídka bude 17. 12.'); await r.keyboard.press('Enter'); await r.keyboard.type('Výlet v květnu');
  await r.waitForTimeout(200);
  await dlg.locator('button[aria-pressed]:has-text("Petra Horáková")').click(); // Petra nebyla
  await dlg.locator('button:has-text("Uložit zápis")').click(); await r.waitForTimeout(1200);
  const radek = sql(`select druh || '|' || program || '|' || coalesce(usneseni,'') || '|' || array_to_string(pritomni, ',') from porady where program like 'Plán akcí%'`);
  kontrola('zápis uložen na server jako text se značkami (žádné HTML)', radek.startsWith('Pedagogická rada|Plán akcí na podzim, **kontrola BOZP**. <img src=x onerror=alert(1)>|- Besídka bude 17. 12.\n- Výlet v květnu|'), radek);
  kontrola('přítomni: Petra odškrtnutá, ostatní zapsáni', !radek.includes('Petra Horáková') && radek.split('|')[3].length > 0, radek.split('|')[3]);
  const telo = await r.locator('body').innerText();
  kontrola('zápis je v seznamu', telo.includes('Plán akcí na podzim, kontrola BOZP.') && telo.includes('1 zápis') && telo.includes('• Výlet v květnu'));
  // tisk / PDF: formátování se propíše, vložený kód zůstane jen textem
  await r.evaluate(() => { window.__tisk = ''; window.open = () => ({ document: { open() {}, write(h) { window.__tisk += h; }, close() {} }, focus() {}, print() {} }); });
  await r.click('article button:has-text("Tisk / PDF")'); await r.waitForTimeout(600);
  const tisk = await r.evaluate(() => window.__tisk);
  kontrola('tisk jednoho zápisu: tučné písmo a odrážky', tisk.includes('<title>Pedagogická rada') && tisk.includes('<b>kontrola BOZP</b>') && tisk.includes('<ul><li>Besídka bude 17. 12.</li><li>Výlet v květnu</li></ul>'), tisk.slice(0, 300));
  kontrola('tisk: vložené HTML je jen text', tisk.includes('&lt;img src=x onerror=alert(1)&gt;') && !tisk.includes('<img src=x'));
  // po obnovení stránky se načte ze serveru
  await r.reload(); await prihlas(r, 'Ředitelna', 'reditelka@test.cz').catch(() => {}); await r.waitForTimeout(800);
  await r.click('nav button:has-text("Porady")'); await r.waitForTimeout(500);
  kontrola('po obnovení je zápis pořád vidět', (await r.locator('body').innerText()).includes('Plán akcí na podzim'));
  // oprávnění: učitelka čte, hospodářka nevidí, nikdo nemění
  kontrola('učitelka zápis čte', sqlJako('aaaaaaaa-0000-4000-8000-000000000002', 'ucitelka@test.cz', `select count(*) from porady;`) === '1');
  kontrola('hospodářka zápis nevidí', sqlJako('aaaaaaaa-0000-4000-8000-000000000006', 'hospodarka@test.cz', `select count(*) from porady;`) === '0');
  kontrola('porady bez chyb na stránce', !r.chyby.length, r.chyby.join(' / '));
  await konec();
};
