// Napříč systémem: tablet třídy zapíše příchod a teplotu → rodič to vidí (RLS),
// cizí rodič ne; rodič omluví dítě → tablet ukáže omluvenku → potvrzení;
// ředitelna vydá kód pro LifeOS; jídelna zveřejní jídelníček → rodič ho vidí.
const T = require('./pomocnik');
const EMA = 'eeeeeeee-0000-4000-8000-000000000101', OLI = 'eeeeeeee-0000-4000-8000-000000000102';
module.exports = async (b) => {
  const t = await T.stranka(b, { width: 1194, height: 834 });
  await T.prihlas(t, 'Třída', T.ucet('ucitelka.a'));
  T.over('tablet: učitelka A otevře třídu', (await T.hash(t)) === '#trida', (await T.hash(t)) + ' ' + (await T.hlaska(t)));
  await T.snimek(t, 'tablet-start');
  await t.click('button[aria-label^="Ema"]'); await t.waitForTimeout(300);
  await t.click('button:has-text("Zapsat příchod")'); await t.click('[role=alertdialog] button:has-text("Zapsat příchod")'); await t.waitForTimeout(1200);
  T.over('tablet: příchod Emy uložen v DB', T.sql(`select stav from dochazka where dite_id = '${EMA}' and den = (now() at time zone 'Europe/Prague')::date`) === 'pritomen');
  T.over('rodič A vidí příchod své Emy', T.sqlJako(T.ucet('rodic.a'), `select count(*) from dochazka where dite_id = '${EMA}' and prichod is not null;`) === '1');
  T.over('rodič Olivera příchod Emy nevidí', T.sqlJako(T.ucet('rodic2.a'), `select count(*) from dochazka where dite_id = '${EMA}';`) === '0');
  await t.click('button:has-text("Teplota")'); await t.waitForTimeout(300);
  for (let i = 0; i < 12; i++) await t.click('[role=dialog] button[aria-label*="Víc"], [role=dialog] button:has-text("+")').catch(() => {});
  await t.click('[role=dialog] button:has-text("Uložit")'); await t.waitForTimeout(1200);
  T.over('tablet: teplota uložena jako událost', T.sql(`select count(*) from udalosti_ditete where dite_id = '${EMA}' and druh = 'teplota'`) === '1');
  T.over('rodič A vidí teplotu', T.sqlJako(T.ucet('rodic.a'), `select count(*) from udalosti_ditete where dite_id = '${EMA}' and druh = 'teplota';`) === '1');
  T.over('rodič B teplotu nevidí', T.sqlJako(T.ucet('rodic.b'), `select count(*) from udalosti_ditete where dite_id = '${EMA}';`) === '0');
  // rodič Olivera omluví zítřek → tablet → potvrzení
  T.sqlJako(T.ucet('rodic2.a'), `select omluv_dite('${OLI}', current_date + 1, current_date + 2, 'nemoc');`);
  await t.reload(); await t.waitForTimeout(2500);
  await t.click('[role=tab]:has-text("Docházka")'); await t.waitForTimeout(600);
  const oml = await t.locator('aside[aria-label="Omluvenky"]').innerText().catch(() => '');
  T.over('tablet: omluvenka Olivera v panelu Omluvenky', oml.includes('Oliver'), oml.replace(/\n/g, ' | ').slice(0, 160));
  await t.locator('aside[aria-label="Omluvenky"] *', { hasText: 'Oliver Z.', has: t.locator('button:has-text("Potvrdit omluvenku")') }).last().locator('button:has-text("Potvrdit omluvenku")').click().catch((e) => console.log('  (klik:', String(e.message).split('\n')[0] + ')')); await t.waitForTimeout(1200);
  T.over('tablet: omluvenka potvrzena v DB', +T.sql(`select count(*) from dochazka where dite_id = '${OLI}' and omluva_potvrzena is not null`) >= 1);
  T.over('rodič vidí potvrzení', +T.sqlJako(T.ucet('rodic2.a'), `select count(*) from dochazka where dite_id = '${OLI}' and omluva_potvrzena is not null;`) >= 1);

  const r = await T.stranka(b);
  await T.prihlas(r, 'Ředitelna', T.ucet('reditelka.a'));
  await r.click('nav button:has-text("Rodiče v LifeOS")'); await r.waitForTimeout(1500);
  const lo = await r.locator('main, body').first().innerText();
  T.over('ředitelna: Rodiče v LifeOS ukazuje děti školky A', lo.includes('Jakub') && !lo.includes('Adam'));
  await r.click('button:has-text("Kód pro LifeOS") >> nth=0'); await r.waitForTimeout(1200);
  const kodTxt = await r.locator('[role=dialog]').first().innerText().catch(() => '');
  T.over('ředitelna: vydá párovací kód', /[A-Z0-9]{4}-[A-Z0-9]{4}/.test(kodTxt), kodTxt.replace(/\n/g, ' | ').slice(0, 120));

  const j = await T.stranka(b);
  await T.prihlas(j, 'Jídelna', T.ucet('kucharka.a'));
  T.over('jídelna: kuchařka se přihlásí', (await T.hash(j)) === '#jidelna', (await T.hash(j)) + ' ' + (await T.hlaska(j)));
  await j.click('nav button:has-text("Jídelníček")').catch(() => {}); await j.waitForTimeout(500);
  await j.click('button:has-text("Zveřejnit rodičům")').catch(() => {}); await j.waitForTimeout(1500);
  T.over('rodič A vidí jídelníček tohoto týdne', +T.sqlJako(T.ucet('rodic.a'), `select count(*) from jidelnicek_tyden(date_trunc('week', current_date)::date, date_trunc('week', current_date)::date + 6);`) >= 5);
  T.over('rodič B nevidí jídelníček A', T.sqlJako(T.ucet('rodic.b'), `select count(*) from jidelnicek where skola_id = 'eeeeeeee-0000-4000-8000-00000000000a';`) === '0');
  T.over('bez chyb v konzoli', !t.chyby.length && !r.chyby.length && !j.chyby.length, t.chyby.concat(r.chyby, j.chyby).join(' | '));
  return T.konec('scenar-trida-rodic');
};
