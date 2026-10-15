// Akce a třídní schůzky v ostrém provozu (tablet): učitelka založí, rodič
// odpoví (jako v LifeOS, funkcí odpovez_na_akci), tablet ukáže počty.
const { sql, sqlJako, stranka, konec, prihlas, kontrola } = require('./spolecne');
const EMA = '00000000-0000-4000-8000-000000000101', OLI = '00000000-0000-4000-8000-000000000102', SLUN = '00000000-0000-4000-8000-000000000011';
const RODA = 'aaaaaaaa-0000-4000-8000-000000000003', ROD2 = 'aaaaaaaa-0000-4000-8000-000000000008';
module.exports = async () => {
  const za = (n) => sql(`select to_char(current_date + ${n}, 'YYYY-MM-DD')`);
  const t = await stranka({ width: 1194, height: 834 });
  await prihlas(t, 'Třída', 'ucitelka@test.cz'); await t.waitForTimeout(800);
  kontrola('tablet: záložky Akce a Schůzky v ostrém provozu', (await t.locator('[role=tab]:has-text("Akce")').count()) === 1 && (await t.locator('[role=tab]:has-text("Schůzky")').count()) === 1);
  await t.click('[role=tab]:has-text("Akce")'); await t.waitForTimeout(600);
  kontrola('akce ze serveru: výlet třídy i akce celé školky', (await t.locator('body').innerText()).includes('Výlet do ZOO') && (await t.locator('body').innerText()).includes('Drakiáda'));
  await t.click('button:has-text("+ Nová akce")'); await t.waitForTimeout(300);
  kontrola('učitelka nezakládá akci celé školky', !(await t.locator('[role=dialog] button[aria-pressed]:has-text("Celá školka")').count()) && (await t.locator('[role=dialog] button[aria-pressed]:has-text("Naše třída")').count()) === 1);
  await t.fill('#akce-nazev', 'Divadlo Kašpárek');
  await t.fill('#akce-den', za(9));
  await t.click('button[aria-pressed]:has-text("Svačinu")');
  await t.click('button[aria-pressed]:has-text("50 Kč")');
  await t.click('button:has-text("Poslat pozvánku")'); await t.waitForTimeout(1500);
  kontrola('akce uložena na server (třída, den, s sebou, cena)', sql(`select trida_id || '|' || den || '|' || array_to_string(s_sebou, ',') || '|' || cena from akce where nazev = 'Divadlo Kašpárek'`) === `${SLUN}|${za(9)}|Svačinu|50.00`);
  // rodiče odpovídají (jako v LifeOS)
  const id = sql(`select id from akce where nazev = 'Divadlo Kašpárek'`);
  sqlJako(RODA, '', `select odpovez_na_akci('${id}', '${EMA}', 'ano');`);
  sqlJako(ROD2, '', `select odpovez_na_akci('${id}', '${OLI}', 'ne');`);
  await t.click('[role=tab]:has-text("Třída")'); await t.waitForTimeout(200);
  await t.click('[role=tab]:has-text("Akce")'); await t.waitForTimeout(1200);
  await t.locator('button:has-text("Divadlo Kašpárek")').first().click(); await t.waitForTimeout(400);
  const txt = await t.locator('body').innerText();
  kontrola('tablet ukáže odpovědi rodičů (1 přijde, 1 ne)', /1 \/ \d+ přijde/.test(txt), txt.match(/\d+ \/ \d+ přijde/g) + '');
  kontrola('připomenutí se v ostrém provozu nenabízí', !(await t.locator('button:has-text("Připomenout")').count()));
  // třídní schůzka
  await t.click('[role=tab]:has-text("Schůzky")'); await t.waitForTimeout(800);
  kontrola('konzultační hodiny zatím jen v ukázce', !(await t.locator('section[aria-label="Konzultační hodiny"]').count()));
  await t.click('button:has-text("+ Nová")'); await t.waitForTimeout(300);
  await t.locator('[role=dialog] input[type=date]').fill(za(14));
  await t.click('[role=dialog] button[aria-pressed]:has-text("16:30")');
  await t.click('button:has-text("Pozvat")'); await t.waitForTimeout(1500);
  kontrola('schůzka uložena na server', sql(`select druh || '|' || den || '|' || to_char(cas, 'HH24:MI') from akce where druh = 'schuzka'`) === `schuzka|${za(14)}|16:30`);
  kontrola('rodič schůzku vidí', sqlJako(RODA, '', `select count(*) from akce where druh = 'schuzka';`) === '1');
  kontrola('tablet bez chyb na stránce', !t.chyby.length, t.chyby.join(' / '));
  await konec();
};
