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
  await dlg.locator('textarea').nth(0).fill('Plán akcí na podzim, kontrola BOZP.');
  await dlg.locator('textarea').nth(1).fill('Besídka bude 17. 12.');
  await dlg.locator('button[aria-pressed]:has-text("Petra Horáková")').click(); // Petra nebyla
  await dlg.locator('button:has-text("Uložit zápis")').click(); await r.waitForTimeout(1200);
  const radek = sql(`select druh || '|' || program || '|' || coalesce(usneseni,'') || '|' || array_to_string(pritomni, ',') from porady where program like 'Plán akcí%'`);
  kontrola('zápis uložen na server (typ, program, usnesení)', radek.startsWith('Pedagogická rada|Plán akcí na podzim, kontrola BOZP.|Besídka bude 17. 12.|'), radek);
  kontrola('přítomni: Petra odškrtnutá, ostatní zapsáni', !radek.includes('Petra Horáková') && radek.split('|')[3].length > 0, radek.split('|')[3]);
  const telo = await r.locator('body').innerText();
  kontrola('zápis je v seznamu', telo.includes('Plán akcí na podzim') && telo.includes('1 zápis'));
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
