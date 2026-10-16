-- =============================================================================
-- Školka — doplněk 16. 10. 2026: LOGO ŠKOLKY v hlavičce tištěných dokumentů.
-- Spusťte v Supabase → SQL Editor po migraci 2026-10-15h-fotky. Jde spustit opakovaně.
--
-- skoly.logo   malý obrázek (PNG / JPEG / WebP jako data URL, do ~150 kB);
--              zmenšuje se už v prohlížeči. SVG ani odkazy ven se nepřijímají.
-- Mění ho vedení školy v Nastavení (stejně jako ostatní údaje školky).
-- =============================================================================

alter table skoly add column if not exists logo text;
alter table skoly drop constraint if exists skoly_logo;
alter table skoly add constraint skoly_logo check (
  logo is null or (length(logo) <= 200000 and logo ~ '^data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/]+={0,2}$')
) not valid;
grant update (logo) on skoly to authenticated;
