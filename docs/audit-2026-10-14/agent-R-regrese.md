# Regresní audit R — Školka + LifeOS (14. 10. 2026)

Nezávislý auditor, jen testy (kód v repozitářích neměněn). Zmrazená kopie `/home/claude/skolka-audit-r` (HEAD `6703cbd`), LifeOS `/home/claude/lifeos-sv2/mobile` (větev `audit-skolka`, HEAD `378d87e`).
Vlastní instance: DB `skolka_r`, PostgREST 3071, proxy 3072, web 8871. Vlastní skripty, logy a snímky: `scratchpad/audit/R/` (`api-rpc.js`, `api-s.js`, `api-s2.js`, `matice.sh`, `seedB.sql`, `b-*.js`, `prochazka.js`, `fin_r.py`, `lifeos/src/__tests__/auditr.test.ts`, `shots/`).

## 1. Automatický cyklus

`testy/spust-vse.sh skolka_r 3071 3072 8871` (LIFEOS_DIR=…/lifeos-sv2/mobile) → **VŠE PROŠLO** (log `R/cyklus.log`).

| Sada | Výsledek |
| --- | --- |
| `bezpecnost.sh` (DB pod identitami) | **110/110 PASS** |
| E2E Playwright (10 sad) | **105/105 PASS** |
| Finance API (pytest) | **11 passed** |
| LifeOS ↔ server (Jest `skolkaserver`) | **6/6 PASS** |
| LifeOS `tsc --noEmit` / `expo lint` / `jest` | 0 chyb / 0 varování / 113 PASS, 2 skip (22 sad) |
| `bezpecnost.sh` na DB „stará verze (497cf59~1) + data + migrace 10-14“ | **110/110 PASS** |

Pozn.: existující E2E hlídají jen `pageerror`, ne `console.error`/HTTP chyby; doplnil jsem vlastní sběr (viz R14).

## 2. Nálezy původního auditu — stav

Vlastní testy: **API** = curl/fetch s JWT na `http://localhost:3072/rest/v1` (`api-rpc.js` 112 kontrol, `api-s.js` 87, `api-s2.js` 7), **matice** = čtení dat cizí školky ve všech 38 tabulkách + 2 pohledech + RPC pro 9 identit (`matice.sh`, data B nasazena do každé tabulky), **UI** = vlastní Playwright skripty, **fin** = `fin_r.py` (17 kontrol), **LifeOS** = vlastní Jest proti lokálnímu serveru (5 testů).

### 2.1 Sjednocené nálezy (S/U/F-)

| # | Stav | Jak ověřeno |
| --- | --- | --- |
| S1 (E1) deti_jidelna zápis | OVĚŘENO-OPRAVENO | API: PATCH/DELETE `deti_jidelna` kuchařkou → 403, dítě zůstalo |
| S2 (E2, F3) pozvánka anon. účtem | OVĚŘENO-OPRAVENO | API: nový anonymní účet + cizí e-mail → `prijmi_pozvanku` odmítnuto |
| S3 (E3, F1, F2, C10, C11) jídelna napříč školkami | OVĚŘENO-OPRAVENO | matice (diety/jidla/nahrady/jidlo_suroviny/suroviny B = 0 pro všechny identity A); API: kuchařka A nevloží dietu/náhradu B, nesmaže alergeny jídla B, nepřipojí surovinu B |
| S4 (E4, F4) třídní kniha | OVĚŘENO-OPRAVENO | matice 0; API: ředitelka A nezapíše do knihy třídy B; rodič nečte |
| S5 (E5, F5) RČ a citlivé sloupce | OVĚŘENO-OPRAVENO | API: učitelka/hospodářka/kuchařka/rodič — `select=rodne_cislo,adresa,pojistovna,ockovani,kod_cizince,obec` i `select=*` → 403; `deti_osobni` jen vedení své školky a rodič vlastního dítěte (ostatní []); `deti_trida`, `deti_jidelna` bez RČ; UI: hospodářka RČ ani adresu nevidí, citlivá pole má neaktivní; zástupkyně RČ vidí a úprava obce jde na server. Pozor R10 |
| S6 (E7) přímý UPDATE `uzivatele` | OVĚŘENO-OPRAVENO | API: role, id, skola_id, povýšení na ředitelku, rodič→učitelka, zástupkyně blokuje ředitelku — vše beze změny |
| S7 (E8, F6, F7, D4) vazby napříč školkami | OVĚŘENO-OPRAVENO (s výjimkami R6) | API: úraz se skola_id B, trida_dnes do B, učitelka B do třídy A, dítě do třídy B, událost/pověřená osoba/souhlas/předpis/vyzvednutí/zástupce dítěti B, akce do B — vše odmítnuto |
| S8 (E9) zpětné omluvy | OVĚŘENO-OPRAVENO | API: rodič omlouvá 1. 10. → „Zpětně omlouvá jen školka“ |
| S9 (D9, F12) autor zápisu | OVĚŘENO-OPRAVENO | API: učitelka posílá `zapsal`=ředitelka u události i úrazu → uloží se ona; číslo úrazu 999 přepsáno DB |
| S10 (F8, A9) zprávy podle adresáta | OVĚŘENO-OPRAVENO | API: 4 zprávy (vse/zaměstnanci/třída Berušky/dítě Oliver) × 5 identit — každý vidí přesně své; rodič/kuchařka nepíší; ředitelka A nepíše do B. Viz E16 |
| S11 (E15, F11) kódy rodičů | OVĚŘENO-OPRAVENO, ale obejitelné (R4) | API: po 10 chybách 11. pokus odmítnut česky, blokován i platný kód a `nahled_kodu`; anon/učitelka/rodič kódy nečtou |
| S12 (E14, A3, A4) rodič ve dvou školkách | OVĚŘENO-OPRAVENO (dočasné řešení), obejitelné ředitelkou (R5) | API: rodič B s kódem dítěte A → „Tento telefon je už propojený s jinou školkou…“ |
| S13 (E17, E18) anon granty, search_path | OVĚŘENO-OPRAVENO (pozor R7) | API anon: pozvanky, skoly_admin, superadmini, deti, uzivatele, zpravy, pokusy_kodu, admin_skoly → nic; DB: žádná SECURITY DEFINER funkce bez search_path |
| S14 (E11, E12) mazání | OVĚŘENO-OPRAVENO | API: ředitelka dítě nesmaže (403, ukončuje se), finance zůstávají; DB: smazání auth účtu rodiče projde (zástupce zůstane), učitelky s úrazem blokuje FK (záměr — úraz je zákonný záznam) |
| S15 (E6, F10) konto dítěte | OVĚŘENO-OPRAVENO | API: hospodářka zaúčtuje banka→dite:Ema, saldo 100; neplatný MD odmítnut; pohyb nejde smazat; učitelka neúčtuje; pohyb na dítě B odmítnut |
| S16 (B2, C12, F9) localStorage | OVĚŘENO-OPRAVENO | UI: ředitelka A projde 6 stránek + kartu → v LS/SS/IndexedDB/Cache nic o dětech; po odhlášení tlačítkem zůstane jen `skolka-oblast`, `skolka-posledni-deska`; Zpět ani `#reditel` nic neukážou; ředitelka B poté na 4 stránkách nic z A. Crawl: po odhlášení u všech rolí stejné |
| S17 (F7b) dvě záložky | OVĚŘENO-OPRAVENO | UI: stejný účet ve 2. záložce (jiná deska) první neodhlásí; odhlášení ve 2. → 1. na přihlášení; jiný účet ve 2. → 1. na přihlášení |
| S18 (E13) finance a blokace | OVĚŘENO-OPRAVENO | fin: zablokovaná hospodářka / školka → 403; učitelka, kuchařka, rodič, superadmin, bez role → 403; cizí dítě → 404; podvržený/propadlý/bez aud/alg=none JWT → 401 |
| S19 (A1, A2, E20) LifeOS obnova tokenu | OVĚŘENO-OPRAVENO | LifeOS: obnova vrátí 400 → 3 souběžná stažení = 1 obnova, všechna `vyprselo`, signup nevolán, počet `auth.users` beze změny |
| S20 (A19) oznámení na zamčené obrazovce | NEOVĚŘENO (jen čtení kódu) | text oznámení je obecný, titulek dál obsahuje jméno dítěte a školky; na zařízení nelze spustit |
| S21 (D14) `current_date` v UTC | OVĚŘENO-OPRAVENO | DB: žádná funkce/zásada/výchozí hodnota s `current_date`; `dnes_praha()` nezávisí na TZ relace (UTC, +14, −7). Pozn.: lokální PG běží v Europe/Prague, takže E2E UTC neemulují |
| U1 (B1, B3, B5, B7) ukázková data v ředitelně | ČÁSTEČNĚ — SELHÁVÁ v Knize úrazů (R2, R3) | UI crawl 13 rolí/desek × 2 rozlišení: v ostrém provozu žádná ukázková jména (porovnání s 53 jmény ze zkušebního provozu), nenapojené stránky skryté; Třídy (provoz, nová třída), karta dítěte, dny absence úrazu jdou na server. „Poslat rodičům“ a „Odeslat ČŠI“ v Knize úrazů ale hlásí odeslání, které neproběhne |
| U2 (B4, D10) úrazy a docházka z tabletu | OVĚŘENO-OPRAVENO | UI: úraz učitelky se v Knize úrazů objeví, Docházka „Dnes z tabletů · ze serveru“ |
| U3 (C1–C5) jídelna | OVĚŘENO-OPRAVENO, nové problémy R8, R9 | UI: jídelníček, diety (Ema, Tobiáš), počty (= `obedy_den`) ze serveru; přidaná surovina s alergenem 3 se do 2,5 s propsala rodiči ({7}→{3,7}); katalog v `jidelna_katalog` přežije nové přihlášení |
| U4 (D1, D2) tablet | OVĚŘENO-OPRAVENO | UI: oběd ze serveru, varování „Ema T. bez mléka“ u oběda s alergenem 7; Fotky/Akce/Schůzky skryté; třídní kniha při výpadku hlásí „neuložila“ |
| U5 (D3, E10) číslo úrazu | OVĚŘENO-OPRAVENO | API: klient posílá 999, DB přidělí další číslo |
| F-1 (D5, D6) Vrátit / přesto přišel | ČÁSTEČNĚ — D5 opraveno, D6 SELHÁVÁ | UI: Vrátit příchod → řádek smazán; Vrátit odchod → odchod smazán; omluvený přišel → přítomen, omluvenka zrušena, ale `strava_prihlasena=false` zůstane (kuchyně ho nezapočte) a UI to neřekne |
| F-2 (D8, F16) úspěch před potvrzením | OVĚŘENO-OPRAVENO (online); offline otevření NEOVĚŘENO | UI: výpadek při odchodu → po 7,1 s „Neuloženo…“ a dítě zpět „ve třídě“ (do té doby UI ukazuje „odešel“); service worker Playwright blokuje |
| F-3 (D12) půlnoc | OVĚŘENO-OPRAVENO | UI s `page.clock`: tablet otevřený 23:59:20, klik v 0:00:10 → zápis k novému dni; po ~1 min se tablet sám načte s novým datem |
| F-4 (F15) nové heslo z e-mailu | OVĚŘENO-OPRAVENO (formulář); e-mail ze Supabase NEOVĚŘENO | UI: „Zapomenuté heslo“ pošle `/auth/v1/recover` s e-mailem a `redirect_to`; propadlý odkaz → česká hláška. Lokální proxy vrací 204 → aplikace hlásí chybu (artefakt, R13) |
| F-5 (F13, D8) blokace a technické chyby | ČÁSTEČNĚ | UI: zablokovaná učitelka během práce — zápis neprojde, česká hláška; děti ale zůstanou na obrazovce do obnovení (R11). Zablokovaná školka — přihlášení s vysvětlením. API: 5 rolí zablokované školky nic nevidí ani nezapíše, ředitelka si školku neodblokuje |
| F-6 (A5) LifeOS offline omluvenka | NEOVĚŘENO | jen čtení kódu (zápis do osy až po přijetí) |
| F-7 (A6, A7, A8, A17) LifeOS synchronizace | A6 a A8 OVĚŘENO-OPRAVENO; A7, A17 NEOVĚŘENO (kód) | LifeOS: zablokovaná školka → `blokovano`, nic se nepřepíše; `odpojDite` zruší vazbu na serveru, další stažení → `odpojeno`; `zapomenUcet` smaže token. Offline odebrání karty chybu spolkne (`.catch(() => {})`) → vazba na serveru zůstane |
| F-8 (C7, C8, C15, C16) náhrady a validace | C7 OVĚŘENO-OPRAVENO; C8, C15 jen automatický cyklus; C16 ČÁSTEČNĚ (R1, R12) | UI: náhrada upravená pro pondělí se uloží, stejné jídlo ve středu si svou nechá; API: víkend, mimo týden, neznámý chod, prázdný název, alergen 15, p_od>p_do odmítnuty česky |
| F-9 (D7, D11) pověřené osoby na tabletu, víc tříd | CHYBÍ (beze změny) | UI: ředitelka i zástupkyně do „Třída“ → „Tento přístup do části Třída nevede“ |

### 2.2 Ostatní ID ze zpráv agentů

| ID | Stav | Ověření / poznámka |
| --- | --- | --- |
| A1, A2, A6, A8 | OVĚŘENO-OPRAVENO | LifeOS test (viz S19, F-7) |
| A3, A4, A5, A7, A17, A19 | NEOVĚŘENO | jen kód (UI mobilu nelze v kontejneru spustit) |
| A9 | OVĚŘENO-OPRAVENO | = S10 |
| A12 | **SELHÁVÁ** | LifeOS: odpověď 502 s HTML → `SyntaxError` místo `ServerError` (`skolkaServer.ts` `JSON.parse` bez ošetření) |
| A15 | **SELHÁVÁ** (nízká) | integrační test počítá `today` z `toISOString()` (UTC) |
| A10, A11, A13, A14, A16, A18, A20–A23 | NEOVĚŘENO | mimo rozsah regrese |
| B1–B5, B7 | OVĚŘENO-OPRAVENO | crawl + UI (nenapojené stránky skryté, data ze serveru, Archiv skrytý) |
| B6 | OVĚŘENO-OPRAVENO | UI: jídelna z ředitelny B = „MŠ Dejvice (test) · Ostrý provoz“ |
| B8 | BEZE ZMĚNY (záměr?) | zástupkyně má Přístupy v ostrém provozu, ve zkušebním ne; viz R15 |
| B9, B10 | OVĚŘENO | Učitelé skryti; profil = účet ze serveru |
| B11–B13 | NEOVĚŘENO | |
| B14 | OVĚŘENO-OPRAVENO | `reset.sh` posílá `notify pgrst` |
| C1–C5, C7, C10–C12, C14 | OVĚŘENO-OPRAVENO | UI/API (viz U3, S3) |
| C6, C8, C15 | OVĚŘENO jen automatickým cyklem | |
| C9, C13 | NEOVĚŘENO | |
| C16 | ČÁSTEČNĚ | R1, R12 |
| D1–D5, D8–D10, D12, D14 | OVĚŘENO-OPRAVENO | |
| D6 | **SELHÁVÁ** | viz F-1 |
| D7, D11 | CHYBÍ | viz F-9 |
| D13 | **SELHÁVÁ** | API: rodič omluví dnešek, dítě je přítomno → DB zůstane `pritomen`, ale RPC vrátí `[{"den":"2026-10-14","obed_odhlasen":false}]` = LifeOS ukáže „omluveno“ |
| D15, D16 | NEOVĚŘENO | |
| D17 | BEZE ZMĚNY (info) | rodič čte řádek `urazy` (svědek, komentář, zapsal) |
| E1–E10, E12–E15, E17, E18, E20 | OVĚŘENO-OPRAVENO | viz výše |
| E11 | OVĚŘENO | rodič smazatelný; učitelka s úrazem blokována FK (záměr) |
| E16 | **SELHÁVÁ** (nízká) | API: zpráva s `komu='nesmysl:xyz'` přijata (201); učitelka B čte všechny účty školky vč. jmen rodičů |
| E19 | ČÁSTEČNĚ | audit trigger na 15 tabulkách; docházka, třídy, stav školky bez auditu |
| F1–F12 | OVĚŘENO-OPRAVENO | viz S1–S15 |
| F13 | ČÁSTEČNĚ | R11 |
| F14 | OVĚŘENO | e-mail s mezerami v `pozvi_zamestnance` odmítnut česky (UI ořezává) |
| F15, F16 | viz F-4, F-2 | |

### 2.3 Regrese (bod 3)

| Kontrola | Výsledek |
| --- | --- |
| Zkušební provoz (config bez `SKOLKA_SERVER`) | OK — ředitelka (19 stránek), zástupkyně (17), hospodářka (8), kuchařka a vedoucí ŠJ (7), učitelka (6 záložek), ředitelka v jídelně; vše bez chyby JS, data v localStorage |
| Role v ostrém provozu | OK — ředitelka 11, zástupkyně 10, hospodářka 6 stránek, kuchařka a ředitelka v jídelně 6, učitelka 3, superadmin `#admin` 6; učitelka→Ředitelna, kuchařka→Třída, hospodářka→Jídelna, bez role → srozumitelné odmítnutí |
| Chyby v konzoli | žádný `pageerror`; jen artefakty prostředí (písma, SW, realtime 404, HEAD `uzivatele?…count` přerušený přes lokální proxy, logout) — R14 |
| Rozložení 1440×900 a 1194×834 | OK — žádné vodorovné rolování ani prvky mimo obrazovku (automatická kontrola + snímky `shots/o-*`, `z-*`) |
| Migrace 2× za sebou na DB ze `setup.sql` | OK — 0 chyb v obou bězích |
| Migrace na DB ze staré verze (`497cf59~1`) + stará data, 2× | OK — 0 chyb; schéma = `setup.sql` až na granty (R7); `bezpecnost.sh` 110/110 |

## 3. Nové nálezy

| # | Závažnost | Nález |
| --- | --- | --- |
| R2 | Vysoká | Kniha úrazů v ostrém provozu: „Odeslat ČŠI a pojišťovně“ hlásí odeslání, nic neodejde |
| R1 | Střední | `zverejni_jidelnicek`: neomezený rozsah smaže celou historii jídelníčku |
| R3 | Střední | Kniha úrazů: „Poslat rodičům“ hlásí doručení, na server nic nejde |
| R8 | Střední | Jídelna: rozpracovaný (nezveřejněný) týden se ztratí |
| R9 | Střední | Jídelna: dvě otevřené desky si přepisují zveřejněný týden |
| R4 | Nízká–střední | Limit pokusů o kód jde obejít novým anonymním účtem |
| R5 | Nízká–střední | Ředitelka připojí k dítěti libovolný účet, i rodiče jiné školky |
| R6 | Nízká | Zbylé vazby napříč školkami: `akce`/`alba.trida_id`, `platby.dite_id` |
| R7 | Nízká | Čerstvý `setup.sql` nechá EXECUTE pro PUBLIC na 7 nových funkcích |
| R10 | Nízká | `odpoj_rodice` smaže osiřelé záznamy zástupců u cizího dítěte |
| R11 | Nízká | Zablokovaná učitelka vidí děti do obnovení stránky |
| R12 | Nízká | `zverejni_jidelnicek`: anglické chyby a tiché přijetí neplatného vstupu |
| R15 | Nízká | Přístupy: zástupkyně „Ředitelna, Třída“, do Třídy ji ale nepustí |
| R16 | Nízká | Hospodářka: kartotéka hlásí chybějící RČ a adresu, které jen nevidí |
| R17 | Nízká | Pestrost týdne počítá jen jídla z ukázkového katalogu |
| R13 | Info | Lokální proxy: `/auth/v1/recover` vrací 204, HEAD se přeruší |
| R14 | Info | E2E nehlídají `console.error` ani HTTP chyby |
| R18 | Info | Drobnosti: `__pycache__` v gitu, gramatika, dvojitá tečka |

### R1 — `zverejni_jidelnicek`: neomezený rozsah smaže celou historii jídelníčku (Střední)
- Reprodukce (API, kuchařka A): `rpc/zverejni_jidelnicek {"p_dny": [], "p_od": "2000-01-03", "p_do": "2099-12-31"}` → 200, `jidelnicek` školky A 20 → 0 řádků. Stejně dopadne klient s chybným `p_do`.
- Oprava: vyžadovat `p_od` i `p_do` současně, `p_od` = pondělí, `p_do = p_od + 4`; jinak výjimka. Mazání jen v tomto týdnu.

### R2 — Kniha úrazů v ostrém provozu: „Odeslat ČŠI a pojišťovně“ hlásí odeslání, nic neodejde (Vysoká)
- Reprodukce: ředitelka → Kniha úrazů → úraz s 3 dny absence → „Vyplnit do 5. 11.“ → „Odeslat ČŠI a pojišťovně“. Toast: „Záznam o úrazu odeslán ČŠI a pojišťovně (zkušební provoz)“, `urazy.zaznam_odeslan` = dnes, sloupec se přepne na odesláno. Žádné odeslání neexistuje. Ředitelka tak může zmeškat zákonnou lhůtu (do 5. dne dalšího měsíce).
- Oprava: v ostrém provozu tlačítko „Stáhnout záznam (PDF) a označit jako odeslaný“ s textem, že se odesílá ručně; nebo skrýt. Opravit text toastu (Reditel.dc.html ~ř. 4197).

### R3 — Kniha úrazů: „Poslat rodičům“ hlásí doručení, na server nic nejde (Střední)
- Reprodukce: úraz → „Poslat rodičům“ → „Rodiče Ema dostali zápis o úrazu do aplikace“, sloupec „Posláno 14.“. Bez síťového požadavku, `udalosti_ditete` beze změny; po novém přihlášení zase „Poslat rodičům“ (`sendParents`, Reditel.dc.html ~ř. 3276).
- Oprava: v ostrém provozu zapsat `udalosti_ditete` (druh `uraz`, není-li už z tabletu) a stav uložit do DB (sloupec v `urazy`); jinak tlačítko skrýt.

### R4 — Limit pokusů o kód jde obejít novým anonymním účtem (Nízká–střední)
- Reprodukce: účet s 10 chybami je blokován; hned založený nový anonymní účet (`/auth/v1/signup {}`) dostane z `nahled_kodu` jméno, příjmení a datum narození dítěte. Limit je jen v `pokusy_kodu` podle `uzivatel_id`.
- Oprava: globální limit (např. podle IP v Edge Function nebo celkový počet chybných pokusů za minutu), zapnout CAPTCHA / limit anonymních registrací v Supabase; z `nahled_kodu` nevracet datum narození.

### R5 — Ředitelka připojí k dítěti libovolný účet, i rodiče jiné školky (Nízká–střední)
- Reprodukce (API): ředitelka A `PATCH /zastupci?dite_id=eq.<Ema>` `{"uzivatel_id": "<rodič školky B>"}` → 200; rodič B pak čte Emu (`deti`, `deti_osobni`). Stejně jde připojit účet učitelky jako rodiče. Obchází i dočasné řešení S12.
- Oprava: `zast_menit` WITH CHECK `uzivatel_id is null or exists (select 1 from uzivatele u where u.id = uzivatel_id and u.skola_id = moje_skola() and u.role = 'rodic')`; v `moje_dite` u rodiče kontrolovat `skola_id` dítěte = škola účtu.

### R6 — Zbylé vazby napříč školkami: `akce`/`alba.trida_id`, `platby.dite_id` (Nízká)
- Reprodukce (API): ředitelka A vloží `akce`/`alba` se `skola_id` A a `trida_id` třídy B (201); hospodářka A vloží `platby` se `dite_id` dítěte B (201). Únik dat to není (čtení filtruje `skola_id`), jde o integritu dat a párování plateb.
- Oprava: WITH CHECK `trida_id is null or exists (select 1 from tridy where id = trida_id and skola_id = moje_skola())`, u plateb obdobně pro `dite_id`.

### R7 — Čerstvý `setup.sql` nechá EXECUTE pro PUBLIC na 7 nových funkcích (Nízká)
- Reprodukce: `pg_dump -s` DB ze `setup.sql` a téže DB po migraci se liší jen `REVOKE ALL … FROM PUBLIC` u `deti_diety, dnes_praha, dochazka_souhrn, jidelnicek_kuchyne, obedy_den, odpoj_rodice, zverejni_jidelnicek` (proacl `=X/postgres`). Funkce se hlídají samy (anon dostane prázdno nebo chybu), ale `setup.sql` ≠ výsledek migrace.
- Oprava: v `setup.sql` dát hromadné `revoke … from public` až za poslední definici funkce (nebo výslovné revoke u každé nové).

### R8 — Jídelna: rozpracovaný (nezveřejněný) týden se ztratí (Střední)
- Reprodukce: kuchařka → Jídelníček → › (19.–23. 10.) → vybere jídlo (zobrazí se) → nové přihlášení nebo jiný počítač → týden prázdný; v DB 0 řádků. Návrh je jen v paměti (ostrý provoz nemá localStorage), bez varování.
- Oprava: ukládat návrh na server (`jidelnicek.zverejneno = false` přes RPC typu `uloz_navrh`; `jidelnicek_tyden` už filtruje `zverejneno`), nebo aspoň varovat při odchodu (`beforeunload`) a v UI.

### R9 — Jídelna: dvě otevřené desky si přepisují zveřejněný týden (Střední)
- Reprodukce: kuchařka (deska 1) i ředitelka (deska 2) mají otevřený týden 12.–16. 10. Deska 1 přidá pitný režim → na serveru. Deska 2 (starý stav) změní středeční svačinu → `srvSync` pošle celý týden a `zverejni_jidelnicek` smaže chody, které deska 2 nezná. Nápoj zmizel (nap 1 → 0). Stejně se může ztratit změna alergenu nebo náhrady.
- Oprava: optimistická kontrola verze (`zmeneno` u týdne, RPC odmítne starší verzi a deska data znovu načte), nebo posílat jen změněné chody místo celého týdne s mazáním.

### R10 — `odpoj_rodice` smaže osiřelé záznamy zástupců u cizího dítěte (Nízká)
- Reprodukce (API): účet bez role (i čerstvý anonymní) zavolá `odpoj_rodice(<dítě školky B>)` → smaže zástupce dítěte B s `poradi=9`, bez účtu a kontaktu (vznikají po smazání anonymního účtu díky FK `set null`). Je potřeba znát UUID dítěte.
- Oprava: mazat jen řádek, který volající právě odpojil (`… returning id`), nebo smazání podmínit tím, že volající byl k dítěti připojen.

### R11 — Zablokovaná učitelka vidí děti do obnovení stránky (Nízká, zbytek F13)
- Reprodukce: tablet otevřený → ředitelka zablokuje → první zápis „Neuloženo — nemáte oprávnění…“, děti ale zůstanou na obrazovce i po přepnutí záložek.
- Oprava: při chybě 401/403 nebo RLS zavolat `muj_stav` a při `aktivni=false` odhlásit (jako při obnovení stránky).

### R12 — `zverejni_jidelnicek`: anglické chyby a tiché přijetí neplatného vstupu (Nízká)
- Reprodukce: alergen `"abc"` → „invalid input syntax for type smallint“; den `"zitra"` → „invalid input syntax for type date“; chybějící `den` → „null value in column den…“; `p_dny: null` → 200, 0 řádků; `p_od` bez `p_do` → 200 bez kontroly rozsahu.
- Oprava: validovat typy a povinná pole v RPC a vracet české hlášky.

### R13 — Lokální proxy: `/auth/v1/recover` vrací 204, HEAD se přeruší (Info, testovací prostředí)
- `/auth/v1/recover` vrací 204 bez těla → aplikace po „Zapomenuté heslo“ hlásí „Server školky odpověděl chybou“ (Supabase vrací 200 `{}`). Chromium přeruší HEAD `uzivatele?select=id…` (počet zaměstnanců) přes proxy (`net::ERR_ABORTED`).
- Oprava: v `sbproxy.js` vracet 200 `{}` a HEAD obsloužit bez těla; ověřit proti Supabase.

### R14 — E2E nehlídají `console.error` ani HTTP chyby (Info)
- `stranka()` sbírá jen `pageerror`. Doporučení: sbírat `console` (error) a odpovědi ≥ 400 z `/rest/v1`, s výjimkami pro písma, SW a realtime.

### R15 — Přístupy: zástupkyně „Ředitelna, Třída“, do Třídy ji ale nepustí (Nízká)
- Přehled u zástupkyně uvádí „Ředitelna · Třída“; přihlášení do Třídy → „Tento přístup do části Třída nevede. Patří do: Ředitelna.“ Souvisí s D11 a B8.
- Oprava: sjednotit texty s pravidly přihlášení.

### R16 — Hospodářka: kartotéka hlásí chybějící RČ a adresu, které jen nevidí (Nízká)
- U všech dětí „bez RČ“, „Do matriky chybí: rodné číslo, obec, adresa“ a filtr „Jen s chybějícími údaji · 3“. Údaje existují, hospodářka je jen nevidí (práva po sloupcích).
- Oprava: pro role bez práv ukazovat „skryto“ a nepočítat to do chybějících údajů.

### R17 — Pestrost týdne počítá jen jídla z ukázkového katalogu (Nízká)
- Jídelna v ostrém provozu: „Ryby 0×“, přestože ve středu je „Rybí filé“ (alergen 4). Jídla ze serveru nemají kategorii; katalog = 33 ukázkových jídel + jídla ze serveru (49).
- Oprava: kategorie odvozovat z alergenů a surovin, nebo je ukládat k jídlu.

### R18 — Drobnosti (Info)
- `server/finance/__pycache__/*.pyc` a `server/tests/__pycache__` jsou commitnuté (přidat do `.gitignore`). Každý běh `spust-vse.sh` je přepíše, takže pracovní strom je pak „změněný“. Po auditu jsem je vrátil přes `git checkout`.
- Tablet skloňuje u dívek „ještě nedorazil“ a „odešel“.
- Hlášky končí dvojitou tečkou („…zablokovaný).. Dítě je zpět…“).
- Tablet ukazuje „odešel“ ~7 s, než při výpadku vrátí stav.
- Přehled ředitelny: „učitelky to vidí v galerii“, galerie je ale v ostrém provozu skrytá.
