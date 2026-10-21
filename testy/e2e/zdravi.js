// Zdraví: léky od rodičů (LifeOS) → tablet „Teď podat“ → kniha podání → ředitelna.
// Rodič posílá lék funkcí posli_lek_skolce (jako LifeOS), učitelka podá / nepodá
// na tabletu, ředitelka vidí přehled, upozornění a doplní, kde je lék uložen.
const { sql, sqlJako, stranka, konec, prihlas, kontrola } = require('./spolecne');
const EMA = '00000000-0000-4000-8000-000000000101', OLI = '00000000-0000-4000-8000-000000000102';
const RODA = 'aaaaaaaa-0000-4000-8000-000000000003', ROD2 = 'aaaaaaaa-0000-4000-8000-000000000008';
module.exports = async () => {
  // Čas „teď“ podle hodin prohlížeče (tablet porovnává se svými hodinami).
  const d = new Date(), m = d.getHours() * 60 + d.getMinutes() - (d.getMinutes() % 5);
  const ted = String(Math.floor(m / 60)).padStart(2, '0') + ':' + String(m % 60).padStart(2, '0');
  const den = d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
  sqlJako(RODA, '', `select posli_lek_skolce('${EMA}', 'lek-ventolin', 'Ventolin', '1 vdech', '{${ted}}', true, 'Při dušnosti 2 vdechy.', null, 'Jana Testová');`);
  sqlJako(RODA, '', `select uprav_zdravi_rodicem('${EMA}', null, 'Při dušnosti posadit a volat rodiče.');`);
  sqlJako(ROD2, '', `select posli_lek_skolce('${OLI}', 'lek-zyrtec', 'Zyrtec', '5 kapek', '{${ted}}', false, null, null, 'Tomáš Zkušební');`);
  sql(`insert into dochazka (dite_id, den, stav, prichod) values ('${EMA}', '${den}', 'pritomen', '07:30'), ('${OLI}', '${den}', 'pritomen', '07:40') on conflict (dite_id, den) do update set stav = 'pritomen', prichod = excluded.prichod, odchod = null;`);

  const t = await stranka({ width: 1194, height: 834 });
  await prihlas(t, 'Třída', 'ucitelka@test.cz');
  const pruh = t.locator('section[aria-label="Lék k podání"]');
  kontrola('tablet: pruh „Teď podat“ s lékem z LifeOS', (await pruh.count()) === 1 && /Ventolin 1 vdech|Zyrtec 5 kapek/.test(await pruh.innerText()), (await pruh.count()) ? await pruh.innerText() : 'není');
  const prvni = /Ema/.test(await pruh.innerText()) ? 'Ema' : 'Oliver';
  await pruh.locator('button:text-is("Podáno")').click(); await t.waitForTimeout(1500);
  const lekPrvni = prvni === 'Ema' ? EMA : OLI;
  kontrola('Podáno → kniha podání (podáno, kdo zapsal)', /^podano\|.+/.test(sql(`select stav || '|' || coalesce(zapsal_jmeno,'') from podani_leku where dite_id='${lekPrvni}' and zruseno is null`)));
  // druhé dítě: Nepodáno → důvod
  kontrola('pruh ukáže další lék', (await pruh.count()) === 1 && /Nepodáno/.test(await pruh.innerText()));
  await pruh.locator('button:has-text("Nepodáno")').click(); await t.waitForTimeout(300);
  kontrola('Uložit bez důvodu nejde', (await t.locator('[role=dialog] button:has-text("Vyberte důvod")').count()) === 1);
  await t.click('[role=dialog] button:has-text("Lék chybí")');
  await t.fill('#lek-poznamka', 'Prosíme o nový');
  await t.click('[role=dialog] button:has-text("Uložit · nepodáno")'); await t.waitForTimeout(1500);
  const druhy = prvni === 'Ema' ? OLI : EMA;
  kontrola('Nepodáno → důvod a poznámka v knize', sql(`select stav || '|' || duvod || '|' || poznamka from podani_leku where dite_id='${druhy}'`) === 'nepodano|chybi|Prosíme o nový');
  // Vrátit u podání (omyl)
  const ban = await pruh.count();
  if (ban) { await pruh.locator('button:has-text("Vrátit")').click(); await t.waitForTimeout(1500); }
  kontrola('Vrátit = záznam zrušen, v knize zůstane', sql(`select count(*) || '|' || count(zruseno) from podani_leku where dite_id='${lekPrvni}'`) === '1|1');
  // Ema: lék při potížích z karty dítěte
  await t.click('section[aria-label="Děti"] button[aria-label^="Ema"]'); await t.waitForTimeout(300);
  let panel = await t.locator('aside[aria-label="Vybrané dítě"]').innerText();
  kontrola('karta dítěte: postup při potížích a léky od rodičů', panel.includes('Při dušnosti posadit') && panel.includes('Podat teď'));
  await t.click('aside[aria-label="Vybrané dítě"] button:has-text("Podat teď")'); await t.waitForTimeout(300);
  kontrola('okno ukáže pokyn rodičů', (await t.locator('[role=dialog]').innerText()).includes('Při dušnosti 2 vdechy'));
  await t.click('[role=dialog] button:has-text("Uložit · podáno")'); await t.waitForTimeout(1500);
  kontrola('podání při potížích (bez času z rozpisu)', sql(`select count(*) from podani_leku where dite_id='${EMA}' and planovano is null and stav='podano'`) === '1');
  panel = await t.locator('aside[aria-label="Vybrané dítě"]').innerText();
  kontrola('podání je v dnešku dítěte', /Lék podán · Ventolin/.test(panel));
  kontrola('rodič vidí podání svého dítěte', +sqlJako(RODA, '', 'select count(*) from podani_leku;') >= 1 && sqlJako(RODA, '', `select count(*) from podani_leku where dite_id<>'${EMA}';`) === '0');
  kontrola('tablet bez chyb JS', !t.chyby.length, t.chyby.join('; '));

  // ředitelna
  const r = await stranka();
  await prihlas(r, 'Ředitelna', 'reditelka@test.cz');
  await r.click('nav button:has-text("Zdraví a léky")'); await r.waitForTimeout(1200);
  const strana = await r.locator('main').innerText();
  kontrola('ředitelna: přehled léků (Ventolin, Zyrtec)', strana.includes('Ventolin · 1 vdech') && strana.includes('Zyrtec · 5 kapek'));
  kontrola('ředitelna: upozornění „chybí“ a „kde je lék“', /chybí/.test(strana) && /kde je/.test(strana));
  kontrola('ředitelna: kniha podání dnes', /Kniha podání · dnes/.test(strana) && /nepodáno/.test(strana));
  await r.click('button[aria-label^="Zdraví: Ema"]'); await r.waitForTimeout(300);
  await r.click('[role=dialog] button:has-text("Změnit")');
  await r.fill('[role=dialog] input[aria-label="Kde je lék uložen"]', 'skříňka ve třídě');
  await r.click('[role=dialog] button:has-text("Uložit")'); await r.waitForTimeout(1200);
  kontrola('ředitelka doplní, kde je lék', sql(`select ulozeni from leky_ve_skolce where dite_id='${EMA}'`) === 'skříňka ve třídě');
  kontrola('ředitelna bez chyb JS', !r.chyby.length, r.chyby.join('; '));

  // hospodářka stránku nevidí
  const h = await stranka();
  await prihlas(h, 'Ředitelna', 'hospodarka@test.cz');
  kontrola('hospodářka nemá Zdraví a léky', !(await h.locator('nav[aria-label="Ředitelna"]').innerText()).includes('Zdraví a léky'));
  await konec();
};
