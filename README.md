# Školka — tablet pro učitelky a ředitelna

Prototyp aplikace pro mateřskou školu: **tablet pro třídu** (do 30 dětí,
na šířku) a **ředitelna** na počítači (kartotéka, učitelé, třídy, matrika).
Sesterský projekt [LifeOS](https://github.com/goldfuse9/lifeos): stejný
runtime, stejný vzhled, záměrně **v samostatném repozitáři**, aby se školka
a rodinná aplikace nemíchaly.

Offline, žádný server, žádný cloud. Data jsou ukázková a drží se v paměti
tabletu — po zavření aplikace se vrátí do výchozího stavu.

## Přihlášení a přístupy

Aplikace začíná přihlášením (**LifeOS | Digitální školka**). Na obrazovce se
vybere, kam se člověk hlásí — **Ředitelna**, **Třída** (tablet) nebo
**Jídelna** — a zadá e-mail a heslo. Registrace tu záměrně není: přístupy
vytváří **jen ředitelka** v Ředitelna → Přístupy. Jeden člověk má jeden
přístup (stejné jméno ani e-mail podruhé neprojde), heslo se vygeneruje
a ukáže jen jednou; dá se vygenerovat nové nebo přístup zablokovat.

| Role | Kam se přihlásí |
| --- | --- |
| Ředitelka | Ředitelna, Jídelna — a jen ona spravuje přístupy |
| Zástupkyně ředitelky | Ředitelna, Třída (svůj tablet) |
| Hospodářka | Ředitelna — přehled, děti, docházka, platby, zprávy, archiv |
| Učitelka, asistent/ka | Třída — tablet své třídy |
| Vedoucí jídelny, kuchařka | Jídelna |

Když se někdo hlásí jinam, než kam jeho přístup vede, přihlášení neprojde
a obrazovka řekne, kam patří. Tablet si pamatuje poslední volbu, takže
učitelka má „Třída“ vybranou předem. Ve zkušebním provozu mají ukázkové
přístupy heslo `skolka`; hesla se ukládají jen jako otisk SHA-256. V ostrém
provozu je nahradí Supabase Auth s rolemi ze `supabase/schema.sql`; stejnou
databázi použije i mobilní aplikace LifeOS pro rodiče (role `rodic`).

### Ostrý provoz: správa LifeOS a pozvánky (`#admin`)

Školky a ředitelky zakládá **jen provozovatel LifeOS (superadmin)** na
adrese `…/index.html#admin`:

- **Přidat školku** (název, IZO, kontakt, tarif) → školka „čeká na aktivaci“.
- **Pozvat ředitelku** (jméno, e-mail) → kód `ABCD-EFGH`, platí 30 dní, jednou.
  Ředitelka v aplikaci zvolí **Mám pozvánku**, zadá ten e-mail, své heslo
  a kód. Tím se školka aktivuje.
- **Stav školky** Aktivní / Čeká / Blokovaná, **předplatné** (tarif, placeno
  do, poznámka), **blokování ředitelky**, rušení pozvánek.
- Superadmin vidí jen počty (děti, třídy, zaměstnanci) — údaje dětí ne.

Ředitelka pak v Ředitelna → **Přístupy** zve zaměstnance (učitelka se třídou,
zástupkyně, hospodářka, kuchařka) stejným kódem a blokuje jejich účty.
Heslo zná jen sám pracovník. Všechno hlídá databáze
(`supabase/migrace-2026-10-13c-superadmin.sql`): blokovaná školka nebo účet
nedostane z žádné tabulky ani řádek, ředitelka vidí jen svou školku.

Nastavení: spusťte migraci v Supabase → SQL Editor, v Authentication → Users
založte svůj účet (Add user, e-mail + heslo, Auto Confirm) a na konci
migrace odkomentujte řádek `insert into superadmini …` se svým e-mailem.

## Co umí

| Část | Co v ní je |
| --- | --- |
| Přehled třídy | 28 dětí jako dlaždice s jejich **značkou** (Oliver = sněhulák s červeným hrncem); štítek jen když něco znamená |
| Karta **Zdraví** | děti s teplotou od 37,5 °C nebo zapsanými potížemi — klepnutím na jméno se dítě vybere |
| Karta **Oběd** | dnešní menu s alergeny proti alergiím **přítomných** dětí; kdo nemá alergen, je v pořádku a v kartě není |
| Karta **Vyzvedává jinak** | děti, za které dnes přijde někdo jiný než obvykle (ohlášeno rodiči) |
| Karta dítěte | alergie, oběd (náhrada / v pořádku), kdo vyzvedává, dnešní záznamy, rychlé zápisy |
| **Docházka** | celá třída; klepnutí zapíše příchod, další odchod — vždy až po potvrzení v okénku (s tím, kdo vyzvedává), omluvenky od rodičů, tlačítko Vrátit |
| **Teplota** | zapisovatelná hodnota (pole + −/+ 0,1 + rychlé volby), kde měřeno, od 38 °C se samo předvybere „Musí přijet“ |
| **Není mu dobře** | stejné tváře a odrážky jako zápis příznaků v LifeOS (+ zvracení, průjem, bolest ucha, vyrážka); u „Teplota“ se objeví pole na hodnotu; u dušnosti upozornění na 155 |
| **Úraz** | místo na těle (+ strana), co se stalo, ošetření, kde, svědek, komentář; dostane číslo v knize úrazů, zapíše se, kdo zapisuje a kdy |
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

Deska `Reditel.dc.html` pro počítač ředitelky a hospodářky (1440×900),
otevírá se jako `index.html#reditel`. Vlevo dole se přepíná uživatel —
**ředitelka** vidí vše, **hospodářka** jen přehled, děti (bez úprav),
docházku, platby, zprávy a archiv.

| Část | Co v ní je |
| --- | --- |
| **Přehled** | dnes ve školce (z tabletů), PPV, chyby v matrice, obsazenost; „Vyžaduje pozornost“: chybějící učitelka bez zástupu, matrika, záznam o úrazu se lhůtou, neomluvená absence u PPV (s dalším krokem), končící doporučení ŠPZ, vyhodnocení PLPP, ověření individuálního vzdělávání, nezaplacené platby; u tříd i to, jestli je dnes zapsaná třídní kniha |
| **Děti** | kartotéka podle školní matriky; karta dítěte: osobní údaje, vzdělávání, **dva zákonní zástupci, doručovací adresa, pověřené osoby k vyzvedávání** (se zmocněním), **podpůrná opatření** (stupeň, doporučení ŠPZ s platností, IVP, asistent, PLPP), **ověření při individuálním vzdělávání**, **neomluvená absence** (výzva rodičům → oznámení OSPOD), **souhlasy GDPR** s datem, **ukončení docházky** (ZŠ, přestup, na žádost, § 35 — u PPV zablokováno); chybějící údaje jsou rovnou pole, „Upravit“ odemkne všechna |
| **Zápis** | žádosti pod registračními čísly, pořadí podle kritérií (PPV ze spádu → spád od nejstaršího → sourozenec → ostatní), volná místa po odchodu předškoláků, rozhodnutí (klepnutím jde změnit), zveřejnění seznamu, odeslání rozhodnutí, převod přijatých do kartotéky s nástupem 1. 9. |
| **Docházka** | měsíční přehled po třídách: přítomno, omluveno, neomluveno, obědy; dnešek z tabletů; neomluvená absence u PPV |
| **Platby** | měsíční předpisy (školkovné, u PPV a odkladu 0; stravné podle docházky a věku 3–6 / 7+, včas omluvený oběd se nepočítá), **konto dítěte** s přeplatky, **QR platba** (SPAYD), **načtení výpisu z banky `.gpc`** a párování podle VS (přesně / přeplatek na konto / nedoplatek / nespárováno → ruční přiřazení), dlužníci po splatnosti, hromadné upomínky, export pro účetnictví; sazby, účet, uzávěrka omluvenek a **pravidla variabilních symbolů** v Nastavení. Částky se počítají v haléřích, nikdy v desetinných číslech |
| **Zprávy rodičům** | komu (celá školka, třída, předškoláci, nezaplacené platby), předmět, text; odeslané s počtem přečtení |
| **Učitelé** | pozvání, třídy, **úvazek** (s přímou pedagogickou prací), **dnes chybí → kdo zastoupí** |
| **Třídy** | kapacita, PPV, věk, provoz, učitelky; upozornění |
| **Porady** | zápisy z pedagogických rad a provozních porad (datum, program, usnesení; přítomní se doplní sami) |
| **Matrika MŠMT** | sběr k 30. 9. / 31. 3., kontrola, údaje školy, export XML (`M{IZO}_{část}.xml`, `a` SVP, `b` podpůrná opatření) |
| **Kniha úrazů** | úrazy z tabletů s číslem, svědkem a tím, kdo zapsal; záznam pro ČŠI a pojišťovnu se lhůtou |
| **Webové stránky** | web školky se skládá z údajů v ředitelně: kontakty, třídy a učitelky, den ve školce, zápis (kritéria, volná místa, po zveřejnění výsledky pod reg. čísly), školné a stravné, aktuality ze zpráv celé školce, povinné informace podle zákona 106/1999 Sb., dokumenty, prohlášení o přístupnosti; kontrola povinných údajů, náhled počítač/mobil, stažení jako `index.html` (ukázka ve složce `web/`) |
| **Archiv** | spisový a skartační plán (lhůty jsou ukázkové a dají se přepsat) a **historie změn** — kdo co kdy změnil |

### Nastavení, profily, dokumenty (zkušební provoz)

- **Menu** je po skupinách: Děti · Školka · Rodiče a veřejnost · Peníze · Povinná evidence · Nastavení.
- **Nastavení školky** — všechny údaje na jednom místě (škola, kontakty, provoz, platby); matrika, web, dokumenty i platby si je berou odsud.
- **Profily** učitelů, ředitelky a hospodářky: jméno, e-mail, telefon, role, fotka; bez fotky kreslená postava (vlasy, barva, tričko). Fotka se ukáže i na tabletu třídy.
- **Kniha úrazů**: detail úrazu s počtem dní nepřítomnosti, **záznam o úrazu pro ČŠI a pojišťovnu** (předvyplněný, ke stažení), **poslat rodičům** jen když mají mobilní aplikaci — povoluje se v kartě dítěte.
- **Dokumenty**: předvyplněné šablony povinných dokumentů (školní řád, ŠVP, kritéria přijímání, úplata, řád jídelny, provozní řád, BOZP, výroční zprávy, GDPR, spisový řád) — upravit, schválit, zveřejnit na webu, stáhnout.
- **Vysvětlivky** zkratek (PPV, PO, ŠPZ, PLPP, IVP, AP, OSPOD…) v kartotéce.
- **Zkušební provoz**: všechno funguje, ale nic neodchází ven; změny zůstávají v tomto prohlížeči (localStorage), „Vrátit ukázková data“ v Nastavení je smaže.

### Propojení s tablety

Tablet třídy a ředitelna v jedné aplikaci sdílejí stav: úraz zapsaný na
tabletu se objeví v knize úrazů, docházka tříd v přehledu a docházce,
zápis do třídní knihy u třídy na přehledu. Mezi zařízeními to bez serveru
nejde — k tomu je `supabase/schema.sql`.

### Server (`supabase/schema.sql`)

Návrh databáze pro ostrý provoz: tabulky pro všechno výše, přístupová
práva podle role (ředitelka / učitelka / hospodářka / rodič) přes RLS,
učitelky a hospodářka nevidí rodná čísla, každá změna osobních údajů jde
do `audit_log`. Ověřeno na PostgreSQL 16.

### Majetek a inventarizace

Ředitelna → Školka → **Majetek**: evidence s čísly `KATEGORIE-ROK-POŘADÍ`
(IT-2026-0012), filtry podle tříd, místností, kategorií a stavu, karta položky
s historií, QR štítky na arch A4 (počet štítků na archu volitelný, i načatý
arch), import ze staré evidence (Excel/CSV), revize a servis, vyřazení
s protokolem a **inventura** — učitelky skenují na tabletu své třídy, ostatní
místnosti se skenují v ředitelně, rozdíly se vyřeší a vytiskne se inventurní
soupis. Podrobnosti v [`docs/MAJETEK.md`](docs/MAJETEK.md).

### Platby z banky a QR pro rodiče

Platby se z účtu školky (Fio API) stahují a párují **samy každých 15 minut**
(Edge Function `supabase/functions/banka-sync` + pg_cron); ředitelka napojí banku
tokenem v Platby → Platby z banky, hospodářka může stáhnout hned. Rodič v LifeOS
zavolá `moje_platby()` a dostane částku k úhradě, VS a hotový řetězec QR platby.
Zprovoznění v [`docs/PLATBY-Z-BANKY.md`](docs/PLATBY-Z-BANKY.md).

### Finanční modul (`server/`)

Školkovné a stravné pro ostrý provoz: Python (`Decimal`) + PostgreSQL
(`NUMERIC(10,2)`), podvojná kniha jen pro doplňování, parser výpisů `.gpc`,
párovací engine, QR platby, API pro hospodářku (FastAPI) a měsíční úloha
(Celery). Podrobnosti v [`server/README.md`](server/README.md).

## Školní jídelna (`#jidelna`)

Počítač v kuchyni. Přihlášená kuchařka je vlevo dole (⇄ přepne na jinou).

- **Dnes v kuchyni** — co se vaří, počty porcí po třídách podle omluv, náhrady pro děti s dietou, výdejní list k tisku.
- **Jídelníček** — týden po dnech (přesnídávka, polévka, oběd, svačina, pitný režim). Jídlo se vybírá z databáze a alergeny se načtou samy ze surovin. Kontrola pestrosti týdne, „Doplnit z minulého týdne“, tisk na nástěnku, zveřejnění rodičům.
- **Jídla a suroviny** — každé jídlo má suroviny, alergeny (1–14 podle EU) se z nich počítají; u jídla je rovnou náhrada pro děti s dietou.
- **Diety a náhrady** — děti s alergií (bere je z kartotéky v ředitelně, kde se alergie zapisuje) a náhrady na celý týden; upozorní, když chybí doporučení lékaře.
- **Kuchařky** — personál jídelny jako u učitelů: pozice, úvazek, zdravotní průkaz, školení hygieny.

Zveřejněný jídelníček se propíše do tabletu učitelky (karta Oběd). Ředitelna má jídelnu v menu (Školka → Školní jídelna).

### Import dětí z Excelu

V Kartotéce dětí tlačítko **Import z Excelu** načte tabulku (.xlsx nebo CSV)
přímo v prohlížeči. Sloupce se poznají podle názvů (Jméno, Příjmení nebo
Jméno a příjmení, Rodné číslo, Datum narození, Třída, Zákonný zástupce,
Telefon, E-mail, Adresa/Trvalý pobyt, Obec, Pojišťovna, Alergie, Nástup).
Před importem je náhled: kdo je nový, kdo už v kartotéce je (podle RČ nebo
jména a data narození — přeskočí se) a komu co chybí. Dětem bez třídy se
třída vybere jedním klepnutím. Vzorová tabulka se dá stáhnout.

### Editor dokumentů

Dokumenty v ředitelně se upravují jako v textovém editoru: styl (text, nadpis,
podnadpis), velikost písma, tučně, kurzíva, podtržení, zarovnání, odrážky
a číslování, zpět/znovu. Pro celý dokument se volí písmo (patkové/bezpatkové),
základní velikost a řádkování. **Náhled** ukáže dokument rozdělený na listy A4
i s hlavičkou školky — přesně tak, jak se vytiskne nebo uloží do PDF.

## Soulad s MŠMT

- **Školní matrika** (vyhl. 364/2005 Sb. ve znění 388/2022 Sb.) — všechny
  údaje o dětech včetně podpůrných opatření, znalosti češtiny a absence;
  předávání k 30. 9. (do 15. 10.) a k 31. 3. na matrika.msmt.cz.
- **Přijímání dětí** (§ 34 a 34a školského zákona) — zápis 2.–16. 5.,
  přednost dětí s PPV ze spádového obvodu, registrační čísla, rozhodnutí.
- **Ukončení vzdělávání** (§ 35) — u dětí s PPV nejde.
- **Individuální vzdělávání** (§ 34b) — ověření očekávaných výstupů
  v listopadu, náhradní termín v prosinci.
- **Podpůrná opatření** (vyhl. 27/2016 Sb.) — stupně, doporučení ŠPZ,
  IVP, PLPP.
- **Úplata** (vyhl. 14/2005 Sb., § 123) — u PPV bezúplatně; **stravné**
  (vyhl. 107/2005 Sb.) podle věkové skupiny.
- **Kniha úrazů** (vyhl. 64/2005 Sb.), **třídní kniha** a **záznamy
  z pedagogických rad** (§ 28).
- **GDPR** — souhlasy s datem, role a historie změn.

**Pozor:** názvy prvků v XML jsou zatím **náhled** — oficiální popis
struktury souborů pro MŠ se nepodařilo stáhnout. Před ostrým odevzdáním
nahrát na testovací **profa.msmt.cz** a upravit podle chybového protokolu.
Lhůty ve skartačním plánu jsou ukázkové.

## Jak to funguje

```
index.html        skořápka, roztáhne desku na displej tabletu
dc.js             mini-runtime pro .dc.html (převzatý z LifeOS beze změny)
shell.js          spustí desku podle #trida / #reditel
Trida.dc.html     třída — deska z plátna (Main.dc.html)
Reditel.dc.html   ředitelna — deska z plátna (Reditel.dc.html)
sw.js             offline
web/index.html    ukázka vygenerovaného webu školky
supabase/         návrh databáze s právy podle rolí pro ostrý provoz
```

Třída je nakreslená na 1194×834 (iPad na šířku), ředitelna na 1440×900.
Větší okno je roztáhne, menší okno (třeba notebook) je celé zmenší, aby se
vešly bez posouvání; pod 60 % se dál nezmenšují a okno se dá posunout.

### Aktualizace desky z plátna

Stáhnout `Main.dc.html` z plátna, uložit jako `Trida.dc.html`, **zvednout
`VERZE` v `sw.js`** a nahrát.

## Jak to dostat do tabletu

1. **Settings → Pages → Deploy from a branch**, větev `main`, složka `/ (root)`.
2. Na iPadu otevřít vzniklou adresu v Safari → **Sdílet → Přidat na plochu**.

Lokálně stačí `python3 -m http.server` v téhle složce a otevřít
`http://localhost:8000`.

## Co to (zatím) není

Data jsou ukázková a drží se v paměti — nic se skutečně neodesílá (rodičům,
do banky, na MŠMT), přihlášení je zatím jen přepínač ředitelka / hospodářka.
Na ostrý provoz je potřeba server podle `supabase/schema.sql` a přihlášení
přes něj.
Napojení na rodiče — co školka vidí (alergie, pověřené osoby) a co rodičům
posílá (teplota, potíže, úraz) — patří do fáze 2 LifeOS.
