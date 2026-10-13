-- =============================================================================
-- Školka — doplněk 13. 10. 2026 (b). Spusťte jednou v Supabase → SQL Editor.
--   • značka ze šatny u dítěte (tablet i LifeOS ukazují stejnou)
--   • potvrzení omluvenky učitelkou (rodič dostane oznámení)
--   • jídelna: zveřejnění jídelníčku na server, vypínač „děláme náhrady“
--   • rodič v LifeOS opraví alergie, svůj kontakt a pověřené osoby
-- =============================================================================

alter table deti add column if not exists znacka text;
alter table dochazka add column if not exists omluva_potvrzena timestamptz;
alter table dochazka add column if not exists omluvu_potvrdil text;
alter table skoly add column if not exists nahrady_obedu boolean not null default true;

-- Testovací děti dostanou značky (jinak se přidělí podle pořadí ve třídě).
update deti set znacka = 'jablko' where id = '00000000-0000-4000-8000-000000000101' and znacka is null;
update deti set znacka = 'snehulak' where id = '00000000-0000-4000-8000-000000000102' and znacka is null;
with x as (
  select id, (array['auticko','kytka','micek','motyl','lodicka','srdce','hvezda','tresne','muchomurka','mesic','domecek','destnik','strom','beruska','rybka','balonek','klic','mracek','mrkev','hruska','zvonek','duha','hrnek','list','slunce','snek'])[1 + (row_number() over (partition by trida_id order by prijmeni, jmeno) - 1)::int % 26] z
  from deti where znacka is null
) update deti d set znacka = x.z from x where x.id = d.id;

-- Nová omluvenka zruší staré potvrzení (rodič mohl změnit dny nebo důvod).
create or replace function omluv_dite(p_dite uuid, p_od date, p_do date, p_duvod text default null)
returns table (den date, obed_odhlasen boolean)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  ted timestamp := now() at time zone 'Europe/Prague';
  dni int := 1; do_ time := '08:00';
  d date;
begin
  if not (moje_role() in ('rodic', 'reditelka', 'zastupce', 'ucitelka') and moje_dite(p_dite)) then
    raise exception 'Toto dítě omluvit nemůžete.';
  end if;
  if p_do < p_od or p_do > p_od + 31 then raise exception 'Omluvit jde nejvýš měsíc dopředu.'; end if;
  select f.omluva_dni_predem, f.omluva_do into dni, do_
    from financni_nastaveni f join deti x on x.skola_id = f.skola_id where x.id = p_dite;
  dni := coalesce(dni, 1); do_ := coalesce(do_, '08:00');
  d := p_od;
  while d <= p_do loop
    if extract(isodow from d) < 6 then
      insert into dochazka (dite_id, den, stav, omluvenka, omluva_zadana, strava_prihlasena, omluva_potvrzena, omluvu_potvrdil)
      values (p_dite, d, 'omluven', p_duvod, now(), not (ted < (d - dni) + do_), null, null)
      on conflict (dite_id, den) do update
        set stav = 'omluven', omluvenka = excluded.omluvenka, omluva_zadana = excluded.omluva_zadana,
            strava_prihlasena = excluded.strava_prihlasena, omluva_potvrzena = null, omluvu_potvrdil = null
        where dochazka.stav <> 'pritomen';
      den := d; obed_odhlasen := ted < (d - dni) + do_;
      return next;
    end if;
    d := d + 1;
  end loop;
end $$;

-- Učitelka potvrdí omluvenku (všechny dny od–do).
create or replace function potvrd_omluvenku(p_dite uuid, p_od date, p_do date) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not (moje_role() in ('reditelka', 'zastupce', 'ucitelka') and moje_dite(p_dite)) then
    raise exception 'Omluvenku potvrzuje škola.';
  end if;
  update dochazka set omluva_potvrzena = now(), omluvu_potvrdil = (select jmeno from uzivatele where id = auth.uid())
   where dite_id = p_dite and den between p_od and p_do and stav = 'omluven' and omluva_potvrzena is null;
  get diagnostics n = row_count;
  return n;
end $$;

-- Jídelna zveřejní týden: [{den, chod, nazev, alergeny:[..], nahrady:{"7": "…"}}]
create or replace function zverejni_jidelnicek(p_dny jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare
  sk uuid := moje_skola();
  r jsonb; j uuid; s uuid; dr text; n int := 0;
begin
  if not (moje_role() in ('kucharka', 'reditelka')) then raise exception 'Jídelníček zveřejňuje jídelna.'; end if;
  for r in select * from jsonb_array_elements(p_dny) loop
    dr := case r->>'chod' when 'pol' then 'polevka' when 'obed' then 'obed' when 'nap' then 'napoj' else 'svacina' end;
    select id into j from jidla where skola_id = sk and nazev = r->>'nazev' and druh = dr limit 1;
    if j is null then insert into jidla (skola_id, nazev, druh) values (sk, r->>'nazev', dr) returning id into j; end if;
    delete from jidlo_suroviny where jidlo_id = j;
    insert into suroviny (skola_id, nazev, alergeny)
      values (sk, 'alergeny: ' || (r->>'nazev'), coalesce(array(select jsonb_array_elements_text(r->'alergeny'))::smallint[], '{}'))
      returning id into s;
    insert into jidlo_suroviny values (j, s);
    delete from nahrady where jidlo_id = j;
    insert into nahrady (jidlo_id, alergen, text)
      select j, k::smallint, v from jsonb_each_text(coalesce(r->'nahrady', '{}'::jsonb)) as e(k, v) where v <> '';
    insert into jidelnicek (skola_id, den, chod, jidlo_id, zverejneno)
      values (sk, (r->>'den')::date, r->>'chod', j, true)
      on conflict (skola_id, den, chod) do update set jidlo_id = excluded.jidlo_id, zverejneno = true;
    n := n + 1;
  end loop;
  return n;
end $$;

create or replace function nastav_nahrady(p boolean) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not (moje_role() in ('kucharka', 'reditelka')) then raise exception 'Náhrady nastavuje jídelna.'; end if;
  update skoly set nahrady_obedu = p where id = moje_skola();
  return p;
end $$;

-- Rodič opraví údaje, které má školka jinak (zapíše se do audit_logu).
create or replace function uprav_udaje_rodicem(p_dite uuid, p_alergie text default null, p_telefon text default null, p_email text default null, p_poverene text[] default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (moje_role() = 'rodic' and moje_dite(p_dite)) then raise exception 'Údaje tohoto dítěte měnit nemůžete.'; end if;
  if p_alergie is not null then update deti set alergie = nullif(trim(p_alergie), '') where id = p_dite; end if;
  if p_telefon is not null or p_email is not null then
    update zastupci set telefon = coalesce(nullif(trim(p_telefon), ''), telefon), email = coalesce(nullif(trim(p_email), ''), email)
     where dite_id = p_dite and uzivatel_id = auth.uid();
  end if;
  if p_poverene is not null then
    update poverene_osoby set zruseno = current_date
     where dite_id = p_dite and zruseno is null and not (jmeno = any(p_poverene));
    insert into poverene_osoby (dite_id, jmeno)
      select p_dite, x from unnest(p_poverene) x
      where trim(x) <> '' and not exists (select 1 from poverene_osoby o where o.dite_id = p_dite and o.jmeno = x and o.zruseno is null);
  end if;
end $$;

-- Jídelníček pro rodiče: když jídelna náhrady nedělá, nevrací je.
create or replace function jidelnicek_tyden(p_od date, p_do date)
returns table (den date, chod text, nazev text, alergeny smallint[], nahrady jsonb)
language sql stable security definer set search_path = public as $$
  select j.den, j.chod, x.nazev,
         coalesce((select array_agg(distinct a order by a) from jidlo_suroviny js join suroviny s on s.id = js.surovina_id, unnest(s.alergeny) a where js.jidlo_id = x.id), '{}'),
         case when (select nahrady_obedu from skoly where id = moje_skola()) then
           coalesce((select jsonb_object_agg(n.alergen, n.text) from nahrady n where n.jidlo_id = x.id), '{}'::jsonb)
         else '{}'::jsonb end
  from jidelnicek j join jidla x on x.id = j.jidlo_id
  where j.skola_id = moje_skola() and j.zverejneno and j.den between p_od and p_do
  order by j.den, array_position(array['prs', 'pol', 'obed', 'sv', 'nap'], j.chod)
$$;

revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
