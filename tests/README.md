# Testovací režim školky

Všechno tady běží **lokálně a jen se smyšlenými daty**. Na ostrý Supabase se nic
nespouští.

## Co to je

| Část | Soubor | Co dělá |
| --- | --- | --- |
| Lokální „Supabase“ | `lokalni-supabase/` | PostgreSQL + PostgREST + proxy, která napodobí `/rest/v1` a přihlašování (`/auth/v1`: anonymní účty, registrace, heslo, obnova relace; `CONFIRM=1` = potvrzování e-mailu) |
| Testovací data | `../supabase/testovaci-data.sql` | 2 školky (A, B), 3 třídy, 8 dětí, všechny role, jídelníček na tento týden, dnešní docházka, úraz, událost. Jde spustit znovu — smaže a založí jen testovací školky (ID `eeeeeeee-…`). |
| Reset | `reset.sh` | čistá DB: stub Supabase → `supabase/setup.sql` → účty → testovací data |
| Bezpečnost DB | `db/bezpecnost.sh` | ~60 kontrol přístupů s různými identitami (oddělení školek, učitelka, rodič, superadmin, blokace, účet bez role, anon) — ověřuje skutečné výsledky dotazů |
| E2E | `e2e/*.js` | Playwright v Chromiu: superadmin, přístupy, pozvánka s potvrzením e-mailu, scénář tablet → rodič → ředitelna → jídelna |
| Celý cyklus | `spust-vse.sh` | všechno výše, výsledky v `vysledky/` |

## Testovací účty (heslo `Test-heslo-2026`)

| E-mail | Role | Školka / třída |
| --- | --- | --- |
| superadmin@test.lifeos.cz | správce LifeOS | — |
| reditelka.a@test.lifeos.cz | ředitelka | A |
| zastupce.a@test.lifeos.cz | zástupkyně | A, Berušky |
| ucitelka.a@test.lifeos.cz | učitelka | A, Sluníčka (Ema, Oliver, Sofie, Jakub) |
| ucitelka2.a@test.lifeos.cz | učitelka | A, Berušky (Anna, Matyáš) |
| hospodarka.a@test.lifeos.cz | hospodářka | A |
| kucharka.a@test.lifeos.cz | kuchařka | A |
| zablokovana.a@test.lifeos.cz | učitelka, **zablokovaná** | A |
| rodic.a@test.lifeos.cz | rodič Emy a Sofie | A |
| rodic2.a@test.lifeos.cz | rodič Olivera | A |
| reditelka.b@test.lifeos.cz | ředitelka | B |
| ucitelka.b@test.lifeos.cz | učitelka | B, Žabky (Adam, Ella) |
| rodic.b@test.lifeos.cz | rodič Adama | B |

## Spuštění

Potřeba: PostgreSQL 16, PostgREST 12 (binárka, cesta v `POSTGREST`), Node 20+, Python 3, Chromium.

```bash
cd tests
npm install                      # Playwright
./spust-vse.sh                   # reset + stack + bezpečnost + E2E
# nebo po částech:
./reset.sh && ./stack.sh         # web na http://localhost:8801/index.html
./db/bezpecnost.sh
node e2e/spust.js superadmin     # jen vybrané E2E
./stack.sh stop
```

Vlastní instance (např. pro souběžné agenty): `DB=skolka_agent1 PGRST_PORT=3201 PROXY_PORT=3202 WEB_PORT=8811 ./reset.sh && … ./stack.sh`.

Ruční zkoušení v prohlížeči: po `./stack.sh` otevřete web a v konzoli prohlížeče
nebo přes rozšíření nastavte `config.js` na `http://localhost:3102` — testy to dělají
automaticky (podvrhnou `config.js`).

## Testovací režim v Supabase (volitelně)

Pro testy proti skutečnému Supabase použijte **samostatný testovací projekt**
(ne ostrý): spusťte `supabase/setup.sql`, založte účty z tabulky výše
(Authentication → Add user, Auto Confirm) a spusťte `supabase/testovaci-data.sql`.
Opakované spuštění vrátí testovací školky do výchozího stavu.
