# Audit F — nezávislé QA a bezpečnostní testy (Školka + LifeOS rodič)

Datum: 14. 10. 2026 · Tester: agent F · Repozitář: `/home/claude/skolka-audit` (jen čteno, nic neměněno)
Prostředí: vlastní lokální instance `skolka_f` (PostgREST 3061, proxy 3062, web 8861), Chromium přes Playwright.
Skutečný Supabase nebyl nikdy kontaktován (config.js přesměrován na proxy; pro test service workeru použita kopie webu ve scratchpadu s lokálním `config.js`).

Skripty a výstupy: `scratchpad/audit/F/` — `t1-rls.js` … `t12-prazdna.js`, výstupy `t*.out`, snímky `shots/*.png`.
Spuštění: `cd /home/claude/skolka-audit/testy && node <cesta>/tN-….js` (API testy `TEST_DB=skolka_f node tN.js` ze složky F).
Po `testy/reset.sh skolka_f` je nutné obnovit cache schématu PostgREST (`kill -USR1/-USR2 <pid postgrest>`), jinak RPC vrací 404 PGRST202 — sám jsem na to narazil (první běh t1 byl kvůli tomu neplatný a byl zopakován).

Pozn.: databáze `skolka_f` při startu obsahovala cizí data (zřejmě z dřívějšího běhu), proto jsem ji nejprve obnovil `reset.sh`.

---

## 1. Seznam provedených testů

### API / RLS (t1-rls.js, t2-kody.js, t2b.js, t10-presun.js, t11-anonym.js) — curl/fetch s JWT jednotlivých identit

| # | Test | Výsledek |
|---|------|----------|
| 1 | anon bez JWT nečte `deti`, nevolá `nahled_kodu` | PASS |
| 2 | učitelka nevidí rodné číslo v `deti` | **FAIL → F5** |
| 3 | hospodářka nevidí rodná čísla | **FAIL → F5** |
| 4 | kuchařka nečte tabulku `deti` | PASS |
| 5 | ředitelka/učitelka/rodič A nečte cizí školku v `deti`, `urazy`, `udalosti_ditete`, `zastupci`, `deti_jidelna` | PASS |
| 6 | kuchařka A nečte / nemění diety dětí školky B; ředitelka A je nesmaže | **FAIL → F1** |
| 7 | ředitelka B nečte / nemění náhrady a nesmaže alergeny (jidlo_suroviny) jídla školky A | **FAIL → F2** |
| 8 | rodič A dostane jídelníček s alergeny (nepoškozený cizí školkou) | **FAIL → F2** |
| 9 | ředitelka B nečte / nepíše třídní knihu školky A | **FAIL → F4** |
| 10 | učitelka si nezmění roli; ředitelka nepřesune účet do cizí školky; nemění sama sebe | PASS |
| 11 | rodič nemění `deti` přímo PATCHem | PASS |
| 12 | ředitelka nezmění stav/tarif/předplatné školky (trigger) | PASS |
| 13 | ředitelka se nezapíše do `superadmini`; nečte `pozvanky`, `skoly_admin` | PASS |
| 14 | učitelka A nezapíše úraz se `skola_id` školky B; učitelka B pak zapíše svůj úraz | **FAIL → F6** |
| 15 | učitelka A nepřesune svůj zápis (`udalosti_ditete`) k dítěti školky B | PASS |
| 16 | učitelka nepodvrhne autora zápisu (`zapsal` = ředitelka) | **FAIL → F12** |
| 17 | zablokovaná učitelka nečte děti, nemění ani nemaže své zápisy (API) | PASS |
| 18 | rodič Emy / kuchařka nečte adresnou zprávu pro rodiče Olivera | **FAIL → F8** |
| 19 | IDOR RPC: `omluv_dite`, `potvrd_omluvenku`, `vytvor_kod_rodice` (cizí dítě, cizí zástupce, hospodářka), `uprav_udaje_rodicem` (cizí rodič, ředitelka) | PASS (vše odmítnuto) |
| 20 | `admin_*` (skoly, uprav_skolu, nastav_ucet, pozvi_reditelku, zaloz_skolu) volané ředitelkou | PASS |
| 21 | superadmin nečte `deti`; `admin_skoly` vrací jen počty | PASS |
| 22 | zástupkyně nezablokuje ředitelku; ředitelka A nezablokuje učitelku B ani rodiče | PASS |
| 23 | ředitelka A nezruší pozvánku školky B; nepozve ředitelku; nepozve do třídy školky B | PASS |
| 24 | `zverejni_jidelnicek`: kuchařka ano, učitelka a účet bez školky ne | PASS |
| 25 | rodič A nepotvrdí přečtení zápisu dítěte B | PASS |
| 26 | hospodářka zaúčtuje předpis vlastnímu dítěti (`ucetni_pohyby` → trigger `konta`) | **FAIL → F10** |
| 27 | pozvánka: cizí e-mail / opakované použití / tentýž účet 2× / propadlá / zrušená / rodič | PASS |
| 28 | pozvánka: registrace e-mailem s velkými písmeny, kód malými písmeny s mezerami | PASS |
| 29 | anonymní účet (bez e-mailu) nepřijme pozvánku zaměstnance | **FAIL → F3** |
| 30 | `pozvi_zamestnance` s mezerou na konci e-mailu (přímé API) | FAIL (nízké, UI ořezává — viz F14) |
| 31 | kód rodiče: náhled, uplatnění, opakované použití, propadlý, zaměstnanec, nový kód ruší starý | PASS |
| 32 | rodič B s kódem dítěte A — konzistentní stav | FAIL (nízké → F14) |
| 33 | hádání kódů je omezeno | **FAIL → F11** |
| 34 | plná entropie kódu (všech 8 znaků 32 možností) | **FAIL → F11** |
| 35 | učitelka A nepřesune dítě „na dnes“ do třídy jiné školky (`trida_dnes`) a učitelka B pak nečte dítě, kontakty, nezapisuje mu | **FAIL → F1b (F7)** |
| 36 | čerstvý anonymní účet (kdokoli s anon. registrací) nečte žádná data | FAIL (nízké: čte všechny `nahrady` všech školek → F2) |

### Prohlížeč (t3-prihlaseni.js, t5-xss.js, t6-relace.js, t7-sw.js, t8-reditelna.js, t9-sdileny-pc.js, t12-prazdna.js)

| # | Test | Výsledek |
|---|------|----------|
| 37 | špatné heslo → „E-mail nebo heslo nesedí.“, zůstává #prihlaseni | PASS |
| 38 | prázdný e-mail / prázdné heslo → hlášky | PASS |
| 39 | e-mail `  KUCHARKA@Test.CZ  ` projde | PASS |
| 40 | kuchařka ručně `#reditel`, `#trida`, `#admin` → přihlašovací obrazovka s vysvětlením | PASS |
| 41 | kuchařka → přihlášení do Ředitelny odmítnuto | PASS |
| 42 | učitelka → `#admin` nedostane správu | PASS |
| 43 | obnova stránky zachová přihlášení | PASS |
| 44 | odhlášení + „zpět“ neukáže děti | PASS |
| 45 | po odhlášení nezůstane token relace (`skolka-sb-auth`, `skolka-server-ucet`) | PASS |
| 46 | po odhlášení nezůstanou v localStorage údaje dětí | **FAIL → F9** |
| 47 | smazaný token relace (profil v localStorage zůstal) → přihlašovací obrazovka | **FAIL → F13** |
| 48 | zablokovaná učitelka po obnově stránky → srozumitelná hláška | **FAIL → F13** |
| 49 | blokace během práce (bez obnovy): srozumitelná hláška; tablet dál neukazuje děti | **FAIL → F13** |
| 50 | zablokovaná školka → „má přístup pozastavený“ | PASS |
| 51 | dvě záložky, dva účty: zápis v záložce A neprojde pod identitou z B | **FAIL → F7** |
| 52 | odkaz „Zapomenuté heslo“ umožní nastavit nové heslo | **FAIL → F8b (F12b)** viz F15 |
| 53 | XSS: `<img onerror>` ve jménu dítěte, alergii, zápisu, vyzvedávání, omluvence, třídě (Tablet) | PASS (vykresleno jako text) |
| 54 | XSS: jméno zástupce, pozvánka (Ředitelna → Rodiče v LifeOS, Přístupy) | PASS |
| 55 | XSS: název školky, kontakt, jméno ředitelky (Správa LifeOS) | PASS |
| 56 | výpadek serveru: tablet ohlásí neuložení | PASS |
| 57 | výpadek serveru: příchod se po obnovení sítě dopíše (nebo UI nehlásí přítomnost) | **FAIL → F16** |
| 58 | pomalá síť (3 s) — příchod se uloží | PASS |
| 59 | service worker necachuje odpovědi API (17 položek, jen statické soubory) | PASS |
| 60 | offline obnova tabletu | **FAIL → F16** |
| 61 | sdílený tablet: další učitelka (bez zavření okna) nevidí děti předchozí třídy | PASS |
| 62 | Ředitelna (ostrý provoz) ukazuje děti ze serveru | FAIL — ukazuje ukázková data (štítek „Pilot · část ukázková“; záměr, ale viz F9) |
| 63 | po odhlášení ředitelky nezůstanou v prohlížeči rodná čísla / kartotéka | **FAIL → F9** |
| 64 | ředitelka B na stejném počítači nevidí záznamy ředitelky A | **FAIL → F9** |
| 65 | konzole bez osobních údajů | PASS |
| 66 | prázdná třída → srozumitelná hláška; účet bez školky → nabídka pozvánky | PASS |
| 67 | bez chyb JS (pageerror) ve všech bězích | PASS |

Souhrn: 67 testovaných oblastí, z toho 27 FAIL (některé sdílejí jednu příčinu) → 16 nálezů.

---

## 2. Nálezy

Závažnost: **Kritická** = únik/změna zdravotních či osobních údajů mezi školkami nebo ohrožení zdraví dítěte; **Vysoká**; **Střední**; **Nízká**.

### F1 — Kritická — Diety dětí (zdravotní údaje) čte, mění a maže kuchyně/ředitelka JAKÉKOLI školky
- Soubor: `supabase/setup.sql:450` — `create policy die on diety for all using (je_kuchyne());` (chybí `moje_dite(dite_id)` / škola).
- Popis: kuchařka nebo ředitelka libovolné školky čte všechny diety (doporučení lékaře, poznámka typu „anafylaxe“) všech dětí v systému a může je přepsat nebo smazat.
- Reprodukce (t1-rls.js, část 3):
  1. jako postgres `insert into diety (dite_id, doporuceni_lekare, poznamka) values ('…0201', true, 'anafylaxe arašídy (B) — EpiPen')` (Adam, školka B);
  2. `GET /rest/v1/diety?select=*` s JWT kuchařky A (`aaaaaaaa-…07`) → vrátí Adamův řádek;
  3. `PATCH /rest/v1/diety?dite_id=eq.…0201 {"poznamka":"bez omezení","doporuceni_lekare":false}` jako kuchařka A → **200, změněno**;
  4. `DELETE /rest/v1/diety?dite_id=eq.…0201` jako ředitelka A → **200, smazáno**.
- Ověřeno: reálně přes PostgREST (výstup `t1.out`).
- Oprava: `using (je_kuchyne() and exists (select 1 from deti d where d.id = dite_id and d.skola_id = moje_skola())) with check (totéž)`.

### F2 — Kritická — Alergeny a náhrady jídel školky A mění/maže kdokoli s rolí kuchyně v JINÉ školce; rodiče A pak vidí jídlo „bez alergenů“
- Soubor: `supabase/setup.sql:444` (`js on jidlo_suroviny for all using (je_kuchyne())`), `:445` (`nah_cist … using (true)`), `:446` (`nah_menit … using (je_kuchyne())`).
- Popis: ředitelka/kuchařka školky B smaže vazby surovin (= alergeny) u jídel školky A a přepíše texty náhrad. Funkce `jidelnicek_tyden` pak rodičům A (LifeOS) vrací jídlo s `alergeny: []` a podvrženou náhradou. Rodiče, kteří podle aplikace hlídají alergii dítěte, dostanou chybnou informaci. Navíc `nahrady` čte každý přihlášený — i čerstvý anonymní účet (t11).
- Reprodukce (t1-rls.js, část 4):
  1. `jidloA = select j.id from jidla j join nahrady n … where j.skola_id = A`;
  2. jako ředitelka B: `PATCH /nahrady?jidlo_id=eq.<jidloA> {"text":"normální jídlo s mlékem (podvrh B)"}` → 200;
  3. jako ředitelka B: `DELETE /jidlo_suroviny?jidlo_id=eq.<jidloA>` → 200;
  4. jako rodič Emy: `POST /rpc/jidelnicek_tyden {"p_od":"2000-01-01","p_do":"2100-01-01"}` → `{"nazev":"Chléb s tuňákovou pomazánkou","alergeny":[],"nahrady":{"7":"normální jídlo s mlékem (podvrh B)"}}`.
- Ověřeno: reálně (t1.out, t11 výstup).
- Oprava: politiky přes vlastníka jídla — `using/with check (je_kuchyne() and exists (select 1 from jidla j where j.id = jidlo_id and j.skola_id = moje_skola()))`; `nah_cist` totéž bez role (`… j.skola_id = moje_skola()`). Pro `jidlo_suroviny` hlídat i `surovina_id` ze stejné školky.

### F3 — Vysoká — Pozvánku zaměstnance přijme anonymní účet bez e-mailu (vazba „kód + e-mail“ neplatí)
- Soubor: `supabase/setup.sql:1141` a `:1150` — `if lower(p.email) <> mail then raise …` při `mail IS NULL` dá NULL → podmínka neplatí → výjimka se nevyhodí.
- Popis: kdo má kód pozvánky (např. přeposlaný e-mail, foto obrazovky), zaregistruje se anonymně (stejně jako rodič v LifeOS) a stane se učitelkou dané třídy — vidí jména, data narození, alergie, zápisy.
- Reprodukce (t2b.js): ředitelka `pozvi_zamestnance('Klára Nová','Klara.Nova@Test.cz','ucitelka',Sluníčka)` → kód; `POST /auth/v1/signup {}` (anonym); `POST /rpc/prijmi_pozvanku {"p_kod":kód}` s anonymním JWT → **200 `{"role":"ucitelka"}`**; `GET /deti` → Ema, Oliver vč. alergií.
- Ověřeno: reálně v lokální emulaci. Výhrada: lokální JWT anonymu nemá claim `email`; skutečný Supabase dává anonymu `"email": ""` (prázdný řetězec, ne NULL) — tam by `'' <> 'klara…'` výjimku vyhodilo. Ochrana tedy v produkci stojí na náhodném tvaru JWT; doporučuji ověřit na stagingu a opravit bez ohledu na to.
- Oprava: `if mail is null or mail = '' or lower(p.email) is distinct from mail then raise …`; navíc odmítnout `auth.jwt()->>'is_anonymous' = 'true'` a nepotvrzený e-mail.

### F4 — Vysoká — Třídní kniha: vedení JAKÉKOLI školky čte a zapisuje třídní knihy všech školek
- Soubor: `supabase/setup.sql:370-371` — `using (je_vedeni() or exists (…ucitel_trida…))`, `je_vedeni()` bez kontroly školy.
- Reprodukce (t1-rls.js, část 5): jako ředitelka B `GET /tridni_kniha` → řádek třídy Sluníčka (A); `POST /tridni_kniha {"trida_id":"…0011","den":"2026-10-01","tema":"podvrh B",…}` → **201**.
- Ověřeno: reálně.
- Oprava: `using ((je_vedeni() and exists (select 1 from tridy t where t.id = trida_id and t.skola_id = moje_skola())) or exists (…ucitel_trida…))` + `with check` totéž.

### F5 — Vysoká — Učitelka i hospodářka čtou rodná čísla (a celý řádek dítěte) přímo z tabulky `deti`
- Soubor: `supabase/setup.sql:345` (`deti_cist … using (moje_dite(id))`) proti záměru v komentáři `:12-14` a `:412` („Učitelky a hospodářka rodná čísla nevidí: čtou pohled bez nich“). Pohled `deti_trida` existuje, ale nic nebrání číst tabulku.
- Reprodukce: JWT učitelky Berušek `GET /rest/v1/deti?id=eq.…0103&select=jmeno,rodne_cislo` → `[{"jmeno":"Tobiáš","rodne_cislo":"220120/0000"}]`; hospodářka `GET /deti?select=jmeno,rodne_cislo` → RČ všech dětí.
- Ověřeno: reálně (t1.out).
- Oprava: sloupcová práva — `revoke select on deti from authenticated; grant select (id, skola_id, trida_id, jmeno, prijmeni, datum_narozeni, alergie, ukonceno, znacka, …) on deti to authenticated;` a citlivé sloupce (rodne_cislo, kod_cizince, adresa, pojistovna, …) jen přes `security definer` funkci pro vedení; nebo `deti_cist` jen pro vedení/rodiče a učitelka/hospodářka přes pohledy.

### F6 — Vysoká — Učitelka zapíše úraz se `skola_id` cizí školky → zablokuje číslování knihy úrazů školky B
- Soubor: `supabase/setup.sql:366` — `uraz_zapsat … with check (moje_role() in (…) and moje_dite(dite_id))`, chybí `skola_id = moje_skola()`; čísla jsou `unique (skola_id, rok, cislo)` (`:129`) a `server.js` počítá další číslo z řádků viditelných pod RLS.
- Reprodukce (t1-rls.js, část 7): jako učitelka A `POST /urazy {"skola_id":B,"cislo":2,"rok":2026,"dite_id":Ema,…}` → **201**; jako učitelka B stejný postup jako `server.js uraz()` (max viditelné číslo + 1 = 2) → **409 duplicate key urazy_skola_id_rok_cislo_key**. Škola B nemůže zapsat úraz (zákonná evidence), dokud cizí řádek někdo neodstraní — a ona ho nevidí.
- Ověřeno: reálně.
- Oprava: `with check (… and skola_id = moje_skola() and exists (select 1 from deti d where d.id = dite_id and d.skola_id = skola_id))`; číslo úrazu přidělovat v `security definer` funkci/sekvenci (ne `max+1` na klientu).

### F7 — Vysoká — Přesun „na dnes“ (`dochazka.trida_dnes`) do třídy JINÉ školky otevře dítě cizí škole
- Soubor: `supabase/setup.sql:499` (`doch_menit` bez kontroly `trida_dnes`) + `moje_dite()` `:978-983` (učitelka vidí dítě, jehož dnešní `trida_dnes` je její třída).
- Reprodukce (t10-presun.js): učitelka A `POST /dochazka {"dite_id":Ema,"den":dnes,"stav":"pritomen","trida_dnes":"…0021" (Žabky, školka B)}` → 201; učitelka B pak `GET /deti?id=eq.Ema` → jméno, alergie, datum narození; `GET /zastupci?dite_id=eq.Ema` → telefon a e-mail matky; `POST /udalosti_ditete {skola_id:B, dite_id:Ema, druh:"uraz", titulek:"Úraz (zapsala škola B)"}` → 201 a rodič Emy ho v LifeOS vidí.
- Ověřeno: reálně.
- Oprava: `with check (… and (trida_dnes is null or exists (select 1 from tridy t join deti d on d.id = dite_id where t.id = trida_dnes and t.skola_id = d.skola_id)))`; v `moje_dite()` pro učitelku navíc `x.skola_id = moje_skola()`.

### F8 — Střední — Zprávy: každý ve školce (rodič, kuchařka) čte všechny zprávy včetně adresných
- Soubor: `supabase/setup.sql:406` — `zpravy_cist … using (skola_id = moje_skola())`, sloupec `komu` se nehodnotí.
- Reprodukce: `insert into zpravy (skola_id, komu, predmet, text) values (A, 'rodiče Olivera Zkušebního', 'Dluh za školkovné', 'Dlužíte 2 700 Kč…')`; rodič Emy `GET /zpravy` → vidí i dluh rodiny Olivera; kuchařka totéž.
- Ověřeno: reálně. (Webová Ředitelna dnes zprávy na server neposílá — riziko nastane s napojením zpráv; tabulka je ale v publikaci realtime a LifeOS ji čte.)
- Oprava: modelovat adresáty (`komu_trida`, `komu_dite`, `komu_role`) a politiku podle nich; adresné zprávy jen pro zástupce daného dítěte a vedení.

### F9 — Vysoká — Sdílený počítač: data ředitelny (kartotéka s RČ, archiv s jmény ze serveru) zůstávají po odhlášení a vidí je další přihlášený — i z jiné školky
- Soubor: `Reditel.dc.html:1847-1875` (`persistKe