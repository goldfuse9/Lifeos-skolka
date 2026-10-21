# Zdraví dítěte ve školce — léky a kniha podání

Databáze: `supabase/migrace-2026-10-22-zdravi.sql` (po migraci `2026-10-21-finance`).

## Jak to funguje

1. **Rodič v LifeOS** u léku dítěte zapne **Podávat ve školce**, vybere čas
   (10:00, po obědě…) nebo **Při potížích** a může napsat, co dělat při potížích.
   Při prvním zapnutí (a při každé změně dávky, času nebo pokynu) potvrdí
   **dohodu se školkou** — jméno a čas se uloží u léku ve školce.
2. **Tablet učitelky** v čas podání ukáže nahoře pruh **Teď podat** se dvěma
   tlačítky: **Podáno** a **Nepodáno** (důvod: odmítlo / není ve třídě / lék
   chybí). Po 15 minutách pruh zčervená. Lék „při potížích“ je na kartě
   dítěte pod tlačítkem **Podat teď** i s pokynem rodičů. Omyl jde do 15 minut
   vrátit (v knize zůstane jako zrušený).
3. **Rodič** vidí v LifeOS → Školka → **Zdraví ve školce**, co učitelka dnes
   podala; při „nepodáno“ dostane oznámení (na zamčené obrazovce bez názvu léku).
4. **Ředitelna → Zdraví a léky**: přehled dětí s léky, alergiemi a omezeními,
   upozornění (lék chybí, opakovaně nepodáno, lék končí, není vyplněno, kde je
   lék) a **kniha podání** k tisku / do PDF za měsíc.

## Kdo co vidí

| Role | Vidí | Smí |
|---|---|---|
| rodič | jen své dítě | poslat / vypnout lék, postup a omezení |
| učitelka | děti svých tříd (i dnes přesunuté) | zapsat podání, doplnit, kde je lék |
| ředitelka, zástupkyně | celá školka | totéž + kniha podání |
| hospodářka, kuchařka | nic | nic (kuchyně dál jen alergeny jídel) |

Tabulky se z aplikací jen čtou; zapisuje se výhradně funkcemi
`posli_lek_skolce`, `zrus_lek_ve_skolce`, `uprav_zdravi_rodicem`,
`zapis_podani`, `zrus_podani`, `uloz_ulozeni_leku`. Kniha podání nejde smazat
ani přepsat; všechny změny jdou i do auditu.

## Nasazení

V Supabase → SQL Editor spusťte `supabase/migrace-2026-10-22-zdravi.sql`.
Jde spustit opakovaně. Bez ní tablet i ředitelna fungují dál, jen stránka
Zdraví a léky ukáže, že úprava databáze chybí.

## Testy

- `testy/bezpecnost.sh` — sekce „zdraví“ (cizí škola, třída, rodič, role, anonym)
- `node testy/e2e/spust.js zdravi` — tablet (Teď podat, Nepodáno, Vrátit, Podat teď) a ředitelna
