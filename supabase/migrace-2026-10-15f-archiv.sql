-- =============================================================================
-- Školka — doplněk 15. 10. 2026 (f): ARCHIV (spisový a skartační plán, záznam změn).
-- Spusťte v Supabase → SQL Editor po migraci 2026-10-15e-nastaveni. Jde spustit opakovaně.
--
-- skoly.skartacni_plan   lhůty uložení podle druhu dokumentu ({"Třídní knihy": 10, …})
-- archiv_zmen()          kdo, kdy a co změnil — z audit_log, bez osobních údajů
-- Nové tabulky (žádosti, porady, kroky zápisu, schválené dokumenty) se zapisují do audit_log.
-- =============================================================================

alter table skoly add column if not exists skartacni_plan jsonb;
alter table skoly drop constraint if exists skoly_plan;
alter table skoly add constraint skoly_plan check (
  skartacni_plan is null or (jsonb_typeof(skartacni_plan) = 'object' and length(skartacni_plan::text) <= 4000)
) not valid;
grant update (skartacni_plan) on skoly to authenticated;

drop trigger if exists a_zadosti on zadosti;
create trigger a_zadosti after insert or update on zadosti for each row execute function zapis_audit();
drop trigger if exists a_porady on porady;
create trigger a_porady after insert on porady for each row execute function zapis_audit();
drop trigger if exists a_zapis_rocnik on zapis_rocnik;
create trigger a_zapis_rocnik after insert or update on zapis_rocnik for each row execute function zapis_audit();
drop trigger if exists a_dokumenty_verze on dokumenty_verze;
create trigger a_dokumenty_verze after insert on dokumenty_verze for each row execute function zapis_audit();

-- záznam změn pro ředitelnu: jméno toho, kdo změnu udělal, a jen neosobní upřesnění
create or replace function archiv_zmen(p_limit int default 300)
returns table (kdy timestamptz, kdo text, tabulka text, akce text, zaznam text, dite uuid, detail text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not je_vedeni() then raise exception 'Archiv vidí vedení školy.'; end if;
  return query
  select a.kdy,
         coalesce(u.jmeno, case when a.kdo is null then 'systém' else 'neznámý účet' end),
         a.tabulka, a.akce, a.zaznam,
         case when a.tabulka = 'deti' then nullif(a.zaznam, '')::uuid
              else nullif(coalesce(a.zmena -> 'po' ->> 'dite_id', a.zmena ->> 'dite_id'), '')::uuid end,
         case a.tabulka
           when 'zadosti' then coalesce(a.zmena -> 'po' ->> 'reg_cislo', a.zmena ->> 'reg_cislo')
           when 'dokumenty_verze' then (a.zmena ->> 'klic') || ', verze ' || (a.zmena ->> 'verze')
           when 'porady' then (a.zmena ->> 'druh') || ' ' || (a.zmena ->> 'den')
           when 'predpisy' then coalesce(a.zmena -> 'po' ->> 'obdobi', a.zmena ->> 'obdobi')
           when 'urazy' then 'č. ' || coalesce(a.zmena -> 'po' ->> 'cislo', a.zmena ->> 'cislo')
           when 'zapis_rocnik' then 'rok ' || coalesce(a.zmena -> 'po' ->> 'rok', a.zmena ->> 'rok')
           else null end
    from audit_log a
    left join uzivatele u on u.id = a.kdo
   where a.skola_id = moje_skola()
   order by a.kdy desc, a.id desc
   limit least(greatest(coalesce(p_limit, 300), 1), 1000);
end $$;
revoke execute on function archiv_zmen(int) from anon, public;
grant execute on function archiv_zmen(int) to authenticated;
