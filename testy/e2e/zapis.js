// Zápis (přijímací řízení) v ostrém provozu: žádosti na serveru s
// registračními čísly, rozhodnutí, kroky „zveřejněno/odesláno“ jen jako
// záznam (aplikace nic neodesílá), převod přijatých do kartotéky.
const { sql, stranka, konec, prihlas, kontrola } = require('./spolecne');
module.exports = async () => {
  const p = await stranka({ width: 1366, height: 900 });
  await prihlas(p, 'Ředitelna', 'reditelka@test.cz'); await p.waitForTimeout(800);
  await p.click('nav button:has-text("Zápis")'); await p.waitForTimeout(500);
  const rok = sql(`select case when extract(month from now()) >= 9 then extract(year from now())::int + 1 else extract(year from now())::int end`);
  const nova = async (jm, pr, rc, spad) => {
    await p.click('button:has-text("+ Nová žádost")'); await p.waitForTimeout(300);
    await p.fill('[role=dialog] input[placeholder="Např. Tereza"]', jm);
    await p.fill('[role=dialog] input[placeholder="Např. Malá"]', pr);
    await p.fill('[role=dialog] input[placeholder="RRMMDD/XXXX"]', rc);
    if (spad) await p.click('[role=dialog] button[aria-pressed]:has-text("Ano") >> nth=0');
    await p.click('[role=dialog] button:has-text("Zapsat žádost")'); await p.waitForTimeout(1200);
  };
  await nova('Klára', 'Zápisová', '225707/0002', true);
  await nova('Hugo', 'Zápisový', '230110/0010', false);
  kontrola('žádosti uloženy na server s reg. čísly Z001, Z002', sql(`select string_agg(reg_cislo || ':' || jmeno, ',' order by reg_cislo) from zadosti where rok=${rok}`) === 'Z001:Klára,Z002:Hugo');
  kontrola('Z001: spád, pohlaví a datum narození z RČ', sql(`select spadovy || '|' || pohlavi || '|' || datum_narozeni from zadosti where reg_cislo='Z001' and rok=${rok}`) === 'true|F|2022-07-07');
  // rozhodnutí
  await p.click('button:has-text("Rozhodnout podle kritérií")'); await p.waitForTimeout(1200);
  kontrola('rozhodnuto: oba mají výsledek a pořadí', sql(`select count(*) from zadosti where rok=${rok} and vysledek is not null and poradi is not null`) === '2'
    && sql(`select rozhodnuto is not null from zapis_rocnik where rok=${rok}`) === 't');
  const v1 = () => sql(`select vysledek from zadosti where reg_cislo='Z001' and rok=${rok}`);
  const pred = v1();
  await p.click('button[aria-label^="Výsledek Z001"]'); await p.waitForTimeout(1000);
  kontrola('klepnutí změní výsledek na serveru', v1() !== pred && !!v1(), pred + ' → ' + v1());
  if (v1() !== 'prijato') { await p.click('button[aria-label^="Výsledek Z001"]'); await p.waitForTimeout(1000); }
  // kroky jen jako záznam
  kontrola('krok zveřejnění se nevydává za automatické', (await p.locator('button:has-text("Označit seznam jako zveřejněný")').count()) === 1 && !(await p.locator('button:has-text("Zveřejnit seznam")').count()));
  await p.click('button:has-text("Označit seznam jako zveřejněný")'); await p.waitForTimeout(1000);
  kontrola('zveřejnění zaznamenáno', sql(`select zverejneno is not null from zapis_rocnik where rok=${rok}`) === 't');
  await p.click('button:has-text("Označit rozhodnutí jako odeslaná")'); await p.waitForTimeout(1000);
  kontrola('odeslání zaznamenáno (i u žádostí)', sql(`select count(*) from zadosti where rok=${rok} and rozhodnuti_odeslano is not null`) === '2');
  const hl = await p.locator('body').innerText();
  kontrola('hláška říká, že rozhodnutí aplikace neodesílá', /neodesílá/.test(hl));
  await p.click('button[aria-label^="Výsledek Z001"]'); await p.waitForTimeout(800);
  kontrola('po odeslání výsledek nejde změnit', v1() === 'prijato');
  // převod do kartotéky
  await p.click('button:has-text("Převést přijaté do kartotéky")'); await p.waitForTimeout(2500);
  kontrola('přijaté dítě je v kartotéce s nástupem 1. 9. a RČ', sql(`select count(*) from deti where jmeno='Klára' and prijmeni='Zápisová' and zahajeni='${rok}-09-01' and rodne_cislo='225707/0002'`) === '1');
  kontrola('převod zaznamenán', sql(`select preneseno is not null from zapis_rocnik where rok=${rok}`) === 't');
  await p.click('nav button:has-text("Kartotéka dětí")'); await p.waitForTimeout(600);
  kontrola('kartotéka ukazuje převedené dítě (bez třídy)', (await p.locator('body').innerText()).includes('Zápisová'));
  await p.click('text=Klára Zápisová'); await p.waitForTimeout(600);
  const tr = p.locator('button[aria-pressed]:has-text("Sluníčka")');
  if (await tr.count()) { await tr.last().click(); await p.waitForTimeout(1800); }
  kontrola('převedenému dítěti jde v kartě přiřadit třídu', sql(`select t.nazev from deti d join tridy t on t.id=d.trida_id where d.jmeno='Klára' and d.prijmeni='Zápisová'`) === 'Sluníčka');
  await p.click('[aria-label="Zavřít kartu"]').catch(() => {}); await p.waitForTimeout(300);
  // po obnovení se stav načte ze serveru
  await p.reload(); await prihlas(p, 'Ředitelna', 'reditelka@test.cz').catch(() => {}); await p.waitForTimeout(800);
  await p.click('nav button:has-text("Zápis")'); await p.waitForTimeout(500);
  const t2 = await p.locator('body').innerText();
  kontrola('po obnovení: žádosti a hotové kroky ze serveru', t2.includes('Z001') && t2.includes('Z002') && !(await p.locator('button:has-text("Rozhodnout podle kritérií")[aria-disabled="false"]').count()));
  kontrola('zápis bez chyb na stránce', !p.chyby.length, p.chyby.join(' / '));
  await konec();
};
