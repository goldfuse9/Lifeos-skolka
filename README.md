# Školka — tablet pro učitelky

Prototyp aplikace pro třídu mateřské školy (do 30 dětí) na tablet na šířku.
Sesterský projekt [LifeOS](https://github.com/goldfuse9/lifeos): stejný
runtime, stejný vzhled, záměrně **v samostatném repozitáři**, aby se školka
a rodinná aplikace nemíchaly.

Offline, žádný server, žádný cloud. Data jsou ukázková a drží se v paměti
tabletu — po zavření aplikace se vrátí do výchozího stavu.

## Co umí

| Část | Co v ní je |
| --- | --- |
| Přehled třídy | 28 dětí jako dlaždice s jejich **značkou** (Oliver = sněhulák s červeným hrncem); štítek jen když něco znamená |
| Karta **Zdraví** | děti s teplotou od 37,5 °C nebo zapsanými potížemi — klepnutím na jméno se dítě vybere |
| Karta **Oběd** | dnešní menu s alergeny proti alergiím **přítomných** dětí; kdo nemá alergen, je v pořádku a v kartě není |
| Karta **Vyzvedává jinak** | děti, za které dnes přijde někdo jiný než obvykle (ohlášeno rodiči) |
| Karta dítěte | alergie, oběd (náhrada / v pořádku), kdo vyzvedává, dnešní záznamy, rychlé zápisy |
| **Docházka** | celá třída; klepnutí zapíše příchod, další odchod (s tím, kdo vyzvedává), omluvenky od rodičů, tlačítko Vrátit |
| **Teplota** | zapisovatelná hodnota (pole + −/+ 0,1 + rychlé volby), kde měřeno, od 38 °C se samo předvybere „Musí přijet“ |
| **Není mu dobře** | stejné tváře a odrážky jako zápis příznaků v LifeOS (+ zvracení, průjem, bolest ucha, vyrážka); u „Teplota“ se objeví pole na hodnotu; u dušnosti upozornění na 155 |
| **Úraz** | místo na těle (+ strana), co se stalo, ošetření, kde; ukládá se i do knihy úrazů |
| **Poznámka** | rychlé volby (spal, jedl…) + vlastní text |
| **Třídy** (klepnout na nadpis) | tři třídy; přepnout, **sloučit** dnes (hned / od 12, 14, 15 h) a zase rozdělit; **přesunout děti** do jiné třídy jen na dnes nebo natrvalo — děti z jiné třídy mají tečku v barvě třídy |
| **Fotky** | alba zakládají učitelky (název + pro koho: třída / celá školka); fotky z tabletu (fotoaparát i galerie), prohlížení, mazání; rodiče album uvidí až po „Zveřejnit rodičům“; upozornění na děti bez souhlasu s focením |
| **Akce** | výlety, divadla, besídky pro třídu nebo celou školku; nová akce = název, den, čas, s sebou, cena; přehled kdo přijde / nepřijde / neodpověděl, připomenutí |
| **Schůzky** | třídní schůzka (den, čas, kde, program) s odpověďmi rodičů; **konzultační hodiny** jako časy po 10–20 min, rezervace rodičů, blokování času; při změně rozpisu rezervace zůstávají |

Docházka, Fotky, Akce a Schůzky jsou záložky v hlavičce. Každý zápis se
okamžitě promítne do karty nahoře, na dlaždici dítěte a do jeho dne —
proto je všechno jedna deska se sdíleným stavem.

Fotky nahrané v prototypu zůstávají jen v paměti tabletu; po zavření
aplikace zmizí (stejně jako ostatní ukázková data).

## Jak to funguje

```
index.html        skořápka, roztáhne desku na displej tabletu
dc.js             mini-runtime pro .dc.html (převzatý z LifeOS beze změny)
shell.js          spustí desku, připraveno na další desky
Trida.dc.html     třída — deska z plátna „Školka — hlavní stránka třídy“
sw.js             offline
```

Deska je nakreslená na 1194×834 (iPad na šířku); `index.html` ji roztáhne
na celý displej (od šířky 1024 px).

### Aktualizace desky z plátna

Stáhnout `Main.dc.html` z plátna, uložit jako `Trida.dc.html`, **zvednout
`VERZE` v `sw.js`** a nahrát.

## Jak to dostat do tabletu

1. **Settings → Pages → Deploy from a branch**, větev `main`, složka `/ (root)`.
2. Na iPadu otevřít vzniklou adresu v Safari → **Sdílet → Přidat na plochu**.

Lokálně stačí `python3 -m http.server` v téhle složce a otevřít
`http://localhost:8000`.

## Co to (zatím) není

Žádné skutečné odesílání rodičům, žádné propojení s LifeOS, žádné účty.
Napojení na rodiče — co školka vidí (alergie, pověřené osoby) a co rodičům
posílá (teplota, potíže, úraz) — patří do fáze 2 LifeOS.
