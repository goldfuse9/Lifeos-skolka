# LifeOS + Školka — stav auditu a dokončování

Průběžně aktualizovaný dokument (pro pokračování po přerušení). Poslední aktualizace: 14. 10. 2026.

## Systém

| Část | Repozitář / soubor | Běží |
| --- | --- | --- |
| LifeOS (rodiče, mobil) | `goldfuse9/lifeos`, větev `faze-1-mobil`, `mobile/` (Expo SDK 57) | iPhone/Android přes `npx expo run:*` |
| Správa LifeOS (superadmin) | `goldfuse9/Lifeos-skolka` `Admin.dc.html` | Netlify, `#admin` |
| Ředitelna | `Reditel.dc.html` | `#reditel` |
| Tablet třídy | `Trida.dc.html` | `#trida` |
| Jídelna | `Jidelna.dc.html` | `#jidelna` |
| Přihlášení | `Prihlaseni.dc.html` + `shell.js` | `#prihlaseni` |
| Napojení na server | `server.js` + `config.js` + `vendor/supabase-2.115.0.js` | Supabase `jokprqoifzjojbpozefh` (Frankfurt) |
| Databáze | `supabase/setup.sql` (= schema + pilot + všechny migrace), `supabase/migrace-*.sql` | Supabase |
| Finance (server) | `server/finance` (Python, FastAPI) | zatím nenasazeno |
| **Testovací režim** | `testy/` (viz níže) | lokálně / v kontejneru |

## Testovací režim (`testy/`)

Lokální náhrada Supabase: PostgreSQL 16 + PostgREST 12 + mini-proxy (`/rest/v1`, `/auth/v1`: anonymní účty, e-mail+heslo, potvrzování e-mailu pro `…@potvrdit.test`). **Nikdy se nepřipojuje ke skutečnému projektu** — testy přesměrují `config.js` na lokální proxy.

```bash
testy/lokalni/stack.sh [db] [port PostgREST] [port proxy] [port webu]   # spustí (výchozí skolka_lokal 3001 3002 8767)
testy/reset.sh [db]                                                      # obnoví výchozí smyšlená data
testy/spust-vse.sh                                                       # celý cyklus: bezpečnost + E2E + LifeOS
```

- `testy/data.sql` — dvě smyšlené školky (A Sluníčko, B Dejvice), všechny role (ředitelka, zástupkyně, učitelky, hospodářka, kuchařka, rodiče, superadmin, účet bez školky). Lokálně projde libovolné heslo.
- `testy/bezpecnost.sh` — 107 testů oprávnění přímo v DB pod skutečnými identitami (oddělení školek, citlivé sloupce, IDOR, blokace, kódy, zprávy, autor zápisu).
- `testy/e2e/` — Playwright: `superadmin`, `pristupy`, `pozvanka-potvrzeni`, `tablet-rodic` (průřez tablet ↔ rodič ↔ ředitelna ↔ jídelna).
- LifeOS: `SKOLKA_TEST_URL=http://localhost:3002 SKOLKA_TEST_KOD=<kód> npx jest skolkaserver` (dělá `spust-vse.sh` sám, pokud najde LifeOS s `node_modules`; cesta `LIFEOS_DIR`).
- Více instancí současně (pro paralelní agenty): každá vlastní DB a porty, např. `stack.sh skolka_b 3021 3022 8821`.

### Výsledky (14. 10. 2026, po opravách DB)

| Sada | Výsledek |
| --- | --- |
| `bezpecnost.sh` | **107/107 PASS** (před opravou 70/106) |
| E2E | **43/43 PASS** |
| LifeOS ↔ server (Jest integrace) | **5/5 PASS** |
| LifeOS typecheck / lint / Jest (agent A) | 0 chyb / 0 varování / 113 PASS, 1 skip (integrace bez URL) |

## Audit agenty (14. 10. 2026)

Šest nezávislých agentů souběžně, každý na vlastní kopii dat, jen audit (kód neměnili). Úplné zprávy: `docs/audit-2026-10-14/agent-*.md`.
A = LifeOS, B = Ředitelna, C = Jídelna, D = Tablet, E = Supabase/backend, F = nezávislé QA a bezpečnost.

## Sjednocené nálezy a stav

Stavy: OPRAVENO (oprava + test), V ŘEŠENÍ, CHYBÍ, NEOVĚŘENO, BLOKOVÁNO.

### 1. Bezpečnost a ochrana dat (priorita 1)

| # | Nález (zdroj) | Stav |
| --- | --- | --- |
| S1 | Kuchařka přes pohled `deti_jidelna` mění alergie a maže děti — obchází RLS (E1) | OPRAVENO (migrace 10-14, test) |
| S2 | Pozvánku přijme anonymní účet bez e-mailu (E2, F3) | OPRAVENO |
| S3 | `diety`, `jidlo_suroviny`, `nahrady` bez kontroly školky — kuchyně cizí školky čte/mění diety a alergeny (E3, F1, F2, C10, C11) | OPRAVENO |
| S4 | Třídní kniha čitelná/zapisovatelná vedením libovolné školky (E4, F4) | OPRAVENO |
| S5 | Rodné číslo, adresa, pojišťovna, očkování čitelné učitelkou, hospodářkou (E5, F5) | OPRAVENO (práva po sloupcích, `deti_osobni()` pro vedení a rodiče) |
| S6 | Ředitelka přímým UPDATE mění role, id účtu, blokuje spoluředitelku (E7) | OPRAVENO |
| S7 | Vazby napříč školkami: učitelka cizí školky do třídy, přesun dítěte „na dnes“ do cizí třídy, úraz do cizí knihy (E8, F6, F7, D4) | OPRAVENO |
| S8 | Rodič omlouvá zpětně a přepisuje „neomluven“ (E9) | OPRAVENO |
| S9 | Podvržení autora zápisu (`zapsal`) u událostí a úrazů (D9, F12) | OPRAVENO (trigger + zásada) |
| S10 | Adresné zprávy čte celá školka vč. rodičů a kuchařky (F8, A9) | OPRAVENO (`smi_zpravu`: vse / zamestnanci / trida:… / dite:…) |
| S11 | Kódy rodičů bez limitu pokusů; 7. znak jen 16 možností (E15, F11) | OPRAVENO (10 pokusů / 15 min, plně náhodné bajty) |
| S12 | Rodič s dětmi ve dvou školkách vidí účet/jídelníček jiné školky (E14, A3, A4) | OPRAVENO dočasně: druhou školku na stejný účet nejde spárovat (srozumitelná hláška); plná podpora více školek = CHYBÍ |
| S13 | Anon role má výchozí granty Supabase (E18); funkce bez `search_path` (E17) | OPRAVENO |
| S14 | Smazání dítěte smaže finanční záznamy; účet rodiče/učitelky nejde smazat (E11, E12) | OPRAVENO (dítě se ukončuje, FK `set null`/`restrict`) |
| S15 | Účetní pohyb na dítě padá na RLS konta (E6, F10) | OPRAVENO |
| S16 | **Data v prohlížeči (localStorage) nejsou oddělená podle účtu/školky a po odhlášení zůstávají** — vč. rodných čísel; ředitelka B vidí data A na sdíleném počítači (B2, C12, F9) | V ŘEŠENÍ (další krok) |
| S17 | Dvě záložky s různými účty sdílejí relaci (F7b) | V ŘEŠENÍ |
| S18 | Finanční API (Python) ignoruje blokaci školky/účtu (E13) | V ŘEŠENÍ (nenasazeno) |
| S19 | LifeOS: při selhání obnovy tokenu tiše založí nový anonymní účet (až 12×), odpojí děti (A1, A2) | V ŘEŠENÍ |
| S20 | LifeOS: oznámení ukazují zdravotní detail na zamčené obrazovce (A) | V ŘEŠENÍ |
| S21 | `moje_dite`/`trida_dnes` používají `current_date` serveru (UTC v Supabase) (D14) | V ŘEŠENÍ |

### 2. Ukázková data místo skutečných v ostrém provozu (priorita 2–3)

| # | Nález | Stav |
| --- | --- | --- |
| U1 | Ředitelna: 15 z 17 stránek v ostrém provozu ukazuje ukázkovou školku (62 smyšlených dětí, úrazy, dlužníci, IZO) a formuláře hlásí „uloženo/odesláno“, ale ukládají jen do prohlížeče (B1, B3, B5, B7) | V ŘEŠENÍ |
| U2 | Ředitelna nevidí úrazy a docházku z tabletu (B4, D10) | V ŘEŠENÍ |
| U3 | Jídelna nenačítá jídelníček ze serveru; „Zveřejnit“ přepíše skutečné menu ukázkovým (C1); počty obědů z kódu, odhlášky od rodičů se nepromítnou, kuchařka nečte docházku (C2); diety smyšlených dětí (C3); změna alergenů po zveřejnění se nepošle (C4, C5) | V ŘEŠENÍ |
| U4 | Tablet: oběd a varování k alergiím z ukázkového menu (D1); třídní kniha/fotky/akce/schůzky se neukládají, přesto „odesláno rodičům“ (D2) | V ŘEŠENÍ |
| U5 | Kniha úrazů: číslo počítal klient, souběh = ztracený úraz (D3, E10) | OPRAVENO (číslo přiděluje DB, tablet ukáže číslo ze serveru) |

### 3. Funkční chyby a chybové stavy

| # | Nález | Stav |
| --- | --- | --- |
| F-1 | Tablet: „Vrátit“ příchod omluveného dítěte nechá v DB „přítomen“ (D5); omluvené dítě přesto přišlo → oběd zůstane odhlášený (D6) | V ŘEŠENÍ |
| F-2 | Tablet hlásí úspěch před potvrzením serveru, při výpadku se zápis ztratí; bez sítě se neotevře (D8, F16) | V ŘEŠENÍ |
| F-3 | Tablet přes půlnoc zapíše do nového dne (D12) | V ŘEŠENÍ |
| F-4 | Zapomenuté heslo: chybí obrazovka pro nastavení nového hesla (F15) | V ŘEŠENÍ |
| F-5 | Zablokovaná učitelka vidí děti do obnovení; technické chyby DB anglicky se stack trace (F13, D8) | V ŘEŠENÍ |
| F-6 | LifeOS: omluvenka/vyzvednutí offline ukáže „omluveno“, ale na server neodejde; chybí fronta zápisů (A5) | V ŘEŠENÍ |
| F-7 | LifeOS: zablokovaná školka → synchronizace tiše smaže data karty (A6); synchronizace přepíše ručně zadaný účet (A7); odpojení nezruší propojení na serveru (A8); „Poslat školce verzi z LifeOS“ smaže alergie, když jsou v LifeOS prázdné (A17) | V ŘEŠENÍ |
| F-8 | Jídelna: náhrada jednoho dne se objeví i jinde (C7); vypnutí náhrad je na serveru smaže natrvalo (C8); každé zveřejnění zdvojí suroviny (C15); validace dne/alergenu (C16) | V ŘEŠENÍ |
| F-9 | Pověřené osoby se na tabletu neukazují (D7); jedna třída na účet, zástupkyně bez třídy (D11) | CHYBÍ |

### Vyřešeno dříve (13. 10.)

Superadmin a pozvánky; Přístupy v ostrém provozu; NULL-bypass oprávnění u účtu bez role; stav/předplatné školky jen superadmin; poznámka správce skrytá; prázdná třída na tabletu; přihlášení po potvrzení e-mailu (PR #22, #23).

## Změněné soubory (větev `audit`)

- `testy/**` — testovací režim
- `supabase/migrace-2026-10-14-audit.sql` (nová), `supabase/setup.sql` (+ migrace)
- `server.js` (číslo úrazu ze serveru), `Trida.dc.html` (číslo úrazu), `sw.js` (v32)
- `docs/audit-2026-10-14/agent-*.md`, tento dokument

## Další krok

1. S16/S17 — oddělit data prohlížeče podle účtu a školky, mazat při odhlášení; v ostrém provozu nenačítat ukázková data.
2. U1–U4 — v ostrém provozu: nenapojené stránky zřetelně označit a zakázat jejich „ukládání“; napojit Kartotéku, Třídy, Docházku, Knihu úrazů, Zprávy (Ředitelna), jídelníček a počty obědů (Jídelna), oběd a alergie (Tablet).
3. F-1…F-8 podle priorit, LifeOS (S19, S20, F-6, F-7).

Pokračování po přerušení: přečíst tento soubor, `git status` v `/home/claude/lifeos-skolka` (větev `audit`), `testy/spust-vse.sh`, pokračovat prvním bodem „Další krok“.

## Externí blokace

- Živý Supabase z testovacího prostředí nedostupný → migrace a chování proti živé DB ověří uživatel (návod v PR). Rozdíly emulace: anonymní uživatel má v ostrém Supabase `email: ""`, realtime se lokálně netestuje.
- Push notifikace na iPhone: chybí placený Apple Developer účet; build iOS/Android nejde v kontejneru ověřit.
