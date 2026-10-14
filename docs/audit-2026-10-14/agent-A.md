# Audit A — LifeOS, rodičovská mobilní aplikace (větev faze-1-mobil, commit ad20071)

Datum: 14. 10. 2026 · Kopie: `/home/claude/lifeos-a/mobile` (v repozitáři se nic neměnilo) · Lokální server: DB `skolka_a`, PostgREST :3011, proxy :3012, web :8811
Vlastní testy: `scratchpad/audit/A/tests/*.audit.ts` (31 testů), spouštění:
`cd mobile && SKOLKA_TEST_URL=http://localhost:3012 npx jest -c <scratchpad>/audit/A/jest.config.js --runInBand`

Legenda: **OVĚŘENO** = spuštěno (unit/integrační test, Node) a sedí · **SELHÁVÁ** = spuštěno a chová se špatně · **CHYBÍ** = funkce není · **NEOVĚŘENO** = jen čteno nebo potřebuje zařízení (Expo, iOS/Android build tu spustit nejde).

---

## 1. Typecheck, lint, testy

| Krok | Výsledek |
|---|---|
| `npm ci` | OK (npm hlásí jen `npm audit` upozornění) |
| `npm run typecheck` (`tsc --noEmit`) | **OK, 0 chyb** |
| `npm run lint` (`expo lint`) | **OK, 0 chyb, 0 varování** |
| `npm test` (Jest) | **22 sad, 114 testů: 113 prošlo, 1 přeskočen, 0 selhalo** (13,4 s) |
| Přeskočený test | `skolkaserver.test.ts` „rodič: propojení kódem, stažení, omluvenka…“, běží jen s `SKOLKA_TEST_URL`. V `npm test`/CI se proti serveru tedy netestuje nic. |
| Integrační test proti lokálnímu serveru | `SKOLKA_TEST_URL=http://localhost:3012 SKOLKA_TEST_KOD=<kód od ředitelky> SKOLKA_TEST_PSQL="psql … -d skolka_a" npx jest skolkaserver` → **5/5 prošlo** (včetně potvrzení omluvenky učitelkou přes psql). |
| Audit testy (moje) | **31/31 prošlo**. Testy jsou psané jako reprodukce: projdou, když se chyba projeví. |

Poznámka k prostředí: DB `skolka_a` na začátku obsahovala cizí stará data (ID `eeeeeeee-…`, 22 zástupců). `stack.sh` databázi neobnoví, když už existuje. Proto jsem spustil `reset.sh skolka_a`. Moje testy si DB samy obnoví v `beforeAll`.

---

## 2. Inventář obrazovek (`src/app`, 62 souborů)

Ukládání: všechno jde do šifrovaného SQLite (SQLCipher, `platform/sqlite.ts`) přes `HcData` (`persons`, `records`, `attachments`, `person_data`). Datová vrstva je **OVĚŘENO** testy `data.test.ts` (12) a `driver.test.ts` (2) přes better-sqlite3, ale bez SQLCipheru. Šifrování samo je **NEOVĚŘENO**, potřebuje zařízení. Vykreslení, navigace a gesta všech obrazovek jsou **NEOVĚŘENO** (žádné testy UI, `jest.config.js` to přiznává). Obrazovky se podle projektu testují ručně podle `docs/QA.md`.

| Obrazovka | Funkce | Uložení / načtení | Validace, chyby, prázdná data | Stav |
|---|---|---|---|---|
| `_layout.tsx`, `login.tsx` | kořen, zámek, odemknutí heslem/biometrií | Keychain (`services/auth`) | chyby přihlášení + throttling | logika OVĚŘENO (`auth.test` 8), UI NEOVĚŘENO |
| `(onboarding)/vitejte, register, obnovit` | úvod, registrace (4 pole), obnova ze zálohy | auth + `backup` | register: `errors`/`valid` (jméno, e-mail, heslo, shoda); obnova: chyba hesla/souboru | logika OVĚŘENO (`auth.test`, `backup.test` 3), UI NEOVĚŘENO |
| `nouzova.tsx` | nouzová karta bez odemknutí | Keychain `lifeos.publicEmergency` (záměrná výjimka) | prázdná karta | NEOVĚŘENO (čteno) |
| `+native-intent.tsx` | filtr deep linků | – | whitelist cest | OVĚŘENO (`deeplink.test` 3) |
| `(app)/index.tsx` Přehled | rozcestník, dlaždice | čtení | prázdné stavy (3) | NEOVĚŘENO |
| `osa.tsx`, `kalendar.tsx`, `k-reseni.tsx` | časová osa, kalendář, úkoly | čtení `records` | prázdné dny | dotazy OVĚŘENO (`data.test`), `timeline`/`useTodo` NEOVĚŘENO |
| `zaznam/upravit.tsx`, `zaznam/[id].tsx` | nový/úprava/smazání záznamu, přílohy | `records.create/update/softDelete`, `files.add` | povinný název (`titleError`), počítá nepovedené přílohy, potvrzení smazání | repozitář OVĚŘENO, formulář NEOVĚŘENO |
| `zapis.tsx` | nálada/příznaky | `records.create` | `canSave` (nálada nebo příznak) | NEOVĚŘENO |
| `cyklus/index, nastaveni, zapis` | cyklus | `person_data.cycle`, records | zapis: prázdný zápis odmítne; index/nastaveni: zápis bez try/catch | doména OVĚŘENO (`cycle.test` 6), UI NEOVĚŘENO |
| `leky/index, upravit` | léky, dávky, připomínky | `person_data.meds/medlog`, records | povinný název; zápis bez try/catch | registr/připomínky OVĚŘENO (`drugs`, `reminders`), UI NEOVĚŘENO |
| `ockovani/index, upravit, sken` | očkování, OCR průkazu | records, přílohy | povinný název; sken: chyby OCR (try/catch) | OVĚŘENO (`vaccines`, `vaxcatalog`, `scan`, `scanquality`), OCR (ML Kit) NEOVĚŘENO |
| `prevence.tsx` | preventivní prohlídky | čtení | – | OVĚŘENO (`prevention.test` 2) |
| `lekari.tsx`, `nastaveni/lekari.tsx` | moji lékaři + registr | `person_data.doctors` | zápis bez try/catch | registr OVĚŘENO (`doctors.test`) |
| `dokumenty.tsx`, `priloha/[id].tsx`, `skener.tsx` | přílohy, skener | files, records | try/catch + toast; potvrzení smazání | AttachmentService OVĚŘENO (`data.test`), kamera/soubory NEOVĚŘENO |
| `nouze.tsx`, `tapeta.tsx` | nouzová karta, tapeta zámku | čtení / view-shot | try/catch | NEOVĚŘENO |
| `nastaveni/index` | účet, export JSON, zámek | export do cache, pak `removeCacheFile` ve `finally` | potvrzení „soubor NENÍ šifrovaný“ | NEOVĚŘENO (čteno, export uklízí) |
| `nastaveni/karta, osobni, nouzove, doplnujici, doklady, vzhled, upozorneni, zabezpeceni, zaloha, fhir, qr-sdilet, qr-nacist` | karty, osobní/nouzové údaje, doklady, nastavení, záloha, FHIR, QR profil | `persons`, `person_data`, settings | karta: povinné jméno, potvrzení odebrání; zabezpeceni: potvrzení „smazat vše“ | OVĚŘENO doména (`fhir` 12, `profileshare` 6, `backup` 3, `summary` 2, `avatar` 2, `domain` 6), UI NEOVĚŘENO |
| **Školka** `skolka/index` | Dnes, dlaždice, sync každých 30 s, chyba syncu dole | `person_data.skolka/skolkafeed`, records | `syncErr` se ukáže | sync OVĚŘENO (vlastní `sync.audit`), UI NEOVĚŘENO |
| `skolka/propojit` | kód → náhled → propojit | `skolka.server`, feed se vynuluje | kód 8 znaků bez 0/O/1/I, varování „jiné dítě“, chyby ze serveru | služby OVĚŘENO (neplatný/propadlý/zrušený/použitý kód), UI NEOVĚŘENO |
| `skolka/dochazka` | kalendář docházky, omluvenka 1 den až měsíc | lokální poznámky + `omluv_dite` | dny ≥ dnes, všední, ≤ +60, rozsah ≤ 31 dní, povinný důvod | server OVĚŘENO; **SELHÁVÁ offline (A5)** |
| `skolka/vyzvedne` | ohlásit vyzvednutí | lokální poznámka + `vyzvednuti` | jen pověřené osoby (z LifeOS) | server OVĚŘENO; **SELHÁVÁ offline (A5)** |
| `skolka/zprava`, `skolka/zpravy` | zápis učitelky, potvrzení přečtení, akce, nástěnka | records + `potvrd_udalosti` | toast „zkusí se znovu“ | potvrzení OVĚŘENO; **offline SELHÁVÁ (A10)**; nástěnka **A9, A14** |
| `skolka/udaje` | porovnání údajů LifeOS × školka, odeslat/převzít | `uprav_udaje_rodicem`, persons, person_data | – | server OVĚŘENO; **A16, A17** |
| `skolka/nastaveni` | propojení, odpojit, „Školka ví“, účet | person_data | – | **odpojení jen lokální (A8)** |
| `skolka/nastavit` | název, telefon, značka, pověřené, účet, VS | person_data | povinný název, `czIban`, VS jen číslice | **sync ruční účet přepíše (A7)** |
| `skolka/jidelnicek, platby, fotky, dotazniky, sdileni` | jídelníček s alergeny, QR platba, alba, dotazníky, co školka uvidí | feed / person_data | QR jen s platným účtem | `skolkafeed.test` 7 OVĚŘENO; **dvě školky (A3/A4)**; fotky ze serveru se nezobrazují (jen barevné náhledy), NEOVĚŘENO |

---

## 3. Karta Školka proti lokálnímu serveru: matice scénářů

Všechno je spuštěno přes `services/skolkaServer.ts` (skutečný `fetch` na :3012) a ověřeno v DB přes psql. Soubory testů: `skolka.audit.ts`, `sync.audit.ts`, `ucet.audit.ts`, `ack.audit.ts`.

| Scénář | Výsledek | Stav |
|---|---|---|
| Náhled kódu nespotřebuje kód; malá písmena a mezera se normalizují | ano | OVĚŘENO |
| Neplatný / propadlý (`plati_do` v minulosti) / zrušený (vydán nový) / použitý kód, i z jiného telefonu | vždy „Kód neplatí — …“ | OVĚŘENO |
| Uplatnění kódu → `zastupci.uzivatel_id`, `uzivatele.role='rodic'` | ano. Přibude ale **druhý zástupce** „Jana Audit“ vedle původní „Jana Testová“ (A20) | OVĚŘENO |
| Stažení: docházka, události, akce, zprávy, jídelníček, předpisy, účet, údaje dítěte; `feedZeServeru` | ano | OVĚŘENO |
| Cizí dítě (jiná školka) | prázdná pole, ne chyba | OVĚŘENO |
| Omluvenka po–út přes víkend (9 kalendářních dní) | 7 všedních dní, `stav='omluven'`, oběd odhlášen | OVĚŘENO |
| Omluvenka > 31 dní / cizí dítě / dnes po 8:00 | chyba / chyba / `obed_odhlasen=false` | OVĚŘENO |
| Omluvenka na den s `pritomen` | server vrátí den jako omluvený, v DB zůstane `pritomen` (A11) | SELHÁVÁ |
| Ohlášení vyzvednutí | řádek ve `vyzvednuti`; server přijme i jméno mimo pověřené osoby | OVĚŘENO (A16) |
| Potvrzení přečtení událostí | `precteno` nastaveno | OVĚŘENO |
| Potvrzení omluvenky učitelkou → rodič vidí `potvrzeno` | ano (oficiální test s psql) | OVĚŘENO |
| Úprava údajů (alergie, telefon/e-mail, pověřené) + audit_log | ano. Prázdné alergie smažou alergie ve školce (A17) | OVĚŘENO |
| Obnova relace po restartu (stejný Keychain) | stejné `uid`. Při jednom stažení ale **12 souběžných refreshů** (A2) | OVĚŘENO |
| Refresh odmítnut (400) / server 503 při refreshi | **tichý nový anonymní účet, prázdná data, žádná chyba; 12 nových účtů** (A1) | SELHÁVÁ |
| Odpověď, která není JSON (502 HTML) | `SyntaxError: Unexpected token '<'…` místo hlášky (A12) | SELHÁVÁ |
| Offline: `stahni`, `omluv`, `vyzvedne` | `ServerError` „Server školky není dostupný…“ | OVĚŘENO |
| Offline sync (`useSkolkaServer().sync`) | vyhodí chybu, uložený feed zůstane beze změny | OVĚŘENO |
| Fronta zápisů offline | **není**: omluvenka/vyzvednutí se zapíše jen lokálně (A5), přečtení se nezopakuje (A10) | CHYBÍ |
| Zablokovaná školka | `stahni` vrátí prázdná data bez chyby; **sync tiše vyprázdní feed**; omluvenka „Toto dítě omluvit nemůžete“ (A6) | SELHÁVÁ |
| Dva rodiče jednoho dítěte | oba vidí; pověřené osoby přepisuje poslední zápis (A16) | OVĚŘENO / chování k diskusi |
| Rodič dvou dětí ze dvou školek | **na kartě dítěte ze školky B akce, zprávy, jídelníček a ÚČET školky A**; blokace A odřízne i dítě z B (A3) | SELHÁVÁ |
| Dvě děti, jedna školka, různé třídy | akce třídy sourozence na cizí kartě (A4) | SELHÁVÁ |
| Odpojit v telefonu / Smazat vše | server propojení drží; token v Keychainu zůstane a dál čte data (A8) | SELHÁVÁ |
| Zpráva jen pro rodiče jednoho dítěte (`komu='kid:…'`) | vidí ji všichni rodiče školky (A9) | SELHÁVÁ |
| Push oznámení (expo-notifications), kamera, SecureStore na zařízení, iOS Keychain po odinstalaci | – | NEOVĚŘENO (potřebuje zařízení) |

---

## 4. Nálezy

### A1 — Vysoká: při každé chybě refreshe aplikace tiše založí nový účet a odpojí všechny děti
- **Soubor:** `src/services/skolkaServer.ts:62-77` (`token()`, catch na ř. 70-73 a `signup` na ř. 75)
- **Popis:** Když obnova tokenu skončí `ServerError` a nejde o výpadek sítě, kód pokračuje anonymním `signup` a nový účet uloží do Keychainu přes starý. Týká se to 400/401 (propadlý nebo rotovaný token), ale i 429 a 5xx. Nový účet nemá žádné děti, RLS vrátí prázdná pole a `sync` je zapíše do feedu. Rodič nedostane žádnou chybu, karta se jen vyprázdní. Starý token je nenávratně pryč a propojení obnoví jen nový kód od ředitelky. `stahni` posílá 12 dotazů najednou, proto vznikne až 12 anonymních účtů naráz.
- **Reprodukce:** `skolka.audit.ts` › „4 relace a token“: refresh vrátí 400 `Invalid Refresh Token` nebo 503 → `uid` v Keychainu se změní, `dochazka=[]`, `dite=null`, naměřeno **12** volání `/auth/v1/signup`.
- **Jak ověřeno:** Jest proti :3012 s injektovanou odpovědí na refresh, kontrola Keychainu (mock) a výsledku.
- **Oprava:** Pokud existuje uložený refresh token, nikdy nezakládat nový účet. Při 5xx/429 hodit dočasnou chybu. Při `invalid_grant` označit propojení jako propadlé („Propojení vypršelo — požádejte o nový kód“) a starý token nemazat. Účet zakládat jen ve `propojKodem`/`nahledKodu`, ne v obecném `token()`.

### A2 — Střední: souběžné obnovy tokenu (12 refreshů na jedno stažení)
- **Soubor:** `src/services/skolkaServer.ts:62-69`, `117-130` (`Promise.all`)
- **Popis:** `token()` nemá „single-flight“. Po restartu nebo vypršení access tokenu pošle každý z 12 paralelních dotazů vlastní refresh se stejným refresh tokenem. Supabase GoTrue rotuje tokeny a má detekci opakovaného použití. Jakmile některý refresh selže, nastoupí A1. Chování proti skutečnému GoTrue je NEOVĚŘENO, lokální proxy rotaci neemuluje.
- **Reprodukce:** „restart aplikace…“: naměřeno 12× `grant_type=refresh_token`.
- **Oprava:** Sdílet jednu rozběhnutou obnovu (`let obnova: Promise<string> | null`), ostatní dotazy na ni počkají.

### A3 — Vysoká: dítě z druhé školky ukazuje data a bankovní účet první školky
- **Soubory:** `src/services/skolkaServer.ts:120-129` (dotazy `akce`, `zpravy`, `alba`, `financni_nastaveni?limit=1`, `skoly?limit=1`, RPC `jidelnicek_tyden` bez dítěte či školky). Server: `uplatni_kod` (`on conflict (id) do nothing` → `uzivatele.skola_id` zůstane první školka) a `moje_skola()`.
- **Popis:** Telefon má jeden anonymní účet. Druhý kód z jiné školky propojí dítě (`moje_dite` funguje), ale vše „podle školy“ jde z `moje_skola()` = první školka. Na kartě Adama (MŠ Dejvice) jsou proto akce, nástěnka a jídelník MŠ Sluníčko a hlavně účet `19-2000145399/0800` (`useSkolka.ts:134` ho zapíše do `sk.ucet` → QR platba odejde **na účet cizí školky**). Zablokování první školky odřízne i dítě z druhé. Ředitelka B rodiče nevidí jako uživatele své školy.
- **Reprodukce:** „8 rodič dvou dětí z různých školek“ (2 testy).
- **Jak ověřeno:** Jest proti :3012 + DB `uzivatele.skola_id`.
- **Oprava:** V aplikaci filtrovat podle `skola_id`/`trida_id` dítěte (`deti?select=skola_id,trida_id` a pak `akce?skola_id=eq…`, `financni_nastaveni?skola_id=eq…`, `jidelnicek_tyden(p_dite)`). Na serveru odvodit školu z dítěte (RLS přes `zastupci`), ne z `uzivatele.skola_id`. Do té doby aspoň odmítnout kód z jiné školky srozumitelnou hláškou.

### A4 — Střední: akce a alba třídy sourozence na cizí kartě
- **Soubor:** `src/services/skolkaServer.ts:120,122`; RLS `akce_cist`/`alba_cist` (`rodic_tridy`)
- **Popis:** Ema (Sluníčka) a Tobiáš (Berušky) na jednom účtu: akce „Výlet do ZOO“ pro Sluníčka se ukáže i na kartě Tobiáše. Ve `skolka/zpravy` jde přidat do jeho kalendáře a dotazník přidá platbu.
- **Reprodukce:** „dvě děti v jedné školce, různé třídy“.
- **Oprava:** Filtrovat `trida_id=is.null` nebo `trida_id=eq.<třída dítěte>`.

### A5 — Vysoká: omluvenka a vyzvednutí offline se tváří jako odeslané
- **Soubory:** `src/app/(app)/skolka/dochazka.tsx:87-92`, `src/app/(app)/skolka/vyzvedne.tsx:208-211`
- **Popis:** I v režimu serveru se nejdřív vytvoří lokální poznámky („Omluven ze školky“ pro každý den, „Ze školky vyzvedne …“), teprve potom se volá server. Když server selže (offline, blokace), zobrazí se jen toast s chybou. Poznámky zůstanou: kalendář docházky je obarví jako „omluveno“ (`omluveno` = poznámky ∪ feed), Dnes ukazuje „Dnes omluveno“ a skryje příchod. Školka nic neví a oběd se neodhlásí. Fronta k opakování neexistuje. Každý další pokus přidá duplicitní poznámky.
- **Reprodukce:** Zapnout režim letadlo → Docházka → Omluvit → Odeslat. Služby offline vyhodí chybu (test „5 offline“, OVĚŘENO). Že poznámky vzniknou před voláním a kalendář je započítá, je jen **čteno** (UI nejde spustit).
- **Oprava:** V režimu serveru zapsat lokální záznam až po úspěchu, nebo se stavem „čeká na odeslání“, s odchozí frontou (`person_data.outbox`) a opakováním v `sync`. V kalendáři ukazovat jen potvrzené ze serveru.

### A6 — Střední: zablokovaná školka nebo neplatné propojení tiše smažou data karty
- **Soubory:** `src/state/useSkolka.ts:127-132`, `src/services/skolkaServer.ts:114-135`
- **Popis:** Při `skoly.stav='blokovana'` vrací RLS prázdná pole a `stahni` neselže. `sync` uloží prázdný feed (jídelníček, akce, docházka, údaje zmizí) a vrátí `true`. Rodič nevidí žádné vysvětlení, pod kartou svítí „Propojeno se školkou · aktualizováno …“. Stejně se projeví A1. Omluvenka pak skončí hláškou „Toto dítě omluvit nemůžete.“, která rodiče mate.
- **Reprodukce:** „6 zablokovaná školka“ + `sync.audit.ts` (feed `jidelnicek=[]`, `skolaVi` zmizí).
- **Oprava:** Když `deti?id=eq.X` vrátí 0 řádků, nepřepisovat feed a ukázat stav (server: `muj_stav()` → „Školka má přístup pozastavený“ / „Propojení už neplatí“).

### A7 — Střední: sync přepíše (i smaže) ručně zadaný účet a VS
- **Soubor:** `src/state/useSkolka.ts:133-136`
- **Popis:** Pokud školka nemá účet vyplněný (`financni_nastaveni.ucet=''`), `d.ucet` = `{ucet:''}` a `'' ?? sk.ucet` dá `''`. Ručně zadaný účet z `skolka/nastavit` zmizí a QR platba přestane fungovat. Ruční úpravu přepíše i neprázdný účet ze serveru, bez upozornění.
- **Reprodukce:** `ucet.audit.ts`: Adam (školka B s prázdným účtem), ručně `2000145399/0800` → po syncu `ucet` prázdný.
- **Oprava:** Prázdný řetězec brát jako `null`. Když je karta propojená, v `nastavit` účet zamknout nebo ukázat „účet posílá školka“.

### A8 — Střední: odpojení a „Smazat vše“ neodpojí účet na serveru a nesmažou token
- **Soubory:** `src/app/(app)/skolka/nastaveni.tsx:57`, `src/state/session.tsx:349-363`, `src/services/auth.ts:226-235`, `src/services/skolkaServer.ts:20,56-59`
- **Popis:** „Odpojit v tomto telefonu“ smaže jen `sk.server` a feed. `zastupci.uzivatel_id` na serveru zůstane, ředitelka dál vidí rodiče jako propojeného a token v Keychainu dál čte data dítěte. `wipeEverything()` maže jen klíče `AuthService` a `lifeos.skolka.auth.v1` zůstane. Nový uživatel na stejném telefonu po „Smazat vše“ zdědí anonymní účet předchozího rodiče (`mojeId`, uložená propojení). Mazání karty (`persons.softDelete`) nechá v DB `person_data.skolka` včetně `diteId` (čteno). Na iOS přežívá Keychain i odinstalaci (NEOVĚŘENO).
- **Reprodukce:** „9 odpojení / smazání“ (token dál stáhne data Emy; `AuthService.wipe()` klíč školky nechá).
- **Oprava:** Při „Smazat vše“ smazat `lifeos.skolka.auth.v1` a zavolat `/auth/v1/logout`. Přidat RPC `odpoj_rodice(p_dite)` a volat ho při odpojení i při odebrání karty.

### A9 — Střední (server + aplikace): zprávu „jen pro rodiče jednoho dítěte“ vidí celá školka
- **Soubory:** `src/services/skolkaServer.ts:121` (bez filtru `komu`); `setup.sql` policy `zpravy_cist` (`skola_id = moje_skola()`)
- **Popis:** Ředitelna umí adresovat zprávu `kid:<id>` (např. „Neomluvená absence — Oliver Zkušební“). Rodič Emy ji stáhne a zobrazí na nástěnce.
- **Reprodukce:** „9b zpráva jen pro rodiče jiného dítěte“.
- **Oprava:** RLS podle `komu` (vse / třída / dítě) a v aplikaci posílat `komu` dál.

### A10 — Nízká: potvrzení přečtení offline se neodešle a zpráva se vrátí jako „Nová“
- **Soubor:** `src/app/(app)/skolka/zprava.tsx:73-76`, `src/state/useSkolka.ts:154-158`
- **Popis:** Toast slibuje „zkusí se znovu“, ale nic se neopakuje. Další sync najde rozdíl v `ackAt` a lokální potvrzení zruší. Učitelka nevidí „rodiče viděli“, dokud rodič nepotvrdí znovu.
- **Reprodukce:** `ack.audit.ts` (logika `ack()` zkopírovaná, síť vypnutá, pak skutečný `sync`).
- **Oprava:** V `sync` znovu odeslat `potvrd_udalosti` pro zprávy s lokálním `ackAt` a serverovým `precteno=null`.

### A11 — Nízká: omluvenka na den, kdy už je dítě ve školce
- **Soubor:** server `omluv_dite` (`where dochazka.stav <> 'pritomen'`, ale `return next` vždy); aplikace `dochazka.tsx:87-94`
- **Popis:** Server den vrátí jako omluvený, přitom ho nezmění. Aplikace napíše „Omluveno“, lokální poznámka obarví den a skryje příchod.
- **Reprodukce:** test „omluvenka na den, kdy už je dítě přítomno“.
- **Oprava:** Vracet `zmeneno boolean` a aplikace ukáže „Dítě už je ve školce — zavolejte“.

### A12 — Nízká: odpověď, která není JSON, skončí `SyntaxError`
- **Soubor:** `src/services/skolkaServer.ts:46-47`
- **Popis:** Při 502/HTML z proxy nebo CDN uvidí uživatel `Unexpected token '<', "<html>502 "... is not valid JSON`.
- **Reprodukce:** „odpověď, která není JSON…“.
- **Oprava:** `try { JSON.parse } catch { body = null }` a hláška podle statusu.

### A13 — Nízká: uživatel vidí surové technické hlášky
- **Soubor:** `src/services/skolkaServer.ts:28-35`
- **Popis:** Neznámé zprávy jdou rodiči beze změny. Během testu se tak zobrazilo „terminating connection due to administrator command“ (restart DB), dále se propouští např. anglické „Invalid Refresh Token“.
- **Oprava:** Neznámé chyby mapovat na obecnou českou hlášku a detail jen logovat.

### A14 — Nízká: datum zprávy na nástěnce se počítá v UTC
- **Soubor:** `src/domain/skolkaServer.ts:67` (`z.odeslano.slice(0, 10)`)
- **Popis:** Supabase vrací `timestamptz` v UTC (`…+00:00`, stejný tvar má fixture v `skolkaserver.test.ts`). Zpráva odeslaná 0:00–2:00 pražského času má datum o den dřív. Lokální DB má timezone Europe/Prague a vrací `+02:00`, takže se tam chyba neprojeví.
- **Reprodukce:** `feedZeServeru` s `odeslano='2026-10-13T22:30:00+00:00'` → `date='2026-10-13'` (OVĚŘENO unit voláním). Proti skutečnému Supabase NEOVĚŘENO.
- **Oprava:** `toLocalDate(new Date(z.odeslano))`, nebo explicitně `Europe/Prague` přes `Intl`.

### A15 — Nízká: integrační test je přeskočený a počítá den v UTC
- **Soubor:** `src/__tests__/skolkaserver.test.ts:78-92`
- **Popis:** Bez `SKOLKA_TEST_URL` test v CI neběží. `today = new Date().toISOString().slice(0,10)` je mezi 0:00 a 2:00 pražského času včerejšek.
- **Oprava:** Použít `toLocalDate(new Date())` a do CI přidat job s lokálním stackem.

### A16 — Nízká: pověřené osoby a vyzvednutí
- **Soubory:** `src/app/(app)/skolka/udaje.tsx:96`; server `uprav_udaje_rodicem`, `vyz_psat`
- **Popis:** (a) Dva rodiče: „Poslat školce verzi z LifeOS“ nahradí celý seznam a pověřené osoby druhého rodiče zruší (test 7: zůstane jen „teta Lída“). (b) Server přijme vyzvednutí libovolným jménem, které není v `poverene_osoby`. Aplikace nabízí seznam z LifeOS, a ten se může lišit od seznamu školky.
- **Oprava:** Posílat přidané a odebrané rozdílově. Na tabletu upozornit, když jméno není mezi pověřenými.

### A17 — Střední (bezpečnost dítěte): prázdné alergie v LifeOS smažou alergie ve školce
- **Soubor:** `src/app/(app)/skolka/udaje.tsx:85` (`em.allergies ?? ''`)
- **Popis:** Rodič nemá alergie v Nouzové kartě, školka eviduje „mléko“. U rozdílu je hlavní tlačítko „Poslat školce verzi z LifeOS“. Klepnutí nastaví `deti.alergie = NULL` a jídelna přestane chystat náhrady.
- **Reprodukce:** test „úprava údajů“ (poslání `''` → `alergie` NULL).
- **Oprava:** Když je LifeOS prázdný, nabídnout jen „Převzít do LifeOS“, případně potvrzovací dialog „Opravdu školce sdělit, že dítě nemá žádné alergie?“.

### A18 — Nízká: text o soukromí neodpovídá skutečnosti
- **Soubory:** `src/app/(app)/skolka/propojit.tsx:141-143`, hlavička `src/services/skolkaServer.ts:5-11`
- **Popis:** Text tvrdí, že „Do školky jde jen omluvenka a kdo dnes vyzvedne — alergie… zůstávají v telefonu“. Ve skutečnosti odchází i jméno účtu rodiče (`p_jmeno`), alergie, telefon/e-mail a pověřené osoby (z „Údaje ve školce“) a potvrzení přečtení. Ověřeno testy, které tato data najdou v DB.
- **Oprava:** Text upřesnit.

### A19 — Nízká: oznámení ze školky ignorují volbu soukromí na zamčené obrazovce
- **Soubory:** `src/state/useSkolka.ts:141,169-172`, `src/platform/notifications.ts:62-68`
- **Popis:** Volba `remindShowTitle` („Ukázat název…“) platí jen pro připomínky. Oznámení školky ukazují jméno dítěte, teplotu nebo úraz. Že `sync` volá `notifySchool` s textem zápisu, je OVĚŘENO (`sync.audit.ts`). Ignorování volby je jen čteno.
- **Oprava:** Respektovat stejnou volbu („Zpráva ze školky“ bez detailu).

### A20 — Nízká: náhled kódu zakládá účty a uplatnění zakládá duplicitní zástupce
- **Soubory:** `src/services/skolkaServer.ts:99-103` (auth → `signup`); server `uplatni_kod`
- **Popis:** Už samotný náhled (i neplatného kódu) z čistého telefonu založí anonymní `auth.users` (OVĚŘENO, +1). Kód bez `zastupce_id` přidá nového zástupce „Rodič (LifeOS)“/jméno účtu vedle existujícího zákonného zástupce (OVĚŘENO, 2 řádky pro Emu). Ředitelka pak vidí duplicitu.
- **Oprava:** Vydávat kód ke konkrétnímu zástupci, případně v `uplatni_kod` spárovat podle jména nebo nabídnout výběr.

### A21 — Nízká, CHYBÍ: omluvenku nejde zrušit
- **Popis:** Aplikace ani server (žádné RPC) neumí odeslanou omluvenku vzít zpět, ani když jde dítě nakonec do školky. Ověřeno grepem v aplikaci i v `setup.sql`.

### A22 — Nízká: zápisy do lokální DB bez ošetření chyby
- **Soubory:** `cyklus/index.tsx`, `cyklus/nastaveni.tsx`, `lekari.tsx`, `leky/index.tsx`, `nastaveni/osobni.tsx`, `skolka/nastavit.tsx`, `skolka/sdileni.tsx`, `ockovani/upravit.tsx`, `skolka/zpravy.tsx` (`personData.set`/`records.*` bez try/catch)
- **Popis:** Pokud zápis selže (zamčená DB po auto-zámku uprostřed ukládání, plný disk), vznikne nezachycená promise bez hlášky. Jen čteno.

### A23 — Nízká: zastaralá dokumentace a drobnosti
- `docs/REVIZE.md:159` tvrdí, že data školky „zatím přicházejí jen jako ukázka“, ale serverové propojení už je hotové. Komentář `skolka/index.tsx:23` je na tom stejně.
- `domain/skolkaServer.ts:73`: `paidAt` = datum splatnosti, ne datum platby.
- Fotky ze serveru (`alba.fotky`) se nezobrazují, jen barevné náhledy (`fotky.tsx`). Funkce „Fotky“ je pro propojenou školku prázdná ozdoba. Jen čteno.

---

## 5. Bezpečnost a soukromí: shrnutí

| Bod | Zjištění | Stav |
|---|---|---|
| Refresh token školky | Keychain/Keystore `lifeos.skolka.auth.v1`, `AFTER_FIRST_UNLOCK_THIS_DEVICE_ONLY` (bez zálohy, bez přenosu na jiné zařízení), access token jen v paměti | čteno + mock OVĚŘENO; na zařízení NEOVĚŘENO |
| Úklid tokenu | nemaže se nikdy (A8) | SELHÁVÁ |
| Klíč Supabase v kódu | jen publishable klíč, tajný ne | čteno, OK |
| Nešifrované úložiště | Keychain: auth, `lifeos.publicEmergency` (vědomá výjimka, volitelná), token školky. Cache: export JSON/FHIR a záloha, mažou se ve `finally`. Jiné AsyncStorage ani soubory nejsou. | čteno (grep) |
| Logování | v `src` není žádné `console.*` mimo testy | OVĚŘENO grepem |
| Oznámení na zamčené obrazovce | zdravotní detail dítěte (A19) | částečně OVĚŘENO |
| Android FLAG_SECURE / krytí v přepínači | přítomné v `_layout` | NEOVĚŘENO (zařízení) |
| Časová pásma | `LocalDate` z času zařízení (`toLocalDate`); server počítá uzávěrku oběda v `Europe/Prague` (OK). Datum nástěnky v UTC (A14), test v UTC (A15). Telefon v zahraničí: „Dnes“ v omluvence je den zařízení, ne Prahy (čteno). | částečně OVĚŘENO |
| Úniky mezi rodinami | zprávy `komu` (A9), akce tříd (A4), druhá školka (A3) | OVĚŘENO |

---

## 6. Co zůstalo neověřené
Build Expo/iOS/Android, vykreslení a navigace všech obrazovek, šifrování SQLCipher na zařízení, SecureStore a Keychain na skutečném zařízení (včetně přežití odinstalace na iOS), push a lokální oznámení, kamera/OCR (ML Kit), sdílení souborů, chování skutečného Supabase GoTrue (rotace refresh tokenů, rate-limit, UTC výstup).
