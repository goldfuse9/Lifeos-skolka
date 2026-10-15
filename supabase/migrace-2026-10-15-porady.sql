-- =============================================================================
-- Školka — doplněk 15. 10. 2026: PORADY (zápisy z pedagogických rad a porad).
-- Spusťte v Supabase → SQL Editor po migraci 2026-10-14b. Jde spustit opakovaně.
--
-- Zápisy čte vedení a učitelky školky, zapisuje je jen vedení (ředitelka,
-- zástupkyně). Zápis je dokument: po uložení se nedá měnit ani mazat.
-- =============================================================================

drop policy if exists porady on porady;
drop policy if exists porady_cist on porady;
create policy porady_cist on porady for select
  using (moje_role() in ('reditelka', 'zastupce', 'ucitelka') and skola_id = moje_skola());
drop policy if exists porady_psat on porady;
create policy porady_psat on porady for insert
  with check (moje_role() in ('reditelka', 'zastupce') and skola_id = moje_skola());
revoke update, delete, truncate on porady from authenticated, anon;

-- rozumné meze (nové řádky; případné starší se nekontrolují zpětně)
alter table porady drop constraint if exists porady_delka;
alter table porady add constraint porady_delka check (
  length(btrim(program)) between 1 and 8000
  and length(coalesce(usneseni, '')) <= 8000
  and length(btrim(druh)) between 1 and 80
  and coalesce(array_length(pritomni, 1), 0) <= 200
) not valid;
