# Platby z banky samy a QR platba v aplikaci rodiče

```
rodič (LifeOS)                     Supabase                               Fio banka
──────────────                     ────────                               ─────────
moje_platby()  ───────────────►  dluh na kontě, VS, IBAN, řetězec QR
zaplatí QR v bankovní aplikaci ─────────────────────────────────────────►  účet školky
                                 pg_cron každých 15 min
                                   └► Edge Function banka-sync ──────────►  API: pohyby za 30 dní
                                        └► banka_zpracuj()
                                             └► fin_zpracuj_platby()  VS → dítě → konto (FIFO)
                                                  nespárované → ředitelna, ruční přiřazení
```

Párování je stejné jako u ručně nahraného výpisu `.gpc`: dítě se najde podle
variabilního symbolu; když VS chybí, ale rodič ho napsal do zprávy pro příjemce
a sedí na jediné dítě, spáruje se taky. Přeplatek zůstává na kontě a odečte se
z dalšího QR. Tatáž platba stažená z API i nahraná z výpisu se nezapočítá dvakrát.

## Zprovoznění (jednou)

1. **Migrace** — v Supabase → SQL Editor spusťte `supabase/migrace-2026-10-17-banka.sql`.
2. **Edge Function** — z kořene repozitáře:
   ```bash
   supabase functions deploy banka-sync --no-verify-jwt
   supabase secrets set CRON_SECRET=$(openssl rand -hex 32)
   ```
   (`--no-verify-jwt`, protože cron se prokazuje heslem `x-cron-secret`; ruční
   spuštění z ředitelny si funkce ověří sama přes JWT a roli.)
3. **Plánovač** — v `supabase/banka-cron.sql` doplňte ref projektu a stejné
   `CRON_SECRET`, spusťte v SQL Editoru.
4. **Token z banky** — ředitelka ve Fio internetovém bankovnictví:
   Nastavení → API → Přidat nový token, **jen pro čtení**, platnost max. 180 dní.
   Token vloží v ředitelně: Platby → Platby z banky → Napojit.
   Token z aplikace už nikdo nepřečte (tabulka je bez práv pro aplikaci), vidí ho jen server.

**Po 180 dnech token vyprší** — v panelu „Platby z banky“ se objeví chyba
s návodem; ředitelka vytvoří nový a vloží ho přes Upravit. Do té doby lze
platby nahrávat i ručně výpisem `.gpc`.

## Aplikace rodiče (LifeOS)

Rodič zavolá jedinou funkci; vidí jen své děti (RLS):

```js
const { data } = await supabase.rpc('moje_platby');
// [{ dite_id, jmeno, k_uhrade, preplatek, splatnost, po_splatnosti,
//    vs, ucet, iban, prijemce, zprava, qr, predpisy: [{obdobi, castka, uhrazeno, stav, polozky}] }]
```

- `qr` je hotový řetězec QR platby (SPAYD) — stačí ho vykreslit jako QR kód
  (např. `react-native-qrcode-svg`). Je `null`, když není co platit.
- `k_uhrade` je celý dluh na kontě, ne jen poslední měsíc.
- **QR na vlastním telefonu nenaskenujete** — vedle QR dejte:
  „Uložit QR do galerie“ (bankovní aplikace ho načtou z obrázku) a „Zkopírovat“
  u účtu, částky a VS.
- Po zaplacení se stav změní do ~15 minut (po připsání na účet školky);
  aplikace si `moje_platby()` načte znovu při otevření obrazovky.

Ukázka obrazovky v React Native je v `docs/lifeos-platby-ukazka.jsx`.

## Testy

```bash
testy/lokalni/stack.sh            # lokální „Supabase“ (proxy už přeposílá /functions/v1)
testy/lokalni/banka.sh            # napodobené Fio API + banka-sync přes deno
node testy/e2e/spust.js banka     # napojení, stažení, párování, QR rodiče, vypnutí
```

## Jiná banka než Fio

Funkce `fin_zpracuj_platby` a celé párování na bance nezávisí. Pro jinou banku
stačí v `banka-sync` doplnit stahování (např. ČSOB/KB/ČS přes jejich API pro
firmy nebo PSD2 agregátor) a převést pohyby na
`{datum, castka, vs, protiucet, nazev, zprava, doklad}`.
