# LifeOS + Školka — stav auditu a dokončování

Průběžně aktualizovaný dokument (pro pokračování po přerušení). Poslední aktualizace: 13. 10. 2026.

## Systém

| Část | Repozitář / soubor | Běží |
| --- | --- | --- |
| LifeOS (rodiče, mobil) | `goldfuse9/lifeos`, větev `faze-1-mobil`, `mobile/` (Expo SDK 57) | iPhone/Android přes `npx expo run:*` |
| Ředitelna | `goldfuse9/Lifeos-skolka` `Reditel.dc.html` | Netlify (statický web), `#reditel` |
| Tablet třídy | `Trida.dc.html` | `#trida` |
| Jídelna | `Jidelna.dc.html` | `#jidelna` |
| Přihlášení | `Prihlaseni.dc.html` + `shell.js` | `#prihlaseni` |
| Napojení na server | `server.js` + `config.js` + `vendor/supabase-2.115.0.js` | Supabase projekt `jokprqoifzjojbpozefh` (Frankfurt) |
| Databáze | `supabase/setup.sql` (= schema + pilot + doplňky), `supabase/migrace-*.sql`, `supabase/seed-pilot.sql` | Supabase |
| Finance (server) | `server/finance` (Python, FastAPI, Celery) | zatím nenasazeno |

## Testovací infrastruktura (v cloudovém kontejneru)

- PostgreSQL 16 + PostgREST 12 + mini-proxy (`/rest/v1`, `/auth/v1`: anonymní účty, registrace e-mail+heslo, přihlášení heslem) = lokální náhrada Supabase; skripty ve scratchpadu (`stack.sh`, `sbproxy.js`, `jwt.js`).
- Playwright (Chromium) pro desky školky, Jest pro LifeOS (`npx jest`, integrační test `SKOLKA_TEST_URL=… npx jest skolkaserver`).
- Živý Supabase projekt z kontejneru **není dosažitelný** (síť) → vše proti živé databázi je NEOVĚŘENO, dokud to neověří uživatel.

## Plán

1. [hotovo, větev `superadmin`] Superadmin: správa školek, ředitelek, aktivace/blokace, předplatné; pozvánky místo ručních účtů; vynucení v DB (RLS/RPC).
2. Nezávislé audity (agenti): LifeOS, desky školky, Supabase/RLS.
3. Opravy podle priorit (bezpečnost → přihlášení/ukládání → hlavní funkce → integrace → UI).
4. Regresní kolo, závěrečná zpráva.

## Nalezené problémy

| # | Závažnost | Kde | Problém | Stav |
| --- | --- | --- | --- | --- |
| 1 | vysoká | ředitelna (server) | Přístupy v ostrém provozu nefungují — účty zaměstnanců jen ručně v Supabase | OPRAVENO (pozvánky, blokace; test a2) |
| 2 | střední | přihlášení (server) | Přihlašovací obrazovka v ostrém provozu ukazuje „Zkušební provoz · heslo skolka“ a pevný název školky | OPRAVENO |
| 3 | střední | celý systém | Chybí správa školek (superadmin), blokace školy/účtu | OPRAVENO (`#admin`, test a1) |
| 4 | **kritická** | databáze | Účet bez role (kdokoli s anonymní registrací) prošel kontrolami `omluv_dite`, `uprav_udaje_rodicem`, `zverejni_jidelnicek`, `nastav_nahrady` — `moje_dite()`/`je_vedeni()` vracely NULL a `if not (NULL)` nezakázalo. Šlo omluvit cizí dítě a přepsat alergie (při znalosti UUID dítěte). | OPRAVENO v migraci c (vždy true/false); regresní testy `sec.sh` |
| 5 | vysoká | databáze | Vedení školy mohlo přímo `update skoly` změnit stav, tarif a předplatné (obejít blokaci/platby) | OPRAVENO (trigger `hlidej_skolu`) |
| 6 | střední | databáze | Poznámka správce by byla čitelná ředitelce (`select * from skoly`) | OPRAVENO (tabulka `skoly_admin` bez zásad) |
| 7 | vysoká | ředitelna (server) | V ostrém provozu ukazuje kartotéka, platby, docházka, třídy… ukázková data; ze serveru jsou jen Přístupy a Rodiče v LifeOS. Hlavička ukazovala ukázkovou školku a jméno. | ČÁSTEČNĚ: hlavička ukazuje skutečnou školku/jméno a štítek „Pilot · část ukázková“; stránky zbývají |
| 8 | střední | tablet (server) | Učitelka v třídě bez dětí → deska spadla (`allergies` of undefined) a přihlášení viselo | OPRAVENO (srozumitelná hláška, odhlášení) |
| 9 | nízká | testy | Testovací data nejdou vrátit do výchozího stavu (s1 neprojde podruhé ve stejný den) | CHYBÍ — reset testovacích dat |
| 10 | nízká | LifeOS | Rodič zablokované školky: aplikace dostane prázdná data bez vysvětlení | NEOVĚŘENO |

## Zbývá / další krok

- PR `superadmin` → po sloučení: uživatel spustí migraci c v Supabase, založí si účet a zapíše se do `superadmini`.
- Bod 2 plánu: nezávislé audity, reset testovacích dat, testy do repozitáře, problém #7.

## Testy (lokálně, scratchpad)

| Test | Co ověřuje | Výsledek 13. 10. |
| --- | --- | --- |
| `sec.sh` | 30 bezpečnostních kontrol rolí (superadmin, ředitelka, učitelka, rodič, účet bez role, anon) | 30/30 PASS |
| `a1.js` | superadmin: přihlášení `#admin`, založení školky, pozvánka, registrace ředitelky (krátké heslo, špatný kód, správný kód), aktivace, blokace → přihlášení odmítnuto; ředitelka nesmí do `#admin` | PASS |
| `a2.js` | ředitelka: Přístupy ze serveru, pozvání učitelky (bez třídy odmítnuto), registrace učitelky, blokace → přihlášení odmítnuto | PASS |
| `s2.js`, `s3.js` | omluvenky, potvrzení, jídelníček, náhrady | PASS |
| `s1.js` | tablet: příchod/teplota/odchod | SELHÁVÁ při opakování ve stejný den (data už zapsaná — viz #9), není regrese |

## Externí blokace

- Živý Supabase z kontejneru nedostupný → testy proti živé DB dělá uživatel podle návodu.
- Push notifikace na iPhone: chybí placený Apple Developer účet.
