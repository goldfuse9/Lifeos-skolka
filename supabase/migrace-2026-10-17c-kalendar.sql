-- =============================================================================
-- Školka — doplněk 17. 10. 2026 (c): PROVOZNÍ KALENDÁŘ a PLATBY PŘEDEM.
-- Spusťte v Supabase → SQL Editor po migraci 2026-10-17b-stravne. Jde spustit opakovaně.
--
-- Provozní kalendář
--   Provozní den = pondělí–pátek, který není státní svátek. Výjimky si školka
--   nastaví sama (kalendar_skoly): svátek, kdy má otevřeno (vaří se), nebo
--   zavřený všední den (prázdniny, ředitelské volno).
--   Podle kalendáře: počty obědů pro kuchyni, omluvenky (na zavřený den se
--   neomlouvá) a stravné v předpisu.
--
-- Platby předem (na začátku měsíce)
--   Předpis za měsíc = školkovné + stravné za všechny provozní dny měsíce.
--   Obědy, které rodič včas odhlásil, se odečtou v předpisu na další měsíc
--   (položka „Odhlášené obědy …“). Pozdě odhlášený oběd se nevrací — kuchyně
--   ho už uvařila. Předpis jde vystavit za běžný i za příští měsíc.
--   Předpisy vystavené dřív (zpětně podle docházky) zůstávají, jak jsou.
-- =============================================================================

-- ------------------------------------------------------------ státní svátky
create or replace function velikonocni_nedele(p_rok int) returns date
language plpgsql immutable set search_path = public as $$
declare a int := p_rok % 19; b int := p_rok / 100; c int := p_rok % 100; d int; e int; f int; g int; h int; i int; k int; l int; m int; mesic int; den int;
begin
  d := b / 4; e := b % 4; f := (b + 8) / 25; g := (b - f + 1) / 3;
  h := (19 * a + b - d - g + 15) % 30; i := c / 4; k := c % 4;
  l := (32 + 2 * e + 2 * i - h - k) % 7; m := (a + 11 * h + 22 * l) / 451;
  mesic := (h + l - 7 * m + 114) / 31; den := ((h + l - 7 * m + 114) % 31) + 1;
  return make_date(p_rok, mesic, den);
end $$;

create or replace function statni_svatky(p_rok int) returns table (den date, nazev text)
language sql immutable set search_path = public as $$
  select make_date(p_rok, m, d), n from (values
    (1, 1, 'Nový rok'), (5, 1, 'Svátek práce'), (5, 8, 'Den vítězství'),
    (7, 5, 'Cyril a Metoděj'), (7, 6, 'Mistr Jan Hus'), (9, 28, 'Den české státnosti'),
    (10, 28, 'Vznik Československa'), (11, 17, 'Den boje za svobodu a demokracii'),
    (12, 24, 'Štědrý den'), (12, 25, '1. svátek vánoční'), (12, 26, '2. svátek vánoční')) v(m, d, n)
  union all select velikonocni_nedele(p_rok) - 2, 'Velký pátek'
  union all select velikonocni_nedele(p_rok) + 1, 'Velikonoční pondělí'
$$;

-- ------------------------------------------------------- výjimky školky
create table if not exists kalendar_skoly (
  skola_id uuid not null references skoly on delete cascade,
  den date not null,
  otevreno boolean not null,
  poznamka text check (length(coalesce(poznamka, '')) <= 120),
  upravil uuid references uzivatele default auth.uid(),
  upraveno timestamptz not null default now(),
  primary key (skola_id, den)
);
alter table kalendar_skoly enable row level security;
drop policy if exists kalendar_cist on kalendar_skoly;
create policy kalendar_cist on kalendar_skoly for select using (skola_id = moje_skola());
revoke insert, update, delete, truncate on kalendar_skoly from authenticated, anon;
grant select on kalendar_skoly to authenticated;

create or replace function je_provozni_den(p_skola uuid, p_den date) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select k.otevreno from kalendar_skoly k where k.skola_id = p_skola and k.den = p_den),
    extract(isodow from p_den) < 6 and not exists (select 1 from statni_svatky(extract(year from p_den)::int) s where s.den = p_den))
$$;

-- Pro ředitelnu: svátky a výjimky v období (ne všechny dny — jen ty, o kterých je co říct).
create or replace function kalendar_skoly_obdobi(p_od date, p_do date)
returns table (den date, svatek text, otevreno boolean, vyjimka boolean, poznamka text)
language sql stable security definer set search_path = public as $$
  with sv as (
    select s.den, s.nazev from generate_series(extract(year from p_od)::int, extract(year from p_do)::int) r, statni_svatky(r) s
     where s.den between p_od and p_do and extract(isodow from s.den) < 6
  ), dny as (
    select den from sv union select k.den from kalendar_skoly k where k.skola_id = moje_skola() and k.den between p_od and p_do
  )
  select d.den, sv.nazev, je_provozni_den(moje_skola(), d.den), k.den is not null, k.poznamka
    from dny d left join sv on sv.den = d.den
    left join kalendar_skoly k on k.skola_id = moje_skola() and k.den = d.den
   where moje_skola() is not null and p_do - p_od <= 400
   order by d.den
$$;

-- Vedení: dny od–do otevřít (i ve svátek), zavřít, nebo vrátit na výchozí.
create or replace function nastav_kalendar(p_od date, p_do date, p_stav text, p_poznamka text default null) returns int
language plpgsql security definer set search_path = public as $$
declare s uuid := moje_skola(); n int;
begin
  if moje_role() is null or moje_role() not in ('reditelka', 'zastupce') or s is null then raise exception 'Provoz školky nastavuje vedení.'; end if;
  if p_od is null or p_do is null or p_do < p_od or p_do - p_od > 120 then raise exception 'Vyberte nejvýš 4 měsíce dní.'; end if;
  if p_stav not in ('otevreno', 'zavreno', 'vychozi') then raise exception 'Neplatný stav dne.'; end if;
  if p_stav = 'vychozi' then
    delete from kalendar_skoly where skola_id = s and den between p_od and p_do;
    get diagnostics n = row_count;
    return n;
  end if;
  insert into kalendar_skoly (skola_id, den, otevreno, poznamka)
  select s, g::date, p_stav = 'otevreno', nullif(btrim(left(coalesce(p_poznamka, ''), 120)), '')
    from generate_series(p_od, p_do, interval '1 day') g
   where extract(isodow from g) < 6 or (p_stav = 'otevreno' and g::date = p_od)   -- víkend je zavřený vždy; otevřít jde jen jednotlivě
  on conflict (skola_id, den) do update set otevreno = excluded.otevreno, poznamka = excluded.poznamka, upravil = auth.uid(), upraveno = now();
  get diagnostics n = row_count;
  return n;
end $$;

revoke execute on function je_provozni_den(uuid, date), kalendar_skoly_obdobi(date, date), nastav_kalendar(date, date, text, text) from anon, public;
grant execute on function je_provozni_den(uuid, date), kalendar_skoly_obdobi(date, date), nastav_kalendar(date, date, text, text) to authenticated;
grant execute on function statni_svatky(int), velikonocni_nedele(int) to authenticated;

drop trigger if exists a_kalendar on kalendar_skoly;
create trigger a_kalendar after insert or update or delete on kalendar_skoly for each row execute function zapis_audit();

-- ------------------------------------------------ kuchyně a omluvenky
-- počty jídel na den: v zavřený den je odhlášeno všechno
create or replace function obedy_den(p_den date)
returns table (trida_id uuid, trida text, barva text, deti int, odhlaseno int)
language sql stable security definer set search_path = public as $$
  select t.id, t.nazev, t.barva,
         count(d.id)::int,
         case when je_provozni_den(moje_skola(), p_den) then
           count(d.id) filter (where exists (select 1 from dochazka x where x.dite_id = d.id and x.den = p_den and x.strava_prihlasena = false))::int
         else count(d.id)::int end
  from tridy t left join deti d on d.trida_id = t.id and d.ukonceno is null and (d.zahajeni is null or d.zahajeni <= p_den)
  where coalesce(je_kuchyne(), false) and t.skola_id = moje_skola()
  group by t.id, t.nazev, t.barva order by t.nazev
$$;

-- je den provozní a proč (pro kuchyni a aplikace)
create or replace function den_provozu(p_den date) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when moje_skola() is null then null else jsonb_build_object(
    'provozni', je_provozni_den(moje_skola(), p_den),
    'svatek', (select s.nazev from statni_svatky(extract(year from p_den)::int) s where s.den = p_den),
    'poznamka', (select k.poznamka from kalendar_skoly k where k.skola_id = moje_skola() and k.den = p_den)) end
$$;
revoke execute on function den_provozu(date) from anon, public;
grant execute on function den_provozu(date) to authenticated;

-- omluvenka: jen na provozní dny (na zavřený den není co omlouvat ani odhlašovat)
create or replace function omluv_dite(p_dite uuid, p_od date, p_do date, p_duvod text default null)
returns table (den date, obed_odhlasen boolean)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  ted timestamp := now() at time zone 'Europe/Prague';
  dni int := 1; do_ time := '08:00';
  d date; rodic boolean := coalesce(moje_role() = 'rodic', false); zapsano boolean; sk uuid;
begin
  if not (moje_role() in ('rodic', 'reditelka', 'zastupce', 'ucitelka') and moje_dite(p_dite)) then
    raise exception 'Toto dítě omluvit nemůžete.';
  end if;
  if p_do < p_od or p_do > p_od + 31 then raise exception 'Omluvit jde nejvýš měsíc dopředu.'; end if;
  if rodic and p_od < ted::date then raise exception 'Zpětně omlouvá jen školka.'; end if;
  select x.skola_id into sk from deti x where x.id = p_dite;
  select f.omluva_dni_predem, f.omluva_do into dni, do_
    from financni_nastaveni f where f.skola_id = sk;
  dni := coalesce(dni, 1); do_ := coalesce(do_, '08:00');
  d := p_od;
  while d <= p_do loop
    if je_provozni_den(sk, d) then
      insert into dochazka (dite_id, den, stav, omluvenka, omluva_zadana, strava_prihlasena, omluva_potvrzena, omluvu_potvrdil)
      values (p_dite, d, 'omluven', p_duvod, now(), not (ted < (d - dni) + do_), null, null)
      on conflict (dite_id, den) do update
        set stav = 'omluven', omluvenka = excluded.omluvenka, omluva_zadana = excluded.omluva_zadana,
            strava_prihlasena = excluded.strava_prihlasena, omluva_potvrzena = null, omluvu_potvrdil = null
        where dochazka.stav <> 'pritomen' and not (rodic and dochazka.stav = 'neomluven')
      returning true into zapsano;
      if coalesce(zapsano, false) then
        den := d; obed_odhlasen := ted < (d - dni) + do_;
        return next;
      end if;
      zapsano := null;
    end if;
    d := d + 1;
  end loop;
  if rodic and not found then raise exception 'V tyto dny se do školky nechodí nebo už tam dítě je — omluvit nejde.'; end if;
end $$;

-- ------------------------------------------------------- platby předem
alter table predpisy add column if not exists predem boolean not null default false;
alter table predpis_polozky drop constraint if exists predpis_polozky_druh_check;
alter table predpis_polozky add constraint predpis_polozky_druh_check check (druh in ('skolkovne', 'stravne', 'vratka'));

-- Odhlášené obědy započtené rovnou do předpisu (doklad „vratka:<předpis>“) už předpis
-- snížily — do kreditu na úhradu se nepočítají znovu.
create or replace function fin_vyrovnej(p_dite uuid) returns void
language plpgsql security definer set search_path = public as $$
declare kredit numeric(10,2); p record; u numeric(10,2); st text;
begin
  select coalesce(sum(castka), 0) into kredit from ucetni_pohyby where dal = 'dite:' || p_dite and doklad not like 'vratka:%';
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

create or replace function vystav_predpisy(p_obdobi text) returns int
language plpgsql security definer set search_path = public as $$
declare
  s uuid := moje_skola(); nf financni_nastaveni; od date; dokdy date; spl date; d deti; pid uuid; n int := 0;
  plus numeric(10,2); minus numeric(10,2); zapocet numeric(10,2); por int; jmeno text; mesic text; pmesic text; pobdobi text;
  kat text; cena numeric(10,2); dny int; vn int; vcena numeric(10,2); zac date; kon date;
  MESICE text[] := array['leden','únor','březen','duben','květen','červen','červenec','srpen','září','říjen','listopad','prosinec'];
begin
  if not je_finance() then raise exception 'Předpisy vystavuje vedení nebo hospodářka.'; end if;
  if p_obdobi !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then raise exception 'Neplatné období.'; end if;
  select * into nf from financni_nastaveni where skola_id = s;
  if not found then raise exception 'Nejdřív vyplňte nastavení plateb (účet a ceny).'; end if;
  od := to_date(p_obdobi || '-01', 'YYYY-MM-DD');
  dokdy := (od + interval '1 month' - interval '1 day')::date;
  if od > (date_trunc('month', dnes_praha()) + interval '1 month')::date then raise exception 'Předpisy jde vystavit nejdřív za příští měsíc.'; end if;
  mesic := MESICE[extract(month from od)::int] || ' ' || extract(year from od)::int;
  pobdobi := to_char(od - interval '1 month', 'YYYY-MM');
  pmesic := MESICE[extract(month from od - interval '1 month')::int];
  -- splatnost v měsíci, za který se platí; když už ten den minul, za 14 dní
  spl := make_date(extract(year from od)::int, extract(month from od)::int, nf.splatnost_den);
  if spl < dnes_praha() then spl := dnes_praha() + 14; end if;
  perform pg_advisory_xact_lock(hashtext('predpisy:' || s || ':' || p_obdobi));
  for d in select * from deti where skola_id = s and zahajeni <= dokdy and (ukonceno is null or ukonceno >= od) order by prijmeni, jmeno loop
    continue when exists (select 1 from predpisy where dite_id = d.id and obdobi = p_obdobi);
    jmeno := d.jmeno || ' ' || d.prijmeni;
    insert into predpisy (dite_id, obdobi, castka, splatnost, vystaveno, predem) values (d.id, p_obdobi, 0, spl, dnes_praha(), true) returning id into pid;
    plus := 0; minus := 0; por := 0;
    -- školkovné (osvobozené děti 0 Kč)
    por := por + 1;
    if d.osvobozen_od_skolkovneho then
      insert into predpis_polozky values (pid, por, 'skolkovne', 'Školkovné — osvobozeno', 1, 0, 0);
    else
      insert into predpis_polozky values (pid, por, 'skolkovne', 'Školkovné ' || mesic, 1, nf.skolkovne, nf.skolkovne);
      plus := plus + nf.skolkovne;
    end if;
    -- stravné předem: provozní dny měsíce, kdy je dítě ve školce zapsané
    kat := case when extract(year from age(make_date(extract(year from od)::int + case when extract(month from od) >= 9 then 1 else 0 end, 8, 31), d.datum_narozeni)) >= 7 then '7+' else '3-6' end;
    select z.cena into cena from sazby_stravneho z where z.skola_id = s and z.kategorie = kat;
    zac := greatest(od, d.zahajeni); kon := least(dokdy, coalesce(d.ukonceno, dokdy));
    select count(*)::int into dny from generate_series(zac, kon, interval '1 day') g where d.trida_id is not null and je_provozni_den(s, g::date);
    if dny > 0 then
      if cena is null then raise exception 'Školka nemá cenu stravného pro kategorii % let.', kat; end if;
      por := por + 1;
      insert into predpis_polozky values (pid, por, 'stravne', 'Stravné ' || mesic || ' (' || kat || ' let)', dny, cena, round(cena * dny, 2));
      plus := plus + round(cena * dny, 2);
    end if;
    -- odpočet: obědy včas odhlášené v předchozím měsíci (jen když se ten měsíc platil předem)
    if exists (select 1 from predpisy where dite_id = d.id and obdobi = pobdobi and predem) then
      select count(*)::int into vn from dochazka y
       where y.dite_id = d.id and y.den between (od - interval '1 month')::date and od - 1 and not y.strava_prihlasena and je_provozni_den(s, y.den);
      if vn > 0 then
        select q.cena into vcena from predpis_polozky q join predpisy p on p.id = q.predpis_id
         where p.dite_id = d.id and p.obdobi = pobdobi and q.druh = 'stravne' order by q.poradi limit 1;
        vcena := coalesce(vcena, cena, 0);
        if vcena > 0 then
          por := por + 1;
          insert into predpis_polozky values (pid, por, 'vratka', 'Odhlášené obědy — ' || pmesic, vn, vcena, -round(vcena * vn, 2));
          minus := minus + round(vcena * vn, 2);
        end if;
      end if;
    end if;
    zapocet := least(minus, plus);
    update predpisy set castka = plus - zapocet, stav = case when plus - zapocet = 0 then 'zaplaceno' else 'otevreno' end where id = pid;
    -- účetnictví: dítě MD / výnosy Dal za každou kladnou položku; odpočet jako dobropis dítěti
    insert into ucetni_pohyby (skola_id, datum, md, dal, castka, popis, doklad)
    select s, od, 'dite:' || d.id, 'vynosy:' || q.druh, q.castka, q.popis || ' — ' || jmeno, pid::text
      from predpis_polozky q where q.predpis_id = pid and q.castka > 0 order by q.poradi;
    if zapocet > 0 then
      insert into ucetni_pohyby (skola_id, datum, md, dal, castka, popis, doklad)
      values (s, od, 'vynosy:stravne', 'dite:' || d.id, zapocet, 'Odhlášené obědy ' || pmesic || ' (započteno v předpisu) — ' || jmeno, 'vratka:' || pid);
    end if;
    if minus > zapocet then   -- odpočet větší než předpis: zbytek zůstane na kontě jako přeplatek
      insert into ucetni_pohyby (skola_id, datum, md, dal, castka, popis, doklad)
      values (s, od, 'vynosy:stravne', 'dite:' || d.id, minus - zapocet, 'Odhlášené obědy ' || pmesic || ' (přeplatek) — ' || jmeno, pid::text);
    end if;
    perform fin_vyrovnej(d.id);
    n := n + 1;
  end loop;
  return n;
end $$;
revoke execute on function vystav_predpisy(text) from anon, public;
grant execute on function vystav_predpisy(text) to authenticated;
