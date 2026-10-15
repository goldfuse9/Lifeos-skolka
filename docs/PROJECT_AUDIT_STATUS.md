# LifeOS + Školka — stav auditu a dokončování

Průběžně aktualizovaný dokument (pro pokračování po přerušení). Poslední aktualizace: 14. 10. 2026 — **audit dokončen, čeká na sloučení PR a nasazení migrace**.

## 1. Systém

| Část | Repozitář / soubor | Běží |
| --- | --- | --- |
| LifeOS (rodiče, mobil) | `goldfuse9/lifeos`, větev `faze-1-mobil` (+ PR z `audit-skolka`), `mobile/` | iPhone/Android přes `npx expo run:*` |
| Správa LifeOS (superadmin) | `goldfuse9/Lifeos-skolka` `Admin.dc.html` | Netlify, `#admin` |
| Ředitelna | `Reditel.dc.html` | `#reditel` |
| Tablet třídy | `Trida.dc.html` | `#trida` |
| Jídelna | `Jidelna.dc.html` | `#jidelna` |
| Přihlášení | `Prihlaseni.dc.html` + `shell.js` | `#prihlaseni` |
| Napojení na server | `server.js` + `config.js` + `vendor/supabase-2.115.0.js` | Supabase `jokprqoifzjojbpozefh` (Frankfurt) |
| Databáze | `supabase/setup.sql` (= vše), migrace `supabase/migrace-*.sql` | Supabase |
| Finance (server) | `server/finance` (Python, FastAPI) | zatím nenasazeno |
| Testovací režim | `testy/` | lokálně / v kontejneru |

## 2. Testovací režim — jak spustit

Lokální náhrada Supabase (PostgreSQL 16 + PostgREST 12 + mini-proxy pro `/auth/v1`). **Nikdy se nepřipojuje ke skutečnému projektu** — testy přesměrují `config.js` na lokální proxy. Data jsou smyšlená.

```bash
testy/lokalni/stack.sh                 # spustí databázi, PostgREST, proxy a web (skolka_lokal, porty 3001/3002/8767)
testy/reset.sh                         # obnoví výchozí testovací data (dvě školky, všechny role)
testy/spust-vse.sh                     # celý testovací cyklus (bezpečnost DB + E2E + finance + LifeOS)
LIFEOS_DIR=…/lifeos/mobile testy/spust-vse.sh   # s LifeOS jinde než výchozí cesta
```

- Aplikace v testovacím režimu ručně: `http://localhost:8767/index.html` s `config.js` mířícím na `http://localhost:3002` (testy to dělají samy přes `testy/e2e/spolecne.js → stranka()`).
- Testovací účty (`testy/data.sql`, lokálně projde libovolné heslo): `reditelka@test.cz`, `zastupce@test.cz`, `ucitelka@test.cz` (Sluníčka), `ucitelka2@test.cz` (Berušky), `hospodarka@test.cz`, `kucharka@test.cz`, školka B: `reditelka.b@test.cz`, `ucitelka.b@test.cz`; superadmin `roman@lifeos.cz`; rodiče jsou anonymní účty (kód vydá ředitelka). E-maily `…@potvrdit.test` vyžadují potvrzení (jako výchozí Supabase).
- Zkušební provoz bez serveru (ukázková data v prohlížeči) funguje dál — test `e2e/zkusebni.js`.

### Jak spustit testovací agenty znovu
1. `git worktree add /home/claude/skolka-audit HEAD` (zmrazená kopie pro agenty).
2. Každý agent dostane vlastní instanci: `testy/lokalni/stack.sh skolka_X 30X1 30X2 88X1` a `testy/reset.sh skolka_X` (žádné střety).
3. Zadání agentů A–F a regresního agenta R jsou v hlavičkách zpráv `docs/audit-2026-10-14/agent-*.md` (role, rozsah, výstup). Agent smí jen testovat, kód nemění; výstup do `…/scratchpad/audit/<X>.md`.

## 3. Výsledky automatických testů (14. 10. 2026, po všech opravách)

| Sada | Výsledek |
| --- | --- |
| `testy/bezpecnost.sh` — oprávnění v DB pod skutečnými identitami | **123/123 PASS** (před auditem 70/106) |
| `testy/e2e/*` — Playwright: superadmin, přístupy, pozvánka s potvrzením, tablet↔rodič↔ředitelna, úložiště prohlížeče, ředitelna, jídelna, tablet, účet, zkušební provoz | **114/114 PASS** |
| Finance API (pytest nad PostgreSQL) | **11/11 PASS** |
| LifeOS ↔ server (Jest integrace) | **6/6 PASS** |
| LifeOS typecheck / lint / Jest | 0 chyb / 0 varování / 113 PASS, 2 skip (integrace bez URL) |
| Migrace `2026-10-14-audit` na DB ze staré verze (před auditem) i opakovaně | bez chyb (ověřil regresní agent) |
| Nezávislý regresní audit (agent R) | všechny původní kritické/vysoké nálezy ověřeny jako opravené; 18 nových (R1–R18) → opraveny kromě níže uvedených |

### Doplněk 14. 10. 2026 večer — zprávy jako komunikační kanál

Rodič (LifeOS) ↔ učitelka (tablet, záložka Zprávy) ↔ vedení (ředitelna, Zprávy).
Migrace `supabase/migrace-2026-10-14b-zpravy.sql`: vlákna (`odpoved_na`),
odesílatel doplněný databází, kanál `vedeni:<uid>`, přečtení/potvrzení
(`zpravy_precteni`, `precti_zpravy`, `potvrzeni_zprav`). Odpověď rodiče na zprávu
celé třídě vidí jen školka. Testy po doplňku: bezpečnost **156/156**, E2E **141/141**
(nový `e2e/zpravy.js`), finance 11/11, LifeOS integrace **8/8**, LifeOS Jest 115 PASS.

## 4. Inventář modulů a stav funkcí

Stavy: OVĚŘENO (test prošel), OPRAVENO (oprava + test), NEOVĚŘENO, BLOKOVÁNO, CHYBÍ, SELHÁVÁ.

### Přihlášení a účty
| Funkce | Stav |
| --- | --- |
| Přihlášení e-mail+heslo do Ředitelny/Třídy/Jídelny/#admin podle role | OVĚŘENO |
| Pozvánky (superadmin → ředitelka, ředitelka → zaměstnanci), registrace s kódem, potvrzení e-mailu | OVĚŘENO / OPRAVENO (smyčka „potvrďte e-mail“) |
| Zapomenuté heslo → formulář Nové heslo | OPRAVENO |
| Blokace účtu/školky — při přihlášení, při obnovení stránky, během práce | OPRAVENO |
| Dvě záložky s různými účty | OPRAVENO |
| Data v prohlížeči po odhlášení (ostrý provoz) | OPRAVENO (nic v localStorage) |
| Skutečný e-mail ze Supabase (doručení, šablony) | NEOVĚŘENO (jen proti živému projektu) |

### Správa LifeOS (superadmin)
| Funkce | Stav |
| --- | --- |
| Školky, stav, tarif, předplatné, poznámka, ředitelky, pozvánky | OVĚŘENO |
| Superadmin nevidí data dětí | OVĚŘENO |

### Ředitelna (ostrý provoz)
| Funkce | Stav |
| --- | --- |
| Přehled (dnes ve školce, PPV, kniha úrazů, obsazenost, úkoly) | OPRAVENO (ze serveru) |
| Kartotéka: čtení, úprava, nové dítě, zástupci, pověřené osoby, souhlasy, import | OPRAVENO (ze serveru) |
| Rodná čísla a osobní údaje jen vedení | OPRAVENO |
| Docházka (měsíční souhrn, dnešek z tabletů) | OPRAVENO |
| Třídy, přiřazení učitelek | OPRAVENO |
| Kniha úrazů (z tabletu, číslování DB, záznam pro ČŠI ke stažení) | OPRAVENO |
| Zprávy rodičům (do aplikace, podle adresáta) | OPRAVENO |
| Rodiče v LifeOS (kódy), Přístupy | OVĚŘENO |
| Zápis, Platby, Matrika MŠMT, Dokumenty, Web, Porady, Archiv, Nastavení, Učitelé | CHYBÍ v ostrém provozu (skryté; ve zkušebním provozu fungují nad ukázkovými daty) |
| Odeslání záznamu o úrazu ČŠI / e-maily rodičům | CHYBÍ (ručně; aplikace to říká) |

### Jídelna (ostrý provoz)
| Funkce | Stav |
| --- | --- |
| Jídelníček ze serveru, návrh i zveřejnění po chodech, změny po zveřejnění, vyprázdnění | OPRAVENO |
| Počty obědů podle tříd + odhlášky z omluvenek | OPRAVENO |
| Diety (děti s alergií ze serveru, doložení lékaře) | OPRAVENO |
| Náhrady po dnech; vypnutí náhrad je skryje, nesmaže | OPRAVENO |
| Katalog jídel a surovin (na serveru, JSON) | OPRAVENO |
| Kuchařky (ZP, hygiena), sklad, platby stravného | CHYBÍ v ostrém provozu (skryté) |
| Pestrost týdne u jídel ze serveru (kategorie) | SELHÁVÁ drobně (R17 — počítá jen jídla z katalogu) |

### Tablet třídy (ostrý provoz)
| Funkce | Stav |
| --- | --- |
| Příchod/odchod/vyzvednutí, omluvenky a potvrzení, události, úraz | OVĚŘENO |
| Oběd a alergie z dnešního jídelníčku | OPRAVENO |
| „Přesto přišel“, Vrátit, výpadek sítě, půlnoc | OPRAVENO |
| Třídní kniha | OPRAVENO (na serveru) |
| Fotky, Akce, Schůzky | CHYBÍ v ostrém provozu (skryté) |
| Pověřené osoby na tabletu; přepínání tříd; zástupkyně bez třídy | CHYBÍ (D7, D11) |
| Tablet bez sítě (offline režim) | CHYBÍ |

### LifeOS — karta Školka
| Funkce | Stav |
| --- | --- |
| Propojení kódem, stažení dat, omluvenka, vyzvednutí, přečtení, úprava údajů | OVĚŘENO (integrace) |
| Relace: žádné tiché nové účty, jedna obnova tokenu | OPRAVENO |
| Zápisy až po přijetí školkou (offline nic falešného) | OPRAVENO (logika; UI na zařízení NEOVĚŘENO) |
| Zablokovaná školka / zrušené propojení — data se nepřepíšou | OPRAVENO |
| Odpojit / Odebrat kartu / Smazat vše ruší propojení i token | OPRAVENO |
| Oznámení bez zdravotních podrobností | OPRAVENO (na zařízení NEOVĚŘENO) |
| Rodič s dětmi ve dvou školkách | CHYBÍ (zatím odmítnuto srozumitelnou hláškou) |
| Build iOS/Android, šifrování SQLCipher, SecureStore, push | NEOVĚŘENO (v kontejneru nejde) |

### Databáze a backend
| Oblast | Stav |
| --- | --- |
| RLS všech 38+ tabulek, oddělení školek, citlivé sloupce, IDOR přes RPC | OVĚŘENO (123 testů) |
| Bezpečnostní nálezy E1–E19, F1–F12, C10–C11, D4, D9, R5–R7, R10 | OPRAVENO |
| Finanční API — blokace | OPRAVENO |
| Storage, Edge Functions | v projektu nejsou (fotky alb nemají úložiště) |

## 5. Zbývající problémy a proč nejsou vyřešené

| # | Problém | Proč |
| --- | --- | --- |
| Z1 | Nenapojené stránky (web, archiv — Učitelé, Porady, Zápis, Dokumenty, Platby, Nastavení a Matrika už napojené 15. 10.; jídelna: kuchařky, sklad; tablet: fotky, akce, schůzky) jsou v ostrém provozu skryté | Rozsah — každá potřebuje vlastní datový model a návrh rozhraní; skrytí brání falešným datům a „uložení“ jen do prohlížeče |
| Z2 | Limit pokusů o kód rodiče jde obejít novými anonymními účty (R4) | Globální limit potřebuje nastavení Supabase (CAPTCHA / limit anonymních registrací) nebo Edge Function → **BLOKOVÁNO: rozhodnutí a nastavení v Supabase** |
| Z3 | Rodič s dětmi ve dvou školkách | Vyžaduje změnu modelu (škola podle dítěte místo účtu) |
| Z4 | Omluvené dítě, které přesto přišlo, má oběd odhlášený | Záměr: kuchyně už oběd neobjedná; tablet učitelku upozorní |
| Z5 | Stejný chod upravený ve dvou deskách současně — vyhraje poslední | Různé chody se už nepřepisují (R9); úplné zamykání by bylo nad rámec |
| Z6 | Živý Supabase z testovacího prostředí nedostupný | Migraci a chování proti živé DB ověří uživatel podle návodu v PR |
| Z7 | Push na iPhone | Chybí placený Apple Developer účet |

## 6. Kde jsou zprávy agentů

`docs/audit-2026-10-14/agent-A.md` (LifeOS), `agent-B.md` (Ředitelna), `agent-C.md` (Jídelna), `agent-D.md` (Tablet), `agent-E.md` (Supabase/backend), `agent-F.md` (nezávislé QA, zpráva zkrácená bezpečnostním filtrem u F9+), `agent-R-regrese.md` (nezávislý regresní audit po opravách).

## 7. Další krok

1. Sloučit PR školky (větev `audit`) a PR LifeOS (větev `audit-skolka` → `faze-1-mobil`).
2. V Supabase spustit `supabase/migrace-2026-10-14-audit.sql` a pak `supabase/migrace-2026-10-14b-zpravy.sql` (obě jdou spustit opakovaně).
3. V Supabase zvážit CAPTCHA / limit anonymních registrací (Z2).
4. Další vývoj: napojit skryté stránky (Z1) — po jedné, se stejným vzorem (model ze serveru, srvSync, test v `testy/e2e`).

Pokračování po přerušení: přečíst tento soubor, `git status` v repozitáři, `testy/spust-vse.sh`.
