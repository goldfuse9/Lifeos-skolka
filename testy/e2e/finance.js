// Pokročilé finance v ostrém provozu (migrace 2026-10-21-finance): předpisy předem
// s číslem dokladu, jednorázová platba, storno, pokladna, vratka, sleva,
// uzávěrka a export pro účetní; hospodářka a role bez přístupu.
const { sql, sqlJako, stranka, konec, prihlas, kontrola } = require('./spolecne');
const { execSync } = require('child_process');
const os = require('os'), path = require('path');
const EMA = '00000000-0000-4000-8000-000000000101', OLI = '00000000-0000-4000-8000-000000000102';
const RA = 'aaaaaaaa-0000-4000-8000-000000000001', S = '00000000-0000-4000-8000-000000000001';
module.exports = async () => {
  sqlJako(RA, 'reditelka@test.cz', `select uloz_financni_nastaveni('19-2000145399/0800', 900, 48, 52, 15);`);
  const curM = sql(`select to_char(current_date, 'YYYY-MM')`);
  const p = await stranka({ width: 1440, height: 900 });
  await prihlas(p, 'Ředitelna', 'reditelka@test.cz'); await p.waitForTimeout(800);
  await p.click('nav button:has-text("Platby")'); await p.waitForTimeout(700);
  const dlg = p.locator('[role=dialog]');
  const ulozit = async (text, ms = 1800) => { await dlg.locator('button:has-text("' + text + '")').last().click(); await p.waitForTimeout(ms); };
  kontrola('finance: záložky v ostrém provozu', (await p.locator('[role=tablist][aria-label="Platby"]').innerText()).includes('Uzávěrka a export'));

  // pokladna a předkontace
  await p.click('button:has-text("Pokladna a předkontace")'); await p.waitForTimeout(300);
  await dlg.locator('label:has-text("Počáteční stav pokladny") input').fill('500');
  await dlg.locator('label:has-text("Předkontace — Výnos — školkovné") input').fill('602.001');
  await ulozit('Uložit');
  kontrola('nastavení: pokladna, předkontace', sql(`select pokladna_pocatek || '|' || (predkontace->>'skolkovne') from financni_nastaveni where skola_id = '${S}'`) === '500.00|602.001');

  // předpisy předem (školkovné + stravné za provozní dny)
  await p.click('main button:has-text("Vystavit předpisy za")'); await p.waitForTimeout(2200);
  kontrola('předpisy předem vystaveny, druh měsíční', sql(`select count(*) from predpisy where obdobi = '${curM}' and druh = 'mesicni' and predem`) === '3');
  kontrola('předpisy: číslo dokladu PR-', /^PR-\d{4}-\d{5}$/.test(sql(`select cislo from predpisy where dite_id = '${EMA}' and obdobi = '${curM}'`)));
  kontrola('deník: předpis s druhem a číslem', sql(`select count(*) from ucetni_pohyby where druh = 'predpis' and doklad like 'PR-%' and md = 'dite:${EMA}'`) === '2');

  // jednorázová platba třídě / celé školce
  await p.click('[role=tab]:has-text("Další platby")'); await p.waitForTimeout(300);
  await p.click('main button:has-text("Nová platba")'); await p.waitForTimeout(300);
  await dlg.locator('label:has-text("Za co") input').fill('Výlet do ZOO');
  await dlg.locator('label:has-text("Částka za dítě") input').fill('250');
  await ulozit('Vystavit platbu');
  kontrola('jednorázová platba pro celou školku', sql(`select count(*) || '|' || sum(castka) from predpisy where druh = 'jednorazova' and nazev = 'Výlet do ZOO'`) === '3|750.00');
  kontrola('jednorázová platba v seznamu', /Výlet do ZOO[\s\S]*0 \/ 3 zaplaceno/.test(await p.locator('main').innerText()));
  await p.click('main [role=button]:has-text("Výlet do ZOO")'); await p.waitForTimeout(300);
  await p.locator('aside[aria-label="Děti v platbě"] button:has-text("Storno")').first().click(); await p.waitForTimeout(200);
  await dlg.locator('label:has-text("Důvod storna") input').fill('Nepojede');
  await ulozit('Stornovat');
  kontrola('storno: předpis označen, protizápis v deníku', sql(`select count(*) from predpisy where nazev = 'Výlet do ZOO' and storno is not null`) === '1' && sql(`select count(*) from ucetni_pohyby where druh = 'storno'`) === '1');

  // pokladna
  await p.click('[role=tab]:has-text("Pokladna")'); await p.waitForTimeout(300);
  await p.click('main button:has-text("Příjem")'); await p.waitForTimeout(300);
  await dlg.locator('label:has-text("Hledat dítě") input').fill('Ema'); await p.waitForTimeout(200);
  await dlg.locator('button[aria-pressed]').filter({ hasText: 'Ema' }).first().click(); await p.waitForTimeout(200);
  await dlg.locator('label:has-text("Částka") input').fill('3000');
  await ulozit('Přijmout a vystavit doklad');
  kontrola('pokladna: příjmový doklad a platba na konto', sql(`select cislo from pokladna where druh = 'prijem'`).startsWith('PPD-') && sql(`select count(*) from platby where zdroj = 'pokladna' and dite_id = '${EMA}'`) === '1');
  kontrola('pokladna: zůstatek 3 500 Kč', /3\s500\sKč/.test(await p.locator('main').innerText()));

  // přeplatek a vratka
  const saldo = sql(`select saldo from konta where dite_id = '${EMA}'`);
  kontrola('Ema má přeplatek', Number(saldo) > 0, saldo);
  await p.click('[role=tab]:has-text("Přeplatky a vratky")'); await p.waitForTimeout(300);
  await p.locator('section[aria-label="Přeplatky"] button:has-text("Vrátit")').first().click(); await p.waitForTimeout(300);
  await dlg.locator('label:has-text("Účet rodiče") input').fill('19-2000145399/0800');
  await dlg.locator('label:has-text("Částka") input').fill('100');
  await ulozit('Vrátit');
  kontrola('vratka připravena', sql(`select stav || '|' || castka from fin_vratky`) === 'pripraveno|100.00');
  await p.click('main button:has-text("Označit jako odeslané")'); await p.waitForTimeout(1800);
  kontrola('vratka odeslána', sql(`select stav from fin_vratky`) === 'odeslano');

  // sleva (ředitelka)
  await p.click('[role=tab]:has-text("Slevy a prominutí")'); await p.waitForTimeout(300);
  await p.click('main button:has-text("Nová sleva")'); await p.waitForTimeout(300);
  await dlg.locator('label:has-text("Hledat dítě") input').fill('Oliver'); await p.waitForTimeout(200);
  await dlg.locator('button[aria-pressed]').filter({ hasText: 'Oliver' }).first().click(); await p.waitForTimeout(200);
  await dlg.locator('label:has-text("Důvod") input').first().fill('Sociální důvody');
  await ulozit('Uložit');
  kontrola('sleva uložena', sql(`select typ || '|' || duvod from fin_upravy where dite_id = '${OLI}'`) === 'osvobozeni|Sociální důvody');

  // export pro účetní
  await p.click('[role=tab]:has-text("Uzávěrka a export")'); await p.waitForTimeout(300);
  const [dz] = await Promise.all([p.waitForEvent('download'), p.locator('main button:has-text("Export ZIP")').first().click()]);
  const zip = path.join(os.tmpdir(), 'export-srv.zip'); await dz.saveAs(zip);
  const obsah = execSync(`python3 -I -c "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); print(z.testzip()); d=z.read('denik.csv').decode('utf-8-sig'); print(d.count(chr(10))); print('602.001' in d, 'PPD-' in d)" ${zip}`).toString().trim().split('\n');
  kontrola('export ZIP: deník s předkontací a pokladnou', obsah[0] === 'None' && +obsah[1] > 5 && obsah[2] === 'True True', obsah.join(' | '));
  const uz = await p.locator('main button:has-text("Uzavřít")').count();
  if (uz) {
    await p.locator('main button:has-text("Uzavřít")').first().click(); await p.waitForTimeout(300);
    await Promise.all([p.waitForEvent('download'), ulozit('Uzavřít a stáhnout export', 2500)]);
    kontrola('uzávěrka měsíce v databázi', sql(`select count(*) from fin_uzaverky`) === '1');
  }
  kontrola('finance bez chyb', !p.chyby.length, p.chyby.join(' / '));

  // hospodářka: vidí a pracuje, ale slevy ne
  const h = await stranka({ width: 1440, height: 900 });
  await prihlas(h, 'Ředitelna', 'hospodarka@test.cz'); await h.waitForTimeout(800);
  await h.click('nav button:has-text("Platby")'); await h.waitForTimeout(700);
  await h.click('[role=tab]:has-text("Pokladna")'); await h.waitForTimeout(300);
  kontrola('hospodářka vidí pokladnu', /PPD-\d{4}-00001/.test(await h.locator('main').innerText()));
  await h.click('[role=tab]:has-text("Slevy a prominutí")'); await h.waitForTimeout(300);
  kontrola('hospodářka nezakládá slevy', !(await h.locator('main button:has-text("Nová sleva")').count()));
  kontrola('hospodářka bez chyb', !h.chyby.length, h.chyby.join(' / '));
  await konec();
};
