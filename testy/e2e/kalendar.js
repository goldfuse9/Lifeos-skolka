// Provoz a svátky (Nastavení školky): svátek přepnout na „Otevřeno, vaří se“,
// zavřít prázdniny, zrušit zavření. Kuchyně vidí zavřený den.
const { sql, stranka, konec, prihlas, kontrola } = require('./spolecne');
const A = '00000000-0000-4000-8000-000000000001';
module.exports = async () => {
  // nejbližší státní svátek ve všední den (od zítřka)
  const sv = sql(`select den || '|' || nazev from generate_series(extract(year from current_date)::int, extract(year from current_date)::int + 1) r, statni_svatky(r) s where s.den > current_date and extract(isodow from s.den) < 6 order by den limit 1`).split('|');
  const p = await stranka({ width: 1366, height: 900 });
  await prihlas(p, 'Ředitelna', 'reditelka@test.cz'); await p.waitForTimeout(800);
  await p.click('nav button:has-text("Nastavení školky")'); await p.waitForTimeout(700);
  const karta = p.locator('section[aria-label="Provoz a svátky"]');
  kontrola('nastavení: karta Provoz a svátky se svátkem ' + sv[1], (await karta.innerText()).includes(sv[1]));
  // svátek: Otevřeno, vaří se
  await karta.locator(`div:has(> span:has-text("${sv[1]}")) button:has-text("Otevřeno, vaří se")`).first().click(); await p.waitForTimeout(1500);
  kontrola('svátek otevřen v databázi', sql(`select otevreno from kalendar_skoly where skola_id = '${A}' and den = '${sv[0]}'`) === 't');
  kontrola('je_provozni_den = ano', sql(`select je_provozni_den('${A}', '${sv[0]}')`) === 't');
  // zpět na zavřeno
  await karta.locator(`div:has(> span:has-text("${sv[1]}")) button:has-text("Zavřeno")`).first().click(); await p.waitForTimeout(1500);
  kontrola('svátek zpět zavřený (bez výjimky)', sql(`select count(*) from kalendar_skoly where skola_id = '${A}' and den = '${sv[0]}'`) === '0');
  // zavřít prázdniny
  const od = sql(`select to_char(current_date + 40, 'YYYY-MM-DD')`), doD = sql(`select to_char(current_date + 46, 'YYYY-MM-DD')`);
  await karta.locator('button:has-text("Zavřít dny")').click(); await p.waitForTimeout(300);
  const d = p.locator('[role=dialog]');
  await d.locator('input[type=date]').nth(0).fill(od);
  await d.locator('input[type=date]').nth(1).fill(doD);
  await d.locator('input[placeholder="Např. Vánoční prázdniny"]').fill('Podzimní prázdniny');
  await d.locator('button:has-text("Zavřít")').last().click(); await p.waitForTimeout(1500);
  kontrola('prázdniny zavřené (5 všedních dní)', sql(`select count(*) from kalendar_skoly where skola_id = '${A}' and not otevreno and poznamka = 'Podzimní prázdniny'`) === '5');
  const txt = await karta.innerText();
  kontrola('v kartě úsek prázdnin s důvodem', txt.includes('Podzimní prázdniny') && txt.includes('Zrušit'), txt.replace(/\n/g, ' | ').slice(0, 300));
  await karta.locator('button:has-text("Zrušit")').first().click(); await p.waitForTimeout(1500);
  kontrola('zavření zrušeno', sql(`select count(*) from kalendar_skoly where skola_id = '${A}'`) === '0');
  kontrola('kalendář bez chyb na stránce', !p.chyby.length, p.chyby.join(' / '));
  await konec();
};
