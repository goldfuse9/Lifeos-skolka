// Fotky v ostrém provozu (tablet): album třídy, nahrání (zmenšení v tabletu)
// do úložiště, zveřejnění rodičům, smazání. Rodič fotku vidí až po zveřejnění.
const { sql, sqlJako, stranka, konec, prihlas, kontrola } = require('./spolecne');
const RODA = 'aaaaaaaa-0000-4000-8000-000000000003', RODB = 'bbbbbbbb-0000-4000-8000-000000000003';
const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAACgAAAAeCAIAAADRv8uKAAAAK0lEQVR4nO3NMQ0AAAgDsMlBIhKRhQw4mvRvputExGKxWCwWi8VisVj8N17V/ZfbssFANwAAAABJRU5ErkJggg==', 'base64');
module.exports = async () => {
  const t = await stranka({ width: 1194, height: 834 });
  await prihlas(t, 'Třída', 'ucitelka@test.cz'); await t.waitForTimeout(800);
  await t.click('[role=tab]:has-text("Fotky")'); await t.waitForTimeout(500);
  await t.click('button:has-text("+ Nové album")'); await t.waitForTimeout(300);
  await t.fill('#album-nazev', 'Podzimní vycházka');
  await t.click('[role=dialog] button:has-text("Vytvořit a přidat fotky")'); await t.waitForTimeout(1200);
  const id = sql(`select id from alba where nazev = 'Podzimní vycházka'`);
  kontrola('album založeno na serveru (nezveřejněné)', !!id && sql(`select zverejneno is null from alba where id = '${id}'`) === 't');
  const telo = await t.locator('body').innerText();
  kontrola('upozornění na děti bez souhlasu s focením', /fotky s nimi nezveřejňujte/.test(telo));
  await t.setInputFiles('input[aria-label="Přidat fotky"]', [{ name: 'a.png', mimeType: 'image/png', buffer: PNG }, { name: 'b.png', mimeType: 'image/png', buffer: PNG }]); await t.waitForTimeout(3500);
  const cesty = sql(`select array_to_string(fotky, ',') from alba where id = '${id}'`).split(',').filter(Boolean);
  kontrola('2 fotky nahrané do úložiště a zapsané v albu', cesty.length === 2 && sql(`select count(*) from storage.objects where bucket_id = 'fotky' and name like '%/${id}/%'`) === '2', cesty.join(' '));
  kontrola('fotky zmenšené na JPEG', sql(`select count(*) from storage.objects where metadata ->> 'mimetype' = 'image/jpeg' and name like '%/${id}/%'`) === '2');
  kontrola('fotky se na tabletu zobrazí (podepsané odkazy)', (await t.locator('img[src*="/storage/v1/object/sign/fotky/"]').count()) >= 1);
  kontrola('rodič nezveřejněné fotky nevidí', sqlJako(RODA, '', `select count(*) from storage.objects where bucket_id = 'fotky';`) === '0');
  await t.click('button:has-text("Zveřejnit rodičům")'); await t.waitForTimeout(1200);
  kontrola('album zveřejněno', sql(`select zverejneno is not null from alba where id = '${id}'`) === 't');
  kontrola('rodič třídy fotky vidí, rodič jiné školky ne', sqlJako(RODA, '', `select count(*) from storage.objects where bucket_id = 'fotky';`) === '2' && sqlJako(RODB, '', `select count(*) from storage.objects where bucket_id = 'fotky';`) === '0');
  // smazání fotky v prohlížeči fotek
  await t.locator('button[aria-label="Fotka 1"]').click(); await t.waitForTimeout(400);
  await t.locator('[role=dialog] button:has-text("Smazat")').first().click(); await t.waitForTimeout(1500);
  kontrola('smazaná fotka zmizí z úložiště i z alba', sql(`select coalesce(array_length(fotky, 1), 0) from alba where id = '${id}'`) === '1' && sql(`select count(*) from storage.objects where name like '%/${id}/%'`) === '1');
  kontrola('fotky bez chyb na stránce', !t.chyby.length, t.chyby.join(' / '));
  await konec();
};
