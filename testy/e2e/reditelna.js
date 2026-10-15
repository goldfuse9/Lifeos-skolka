// Ředitelna v ostrém provozu: skutečná data školky, zápisy jdou na server,
// nenapojené stránky se neukazují, hospodářka nevidí rodná čísla.
const { sql, sqlJako, stranka, konec, prihlas, kontrola } = require('./spolecne');
const EMA = '00000000-0000-4000-8000-000000000101';
module.exports = async () => {
  // dnešní příchod a úraz z tabletu (jako učitelka)
  sqlJako('aaaaaaaa-0000-4000-8000-000000000002', 'ucitelka@test.cz', `insert into dochazka (dite_id, den, stav, prichod) values ('${EMA}', current_date, 'pritomen', '07:50');
    insert into urazy (skola_id, cislo, rok, dite_id, kdy, kde, co, osetreni, zapsal) values ('00000000-0000-4000-8000-000000000001', 0, extract(year from now())::int, '${EMA}', now(), 'zahrada', 'odřené koleno z tabletu', 'dezinfekce', 'aaaaaaaa-0000-4000-8000-000000000002');`);
  sql(`update urazy set dny_absence = 3 where co = 'odřené koleno z tabletu'`);
  const p = await stranka();
  await prihlas(p, 'Ředitelna', 'reditelka@test.cz');
  const nav = await p.locator('nav[aria-label="Ředitelna"]').innerText();
  kontrola('hlavička: skutečná školka a „Ostrý provoz“', nav.includes('MŠ Sluníčko (test)') && nav.includes('Ostrý provoz'));
  kontrola('nenapojené stránky skryté (Platby, Matrika, Nastavení…)', !/Platby|Matrika|Nastavení školky|Dokumenty|Archiv|Webové/.test(nav) && /Porady/.test(nav) && /Zápis/.test(nav));
  kontrola('Přehled: dnes ve školce 1 / 3', /1 \/ 3/.test(await p.locator('body').innerText()));
  await p.click('nav button:has-text("Kartotéka dětí")'); await p.waitForTimeout(500);
  let telo = await p.locator('body').innerText();
  kontrola('kartotéka: 3 děti školky A, žádné ukázkové ani cizí', telo.includes('Ema Testová') && telo.includes('Tobiáš Ukázkový') && !telo.includes('Adam') && !telo.includes('Ella Marková'));
  // úprava karty
  await p.click('text=Ema Testová'); await p.waitForTimeout(600);
  await p.fill('input[aria-label="Obec"]', 'Praha 6');
  await p.fill('input[placeholder^="Jméno, např. babička"]', 'děda Karel');
  await p.locator('input[placeholder^="Jméno, např. babička"]').locator('xpath=..').locator('button').click();
  await p.waitForTimeout(1800);
  kontrola('úprava karty uložena na server (obec)', sql(`select obec from deti where id='${EMA}'`) === 'Praha 6');
  kontrola('pověřená osoba uložena na server', sql(`select count(*) from poverene_osoby where dite_id='${EMA}' and jmeno='děda Karel' and zruseno is null`) === '1');
  await p.click('[aria-label="Zavřít kartu"]'); await p.waitForTimeout(300);
  // nové dítě
  await p.click('button:has-text("+ Přidat dítě")'); await p.waitForTimeout(400);
  await p.fill('[role=dialog] input[placeholder="Např. Tereza"]', 'Lucie');
  await p.fill('[role=dialog] input[placeholder="Např. Malá"]', 'Nová');
  await p.fill('[role=dialog] input[placeholder="RRMMDD/XXXX"]', '225305/0008');
  await p.click('[role=dialog] button:has-text("Sluníčka")');
  await p.locator('[role=dialog] button').last().click(); await p.waitForTimeout(2000);
  kontrola('nové dítě uloženo na server (se třídou a RČ)', sql(`select t.nazev || ' ' || d.rodne_cislo from deti d join tridy t on t.id=d.trida_id where d.jmeno='Lucie' and d.prijmeni='Nová'`) === 'Sluníčka 225305/0008');
  // třídy: přiřazení učitelky
  await p.click('nav button:has-text("Třídy")'); await p.waitForTimeout(500);
  const tridy = await p.locator('body').innerText();
  kontrola('třídy: k přiřazení jen pedagogové (ne kuchařka, hospodářka)', !tridy.includes('Jana Králová') && !tridy.includes('Marta Svobodová'));
  await p.locator('section[aria-label="Třída Sluníčka"] button:has-text("Lucie Malá")').click(); await p.waitForTimeout(1500);
  kontrola('přiřazení učitelky ke třídě uloženo na server', sql(`select count(*) from ucitel_trida ut join tridy t on t.id=ut.trida_id where ut.ucitel_id='aaaaaaaa-0000-4000-8000-000000000005' and t.nazev='Sluníčka'`) === '1');
  kontrola('učitelka teď vidí děti Sluníček', +sqlJako('aaaaaaaa-0000-4000-8000-000000000005', 'ucitelka2@test.cz', `select count(*) from deti where jmeno='Ema';`) === 1);
  // kniha úrazů z tabletu
  await p.click('nav button:has-text("Kniha úrazů")'); await p.waitForTimeout(500);
  kontrola('kniha úrazů ukazuje úraz z tabletu', (await p.locator('body').innerText()).includes('odřené koleno z tabletu'));
  // docházka
  kontrola('úraz z tabletu: „Poslat rodičům“ nenabízí falešné odeslání', /Mají v aplikaci|Bez aplikace/.test(await p.locator('body').innerText()));
  await p.locator('button:has-text("Vyplnit")').first().click(); await p.waitForTimeout(400);
  for (const x of ['pohmoždění', 'noha', 'pád na rovině nebo z výšky', 'nepozornost, nepředvídatelná situace']) await p.locator(`[role=dialog] button:has-text("${x}")`).first().click();
  const dl = p.waitForEvent('download', { timeout: 5000 }).catch(() => null);
  await p.locator('[role=dialog] button:has-text("Stáhnout a označit jako odeslaný")').click();
  const soubor = await dl; await p.waitForTimeout(1500);
  kontrola('záznam o úrazu: stáhne se a neříká „odesláno ČŠI“', !!soubor && /pošlete ho ČŠI/.test((await p.locator('[role=status]').allTextContents()).join(' ')));
  kontrola('záznam o úrazu uložen na server (datum a podrobnosti)', sql(`select (zaznam_odeslan is not null) || '|' || (zaznam->>'druh') from urazy where co = 'odřené koleno z tabletu'`) === 'true|pohmoždění');
  await p.screenshot({ path: require('./spolecne').VYSL + '/reditelna-urazy.png' });
  await p.click('nav button:has-text("Docházka")'); await p.waitForTimeout(500);
  await p.screenshot({ path: require('./spolecne').VYSL + '/reditelna-dochazka.png' });
  kontrola('docházka: data ze serveru, ne ukázková', !(await p.locator('body').innerText()).includes('Jonáš Procházka'));
  // zpráva rodičům Emy
  await p.click('nav button:has-text("Zprávy")'); await p.waitForTimeout(500);
  await p.click('section[aria-label="Nová zpráva"] button:has-text("Sluníčka")');
  await p.locator('input, textarea').filter({ hasNot: p.locator('[aria-label="Hledat dítě"]') }).nth(0).fill('Výlet');
  await p.locator('textarea').first().fill('Zítra jdeme na výlet.');
  await p.click('button:has-text("Poslat rodičům")'); await p.waitForTimeout(1500);
  kontrola('zpráva uložena pro třídu', sql(`select komu like 'trida:%' from zpravy where predmet='Výlet'`) === 't');
  kontrola('rodič Emy zprávu vidí', sqlJako('aaaaaaaa-0000-4000-8000-000000000003', '', `select count(*) from zpravy where predmet='Výlet';`) === '1');
  kontrola('rodič Olivera (také Sluníčka) ji vidí', sqlJako('aaaaaaaa-0000-4000-8000-000000000008', '', `select count(*) from zpravy where predmet='Výlet';`) === '1');
  kontrola('rodič z jiné školky ji nevidí', sqlJako('bbbbbbbb-0000-4000-8000-000000000003', '', `select count(*) from zpravy where predmet='Výlet';`) === '0');
  await p.screenshot({ path: require('./spolecne').VYSL + '/reditelna-zpravy.png' });
  kontrola('v prohlížeči nezůstala data dětí', await p.evaluate(() => !Object.values(localStorage).join(' ').includes('Testová')));
  kontrola('bez chyb JS (ředitelka)', !p.chyby.length, p.chyby.join('; '));
  // hospodářka
  const h = await stranka();
  await prihlas(h, 'Ředitelna', 'hospodarka@test.cz');
  await h.click('nav button:has-text("Kartotéka dětí")').catch(() => {}); await h.waitForTimeout(500);
  const ht = await h.locator('body').innerText();
  kontrola('hospodářka nevidí rodná čísla', ht.includes('Tobiáš') && !ht.includes('220120/0000'), (await h.evaluate(() => location.hash)));
  kontrola('hospodářka nemá Přístupy', !(await h.locator('nav[aria-label="Ředitelna"]').innerText()).includes('Přístupy'));
  kontrola('bez chyb JS (hospodářka)', !h.chyby.length, h.chyby.join('; '));
  await konec();
};
