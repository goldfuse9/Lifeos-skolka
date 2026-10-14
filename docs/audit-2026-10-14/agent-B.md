# Audit B — Ředitelna (Školka / LifeOS)

Datum: 14. 10. 2026 · Zmrazená kopie: `/home/claude/skolka-audit` (kód jsem neměnil)
Prostředí: vlastní lokální instance `skolka_b` (PostgREST 3021, proxy 3022, web 8821), Playwright + Chromium; config.js vždy přesměrovaný na lokální proxy a navíc zablokované všechny požadavky na `*.supabase.co`.
Skripty, logy a screenshoty: `scratchpad/audit/B/` (`t1-prohlidka.js` … `t10-server-ok.js`, `*.log`, `shots/*.png`).

Poznámka k prostředí: databáze `skolka_b` už existovala s jinými daty (účty `*@test.lifeos.cz`). Po `testy/reset.sh skolka_b` PostgREST načetl neúplnou cache schématu (chyběla `muj_stav` → přihlášení vracelo 404). Pomohlo `NOTIFY pgrst, 'reload schema'`, proto jsem použil vlastní `B/reset.sh` (reset + reload). Na tohle by měl pamatovat i `testy/reset.sh` (viz B14).

## Shrnutí v jedné větě

V ostrém provozu čtou nebo zapisují server jen **Přístupy** a **Rodiče v LifeOS** (a jedno čtení `skoly.nahrady_obedu` v jídelně). **Všech ostatních 15 stránek** ukazuje ukázková data „MŠ Sluníčko“ pod názvem skutečné školky. Jejich formuláře hlásí úspěch („Pozvánka odeslána“, „Odesláno: 52× do aplikace“), ale ukládají jen do `localStorage`. Tenhle `localStorage` sdílejí všechny školky, které se přihlásí ve stejném prohlížeči.

## 1. Inventář stránek

Režim v ostrém provozu: **SERVER** = čte a zapisuje DB, **UKÁZKA** = ukázková data v kódu, **LS** = změny jdou jen do `localStorage` (`skolka-reditel-v1`, `skolka-sdilene-v1`).
Stav: OVĚŘENO = funguje správně (ověřeno testem), SELHÁVÁ = test ukázal chybné chování, CHYBÍ = funkce nebo napojení neexistuje.
Role: Ř = ředitelka, Z = zástupkyně, H = hospodářka (viditelnost v menu je ověřená prohlídkou t1 pro všechny tři role v obou režimech).

| Stránka | Role (menu) | Zkušební provoz | Ostrý provoz | Stav v ostrém | Co by měla používat v DB (setup.sql) | API v server.js |
|---|---|---|---|---|---|---|
| Přehled | Ř Z H | LS, OK | UKÁZKA (53/62 dětí, „Dnes chybí Alena Benešová“, úraz Kamil Kos) | SELHÁVÁ | `deti`, `dochazka` (dnes), `urazy`, `tridy`, `uzivatele`, `predpisy` | žádné |
| Kartotéka dětí | Ř Z H (H jen čte) | LS, OK | UKÁZKA + LS (62 dětí místo 1) | SELHÁVÁ | `deti`, `zastupci`, `poverene_osoby`, `souhlasy` (RLS `deti_menit` = vedení) | jen `detiSkoly()` (výběr pro LifeOS), zápis chybí |
| Zápis | Ř Z | LS, OK | UKÁZKA + LS (34 žádostí) | SELHÁVÁ | `zadosti` | žádné |
| Docházka | Ř Z H | LS, OK | UKÁZKA (panel „Dnes z tabletů“ má štítek „ukázka“) | SELHÁVÁ | `dochazka` (měsíc), `deti`, `tridy` | `denTridy` je interní, jen pro tablet, jen dnešek |
| Třídy | Ř Z | LS, OK | UKÁZKA + LS (Sluníčka/Berušky/Motýlci, v DB je jen Žabky) | SELHÁVÁ | `tridy`, `ucitel_trida` | jen `tridySkoly()` (id, název), jen čtení |
| Učitelé | Ř Z | LS, OK | UKÁZKA + LS („Pozvánka odeslána“, ale nic se nepošle) | SELHÁVÁ | `uzivatele`, `ucitel_trida`, RPC `pozvi_zamestnance` | `zamestnanci()`, `pozviZamestnance()` existují, stránka je nevolá |
| Porady | Ř Z | LS, OK | LS | SELHÁVÁ | `porady` | žádné |
| Školní jídelna | Ř | odkaz na desku Jídelna | deska Jídelna: hlavička „MŠ Sluníčko · Zkušební provoz“, ukázkové porce a diety; síť: jen `GET skoly?select=nahrady_obedu` | SELHÁVÁ (patří i auditu jídelny) | `jidelnicek`, `jidla`, `diety`, `dochazka` | `zverejniJidelnicek`, `nahradyObedu`, `nastavNahrady` |
| Rodiče v LifeOS | Ř Z (jen ostrý) | není v menu (správně) | SERVER | OVĚŘENO | `deti`, `zastupci`, RPC `vytvor_kod_rodice` | `detiSkoly`, `kodRodice` |
| Zprávy rodičům | Ř Z H | LS, OK | UKÁZKA + LS (toast „Odesláno: 52× do aplikace, 11× e-mailem“) | SELHÁVÁ | `zpravy` (insert: vedení + hospodářka) | žádné |
| Webové stránky | Ř Z | LS, OK | UKÁZKA (adresa „Na Hutích 12“, IČO 70891234) | SELHÁVÁ / CHYBÍ schéma | `skoly` nemá sloupce pro adresu, IČO, DS ani web; tabulka pro web chybí | žádné |
| Platby | Ř Z H | LS, OK | UKÁZKA + LS (tlačítko „Ukázkový výpis“ je i v ostrém) | SELHÁVÁ | `predpisy`, `predpis_polozky`, `platby`, `nesparovane_platby`, `upominky`, `ucetni_pohyby`, `konta`, `financni_nastaveni`, `sazby_stravneho` | žádné |
| Matrika MŠMT | Ř Z | LS, OK | UKÁZKA (IZO 600012345 místo 000000002 z DB) | SELHÁVÁ | `deti`, `skoly` (izo, red_izo, cast_skoly) | žádné |
| Kniha úrazů | Ř Z | LS, OK | UKÁZKA + LS; skutečný úraz z DB („odřené koleno (B)“) chybí | SELHÁVÁ | `urazy` (čtení, update `zaznam_odeslan`, `dny_absence`) | jen `uraz()` (insert z tabletu), čtení chybí |
| Dokumenty | Ř Z | LS, OK | UKÁZKA + LS | CHYBÍ schéma | tabulka dokumentů chybí (verze, schváleno, na webu) | žádné |
| Archiv (historie změn) | Ř Z H | LS, OK | LS; akce ředitelky B se zapisují jako „Ivana Pokorná“ | SELHÁVÁ | `audit_log` (triggery už plní deti/urazy/pozvanky…) | žádné |
| Nastavení školky | Ř Z | LS, OK | UKÁZKA + LS (název „MŠ Sluníčko“, ředitelka Ivana Pokorná) | SELHÁVÁ | `skoly` (update = vedení), `financni_nastaveni`, `sazby_stravneho` | žádné |
| Přístupy | Ř, Z jen v ostrém | LS (shell.js), OK | SERVER | OVĚŘENO | RPC `zamestnanci_skoly`, `pozvi_zamestnance`, `nastav_ucet_zamestnance`, `admin_zrus_pozvanku` | ano |

Doplňkové kontroly:
- **Oddělení školek v DB: OVĚŘENO.** `sqlJako` jako ředitelka B: `deti` = jen Adam, `tridy` = jen Žabky, `zamestnanci_skoly()` = jen účty B. `vytvor_kod_rodice` pro dítě školky A skončí výjimkou. V UI Přístupy a Rodiče v LifeOS ukazují jen B (t1, t3, t4).
- **Oddělení školek v UI: SELHÁVÁ** kvůli sdílenému `localStorage` (B2).
- **Role v DB: OVĚŘENO.** Hospodářka: `zamestnanci_skoly` i `pozvi_zamestnance` skončí výjimkou, `urazy` = 0 řádků, `vytvor_kod_rodice` skončí výjimkou. V UI nemá v menu Přístupy, Rodiče v LifeOS ani Kniha úrazů a tlačítko „+ Přidat dítě“ se jí nezobrazí (t1, t3, t6).
- **Validace v Přístupech (ostrý): OVĚŘENO.** Prázdný formulář vrátí „Vyplňte jméno a platný e-mail.“, duplicitní e-mail „Tento e-mail už ve školce přístup má.“, učitelka bez třídy je odmítnuta (t7 a existující `pristupy.js`).
- **Výpadek serveru (proxy 3022 zastavena):**
  - Přístupy: „Nový přístup“ i „Zablokovat“ ukážou „Server není dostupný…“. OVĚŘENO (t7, `shots/t7-vypadek-*.png`).
  - Rodiče v LifeOS: chyba se ukáže až po zhruba 7 s, protože supabase-js zkouší požadavek čtyřikrát. Do té doby svítí „Načítám…“ (t8).
  - Kartotéka: „Přidat dítě“ při výpadku hlásí úspěch („Offline přidána“), protože server vůbec nevolá (t7).
- **Konzole:** žádné `pageerror` v žádném běhu. Jediné chyby „Failed to load resource: ERR_FAILED“ jsou Google Fonts, které testovací prostředí záměrně blokuje (ověřeno přes `requestfailed`, t9).
- **1440×900 a 1194×834:** při 1194×834 je deska zmenšená (`--z` = 0,829), nic nepřetéká a stránka se nikam neposouvá (t9, 7 stránek, `shots/t9-1194-*.png`). Rozvržení je v pořádku.
- **Tlačítka bez akce:** statická kontrola všech 80 obsluh `onClick` v šabloně našla ke každé funkci v kódu. Tlačítko bez akce nebylo nalezeno. Problémem je, že akce předstírají úspěch (B1).

## 2. Nálezy

### B1 — Kritická — Formuláře v ostrém provozu hlásí úspěch, ale do DB nic neuloží
- **Soubor:** `Reditel.dc.html`
  - 3854–3870 Přidat dítě, 3873–3888 Přidat učitele, 3891–3906 Nová třída, 3950–3964 Porada, 3405–3411 Zprávy rodičům
  - 3751–3756 a 3819 Nastavení (`fIn` mění jen `this.school`)
  - 3247–3290 Platby (předpisy, upomínky), 3314 `pay.demo`, 4002–4009 záznam o úrazu
  - Ukládání: 1849–1874 (`restore`/`save` do `localStorage`)
- **Popis:** V ostrém provozu tyto akce ukážou potvrzení, ale zapíšou jen do `localStorage`. Žádný požadavek na server nevznikne a ostatní zařízení ani rodiče nic nedostanou:
  - Přidat dítě: „Tereza přidána“
  - Nová třída: „Třída Auditníci založena“
  - Přidat učitele: „Pozvánka odeslána na klara.audit@test.cz“
  - Zprávy rodičům: „Odesláno: 52× do aplikace, 11× e-mailem“
  - Porady: „Zápis z porady uložen“
  - Nastavení: změna názvu
  - Platby: hospodářka nahraje výpis „Zaplaceno přesně 3“, upomínky, předpisy
  - Kniha úrazů: „Záznam o úrazu odeslán ČŠI a pojišťovně (zkušební provoz)“ (text zmiňuje zkušební provoz i v ostrém)
- **Reprodukce:** Ostrý provoz → přihlásit `reditelka.b@test.cz` → Kartotéka → „+ Přidat dítě“ → vyplnit → uložit. Potom Třídy → „+ Nová třída“, Učitelé → „+ Přidat učitele“, Zprávy rodičům → „Poslat rodičům“, Porady → „+ Nový zápis“, Nastavení → Krátký název.
- **Jak ověřeno:**
  - `t2-zapisy.js`: SQL počty pro školku B před i po jsou stejné (`deti 1, tridy 1, zpravy 0, porady 0, pozvanky 0, uzivatele 3, audit 0, nazev "MŠ Dejvice (test)"`). Mezi akcemi nevznikl žádný požadavek na `/rest/v1`, jen přihlášení. Po obnovení stránky je „Tereza Auditní“ stále v kartotéce, tedy z `localStorage`. Toasty jsou zalogované v `t2.log`.
  - `t6-platby.js` (hospodářka A): po „Ukázkovém výpisu“ a „Poslat rodičům“ jsou `platby`, `ucetni_pohyby`, `predpisy`, `upominky`, `zpravy` beze změny a síť je prázdná.
  - `t7`: „Přidat dítě“ hlásí úspěch i při vypnuté proxy.
- **Oprava:** Dokud stránka nemá serverové API, v ostrém provozu (`SRVON`) zakázat zápisové akce a zobrazit na stránce viditelný pruh „Ukázka — v ostrém provozu se zatím neukládá“. Pak napojit tyto tabulky a RPC (RLS je pro ně v setup.sql připravená):

  | Stránka | Napojit na | Pozn. |
  |---|---|---|
  | Kartotéka | `deti`, `zastupci`, `poverene_osoby`, `souhlasy` | insert/update přes `deti_menit`; VS podle `financni_nastaveni.vs_schema` |
  | Třídy | `tridy`, `ucitel_trida` | |
  | Učitelé | `zamestnanci()` a `pozviZamestnance()` (RPC `pozvi_zamestnance`) místo lokálního `teachers` | ideálně sloučit s Přístupy |
  | Porady | `porady` | |
  | Zprávy | `zpravy` | insert, a mechanismus doručení (push / e-mail), jinak toast nesmí tvrdit „Odesláno 52×“ |
  | Nastavení | `skoly` (update) | doplnit sloupce adresa, IČO, DS, web, provozní doba atd.; `financni_nastaveni`, `sazby_stravneho` |
  | Platby | `predpisy`, `predpis_polozky`, `platby`, `nesparovane_platby`, `upominky`, `ucetni_pohyby` | ideálně RPC (párování a pohyby atomicky, sdílet logiku se `server/finance`) |
  | Kniha úrazů | `urazy` | select + update `zaznam_odeslan`, `dny_absence` |
  | Zápis | `zadosti` | |

  Tlačítko „Ukázkový výpis“ v ostrém provozu skrýt.

### B2 — Kritická — Data ředitelny sdílí `localStorage` napříč školkami a účty; po odhlášení zůstávají
- **Soubor:** `Reditel.dc.html` 1832, 1842, 1851, 1872 (pevné klíče `skolka-reditel-v1` a `skolka-sdilene-v1` bez ID školky nebo účtu); `shell.js` 244–249 (`odhlas()` maže jen `skolka-prihlaseni-v1`).
- **Popis:** Co ředitelka B zadá v ředitelně (děti s rodnými čísly, zprávy, třídy…), uvidí ve stejném prohlížeči ředitelka jiné školky A. Totéž platí pro hospodářku nebo zástupkyni. Osobní údaje (RČ) zůstanou nešifrovaně v prohlížeči i po odhlášení. Na sdíleném počítači ve sborovně jde o únik osobních údajů (GDPR).
- **Reprodukce:**
  1. Přihlásit `reditelka.b@test.cz`.
  2. Kartotéka: přidat „Tajná Béčková“ s RČ. Zprávy: odeslat „Interní zpráva školky B“.
  3. Odhlásit.
  4. Přihlásit `reditelka@test.cz` (školka A).
  5. Kartotéka i Zprávy obsahují záznamy školky B.
- **Jak ověřeno:** `t4-tenant.js`: „A vidí dítě zapsané ředitelkou B: true“, „A vidí zprávu ředitelky B: true“. Po odhlášení zůstávají klíče `skolka-reditel-v1`, `skolka-sdilene-v1`. Screenshot `shots/t4-A-vidi-B-dite.png`. Serverové stránky (Rodiče v LifeOS) neunikají: A vidí Emu, ne Adama.
- **Oprava:** V ostrém provozu ředitelna nemá ukládat data školky do `localStorage` vůbec (zdrojem je DB). Do doby napojení aspoň:
  - klíče rozlišit podle `skolaId` a uživatele (`skolka-reditel-v1:<skola>:<uid>`);
  - v `SkolkaUcet.odhlas()` a při změně účtu mazat `skolka-reditel-v1`, `skolka-sdilene-v1`, `skolka-jidelna-v1`;
  - v ostrém provozu nenačítat `restore()`.

### B3 — Kritická — Ukázková data se v ostrém provozu tváří jako skutečná data školky
- **Soubor:** `Reditel.dc.html` 4049–4050 (název školy z účtu, štítek „Pilot · část ukázková“, vysvětlení jen v atributu `title`), 2640–2700 (`renderVals` bere `this.kids`, `this.classes`, `this.teachers` z ukázky).
- **Popis:** Ředitelka školky B vidí v hlavičce název „MŠ Dejvice (test)“, ale pod ním ukázková data MŠ Sluníčko:
  - Přehled: 53/62 dětí, „Dnes chybí Alena Benešová“, „Záznam o úrazu: Kamil Kos – vyplnit do 5. 11.“
  - Kartotéka: 62 dětí s RČ
  - Matrika: IZO 600012345 (v DB 000000002)
  - Nastavení: „Ředitelka Ivana Pokorná“
  - Platby: 94 524 Kč

  Jediné vysvětlení je tooltip štítku. Na stránkách kromě panelu „Dnes z tabletů“ žádný štítek „ukázka“ není. Hrozí:
  - Matrika: export pro MŠMT ze smyšlených dětí pod skutečnou školou;
  - Kniha úrazů: odeslání smyšleného záznamu ČŠI;
  - Platby: upomínky „dlužníkům“, kteří neexistují.
- **Reprodukce:** Ostrý provoz → `reditelka.b@test.cz` → projít všechny stránky.
- **Jak ověřeno:**
  - `t1-prohlidka.js` (log `t1-server-redB.log`, screenshoty `shots/server-reditelka.b-1440-*.png`, `t9-1194-Pehled.png`): v Kartotéce, Docházce a Platbách jsou ukázková jména (Jonáš Procházka…), skutečné dítě „Adam Cizí“ chybí.
  - `t5-tablet.js`: vložil jsem do DB docházku Adama na dnešek a teplotu. Ředitelna je neukáže na Přehledu, v Docházce, Kartotéce, Platbách, Matrice ani v Knize úrazů. Úraz „odřené koleno (B)“, který v DB je, v Knize úrazů chybí (`shots/t5-kniha-urazu-B.png`).
- **Oprava:** V ostrém provozu nenačítat ukázková data (`this.kids`, `classes`, `teachers`, `urazy`, `fin`…). Stránky bez serverového napojení skrýt, nebo ukázat prázdný stav „Tato část ještě není napojená na server“. Štítek „ukázka“ dát přímo na stránku, ne do `title`. Prioritně napojit čtení: `deti`/`tridy` (Kartotéka, Třídy, Přehled), `dochazka` (Docházka, Přehled), `urazy` (Kniha úrazů), `skoly` (Nastavení, Matrika).

### B4 — Vysoká — Docházka a úrazy z tabletů do ředitelny nedorazí
- **Soubor:** `server.js` 229–254 (tablet zapisuje do `dochazka`, `udalosti_ditete`, `urazy`); `Reditel.dc.html` 2648–2656 (ředitelna čte jen `window.__skolka` a `localStorage` `skolka-sdilene-v1`).
- **Popis:** Ve zkušebním provozu propojení tablet → ředitelna funguje přes sdílený objekt v prohlížeči. V ostrém provozu tablet zapisuje do DB, ale ředitelna DB nečte. Ředitelka se tak o úrazu zapsaném učitelkou nedozví a nevyplní záznam pro ČŠI. Zákonná lhůta se tím může zmeškat.
- **Jak ověřeno:** `t5-tablet.js`, viz B3: `urazy` B v DB = „1/2026 odřené koleno (B)“, Kniha úrazů ho neobsahuje. Docházka Adama „pritomen 07:45“ není nikde vidět.
- **Oprava:** Do server.js přidat `urazySkoly(rok)` (select `urazy` + `deti(jmeno, prijmeni, trida_id)`), `uzavriUraz(id, {dny_absence, zaznam_odeslan})` (update, RLS `uraz_menit`) a `dochazkaMesic(od, do)` (select `dochazka` + `deti`). Kniha úrazů a Docházka je pak mají použít. Realtime stačí stejný jako u tabletu (`sleduj`).

### B5 — Vysoká — Historie změn (Archiv) zapisuje akce pod ukázkovým jménem
- **Soubor:** `Reditel.dc.html` 1882–1886 (`log()` bere `this.users[role].name`, tedy ukázkovou „Ivanu Pokornou“, ne `this.ucet.jmeno`).
- **Popis:** Ředitelka B (Jana Nová) založí třídu a Archiv zapíše „Založena třída Logovací — Ivana Pokorná“. Historie změn „pro kontrolu a GDPR“ tak uvádí špatnou osobu. Navíc vede jen lokální kopii, ne `audit_log`, který DB triggery už plní (pozvanky, parovaci_kody, deti…).
- **Jak ověřeno:** `t5-tablet.js`: řádek v Archivu „Založena třída Logovací ¦ Ivana Pokorná · 14. 10. 2026“ (`shots/t5-archiv.png`).
- **Oprava:** V `log()` použít `this.ucet.jmeno`, když je k dispozici. V ostrém provozu zobrazovat `audit_log` (select je pro vedení povolen politikou `audit`) a lokální `this.audit` nepoužívat.

### B6 — Vysoká — Jídelna otevřená z ředitelny v ostrém provozu ukazuje „MŠ Sluníčko · Zkušební provoz“
- **Soubor:** `Jidelna.dc.html` (patří spíš auditu jídelny); vazba přes `Reditel.dc.html` 2648–2652 (alergie ukázkových dětí se ukládají do `skolka-sdilene-v1` a jídelna z nich počítá diety a porce).
- **Popis:** Ředitelka B klikne na „Školní jídelna“ a otevře se deska s názvem cizí školky, štítkem „Zkušební provoz“, 66 obědy a dietami ukázkových dětí („Ema K., Jonáš P.…“). Kuchyně by mohla vařit náhrady podle smyšlených alergií.
- **Jak ověřeno:** `t1` (ostrý, `reditelka.b`): přesměrování na `#jidelna`, síť jen `GET skoly?select=nahrady_obedu`, screenshot `shots/server-reditelka.b-1440-kolnjdelna.png`.
- **Oprava:** Porce a diety brát z `dochazka` + `deti.alergie` + `diety` (RLS `je_kuchyne`). Název školy brát z účtu. V ostrém provozu nesmí `skolka-sdilene-v1` z ředitelny ovlivňovat jídelnu.

### B7 — Vysoká — Nastavení, Webové stránky a Dokumenty nemají kam ukládat (chybí schéma)
- **Soubor:** `supabase/setup.sql` 36–42 (`skoly` má jen nazev, izo, red_izo, cast_skoly, rozliseni, doba_provozu, kontakt); `Reditel.dc.html` 3819–3827 (pole Úplný název, IČO, adresa, DS, web, pověřenec, úřední hodiny…).
- **Popis:** Ani po napojení server.js by většina polí Nastavení a obsah Webových stránek a Dokumentů neměly sloupce ani tabulky.
- **Jak ověřeno:** Porovnání polí formuláře (t2: pole „Krátký název“ obsahuje „MŠ Sluníčko“) se schématem `skoly`. Tabulka pro dokumenty a web v setup.sql není (`grep "create table"`).
- **Oprava:**
  - Rozšířit `skoly` o ico, adresa, telefon, email, datova_schranka, web, poverenec, uredni_hodiny, provozni_doba, zrizovatel.
  - Přidat tabulku `dokumenty (skola_id, klic, verze, obsah, schvaleno, na_webu, schvalil)`.
  - Web generovat ze `skoly` a `dokumenty`.

### B8 — Střední — Zástupkyně smí v ostrém provozu spravovat přístupy (ve zkušebním ne)
- **Soubor:** `shell.js` 254 (`smiSpravovat`: `u.server && u.kod === 'zastupce'`), komentář na řádcích 53–58 „Přístupy vytváří jen ředitelka“; `setup.sql` 1108–1134 (`je_vedeni()` = ředitelka i zástupkyně).
- **Popis:** Pravidla se mezi režimy liší. V ostrém provozu zástupkyně pozve další zástupkyni a zablokuje hospodářku nebo jinou zástupkyni. Ve zkušebním provozu stránku Přístupy nevidí.
- **Jak ověřeno:**
  - `t3-rls.js` jako zástupkyně: `pozvi_zamestnance(...,'zastupce')` vrátil kód `NATW-DGFC`; `nastav_ucet_zamestnance(hospodářka,false)` nastavil `aktivni=f` (pak vráceno zpět).
  - `t1`: zástupkyně má v ostrém provozu Přístupy v menu, ve zkušebním ne.
- **Oprava:** Rozhodnout záměr. Pokud má přístupy spravovat jen ředitelka: v RPC `pozvi_zamestnance` a `nastav_ucet_zamestnance` kontrolovat `moje_role() = 'reditelka'` a v `smiSpravovat` vyhodit větev pro zástupkyni. Jinak opravit komentář a zkušební provoz.

### B9 — Střední — Učitelé a Přístupy jsou dvě nezávislé evidence
- **Soubor:** `Reditel.dc.html` 3873–3888 vs. 3655–3740.
- **Popis:** V ostrém provozu ukazuje stránka Učitelé 8 ukázkových lidí a „Poslat pozvánku“ nic nepošle (B1), zatímco Přístupy ukazují skutečné 2 účty. Dialog „Přidat dítě“ i stránka Třídy nabízejí třídy Sluníčka/Berušky/Motýlci, ale Přístupy (server) nabízejí Žabky.
- **Jak ověřeno:** `t2` (třídy v dialogu „Sluníčka, Berušky, Motýlci“), `t1` (Přístupy: Eva Učitelka, Jana Nová; Učitelé: Ivana Pokorná, Petra Horáková…).
- **Oprava:** Učitele v ostrém provozu brát z `zamestnanci_skoly()` a `ucitel_trida`, pozvánky přes `pozvi_zamestnance`. Třídy všude z `tridy`.

### B10 — Střední — Profil a „Ředitelka“ v Nastavení jsou ukázkové osoby
- **Soubor:** `Reditel.dc.html` 3486–3493 (`mePerson` hledá v `this.teachers` podle jména, jinak vezme první ředitelku z ukázky), 4014–4040 (Uložit profil mění jen `this.teachers`).
- **Popis:** V ostrém provozu Nastavení uvádí „Ředitelka Ivana Pokorná“, profil se otevře s údaji ukázkové osoby a uložení nejde do `uzivatele`.
- **Jak ověřeno:** `t1` (text stránky Nastavení pro `reditelka.b`).
- **Oprava:** Profil číst a zapisovat z `uzivatele` (jméno; telefon a e-mail podle schématu).

### B11 — Nízká — Rodiče v LifeOS: při výpadku serveru se chyba ukáže až po ~7 s
- **Soubor:** `Reditel.dc.html` 3626–3631; supabase-js opakuje požadavek (4 pokusy: +0, +1, +3, +7 s).
- **Jak ověřeno:** `t8-lifeos-vypadek.js` (proxy zastavena): `requestfailed` v časech +63 ms, +1070 ms, +3074 ms, +7079 ms; po ~10 s „Nepodařilo se načíst: Server není dostupný…“.
- **Oprava:** Pro čtení v ředitelně nastavit kratší timeout nebo vypnout retry, případně ukázat „Server neodpovídá, zkouším znovu…“.

### B12 — Nízká — Chyba v Přístupech je jen dole v postranním panelu
- **Soubor:** `Reditel.dc.html` (blok `pr.hasErr2`).
- **Popis:** Po neúspěšném „Zablokovat“ zůstane seznam beze změny. Hláška „Server není dostupný“ je drobně v pravém dolním rohu, takže ji uživatelka snadno přehlédne.
- **Jak ověřeno:** `t7`, `shots/t7-vypadek-blokace.png`.
- **Oprava:** Ukázat chybu toastem nebo `role=alert` u řádku, u kterého akce selhala.

### B13 — Nízká — Pole v Nastavení nejsou svázaná s popisky (přístupnost)
- **Soubor:** `Reditel.dc.html` 3751–3756 (`fIn`) a příslušná šablona: popisek je samostatný `span`, `input` nemá `id`, `aria-label` ani obalující `label`.
- **Jak ověřeno:** `t2`: lokátor `label:has-text("Krátký název") input` nenašel nic (timeout 30 s); pole jsem musel najít přes XPath „následující input“.
- **Oprava:** Obalit pole do `<label>` nebo doplnit `aria-label="{{f.label}}"`.

### B14 — Nízká (testovací prostředí) — `reset.sh` nechá PostgREST se zastaralou cache schématu
- **Soubor:** `testy/reset.sh`
- **Popis:** Po `drop/create database` se PostgREST znovu připojí dřív, než doběhne setup.sql. Cache pak nezná část funkcí (`muj_stav` → PGRST202) a přihlášení selže hláškou „E-mail nebo heslo nesedí“ nebo 404.
- **Jak ověřeno:** Po resetu `curl POST /rest/v1/rpc/muj_stav` vrátil PGRST202; po `NOTIFY pgrst, 'reload schema'` je cache v pořádku (37 funkcí místo 25).
- **Oprava:** Na konec `reset.sh` přidat `psql … -c "notify pgrst, 'reload schema'"`.
- **Postřeh:** `pgrep -f "sbproxy.js $DB"` ve `stack.sh` najde i shell, jehož příkazový řádek ten text obsahuje. Proxy se pak po pádu znovu nespustí („proxy neodpovídá“), stalo se mi to v t7. Lepší je hledat přes `pgrep -x node` nebo vést PID soubor.

## Co funguje (OVĚŘENO)
- Přihlášení do Ředitelny pro ředitelku, zástupkyni a hospodářku v obou režimech; hlavička ukazuje skutečný název školky (t1).
- Přístupy (ostrý):
  - seznam jen vlastní školky;
  - pozvánka: v DB vznikne `pozvanky` (role hospodarka, skola B);
  - validace;
  - chybové hlášky při výpadku;
  - hospodářka stránku nevidí a v DB ji odmítnou RPC (t1, t3, t7, t10).
- Rodiče v LifeOS (ostrý): seznam dětí a zástupců z DB; „Nový kód“ vytvoří `parovaci_kody` (skola B, Adam) a ukáže kód (t10).
- RLS a oddělení školek v DB (t3).
- Rozvržení na 1194×834 bez přetečení (t9). Žádné JS chyby (`pageerror`) v žádném běhu.

## Úklid
Instance `skolka_b` (PostgREST 3021, proxy 3022, web 8821) je po auditu zastavená (podle PID s přesnými argumenty).
