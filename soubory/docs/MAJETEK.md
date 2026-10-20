# Majetek a inventarizace

Ředitelna → **Školka → Majetek**. Učitelky na tabletu: menu u jména → **Majetek třídy**,
při inventuře záložka **Inventura**.

## Inventární číslo

`KATEGORIE-ROK-POŘADÍ`, např. `IT-2026-0012`:

- **kategorie** — zkratka 2–4 písmen (IT, NAB, VYB, HRA, KUC, ZAH, TEX, UKL; další
  v *Místnosti a kategorie*). Zkratka se po založení nemění, název ano.
- **rok** — rok pořízení (u importu bez data rok importu),
- **pořadí** — zvlášť pro kategorii a rok, přiděluje ho databáze (dva lidé najednou
  nedostanou stejné číslo).

Číslo se položce už nikdy nemění. Staré číslo z Excelu zůstává jako *Původní číslo*.

## Co stránka umí

| Záložka | |
| --- | --- |
| **Seznam** | filtry podle místnosti, kategorie a stavu, hledání (i podle sériového a původního čísla), výběr pro tisk štítků a hromadný přesun, export CSV pro účetní, hodnota podle kategorií, „Vyžaduje pozornost“ (závady, kontroly do 30 dní, zápůjčky před vrácením, rozdíly z inventury) |
| **Karta položky** | všechny údaje, historie (zařazení, přesuny, zápůjčky, závady, opravy, štítky, inventury), revize a záruka, QR štítek, akce přesunout / zapůjčit / vráceno / závada / do opravy / opraveno / vyřadit, protokol o vyřazení |
| **Nová položka** | i více stejných kusů najednou (každý své číslo), účetní druh předvybraný podle ceny (nad 40 000 Kč DHM, od 1 000 Kč drobný, jinak operativní evidence — hranice podle vaší směrnice upravte v `majLok`/SQL) |
| **Tisk štítků** | arch A4 3×7, 3×8, 4×10, 5×13 nebo vlastní (sloupce, řádky, okraje), začátek od libovolné pozice (načatý arch), zkušební tisk s obrysy; QR obsahuje odkaz `…/index.html#majetek/<číslo>` |
| **Import** | Excel (.xlsx) nebo CSV z jiného systému; sloupce se poznají podle názvů, hodnoty místností a kategorií se přiřadí klepnutím, řádek s počtem kusů se rozdělí, stejné původní číslo se nenaimportuje dvakrát |
| **Inventury** | zahájení k datu s komisí, místnosti s tím, kdo je kontroluje, skenování (tablet třídy, v ředitelně čtečkou nebo napsáním čísla), „Místnost hotová“ = co se nenašlo, chybí; rozdíly: jinde → přesunout / vrátit, chybí → našlo se / ponechat / vyřadit jako manko, bez štítku → založit / zrušit; inventurní soupis k podpisu; uzavřít jde až bez rozdílů |
| **Revize a servis** | kontroly s intervalem (elektrorevize, hasicí přístroje, herní prvky, servis); „Hotovo“ posune další termín |
| **Vyřazené** | s důvodem a protokolem o vyřazení |
| **Místnosti a kategorie** | místnosti napojené na třídy (učitelky té třídy vidí jejich majetek), nepoužívané místnosti se do inventury nezařadí |

## Skenování

- **Tablet s Androidem (Chrome)** — tlačítko *Skenovat kamerou* čte QR přímo (BarcodeDetector).
- **iPad / jiný prohlížeč** — štítek naskenovat fotoaparátem tabletu; odkaz otevře
  aplikaci a při inventuře se položka rovnou zapíše jako nalezená.
- **Počítač** — USB čtečka QR funguje jako klávesnice: kurzor do pole *Štítek*
  v dialogu *Skenovat*, číslo se zapíše samo.
- Vždy jde napsat číslo ze štítku ručně.

## Kdo co smí (hlídá databáze)

| Role | |
| --- | --- |
| ředitelka, zástupkyně | vše, včetně zahájení a uzavření inventury |
| hospodářka | vše kromě zahájení a uzavření inventury |
| učitelka | čte majetek místností svých tříd, hlásí závady, při inventuře skenuje ve svých místnostech |
| kuchařka, rodič, jiná školka | nic |

Tabulky jdou z aplikace jen číst; každá změna jde přes funkci v
`supabase/migrace-2026-10-20-majetek.sql`, která hlídá roli a zapíše historii.
Změny položek jdou i do auditního logu (Archiv).

## Zprovoznění

V Supabase → SQL Editor spusťte `supabase/migrace-2026-10-20-majetek.sql` (po migraci
2026-10-17-banka). Kategorie a místnosti z tříd se založí samy při prvním otevření.

## Testy

```bash
node testy/e2e/spust.js majetek majetek-zkusebni
```
