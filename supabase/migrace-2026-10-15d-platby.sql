-- =============================================================================
-- Školka — doplněk 15. 10. 2026 (d): PLATBY přímo v Supabase.
-- Spusťte v Supabase → SQL Editor po migraci 2026-10-15c-dokumenty. Jde spustit opakovaně.
--
-- Stejná pravidla jako server/finance (Python), jen jako funkce v databázi:
--   předpis  … MD dite:<id> / Dal vynosy:skolkovne | vynosy:stravne
--   platba   … MD banka     / Dal dite:<id>
-- Saldo konta (tabulka konta, drží trigger): kladné = přeplatek, záporné = dluh.
-- Úhrady se rozpouštějí do předpisů od nejstaršího (FIFO).
-- Kniha, předpisy a platby se z aplikace mění JEN těmito funkcemi
-- (přímé zápisy jsou odebrané) — čtení zůstává podle dosavadních pravidel.
-- =============================================================================

revoke insert, update, delete, truncate on ucetni_pohyby, predpisy, predpis_polozky, platby, nesparovane_platby, konta, upominky,
  financni_nastaveni, sazby_stravneho from authenticated, anon;
grant select on ucetni_pohyby, predpisy, predpis_polozky, platby, nesparovane_platby, konta, upominky, financni_nastaveni, sazby_stravneho to authenticated;

-- rozpuštění kreditů do předpisů (FIFO podle splatnosti)
create or replace function fin_vyrovnej(p_dite uuid) returns void
language plpgsql security definer set search_path = public as $$
declare kredit numeric(10,2); p record; u numeric(10,2); st text;
begin
  select coalesce(sum(castka), 0) into kredit from ucetni_pohyby where dal = 'dite:' || p_dite;
  for p in select * from predpisy where dite_id = p_dite order by splatnost, obdobi loop
    u := least(p.castka, greatest(0, kredit));
    kredit := kredit - u;
    st := case when u >= p.castka then 'zaplaceno' when u > 0 then 'castecne_zaplaceno' else 'otevreno' end;
    if p.uhrazeno is distinct from u or p.stav is distinct from st then
      update predpisy set uhrazeno = u, stav = st where id = p.id;
    end if;
  end loop;
end $$;
revoke execute on function fin_vyrovnej(uuid) from anon, public, authenticated;

-- nastavení plateb (ředitelka, zástupkyně): účet, školkovné, stravné, splatnost
create or replace function uloz_financni_nastaveni(p_ucet text, p_skolkovne numeric, p_stravne_36 numeric, p_stravne_7 numeric, p_splatnost int)
returns void language plpgsql security definer set search_path = public as $$
declare s uuid := moje_skola();
begin
  if moje_role() not in ('reditelka', 'zastupce') then raise exception 'Ceny a účet nastavuje vedení školy.'; end if;
  if coalesce(btrim(p_ucet), '') = '' or length(p_ucet) > 40 then raise exception 'Vyplňte číslo účtu školky.'; end if;
  if p_skolkovne is null or p_skolkovne < 0 or p_skolkovne > 100000 then raise exception 'Neplatná výše školkovného.'; end if;
  if p_stravne_36 is null or p_stravne_36 < 0 or p_stravne_36 > 1000 or p_stravne_7 is null or p_stravne_7 < 0 or p_stravne_7 > 1000 then raise exception 'Neplatná cena stravného.'; end if;
  if p_splatnost is null or p_splatnost not between 1 and 28 then raise exception 'Splatnost musí být 1.–28. den v měsíci.'; end if;
  insert into financni_nastaveni (skola_id, ucet, skolkovne, splatnost_den) values (s, btrim(p_ucet), round(p_skolkovne, 2), p_splatnost)
  on conflict (skola_id) do update set ucet = excluded.ucet, skolkovne = excluded.skolkovne, splatnost_den = excluded.splatnost_den;
  insert into sazby_stravneho (skola_id, kategorie, cena) values (s, '3-6', round(p_stravne_36, 2)), (s, '7+', round(p_stravne_7, 2))
  on conflict (skola_id, kategorie) do update set cena = excluded.cena;
end $$;

-- předpisy za měsíc pro děti, které ve školce v tom měsíci jsou; opakování nic nezdvojí
create or replace function vystav_predpisy(p_obdobi text) returns int
language plpgsql security definer set search_path = public as $$
declare
  s uuid := moje_skola(); nf financni_nastaveni; od date; dokdy date; spl date; d deti; pid uuid; n int := 0;
  celkem numeric(10,2); por int; x record; jmeno text; mesic text;
begin
  if not je_finance() then raise exception 'Předpisy vystavuje vedení nebo hospodářka.'; end if;
  if p_obdobi !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then raise exception 'Neplatné období.'; end if;
  select * into nf from financni_nastaveni where skola_id = s;
  if not found then raise exception 'Nejdřív vyplňte nastavení plateb (účet a ceny).'; end if;
  od := to_date(p_obdobi || '-01', 'YYYY-MM-DD');
  dokdy := (od + interval '1 month' - interval '1 day')::date;
  if dokdy >= dnes_praha() then raise exception 'Předpisy za měsíc se vystavují až po jeho skončení (stravné podle skutečnosti).'; end if;
  mesic := (array['leden','únor','březen','duben','květen','červen','červenec','srpen','září','říjen','listopad','prosinec'])[extract(month from od)::int] || ' ' || extract(year from od)::int;
  spl := make_date(extract(year from dokdy + 1)::int, extract(month from dokdy + 1)::int, nf.splatnost_den);
  perform pg_advisory_xact_lock(hashtext('predpisy:' || s || ':' || p_obdobi));
  for d in select * from deti where skola_id = s and zahajeni <= dokdy and (ukonceno is null or ukonceno >= od) order by prijmeni, jmeno loop
    continue when exists (select 1 from predpisy where dite_id = d.id and obdobi = p_obdobi);
    jmeno := d.jmeno || ' ' || d.prijmeni;
    insert into predpisy (dite_id, obdobi, castka, splatnost, vystaveno) values (d.id, p_obdobi, 0, spl, dnes_praha()) returning id into pid;
    celkem := 0; por := 0;
    -- školkovné (osvobozené děti 0 Kč)
    por := por + 1;
    if d.osvobozen_od_skolkovneho then
      insert into predpis_polozky values (pid, por, 'skolkovne', 'Školkovné — osvobozeno', 1, 0, 0);
    else
      insert into predpis_polozky values (pid, por, 'skolkovne', 'Školkovné ' || mesic, 1, nf.skolkovne, nf.skolkovne);
      celkem := celkem + nf.skolkovne;
    end if;
    -- stravné: dny s přihlášeným jídlem bez včas omluvených, po věkových skupinách
    for x in
      select k.kat, count(*)::int as dny, sz.cena from (
        select case when extract(year from age(make_date(extract(year from y.den)::int + case when extract(month from y.den) >= 9 then 1 else 0 end, 8, 31), d.datum_narozeni)) >= 7 then '7+' else '3-6' end as kat
          from dochazka y
         where y.dite_id = d.id and y.den between od and dokdy and y.strava_prihlasena
           and not (y.omluva_zadana is not null
                    and (y.omluva_zadana at time zone 'Europe/Prague') <= ((y.den - nf.omluva_dni_predem) + nf.omluva_do))
      ) k left join sazby_stravneho sz on sz.skola_id = s and sz.kategorie = k.kat
      group by k.kat, sz.cena order by k.kat
    loop
      if x.cena is null then raise exception 'Školka nemá cenu stravného pro kategorii % let.', x.kat; end if;
      por := por + 1;
      insert into predpis_polozky values (pid, por, 'stravne', 'Stravné ' || x.kat || ' let', x.dny, x.cena, round(x.cena * x.dny, 2));
      celkem := celkem + round(x.cena * x.dny, 2);
    end loop;
    update predpisy set castka = celkem, stav = case when celkem = 0 then 'zaplaceno' else 'otevreno' end where id = pid;
    insert into ucetni_pohyby (skola_id, datum, md, dal, castka, popis, doklad)
    select s, dokdy, 'dite:' || d.id, 'vynosy:' || q.druh, q.castka, q.popis || ' — ' || jmeno, pid::text
      from predpis_polozky q where q.predpis_id = pid and q.castka > 0 order by q.poradi;
    perform fin_vyrovnej(d.id);
    n := n + 1;
  end loop;
  return n;
end $$;

-- připsání platby dítěti (vnitřní): vrací výsledek párování
create or replace function fin_pripis(p_platba uuid, p_dite uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pl platby; dluh numeric(10,2); d deti;
begin
  select * into pl from platby where id = p_platba;
  select * into d from deti where id = p_dite;
  select greatest(0, -coalesce((select saldo from konta where dite_id = p_dite), 0)) into dluh;
  update platby set dite_id = p_dite where id = p_platba;
  insert into ucetni_pohyby (skola_id, datum, md, dal, castka, popis, doklad)
  values (pl.skola_id, pl.datum, 'banka', 'dite:' || p_dite, pl.castka, 'Platba VS ' || coalesce(nullif(pl.vs, ''), '—') || ' — ' || d.jmeno || ' ' || d.prijmeni, pl.id::text);
  perform fin_vyrovnej(p_dite);
  return jsonb_build_object('vysledek', case when pl.castka = dluh then 'presne' when pl.castka > dluh then 'preplatek' else 'nedoplatek' end,
    'dite', p_dite, 'preplatek', greatest(0, pl.castka - dluh), 'zbyva', greatest(0, dluh - pl.castka));
end $$;
revoke execute on function fin_pripis(uuid, uuid) from anon, public, authenticated;

-- příchozí platby z výpisu (výpis přečte prohlížeč): [{datum, castka, vs, protiucet, nazev, doklad}]
create or replace function zpracuj_platby(p_platby jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s uuid := moje_skola(); x record; vsn text; did uuid; pid uuid; r jsonb;
  presne int := 0; preplatek int := 0; nedoplatek int := 0; nesparovano int := 0; duplicita int := 0; celkem numeric(12,2) := 0;
begin
  if not je_finance() then raise exception 'Platby zpracovává vedení nebo hospodářka.'; end if;
  if jsonb_typeof(p_platby) <> 'array' or jsonb_array_length(p_platby) > 2000 then raise exception 'Neplatný výpis.'; end if;
  for x in select * from jsonb_to_recordset(p_platby) as t(datum date, castka numeric, vs text, protiucet text, nazev text, doklad text) loop
    if x.castka is null or x.castka <= 0 or x.castka > 1000000 or x.datum is null then raise exception 'Neplatná platba ve výpisu.'; end if;
    if coalesce(x.doklad, '') <> '' and exists (select 1 from platby where skola_id = s and doklad = x.doklad) then duplicita := duplicita + 1; continue; end if;
    vsn := ltrim(regexp_replace(coalesce(x.vs, ''), '\D', '', 'g'), '0');
    did := null;
    if vsn <> '' then select id into did from deti where skola_id = s and ltrim(coalesce(variabilni_symbol, ''), '0') = vsn limit 1; end if;
    insert into platby (skola_id, datum, castka, vs, protiucet, nazev, zdroj, doklad)
    values (s, x.datum, round(x.castka, 2), left(coalesce(x.vs, ''), 10), left(coalesce(x.protiucet, ''), 40), left(coalesce(x.nazev, ''), 60), 'gpc', left(coalesce(x.doklad, ''), 80))
    returning id into pid;
    celkem := celkem + round(x.castka, 2);
    if did is null then
      insert into nesparovane_platby (platba_id, duvod) values (pid, case when coalesce(x.vs, '') = '' then 'Platba nemá VS' else 'VS ' || x.vs || ' nepatří žádnému dítěti' end);
      nesparovano := nesparovano + 1;
    else
      r := fin_pripis(pid, did);
      case r->>'vysledek' when 'presne' then presne := presne + 1; when 'preplatek' then preplatek := preplatek + 1; else nedoplatek := nedoplatek + 1; end case;
    end if;
  end loop;
  return jsonb_build_object('presne', presne, 'preplatek', preplatek, 'nedoplatek', nedoplatek, 'nesparovano', nesparovano, 'duplicita', duplicita, 'celkem', celkem);
end $$;

-- ruční spárování nespárované platby
create or replace function sparuj_platbu(p_platba uuid, p_dite uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s uuid := moje_skola(); r jsonb;
begin
  if not je_finance() then raise exception 'Platby páruje vedení nebo hospodářka.'; end if;
  if not exists (select 1 from nesparovane_platby n join platby p on p.id = n.platba_id where n.platba_id = p_platba and not n.vyreseno and p.skola_id = s) then
    raise exception 'Nespárovaná platba neexistuje nebo už je vyřešená.';
  end if;
  if not exists (select 1 from deti where id = p_dite and skola_id = s) then raise exception 'Dítě do školky nepatří.'; end if;
  r := fin_pripis(p_platba, p_dite);
  update nesparovane_platby set vyreseno = true, vyresil = auth.uid(), vyreseno_kdy = now() where platba_id = p_platba;
  return r;
end $$;

-- záznam upomínky (zprávu do aplikace pošle ředitelna přes zprávy)
create or replace function zapis_upominku(p_dite uuid, p_kanal text default 'push') returns int
language plpgsql security definer set search_path = public as $$
declare s uuid := moje_skola(); n int;
begin
  if not je_finance() then raise exception 'Upomínky posílá vedení nebo hospodářka.'; end if;
  if p_kanal not in ('push', 'email') then raise exception 'Neznámý kanál.'; end if;
  if not exists (select 1 from deti where id = p_dite and skola_id = s) then raise exception 'Dítě do školky nepatří.'; end if;
  insert into upominky (dite_id, obdobi, kanal)
  select p_dite, obdobi, p_kanal from predpisy where dite_id = p_dite and stav <> 'zaplaceno' and splatnost < dnes_praha();
  get diagnostics n = row_count;
  return n;
end $$;

revoke execute on function uloz_financni_nastaveni(text, numeric, numeric, numeric, int), vystav_predpisy(text), zpracuj_platby(jsonb),
  sparuj_platbu(uuid, uuid), zapis_upominku(uuid, text) from anon, public;
grant execute on function uloz_financni_nastaveni(text, numeric, numeric, numeric, int), vystav_predpisy(text), zpracuj_platby(jsonb),
  sparuj_platbu(uuid, uuid), zapis_upominku(uuid, text) to authenticated;
