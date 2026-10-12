# Finanční modul — školkovné a stravné (server)

Python balíček `finance`: předpisy, konto dítěte v podvojné knize, QR platby,
import výpisů `.gpc` a párování plateb podle variabilního symbolu. Databáze je
`supabase/schema.sql` (PostgreSQL).

## Pravidla pro peníze

- Peníze jsou **vždy `Decimal`** v Pythonu a **`NUMERIC(10,2)`** v databázi.
  `penize.kc()` odmítne `float` (vyhodí `TypeError`), zaokrouhluje na haléře
  `ROUND_HALF_UP`. V JSON jsou částky textem (`"1908.00"`).
- Každé dítě má **konto** (účet `dite:<id>`). Každý pohyb je podvojný zápis
  v `ucetni_pohyby` (MD / Dal), tabulka se dá **jen doplňovat** (trigger zakáže
  UPDATE/DELETE), saldo v `konta` drží trigger.
  - předpis: MD `dite:<id>` / Dal `vynosy:skolkovne` nebo `vynosy:stravne`
  - platba: MD `banka` / Dal `dite:<id>`
- Saldo kladné = přeplatek (kredit), záporné = dluh. Úhrady se rozpouštějí do
  předpisů od nejstaršího (FIFO), stav předpisu jde vždy přepočítat z konta.

## Moduly

| Soubor | Co dělá |
| --- | --- |
| `penize.py` | `kc()`, převody na haléře a zpět, formát „12 345,50 Kč“ |
| `model.py` | datové třídy: `Nastaveni`, `Dite`, `DochazkaDen`, `Predpis`, `Platba`, `Pohyb`… |
| `predpisy.py` | výpočet měsíčního předpisu: školkovné (0 u `osvobozen_od_skolkovneho` — PPV, odklad), stravné podle docházky a věkové kategorie 3–6 / 7+ (věk k 31. 8. školního roku); den omluvený před uzávěrkou se nepočítá |
| `vs.py` | variabilní symboly: kontrola (jen číslice, max 10, jedinečné ve školce), přidělení dalšího podle schématu |
| `spayd.py` | QR platba (SPAYD): `ACC` IBAN školky, `AM` předpis minus přeplatek, `X-VS`, `MSG`; převod českého čísla účtu na IBAN s kontrolou |
| `gpc.py` | parser výpisu ABO/GPC: hlavička `074`, transakce `075`, částky v haléřích, VS, protiúčet, datum; kódování UTF-8 nebo CP1250 |
| `sluzby.py` | `Finance`: vystavení předpisů (idempotentní, v transakci), párovací engine, ruční spárování, dlužníci, upomínky |
| `zpracovani.py` | výpis → platby → párování (společné pro API i Celery) |
| `uloziste.py`, `uloziste_pg.py` | rozhraní úložiště; paměťové pro testy, PostgreSQL (psycopg 3) pro provoz |
| `api.py` | FastAPI pro hospodářku |
| `ulohy.py` | Celery: předpisy 1. den v měsíci v 6:00, zpracování výpisu na pozadí |

## Párování platby

1. Duplicita (stejný doklad z výpisu) → přeskočí se.
2. Dítě podle VS (bez úvodních nul) nenalezeno → `nesparovane_platby`, hospodářka přiřadí ručně.
3. Částka = dluh → **zaplaceno**; víc → **zaplaceno** a zbytek je kredit na kontě
   (odečte se z dalšího předpisu i z QR); míň → **částečně zaplaceno**.
4. Párují se jen příchozí platby (kód 2); odchozí a storna se přeskočí.

## Variabilní symboly

Nastavení školky (`financni_nastaveni`): `vs_schema`
- `rok_poradi` — rok nástupu + pořadí (`260001`), 
- `prefix_poradi` — vlastní předčíslí + pořadí (`770001`),
- `rucne` — VS zadává hospodářka;

`vs_delka` 6/8/10 číslic. VS dítěte platí po celou docházku a jde změnit
(`PUT /finance/deti/{id}/vs`), duplicita se odmítne.

## API

Přihlášení `Authorization: Bearer <JWT ze Supabase Auth>`; finance smí ředitelka,
zástupkyně a hospodářka.

| | |
| --- | --- |
| `POST /finance/vypisy` | ruční import `.gpc` (max 5 MB) |
| `GET /finance/dluznici?k_datu=` | dlužníci po splatnosti |
| `POST /finance/upominky` | hromadné upomínky (push, má-li rodič aplikaci, jinak e-mail) |
| `GET /finance/nesparovane` | nespárované platby |
| `POST /finance/nesparovane/{id}/sparovat` | ruční přiřazení dítěti |
| `POST /finance/predpisy/{RRRR-MM}/vystavit` | vystavit předpisy za měsíc (opakovaně bezpečné) |
| `GET /finance/deti/{id}/konto` | saldo, předpisy, pohyby |
| `GET /finance/deti/{id}/qr?obdobi=&format=svg\|text` | QR platba |
| `PUT /finance/deti/{id}/vs`, `POST /finance/deti/{id}/vs/pridelit` | variabilní symbol |

## Spuštění

```bash
cd server
pip install -r requirements.txt
DATABASE_URL=postgresql://… SUPABASE_JWT_SECRET=… uvicorn finance.api:app
CELERY_BROKER_URL=redis://… DATABASE_URL=… celery -A finance.ulohy worker -B
```

## Testy

```bash
cd server
python -m pytest -q tests                                   # logika v paměti
TEST_DATABASE_URL="host=… dbname=…" python -m pytest -q tests  # + celý tok nad PostgreSQL a API
```

Databáze pro `test_pg_api.py` musí mít načtené `supabase/schema.sql` (a schéma
`auth` se stubem `auth.users`/`auth.uid()` mimo Supabase).
