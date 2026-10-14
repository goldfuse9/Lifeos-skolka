# Audit D — Tablet třídy (Trida.dc.html) v ostrém provozu

Datum: 2026-10-14 · Agent D · Repo: `/home/claude/skolka-audit` (jen čtení, nic neměněno)
Prostředí: vlastní lokální instance `stack.sh skolka_d 3041 3042 8841` (PostgreSQL + PostgREST + sbproxy), DB před každým scénářem obnovena `reset.sh skolka_d`. Realtime je v testu vypnutý.
Skripty a screenshoty: `scratchpad/audit/D/` (`h.js` pomůcky, scénáře `a.js` docházka, `b.js` omluvenky, `c.js` zápisy+úrazy+RLS, `e.js` výpadky+blokace, `f.js` kniha/fotky/akce/schůzky/role/rozměry, `g.js`, `g2.js`, `h2.js`; spouštění `run.sh <skript>`).
Ověřování: Playwright (Chromium, stranka() → config.js na lokální proxy), stav DB přes `sql()`, pohled rodiče a dalších rolí přes `sqlJako()` (RLS platí).

Poznámka k prostředí: DB `skolka_d` při startu obsahovala cizí data (jiné účty s hesly). Přihlášení proto selhávalo, dokud jsem DB neobnovil přes `reset.sh`. Po `reset.sh` je potřeba počkat, až se PostgREST znovu připojí (v `h.js` je čekání a opakované přihlášení).

---

## 1. Inventář funkcí

Režim: **SERVER** = čte/zapisuje Supabase · **UKÁZKA** = natvrdo zadaná ukázková data · **LS** = localStorage prohlížeče · **PAMĚŤ** = jen v paměti stránky, obnovením zmizí.

| Funkce | Režim | Stav | Jak ověřeno |
|---|---|---|---|
| Načtení třídy (děti, alergie, dnešní docházka, vyzvednutí, události) | SERVER | OVĚŘENO | a.js, g.js: tablet ukazuje Emu a Olivera, Tobiáše ani Adama ne; učitelka B vidí jen Adama |
| Příchod jednoho dítěte (Třída → Zapsat příchod, Docházka → dlaždice) | SERVER | OVĚŘENO | a.js: řádek `dochazka` pritomen, čas = místní čas v Praze ±2 min, po obnovení stránky zůstane, rodič Emy ho vidí, rodič Olivera ani rodič ze školky B ne |
| Dvojklik na potvrzení příchodu nebo omluvenky | SERVER | OVĚŘENO | a.js, b.js: v DB jeden řádek, žádná chyba, v deníku jeden „Příchod“ |
| Hromadný příchod | — | CHYBÍ | g.js + výpis tlačítek: žádná volba „všichni/vybrat víc“; každé dítě je potřeba zapsat zvlášť a potvrdit dialog |
| Odchod + kdo vyzvedl | SERVER | OVĚŘENO s výhradou (D7) | a.js: odchod, `vyzvedl` = „rodiče“ nebo ohlášená osoba; rodič ho vidí |
| Ohlášené vyzvednutí od rodiče („Dnes vyzvedává jinak“) | SERVER | OVĚŘENO | a.js: karta i dialog odchodu ukazují „teta Jana“, `vyzvedl`=teta Jana; RLS brání rodiči jiného dítěte i rodiči ze školky B v zápisu |
| Pověřené osoby (`poverene_osoby`) | — | CHYBÍ | a.js, g.js: „babička Marie“ ani rodičem přidaný „dědeček Karel“ se na tabletu nikde neukáže |
| Vrátit (undo) odchodu | SERVER | OVĚŘENO | a.js: `odchod` i `vyzvedl` se vymažou |
| Vrátit příchod dítěte s omluvenkou | SERVER | SELHÁVÁ (D5) | b.js |
| Omluvenky (přehled od dneška dál) | SERVER | OVĚŘENO | b.js: rozsah „dnes – pá“, důvod, oběd odhlášen |
| Potvrzení omluvenky | SERVER | OVĚŘENO | b.js: všechny dny, `omluvu_potvrdil`=Petra Horáková, rodič potvrzení vidí, rodič jiného dítěte omluvenku nevidí, po obnovení „✓ Potvrzeno“ |
| „Přesto přišel“ (dítě s omluvenkou) | SERVER | SELHÁVÁ částečně (D6) | b.js |
| Neomluvená absence (`stav='neomluven'`) | — | CHYBÍ | b.js: tablet ji zapsat neumí; „čekáme“ zůstane do konce dne (u PPV je to přitom povinné) |
| Teplota / Není mu dobře / Poznámka | SERVER | OVĚŘENO | c.js: `udalosti_ditete` (druh, hodnota, text), `zapsal`=uid učitelky, `zapsal_jmeno`, den v Praze; rodič Emy 4 zápisy vidí, rodič Olivera ani rodič ze školky B ne; po obnovení zůstanou (D15) |
| Úraz → rodiči (`udalosti_ditete`) | SERVER | OVĚŘENO | c.js |
| Úraz → kniha úrazů (`urazy`) | SERVER + LS | SELHÁVÁ částečně (D3, D4, D9) | c.js: řádek se uloží (`zapsal`=učitelka); číslo nesedí, při souběhu se úraz ztratí; RLS dovolí podvrhnout `skola_id` i `zapsal` |
| Kniha úrazů v ředitelně | LS + UKÁZKA | SELHÁVÁ (D10) | c.js: ředitelka na jiném zařízení úraz z tabletu nevidí, vidí ukázková data („Kamil Kos, Motýlci“). Přes API (sqlJako) ho ale vidí |
| Karta Oběd / náhrada podle alergií | UKÁZKA (+LS) | SELHÁVÁ (D1) | f.js, g2.js: tablet ukazuje „Rizoto se sýrem“, server má „Rybí filé…“ {4,7}; Oliver s alergií na ryby má „Oběd v pořádku“ |
| Alergie dítěte (zobrazení) | SERVER | OVĚŘENO | g.js: alergie upravená rodičem (`uprav_udaje_rodicem`) je na tabletu |
| Zdravotní omezení (SPZ, IVP, očkování…) | — | CHYBÍ | `deti` má sloupce `spz, ivp, asistent, ockovani`. Tablet je nenačítá (`server.js:209` vybírá jen alergie). Ověřeno čtením kódu a v UI |
| Třídní kniha | LS | SELHÁVÁ (D2) | f.js: `tridni_kniha` 0 řádků; po obnovení stránky je zápis pryč |
| Fotky / alba | PAMĚŤ | SELHÁVÁ (D2) | f.js: `alba` 0 řádků, rodič nic nevidí, po obnovení album zmizí |
| Akce | PAMĚŤ | SELHÁVÁ (D2) | f.js: toast „Pozvánka odeslána 2 rodičům“, `akce` 0 řádků, rodič nic, po obnovení zmizí |
| Schůzky / konzultační hodiny | PAMĚŤ | SELHÁVÁ (D2) | f.js: toast „Pozvánka na schůzku odeslána“, po obnovení „Zatím žádná schůzka“ |
| Přepnutí třídy (víc tříd jednoho účtu) | — | CHYBÍ (D11) | f.js: zástupkyně se 2 třídami vidí jen Berušky |
| Sloučení tříd / přesun dítěte | PAMĚŤ | CHYBÍ (D11) | f.js: v ostrém provozu je k dispozici jen jedna třída, takže není s čím sloučit; `server.js` nezapisuje `trida_dnes` |
| Dítě dočasně v jiné třídě (`dochazka.trida_dnes`) | — | SELHÁVÁ (D11) | f.js: RLS učitelce Sluníček Tobiáše zpřístupní, tablet ho ale neukáže (`nactiTridu` filtruje podle `deti.trida_id`) |
| Zástupkyně s tabletem | SERVER | SELHÁVÁ částečně (D11) | f.js: bez `ucitel_trida` → „Tento přístup do části Třída nevede“; s jednou třídou funguje |
| Třída bez dětí | SERVER | OVĚŘENO | f.js: srozumitelná hláška při přihlášení |
| Zablokovaný účet během práce | SERVER | SELHÁVÁ částečně (D8) | e.js, f.js: zápis se neuloží (RLS) — v pořádku; hlášky jsou ale technické nebo zavádějící |
| Výpadek sítě / zastavená proxy při zápisu | SERVER | SELHÁVÁ částečně (D8) | e.js: hláška „Server není dostupný“ přijde, tablet ale dál ukazuje dítě „ve třídě“, zápis se nezopakuje a je ztracen |
| Otevření tabletu bez serveru | SERVER | OVĚŘENO s výhradou | g.js: „Server není dostupný…“ + „[object Object]“; offline režim není |
| Obnova po návratu do okna (visibilitychange) | SERVER | OVĚŘENO | h2.js: omluvenka od rodiče se objeví |
| Realtime (živé změny od rodiče) | SERVER | NEOVĚŘENO | v testovacím režimu vypnutý (`**/realtime/**` abort) |
| Tablet otevřený přes půlnoc | SERVER | SELHÁVÁ (D12) | h2.js (posun hodin o +1 den) |
| Rozměry 1194×834, 1024×768, 834×1112 | — | OVĚŘENO s výhradou (D16) | f.js: nic nepřetéká ani se neořezává; deska se zmenší zhruba na 0,86 (1024) a 0,7 (834 na výšku) |
| Izolace školek a tříd (RLS) | SERVER | OVĚŘENO s výjimkami (D4, D9) | a/b/c/g.js: rodič jiného dítěte, rodič ze školky B ani učitelka B nevidí data A; učitelka Sluníček nesmí zapsat Tobiášovi |

---

## 2. Nálezy

### D1 — KRITICKÁ — Karta Oběd a varování k alergiím vychází z ukázkového jídelníčku, ne ze serveru
- **Kde:** `Trida.dc.html:1164` (`this.menu = { name: 'Rizoto se sýrem', allergens: ['mléko','lepek'] }`), `Trida.dc.html:1429-1435` (přepíše ho jen `store().jidelna` z localStorage téhož prohlížeče). `server.js` jídelníček pro tablet nenačítá (funkce `jidelnicek_tyden` existuje a učitelka ji podle RLS smí volat).
- **Popis:** Učitelka v ostrém provozu vidí jako dnešní oběd vždy ukázkové „Rizoto se sýrem“ s alergeny mléko a lepek. Podle toho tablet označuje děti „bez mléka“ a ostatním píše „Oběd v pořádku“.
- **Reprodukce:** reset → `uprav_udaje_rodicem(Oliver, 'arašídy, ryby')` → tablet → Oliver. Tablet: „OBĚD · RIZOTO SE SÝREM“, u Olivera „Oběd: v pořádku“. Server (`jidelnicek_tyden` jako učitelka): „Rybí filé, brambory, mrkvový salát {4,7}“.
- **Ověřeno:** f.js, g2.js (screenshot `g2-oliver-ryby.png`).
- **Oprava:** V `nactiTridu` načíst `jidelnicek_tyden(dnes, dnes)` (oběd a svačiny), převést kódy alergenů 1–14 na názvy a stejně převést `deti.alergie`. Ukázkové menu v ostrém provozu nikdy nepoužít. Když jídelníček zveřejněný není, napsat „Jídelníček na dnes není zveřejněný“ a nedávat „v pořádku“. Kontrolovat i přesnídávku a svačinu (dnes obsahuje vejce).

### D2 — VYSOKÁ — Třídní kniha, Fotky, Akce a Schůzky v ostrém provozu nic neukládají, a přesto hlásí odeslání rodičům
- **Kde:** kniha `Trida.dc.html:1924-1931` (jen `store().kniha` → localStorage), navíc `Trida.dc.html:1250` (`this.kniha[SRVT.id] = []` po obnovení zápis z localStorage zahodí). Album `:2062-2067`, akce `:2087-2092`, schůzka `:2109-2113`, konzultace `:2133+` — jen v paměti (`self.albums/events/meetings/konz`).
- **Popis:** Tabulky `tridni_kniha`, `alba`, `akce` v DB jsou a RLS pro učitelku má, tablet do nich ale nezapisuje. Toasty „Pozvánka odeslána 2 rodičům“ a „Pozvánka na schůzku odeslána“ nejsou pravda. Třídní kniha je povinná dokumentace, a ta se ztratí obnovením stránky nebo výměnou tabletu.
- **Reprodukce:** Třídní kniha → téma + činnost → Zapsat → obnovit stránku: téma je prázdné, `select count(*) from tridni_kniha` = 0. Akce → Nová → název + datum → „Poslat pozvánku 2 rodičům“: toast odeslání, `akce` = 0, rodič nic nevidí, po obnovení akce zmizí.
- **Ověřeno:** f.js.
- **Oprava:** Napojit na server (`tridni_kniha` upsert (trida_id, den) se `zapsal=auth.uid()`; `akce`/`alba` insert + Storage pro fotky; pro schůzky a konzultace přidat tabulku). Do té doby v ostrém provozu tyto záložky skrýt nebo označit „zatím nefunguje“ a hlavně neukazovat toast o odeslání.

### D3 — VYSOKÁ — Kniha úrazů: číslo počítá klient, při souběhu se úraz ztratí, tablet ukazuje jiné číslo
- **Kde:** `server.js:246-252` (číslo = max+1 na klientovi, pak insert, při konfliktu se nezkusí znovu), `Trida.dc.html:1758, 1831-1834` (číslo na tabletu je z localStorage `urazNo`, výchozí 3).
- **Popis:** (a) Na čisté školce tablet ukazuje „Kniha úrazů č. 4/2026“, server uloží č. 1. Do deníku dítěte jde „kniha úrazů č. 4“. (b) Když dvě učitelky ukládají úraz současně, druhý insert spadne na `urazy_skola_id_rok_cislo_key` a úraz v zákonné evidenci chybí. Učitelka předtím dostala toast „Odesláno rodičům … · v knize úrazů“, chyba přijde až po něm.
- **Reprodukce:** c.js — tablet Sluníček (Oliver) a tablet Berušek (Tobiáš) uloží úraz zároveň → v `urazy` jsou jen č. 1 a 2 ze 3 úrazů, toast „duplicate key value violates unique constraint…“.
- **Ověřeno:** c.js.
- **Oprava:** Číslo přidělovat na serveru (RPC `zapis_uraz` se zámkem nebo sekvencí na (skola_id, rok), vrátí číslo). Tablet ukáže až číslo vrácené serverem a localStorage `urazNo/urazy` v ostrém provozu nepoužije.

### D4 — VYSOKÁ (bezpečnost) — RLS pro `urazy` nekontroluje `skola_id` ani `zapsal`, takže jde zablokovat číslování cizí školky
- **Kde:** `supabase/setup.sql:366` (`uraz_zapsat … with check (role in (...) and moje_dite(dite_id))`).
- **Popis:** Učitelka školky A vloží úraz svého dítěte se `skola_id` školky B a `zapsal` = učitelka B. Řádek v B není vidět (moje_dite), obsadí ale číslo. Klient v B pak počítá max+1 jen z viditelných řádků a každý další úraz v B končí chybou duplicity. Kniha úrazů školky B je tím trvale zablokovaná. Stejně jde podvrhnout `zapsal` = ředitelka.
- **Reprodukce:** `sqlJako(učitelka A, insert into urazy (skola_id=B, cislo=2, dite_id=Ema, zapsal=učitelka B))` projde. Učitelka B pak `max(cislo)` = 1 a `insert cislo=2` → `duplicate key`.
- **Ověřeno:** c.js + ruční psql jako učitelka B.
- **Oprava:** `with check (… and skola_id = moje_skola() and zapsal = auth.uid() and exists(select 1 from deti where id=dite_id and skola_id=urazy.skola_id))`, `zapsal default auth.uid()`. Nejlépe vkládat jen přes RPC (D3).

### D5 — VYSOKÁ — „Vrátit“ u příchodu dítěte s omluvenkou nechá v DB stav „přítomen“
- **Kde:** `server.js:231` (`if (k.att === 'excused') return null;`), volání z undo `Trida.dc.html:1571-1578`.
- **Popis:** Učitelka omylem klepne na omluvené dítě („přesto přišel“) a dá Vrátit. Tablet ukáže „omluven“, server zůstane `pritomen` s časem příchodu. Rodič vidí, že je dítě ve školce, a docházka i stravné jsou špatně. Po obnovení stránky tablet ukazuje dítě jako přítomné.
- **Reprodukce:** b.js — omluva rodiče → Docházka → Oliver → Zapsat příchod → Vrátit → `dochazka` = `pritomen|…|nemoc`.
- **Ověřeno:** b.js.
- **Oprava:** Undo má obnovit předchozí řádek. Buď si tablet pamatuje původní stav a pošle ho zpět (stav omluven + omluvenka + strava), nebo na to bude RPC `vrat_dochazku(dite, den, puvodni_stav)`.

### D6 — STŘEDNÍ — „Přesto přišel“ nechá oběd odhlášený a omluvenku potvrzenou
- **Kde:** `server.js:232-235` (upsert mění jen stav, příchod, odchod a vyzvedl).
- **Popis:** U dítěte, které rodič omluvil včas (oběd odhlášen) a které přesto přišlo, zůstane `strava_prihlasena=false`, `omluvenka='nemoc'` a `omluva_potvrzena`. Kuchyně oběd nepočítá a vyúčtování stravného je špatně.
- **Reprodukce / ověřeno:** b.js (`strava_prihlasena=false` simulováno jako včasná omluvenka) → po příchodu `pritomen|04:29|nemoc|false|<potvrzeno>|Petra Horáková`.
- **Oprava:** Při přechodu z omluven na přítomen vynulovat omluvenku a potvrzení. Oběd přihlásit, jen pokud to kuchyně ještě stihne (jinak upozornit „oběd dnes není objednaný“).

### D7 — STŘEDNÍ — Pověřené osoby se na tabletu neukazují a „vyzvedl“ je jen obecné „rodiče“
- **Kde:** `server.js:91` (`usualPickup: 'rodiče'`), `server.js:209` (`poverene_osoby` ani `zastupci` se nenačítají). Dialog odchodu `Trida.dc.html:1594-1597`.
- **Popis:** Učitelka při předání nevidí, kdo smí dítě vyzvednout (babička Marie, rodičem přidaný dědeček Karel), a nemůže vybrat skutečnou osobu. Do DB i rodiči jde vždy „rodiče“, pokud rodič vyzvednutí neohlásil. Kontrolu oprávněnosti předání tak tablet nepodporuje.
- **Ověřeno:** a.js, g.js (dialog: „Zapsat odchod? | Ema T. | Vyzvedává rodiče“, „Marie“ ani „Karel“ nikde).
- **Oprava:** Načíst `zastupci` a aktivní `poverene_osoby`, v dialogu odchodu nabídnout výběr (výchozí = ohlášená osoba) a jméno uložit do `vyzvedl`. Volbu „jiná osoba“ výrazně označit.

### D8 — STŘEDNÍ — Chybové stavy: tablet hlásí úspěch dřív, než server zápis potvrdí, a po chybě ukazuje neuložený stav
- **Kde:** `Trida.dc.html:1544-1551, 1600-1616, 1803-1851` (nejdřív změní stav a ukáže „zapsán/Odesláno rodičům“, server až potom), `srvSend` `:1272-1276`, `server.js:31-39` (`chyba()` RLS chybu nepřeloží), `shell.js:357` („[object Object]“).
- **Popis:** Při výpadku sítě nebo zastavené proxy přijde nejdřív „Ema T. — příchod zapsán“, hned po něm toast „Nepodařilo se uložit… Server není dostupný“ (to je v pořádku). Dlaždice ale dál ukazuje „ve třídě“, zápis se nikam nezařadí a po obnovení sítě se nedopíše. V DB nic není a po obnovení stránky dítě „zmizí“ zpět do „čekáme“. U zablokovaného účtu je toast „new row violates row-level security policy for table "dochazka"“. Po obnovení stránky pak tablet tvrdí „Ve třídě Sluníčka zatím nejsou žádné děti“, místo aby řekl, že je přístup zablokovaný. Když je zápis příchodu odmítnutý, tablet přesto dovolí zapsat teplotu („Odesláno rodičům“ + další chyba).
- **Ověřeno:** e.js (route abort i skutečné zastavení proxy podle PID), f.js (blokace během práce), g.js.
- **Oprava:** Ukládat pesimisticky (spinner, toast až po úspěchu) nebo vést frontu neodeslaných zápisů s opakováním a viditelným štítkem „neuloženo“ u dítěte. Při chybě lokální stav vrátit. `chyba()` doplnit o RLS/401 → „Váš přístup je zablokovaný / platnost přihlášení vypršela“. V `shell.js` (`prazdnaTrida`/`otevri`) nejdřív zavolat `muj_stav` a teprve pak hlásit „žádné děti“. Opravit „[object Object]“.

### D9 — STŘEDNÍ (integrita) — `udalosti_ditete.zapsal/zapsal_jmeno` a `urazy.zapsal` jdou podvrhnout, docházka nemá autora ani audit
- **Kde:** `supabase/setup.sql:613` (ud_psat nekontroluje `zapsal`), `:366` (urazy), `:109-118` (`dochazka` nemá `zapsal`), triggery `a_*` (`:425-429`, `:721`) na `dochazka` chybí.
- **Popis:** Učitelka vloží událost se `zapsal` = ředitelka a `zapsal_jmeno` = „Ivana Pokorná“ (prošlo). U docházky se nedá zjistit, kdo a kdy příchod, odchod nebo vrácení zapsal (a ani kdo smazal řádek přes `delete`).
- **Ověřeno:** c.js (insert jako učitelka prošel), a.js (`information_schema`: dochazka bez `zapsal`, 0 triggerů).
- **Oprava:** `with check (zapsal = auth.uid())`, `zapsal_jmeno` doplňovat triggerem z `uzivatele`. Do `dochazka` přidat `zapsal uuid default auth.uid()`, `zmeneno timestamptz` a trigger `zapis_audit`.

### D10 — STŘEDNÍ — Ředitelna na jiném zařízení úraz z tabletu nevidí a v ostrém provozu ukazuje ukázkové úrazy
- **Kde:** `Reditel.dc.html:1543` (ukázková `this.urazy`), `:2650-2654` (doplňuje jen z localStorage `S.urazy`).
- **Popis:** Úraz je v DB (ředitelka ho přes API čte) a ředitelna v prohlížeči ukazuje „3/2026 … Kamil Kos, Motýlci“. Záznam pro ČŠI a pojišťovnu pak nikdo nevyplní.
- **Ověřeno:** c.js (screenshot `c-reditelna-urazy.png`). Týká se Ředitelny, uvádím kvůli návaznosti na tablet.
- **Oprava:** V ostrém provozu načítat `urazy` ze serveru a ukázková data nezobrazovat.

### D11 — STŘEDNÍ — Jen jedna třída na účet: nejde přepnout třídu, zástupkyně bez třídy se na tablet nedostane, `trida_dnes` se neukazuje ani nezapisuje
- **Kde:** `shell.js:162-166` (`const t = s.tridy[0]`; zástupkyně má tablet jen s `ucitel_trida`), `server.js:208-211` (`nactiTridu` filtruje `deti.trida_id`), `server.js` neobsahuje `trida_dnes`, `Trida.dc.html:1245` (classes = jen jedna třída).
- **Popis:** Učitelka nebo zástupkyně se dvěma třídami vidí jen první (podle pořadí z DB) a přepnout nemůže. Zástupkyně, která ráno zaskočí ve třídě, na tablet nesmí („Patří do: Ředitelna“). Sloučení tříd a přesun dětí v ostrém provozu nejde (není s čím slučovat). Dítě dočasně přesunuté přes `dochazka.trida_dnes` (RLS ho učitelce zpřístupní) se v cílové třídě neukáže.
- **Ověřeno:** f.js.
- **Oprava:** Ve `profil()` nechat seznam všech tříd a dát přepínač do hlavičky. Vedení dovolit otevřít tablet libovolné třídy své školky. `nactiTridu` = děti třídy ∪ děti s `trida_dnes = třída` dnes. Přesun a sloučení ukládat do `trida_dnes`.

### D12 — STŘEDNÍ — Tablet otevřený přes půlnoc zapíše včerejší příchod do nového dne
- **Kde:** `server.js:41-44, 229-235` (`dnes()` se počítá při každém zápisu, stav dětí v desce se ale při změně dne neobnoví).
- **Popis:** Deska v paměti drží včerejší stav. Klepnutí na odchod druhý den vytvoří nový řádek `pritomen 04:39–04:39`, i když dítě nepřišlo. Hlavička už ukazuje nové datum, ale děti ne.
- **Ověřeno:** h2.js (Date v prohlížeči posunutý o +24 h).
- **Oprava:** Při změně `dnes()` (kontrolovat po minutě a při visibilitychange) desku načíst znovu ze serveru.

### D13 — NÍZKÁ — `omluv_dite` vrací rodiči „omluveno“ i za den, kdy už dítě je ve školce
- **Kde:** `supabase/setup.sql:799-808` (`return next` i když `on conflict … where stav <> 'pritomen'` nic nezměnil).
- **Popis:** Řádek se správně nepřepíše, RPC ale vrátí `2026-10-14:false`, takže LifeOS rodiči ukáže úspěšnou omluvenku, která neplatí.
- **Ověřeno:** b.js.
- **Oprava:** Vracet jen skutečně změněné dny (`get diagnostics`) a ostatní vrátit s příznakem „už je ve školce“.

### D14 — NÍZKÁ — `moje_dite` a `trida_dnes` porovnávají s `current_date` serveru (UTC v Supabase)
- **Kde:** `supabase/setup.sql:982-983`.
- **Popis:** Mezi 0:00 a 2:00 (letní čas) platí `trida_dnes` pro jiný den, než jaký je v Praze. Tablet i `udalosti_ditete` přitom používají pražské datum.
- **Ověřeno:** jen čtením kódu — NEOVĚŘENO, lokální DB běží v Europe/Prague.
- **Oprava:** `(now() at time zone 'Europe/Prague')::date`.

### D15 — NÍZKÁ — Po obnovení stránky se v deníku dítěte ztratí podrobnosti
- **Kde:** `server.js:113-114` (`title = titulek + hodnota`, `text` se nezobrazí).
- **Popis:** Po obnovení je místo „Snědl celý oběd“ jen „Poznámka“, místo „kašel, rýma“ jen „Není mu dobře“ a zmizí i „kniha úrazů č.“.
- **Ověřeno:** c.js.
- **Oprava:** Do `sub` přidat `text`, u úrazu číslo z `urazy`.

### D16 — NÍZKÁ — Na 1024×768 a 834×1112 se deska jen zmenšuje
- **Popis:** Na 1024×768 se deska zmenší zhruba na 0,86 (cíle 44 px → ~38 px, písmo stavů ~10 px), na 834×1112 na výšku zhruba na 0,7. Nic se neořízne ani nepřeteče.
- **Ověřeno:** f.js (měření `scrollWidth`, okrajů tlačítek, screenshoty `f-*.png`).
- **Oprava:** Pro užší displeje skládat sloupce pod sebe místo zmenšování, minimální dotykový cíl 44 px.

### D17 — INFO — Rodič čte přímo tabulku `urazy` (svědek, komentář, `zapsal`)
- `uraz_cist` povoluje roli rodič. LifeOS ji nečte (používá `udalosti_ditete`). Je potřeba rozhodnout, jestli rodič má vidět interní komentář a svědka. Ověřeno: c.js (rodič Emy: 1 řádek).

---

## 3. Co nebylo ověřeno
- Realtime (živé změny) — v testovacím režimu je vypnutý. Ověřena jen náhradní obnova při návratu do okna (h2.js).
- Chování v DB s časovou zónou UTC (D14).
- Nahrávání fotek do Storage — v ostrém provozu není (alba se neukládají vůbec).
