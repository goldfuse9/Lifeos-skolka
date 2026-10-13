-- =============================================================================
-- Školka — doplněk pro pilotní provoz se sdílenými daty (Supabase)
-- -----------------------------------------------------------------------------
-- Spouští se po schema.sql (v Supabase je obojí v setup.sql). Přidává:
--   • práva i pro školu, uživatele, třídy (všechny tabulky mají RLS)
--   • propojení rodiče v LifeOS jednorázovým kódem od ředitelky
--   • zápisy učitelky pro rodiče (teplota, úraz, jídlo, spánek)
--   • akce, alba (denní / týdenní), „dnes vyzvedne jiný“
--   • omluvenku od rodiče (odhlásí oběd, když přijde do uzávěrky)
--   • jídelníček pro rodiče — alergeny a náhrady; které alergeny má dítě,
--     si LifeOS hlídá v telefonu, na server to nejde
--   • živé změny (realtime) a přístup jen pro přihlášené
-- =============================================================================

-- ------------------------------------------------------------ práva: základ
create or replace function je_vedeni() returns boolean language sql stable as
  $$ select moje_role() in ('reditelka', 'zastupce') $$;

alter table skoly enable row level security;
create policy skola_cist on skoly for select using (id = moje_skola());
create policy skola_menit on skoly for update using (je_vedeni() and id = moje_skola());

alter table uzivatele enable row level security;
create policy uziv_cist on uzivatele for select using (id = auth.uid() or (skola_id = moje_skola() and moje_role() <> 'rodic'));
create policy uziv_menit on uzivatele for all using (moje_role() = 'reditelka' and skola_id = moje_skola());

alter table tridy enable row level security;
create policy tridy_cist on tridy for select using (skola_id = moje_skola());
create policy tridy_menit on tridy for all using (je_vedeni() and skola_id = moje_skola());

alter table ucitel_trida enable row level security;
create policy ut_cist on ucitel_trida for select using (exists (select 1 from tridy t where t.id = trida_id and t.skola_id = moje_skola()));
create policy ut_menit on ucitel_trida for all using (je_vedeni() and exists (select 1 from tridy t where t.id = trida_id and t.skola_id = moje_skola()));

-- Docházku zapisuje škola; rodič omlouvá přes omluv_dite() (hlídá uzávěrku obědů).
drop policy doch_menit on dochazka;
create policy doch_menit on dochazka for all using (moje_role() in ('reditelka', 'zastupce', 'ucitelka') and moje_dite(dite_id));

create or replace function je_ucitelka_tridy(t uuid) returns boolean language sql stable security definer set search_path = public as
  $$ select exists (select 1 from ucitel_trida where trida_id = t and ucitel_id = auth.uid()) $$;

create or replace function rodic_tridy(t uuid) returns boolean language sql stable security definer set search_path = public as
  $$ select exists (select 1 from deti d join zastupci z on z.dite_id = d.id where z.uzivatel_id = auth.uid() and d.trida_id = t) $$;

-- ------------------------------------------------- propojení rodiče s LifeOS
create table parovaci_kody (
  kod text primary key,                       -- 8 znaků bez 0/O/1/I, ukazuje se jako ABCD-EFGH
  skola_id uuid not null references skoly,
  dite_id uuid not null references deti on delete cascade,
  zastupce_id uuid references zastupci on delete cascade,   -- komu je kód určený (nepovinné)
  vytvoril uuid references uzivatele,
  vytvoreno timestamptz not null default now(),
  plati_do timestamptz not null,
  pouzito timestamptz, pouzil uuid,
  zruseno timestamptz
);
alter table parovaci_kody enable row level security;
create policy kody_cist on parovaci_kody for select using (je_vedeni() and skola_id = moje_skola());

-- Ředitelka vydá kód pro rodiče (starý nepoužitý kód téhož dítěte/zástupce zneplatní).
create or replace function vytvor_kod_rodice(p_dite uuid, p_zastupce uuid default null) returns text
language plpgsql security definer set search_path = public as $$
declare
  abc constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  b bytea := uuid_send(gen_random_uuid());
  k text := '';
begin
  if not (je_vedeni() and exists (select 1 from deti where id = p_dite and skola_id = moje_skola())) then
    raise exception 'Kód pro rodiče vydává jen vedení školy.';
  end if;
  if p_zastupce is not null and not exists (select 1 from zastupci where id = p_zastupce and dite_id = p_dite) then
    raise exception 'Zástupce k tomuto dítěti nepatří.';
  end if;
  for i in 0..7 loop k := k || substr(abc, get_byte(b, i) % 32 + 1, 1); end loop;
  update parovaci_kody set zruseno = now()
   where dite_id = p_dite and zastupce_id is not distinct from p_zastupce and pouzito is null and zruseno is null;
  insert into parovaci_kody (kod, skola_id, dite_id, zastupce_id, vytvoril, plati_do)
  values (k, moje_skola(), p_dite, p_zastupce, auth.uid(), now() + interval '14 days');
  return substr(k, 1, 4) || '-' || substr(k, 5, 4);
end $$;

-- Rodič v LifeOS zadá kód. Účet rodiče vznikne sám (anonymní přihlášení v aplikaci).
create or replace function uplatni_kod(p_kod text, p_jmeno text default null)
returns table (dite_id uuid, jmeno text, prijmeni text, datum_narozeni date, skola text, trida text, telefon_skoly text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  me uuid := auth.uid();
  k parovaci_kody;
begin
  if me is null then raise exception 'Nejste přihlášeni.'; end if;
  select * into k from parovaci_kody
   where kod = upper(regexp_replace(coalesce(p_kod, ''), '[^A-Za-z0-9]', '', 'g'))
     and pouzito is null and zruseno is null and plati_do > now()
   for update;
  if not found then raise exception 'Kód neplatí — je překlepnutý, použitý nebo starší než 14 dní. Požádejte ve školce o nový.'; end if;
  if exists (select 1 from uzivatele u where u.id = me and u.role <> 'rodic') then
    raise exception 'Tento účet patří zaměstnanci školy, rodičovský kód na něj nejde použít.';
  end if;
  insert into uzivatele (id, skola_id, jmeno, role)
  values (me, k.skola_id, coalesce(nullif(trim(p_jmeno), ''), 'Rodič'), 'rodic')
  on conflict (id) do nothing;
  if k.zastupce_id is not null then
    update zastupci set uzivatel_id = me where id = k.zastupce_id;
  elsif not exists (select 1 from zastupci z where z.dite_id = k.dite_id and z.uzivatel_id = me) then
    insert into zastupci (dite_id, uzivatel_id, jmeno, poradi)
    values (k.dite_id, me, coalesce(nullif(trim(p_jmeno), ''), 'Rodič (LifeOS)'), 9);
  end if;
  update parovaci_kody set pouzito = now(), pouzil = me where kod = k.kod;
  return query
    select d.id, d.jmeno, d.prijmeni, d.datum_narozeni, s.nazev, t.nazev, s.kontakt
    from deti d join skoly s on s.id = d.skola_id left join tridy t on t.id = d.trida_id
    where d.id = k.dite_id;
end $$;

-- ------------------------------------------- zápisy učitelky pro rodiče
create table udalosti_ditete (
  id uuid primary key default gen_random_uuid(),
  skola_id uuid not null references skoly,
  dite_id uuid not null references deti on delete cascade,
  den date not null default (now() at time zone 'Europe/Prague')::date,
  cas time not null default (now() at time zone 'Europe/Prague')::time(0),
  druh text not null check (druh in ('teplota', 'uraz', 'jidlo', 'spanek', 'info')),
  titulek text not null,
  hodnota text,                               -- „38,4 °C“, „pravé koleno“, „polovina“
  text text,
  osetreni text,
  zapsal uuid references uzivatele default auth.uid(),
  zapsal_jmeno text,
  precteno timestamptz,                       -- rodič potvrdil přečtení
  vytvoreno timestamptz not null default now()
);
create index on udalosti_ditete (dite_id, den);
alter table udalosti_ditete enable row level security;
create policy ud_cist on udalosti_ditete for select using (moje_role() not in ('hospodarka', 'kucharka') and moje_dite(dite_id));
create policy ud_psat on udalosti_ditete for insert with check (moje_role() in ('reditelka', 'zastupce', 'ucitelka') and moje_dite(dite_id) and skola_id = moje_skola());
create policy ud_menit on udalosti_ditete for update using (je_vedeni() and skola_id = moje_skola() or zapsal = auth.uid());
create policy ud_mazat on udalosti_ditete for delete using (je_vedeni() and skola_id = moje_skola() or zapsal = auth.uid());

create or replace function potvrd_udalosti(p_ids uuid[]) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update udalosti_ditete set precteno = now()
   where id = any(p_ids) and precteno is null and moje_role() = 'rodic' and moje_dite(dite_id);
  get diagnostics n = row_count;
  return n;
end $$;

-- ------------------------------------------------------------------ akce
create table akce (
  id uuid primary key default gen_random_uuid(),
  skola_id uuid not null references skoly,
  trida_id uuid references tridy,             -- null = celá školka
  den date not null, cas time,
  nazev text not null, misto text, poznamka text,
  cena numeric(10,2) check (cena >= 0),
  jen_info boolean not null default false,    -- zavřeno, svátek — do kalendáře nepatří
  vytvoreno timestamptz not null default now()
);
alter table akce enable row level security;
create policy akce_cist on akce for select using (skola_id = moje_skola() and (trida_id is null or moje_role() <> 'rodic' or rodic_tridy(trida_id)));
create policy akce_menit on akce for all using (skola_id = moje_skola() and (je_vedeni() or (moje_role() = 'ucitelka' and trida_id is not null and je_ucitelka_tridy(trida_id))));

-- ------------------------------------------------------------ alba fotek
create table alba (
  id uuid primary key default gen_random_uuid(),
  skola_id uuid not null references skoly,
  trida_id uuid not null references tridy,
  den date not null,
  druh text not null default 'den' check (druh in ('den', 'tyden')),
  nazev text not null,
  popis text,                                 -- co děti dělaly
  fotky text[] not null default '{}',         -- cesty v úložišti (Storage)
  vytvoril uuid references uzivatele default auth.uid(),
  vytvoreno timestamptz not null default now()
);
alter table alba enable row level security;
create policy alba_cist on alba for select using (skola_id = moje_skola() and (moje_role() <> 'rodic' or rodic_tridy(trida_id)));
create policy alba_menit on alba for all using (skola_id = moje_skola() and (je_vedeni() or je_ucitelka_tridy(trida_id)));

-- --------------------------------------------- dnes vyzvedne někdo jiný
create table vyzvednuti (
  id uuid primary key default gen_random_uuid(),
  dite_id uuid not null references deti on delete cascade,
  den date not null,
  kdo text not null, kdy text,
  zapsal uuid default auth.uid(),
  vytvoreno timestamptz not null default now()
);
alter table vyzvednuti enable row level security;
create policy vyz_cist on vyzvednuti for select using (moje_dite(dite_id));
create policy vyz_psat on vyzvednuti for insert with check (moje_role() in ('rodic', 'reditelka', 'zastupce', 'ucitelka') and moje_dite(dite_id));

-- ------------------------------------------------------ omluvenka rodiče
-- Omluví všední dny od–do. Oběd se odhlásí, když omluvenka přijde do uzávěrky
-- školky (financni_nastaveni: omluva_dni_predem, omluva_do; jinak den předem do 8:00).
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
      insert into dochazka (dite_id, den, stav, omluvenka, omluva_zadana, strava_prihlasena)
      values (p_dite, d, 'omluven', p_duvod, now(), not (ted < (d - dni) + do_))
      on conflict (dite_id, den) do update
        set stav = 'omluven', omluvenka = excluded.omluvenka, omluva_zadana = excluded.omluva_zadana,
            strava_prihlasena = excluded.strava_prihlasena
        where dochazka.stav <> 'pritomen';
      den := d; obed_odhlasen := not (ted >= (d - dni) + do_);
      return next;
    end if;
    d := d + 1;
  end loop;
end $$;

-- ------------------------------------------------- jídelníček pro rodiče
-- Zveřejněný jídelníček školy s alergeny (z surovin) a náhradami podle alergenu.
create or replace function jidelnicek_tyden(p_od date, p_do date)
returns table (den date, chod text, nazev text, alergeny smallint[], nahrady jsonb)
language sql stable security definer set search_path = public as $$
  select j.den, j.chod, x.nazev,
         coalesce((select array_agg(distinct a order by a) from jidlo_suroviny js join suroviny s on s.id = js.surovina_id, unnest(s.alergeny) a where js.jidlo_id = x.id), '{}'),
         coalesce((select jsonb_object_agg(n.alergen, n.text) from nahrady n where n.jidlo_id = x.id), '{}'::jsonb)
  from jidelnicek j join jidla x on x.id = j.jidlo_id
  where j.skola_id = moje_skola() and j.zverejneno and j.den between p_od and p_do
  order by j.den, array_position(array['prs', 'pol', 'obed', 'sv', 'nap'], j.chod)
$$;

-- ------------------------------------------------------- audit nových tabulek
create trigger a_udalosti after insert or update or delete on udalosti_ditete for each row execute function zapis_audit();
create trigger a_kody after insert or update on parovaci_kody for each row execute function zapis_audit();

-- -------------------------------------------------------- realtime (živé změny)
alter publication supabase_realtime add table dochazka, udalosti_ditete, akce, zpravy, alba, vyzvednuti, jidelnicek;

-- ----------------------------------------- přístup: jen přihlášení, vše pod RLS
do $$
declare t record;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t.tablename);
  end loop;
end $$;

grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
revoke all on all tables in schema public from anon;
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
