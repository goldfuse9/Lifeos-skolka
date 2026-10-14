// Zprávy: rodič (LifeOS) ↔ učitelka (tablet) ↔ vedení (ředitelna).
// Rodič píše přes databázi stejně jako LifeOS (role rodic, RLS), tablet a
// ředitelna se ovládají v prohlížeči.
const { sql, sqlJako, stranka, konec, prihlas, kontrola } = require('./spolecne');
const EMA = '00000000-0000-4000-8000-000000000101', SLUN = '00000000-0000-4000-8000-000000000011';
const RODA = 'aaaaaaaa-0000-4000-8000-000000000003', ROD2 = 'aaaaaaaa-0000-4000-8000-000000000008';
const RA = 'aaaaaaaa-0000-4000-8000-000000000001', UA = 'aaaaaaaa-0000-4000-8000-000000000002';
const rodic = (q) => sqlJako(RODA, '', q);
const neprectene = () => sqlJako(UA, 'ucitelka@test.cz', `select count(*) from zpravy z where odeslal is distinct from '${UA}' and od_role is distinct from 'ucitelka' and not exists (select 1 from zpravy_precteni p where p.zprava_id=z.id and p.uzivatel_id='${UA}');`);
const obnov = (p) => p.evaluate(() => document.dispatchEvent(new Event('visibilitychange')));

module.exports = async () => {
  // výchozí stav: rodič Emy napsal školce, vedení napsalo celé školce
  rodic(`insert into zpravy (komu, predmet, text) values ('dite:${EMA}', '', 'Ema dnes odejde ve 12 s babičkou.');`);
  sqlJako(RA, 'reditelka@test.cz', `insert into zpravy (komu, predmet, text) values ('vse', 'Besídka', 'Ve čtvrtek v 16 h besídka pro rodiče.');`);

  const t = await stranka({ width: 1194, height: 834 });
  await prihlas(t, 'Třída', 'ucitelka@test.cz');
  await t.waitForTimeout(800);
  const zal = await t.locator('[role=tab]:has-text("Zprávy")').innerText();
  const n0 = neprectene();
  kontrola('tablet: záložka Zprávy s počtem nových', +n0 >= 2 && new RegExp('Zprávy\\s*' + n0 + '$').test(zal.trim()), zal.replace(/\n/g, ' ') + ' / DB ' + n0);
  await t.click('[role=tab]:has-text("Zprávy")'); await t.waitForTimeout(400);
  let telo = await t.locator('body').innerText();
  kontrola('tablet: zpráva rodiče v seznamu nahoře s odesílatelem', telo.indexOf('Ema dnes odejde') !== -1 && telo.includes('Rodiče · Ema'));
  kontrola('tablet: zpráva vedení celé školce v seznamu', telo.includes('Besídka') && telo.includes('Celá školka'));

  // otevřít zprávu rodiče → přečteno, odpovědět
  await t.locator('aside[aria-label="Konverzace"] button:has-text("Ema dnes odejde")').first().click(); await t.waitForTimeout(1200);
  kontrola('otevřením se zpráva označí jako přečtená', sql(`select count(*) from zpravy_precteni p join zpravy z on z.id=p.zprava_id where p.uzivatel_id='${UA}' and z.komu='dite:${EMA}'`) === '1');
  telo = await t.locator('section[aria-label="Konverzace"]').innerText();
  kontrola('konverzace ukazuje jméno rodiče', telo.includes('Jana Testová (rodič)'), telo.slice(0, 120).replace(/\n/g, ' | '));
  await t.fill('#zprava-odpoved', 'Dobře, díky za info.');
  await t.click('section[aria-label="Konverzace"] button:has-text("Odeslat")'); await t.waitForTimeout(1500);
  kontrola('odpověď učitelky jde do kanálu dítěte ve stejném vlákně', sql(`select count(*) from zpravy where komu='dite:${EMA}' and odpoved_na is not null and odeslal='${UA}' and text='Dobře, díky za info.'`) === '1');
  kontrola('rodič odpověď vidí', rodic(`select count(*) from zpravy where text='Dobře, díky za info.';`) === '1');
  kontrola('rodič Olivera odpověď nevidí', sqlJako(ROD2, '', `select count(*) from zpravy where text='Dobře, díky za info.';`) === '0');
  kontrola('odpověď je v konverzaci vidět', (await t.locator('section[aria-label="Konverzace"]').innerText()).includes('Dobře, díky za info.'));

  // odpověď na zprávu vedení celé školce → jde vedení
  await t.locator('aside[aria-label="Konverzace"] button:has-text("Besídka")').first().click(); await t.waitForTimeout(800);
  kontrola('u hromadné zprávy vedení se odpovídá vedení', (await t.locator('#zprava-odpoved').getAttribute('placeholder')) === 'Odpovědět vedení');
  await t.fill('#zprava-odpoved', 'Ve čtvrtek mám odpolední službu, přijdu.');
  await t.click('section[aria-label="Konverzace"] button:has-text("Odeslat")'); await t.waitForTimeout(1500);
  kontrola('odpověď učitelky na zprávu celé školce vidí jen vedení', sql(`select komu from zpravy where text like 'Ve čtvrtek mám%'`) === 'vedeni:' + UA
    && rodic(`select count(*) from zpravy where text like 'Ve čtvrtek mám%';`) === '0');

  // nová zpráva rodičům třídy, potvrzení od rodiče
  await t.click('button:has-text("Nová zpráva")'); await t.waitForTimeout(300);
  kontrola('nová zpráva: tlačítko Odeslat neaktivní bez textu', (await t.locator('section[aria-label="Nová zpráva"] button:has-text("Odeslat")').getAttribute('aria-disabled')) === 'true');
  await t.fill('#zprava-nova', 'Zítra jdeme do lesa, prosím holínky.');
  await t.click('section[aria-label="Nová zpráva"] button:has-text("Odeslat")'); await t.waitForTimeout(1500);
  const idTr = sql(`select id from zpravy where komu='trida:${SLUN}' and text like 'Zítra jdeme%'`);
  kontrola('zpráva třídě uložena (předmět z textu)', !!idTr && sql(`select predmet from zpravy where id='${idTr}'`).startsWith('Zítra jdeme do lesa'));
  kontrola('rodič třídy zprávu vidí', rodic(`select count(*) from zpravy where id='${idTr}';`) === '1');
  rodic(`select precti_zpravy(array['${idTr}']::uuid[], true);`);
  await t.locator('aside[aria-label="Konverzace"] button:has-text("Zítra jdeme")').first().click(); await t.waitForTimeout(1200);
  telo = await t.locator('section[aria-label="Konverzace"]').innerText();
  kontrola('učitelka vidí, kdo zprávu potvrdil', /Potvrdili:\s*Jana Testová \(Ema\)/.test(telo), telo.slice(-120).replace(/\n/g, ' | '));

  // zpráva vedení
  await t.click('button:has-text("Nová zpráva")'); await t.waitForTimeout(300);
  await t.click('section[aria-label="Nová zpráva"] button:has-text("Vedení školky")');
  await t.fill('#zprava-nova', 'Prosím o volno na pátek.');
  await t.click('section[aria-label="Nová zpráva"] button:has-text("Odeslat")'); await t.waitForTimeout(1500);
  kontrola('zpráva vedení uložena do kanálu učitelky', sql(`select komu from zpravy where text='Prosím o volno na pátek.'`) === 'vedeni:' + UA);

  // nová zpráva od rodiče za běhu → objeví se nahoře s počtem
  rodic(`insert into zpravy (komu, predmet, text) values ('dite:${EMA}', '', 'Zapomněli jsme bačkory.');`);
  await t.click('[role=tab]:has-text("Třída")'); await t.waitForTimeout(200);
  await obnov(t); await t.waitForTimeout(1500);
  const zal2 = (await t.locator('[role=tab]:has-text("Zprávy")').innerText()).trim(), n2 = neprectene();
  kontrola('nová zpráva za běhu: počet na záložce', new RegExp('Zprávy\\s*' + n2 + '$').test(zal2) && rodic(`select count(*) from zpravy where text='Zapomněli jsme bačkory.';`) === '1', zal2.replace(/\n/g, ' ') + ' / DB ' + n2);
  await t.click('[role=tab]:has-text("Zprávy")'); await t.waitForTimeout(400);
  const prvni = await t.locator('aside[aria-label="Konverzace"] button').nth(1).innerText();
  kontrola('konverzace s novou zprávou je nahoře', prvni.includes('Zapomněli jsme bačkory') && prvni.includes('Nová'), prvni.replace(/\n/g, ' | '));
  kontrola('tablet bez chyb na stránce', !t.chyby.length, t.chyby.join(' / '));

  // ředitelna: odpověď rodiče na Besídku + zprávy učitelky vedení
  const besidka = sql(`select id from zpravy where predmet='Besídka' and odpoved_na is null`);
  rodic(`insert into zpravy (komu, predmet, text, odpoved_na) values ('dite:${EMA}', '', 'Přijdeme oba.', '${besidka}');`);
  const r = await stranka();
  await prihlas(r, 'Ředitelna', 'reditelka@test.cz'); await r.waitForTimeout(800);
  const nav = await r.locator('nav button:has-text("Zprávy")').innerText();
  kontrola('ředitelna: v menu „Zprávy“ s počtem nových (3: 2× učitelka, 1× rodič)', /Zprávy\s*3/.test(nav), nav.replace(/\n/g, ' '));
  await r.click('nav button:has-text("Zprávy")'); await r.waitForTimeout(500);
  let rt = await r.locator('section[aria-label="Konverzace"]').innerText();
  kontrola('ředitelna: odpověď rodiče na Besídku je vidět', rt.includes('Přijdeme oba.') && rt.includes('Rodiče · Ema Testová'));
  kontrola('ředitelna: zpráva učitelky vedení je vidět', rt.includes('Prosím o volno na pátek.') && rt.includes('Petra Horáková → vedení'));
  await r.locator('section[aria-label="Konverzace"] button:has-text("Prosím o volno")').click(); await r.waitForTimeout(1000);
  await r.fill('#zprava-odpoved', 'Volno schváleno.');
  await r.click('section[aria-label="Konverzace"] button:has-text("Odeslat")'); await r.waitForTimeout(1500);
  kontrola('odpověď vedení jde do kanálu učitelky', sql(`select komu from zpravy where text='Volno schváleno.'`) === 'vedeni:' + UA);
  kontrola('učitelka odpověď vidí, rodič ne', sqlJako(UA, 'ucitelka@test.cz', `select count(*) from zpravy where text='Volno schváleno.';`) === '1' && rodic(`select count(*) from zpravy where text='Volno schváleno.';`) === '0');
  // hromadná zpráva + potvrzení rodiče
  await r.click('button:has-text("← Zpět")'); await r.waitForTimeout(300);
  await r.fill('#zprava-predmet', 'Uzavření v pátek'); await r.fill('#zprava-text', 'V pátek je školka zavřená.');
  await r.click('section[aria-label="Nová zpráva"] button:has-text("Poslat rodičům")'); await r.waitForTimeout(1500);
  const uz = sql(`select id from zpravy where predmet='Uzavření v pátek'`);
  kontrola('hromadná zpráva odeslána jednou (ne dvakrát)', !!uz && sql(`select count(*) from zpravy where predmet='Uzavření v pátek'`) === '1');
  rodic(`select precti_zpravy(array['${uz}']::uuid[], true);`);
  await r.click('button:has-text("← Zpět")'); await r.waitForTimeout(300);
  await r.locator('section[aria-label="Konverzace"] button:has-text("Uzavření v pátek")').click(); await r.waitForTimeout(1200);
  rt = await r.locator('section[aria-label="Konverzace"]').innerText();
  kontrola('ředitelka vidí, kdo potvrdil', rt.includes('Potvrdili: Jana Testová (Ema)'), rt.slice(-100).replace(/\n/g, ' | '));
  kontrola('ředitelna bez chyb na stránce', !r.chyby.length, r.chyby.join(' / '));
  await konec();
};
