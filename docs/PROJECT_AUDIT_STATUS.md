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

- PostgreSQL 16 + PostgREST 12 + mini-proxy (`/rest/v1`, anonymní `/auth/v1`) = lokální náhrada Supabase; skripty ve scratchpadu (`stack.sh`, `sbproxy.js`, `jwt.js`).
- Playwright (Chromium) pro desky školky, Jest pro LifeOS (`npx jest`, integrační test `SKOLKA_TEST_URL=… npx jest skolkaserver`).
- Živý Supabase projekt z kontejneru **není dosažitelný** (síť) → vše proti živé databázi je NEOVĚŘENO, dokud to neověří uživatel.

## Plán

1. [probíhá] Superadmin: správa školek, ředitelek, aktivace/blokace, předplatné; pozvánky místo ručních účtů; vynucení v DB (RLS/RPC).
2. Nezávislé audity (agenti): LifeOS, desky školky, Supabase/RLS.
3. Opravy podle priorit (bezpečnost → přihlášení/ukládání → hlavní funkce → integrace → UI).
4. Regresní kolo, závěrečná zpráva.

## Nalezené problémy

| # | Závažnost | Kde | Problém | Stav |
| --- | --- | --- | --- | --- |
| 1 | vysoká | ředitelna (server) | Přístupy v ostrém provozu nefungují — účty zaměstnanců jen ručně v Supabase | v řešení (pozvánky) |
| 2 | střední | přihlášení (server) | Přihlašovací obrazovka v ostrém provozu ukazuje „Zkušební provoz · heslo skolka“ a pevný název školky | v řešení |
| 3 | střední | celý systém | Chybí správa školek (superadmin), blokace školy/účtu | v řešení |

## Zbývá / další krok

- Dokončit superadmina (bod 1 plánu).

## Externí blokace

- Živý Supabase z kontejneru nedostupný → testy proti živé DB dělá uživatel podle návodu.
- Push notifikace na iPhone: chybí placený Apple Developer účet.
