// Pokročilé finance ve zkušebním provozu (bez serveru): předpis s číslem,
// jednorázová platba, pokladna, vratka, slevy, uzávěrka a export ZIP.
const { stranka, konec, prihlas, kontrola } = require('./spolecne');
const { execSync } = require('child_process');
const os = require('os'), path = require('path');
const SHOT = process.env.SHOT_DIR || '';
module.exports = async () => {
  const p = await stranka({ width: 1440, height: 900 }, true);
  await prihlas(p, 'Ředitelna', 'reditelka@ms-slunicko.cz', 'skolka');
  await p.click('nav button:has-text("Platby")'); await p.waitForTimeout(500);
  const tabs = await p.locator('[role=tablist][aria-label="Platby"]').innerText();
  kontrola('zkušební finance: záložky', tabs.includes('Pokladna') && tabs.includes('Uzávěrka a export'), tabs);
  const dlg = p.locator('[role=dialog]');
  const ulozit = async (text) => { await dlg.locator('button:has-text("' + text + '")').last().click(); await p.waitForTimeout(400); };

  // předpisy za aktuální měsíc (ve zkušebním provozu podle docházky)
  await p.locator('main button[aria-pressed]').filter({ hasText: /^říjen$/ }).first().click(); await p.waitForTimeout(200);
  await p.click('main button:has-text("Vystavit předpisy za")'); await p.waitForTimeout(500);
  let telo = await p.locator('body').innerText();
  kontrola('zkušební: předpisy vystaveny', /Vystaveno předpisů: \d+/.test(telo) && telo.includes('školkovné'), telo.slice(0, 200));
  await p.locator('main button:has-text("Konto"), main button:has-text("QR platba")').first().click(); await p.waitForTimeout(300);
  kontrola('zkušební: konto ukazuje předpis s číslem a storno', /PR-\d{4}-\d{5}/.test(await dlg.innerText()) && (await dlg.locator('button:has-text("Storno")').count()) > 0);
  await dlg.locator('button[aria-label="Zavřít"]').first().click(); await p.waitForTimeout(200);

  // jednorázová platba pro celou školku
  await p.click('[role=tab]:has-text("Další platby")'); await p.waitForTimeout(200);
  await p.click('main button:has-text("Nová platba")'); await p.waitForTimeout(200);
  await dlg.locator('label:has-text("Za co") input').fill('Divadlo Kašpárek');
  await dlg.locator('label:has-text("Částka za dítě") input').fill('120');
  await ulozit('Vystavit platbu');
  telo = await p.locator('main').innerText();
  kontrola('zkušební: jednorázová platba', telo.includes('Divadlo Kašpárek') && /\d+ \/ \d+ zaplaceno/.test(telo), telo.slice(0, 300));
  await p.click('main [role=button]:has-text("Divadlo Kašpárek")'); await p.waitForTimeout(200);
  await p.locator('aside[aria-label="Děti v platbě"] button:has-text("Storno")').first().click(); await p.waitForTimeout(200);
  await dlg.locator('label:has-text("Důvod storna") input').fill('Nemocné dítě, nepůjde');
  await ulozit('Stornovat');
  telo = await p.locator('main').innerText();
  kontrola('zkušební: storno jednoho předpisu', /Předpis stornován/.test(await p.locator('body').innerText()) && !(await dlg.count()));

  // pokladna: příjem hotově a výdej
  await p.click('[role=tab]:has-text("Pokladna")'); await p.waitForTimeout(200);
  await p.click('main button:has-text("Příjem")'); await p.waitForTimeout(200);
  await dlg.locator('label:has-text("Hledat dítě") input').fill('Ema');
  await p.waitForTimeout(150);
  await dlg.locator('button[aria-pressed]').filter({ hasText: 'Ema' }).first().click(); await p.waitForTimeout(150);
  await dlg.locator('label:has-text("Částka") input').fill('5000');
  await ulozit('Přijmout a vystavit doklad');
  telo = await p.locator('main').innerText();
  kontrola('zkušební: příjmový doklad', /PPD-\d{4}-00001/.test(telo) && /5\s000\sKč/.test(telo), telo.slice(0, 400));
  await p.click('main button:has-text("Výdej")'); await p.waitForTimeout(200);
  await dlg.locator('label:has-text("Částka") input').fill('9999');
  await dlg.locator('label:has-text("Účel") input').fill('Vstupné');
  await ulozit('Vydat a vystavit doklad');
  kontrola('zkušební: výdej nad zůstatek nejde', /není dost peněz/.test(await p.locator('body').innerText()));
  await dlg.locator('label:has-text("Částka") input').fill('200');
  await ulozit('Vydat a vystavit doklad');
  telo = await p.locator('main').innerText();
  kontrola('zkušební: výdajový doklad a zůstatek', /VPD-\d{4}-00001/.test(telo) && /4\s800\sKč/.test(telo), telo.slice(0, 400));
  if (SHOT) await p.screenshot({ path: SHOT + '/finance-pokladna.png' });

  // přeplatky: dítě s přeplatkem z ukázkových dat
  await p.click('[role=tab]:has-text("Přeplatky a vratky")'); await p.waitForTimeout(200);
  const maPrepl = await p.locator('section[aria-label="Přeplatky"] button:has-text("Vrátit")').count();
  kontrola('zkušební: seznam přeplatků', maPrepl > 0);
  if (maPrepl) {
    await p.locator('section[aria-label="Přeplatky"] button:has-text("Vrátit")').first().click(); await p.waitForTimeout(200);
    await dlg.locator('label:has-text("Účet rodiče") input').fill('19-2000145399/0800');
    await dlg.locator('label:has-text("Částka") input').fill('100');
    await ulozit('Vrátit');
    telo = await p.locator('main').innerText();
    kontrola('zkušební: vratka připravena', /VR-\d{4}-00001/.test(telo) && telo.includes('Čeká na odeslání'), telo.slice(0, 300));
    const [dl] = await Promise.all([p.waitForEvent('download'), p.click('main button:has-text("Hromadný příkaz pro banku")')]);
    const kpc = path.join(os.tmpdir(), 'vratky-test.kpc'); await dl.saveAs(kpc);
    const abo = require('fs').readFileSync(kpc, 'utf8');
    kontrola('zkušební: ABO příkaz', /^UHL1\d{6}/.test(abo) && /\r\n2 19-2000145399 10000 \d{6}\r\n/.test(abo) && /\r\n3 \+\r\n5 \+\r\n$/.test(abo), abo.slice(0, 200));
  }

  // slevy
  await p.click('[role=tab]:has-text("Slevy a prominutí")'); await p.waitForTimeout(200);
  await p.click('main button:has-text("Nová sleva")'); await p.waitForTimeout(200);
  await dlg.locator('label:has-text("Hledat dítě") input').fill('Ema'); await p.waitForTimeout(150);
  await dlg.locator('button[aria-pressed]').filter({ hasText: 'Ema' }).first().click(); await p.waitForTimeout(150);
  await dlg.locator('button:has-text("Snížit o %")').click();
  await dlg.locator('label:has-text("Snížení (%)") input').fill('50');
  await dlg.locator('label:has-text("Důvod") input').first().fill('Sociální důvody');
  await ulozit('Uložit');
  kontrola('zkušební: sleva uložena', (await p.locator('main').innerText()).includes('Snížení o % 50 %'));

  // uzávěrka a export
  await p.click('[role=tab]:has-text("Uzávěrka a export")'); await p.waitForTimeout(200);
  const [dz] = await Promise.all([p.waitForEvent('download'), p.locator('main button:has-text("Export ZIP")').first().click()]);
  const zip = path.join(os.tmpdir(), 'export-test.zip'); await dz.saveAs(zip);
  const obsah = execSync(`python3 -I -c "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); print(z.testzip()); print(' '.join(z.namelist())); print(z.read('denik.csv').decode('utf-8-sig').splitlines()[0])" ${zip}`).toString();
  kontrola('zkušební: export ZIP pro účetní', /^None\n/.test(obsah) && /rekapitulace\.csv .*denik\.csv .*saldokonto\.csv/.test(obsah) && obsah.includes('Datum;Doklad;Druh;Popis;MD;Dal'), obsah);
  await p.locator('main button:has-text("Uzavřít")').first().click(); await p.waitForTimeout(200);
  await Promise.all([p.waitForEvent('download'), ulozit('Uzavřít a stáhnout export')]);
  telo = await p.locator('main').innerText();
  kontrola('zkušební: měsíc uzavřen', telo.includes('Uzavřeno') && telo.includes('Otevřít'));
  kontrola('zkušební finance bez chyb', !p.chyby.length, p.chyby.join(' / '));
  await konec();
};
