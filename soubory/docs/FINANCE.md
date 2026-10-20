# Pokročilé finance a export pro účetní

Ředitelna → **Platby**. Databáze: `supabase/migrace-2026-10-21-finance.sql`
(v `setup.sql` jako doplněk 21. 10. 2026). Bez migrace ředitelna ukazuje jen
dosavadní záložku Předpisy.

## Záložky

| Záložka | Co dělá |
| --- | --- |
| **Předpisy** | měsíční předpis pro každé dítě: školkovné (u PPV, odkladu a prominutí 0, u slevy snížené) + záloha na stravné. Na další měsíc jde vystavit od 20. dne. Konto dítěte: QR platba, seznam předpisů se **Storno**, **Přijmout hotově**, **Vrátit přeplatek**, **Sleva / prominutí** |
| **Další platby** | výlety, divadla, pomůcky, kroužky, fond rodičů — pro celou školku, třídu, děti přihlášené na akci (odpověď „ano“ v aplikaci) nebo vybrané děti; přehled kdo zaplatil, storno jednotlivě |
| **Vyúčtování stravného** | vyberou se skončené měsíce, náhled zálohy × skutečně odebrané obědy (přítomen + omluveno po uzávěrce) × cena podle věku; doplatek = nový předpis se splatností 14 dní, přeplatek = dobropis na konto. Vyúčtované dítě a období se podruhé nevyúčtuje |
| **Přeplatky a vratky** | děti s přeplatkem, vrácení převodem (účet z poslední platby rodiče) nebo hotově; **hromadný příkaz pro banku** (ABO/KPC) a „Označit jako odeslané“ |
| **Pokladna** | příjmové (PPD) a výdajové (VPD) pokladní doklady s číselnou řadou, tisk dokladu, pokladní kniha za měsíc; výdej nad zůstatek nejde |
| **Slevy a prominutí** | snížení o % / o částku nebo prominutí školkovného s platností a číslem rozhodnutí (jen ředitelka) |
| **Uzávěrka a export** | export ZIP za měsíc, uzávěrka měsíců postupně, znovuotevření posledního uzavřeného (jen ředitelka), předkontace |

**Nastavení** (Předpisy → Sazby a účet → *Zálohy, pokladna a předkontace*): režim
stravného (zálohy předem + vyúčtování, nebo podle skutečnosti po skončení měsíce),
pevná měsíční záloha pro 3–6 a 7+ let (prázdné = cena oběda × pracovní dny měsíce),
počáteční stav pokladny, předkontace.

Dosavadní školky po migraci zůstávají u stravného podle skutečnosti, dokud ředitelka
režim nepřepne; nové školky začínají zálohami. Změna platí pro předpisy vystavené odteď.

## Účetní pravidla

- **Nic se nemaže.** Účetní kniha (`ucetni_pohyby`) je jen pro doplňování; storno
  předpisu je protizápis (`druh = storno`), předpis zůstane se značkou storna a důvodem.
- Každý pohyb má **účetní období** (`obdobi_uctu`): měsíc data, nebo první
  neuzavřený měsíc po něm. Pozdě načtená platba za uzavřený měsíc tak jde do
  dalšího měsíce a export uzavřeného měsíce se už nezmění.
- **Uzávěrka** jde jen u skončeného měsíce a postupně (bez děr); do uzavřeného
  měsíce nejde vystavit pokladní doklad ani nic jiného s jeho datem.
- Úhrady se přiřazují k nejstarší splatnosti (FIFO); vrácený přeplatek kredit snižuje.
- Číselné řady: `PR` předpisy, `VY` vyúčtování, `PPD`/`VPD` pokladna, `VR` vratky —
  `PR-2026-00001`, číslo přidělí databáze.

## Export pro účetní (ZIP)

CSV s oddělovačem `;`, kódování UTF-8 (s BOM, Excel ho otevře rovnou):

| Soubor | Obsah |
| --- | --- |
| `rekapitulace.csv` | obraty MD/Dal podle předkontace a souhrn měsíce (předepsáno, storna, dobropisy, úhrady banka/pokladna, vratky, přeplatky a nedoplatky ke konci měsíce, zůstatek pokladny, stav uzávěrky) |
| `denik.csv` | všechny účetní pohyby měsíce: datum, doklad, druh, popis, MD, Dal, částka, dítě, VS |
| `predpisy.csv` | předpisy vystavené nebo stornované v měsíci s položkami |
| `uhrady.csv` | příchozí platby (banka i pokladna), spárované i nespárované |
| `pokladni-kniha.csv` | pokladní kniha s počátečním a průběžným zůstatkem |
| `vratky.csv` | vrácené přeplatky |
| `vyuctovani-stravneho.csv` | jen když v měsíci proběhlo vyúčtování |
| `saldokonto.csv` | zůstatek každého dítěte na začátku a konci měsíce |
| `CTI-ME.txt` | popis souborů a použitá předkontace |

Výchozí předkontace (účetní si ji přepíše podle svého účtového rozvrhu):

| | |
| --- | --- |
| pohledávky za rodiči | 315 |
| bankovní účet / pokladna | 241 / 261 |
| výnos školkovné / stravné / kroužky / jiné | 602.100 / 602.200 / 602.300 / 602.900 |
| akce, pomůcky, fond (průběžné položky) | 378.100 / 378.200 / 378.300 |
| výdaje z pokladny | 501 |

## Hromadný příkaz pro vratky

Formát ABO (KPC), který přijímá internetové bankovnictví většiny českých bank
(tuzemské platby v Kč, účty ve tvaru `předčíslí-číslo/kód banky`, bez diakritiky).
Účet školky musí být v Nastavení jako `číslo/kód banky`. Po nahrání do banky
označte vratky jako odeslané.

## Kdo co smí (hlídá databáze)

| Role | |
| --- | --- |
| ředitelka, zástupkyně | vše, včetně slev, režimu stravného a znovuotevření uzávěrky |
| hospodářka | předpisy, platby, storno, vyúčtování, pokladna, vratky, uzávěrka, export |
| učitelka, kuchařka | nic z financí |
| rodič | své předpisy (`moje_platby()`), slevy a vratky svého dítěte |

Tabulky jdou z aplikace jen číst, každá změna jde přes funkci v migraci.

## Testy

```bash
psql … -f supabase/migrace-2026-10-21-finance.sql   # nebo testy/reset.sh
testy/bezpecnost.sh skolka_lokal                     # blok „pokročilé finance“
node testy/e2e/spust.js finance finance-zkusebni platby
```
