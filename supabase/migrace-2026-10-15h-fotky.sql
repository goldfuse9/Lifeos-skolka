-- =============================================================================
-- Školka — doplněk 15. 10. 2026 (h): FOTKY tříd v úložišti (Supabase Storage).
-- Spusťte v Supabase → SQL Editor po migraci 2026-10-15g-akce. Jde spustit opakovaně.
--
-- Soubory:  úložiště „fotky“ (soukromé), cesta <škola>/<třída>/<album>/<soubor>.jpg
-- Alba:     tabulka alba; rodiče vidí jen zveřejněná alba třídy svého dítěte.
-- Nahrává a maže vedení a učitelka té třídy. Odkazy na fotky jsou dočasné
-- (podepsané) — fotka se nedá sdílet natrvalo ani najít bez přihlášení.
-- =============================================================================

alter table alba add column if not exists zverejneno timestamptz;
alter table alba drop constraint if exists alba_hodnoty;
alter table alba add constraint alba_hodnoty check (
  length(btrim(nazev)) between 1 and 120 and length(coalesce(popis, '')) <= 2000
  and coalesce(array_length(fotky, 1), 0) <= 300
) not valid;
create index if not exists alba_trida_den on alba (trida_id, den desc);

drop policy if exists alba_cist on alba;
create policy alba_cist on alba for select using (
  skola_id = moje_skola() and (moje_role() <> 'rodic' or (zverejneno is not null and rodic_tridy(trida_id)))
);
drop policy if exists alba_menit on alba;
create policy alba_menit on alba for all
  using (skola_id = moje_skola() and moje_role() <> 'rodic' and (je_vedeni() or je_ucitelka_tridy(trida_id)))
  with check (skola_id = moje_skola() and moje_role() <> 'rodic' and (je_vedeni() or je_ucitelka_tridy(trida_id)));

drop trigger if exists a_alba on alba;
create trigger a_alba after insert or update or delete on alba for each row execute function zapis_audit();

-- úložiště: soukromé, jen obrázky do 5 MB (fotky se zmenšují už na tabletu)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('fotky', 'fotky', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- kdo smí fotku vidět / spravovat — podle alba v cestě <škola>/<třída>/<album>/…
create or replace function smi_videt_fotku(p_name text) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from alba a
    where a.id::text = split_part(p_name, '/', 3) and a.trida_id::text = split_part(p_name, '/', 2)
      and a.skola_id::text = split_part(p_name, '/', 1) and a.skola_id = moje_skola()
      and (moje_role() <> 'rodic' or (a.zverejneno is not null and rodic_tridy(a.trida_id))))
$$;
create or replace function smi_spravovat_fotku(p_name text) returns boolean language sql stable security definer set search_path = public as $$
  select moje_role() is not null and moje_role() <> 'rodic' and exists (select 1 from alba a
    where a.id::text = split_part(p_name, '/', 3) and a.trida_id::text = split_part(p_name, '/', 2)
      and a.skola_id::text = split_part(p_name, '/', 1) and a.skola_id = moje_skola()
      and (je_vedeni() or je_ucitelka_tridy(a.trida_id)))
$$;
revoke execute on function smi_videt_fotku(text), smi_spravovat_fotku(text) from anon, public;
grant execute on function smi_videt_fotku(text), smi_spravovat_fotku(text) to authenticated;

drop policy if exists skolka_fotky_cist on storage.objects;
create policy skolka_fotky_cist on storage.objects for select to authenticated using (bucket_id = 'fotky' and public.smi_videt_fotku(name));
drop policy if exists skolka_fotky_nahrat on storage.objects;
create policy skolka_fotky_nahrat on storage.objects for insert to authenticated with check (bucket_id = 'fotky' and public.smi_spravovat_fotku(name));
drop policy if exists skolka_fotky_smazat on storage.objects;
create policy skolka_fotky_smazat on storage.objects for delete to authenticated using (bucket_id = 'fotky' and public.smi_spravovat_fotku(name));
