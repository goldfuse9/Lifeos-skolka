# Audit E — Backend a Supabase (Školka + LifeOS)

Datum: 14. 10. 2026 · Zdroj: zmrazená kopie `/home/claude/skolka-audit` (commit `1e3a725`), LifeOS `/home/claude/lifeos-a/mobile/src/services/skolkaServer.ts`.
Prostředí: lokální PostgreSQL 16 + stub auth (`testy/lokalni/supabase-stub.sql`) + PostgREST 12.2.3 + lokální proxy `/auth/v1` (DB `skolka_e`, porty 3051/3052/8851). Na živý Supabase jsem se nepřipojoval.

**Jak se ověřovalo.** Každý nález níže je reprodukovaný skutečným dotazem: buď SQL pod rolí `authenticated` s JWT claims dané identity (stejně jako `testy/bezpecnost.sh`), nebo HTTP přes PostgREST/proxy s JWT z `testy/lokalni/jwt.js`, nebo spuštěním **skutečného** `server.js` (v Node přes `vendor/supabase-2.115.0.js`) a **skutečného** `skolkaServer.ts` (přeložený `typescript`em). U nálezů, které závisí na chování ostrého Supabase (formát JWT, výchozí granty), je to výslovně uvedeno.

Pomocné soubory (vše v `scratchpad/audit/E/`):
- `seed-extra.sql` — doplní řádky do **všech** tabulek pro obě školky (A i B) + funkci `audit_e.skola()` pro měření,
- `matice.py` → `matice.txt` (surová matice), `matice.md`,
- `bezpecnost-doplnek.sh` — 25 nových testů ve formátu `testy/bezpecnost.sh` (na současném `setup.sql`: **1 PASS / 24 FAIL**; s `oprava-navrh.sql`: **25 PASS / 0 FAIL**, a původní `bezpecnost.sh` pak **69/69 PASS**),
- `oprava-navrh.sql` — konkrétní SQL oprav (ověřené na kopii DB; po nich `server.js` 30/30 volání OK a LifeOS klient 9/9 OK přes HTTP),
- `klient-server.js`, `klient-lifeos.js`, `refresh_test.js`, `fin_test.py`, `enum.js`, `migrace.sh`, `q.sh`.

Poznámka k prostředí: DB `skolka_e` při prvním spuštění `stack.sh` už existovala s cizími daty (školky `eeeeeeee-…`, jiné ID) — `stack.sh` DB neobnovuje, když existuje. Proto první běh `bezpecnost.sh` dal 14 FAIL; po `reset.sh skolka_e` 67 PASS / 2 FAIL (známá selhání). Doporučení: `stack.sh` by měl volat `reset.sh` vždy nebo aspoň ověřit testovací data.

## Shrnutí

| # | Závažnost | Nález |
|---|---|---|
| E1 | **Kritická** | Pohled `deti_jidelna` jde zapisovat (UPDATE/DELETE) a běží s právy vlastníka → kuchařka mění alergie a **maže děti** mimo RLS |
| E2 | **Vysoká** | `prijmi_pozvanku` není odolná vůči NULL e-mailu → anonymní účet (JWT bez `email`) převezme pozvánku i **ředitelky** |
| E3 | **Vysoká** | `diety`, `jidlo_suroviny`, `nahrady` bez kontroly školky → kuchařka/ředitelka A čte zdravotní diety dětí B a **maže alergeny v jídelníčku B** |
| E4 | **Vysoká** | `tridni_kniha`: vedení libovolné školky čte/zapisuje/maže třídní knihu všech školek |
| E5 | **Vysoká** | Rodné číslo, adresu, pojišťovnu, očkování čte učitelka i hospodářka (RLS je jen řádková) |
| E7 | **Vysoká** | Přímý UPDATE `uzivatele`: ředitelka degraduje a zablokuje spoluředitelku, přepíše `id` účtu (např. na superadmina), z anonymního rodiče udělá učitelku; nic z toho se neaudituje |
| E13 | **Vysoká** | Finanční API (Python) ignoruje blokaci účtu i školky |
| E6 | Střední | Trigger `pohyb_do_konta` běží s právy volajícího → zápis do konta dítěte přes API selže na RLS; MD/Dal se nevalidují |
| E8 | Střední | Vazby napříč školkami: `ucitel_trida`, `deti.trida_id`, `dochazka.trida_dnes`, `urazy.skola_id/zapsal` |
| E9 | Střední | Rodič omluví zpětně (i roky dozadu) a přepíše „neomluven“ na „omluven“ |
| E10 | Střední | Číslo úrazu počítá tablet z úrazů, které učitelka vidí → duplicita → **úraz z tabletu nejde zapsat** |
| E11 | Střední | Smazání auth účtu (anonymní rodič, učitelka se zápisy) selže na FK → nejde výmaz ani úklid anonymních účtů |
| E12 | Střední | Smazání dítěte kaskádou maže předpisy a konto; účetní pohyby zůstanou osiřelé |
| E14 | Střední | Rodič s dětmi ve dvou školkách: `moje_skola()` = první školka → LifeOS ukáže cizí jídelníček, akce a **číslo účtu jiné školky** |
| E15 | Střední | Kódy pro rodiče: žádný limit pokusů ani log, náhled vrací jméno + datum narození |
| E16 | Nízká | `zpravy.komu` se nevynucuje; personál čte jména všech rodičů |
| E17 | Nízká | `zapis_audit` (SECURITY DEFINER) a další funkce bez pevné `search_path` |
| E18 | Nízká | Výchozí granty Supabase: `anon` má ALL vč. TRUNCATE na `pozvanky`, `skoly_admin`, `superadmini` (ověřeno emulací) |
| E19 | Nízká | `audit_log` nepokrývá účty, třídy učitelek, diety, docházku, stav školky; akce superadmina mají `skola_id` NULL |
| E20 | Nízká | LifeOS při neplatném refresh tokenu potichu založí nový anonymní účet |
| E21 | Info | Storage ani Edge Functions v projektu nejsou; `alba.fotky` odkazuje na neexistující úložiště |
| E22 | Info | Migrace, konfigurace a klíče — v pořádku (detaily níže) |

## 1. RLS a politiky — přehled

Všech 38 tabulek v `public` má zapnuté RLS (smyčka `setup.sql:728-734`). Bez politik (jen přes funkce): `superadmini`, `skoly_admin`, `pozvanky`. Jen SELECT politika: `audit_log`, `konta`, `predpis_polozky`, `parovaci_kody`. Pohledy: `deti_trida` (`security_invoker`, RLS platí), **`deti_jidelna` (práva vlastníka, RLS neplatí — viz E1)**. `anon` nemá na tabulky ani funkce žádná práva (ověřeno — každá operace `permission denied`).

## 2. Matice oprávnění (reálné testy)

Formát buňky: `S a/b` = počet viditelných řádků vlastní školky A / cizí školky B · `I a/b` = INSERT kopie řádku A / B (✓ prošlo RLS, ✗ zamítnuto) · `U a/b` = počet změněných řádků A / B · `D a/b` = počet smazaných řádků A / B (`✓FK` = RLS pustilo, zastavil až cizí klíč). Identita „A“ = účty školky A (`testy/data.sql`), u bez role/superadmin/anon jde jen o to, co vidí. V hlavičce řádku je skutečný počet řádků A/B v DB. Každý pokus v transakci s rollbackem (`matice.py`). Tučně v textu níže jsou rozpory se zamýšleným modelem.

| tabulka (řádků A/B) | ředitelka | zástupkyně | učitelka | hospodářka | kuchařka | rodič | bez role | superadmin | anon |
|---|---|---|---|---|---|---|---|---|---|
| `akce` (3/1) | S 3/0 · I ✓/✗ · U 3/0 · D 3/0 | S 3/0 · I ✓/✗ · U 3/0 · D 3/0 | S 3/0 · I ✗/✗ · U 1/0 · D 1/0 | S 3/0 · I ✗/✗ · U 0/0 · D 0/0 | S 3/0 · I ✗/✗ · U 0/0 · D 0/0 | S 2/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `alba` (1/1) | S 1/0 · I ✓/✗ · U 1/0 · D 1/0 | S 1/0 · I ✓/✗ · U 1/0 · D 1/0 | S 1/0 · I ✓/✗ · U 1/0 · D 1/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `audit_log` (0/0+25) | S 0/0 · I –/– · U 0/0 · D 0/0 | S 0/0 · I –/– · U 0/0 · D 0/0 | S 0/0 · I –/– · U 0/0 · D 0/0 | S 0/0 · I –/– · U 0/0 · D 0/0 | S 0/0 · I –/– · U 0/0 · D 0/0 | S 0/0 · I –/– · U 0/0 · D 0/0 | S 0/0 · I –/– · U 0/0 · D 0/0 | S 0/0 · I –/– · U 0/0 · D 0/0 | ✗ |
| `deti` (3/1) | S 3/0 · I ✓/✗ · U 3/0 · D ✓FK/0 | S 3/0 · I ✓/✗ · U 3/0 · D ✓FK/0 | S 2/0 · I ✗/✗ · U 0/0 · D 0/0 | S 3/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `deti_jidelna` (0/0) | S 3/0 · I –/– · U 3/0 · D ✓FK/0 | S 3/0 · I –/– · U 3/0 · D ✓FK/0 | S 0/0 · I –/– · U 0/0 · D 0/0 | S 0/0 · I –/– · U 0/0 · D 0/0 | S 3/0 · I –/– · U 3/0 · D ✓FK/0 | S 0/0 · I –/– · U 0/0 · D 0/0 | S 0/0 · I –/– · U 0/0 · D 0/0 | S 0/0 · I –/– · U 0/0 · D 0/0 | ✗ |
| `deti_trida` (3/1) | S 3/0 · I ✗/✗ · U 3/0 · D ✓FK/0 | S 3/0 · I ✗/✗ · U 3/0 · D ✓FK/0 | S 2/0 · I ✗/✗ · U 0/0 · D 0/0 | S 3/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `diety` (1/1) | S 1/1 · I ✓/✓ · U 1/1 · D 1/1 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/1 · I ✓/✓ · U 1/1 · D 1/1 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `dochazka` (2/1) | S 2/0 · I ✓/✗ · U 2/0 · D 2/0 | S 2/0 · I ✓/✗ · U 2/0 · D 2/0 | S 2/0 · I ✓/✗ · U 2/0 · D 2/0 | S 2/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `financni_nastaveni` (1/1) | S 1/0 · I ✓/✗ · U 1/0 · D 1/0 | S 1/0 · I ✓/✗ · U 1/0 · D 1/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✓/✗ · U 1/0 · D 1/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `jidelnicek` (20/1) | S 20/0 · I ✓/✗ · U 20/0 · D 20/0 | S 20/0 · I ✗/✗ · U 0/0 · D 0/0 | S 20/0 · I ✗/✗ · U 0/0 · D 0/0 | S 20/0 · I ✗/✗ · U 0/0 · D 0/0 | S 20/0 · I ✓/✗ · U 20/0 · D 20/0 | S 20/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `jidla` (20/1) | S 20/0 · I ✓/✗ · U 20/0 · D ✓FK/0 | S 20/0 · I ✗/✗ · U 0/0 · D 0/0 | S 20/0 · I ✗/✗ · U 0/0 · D 0/0 | S 20/0 · I ✗/✗ · U 0/0 · D 0/0 | S 20/0 · I ✓/✗ · U 20/0 · D ✓FK/0 | S 20/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `jidlo_suroviny` (20/1) | S 20/1 · I ✓/✓ · U 20/1 · D 20/1 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 20/1 · I ✓/✓ · U 20/1 · D 20/1 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `konta` (1/1) | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `nahrady` (14/1) | S 14/1 · I ✓/✓ · U 14/1 · D 14/1 | S 14/1 · I ✗/✗ · U 0/0 · D 0/0 | S 14/1 · I ✗/✗ · U 0/0 · D 0/0 | S 14/1 · I ✗/✗ · U 0/0 · D 0/0 | S 14/1 · I ✓/✓ · U 14/1 · D 14/1 | S 14/1 · I ✗/✗ · U 0/0 · D 0/0 | S 14/1 · I ✗/✗ · U 0/0 · D 0/0 | S 14/1 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `nesparovane_platby` (1/1) | S 1/0 · I ✓/✗ · U 1/0 · D 1/0 | S 1/0 · I ✓/✗ · U 1/0 · D 1/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✓/✗ · U 1/0 · D 1/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `parovaci_kody` (1/1) | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `platby` (1/1) | S 1/0 · I ✓/✗ · U 1/0 · D 1/0 | S 1/0 · I ✓/✗ · U 1/0 · D 1/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✓/✗ · U 1/0 · D 1/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `porady` (1/1) | S 1/0 · I ✓/✗ · U 1/0 · D 1/0 | S 1/0 · I ✓/✗ · U 1/0 · D 1/0 | S 1/0 · I ✓/✗ · U 1/0 · D 1/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `poverene_osoby` (1/1) | S 1/0 · I ✓/✗ · U 1/0 · D 1/0 | S 1/0 · I ✓/✗ · U 1/0 · D 1/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✓/✗ · U 1/0 · D 1/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `pozvanky` (1/1) | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `predpis_polozky` (1/1) | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `predpisy` (1/1) | S 1/0 · I ✓/✗ · U 1/0 · D 1/0 | S 1/0 · I ✓/✗ · U 1/0 · D 1/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✓/✗ · U 1/0 · D 1/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `sazby_stravneho` (2/0) | S 2/0 · I ✓/– · U 2/0 · D 2/0 | S 2/0 · I ✓/– · U 2/0 · D 2/0 | S 2/0 · I ✗/– · U 0/0 · D 0/0 | S 2/0 · I ✓/– · U 2/0 · D 2/0 | S 2/0 · I ✗/– · U 0/0 · D 0/0 | S 2/0 · I ✗/– · U 0/0 · D 0/0 | S 0/0 · I ✗/– · U 0/0 · D 0/0 | S 0/0 · I ✗/– · U 0/0 · D 0/0 | ✗ |
| `skoly` (1/1) | S 1/0 · I ✗/✗ · U 1/0 · D 0/0 | S 1/0 · I ✗/✗ · U 1/0 · D 0/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `skoly_admin` (1/1) | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `souhlasy` (1/1) | S 1/0 · I ✓/✗ · U 1/0 · D 1/0 | S 1/0 · I ✓/✗ · U 1/0 · D 1/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✓/✗ · U 1/0 · D 1/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `superadmini` (0/0+1) | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `suroviny` (20/1) | S 20/0 · I ✓/✗ · U 20/0 · D ✓FK/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 20/0 · I ✓/✗ · U 20/0 · D ✓FK/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `tridni_kniha` (1/1) | S 1/1 · I ✓/✓ · U 1/1 · D 1/1 | S 1/1 · I ✓/✓ · U 1/1 · D 1/1 | S 1/0 · I ✓/✗ · U 1/0 · D 1/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `tridy` (2/1) | S 2/0 · I ✓/✗ · U 2/0 · D ✓FK/0 | S 2/0 · I ✓/✗ · U 2/0 · D ✓FK/0 | S 2/0 · I ✗/✗ · U 0/0 · D 0/0 | S 2/0 · I ✗/✗ · U 0/0 · D 0/0 | S 2/0 · I ✗/✗ · U 0/0 · D 0/0 | S 2/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `ucetni_pohyby` (1/1) | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `ucitel_trida` (2/1) | S 2/0 · I ✓/✗ · U 2/0 · D 2/0 | S 2/0 · I ✓/✗ · U 2/0 · D 2/0 | S 2/0 · I ✗/✗ · U 0/0 · D 0/0 | S 2/0 · I ✗/✗ · U 0/0 · D 0/0 | S 2/0 · I ✗/✗ · U 0/0 · D 0/0 | S 2/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `udalosti_ditete` (1/1) | S 1/0 · I ✓/✗ · U 1/0 · D 1/0 | S 1/0 · I ✓/✗ · U 1/0 · D 1/0 | S 1/0 · I ✓/✗ · U 1/0 · D 1/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `upominky` (1/1) | S 1/0 · I ✓/✗ · U 0/0 · D 0/0 | S 1/0 · I ✓/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✓/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `urazy` (2/1) | S 2/0 · I ✓/✗ · U 2/0 · D 0/0 | S 2/0 · I ✓/✗ · U 2/0 · D 0/0 | S 1/0 · I ✓/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `uzivatele` (8/3) | S 8/0 · I ✗/✗ · U 7/0 · D 0/0 | S 8/0 · I ✗/✗ · U 0/0 · D 0/0 | S 8/0 · I ✗/✗ · U 0/0 · D 0/0 | S 8/0 · I ✗/✗ · U 0/0 · D 0/0 | S 8/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `vyzvednuti` (1/1) | S 1/0 · I ✓/✗ · U 0/0 · D 0/0 | S 1/0 · I ✓/✗ · U 0/0 · D 0/0 | S 1/0 · I ✓/✗ · U 0/0 · D 0/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✓/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `zadosti` (1/1) | S 1/0 · I ✓/✗ · U 1/0 · D 1/0 | S 1/0 · I ✓/✗ · U 1/0 · D 1/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `zastupci` (3/1) | S 3/0 · I ✓/✗ · U 3/0 · D 3/0 | S 3/0 · I ✓/✗ · U 3/0 · D 3/0 | S 2/0 · I ✗/✗ · U 0/0 · D 0/0 | S 3/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 1/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |
| `zpravy` (2/1) | S 2/0 · I ✓/✗ · U 0/0 · D 0/0 | S 2/0 · I ✓/✗ · U 0/0 · D 0/0 | S 2/0 · I ✗/✗ · U 0/0 · D 0/0 | S 2/0 · I ✓/✗ · U 0/0 · D 0/0 | S 2/0 · I ✗/✗ · U 0/0 · D 0/0 | S 2/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | S 0/0 · I ✗/✗ · U 0/0 · D 0/0 | ✗ |

Rozpory s modelem v `setup.sql:11-18`, které matice ukazuje (podrobně v nálezech):
- `deti_jidelna` — kuchařka **U 3 / D ✓FK** (E1); `diety`, `jidlo_suroviny`, `nahrady` — kuchařka i ředitelka **S/U/D i ve školce B** (E3); `nahrady` čte i účet bez role a superadmin (E3).
- `tridni_kniha` — ředitelka i zástupkyně **S 1/1, I ✓/✓, U 1/1, D 1/1** (E4).
- `deti` — učitelka a hospodářka čtou celé řádky včetně `rodne_cislo` (E5); kuchařka nevidí nic (známé selhání „kuchařka nevidí rodná čísla“ v `bezpecnost.sh` je **falešný poplach** — dotaz vrátí 0 řádků místo chyby).
- `uzivatele` — učitelka, hospodářka, kuchařka čtou 8 řádků = celý personál **i rodiče** (E16); ředitelka mění 7 řádků (E7).
- `zpravy` — rodič a kuchařka čtou i zprávy s `komu='ucitelky'` (E16).
- `ucetni_pohyby` — INSERT ✗ i pro hospodářku/ředitelku: nejde o ochranu, ale o chybu triggeru (E6).
- Ostatní odpovídá modelu: oddělení školek A/B drží všude kromě výše uvedených; rodič vidí jen své dítě; `skoly_admin`, `pozvanky`, `superadmini`, `parovaci_kody` (kromě vedení) nejsou čitelné; `audit_log` jde jen číst vedení vlastní školky (ověřeno zvlášť: ředitelka A 1/0, ředitelka B 0/1, učitelka a rodič 0/0, INSERT ✗, DELETE 0 řádků).
- Blokace: zablokovaná učitelka / zablokovaná školka nevidí nic, ani přes `zapsal = auth.uid()` (`ud_menit`) ani přes `tridni_kniha` — UPDATE i SELECT vrací 0 (ověřeno).

## 3. SECURITY DEFINER funkce

| Funkce | `search_path` | Kdo smí volat | Kontrola oprávnění odolná vůči NULL (ověřeno: bez role, blokovaná učitelka, blokovaná školka) |
|---|---|---|---|
| `moje_role`, `moje_skola`, `moje_dite`, `je_superadmin`, `je_ucitelka_tridy`, `rodic_tridy`, `muj_stav` | public | authenticated | ano (`moje_dite` coalesce → false) |
| `vytvor_kod_rodice`, `omluv_dite`, `potvrd_omluvenku`, `potvrd_udalosti`, `zverejni_jidelnicek`, `nastav_nahrady`, `uprav_udaje_rodicem`, `zamestnanci_skoly`, `pozvi_zamestnance`, `nastav_ucet_zamestnance`, `admin_*`, `jidelnicek_tyden` | public | authenticated | ano — všechny vrátily chybu / 0 řádků pro všechny 4 identity |
| `nahled_kodu` | public | authenticated | vrací data komukoli přihlášenému včetně bez role a blokovaných (záměr; viz E15) |
| `uplatni_kod` | public | authenticated | projde i pro zablokovanou školku (vznikne účet rodiče s rolí, která nic nevidí) — nízké riziko |
| **`prijmi_pozvanku`** | public | authenticated | **NE — NULL e-mail projde (E2)** |
| **`zapis_audit`** (trigger) | **chybí** | trigger | — (E17) |

Všechny funkce mají `revoke … from public, anon` a `grant execute … to authenticated` (ověřeno `pg_proc.proacl`). Přes PostgREST jsou volatelné i pomocné funkce (`moje_dite(uuid)`, `novy_kod()`, lokálně i `pgcrypto`) — vrací jen data volajícího, neškodné.

## 4. Nálezy

### E1 — Kritická: pohled `deti_jidelna` jde zapisovat a obchází RLS
- **Soubor:** `supabase/setup.sql:455-458` (pohled bez `security_invoker`, vlastník postgres), granty `setup.sql:737` a `:1218` (`grant select, insert, update, delete on all tables` zahrnuje i pohledy).
- **Popis:** Jednoduchý pohled je v PostgreSQL automaticky zapisovatelný. Protože běží s právy vlastníka, UPDATE/DELETE přes něj jde do `deti` mimo RLS. Kuchařka (i zástupkyně, ředitelka) tak mění `jmeno`, `alergie`, `trida_id` a **maže děti** své školky; DELETE kaskádou smaže zástupce, docházku, předpisy, konto, diety (zastaví ho jen existující úraz).
- **Reprodukce (SQL jako kuchařka a7):**
  `delete from deti_jidelna where id='00000000-0000-4000-8000-000000000102';` → smazáno 1 dítě
  `update deti_jidelna set alergie='žádné', trida_id='…012' where id='…101';` → 1 řádek
- **HTTP:** `PATCH /rest/v1/deti_jidelna?id=eq.<Tobiáš>` `{"alergie":null}` s tokenem kuchařky → 200, alergie v `deti` je NULL.
- **Ověřeno:** SQL i HTTP přes PostgREST.
- **Oprava:** `revoke insert, update, delete, truncate on deti_jidelna, deti_trida from authenticated, anon;` a totéž zopakovat po každém `grant … on all tables` (nebo granty psát po tabulkách). Test: `bezpecnost-doplnek.sh` E1.

### E2 — Vysoká: anonymní účet převezme pozvánku zaměstnance i ředitelky
- **Soubor:** `supabase/setup.sql:1141` a `:1150`.
- **Popis:** `mail := lower(coalesce(auth.jwt() ->> 'email', (select email from auth.users …)))` je u anonymního účtu NULL a `if lower(p.email) <> mail then raise` se při NULL nevyhodnotí jako pravda → kontrola e-mailu se přeskočí. Komu unikne kód pozvánky (e-mail, screenshot, přeposlání), ten si anonymním přihlášením (zapnuté kvůli LifeOS) vezme roli ředitelky a celou školku. U pozvánky ředitelky navíc nastaví školku na `aktivni`.
- **Reprodukce HTTP (lokální proxy):** `POST /auth/v1/signup {"data":{}}` → token bez claimu `email`; `POST /rest/v1/rpc/prijmi_pozvanku {"p_kod":"RRRR-SSSS"}` → `[{"role":"reditelka","skola":"MŠ Dejvice (test)"}]`; pak `GET /rest/v1/deti?select=jmeno,rodne_cislo` → `Adam, 211102/0000`, `rpc/zamestnanci_skoly` → seznam zaměstnanců.
- **Ověřeno:** SQL + HTTP v lokálním stacku. Varianta s claimem `"email":""` (tak ho podle mého vydává GoTrue i pro anonymní účty) skončí chybou „Pozvánka patří jinému e-mailu“ → **v ostrém Supabase je to pravděpodobně zablokované jen náhodou** (prázdným řetězcem), neověřeno proti živému projektu. Stejně tak nezávisí na tom, zda je v Supabase zapnuté potvrzování e-mailu: bez něj stačí zaregistrovat cizí e-mail.
- **Oprava:** `oprava-navrh.sql` blok E2: `mail := lower(nullif(…, ''))`; `if mail is null or (auth.jwt()->>'is_anonymous')::boolean then raise …`; porovnání `is distinct from`. V Supabase Auth zapnout „Confirm email“. Test: doplněk E2.

### E3 — Vysoká: jídelna napříč školkami (diety, alergeny, náhrady)
- **Soubor:** `supabase/setup.sql:444` (`js … using (je_kuchyne())`), `:445` (`nah_cist … using (true)`), `:446` (`nah_menit … using (je_kuchyne())`), `:450` (`die … using (je_kuchyne())`).
- **Popis:** Politiky nekontrolují školku. Kuchařka a ředitelka libovolné školky čtou, mění i mažou `diety` (zdravotní údaje — „anafylaxe“) všech dětí všech školek a vazby `jidlo_suroviny`/`nahrady`, ze kterých `jidelnicek_tyden()` počítá alergeny pro rodiče. `nahrady` čte každý přihlášený včetně účtu bez role.
- **Reprodukce:** jako kuchařka A `delete from jidlo_suroviny where jidlo_id='<oběd B>'; delete from nahrady where jidlo_id='<oběd B>';` → rodič B pak v `jidelnicek_tyden()` vidí `Oběd B | {} | {}` místo `{1} | {"1":"Bezlepková varianta B"}` — **alergen zmizí z jídelníčku cizí školky**. `GET /rest/v1/diety` s tokenem kuchařky A vrátí i `bez arašídů — anafylaxe (B)`.
- **Ověřeno:** SQL (matice + cílený test) a HTTP.
- **Oprava:** `oprava-navrh.sql` blok E3 (pomocná `skola_ditete()` SECURITY DEFINER, politiky s `skola_id = moje_skola()` přes `jidla`/`suroviny`). Test: doplněk E3.

### E4 — Vysoká: třídní kniha všech školek pro vedení kterékoli školky
- **Soubor:** `supabase/setup.sql:370-371` (`je_vedeni() or exists(ucitel_trida …)` bez školky).
- **Reprodukce:** ředitelka A: `select trida_id, tema from tridni_kniha;` → i `Podzim B`; `update tridni_kniha set tema='přepsáno A' where trida_id='<Žabky B>'` → 1; INSERT do třídy B projde.
- **Ověřeno:** SQL (matice: S 1/1, I ✓/✓, U 1/1, D 1/1 pro ředitelku i zástupkyni).
- **Oprava:** blok E4: `(je_vedeni() and exists (select 1 from tridy t where t.id = trida_id and t.skola_id = moje_skola())) or (moje_role()='ucitelka' and je_ucitelka_tridy(trida_id))`.

### E5 — Vysoká: citlivé sloupce dítěte čte učitelka i hospodářka
- **Soubor:** `supabase/setup.sql:345` (`deti_cist … using (moje_dite(id))`), `:330-342` (`moje_dite` zahrnuje učitelku i hospodářku), komentář `:412` tvrdí opak; pohled `deti_trida` (`:413`) nikdo nevynucuje.
- **Reprodukce HTTP:** token učitelky a2: `GET /rest/v1/deti?select=jmeno,rodne_cislo,adresa` → `Ema, 210315/0000, Testovací 1, Praha`. Hospodářka a6 přes SQL čte `rodne_cislo, adresa, pojistovna, ockovani` všech dětí školky.
- **Ověřeno:** SQL i HTTP (pro tento test jsem Emě doplnil RČ a adresu, seed je nemá). Učitelka = známé selhání; **hospodářka je nový nález** (`bezpecnost.sh` ji netestuje).
- **Oprava:** blok E5: `revoke select on deti from authenticated; grant select (<necitlivé sloupce>) on deti to authenticated;` + funkce `deti_osobni(p_dite)` (SECURITY DEFINER, jen vedení a rodič). Dlouhodobě oddělit citlivé údaje do vlastní tabulky. Ověřeno, že `server.js` i LifeOS dál fungují (čtou jen povolené sloupce).

### E6 — Střední: zápis do konta dítěte přes API nefunguje, MD/Dal bez kontroly
- **Soubor:** `supabase/setup.sql:248-260` (`pohyb_do_konta` bez `security definer`), `:378-379` (konta jen SELECT), `:389-390`.
- **Reprodukce:** hospodářka: `insert into ucetni_pohyby (skola_id, datum, md, dal, castka, popis) values ('<A>', current_date, 'dite:<Ema>', 'vynosy:skolkovne', 100, 'x');` → `new row violates row-level security policy for table "konta"`. Přitom `md='banka', dal='xdite:<Adam z B>'` projde — účty se nevalidují.
- **Ověřeno:** SQL. Python finance (`server/finance`) jde přímo přes `DATABASE_URL` (obchází RLS), proto to dosud nevadilo; ředitelna přes PostgREST ale konto zapsat nemůže.
- **Oprava:** blok E6 — trigger `security definer set search_path = public` + kontrola, že `dite:<id>` patří do `new.skola_id`; CHECK na formát účtů.

### E7 — Vysoká: přímá úprava `uzivatele` ředitelkou
- **Soubor:** `supabase/setup.sql:1160-1162` (USING nekontroluje původní roli, WITH CHECK jen „nová role ≠ ředitelka“; sloupce `id`, `role`, `aktivni`, `email` volně), chybí audit (`zapis_audit` na `uzivatele` není).
- **Reprodukce (ředitelka a1):**
  - spoluředitelka: `update uzivatele set role='ucitelka', aktivni=false where id='<druhá ředitelka A>'` → 1 (obchází pravidlo „ředitelku blokuje jen správce LifeOS“ z `nastav_ucet_zamestnance`, `:1129-1130`),
  - `update uzivatele set id='<uid superadmina>' where id='<hospodářka>'` → 1; superadmin pak má `moje_role()='hospodarka'` a čte 3 děti (porušuje „superadmin dětská data nevidí“),
  - `update uzivatele set role='ucitelka' where id='<anonymní rodič>'` → 1.
- **Ověřeno:** SQL. Pozn.: přímé zablokování druhé ředitelky (jen `aktivni=false`) zastaví WITH CHECK, degradace + blokace v jednom UPDATE projde.
- **Oprava:** blok E7 — USING i WITH CHECK `role not in ('reditelka','rodic')`, `revoke update on uzivatele`, `grant update (jmeno, uvazek, zdravotni_prukaz, skoleni_hygieny)`; role/blokace jen přes funkce; trigger auditu (E19).

### E8 — Střední: vazby napříč školkami
- **Soubor:** `setup.sql:495` (`ut_menit` kontroluje jen třídu, ne učitelku), `:346` (`deti_menit` nekontroluje `trida_id`), `:499` (`doch_menit` nekontroluje `trida_dnes`), `:366` (`uraz_zapsat` nekontroluje `skola_id` ani `zapsal`).
- **Reprodukce:** ředitelka B `insert into ucitel_trida values ('<učitelka A>', '<Žabky B>')` → OK (učitelka A pak čte Adama vč. RČ); ředitelka A `update deti set trida_id='<Žabky B>' where id='<Ema>'` → učitelka B vidí Emu; totéž `dochazka.trida_dnes`; učitelka A vloží úraz své Emy se `skola_id=<B>` a `zapsal=<ředitelka B>` → OK.
- **Ověřeno:** SQL. Data jedné školky tak jdou „přistrčit“ uživateli jiné školky a kniha úrazů nese falešného zapisovatele.
- **Oprava:** blok E8 (WITH CHECK na školku třídy/uživatele, `uraz_zapsat … skola_id = moje_skola() and zapsal = auth.uid()`). Dlouhodobě složené FK `(trida_id, skola_id) references tridy(id, skola_id)`.

### E9 — Střední: rodič omlouvá zpětně a přepisuje „neomluven“
- **Soubor:** `supabase/setup.sql:781-811` (žádná kontrola `p_od` vůči dnešku; `where dochazka.stav <> 'pritomen'`).
- **Reprodukce:** rodič Olivera: `select * from omluv_dite('<Oliver>', current_date-7, current_date-7, 'zpětně');` → den 7. 10. se změní z `neomluven` na `omluven`; `omluv_dite(…, current_date-730, current_date-700, 'x')` → 23 nových řádků docházky před dvěma lety.
- **Ověřeno:** SQL i přes skutečný LifeOS klient (`omluv`).
- **Oprava:** blok E9 — rodič jen od dneška, `neomluven` nepřepíše.

### E10 — Střední: úraz z tabletu nejde zapsat
- **Soubor:** `server.js:246-251` (číslo = max z viditelných + 1), `setup.sql:365` (učitelka vidí jen úrazy dětí svých tříd), unikát `setup.sql:129`.
- **Reprodukce:** skutečný `server.js` jako učitelka Sluníček, když Berušky mají úraz č. 2: `uraz()` → `duplicate key value violates unique constraint "urazy_skola_id_rok_cislo_key"`. Totéž nastane při souběhu dvou tabletů.
- **Ověřeno:** spuštění `server.js` přes PostgREST (`klient-server.js`).
- **Oprava:** blok E10 — trigger `cislo_urazu()` (SECURITY DEFINER, advisory lock) přidělí číslo v DB; `server.js` má číslo číst z `insert … select('cislo')`. Po opravě `uraz()` projde.

### E11 — Střední: účet nejde smazat
- **Soubor:** `setup.sql:45` (`uzivatele → auth.users on delete cascade`) vs. `:92` (`zastupci.uzivatel_id`), `:127` (`urazy.zapsal`), `:605`, `:136`, `:270`, `:513`, `:652` — vše `NO ACTION`.
- **Reprodukce (postgres):** `delete from auth.users where id='<rodič Emy>'` → `violates foreign key constraint "zastupci_uzivatel_id_fkey"`; učitelka → `urazy_zapsal_fkey`. V Supabase tedy selže „Delete user“ v dashboardu i úklid anonymních účtů (a LifeOS je vyrábí, E20).
- **Ověřeno:** SQL.
- **Oprava:** `zastupci.uzivatel_id … on delete set null` (blok E11); u `zapsal/vytvoril/odeslal` buď `set null` (jméno je v `zapsal_jmeno`), nebo účty zaměstnanců jen deaktivovat a nemazat.

### E12 — Střední: smazání dítěte maže finanční záznamy
- **Soubor:** `setup.sql:174-176`, `:194-197`, `:241` (`on delete cascade` na `konta`, `predpisy`, `upominky`), `:346` (`deti_menit for all` = i DELETE).
- **Reprodukce:** ředitelka `delete from deti where id='<Oliver>'` (bez úrazu) → předpisy 0, konto 0, `ucetni_pohyby` s `dite:<Oliver>` zůstanou osiřelé.
- **Ověřeno:** SQL.
- **Oprava:** `on delete restrict` na `predpisy`, `konta`; `revoke delete on deti from authenticated` (dítě se ukončuje `ukonceno`). Blok E11/E12.

### E13 — Vysoká: finanční API ignoruje blokaci
- **Soubor:** `server/finance/api.py:61` (`select skola_id, role from uzivatele where id = %s` — bez `aktivni` a `skoly.stav`).
- **Reprodukce:** `fin_test.py` — hospodářka a6 s `aktivni=false` ve školce `blokovana`: `GET /finance/dluznici` → 200, `GET /finance/deti/<Ema>/konto` → 200 se saldem a předpisy.
- **Ověřeno:** FastAPI `TestClient` proti lokální DB `skolka_e` (stav po testu vrácen).
- **Oprava:** `select u.skola_id, u.role from uzivatele u join skoly s on s.id = u.skola_id where u.id = %s and u.aktivni and s.stav = 'aktivni'`.

### E14 — Střední: rodič ve dvou školkách vidí data a účet jiné školky
- **Soubor:** `setup.sql:562-564` (`on conflict (id) do nothing` — účet zůstane v první školce), `skolkaServer.ts:120-129` (`akce`, `zpravy`, `alba`, `financni_nastaveni?limit=1`, `skoly?limit=1` bez filtru dítěte/školky).
- **Reprodukce:** rodič Emy (A) uplatní kód Adama (B) → projde; `moje_skola()` = A; `omluv_dite(Adam)` projde; `jidelnicek_tyden` a `akce` vrací školku A. LifeOS pak u Adama ukáže jídelníček A a **číslo účtu školky A** pro platbu za Adama.
- **Ověřeno:** SQL. Navíc: kód určený konkrétnímu zástupci (`zastupce_id`) přepíše propojení původního rodiče bez upozornění (ověřeno — `zastupci.uzivatel_id` se změní).
- **Oprava:** blok E14 (odmítnout kód cizí školky) nebo v LifeOS filtrovat `skola_id` dítěte a v DB nahradit `moje_skola()` školkou dítěte.

### E15 — Střední: kódy bez limitu pokusů
- **Soubor:** `setup.sql:545-591`, `:743-755`; `vytvor_kod_rodice` `:523-542` (8 znaků z 32 = 40 bitů, bez zkreslení).
- **Reprodukce:** `enum.js` — jeden anonymní účet, 500 náhodných kódů na `rpc/nahled_kodu` za 1,2 s, všechny 400, nic se nezablokuje ani nezaloguje (`audit_log` beze změny). Platný kód vrátí jméno, příjmení, **datum narození**, školku a třídu.
- **Ověřeno:** HTTP. Jednorázovost a 14denní platnost ověřeny (druhé uplatnění i prošlý kód → chyba).
- **Hodnocení:** při 1 000 platných kódech ≈ 10⁹ pokusů na zásah → dnes nepraktické, ale bez jakékoli brzdy.
- **Oprava:** tabulka `pokusy_kodu(uid, kdy, ok)` + v obou funkcích `if (select count(*) from pokusy_kodu where uid = auth.uid() and kdy > now() - interval '1 hour' and not ok) >= 10 then raise …`; náhled bez data narození (stačí jméno + iniciála).

### E16 — Nízká: zprávy a seznam lidí
- **Soubor:** `setup.sql:406` (`zpravy_cist … skola_id = moje_skola()`), `:486` (`uziv_cist`).
- **Reprodukce:** rodič a kuchařka čtou zprávu `komu='ucitelky'` „Interní A — jen učitelky“ (i přes LifeOS `stahni`: `zpravy: 2`); učitelka/kuchařka/hospodářka čtou jména a e-maily celého personálu i jména rodičů.
- **Oprava:** `zpravy_cist using (skola_id = moje_skola() and (komu = 'vse' or je_vedeni() or (komu = 'ucitelky' and moje_role() in ('ucitelka','zastupce')) or (komu = 'rodice' and moje_role() = 'rodic')))` (podle skutečných hodnot `komu`); `uziv_cist` pro nevedení jen `role <> 'rodic'`.

### E17 — Nízká: funkce bez pevné `search_path`
- **Soubor:** `setup.sql:417` (`zapis_audit` SECURITY DEFINER bez `set search_path`); bez ní i `pohyb_do_konta`, `pohyby_jen_pridavat`, `je_kuchyne`, `je_finance`, `novy_kod` (`pg_proc.proconfig` NULL — ověřeno).
- **Riziko:** v Supabase nízké (role nemají CREATE v `public`), ale Supabase Advisor to hlásí a je to obrana do hloubky.
- **Oprava:** `alter function zapis_audit() set search_path = public;` atd. (blok E17).

### E18 — Nízká: výchozí granty Supabase na pozdě vytvořené tabulky
- **Soubor:** `setup.sql:739` (`revoke all on all tables … from anon` proběhne **před** vytvořením `superadmini`, `skoly_admin`, `pozvanky` na `:913-958`), `:1216-1218` revokuje jen funkce.
- **Reprodukce:** DB `skolka_e_m3` = stub + `alter default privileges in schema public grant all on tables/functions/sequences to anon, authenticated` (jako v Supabase) + `setup.sql` → `anon` má `INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER` na `pozvanky`, `skoly_admin`, `superadmini` a USAGE na `audit_log_id_seq`; funkce žádné. Řádky chrání RLS (SELECT vrací 0), ale TRUNCATE RLS nepodléhá (přes PostgREST nedostupné).
- **Ověřeno:** jen emulací výchozích práv (živý projekt nedostupný).
- **Oprava:** blok E18 — na konci `setup.sql` `revoke all on all tables in schema public from anon; revoke truncate, references, trigger on all tables in schema public from authenticated;` + `alter default privileges … revoke`.

### E19 — Nízká: mezery v `audit_log`
- **Soubor:** `setup.sql:417-430`, `:459-461`, `:721-722`, `:1213-1214`.
- **Stav (ověřeno `pg_trigger`):** audit mají `deti`, `zastupci`, `poverene_osoby`, `souhlasy`, `urazy`, `udalosti_ditete` (IUD), `predpisy`, `platby`, `nesparovane_platby` (jen U), `financni_nastaveni`, `parovaci_kody`, `pozvanky` (IU). **Chybí:** `uzivatele` (role, blokace — E7), `ucitel_trida`, `diety` (zdravotní), `dochazka`, `skoly` (stav, předplatné), `superadmini`. Akce superadmina se zapíšou se `skola_id = moje_skola()` = NULL → nikdo je nevidí. U tabulek bez sloupce `id` (`souhlasy`, `pozvanky`) je `zaznam` NULL (ověřeno na `souhlasy`).
- **Oprava:** blok E19 (triggery) + v `zapis_audit` brát školku z řádku (`coalesce(to_jsonb(new)->>'skola_id', …)`) a `zaznam` z primárního klíče.

### E20 — Nízká: LifeOS potichu založí nový účet
- **Soubor:** `lifeos-a/mobile/src/services/skolkaServer.ts:62-78`.
- **Reprodukce:** `refresh_test.js` — mock server vrátí na `/auth/v1/token` 400 → klient zavolá `/auth/v1/signup` a `mojeId()` se změní z `puvodni-rodic` na `NOVY-anonymni`. Rodič přijde o propojení bez vysvětlení, starý anonymní účet zůstane (a kvůli E11 nejde smazat). Totéž při 4xx z jiného důvodu (např. rate limit `/token`).
- **Ověřeno:** spuštěním skutečného přeloženého `skolkaServer.ts`.
- **Oprava:** zakládat nový účet jen při výslovném novém propojení kódem; při selhání refresh ukázat „Propojení vypršelo — zadejte nový kód“.

### E21 — Info: Storage a Edge Functions
V repozitáři školky ani LifeOS nejsou Edge Functions (`supabase/functions` neexistuje) ani definice Storage bucketů/politik (`storage.objects` se nikde nepoužívá). `alba.fotky` (`setup.sql:651`) ukládá „cesty v úložišti“ a LifeOS je čte (`skolkaServer.ts:122`), ale úložiště není. Před nahráváním fotek je nutné bucket **private** + politiky na `storage.objects` podle `alba.skola_id`/`rodic_tridy()` a podepsané URL.

### E22 — Info: migrace, konfigurace, klíče
- **Migrace (`migrace.sh`):** `setup.sql` na čisté DB projde (exit 0). Podruhé neprojde (`setup.sql:34 type "role_t" already exists`) — v souladu s hlavičkou „spouští se jednou“. Všechny tři `migrace-*.sql` jdou opakovaně (2× na DB ze `setup.sql`, 2× na staré verzi). Stará verze `schema.sql` + `pilot.sql` + migrace v pořadí dá **shodné schéma** jako `setup.sql` (`pg_dump --schema-only`, rozdíl jen v náhodném tokenu `\restrict`). `seed-pilot.sql` bez účtů skončí srozumitelnou chybou.
- **FK/indexy:** 36 cizích klíčů nemá index na prvním sloupci (např. `zastupci.dite_id`, `zastupci.uzivatel_id`, `urazy.dite_id`, `deti.trida_id`, `platby.dite_id`, `udalosti_ditete.skola_id`, `akce.skola_id`, `parovaci_kody.dite_id`, `jidelnicek.jidlo_id`) — `zastupci.uzivatel_id` a `zastupci.dite_id` jsou v `moje_dite()` pro rodiče na každém řádku každé politiky. Doporučení: `create index on zastupci (uzivatel_id, dite_id); create index on zastupci (dite_id); create index on deti (trida_id); create index on deti (skola_id); create index on urazy (dite_id); create index on dochazka (den, trida_dnes); create index on ucitel_trida (trida_id); create index on akce (skola_id, den); create index on alba (skola_id, den);`. Bez FK: `audit_log.skola_id/kdo`, `parovaci_kody.pouzil`, `pozvanky.prijal/vytvoril`, `vyzvednuti.zapsal` (pro audit/log přijatelné).
- **Testovací data v produkčním skriptu:** `setup.sql:773-774` aktualizuje děti podle pevných testovacích UUID; `seed-pilot.sql` zakládá smyšlenou školku a účty `@test.cz` v témže (produkčním) projektu `jokprqoifzjojbpozefh` → vývoj/pilot a provoz sdílejí jednu databázi. Testovací režim se do aplikace dostane jen přes přepsání `config.js` v Playwrightu (`testy/e2e/spolecne.js:25`), v produkčním kódu žádný přepínač `?test=` není (ověřeno grepem).
- **Klíče:** `config.js` i `skolkaServer.ts:15-18` obsahují jen URL a `sb_publishable_…`. `git log -p --all` (59 commitů školky, 68 LifeOS): žádný `sb_secret_…`, `service_role` klíč ani JWT (`eyJ…`); jediný výskyt `sb_secret_` je kontrola prefixu v minifikovaném `vendor/supabase-2.115.0.js`. `server/finance` čte `DATABASE_URL` a `SUPABASE_JWT_SECRET` z prostředí (v repu jen testovací hodnota v `server/tests/test_pg_api.py:45`). Pozn.: `api.py` ověřuje HS256 sdíleným tajemstvím — u nových projektů Supabase s asymetrickými JWT klíči je potřeba přejít na JWKS.

## 5. Nesoulad schématu a klientů (reálná volání přes PostgREST)

- **`server.js`** (spuštěn skutečný soubor, `klient-server.js`): 30 volání pod učitelkou, kuchařkou, ředitelkou, superadminem a hospodářkou — všechny tabulky, sloupce, embedy (`tridy(nazev, barva)`, `zastupci(...)`) i RPC s parametry existují. **Jediné selhání:** `uraz()` (E10). Po `oprava-navrh.sql` 30/30 OK.
- **LifeOS `skolkaServer.ts`** (přeložený skutečný soubor, `klient-lifeos.js`, anonymní účet přes `/auth/v1/signup`): `nahled_kodu`, `uplatni_kod`, 12 dotazů `stahni`, `omluv_dite`, POST `vyzvednuti`, `potvrd_udalosti`, `uprav_udaje_rodicem` — 9/9 OK před i po opravách. Logické nesoulady: E14 (dotazy bez filtru školky), E20 (refresh). Zastaralý komentář `server.js:80-81` („značky na serveru zatím nejsou“) — sloupec `deti.znacka` existuje a čte se.
- Realtime: `sleduj()` odebírá `dochazka`, `vyzvednuti`, `udalosti_ditete` bez filtru; všechny jsou v publikaci (`setup.sql:725`) a Supabase Realtime filtruje podle RLS — lokálně neověřitelné (stub nemá Realtime).
