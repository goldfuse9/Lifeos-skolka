// Tablet třídy v ostrém provozu: oběd a alergie ze serveru, omluvené dítě
// „přesto přišlo“ + Vrátit, třídní kniha na serveru, chyba sítě = žádný falešný stav.
const { sql, sqlJako, stranka, konec, prihlas, kontrola } = require('./spolecne');
const OLI = '00000000-0000-4000-8000-000000000102', ROD2 = 'aaaaaaaa-0000-4000-8000-000000000008', UA = 'aaaaaaaa-0000-4000-8000-000000000002';
module.exports = async () => {
  sqlJako(ROD2, '', `select omluv_dite('${OLI}', current_date, current_date, 'nemoc');`);
  const t = await stranka({ width: 1194, height: 834 });
  await prihlas(t, 'Třída', 'ucitelka@test.cz');
  let telo = await t.locator('body').innerText();
  const obed = sqlJako(UA, 'ucitelka@test.cz', `select split_part(nazev, ',', 1) from jidelnicek_tyden(current_date, current_date) where chod='obed';`);
  kontrola('karta Oběd = jídelníček ze serveru (ne ukázkové „Rizoto se sýrem“)', obed ? telo.toLowerCase().includes(obed.toLowerCase()) : /není zveřejněný/i.test(telo), obed || 'dnes bez jídelníčku');
  kontrola('záložka Fotky v ostrém provozu skrytá, Akce a Schůzky ano', !/\nFotky\n/.test(telo) && /\nAkce\n/.test(telo) && /\nSchůzky\n/.test(telo) && telo.includes('Třídní kniha'));
  // omluvený Oliver přesto přišel → vrátit
  await t.click('[role=tab]:has-text("Docházka")'); await t.waitForTimeout(500);
  await t.click('div[aria-label="Docházka"] button[aria-label^="Oliver"]'); await t.waitForTimeout(300);
  await t.click('[role=alertdialog] button:has-text("Zapsat příchod")'); await t.waitForTimeout(1500);
  kontrola('omluvený, přesto přišel: v DB přítomen, omluvenka zrušena', sql(`select stav || '|' || coalesce(omluvenka, '-') from dochazka where dite_id='${OLI}' and den=current_date`) === 'pritomen|-');
  await t.click('button:has-text("Vrátit")'); await t.waitForTimeout(1500);
  kontrola('Vrátit obnoví omluvenku od rodiče', sql(`select stav || '|' || coalesce(omluvenka, '-') from dochazka where dite_id='${OLI}' and den=current_date`) === 'omluven|nemoc');
  // třídní kniha
  await t.click('[role=tab]:has-text("Třídní kniha")'); await t.waitForTimeout(400);
  await t.locator('input').first().fill('Podzim v lese');
  await t.click('button:has-text("Zapsat do třídní knihy")'); await t.waitForTimeout(1500);
  kontrola('třídní kniha uložena na server', sql(`select tema from tridni_kniha where den=current_date`) === 'Podzim v lese');
  kontrola('rodič třídní knihu nečte', sqlJako(ROD2, '', 'select count(*) from tridni_kniha;') === '0');
  const t2 = await stranka({ width: 1194, height: 834 });
  await prihlas(t2, 'Třída', 'ucitelka@test.cz');
  await t2.click('[role=tab]:has-text("Třídní kniha")'); await t2.waitForTimeout(400);
  kontrola('po novém přihlášení (jiný tablet) zápis zůstal', (await t2.locator('input').first().inputValue()) === 'Podzim v lese');
  // výpadek sítě: příchod se nesmí tvářit jako uložený
  await t2.route(/\/rest\/v1\/dochazka/, (r) => r.abort());
  await t2.click('[role=tab]:has-text("Docházka")'); await t2.waitForTimeout(400);
  await t2.click('div[aria-label="Docházka"] button[aria-label^="Ema"]'); await t2.waitForTimeout(300);
  await t2.click('[role=alertdialog] button:has-text("Zapsat příchod")');
  await t2.waitForSelector('[role=status]:has-text("Neuloženo")', { timeout: 20000 }).catch(() => {});
  const em = await t2.locator('div[aria-label="Docházka"] button[aria-label^="Ema"]').innerText();
  kontrola('chyba sítě: tablet ukáže „neuloženo“ a dítě vrátí', /Neuloženo/.test(await t2.locator('[role=status]').allTextContents().then((x) => x.join(' '))) && !/ve třídě/.test(em), em.replace(/\n/g, ' '));
  kontrola('bez chyb JS', [t, t2].every((p) => !p.chyby.length), [t, t2].flatMap((p) => p.chyby).join('; '));
  await konec();
};
