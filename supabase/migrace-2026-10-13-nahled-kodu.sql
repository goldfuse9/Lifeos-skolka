-- Školka — doplněk 13. 10. 2026: náhled kódu pro rodiče.
-- LifeOS před propojením ukáže, kterému dítěti kód patří, a rodič to potvrdí.
-- Spusťte jednou v Supabase → SQL Editor (po setup.sql).
create or replace function nahled_kodu(p_kod text)
returns table (jmeno text, prijmeni text, datum_narozeni date, skola text, trida text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if auth.uid() is null then raise exception 'Nejste přihlášeni.'; end if;
  return query
    select d.jmeno, d.prijmeni, d.datum_narozeni, s.nazev, t.nazev
    from parovaci_kody k join deti d on d.id = k.dite_id join skoly s on s.id = k.skola_id left join tridy t on t.id = d.trida_id
    where k.kod = upper(regexp_replace(coalesce(p_kod, ''), '[^A-Za-z0-9]', '', 'g'))
      and k.pouzito is null and k.zruseno is null and k.plati_do > now();
  if not found then raise exception 'Kód neplatí — je překlepnutý, použitý nebo starší než 14 dní. Požádejte ve školce o nový.'; end if;
end $$;
revoke execute on function nahled_kodu(text) from public, anon;
grant execute on function nahled_kodu(text) to authenticated;
