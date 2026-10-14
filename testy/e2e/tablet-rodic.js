// Průřezový scénář: tablet (učitelka) ↔ rodič (LifeOS přes API jako rodič) ↔ ředitelna ↔ jídelna.
const { sql, sqlJako, stranka, konec, prihlas, kontrola } = require('./spolecne');
const EMA = '00000000-0000-4000-8000-000000000101', OLI = '00000000-0000-4000-8000-000000000102';
const RODA = 'aaaaaaaa-0000-4000-8000-000000000003', ROD2 = 'aaaaaaaa-0000-4000-8000-000000000008', RODB = 'bbbbbbbb-0000-4000-8000-000000000003';
module.exports = async () => {
  // rodič Olivera omluví zítřek (jako z LifeOS)
  sqlJako(ROD2, '', `select omluv_dite('${OLI}', current_date + 1, current_date + 1, 'nemoc');`);
  const t = await stranka({ width: 1194, height: 834 });
  await prihlas(t, 'Třída', 'ucitelka@test.cz');
  kontrola('tablet Sluníček otevřen', (await t.evaluate(() => location.hash)) === '#trida');
  const telo = await t.locator('body').innerText();
  kontrola('tablet ukazuje Emu a Olivera, ne cizí děti', telo.includes('Ema') && telo.includes('Oliver') && !telo.includes('Tobiáš') && !telo.includes('Adam'));
  await t.click('button:has-text("Zapsat příchod")'); await t.click('[role=alertdialog] button:has-text("Zapsat příchod")'); await t.waitForTimeout(1000);
  const prichod = sql(`select count(*) from dochazka where den = current_date and prichod is not null and dite_id in ('${EMA}','${OLI}')`);
  kontrola('příchod uložen v databázi', +prichod >= 1, prichod);
  kontrola('rodič Emy vidí dnešní docházku', +sqlJako(RODA, '', `select count(*) from dochazka where dite_id='${EMA}' and den=current_date;`) === 1);
  kontrola('rodič Olivera nevidí docházku Emy', sqlJako(ROD2, '', `select count(*) from dochazka where dite_id='${EMA}';`) === '0');
  kontrola('rodič z jiné školky nevidí nic z A', sqlJako(RODB, '', `select count(*) from dochazka where dite_id in ('${EMA}','${OLI}');`) === '0');
  await t.click('[role=tab]:has-text("Docházka")'); await t.waitForTimeout(600);
  const oml = await t.locator('aside[aria-label="Omluvenky"]').innerText().catch(() => '');
  kontrola('tablet ukazuje omluvenku Olivera', oml.includes('Oliver'), oml.replace(/\n/g, ' | ').slice(0, 120));
  await t.click('aside[aria-label="Omluvenky"] button:has-text("Potvrdit omluvenku") >> nth=0'); await t.waitForTimeout(1000);
  kontrola('potvrzení omluvenky uloženo', +sql(`select count(*) from dochazka where dite_id='${OLI}' and omluva_potvrzena is not null`) >= 1);
  kontrola('rodič vidí potvrzení', +sqlJako(ROD2, '', `select count(*) from dochazka where dite_id='${OLI}' and omluva_potvrzena is not null;`) >= 1);

  const r = await stranka();
  await prihlas(r, 'Ředitelna', 'reditelka@test.cz');
  await r.click('nav button:has-text("Rodiče v LifeOS")'); await r.waitForTimeout(1500);
  const lo = await r.locator('main, body').first().innerText();
  kontrola('Rodiče v LifeOS: děti školky A ze serveru', lo.includes('Tobiáš') && !lo.includes('Adam'));
  await r.click('button:has-text("Kód pro LifeOS") >> nth=0'); await r.waitForTimeout(1000);
  kontrola('kód pro rodiče vydán', +sql(`select count(*) from parovaci_kody where pouzito is null and zruseno is null`) >= 1);

  const j = await stranka();
  await prihlas(j, 'Jídelna', 'kucharka@test.cz');
  kontrola('kuchařka v jídelně', (await j.evaluate(() => location.hash)) === '#jidelna');
  await j.click('nav button:has-text("Jídelníček")'); await j.waitForTimeout(500);
  await j.click('button:has-text("Zveřejnit rodičům")'); await j.waitForTimeout(1500);
  kontrola('jídelníček zveřejněn na server', +sql(`select count(*) from jidelnicek where skola_id='00000000-0000-4000-8000-000000000001' and zverejneno`) >= 5);
  kontrola('rodič vidí jídelníček', +sqlJako(RODA, '', `select count(*) from jidelnicek_tyden(current_date - 7, current_date + 7);`) >= 1);
  await j.click('nav button:has-text("Diety a náhrady")'); await j.waitForTimeout(500);
  const pred = sql(`select nahrady_obedu from skoly where id='00000000-0000-4000-8000-000000000001'`);
  await j.click('button[role=switch]'); await j.waitForTimeout(1000);
  kontrola('přepínač náhrad uložen', sql(`select nahrady_obedu from skoly where id='00000000-0000-4000-8000-000000000001'`) !== pred);
  kontrola('bez chyb JS', [t, r, j].every((p) => !p.chyby.length), [t, r, j].flatMap((p) => p.chyby).join('; '));
  await konec();
};
