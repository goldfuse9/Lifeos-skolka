# Audit C — Jídelna (Jidelna.dc.html + server.js + supabase/setup.sql)

Datum: 14. 10. 2026 (středa, Europe/Prague). Prostředí: zmrazená kopie `/home/claude/skolka-audit`, vlastní lokální instance `skolka_c` (PostgREST 3031, proxy 3032, web 8831). Data obnovena `testy/reset.sh skolka_c` (pozn.: DB `skolka_c` na začátku obsahovala cizí sadu účtů `*.lifeos.cz`, proto reset).
Skripty a screenshoty: `scratchpad/audit/C/` (t1–t8.js, 01–10*.png). Všechny E2E přes `stranka()` (config.js → lokální proxy), SQL kontroly přes `sql()` / `sqlJako()` (RLS jako konkrétní identita).

Legenda režimu: **SERVER** = čte/zapisuje Supabase, **UKÁZKA** = data natvrdo v kódu desky, **localStorage** = jen v prohlížeči (klíč `skolka-jidelna-v1`, `skolka-sdilene-v1`).

---

## 1) Inventář funkcí

| # | Funkce (deska) | Režim v ostrém provozu | Stav | Jak ověřeno |
|---|---|---|---|---|
| 1 | Přihlášení kuchařky / ředitelky do #jidelna | SERVER (Auth, muj_stav) | OVĚŘENO | t1: kucharka@test.cz → #jidelna, bez chyb JS |
| 2 | Odznak „Zkušební provoz“ | UKÁZKA (natvrdo) | SELHÁVÁ | t1: v nav i v ostrém provozu (C14) |
| 3 | Název školky v menu / hlavička tisku | UKÁZKA / localStorage ředitelny | SELHÁVÁ | t1, t7, t4-E: „MŠ Sluníčko“, IČO 70891234 i pro školku B (C13) |
| 4 | Přehled „Co se vaří“ (dnes) | UKÁZKA + localStorage | SELHÁVÁ | t1: deska „Rybí filé na másle, brambory“, DB „Rybí filé, brambory, mrkvový salát“ (C1) |
| 5 | Počty porcí / obědů na den | UKÁZKA (3 smyšlené třídy, 28/18/16 dětí, 11 dospělých) | SELHÁVÁ | t1, t5-3 (C2) |
| 6 | Odhlášené obědy (omluvy rodičů, `strava_prihlasena`) | CHYBÍ (natvrdo 4/2/1) | SELHÁVÁ | t5-3: omluva Emy 19.10 v DB `strava=false`, deska (sobota → Po 19.10) dál „Odhlášeno 7“ (C2) |
| 7 | Diety dětí (kdo má jakou alergii) | UKÁZKA (7 smyšlených dětí) / localStorage ředitelny | SELHÁVÁ | t1: Oliver N., Ema K., Jonáš P.… ; DB `deti_jidelna`: Ema (mléko), Tobiáš (vejce), Oliver (–) (C3) |
| 8 | „Doporučení lékaře doloženo“ přepínač | localStorage (tabulka `diety` nepoužita) | SELHÁVÁ | t7: klik → žádný zápis na server, `diety` 0→0 (C3) |
| 9 | Jídelníček týdne – zobrazení | UKÁZKA + localStorage (ze serveru se nečte) | SELHÁVÁ | t1/t2: v DB zveřejněný týden, deska ukazuje vlastní ukázkové menu a stav „Návrh“ (C1) |
| 10 | Jídelníček – výběr jídla do buňky | localStorage; na server jen když je týden v TOMTO prohlížeči `srvPublished` | ČÁSTEČNĚ | t2: změna Pá oběd po zveřejnění → DB změněno; t4/t8 nový prohlížeč → bez push (C5) |
| 11 | Jídelníček – „Vyprázdnit“ | localStorage | SELHÁVÁ | t2: deska dál „Zveřejněno rodičům“, DB i rodič dál vidí staré jídlo (C6) |
| 12 | Zveřejnit rodičům | SERVER (RPC zverejni_jidelnicek) | OVĚŘENO (zápis) / SELHÁVÁ (obsah) | t2: 25 řádků v DB, rodič je přes `jidelnicek_tyden` vidí; ale přepíše skutečné menu ukázkovým (C1), stav zveřejnění jen v localStorage (C5) |
| 13 | „Doplnit z minulého týdne“ | localStorage | OVĚŘENO (lokálně) | t5: doplní, jen bez serveru |
| 14 | Alergeny jídla ze surovin (1–14) | localStorage; na server jen snímek při zveřejnění | SELHÁVÁ | t4-C: přidání arašídů → deska „5, 7, 9“, rodič dál `{7,9}`, deska hlásí „Zveřejněno“ (C4) |
| 15 | Jídla a suroviny (nové jídlo, surovina, úprava) | localStorage (tabulky `jidla/suroviny/jidlo_suroviny` se z desky nečtou ani nepíší, jen generovaný řádek „alergeny: …“) | SELHÁVÁ | t7: žádný POST, `jidla` 70→70, `suroviny` 198→198 |
| 16 | Náhrady podle alergenu (Diety → týden) | localStorage; server jen při dalším push | SELHÁVÁ | t4-B: editace → DB 0 řádků; po push se náhrada „jen pro pátek“ objeví i 22.10 (C7) |
| 17 | Přepínač „Náhrady děláme/neděláme“ | SERVER (nastav_nahrady, čte skoly.nahrady_obedu) | OVĚŘENO s vadami | t3-A: DB `f`, rodič `nahrady={}`, po reloadu přepínač ze serveru; vady C8, C9 |
| 18 | Kuchařky (úvazek, ZP, hygiena) | UKÁZKA + localStorage | SELHÁVÁ (není ostrý) | t7: přidání kuchařky → žádný zápis |
| 19 | Tisk jídelníčku na nástěnku | lokální data | OVĚŘENO (funkčně) / obsah ukázkový | t5-2: popup s tabulkou, alergeny, legenda, „Vedoucí: Jaroslava Benešová“ (smyšlená) |
| 20 | Výdejní list | lokální/ukázková data | SELHÁVÁ (obsah) | t7: porce 55/66, třídy Motýlci…, smyšlené děti |
| 21 | Pestrost týdne (spotřební koš) | lokální | NEOVĚŘENO věcně (jen zobrazení) | t1 |
| 22 | Sklad / objednávky surovin | CHYBÍ | CHYBÍ | deska žádnou takovou sekci nemá (Jidelna.dc.html:790–794) |
| 23 | Platby stravného | CHYBÍ v jídelně | CHYBÍ | deska nemá; tabulky `sazby_stravneho/predpisy` jsou jen pro ředitelnu/hospodářku (mimo scope C) |
| 24 | Realtime změny (omluvy během dne) | CHYBÍ | CHYBÍ | server.js jídelna nemá `sleduj`; deska nic neodebírá |
| 25 | Rodič: `jidelnicek_tyden` | SERVER | OVĚŘENO | t2: dny Po–Pá, chody v pořadí prs/pol/obed/sv/nap, alergeny, náhrady; s vypnutými náhradami `{}` (t3-A) |
| 26 | Rodič: omluva → odhlášení oběda (`omluv_dite`) | SERVER | OVĚŘENO (DB) / do jídelny se nepromítá | t5-3: 19.10 `obed_odhlasen=true`, `strava_prihlasena=false` (C2) |
| 27 | Role – UI směrování | SERVER (muj_stav) + shell | OVĚŘENO | t5-4: učitelka/hospodářka/zástupkyně do Jídelny odmítnuty, kuchařka do Ředitelny/Třídy odmítnuta i přímým #reditel/#trida |
| 28 | Role – DB (učitelka/rodič nesmí zveřejnit) | SERVER (RLS, RPC) | OVĚŘENO | t6: zverejni/nastav_nahrady → výjimka, insert jidelnicek → RLS, update → 0 řádků |
| 29 | Oddělení školek – jídelníček (`jidelnicek`, `jidla`) | SERVER | OVĚŘENO | t6: kuchařka A nevidí jídla B, ředitelka B nevidí jídelníček A |
| 30 | Oddělení školek – `nahrady`, `jidlo_suroviny`, `diety` | SERVER | SELHÁVÁ | t6 (C10, C11) |
| 31 | Oddělení školek – data desky v prohlížeči | localStorage | SELHÁVÁ | t4-E (C12) |
| 32 | Výpadek sítě při zveřejnění | SERVER | OVĚŘENO | t5-1: proxy zastavena → toast „Server není dostupný…“, týden zůstal „Návrh“, po obnově zveřejnění prošlo (25 řádků) |
| 33 | Výpadek sítě u přepínače náhrad | SERVER | SELHÁVÁ (drobně) | t5-1 (C9) |
| 34 | Časová pásma / týden od pondělí | klient (lokální čas) + SQL Europe/Prague | OVĚŘENO | t5-3: hodiny na so 17.10 → deska Po 19.10; týden +2 přes změnu času 25.10 → „26. – 30. října“; `omluv_dite` počítá v Europe/Prague; LifeOS `pondeli()` o víkendu = příští Po (shodně s deskou) |
| 35 | Validace vstupu `zverejni_jidelnicek` | SERVER | SELHÁVÁ (drobně) | t6 (C16) |

---

## 2) Nálezy

### C1 — KRITICKÁ: Deska v ostrém provozu nečte jídelníček ze serveru; zveřejnění přepíše skutečné menu ukázkovým
- **Soubor:řádek:** Jidelna.dc.html:452–486 (ukázková jídla), 507–513 (ukázkové týdny), 537–540 (componentDidMount čte jen `nahradyObedu`), 1073–1088 (publishWeek); server.js:265–276 (jídelna má jen zápis, žádné čtení).
- **Popis:** Kuchařka vidí a vaří podle ukázkového týdne natvrdo v kódu (+ localStorage), ne podle `jidelnicek` v DB. Rodiče přes `jidelnicek_tyden` vidí DB. Dva různé jídelníčky ve stejný den. Když kuchařka klikne „Zveřejnit rodičům“ (deska ukazuje „Návrh“, i když DB týden zveřejněný má), přepíše skutečné menu ukázkovými jídly.
- **Reprodukce:** reset → přihlásit kucharka@test.cz → Jídelníček (12.–16. 10.) ukazuje „Návrh · připraveno ke zveřejnění“ a jiná jídla než DB → „Zveřejnit rodičům“.
- **Jak ověřeno:** t1 (síťové požadavky: jen muj_stav, uzivatele, ucitel_trida, skoly; žádné čtení jídelníčku); t2: rodič před = „Chléb s tuňákovou pomazánkou… Kuřecí plátek…“, po = „Chléb se sýrovou pomazánkou, paprika / Dýňový krém / Rizoto se sýrem…“ (přepsáno všech 20 + 5 nových „nap“).
- **Oprava:** Přidat `SkolkaServer.jidelnicek(od, do)` (select `jidelnicek` + `jidla` + alergeny/náhrady, RLS dovolí i nezveřejněné kuchyni) a v ostrém režimu stavět `weeks` ze serveru; ukázková data jen bez serveru. Stav „zveřejněno“ brát z `jidelnicek.zverejneno`, ne z localStorage.

### C2 — KRITICKÁ: Počty obědů a odhlášky jsou smyšlené; omluva rodiče (odhlášený oběd) se do jídelny nepromítne
- **Soubor:řádek:** Jidelna.dc.html:430 (třídy Sluníčka 28 / Berušky 18 / Motýlci 16), 699–715 (`excusedBy = {slunicka:4, berusky:2, motylci:1}`, dnes jen z lokálního `kidAtt` tabletu v localStorage), 898 (`adults = 11`); setup.sql:361 + 973–986 (`moje_dite` nemá větev `kucharka` → kuchařka z `dochazka` nevidí nic).
- **Popis:** „Obědů 66 · Odhlášeno 7 · podle docházky z tabletů“ je vždy stejné číslo z kódu, bez ohledu na skutečné děti (A má 3 aktivní děti ve 2 třídách) a omluvy. `dochazka.strava_prihlasena` deska nečte a kuchařka ji kvůli RLS číst ani nemůže. Popisek „odhlášky do 7:30“ (ř. 926, 1090) neodpovídá serveru (uzávěrka den předem do 8:00 – `financni_nastaveni.omluva_do`).
- **Reprodukce:** rodič Emy `omluv_dite(Ema, 2026-10-19, 2026-10-19)` → DB `omluven, strava_prihlasena=false`; deska s hodinami na so 17.10 (výdej Po 19.10) → „Obědů 66, Odhlášeno 7“.
- **Jak ověřeno:** t5-3 (E2E s `clock.install` + `sqlJako` rodiče a kuchařky: `select count(*) from dochazka` jako kuchařka = 0); t1 (dnešek).
- **Oprava:** RPC `pocty_obedu(den)` (security definer, role kucharka/reditelka, filtr `moje_skola()`), vracející po třídách počet zapsaných dětí minus `strava_prihlasena=false`, + počet diet; desku přepnout na něj (a realtime/obnova). Text uzávěrky brát z `financni_nastaveni`.

### C3 — VYSOKÁ: Diety jsou smyšlené děti, skutečné alergie dětí z kartotéky se v jídelně neukáží
- **Soubor:řádek:** Jidelna.dc.html:489–497 (ukázkové diety), 720–736 (`syncDiets` jen z `store().deti` v localStorage ředitelny), 1053 (doporučení lékaře jen lokálně); setup.sql:455–458 (view `deti_jidelna` existuje, ale nepoužívá se), 311–315 (`diety` nepoužitá).
- **Popis:** Kuchařka vidí „Oliver N. – arašídy, Ema K., Jonáš P., Anna B. …“, ale ve školce jsou Ema (mléko) a Tobiáš (vejce). Tobiášův alergen vejce kuchyně nevidí → náhrada se nepřipraví. Kolize/„chybí náhrada“ v jídelníčku se počítají nad smyšlenými dětmi.
- **Jak ověřeno:** t1 (texty diet), t5-3 (`sqlJako` kuchařky nad `deti_jidelna` = „Oliver Z -, Ema T mléko, Tobiáš U vejce“), t7 (přepnutí „doporučení lékaře“ → žádný zápis, `diety` 0→0).
- **Oprava:** V ostrém režimu načíst `deti_jidelna` (+ `diety` pro doporučení/poznámku) a zapisovat doporučení do `diety`.

### C4 — KRITICKÁ (bezpečnost dětí): Změna receptury/alergenu po zveřejnění se rodičům nepropíše a deska dál hlásí „Zveřejněno“
- **Soubor:řádek:** Jidelna.dc.html:1003–1019 (úpravy jídla/surovin jen v paměti), 1007, 1012 (`cur.ings.push`), 1074 (stav podle `srvPublished`).
- **Popis:** Přidání suroviny s alergenem (např. arašídové máslo do „Rizoto se sýrem“) se na server nepošle; rodič v LifeOS dál vidí alergeny bez 5 a aplikace dítěti s alergií na arašídy nic nehlásí.
- **Reprodukce:** zveřejnit týden → Jídla a suroviny → Rizoto → přidat „Arašídové máslo“ → Jídelníček ukazuje „Zveřejněno rodičům“.
- **Jak ověřeno:** t4-C: deska „Alergeny 5 Arašídy 7 Mléko 9 Celer“, `jidelnicek_tyden` jako rodič 12.10 oběd `{7,9}`.
- **Oprava:** Alergeny a suroviny ukládat do `jidla/suroviny/jidlo_suroviny` hned (RLS to kuchyni dovoluje) – `jidelnicek_tyden` je počítá živě; nebo po každé změně jídla, které je v zveřejněném týdnu, automaticky volat znovu `zverejni_jidelnicek` a do té doby ukázat „Změna není u rodičů“.

### C5 — VYSOKÁ: Stav „zveřejněno“ je jen v localStorage jednoho prohlížeče
- **Soubor:řádek:** Jidelna.dc.html:845 (push změny jen při `WW.srvPublished`), 935–936, 1074, 1081.
- **Popis:** Na jiném počítači / po vymazání prohlížeče je zveřejněný týden „Návrh“ a změny jídel se na server vůbec neposílají (jen „Uloženo do návrhu“), přitom rodiče zveřejněnou verzi vidí. Kuchařka tak může mít dojem, že rodiče nic nevidí, nebo naopak, že změnu vidí.
- **Jak ověřeno:** t2 (stejný prohlížeč: změna Pá oběd → DB změněna) vs. t4/t8 (nový kontext: týden 12.–16. 10. zveřejněný v DB, deska „Návrh“).
- **Oprava:** viz C1 — stav z `jidelnicek.zverejneno`.

### C6 — VYSOKÁ: „Vyprázdnit“ v zveřejněném týdnu nesmaže jídlo u rodičů a nejde znovu zveřejnit
- **Soubor:řádek:** Jidelna.dc.html:837 (`published=false`, server se nevolá, `srvPublished` zůstává true), 1076 (`if (PUB) return`); setup.sql:1165–1191 (RPC jen upsertuje, nikdy nemaže chody, neumí zrušit zveřejnění).
- **Reprodukce:** zveřejnit příští týden → Pá svačina → Vyprázdnit.
- **Jak ověřeno:** t2: stav týdne „Zveřejněno rodičům“ s prázdnou buňkou, DB `2026-10-23 sv` = „Chléb se sýrovou pomazánkou… z=true“, tlačítko „✓ Zveřejněno“ (nelze znovu).
- **Oprava:** RPC pro smazání chodu / zrušení zveřejnění (`delete from jidelnicek where skola_id=moje_skola() and den=… and chod=…`), volat při Vyprázdnit; `zverejni_jidelnicek` ať nahradí celý týden (delete den∈týden + insert).

### C7 — VYSOKÁ: Náhrady se ukládají k jídlu, ne ke dni — úprava pro jeden den přepíše náhradu u téhož jídla v jiných dnech/týdnech; samotná úprava se neuloží
- **Soubor:řádek:** Jidelna.dc.html:1031 (`W.subs[key]` jen lokálně, bez serveru), 549 (náhrada dne se posílá jako náhrada jídla); setup.sql:1174 (jídlo hledané podle názvu+druhu), 1181–1183 (`delete from nahrady where jidlo_id` + insert).
- **Reprodukce:** Diety → 16.10 přesnídávka „Rohlík s tvarohovou…“ bez mléka → napsat „NAHRADA-PATEK-16“ → (nic se neuloží) → v Jídelníčku znovu vybrat totéž jídlo (push).
- **Jak ověřeno:** t4-B: po editaci `nahrady` s textem = 0; po push rodič 16.10 prs `{"7":"NAHRADA-PATEK-16"}` **i** 22.10 sv (jiný den, jiný chod) `{"7":"NAHRADA-PATEK-16"}`.
- **Oprava:** Buď náhrady k `jidelnicek` (skola, den, chod, alergen), nebo v UI náhradu vázat jen na jídlo (bez denních výjimek). Po editaci ve zveřejněném týdnu odeslat změnu na server.

### C8 — STŘEDNÍ: Vypnutí náhrad + jakákoli změna smaže náhrady na serveru; po zapnutí rodiče vidí „náhrada chybí“
- **Soubor:řádek:** Jidelna.dc.html:549 (`if (self.nahradyOn !== false)` → prázdné `nahrady`), 1043–1047 (zapnutí nic znovu neposílá); setup.sql:1181.
- **Jak ověřeno:** t8: Út 13.10 oběd `{"7":"Kuřecí plátek, vařené brambory"}` → vypnout, uložit buňku, zapnout → DB `nahrady_obedu=t`, rodič `{}`; deska přitom náhradu ukazuje.
- **Oprava:** Posílat náhrady vždy (filtr podle `nahrady_obedu` už dělá `jidelnicek_tyden`).

### C9 — NÍZKÁ: Přepínač náhrad při výpadku sítě zůstane v desce přepnutý (a v localStorage), server ne
- **Soubor:řádek:** Jidelna.dc.html:1043–1047 (optimistická změna bez vrácení).
- **Jak ověřeno:** t5-1: proxy zastavena → toast „Nepodařilo se uložit…“, přepínač „Náhrady neděláme“, DB `t`; po reloadu se vrátí „Náhrady děláme“.
- **Oprava:** Při chybě vrátit `nahradyOn` a `save()`.

### C10 — KRITICKÁ (oddělení školek): Kuchařka/ředitelka školky A může měnit náhrady a mazat alergeny jídel školky B
- **Soubor:řádek:** setup.sql:444 (`js on jidlo_suroviny for all using (je_kuchyne())`), 446 (`nah_menit ... using (je_kuchyne())`) — chybí podmínka na školu.
- **Reprodukce (jako kucharka A, známé `jidlo_id` školky B):** `update nahrady set text='PODVRH-OD-A' where jidlo_id='<B>'` → 2 řádky; `insert into nahrady values ('<B>',5,'PODVRH-5')` → 1; `delete from jidlo_suroviny where jidlo_id='<B>'` → 1.
- **Jak ověřeno:** t6 (`sqlJako` kuchařky A); rodič školky B pak v `jidelnicek_tyden` vidí 12.10 prs `alergeny {}` a náhrady „PODVRH…“ — tj. dítěti ze školky B zmizí informace o alergenech.
- **Oprava:** `using (je_kuchyne() and exists (select 1 from jidla j where j.id = jidlo_id and j.skola_id = moje_skola()))` + stejné `with check`; ID jídel jsou UUID (těžko uhodnutelná), ale `nahrady` jsou čitelné všem (C11) → ID získatelná.

### C11 — VYSOKÁ (GDPR/oddělení): `diety` bez vazby na školu; `nahrady` čte každý přihlášený napříč školkami
- **Soubor:řádek:** setup.sql:450 (`die on diety for all using (je_kuchyne())`), 445 (`nah_cist ... using (true)`).
- **Jak ověřeno:** t6: kuchařka A `insert into diety` pro Adama (školka B) → OK; ředitelka B ho čte („podvrh A“); kuchařka A čte i maže diety dětí školky B. Rodič A čte `nahrady` všech školek (84 řádků, vč. textů školky B); rodič může `nahrady` číst i když jídelna náhrady vypnula (obchází `nahrady_obedu`). `jidlo_suroviny` čte kuchařka A napříč školkami (69 řádků).
- **Oprava:** `diety`: `using/with check (je_kuchyne() and exists (select 1 from deti d where d.id = dite_id and d.skola_id = moje_skola()))`. `nahrady`/`jidlo_suroviny` select: přes `jidla.skola_id = moje_skola()`.

### C12 — VYSOKÁ (oddělení školek v prohlížeči): Data jídelny v localStorage nejsou vázaná na školku/účet a po odhlášení zůstávají
- **Soubor:řádek:** Jidelna.dc.html:555–586 (klíče `skolka-jidelna-v1`, `skolka-sdilene-v1` bez skola_id/uid); odhlášení (1113) je nemaže.
- **Reprodukce:** stejný prohlížeč: kuchařka A pracuje → Odhlásit → ředitelka B do Jídelny.
- **Jak ověřeno:** t4-E: ředitelka B vidí „MŠ Sluníčko“, jídla A (vč. přidaných arašídů), týden „Zveřejněno rodičům“, přestože DB B má 0 řádků; po uložení jedné buňky se do školky B odeslal celý týden školky A (DB B 0 → 25). Data diet (jména dětí + alergie) zůstanou po odhlášení v prohlížeči.
- **Oprava:** Klíč localStorage s `skolaId`/`uid`, při odhlášení smazat; v ostrém režimu localStorage nepoužívat pro data.

### C13 — STŘEDNÍ: Tisk (jídelníček, výdejní list) nese smyšlenou hlavičku a smyšlenou vedoucí ŠJ
- **Soubor:řádek:** Jidelna.dc.html:431 (škola „Mateřská škola Sluníčko, Praha 6, IČO 70891234“), 500–505 (kuchařky), 692 (vedoucí z ukázkových kuchařek), 1090–1097.
- **Jak ověřeno:** t5-2 a t7 (obsah popup okna: hlavička s IČO 70891234, „Vedoucí školní jídelny: Jaroslava Benešová“, výdejní list s porcemi 55/66 a třídou Motýlci). V DB je škola „MŠ Sluníčko (test)“.
- **Oprava:** Hlavičku brát ze `skoly` (+ IČO), vedoucí z `uzivatele` role kuchyně.

### C14 — NÍZKÁ: Odznak „Zkušební provoz · nic neodchází ven“ i v ostrém provozu
- **Soubor:řádek:** Jidelna.dc.html:27.
- **Jak ověřeno:** t1 (text navigace v ostrém režimu), screenshot 01-prehled.png. Klamavé — zveřejnění rodičům ven odchází.
- **Oprava:** Zobrazit jen když `!srvOn()`.

### C15 — NÍZKÁ: Každé zveřejnění vytváří nové „suroviny“ – tabulka roste a hromadí sirotky
- **Soubor:řádek:** setup.sql:1176–1180 (insert `suroviny 'alergeny: …'` při každém chodu, staré vazby smazány, surovina ne).
- **Jak ověřeno:** t2: 20 → 45 po jednom zveřejnění týdne; t6: 171 surovin školky A, z toho 151 „alergeny: …“, 129 osiřelých.
- **Oprava:** Upsert jedné technické suroviny na jídlo nebo ukládat alergeny přímo k jídlu; mazat osiřelé.

### C16 — NÍZKÁ: `zverejni_jidelnicek` nevaliduje vstup
- **Soubor:řádek:** setup.sql:1165–1191.
- **Jak ověřeno:** t6: kuchařka zveřejní jídlo na sobotu 17.10 (OK), alergen 99 (OK — `suroviny.alergeny` nemá check 1–14), chybějící název → syrová chyba NOT NULL.
- **Oprava:** Kontrola `isodow < 6`, `alergen between 1 and 14`, neprázdný název, srozumitelná hláška.

### C17 — INFO: Jídelna nemá sklad/objednávky surovin ani platby stravného; realtime chybí
- Ověřeno čtením navigace desky (Jidelna.dc.html:790–794) a server.js:265–276; E2E t1 (nav: Dnes v kuchyni, Jídelníček, Jídla a suroviny, Diety a náhrady, Kuchařky). Platby stravného patří ředitelně/hospodářce (mimo C).

---

## 3) Co je v pořádku (ověřeno)
- Role: učitelka, hospodářka, zástupkyně se do Jídelny nepřihlásí; kuchařka nesmí do Ředitelny ani Třídy (ani přímým #reditel/#trida) — t5-4.
- DB: učitelka ani rodič nemohou zveřejnit ani přepnout náhrady (RPC výjimka), přímý zápis do `jidelnicek` blokuje RLS — t6. Anon nemá `jidelnicek_tyden` — t6.
- `jidelnicek`/`jidla` jsou oddělené mezi školkami; `jidelnicek_tyden` vrací jen vlastní školku — t6.
- `jidelnicek_tyden` vrací dny Po–Pá ve správném pořadí chodů, alergeny ze surovin a náhrady; při `nahrady_obedu=false` vrací `{}` — t2, t3.
- `omluv_dite` počítá uzávěrku v Europe/Prague a správně nastaví `strava_prihlasena` — t5-3.
- Výpadek sítě při zveřejnění: srozumitelná hláška, týden zůstane návrhem, po obnově projde — t5-1.
- Týdny a víkend: deska i LifeOS o víkendu ukazují příští týden; přechod času 25.10 neposune týden — t5-3, t4-D.

## 4) Neověřeno
- Chování desky v jiném časovém pásmu prohlížeče než Europe/Prague (deska používá lokální čas prohlížeče; server.js `dnes()` taky).
- LifeOS mobil end-to-end (testováno jen RPC `jidelnicek_tyden`/`omluv_dite` jako identita rodiče + čtení kódu mapování `feedZeServeru`; chod `nap` LifeOS zahazuje — `CHOD` map v services/skolkaServer.ts).
