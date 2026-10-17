-- =============================================================================
-- Školka — doplněk 17. 10. 2026 (b): STRAVNÉ ZA NEODHLÁŠENÉ OBĚDY.
-- Spusťte v Supabase → SQL Editor po migraci 2026-10-17-banka. Jde spustit opakovaně.
--
-- Kuchyně vaří pro každé zapsané dítě kromě odhlášených (obedy_den). Dítě, které
-- nepřišlo a nikdo ho neomluvil, ale v docházce nemá žádný řádek — předpis ho
-- dosud nezaúčtoval, i když oběd byl uvařený. Nově se účtují i dny, kdy se podle
-- zveřejněného jídelníčku vařil oběd a dítě v docházce chybí; v předpisu jako
-- samostatná položka „neodhlášené obědy“. Dny bez jídelníčku se neúčtují.
-- Už vystavené předpisy se nemění.
-- =============================================================================

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
    -- stravné po věkových skupinách:
    --  a) dny v docházce s přihlášeným jídlem (bez včas omluvených),
    --  b) dny, kdy se podle jídelníčku vařil oběd a dítě v docházce vůbec není
    --     (nepřišlo a nikdo ho neodhlásil) — kuchyně s ním počítala, obědy_den ho
    --     započítala, tak se účtuje jako neodhlášený oběd. Dny bez jídelníčku
    --     (prázdniny, zavřeno, školka bez jídelny v aplikaci) se neúčtují.
    for x in
      select k.kat, k.neodhlaseno, count(*)::int as dny, sz.cena from (
        select y.den, false as neodhlaseno
          from dochazka y
         where y.dite_id = d.id and y.den between od and dokdy and y.strava_prihlasena
           and not (y.omluva_zadana is not null
                    and (y.omluva_zadana at time zone 'Europe/Prague') <= ((y.den - nf.omluva_dni_predem) + nf.omluva_do))
        union all
        select j.den, true
          from jidelnicek j
         where j.skola_id = s and j.chod = 'obed' and j.zverejneno and j.den between od and dokdy
           and d.trida_id is not null and j.den >= d.zahajeni and (d.ukonceno is null or j.den <= d.ukonceno)
           and not exists (select 1 from dochazka y where y.dite_id = d.id and y.den = j.den)
      ) z
      cross join lateral (select case when extract(year from age(make_date(extract(year from z.den)::int + case when extract(month from z.den) >= 9 then 1 else 0 end, 8, 31), d.datum_narozeni)) >= 7 then '7+' else '3-6' end as kat, z.neodhlaseno) k
      left join sazby_stravneho sz on sz.skola_id = s and sz.kategorie = k.kat
      group by k.kat, k.neodhlaseno, sz.cena order by k.kat, k.neodhlaseno
    loop
      if x.cena is null then raise exception 'Školka nemá cenu stravného pro kategorii % let.', x.kat; end if;
      por := por + 1;
      insert into predpis_polozky values (pid, por, 'stravne', 'Stravné ' || x.kat || ' let' || case when x.neodhlaseno then ' — neodhlášené obědy (dítě chybělo bez omluvy)' else '' end, x.dny, x.cena, round(x.cena * x.dny, 2));
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
