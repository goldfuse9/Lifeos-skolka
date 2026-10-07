# Školka — tablet pro učitelky a ředitelna

Prototyp aplikace pro mateřskou školu: **tablet pro třídu** (do 30 dětí,
na šířku) a **ředitelna** na počítači (kartotéka, učitelé, třídy, matrika).
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
| **Úraz** | místo na těle (+ strana), co se stalo, ošetření, kde, svědek; dostane číslo v knize úrazů, zapíše se, kdo zapisuje a kdy |
| **Poznámka** | rychlé volby (spal, jedl…) + vlastní text |
| **Třídy** (klepnout na nadpis) | tři třídy; přepnout, **sloučit** dnes (hned / od 12, 14, 15 h) a zase rozdělit; **přesunout děti** do jiné třídy jen na dnes nebo natrvalo — děti z jiné třídy mají tečku v barvě třídy |
| **Fotky** | alba zakládají učitelky (název + pro koho: třída / celá školka); fotky z tabletu (fotoaparát i galerie), prohlížení, mazání; rodiče album uvidí až po „Zveřejnit rodičům“; upozornění na děti bez souhlasu s focením |
| **Akce** | výlety, divadla, besídky pro třídu nebo celou školku; nová akce = název, den, čas, s sebou, cena; přehled kdo přijde / nepřijde / neodpověděl, připomenutí |
| **Třídní kniha** | denní zápis: téma (předvyplní se včerejší), co jsme dělali, poučení o bezpečnosti; docházka se zapíše sama; předchozí dny vpravo |
| **Schůzky** | třídní schůzka (den, čas, kde, program) s odpověďmi rodičů; **konzultační hodiny** jako časy po 10–20 min, rezervace rodičů, blokování času; při změně rozpisu rezervace zůstávají |

Docházka, Třídní kniha, Fotky, Akce a Schůzky jsou záložky v hlavičce.
V docházce mají děti s povinným předškolním vzděláváním štítek **PPV**;
když nedorazí bez omluvenky, dlaždice zčervená. Každý zápis se
okamžitě promítne do karty nahoře, na dlaždici dítěte a do jeho dne —
proto je všechno jedna deska se sdíleným stavem.

Fotky nahrané v prototypu zůstávají jen v paměti tabletu; po zavření
aplikace zmizí (stejně jako ostatní ukázková data).

## Ředitelna (`#reditel`)

Deska `Reditel.dc.html` pro počítač ředitelky (1440×900). Odkaz na ni
stačí otevřít jako `index.html#reditel`.

| Část | Co v ní je |
| --- | --- |
| **Přehled** | dnes ve školce, počet dětí s PPV, chyby v matrice, obsazenost; „Vyžaduje pozornost“ (chyby matriky, záznam o úrazu se lhůtou, neomluvená absence u PPV, chybějící souhlas s focením a doklad o očkování, třída s jednou učitelkou) |
| **Děti** | kartotéka podle školní matriky: hledání, filtr tříd a PPV, „jen s chybějícími údaji“; karta dítěte, ve které jsou chybějící údaje rovnou pole k vyplnění. Nové dítě = jméno, příjmení, rodné číslo (datum narození a pohlaví se z něj spočítají, kontroluje se kontrolní číslice), nástup a třída — zbytek se doplní v kartě |
| **Učitelé** | přidat (jméno, e-mail, role, třídy → pozvánka), přiřadit ke třídám klepnutím |
| **Třídy** | kapacita, počet dětí s PPV, věk, celodenní/polodenní provoz, přiřazení učitelek; upozornění na překročenou kapacitu nebo chybějící druhou učitelku |
| **Matrika MŠMT** | sběr k 30. 9. / 31. 3., lhůty, kontrola před odevzdáním (s tlačítkem „Doplnit“), údaje školy (IZO, RED_IZO, část, název, doba provozu, rozlišení); export **XML** `M{IZO}_{část}.xml` (+ `a` pro SVP, `b` pro podpůrná opatření na podzim) s náhledem a stažením |
| **Kniha úrazů** | všechny úrazy z tabletů s pořadovým číslem; u úrazu s absencí 2 a více dní lhůta pro záznam pro ČŠI a pojišťovnu (do 5. dne dalšího měsíce) |

## Soulad s MŠMT

Co prototyp pokrývá podle školského zákona (§ 28) a prováděcích vyhlášek:

- **Školní matrika** — údaje o dětech podle vyhl. 364/2005 Sb. (ve znění
  388/2022 Sb.): rodné číslo nebo náhradní kód u cizinců, pohlaví, datum
  narození, státní občanství, obec trvalého pobytu, spádovost, třída, druh
  provozu, zahájení vzdělávání, způsob plnění PPV, odklad, znalost češtiny,
  SVP a podpůrná opatření, omluvená/neomluvená absence.
- **Předávání individuálních údajů** — od 2025/26 i za mateřské školy; k 30. 9.
  (odevzdat do 15. 10.) a k 31. 3.; nahrává se na matrika.msmt.cz. Jména
  dětí se nepředávají.
- **Kniha úrazů** — podle vyhl. 64/2005 Sb.: pořadové číslo, dítě, co se
  stalo, kde a kdy, ošetření, svědek, kdo zapsal; záznam o úrazu při absenci
  2 a více dní.
- **Třídní kniha** — denní zápis s poučením o bezpečnosti a docházkou.
- **Povinné předškolní vzdělávání** — PPV se počítá samo (5 let do 31. 8.),
  absence musí být omluvená.

**Pozor:** názvy prvků v XML jsou zatím **náhled**. Oficiální popis struktury
souborů pro MŠ se nepodařilo stáhnout, takže pojmenování vychází z
dostupných popisů a nápovědy. Před ostrým odevzdáním je potřeba soubor
nahrát na testovací server **profa.msmt.cz** a pojmenování i číselníky
(RAZM, RAKO, RASM…) upravit podle jeho chybového protokolu.

## Jak to funguje

```
index.html        skořápka, roztáhne desku na displej tabletu
dc.js             mini-runtime pro .dc.html (převzatý z LifeOS beze změny)
shell.js          spustí desku podle #trida / #reditel
Trida.dc.html     třída — deska z plátna (Main.dc.html)
Reditel.dc.html   ředitelna — deska z plátna (Reditel.dc.html)
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
