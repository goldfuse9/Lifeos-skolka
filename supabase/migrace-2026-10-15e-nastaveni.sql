-- =============================================================================
-- Školka — doplněk 15. 10. 2026 (e): NASTAVENÍ ŠKOLKY na serveru.
-- Spusťte v Supabase → SQL Editor po migraci 2026-10-15d-platby. Jde spustit opakovaně.
--
-- Údaje školky pro matriku, dokumenty a web (adresa, IČO, kontakty…) a
-- pravidla plateb (omluvenky, variabilní symboly). Mění je vedení školy;
-- stav školky a předplatné dál jen správce LifeOS (trigger hlidej_skolu).
-- =============================================================================

alter table skoly add column if not exists kratky_nazev text;
alter table skoly add column if not exists ico text;
alter table skoly add column if not exists zrizovatel text;
alter table skoly add column if not exists adresa text;
alter table skoly add column if not exists telefon text;
alter table skoly add column if not exists email text;
alter table skoly add column if not exists datovka text;
alter table skoly add column if not exists web text;
alter table skoly add column if not exists ucet text;
alter table skoly add column if not exists poverenec text;
alter table skoly add column if not exists provozni_doba text;
alter table skoly add column if not exists uredni_hodiny text;
alter table skoly add column if not exists druh_provozu char(1) not null default 'C';
alter table skoly drop constraint if exists skoly_udaje;
alter table skoly add constraint skoly_udaje check (
  druh_provozu in ('C', 'P', 'I')
  and rozliseni in ('bez', 'lesni', 'firemni')
  and length(btrim(nazev)) between 1 and 200
  and length(coalesce(kratky_nazev, '')) <= 80 and length(coalesce(ico, '')) <= 20
  and length(coalesce(zrizovatel, '')) <= 200 and length(coalesce(adresa, '')) <= 200
  and length(coalesce(telefon, '')) <= 40 and length(coalesce(email, '')) <= 120
  and length(coalesce(datovka, '')) <= 20 and length(coalesce(web, '')) <= 120
  and length(coalesce(ucet, '')) <= 40 and length(coalesce(poverenec, '')) <= 200
  and length(coalesce(provozni_doba, '')) <= 40 and length(coalesce(uredni_hodiny, '')) <= 200
  and length(coalesce(kontakt, '')) <= 200 and length(izo) <= 20 and length(red_izo) <= 20 and length(cast_skoly) <= 4
) not valid;

-- údaje mění vedení: jen tyto sloupce (stav, tarif, předplatné ne)
revoke update on skoly from authenticated;
grant update (nazev, kratky_nazev, ico, izo, red_izo, cast_skoly, zrizovatel, rozliseni, adresa, telefon, email, datovka, web, ucet,
  poverenec, provozni_doba, uredni_hodiny, druh_provozu, doba_provozu, kontakt, nahrady_obedu) on skoly to authenticated;

-- nastavení plateb i s omluvenkami a variabilními symboly (nepovinné parametry)
drop function if exists uloz_financni_nastaveni(text, numeric, numeric, numeric, int);
create or replace function uloz_financni_nastaveni(p_ucet text, p_skolkovne numeric, p_stravne_36 numeric, p_stravne_7 numeric, p_splatnost int,
  p_omluva_dni int default null, p_omluva_do time default null, p_vs_schema text default null, p_vs_prefix text default null, p_vs_delka int default null)
returns void language plpgsql security definer set search_path = public as $$
declare s uuid := moje_skola();
begin
  if moje_role() not in ('reditelka', 'zastupce') then raise exception 'Ceny a účet nastavuje vedení školy.'; end if;
  if coalesce(btrim(p_ucet), '') = '' or length(p_ucet) > 40 then raise exception 'Vyplňte číslo účtu školky.'; end if;
  if p_skolkovne is null or p_skolkovne < 0 or p_skolkovne > 100000 then raise exception 'Neplatná výše školkovného.'; end if;
  if p_stravne_36 is null or p_stravne_36 < 0 or p_stravne_36 > 1000 or p_stravne_7 is null or p_stravne_7 < 0 or p_stravne_7 > 1000 then raise exception 'Neplatná cena stravného.'; end if;
  if p_splatnost is null or p_splatnost not between 1 and 28 then raise exception 'Splatnost musí být 1.–28. den v měsíci.'; end if;
  if p_omluva_dni is not null and p_omluva_dni not between 0 and 7 then raise exception 'Neplatná uzávěrka omluvenek.'; end if;
  if p_vs_schema is not null and p_vs_schema not in ('rok_poradi', 'prefix_poradi', 'rucne') then raise exception 'Neplatné přidělování VS.'; end if;
  if p_vs_prefix is not null and p_vs_prefix !~ '^[0-9]{0,6}$' then raise exception 'Předčíslí VS: nejvýš 6 číslic.'; end if;
  if p_vs_delka is not null and p_vs_delka not between 4 and 10 then raise exception 'VS má 4 až 10 číslic.'; end if;
  insert into financni_nastaveni (skola_id, ucet, skolkovne, splatnost_den, omluva_dni_predem, omluva_do, vs_schema, vs_prefix, vs_delka)
  values (s, btrim(p_ucet), round(p_skolkovne, 2), p_splatnost, coalesce(p_omluva_dni, 1), coalesce(p_omluva_do, '08:00'),
          coalesce(p_vs_schema, 'rok_poradi'), coalesce(p_vs_prefix, ''), coalesce(p_vs_delka, 6))
  on conflict (skola_id) do update set ucet = excluded.ucet, skolkovne = excluded.skolkovne, splatnost_den = excluded.splatnost_den,
    omluva_dni_predem = coalesce(p_omluva_dni, financni_nastaveni.omluva_dni_predem), omluva_do = coalesce(p_omluva_do, financni_nastaveni.omluva_do),
    vs_schema = coalesce(p_vs_schema, financni_nastaveni.vs_schema), vs_prefix = coalesce(p_vs_prefix, financni_nastaveni.vs_prefix),
    vs_delka = coalesce(p_vs_delka, financni_nastaveni.vs_delka);
  insert into sazby_stravneho (skola_id, kategorie, cena) values (s, '3-6', round(p_stravne_36, 2)), (s, '7+', round(p_stravne_7, 2))
  on conflict (skola_id, kategorie) do update set cena = excluded.cena;
end $$;
revoke execute on function uloz_financni_nastaveni(text, numeric, numeric, numeric, int, int, time, text, text, int) from anon, public;
grant execute on function uloz_financni_nastaveni(text, numeric, numeric, numeric, int, int, time, text, text, int) to authenticated;
