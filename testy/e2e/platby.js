// Platby v ostrém provozu: nastavení cen, vystavení předpisů, import výpisu
// GPC (párování v databázi), ruční spárování, upomínka do aplikace LifeOS.
const { sql, sqlJako, stranka, konec, prihlas, kontrola } = require('./spolecne');
const EMA = '00000000-0000-4000-8000-000000000101', OLI = '00000000-0000-4000-8000-000000000102';
const RA = 'aaaaaaaa-0000-4000-8000-000000000001';
const gpcRadek = (castkaHal, vs, nazev, doklad, ddmmyy) => '075' + '0000002000145399' + '0000001234567890' + String(doklad).padStart(13, '0')
  + String(castkaHal).padStart(12, '0') + '2' + String(vs).padStart(10, '0') + '0800000000' + '0000000000' + '000000' + (nazev + ' '.repeat(20)).slice(0, 20) + '0' + '0203' + ddmmyy;
module.exports = async () => {
  // platí se předem: běžný měsíc, školkovné + stravné za provozní dny (svátky ne)
  const pM = sql(`select to_char(current_date, 'YYYY-MM')`);
  const dny = +sql(`select count(*) from generate_series(date_trunc('month', current_date), date_trunc('month', current_date) + interval '1 month' - interval '1 day', interval '1 day') g where je_provozni_den('00000000-0000-4000-8000-000000000001', g::date)`);
  const emaKc = 900 + 48 * dny;
  const p = await stranka({ width: 1366, height: 900 });
  await prihlas(p, 'Ředitelna', 'reditelka@test.cz'); await p.waitForTimeout(800);
  await p.click('nav button:has-text("Platby")'); await p.waitForTimeout(600);
  kontrola('platby: stránka v ostrém provozu bez ukázkového výpisu', !(await p.locator('button:has-text("Ukázkový výpis")').count()));
  // nastavení cen a účtu
  await p.click('button:has-text("Upravit")'); await p.waitForTimeout(300);
  const d = p.locator('[role=dialog]');
  await d.locator('input[placeholder="Např. 900"]').fill('900');
  await d.locator('input[placeholder="Např. 48"]').fill('48');
  await d.locator('input[placeholder="Např. 52"]').fill('52');
  await d.locator('input[placeholder="Např. 15"]').fill('15');
  await d.locator('button:has-text("Uložit")').click(); await p.waitForTimeout(1500);
  kontrola('nastavení plateb uloženo (školkovné, stravné, splatnost)', sql(`select f.skolkovne || '|' || f.splatnost_den || '|' || (select string_agg(cena::text, ',' order by kategorie) from sazby_stravneho s where s.skola_id = f.skola_id) from financni_nastaveni f where skola_id = '00000000-0000-4000-8000-000000000001'`) === '900.00|15|48.00,52.00');
  // předpisy
  await p.click('button:has-text("Vystavit předpisy za")'); await p.waitForTimeout(2000);
  kontrola('předpisy vystaveny pro 3 děti', sql(`select count(*) from predpisy where obdobi = '${pM}'`) === '3');
  kontrola(`Ema: školkovné + ${dny} obědů předem = ${emaKc} Kč`, sql(`select castka from predpisy where dite_id = '${EMA}' and obdobi = '${pM}'`) === emaKc + '.00');
  kontrola('předpisy vidět v tabulce', (await p.locator('body').innerText()).includes('Ema Testová'));
  // výpis z banky
  const dd = sql(`select to_char(current_date, 'DDMMYY')`);
  const vypis = ['0740000002000145399MS SLUNICKO TEST', gpcRadek(emaKc * 100, '260001', 'TESTOVA JANA', 101, dd), gpcRadek(50000, '777', 'NEZNAMY PLATCE', 102, dd),
    '075' + '0000002000145399' + '0000009876543210' + '0000000000103' + '000000150000' + '1' + '0000000000' + '0300000000' + '0000000000' + '000000' + 'NAKUP PAPIRNICTVI   ' + '0' + '0203' + dd].join('\r\n');
  await p.setInputFiles('#vypis-gpc', { name: 'vypis.gpc', mimeType: 'text/plain', buffer: Buffer.from(vypis) }); await p.waitForTimeout(2500);
  const dl = await p.locator('[role=dialog]').innerText().catch(() => '');
  kontrola('import: 1 přesně, 1 nespárovaná, 1 odchozí', /Zaplaceno přesně\s*1/.test(dl) && /Nespárováno[^\n]*\s*1/.test(dl) && /Odchozí[^\n]*\s*1/.test(dl), dl.replace(/\n/g, ' | ').slice(0, 200));
  kontrola('Ema: předpis zaplacen, konto 0', sql(`select stav from predpisy where dite_id = '${EMA}' and obdobi = '${pM}'`) === 'zaplaceno' && sql(`select saldo from konta where dite_id = '${EMA}'`) === '0.00');
  kontrola('kniha: platba MD banka / Dal dítě', sql(`select count(*) from ucetni_pohyby where md = 'banka' and dal = 'dite:${EMA}' and castka = ${emaKc}`) === '1');
  await p.locator('[role=dialog] button:has-text("Zavřít"), [role=dialog] button[aria-label="Zavřít"]').first().click().catch(() => p.keyboard.press('Escape')); await p.waitForTimeout(300);
  // stejný výpis znovu → nic dvakrát
  await p.setInputFiles('#vypis-gpc', { name: 'vypis.gpc', mimeType: 'text/plain', buffer: Buffer.from(vypis) }); await p.waitForTimeout(2500);
  kontrola('stejný výpis podruhé: nic se nezdvojí', sql(`select count(*) from platby`) === '2');
  await p.locator('[role=dialog] button:has-text("Zavřít"), [role=dialog] button[aria-label="Zavřít"]').first().click().catch(() => p.keyboard.press('Escape')); await p.waitForTimeout(300);
  // ruční spárování
  await p.click('button:has-text("Přiřadit")'); await p.waitForTimeout(400);
  await p.locator('[role=dialog] button:has-text("Oliver Zkušební")').click(); await p.waitForTimeout(2000);
  kontrola('ruční spárování: platba u Olivera, vyřešeno', sql(`select count(*) from platby where dite_id = '${OLI}' and castka = 500`) === '1' && sql(`select count(*) from nesparovane_platby where vyreseno`) === '1');
  // upomínka: dluh po splatnosti (předpisy za starší měsíc)
  sqlJako(RA, 'reditelka@test.cz', `select vystav_predpisy(to_char(date_trunc('month', current_date) - interval '2 month', 'YYYY-MM'));`);
  sql(`update predpisy set splatnost = current_date - 1 where obdobi = to_char(date_trunc('month', current_date) - interval '2 month', 'YYYY-MM')`);
  await p.reload(); await prihlas(p, 'Ředitelna', 'reditelka@test.cz').catch(() => {}); await p.waitForTimeout(800);
  await p.click('nav button:has-text("Platby")'); await p.waitForTimeout(600);
  const radek = p.locator('div:has(> span > span:text-is("Oliver Zkušební"))').first();
  await radek.locator('button:has-text("Upomínka")').click(); await p.waitForTimeout(2000);
  kontrola('upomínka: zpráva rodičům do aplikace + záznam', sql(`select count(*) from zpravy where komu = 'dite:${OLI}' and predmet = 'Platba po splatnosti'`) === '1' && +sql(`select count(*) from upominky where dite_id = '${OLI}'`) >= 1);
  kontrola('rodič Olivera upomínku vidí', sqlJako('aaaaaaaa-0000-4000-8000-000000000008', '', `select count(*) from zpravy where predmet = 'Platba po splatnosti';`) === '1');
  kontrola('platby bez chyb na stránce', !p.chyby.length, p.chyby.join(' / '));
  // hospodářka: platby ano, ceny ne
  const h = await stranka({ width: 1366, height: 900 });
  await prihlas(h, 'Ředitelna', 'hospodarka@test.cz'); await h.waitForTimeout(800);
  await h.click('nav button:has-text("Platby")'); await h.waitForTimeout(600);
  kontrola('hospodářka vidí platby, ceny nemění', (await h.locator('body').innerText()).includes('Oliver Zkušební') && !(await h.locator('button:has-text("Upravit")').count()));
  kontrola('hospodářka bez chyb', !h.chyby.length, h.chyby.join(' / '));
  await konec();
};
