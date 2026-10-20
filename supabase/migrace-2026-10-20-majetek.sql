-- =============================================================================
-- Školka — doplněk 20. 10. 2026: SPRÁVA MAJETKU a INVENTARIZACE.
-- Spusťte v Supabase → SQL Editor po migraci 2026-10-17c-kalendar. Jde spustit opakovaně.
--
--   mistnosti            třídy (napojené na tabulku tridy) a další místnosti
--   majetek_kategorie    zkratka (IT, NAB…) = začátek inventárního čísla
--   majetek              položky; číslo KATEGORIE-ROK-POŘADÍ (IT-2026-0012),
--                        rok = rok pořízení, pořadí běží zvlášť pro kategorii a rok
--   majetek_pohyby       historie položky (zařazení, přesun, zápůjčka, závada…)
--   majetek_kontroly     revize a servis s dalším termínem
--   inventury, inventura_mistnosti, inventura_zaznamy, inventura_nalezy
--
-- Kdo co smí:
--   ředitelka, zástupkyně, hospodářka … vše ve své školce
--   učitelka … vidí majetek místností svých tříd, hlásí závadu a při inventuře
--              skenuje ve svých místnostech
--   ostatní (kuchařka, rodič) … nic
-- Z aplikace se tabulky jen čtou; mění se výhradně funkcemi níže, které
-- hlídají role, číslování a zapisují historii.
-- =============================================================================

create or replace function je_majetek() returns boolean language sql stable set search_path = public as
  $$ select coalesce(moje_role() in ('reditelka', 'zastupce', 'hospodarka'), false) $$;

-- ---------------------------------------------------------------- tabulky
create table if not exists mistnosti (
  id uuid primary key default gen_random_uuid(),
  skola_id uuid not null references skoly on delete cascade,
  nazev text not null check (length(btrim(nazev)) between 1 and 60),
  trida_id uuid references tridy on delete set null,
  poradi int not null default 100,
  aktivni boolean not null default true,
  unique (skola_id, nazev)
);

create table if not exists majetek_kategorie (
  skola_id uuid not null references skoly on delete cascade,
  kod text not null check (kod ~ '^[A-Z]{2,4}$'),
  nazev text not null check (length(btrim(nazev)) between 1 and 40),
  poradi int not null default 100,
  primary key (skola_id, kod)
);

create table if not exists majetek_cisla (
  skola_id uuid not null references skoly on delete cascade,
  kod text not null, rok int not null, posledni int not null default 0,
  primary key (skola_id, kod, rok)
);

create table if not exists majetek (
  id uuid primary key default gen_random_uuid(),
  skola_id uuid not null references skoly on delete cascade,
  cislo text not null,
  kategorie text not null,
  rok int not null,
  poradi int not null,
  nazev text not null check (length(btrim(nazev)) between 1 and 120),
  druh text not null default '' check (length(druh) <= 60),
  mistnost_id uuid references mistnosti,
  odpovida text not null default '' check (length(odpovida) <= 80),
  vyrobce text not null default '' check (length(vyrobce) <= 120),
  seriove text not null default '' check (length(seriove) <= 80),
  porizeno date,
  cena numeric(12,2) check (cena is null or (cena >= 0 and cena < 100000000)),
  dodavatel text not null default '' check (length(dodavatel) <= 120),
  doklad text not null default '' check (length(doklad) <= 60),
  ucetni_druh text not null default 'oe' check (ucetni_druh in ('dhm', 'ddhm', 'oe', 'zrizovatel')),
  zaruka_do date,
  financovani text not null default '' check (length(financovani) <= 80),
  puvodni_cislo text not null default '' check (length(puvodni_cislo) <= 60),
  poznamka text not null default '' check (length(poznamka) <= 2000),
  stav text not null default 'ok' check (stav in ('ok', 'poskozeno', 'oprava', 'zapujceno', 'vyrazeno')),
  zapujceno_komu text not null default '' check (length(zapujceno_komu) <= 80),
  zapujceno_do date,
  vyrazeno date, duvod_vyrazeni text not null default '' check (length(duvod_vyrazeni) <= 300),
  stitek_tisk timestamptz,
  vytvoreno timestamptz not null default now(),
  unique (skola_id, cislo),
  foreign key (skola_id, kategorie) references majetek_kategorie (skola_id, kod)
);
create index if not exists majetek_mistnost on majetek (mistnost_id);
create index if not exists majetek_puvodni on majetek (skola_id, puvodni_cislo) where puvodni_cislo <> '';

create table if not exists majetek_pohyby (
  id uuid primary key default gen_random_uuid(),
  skola_id uuid not null references skoly on delete cascade,
  polozka_id uuid not null references majetek on delete cascade,
  kdy timestamptz not null default now(),
  druh text not null check (druh in ('zarazeno', 'uprava', 'presun', 'zapujceni', 'vraceni', 'zavada', 'oprava', 'vyrazeni', 'stitek', 'inventura', 'kontrola')),
  popis text not null default '' check (length(popis) <= 500),
  kdo uuid references uzivatele default auth.uid()
);
create index if not exists majetek_pohyby_polozka on majetek_pohyby (polozka_id, kdy desc);

create table if not exists majetek_kontroly (
  id uuid primary key default gen_random_uuid(),
  skola_id uuid not null references skoly on delete cascade,
  polozka_id uuid references majetek on delete cascade,     -- null = kontrola celé školky (hasicí přístroje…)
  nazev text not null check (length(btrim(nazev)) between 1 and 120),
  interval_mesicu int check (interval_mesicu is null or interval_mesicu between 1 and 120),
  posledni date,
  dalsi date not null,
  poznamka text not null default '' check (length(poznamka) <= 500)
);

create table if not exists inventury (
  id uuid primary key default gen_random_uuid(),
  skola_id uuid not null references skoly on delete cascade,
  k_datu date not null,
  zahajena date not null default ((now() at time zone 'Europe/Prague')::date),
  uzavrena timestamptz,
  komise text[] not null default '{}' check (coalesce(array_length(komise, 1), 0) <= 10),
  zahajil uuid references uzivatele default auth.uid()
);
create unique index if not exists inventury_jedna_bezi on inventury (skola_id) where uzavrena is null;

create table if not exists inventura_mistnosti (
  inventura_id uuid not null references inventury on delete cascade,
  mistnost_id uuid not null references mistnosti on delete cascade,
  kontroluje text not null default '' check (length(kontroluje) <= 80),
  hotovo timestamptz,
  primary key (inventura_id, mistnost_id)
);

create table if not exists inventura_zaznamy (
  inventura_id uuid not null references inventury on delete cascade,
  polozka_id uuid not null references majetek on delete cascade,
  vysledek text not null check (vysledek in ('nalezeno', 'jinde', 'chybi')),
  nalezeno_v uuid references mistnosti,
  kdy timestamptz not null default now(),
  kdo uuid references uzivatele default auth.uid(),
  vyreseno text check (vyreseno is null or vyreseno in ('presunuto', 'vraceno', 'naslo_se', 'vyrazeno', 'ponechano')),
  primary key (inventura_id, polozka_id)
);

create table if not exists inventura_nalezy (                 -- věci bez štítku (možný přebytek)
  id uuid primary key default gen_random_uuid(),
  inventura_id uuid not null references inventury on delete cascade,
  mistnost_id uuid not null references mistnosti,
  popis text not null check (length(btrim(popis)) between 1 and 200),
  kdy timestamptz not null default now(),
  kdo uuid references uzivatele default auth.uid(),
  vyreseno text check (vyreseno is null or vyreseno in ('zalozeno', 'zruseno')),
  polozka_id uuid references majetek
);

-- ---------------------------------------------------------------- práva čtení
create or replace function moje_mistnost(m uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from mistnosti x join ucitel_trida ut on ut.trida_id = x.trida_id
                  where x.id = m and ut.ucitel_id = auth.uid() and x.skola_id = moje_skola())
$$;

alter table mistnosti enable row level security;
alter table majetek_kategorie enable row level security;
alter table majetek_cisla enable row level security;
alter table majetek enable row level security;
alter table majetek_pohyby enable row level security;
alter table majetek_kontroly enable row level security;
alter table inventury enable row level security;
alter table inventura_mistnosti enable row level security;
alter table inventura_zaznamy enable row level security;
alter table inventura_nalezy enable row level security;

drop policy if exists mis_cist on mistnosti;
create policy mis_cist on mistnosti for select using (skola_id = moje_skola() and moje_role() in ('reditelka', 'zastupce', 'hospodarka', 'ucitelka'));
drop policy if exists mkat_cist on majetek_kategorie;
create policy mkat_cist on majetek_kategorie for select using (skola_id = moje_skola() and moje_role() in ('reditelka', 'zastupce', 'hospodarka', 'ucitelka'));
drop policy if exists maj_cist on majetek;
create policy maj_cist on majetek for select using (skola_id = moje_skola() and (je_majetek() or (moje_role() = 'ucitelka' and moje_mistnost(mistnost_id))));
drop policy if exists mpoh_cist on majetek_pohyby;
create policy mpoh_cist on majetek_pohyby for select using (skola_id = moje_skola() and je_majetek());
drop policy if exists mkon_cist on majetek_kontroly;
create policy mkon_cist on majetek_kontroly for select using (skola_id = moje_skola() and je_majetek());
drop policy if exists inv_cist on inventury;
create policy inv_cist on inventury for select using (skola_id = moje_skola() and moje_role() in ('reditelka', 'zastupce', 'hospodarka', 'ucitelka'));
drop policy if exists invm_cist on inventura_mistnosti;
create policy invm_cist on inventura_mistnosti for select using (exists (select 1 from inventury i where i.id = inventura_id and i.skola_id = moje_skola())
  and (je_majetek() or (moje_role() = 'ucitelka' and moje_mistnost(mistnost_id))));
drop policy if exists invz_cist on inventura_zaznamy;
create policy invz_cist on inventura_zaznamy for select using (exists (select 1 from inventury i where i.id = inventura_id and i.skola_id = moje_skola())
  and (je_majetek() or (moje_role() = 'ucitelka' and (moje_mistnost(nalezeno_v) or exists (select 1 from majetek m where m.id = polozka_id and moje_mistnost(m.mistnost_id))))));
drop policy if exists invn_cist on inventura_nalezy;
create policy invn_cist on inventura_nalezy for select using (exists (select 1 from inventury i where i.id = inventura_id and i.skola_id = moje_skola())
  and (je_majetek() or (moje_role() = 'ucitelka' and moje_mistnost(mistnost_id))));

revoke insert, update, delete, truncate on mistnosti, majetek_kategorie, majetek_cisla, majetek, majetek_pohyby, majetek_kontroly,
  inventury, inventura_mistnosti, inventura_zaznamy, inventura_nalezy from authenticated, anon;
grant select on mistnosti, majetek_kategorie, majetek, majetek_pohyby, majetek_kontroly, inventury, inventura_mistnosti, inventura_zaznamy, inventura_nalezy to authenticated;
revoke all on majetek_cisla from authenticated, anon;

drop trigger if exists a_majetek on majetek;
create trigger a_majetek after insert or update on majetek for each row execute function zapis_audit();

-- ---------------------------------------------------------------- pomocné
create or replace function maj_kontrola() returns uuid language plpgsql stable security definer set search_path = public as $$
begin
  if not je_majetek() then raise exception 'Majetek spravuje vedení školy nebo hospodářka.'; end if;
  return moje_skola();
end $$;

create or replace function maj_pohyb(p_polozka uuid, p_druh text, p_popis text) returns void
language sql security definer set search_path = public as $$
  insert into majetek_pohyby (skola_id, polozka_id, druh, popis) select skola_id, id, p_druh, left(coalesce(p_popis, ''), 500) from majetek where id = p_polozka
$$;

create or replace function maj_mistnost(p_skola uuid, p_mistnost uuid) returns uuid language plpgsql stable security definer set search_path = public as $$
begin
  if p_mistnost is null then return null; end if;
  if not exists (select 1 from mistnosti where id = p_mistnost and skola_id = p_skola) then raise exception 'Místnost do školky nepatří.'; end if;
  return p_mistnost;
end $$;

create or replace function maj_nazev_mistnosti(p uuid) returns text language sql stable security definer set search_path = public as
  $$ select coalesce((select nazev from mistnosti where id = p), 'bez místnosti') $$;

revoke execute on function maj_kontrola(), maj_pohyb(uuid, text, text), maj_mistnost(uuid, uuid), maj_nazev_mistnosti(uuid) from anon, public, authenticated;

-- ---------------------------------------------------------------- výchozí nastavení
-- Kategorie a místnosti (z tříd + kuchyně, kancelář, zahrada, sklad). Opakování nic nezdvojí.
create or replace function majetek_priprav() returns void language plpgsql security definer set search_path = public as $$
declare s uuid := maj_kontrola();
begin
  insert into majetek_kategorie (skola_id, kod, nazev, poradi) values
    (s, 'IT', 'IT', 1), (s, 'NAB', 'Nábytek', 2), (s, 'VYB', 'Vybavení tříd', 3), (s, 'HRA', 'Hračky a pomůcky', 4),
    (s, 'KUC', 'Kuchyně', 5), (s, 'ZAH', 'Zahrada', 6), (s, 'TEX', 'Textil', 7), (s, 'UKL', 'Úklid a údržba', 8)
  on conflict do nothing;
  insert into mistnosti (skola_id, nazev, trida_id, poradi)
  select s, t.nazev, t.id, 10 + row_number() over (order by t.nazev) from tridy t where t.skola_id = s
     and not exists (select 1 from mistnosti m where m.trida_id = t.id)
  on conflict (skola_id, nazev) do nothing;
  insert into mistnosti (skola_id, nazev, poradi) values (s, 'Kuchyně', 50), (s, 'Kancelář', 51), (s, 'Zahrada', 52), (s, 'Sklad', 53)
  on conflict (skola_id, nazev) do nothing;
end $$;

create or replace function uloz_mistnost(p_id uuid, p_nazev text, p_trida uuid default null, p_aktivni boolean default true) returns uuid
language plpgsql security definer set search_path = public as $$
declare s uuid := maj_kontrola(); r uuid;
begin
  if coalesce(btrim(p_nazev), '') = '' then raise exception 'Napište název místnosti.'; end if;
  if p_trida is not null and not exists (select 1 from tridy where id = p_trida and skola_id = s) then raise exception 'Třída do školky nepatří.'; end if;
  if p_id is null then
    insert into mistnosti (skola_id, nazev, trida_id) values (s, btrim(p_nazev), p_trida) returning id into r;
  else
    update mistnosti set nazev = btrim(p_nazev), trida_id = p_trida, aktivni = coalesce(p_aktivni, true) where id = p_id and skola_id = s returning id into r;
    if r is null then raise exception 'Místnost nenalezena.'; end if;
  end if;
  return r;
exception when unique_violation then raise exception 'Místnost „%“ už existuje.', btrim(p_nazev);
end $$;

create or replace function uloz_kategorii(p_kod text, p_nazev text) returns void language plpgsql security definer set search_path = public as $$
declare s uuid := maj_kontrola(); k text := upper(btrim(coalesce(p_kod, '')));
begin
  if k !~ '^[A-Z]{2,4}$' then raise exception 'Zkratka kategorie má 2–4 velká písmena bez diakritiky (např. IT, NAB).'; end if;
  if coalesce(btrim(p_nazev), '') = '' then raise exception 'Napište název kategorie.'; end if;
  insert into majetek_kategorie (skola_id, kod, nazev) values (s, k, btrim(p_nazev))
  on conflict (skola_id, kod) do update set nazev = excluded.nazev;
end $$;

-- ---------------------------------------------------------------- položky
-- Vnitřní: založí p_pocet kusů, vrací jejich id. Číslo KAT-ROK-POŘADÍ.
create or replace function maj_zaloz(s uuid, p jsonb, p_pocet int, p_popis text) returns uuid[]
language plpgsql security definer set search_path = public as $$
declare
  kat text := upper(btrim(coalesce(p->>'kategorie', ''))); v_rok int; od int; i int; nid uuid; ids uuid[] := '{}';
  datum date := nullif(p->>'porizeno', '')::date; cena numeric := nullif(p->>'cena', '')::numeric; ud text;
begin
  if p_pocet is null or p_pocet < 1 or p_pocet > 500 then raise exception 'Počet kusů musí být 1–500.'; end if;
  if not exists (select 1 from majetek_kategorie where skola_id = s and kod = kat) then raise exception 'Neznámá kategorie %.', kat; end if;
  if coalesce(btrim(p->>'nazev'), '') = '' then raise exception 'Napište název položky.'; end if;
  if datum is not null and (datum > (now() at time zone 'Europe/Prague')::date + 31 or datum < date '1950-01-01') then raise exception 'Datum pořízení nesedí.'; end if;
  v_rok := coalesce(extract(year from datum)::int, extract(year from now() at time zone 'Europe/Prague')::int);
  ud := coalesce(nullif(p->>'ucetni_druh', ''), case when cena > 40000 then 'dhm' when cena >= 1000 then 'ddhm' else 'oe' end);
  insert into majetek_cisla (skola_id, kod, rok, posledni) values (s, kat, v_rok, 0) on conflict do nothing;
  update majetek_cisla set posledni = posledni + p_pocet where skola_id = s and kod = kat and majetek_cisla.rok = v_rok returning posledni - p_pocet into od;
  for i in 1..p_pocet loop
    insert into majetek (skola_id, cislo, kategorie, rok, poradi, nazev, druh, mistnost_id, odpovida, vyrobce, seriove, porizeno, cena, dodavatel, doklad,
                         ucetni_druh, zaruka_do, financovani, puvodni_cislo, poznamka)
    values (s, kat || '-' || v_rok || '-' || lpad((od + i)::text, 4, '0'), kat, v_rok, od + i, btrim(p->>'nazev'), coalesce(btrim(p->>'druh'), ''),
            maj_mistnost(s, nullif(p->>'mistnost_id', '')::uuid), coalesce(btrim(p->>'odpovida'), ''), coalesce(btrim(p->>'vyrobce'), ''),
            coalesce(btrim(p->>'seriove'), ''), datum, cena, coalesce(btrim(p->>'dodavatel'), ''), coalesce(btrim(p->>'doklad'), ''),
            ud, nullif(p->>'zaruka_do', '')::date, coalesce(btrim(p->>'financovani'), ''), coalesce(btrim(p->>'puvodni_cislo'), ''), coalesce(p->>'poznamka', ''))
    returning id into nid;
    ids := ids || nid;
    insert into majetek_pohyby (skola_id, polozka_id, druh, popis) values (s, nid, 'zarazeno', coalesce(p_popis, 'Zařazeno do evidence') || ' · ' || maj_nazev_mistnosti(nullif(p->>'mistnost_id', '')::uuid));
  end loop;
  return ids;
end $$;
revoke execute on function maj_zaloz(uuid, jsonb, int, text) from anon, public, authenticated;

-- Nová položka (i více stejných kusů). Vrací přidělená čísla.
create or replace function nova_polozka(p jsonb, p_pocet int default 1) returns text[]
language plpgsql security definer set search_path = public as $$
declare s uuid := maj_kontrola(); ids uuid[];
begin
  ids := maj_zaloz(s, p, coalesce(p_pocet, 1), null);
  return array(select cislo from majetek where id = any(ids) order by poradi);
end $$;

-- Úprava údajů (ne kategorie ani číslo — ty zůstávají napořád).
create or replace function uprav_polozku(p_id uuid, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare s uuid := maj_kontrola(); m majetek;
begin
  select * into m from majetek where id = p_id and skola_id = s;
  if not found then raise exception 'Položka nenalezena.'; end if;
  if m.stav = 'vyrazeno' then raise exception 'Vyřazenou položku už nejde měnit.'; end if;
  if coalesce(btrim(p->>'nazev'), '') = '' then raise exception 'Napište název položky.'; end if;
  update majetek set nazev = btrim(p->>'nazev'), druh = coalesce(btrim(p->>'druh'), ''), odpovida = coalesce(btrim(p->>'odpovida'), ''),
    vyrobce = coalesce(btrim(p->>'vyrobce'), ''), seriove = coalesce(btrim(p->>'seriove'), ''), porizeno = nullif(p->>'porizeno', '')::date,
    cena = nullif(p->>'cena', '')::numeric, dodavatel = coalesce(btrim(p->>'dodavatel'), ''), doklad = coalesce(btrim(p->>'doklad'), ''),
    ucetni_druh = coalesce(nullif(p->>'ucetni_druh', ''), ucetni_druh), zaruka_do = nullif(p->>'zaruka_do', '')::date,
    financovani = coalesce(btrim(p->>'financovani'), ''), puvodni_cislo = coalesce(btrim(p->>'puvodni_cislo'), ''), poznamka = coalesce(p->>'poznamka', '')
  where id = p_id;
  perform maj_pohyb(p_id, 'uprava', 'Upraveny údaje');
end $$;

create or replace function presun_polozky(p_ids uuid[], p_mistnost uuid, p_poznamka text default '') returns int
language plpgsql security definer set search_path = public as $$
declare s uuid := maj_kontrola(); m record; n int := 0; kam uuid := maj_mistnost(s, p_mistnost);
begin
  if kam is null then raise exception 'Vyberte místnost.'; end if;
  for m in select * from majetek where id = any(p_ids) and skola_id = s and stav <> 'vyrazeno' and mistnost_id is distinct from kam loop
    update majetek set mistnost_id = kam where id = m.id;
    perform maj_pohyb(m.id, 'presun', 'Přesun ' || maj_nazev_mistnosti(m.mistnost_id) || ' → ' || maj_nazev_mistnosti(kam) || coalesce(nullif(' · ' || btrim(p_poznamka), ' · '), ''));
    n := n + 1;
  end loop;
  return n;
end $$;

create or replace function zapujc_polozku(p_id uuid, p_komu text, p_do date) returns void
language plpgsql security definer set search_path = public as $$
declare s uuid := maj_kontrola();
begin
  if coalesce(btrim(p_komu), '') = '' then raise exception 'Napište, komu se půjčuje.'; end if;
  update majetek set stav = 'zapujceno', zapujceno_komu = btrim(p_komu), zapujceno_do = p_do where id = p_id and skola_id = s and stav in ('ok', 'poskozeno');
  if not found then raise exception 'Položku teď nejde zapůjčit.'; end if;
  perform maj_pohyb(p_id, 'zapujceni', 'Zapůjčeno: ' || btrim(p_komu) || coalesce(', vrátit do ' || to_char(p_do, 'FMDD. FMMM. YYYY'), ''));
end $$;

create or replace function vrat_polozku(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare s uuid := maj_kontrola();
begin
  update majetek set stav = 'ok', zapujceno_komu = '', zapujceno_do = null where id = p_id and skola_id = s and stav = 'zapujceno';
  if not found then raise exception 'Položka není zapůjčená.'; end if;
  perform maj_pohyb(p_id, 'vraceni', 'Vráceno');
end $$;

-- Závadu nahlásí i učitelka (u majetku svých tříd).
create or replace function nahlas_zavadu(p_id uuid, p_popis text) returns void
language plpgsql security definer set search_path = public as $$
declare m majetek;
begin
  select * into m from majetek where id = p_id and skola_id = moje_skola();
  if not found or not (je_majetek() or (moje_role() = 'ucitelka' and moje_mistnost(m.mistnost_id))) then raise exception 'Položka nenalezena.'; end if;
  if m.stav = 'vyrazeno' then raise exception 'Položka je vyřazená.'; end if;
  if coalesce(btrim(p_popis), '') = '' then raise exception 'Napište, co se stalo.'; end if;
  update majetek set stav = 'poskozeno' where id = p_id;
  perform maj_pohyb(p_id, 'zavada', 'Závada: ' || btrim(p_popis));
end $$;

-- Stav po závadě: 'oprava' (odvezeno do opravy) nebo 'ok' (opraveno / v pořádku).
create or replace function oprav_polozku(p_id uuid, p_stav text, p_popis text default '') returns void
language plpgsql security definer set search_path = public as $$
declare s uuid := maj_kontrola();
begin
  if p_stav not in ('oprava', 'ok') then raise exception 'Neznámý stav.'; end if;
  update majetek set stav = p_stav where id = p_id and skola_id = s and stav in ('poskozeno', 'oprava', 'ok');
  if not found then raise exception 'Stav položky teď nejde změnit.'; end if;
  perform maj_pohyb(p_id, 'oprava', case p_stav when 'oprava' then 'V opravě' else 'Opraveno, v pořádku' end || coalesce(nullif(' · ' || btrim(p_popis), ' · '), ''));
end $$;

create or replace function vyrad_polozku(p_id uuid, p_duvod text, p_datum date default null) returns void
language plpgsql security definer set search_path = public as $$
declare s uuid := maj_kontrola();
begin
  if coalesce(btrim(p_duvod), '') = '' then raise exception 'Napište důvod vyřazení.'; end if;
  update majetek set stav = 'vyrazeno', vyrazeno = coalesce(p_datum, (now() at time zone 'Europe/Prague')::date), duvod_vyrazeni = btrim(p_duvod)
   where id = p_id and skola_id = s and stav <> 'vyrazeno';
  if not found then raise exception 'Položka už je vyřazená.'; end if;
  perform maj_pohyb(p_id, 'vyrazeni', 'Vyřazeno: ' || btrim(p_duvod));
end $$;

create or replace function stitky_vytisteny(p_ids uuid[]) returns int
language plpgsql security definer set search_path = public as $$
declare s uuid := maj_kontrola(); n int;
begin
  insert into majetek_pohyby (skola_id, polozka_id, druh, popis)
  select s, id, 'stitek', case when stitek_tisk is null then 'Vytištěn štítek' else 'Štítek vytištěn znovu' end from majetek where id = any(p_ids) and skola_id = s;
  update majetek set stitek_tisk = now() where id = any(p_ids) and skola_id = s;
  get diagnostics n = row_count;
  return n;
end $$;

-- Import ze staré evidence: [{nazev, kategorie, mistnost_id, cena, porizeno, puvodni_cislo, pocet, druh, poznamka}]
-- Řádek se stejným původním číslem, jaké už v evidenci je, se přeskočí.
create or replace function import_majetku(p_radky jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s uuid := maj_kontrola(); x jsonb; nove int := 0; preskoceno int := 0; ks int;
begin
  if jsonb_typeof(p_radky) <> 'array' or jsonb_array_length(p_radky) > 5000 then raise exception 'Neplatný import.'; end if;
  for x in select * from jsonb_array_elements(p_radky) loop
    if coalesce(btrim(x->>'puvodni_cislo'), '') <> '' and exists (select 1 from majetek where skola_id = s and puvodni_cislo = btrim(x->>'puvodni_cislo')) then
      preskoceno := preskoceno + 1; continue;
    end if;
    ks := greatest(1, least(coalesce(nullif(x->>'pocet', '')::int, 1), 500));
    perform maj_zaloz(s, x, ks, 'Převedeno ze staré evidence');
    nove := nove + ks;
  end loop;
  return jsonb_build_object('nove', nove, 'preskoceno', preskoceno);
end $$;

-- ---------------------------------------------------------------- revize a servis
create or replace function uloz_kontrolu(p_id uuid, p_polozka uuid, p_nazev text, p_interval int, p_dalsi date, p_poznamka text default '') returns uuid
language plpgsql security definer set search_path = public as $$
declare s uuid := maj_kontrola(); r uuid;
begin
  if coalesce(btrim(p_nazev), '') = '' or p_dalsi is null then raise exception 'Napište název a termín kontroly.'; end if;
  if p_polozka is not null and not exists (select 1 from majetek where id = p_polozka and skola_id = s) then raise exception 'Položka nenalezena.'; end if;
  if p_id is null then
    insert into majetek_kontroly (skola_id, polozka_id, nazev, interval_mesicu, dalsi, poznamka) values (s, p_polozka, btrim(p_nazev), p_interval, p_dalsi, coalesce(p_poznamka, '')) returning id into r;
  else
    update majetek_kontroly set nazev = btrim(p_nazev), interval_mesicu = p_interval, dalsi = p_dalsi, poznamka = coalesce(p_poznamka, '') where id = p_id and skola_id = s returning id into r;
    if r is null then raise exception 'Kontrola nenalezena.'; end if;
  end if;
  return r;
end $$;

-- Hotovo: zapíše se k položce a posune se další termín (bez intervalu se kontrola smaže).
create or replace function kontrola_hotova(p_id uuid, p_datum date, p_poznamka text default '') returns void
language plpgsql security definer set search_path = public as $$
declare s uuid := maj_kontrola(); k majetek_kontroly;
begin
  select * into k from majetek_kontroly where id = p_id and skola_id = s;
  if not found then raise exception 'Kontrola nenalezena.'; end if;
  if k.polozka_id is not null then perform maj_pohyb(k.polozka_id, 'kontrola', k.nazev || ' provedena ' || to_char(coalesce(p_datum, current_date), 'FMDD. FMMM. YYYY') || coalesce(nullif(' · ' || btrim(p_poznamka), ' · '), '')); end if;
  if k.interval_mesicu is null then delete from majetek_kontroly where id = p_id;
  else update majetek_kontroly set posledni = coalesce(p_datum, current_date), dalsi = (coalesce(p_datum, current_date) + make_interval(months => k.interval_mesicu))::date where id = p_id;
  end if;
end $$;

-- ---------------------------------------------------------------- inventura
create or replace function zahaj_inventuru(p_k_datu date, p_komise text[] default '{}') returns uuid
language plpgsql security definer set search_path = public as $$
declare s uuid; r uuid;
begin
  if moje_role() not in ('reditelka', 'zastupce') then raise exception 'Inventuru zahajuje vedení školy.'; end if;
  s := moje_skola();
  if p_k_datu is null then raise exception 'Zadejte, k jakému dni se inventura dělá.'; end if;
  if exists (select 1 from inventury where skola_id = s and uzavrena is null) then raise exception 'Jedna inventura už probíhá — nejdřív ji uzavřete.'; end if;
  insert into inventury (skola_id, k_datu, komise) values (s, p_k_datu, coalesce(p_komise, '{}')) returning id into r;
  insert into inventura_mistnosti (inventura_id, mistnost_id) select r, id from mistnosti where skola_id = s and aktivni;
  return r;
end $$;

create or replace function inventura_kontroluje(p_inventura uuid, p_mistnost uuid, p_kdo text) returns void
language plpgsql security definer set search_path = public as $$
declare s uuid := maj_kontrola();
begin
  update inventura_mistnosti im set kontroluje = left(btrim(coalesce(p_kdo, '')), 80)
    from inventury i where i.id = im.inventura_id and i.id = p_inventura and i.skola_id = s and i.uzavrena is null and im.mistnost_id = p_mistnost;
  if not found then raise exception 'Místnost v inventuře není.'; end if;
end $$;

-- Kdo smí skenovat v místnosti: vedení a hospodářka kdekoli, učitelka ve svých místnostech.
create or replace function inv_smi(p_inventura uuid, p_mistnost uuid) returns uuid
language plpgsql stable security definer set search_path = public as $$
declare s uuid := moje_skola();
begin
  if not exists (select 1 from inventury where id = p_inventura and skola_id = s and uzavrena is null) then raise exception 'Inventura neprobíhá.'; end if;
  if not exists (select 1 from inventura_mistnosti where inventura_id = p_inventura and mistnost_id = p_mistnost) then raise exception 'Místnost v inventuře není.'; end if;
  if not (je_majetek() or (moje_role() = 'ucitelka' and moje_mistnost(p_mistnost))) then raise exception 'V této místnosti inventuru dělá někdo jiný.'; end if;
  return s;
end $$;
revoke execute on function inv_smi(uuid, uuid) from anon, public, authenticated;

-- Načtený štítek (číslo nebo celý odkaz z QR). Vrací, co se s ním stalo.
create or replace function inventura_sken(p_inventura uuid, p_mistnost uuid, p_kod text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s uuid := inv_smi(p_inventura, p_mistnost); c text; m majetek; z inventura_zaznamy; vys text;
begin
  c := upper(substring(coalesce(p_kod, '') from '([A-Za-z]{2,4}-[0-9]{4}-[0-9]{4,})\s*$'));
  if c is null then return jsonb_build_object('vysledek', 'neznamy', 'kod', left(coalesce(p_kod, ''), 60)); end if;
  select * into m from majetek where skola_id = s and cislo = c;
  if not found then return jsonb_build_object('vysledek', 'neznamy', 'kod', c); end if;
  if m.stav = 'vyrazeno' then return jsonb_build_object('vysledek', 'vyrazeno', 'cislo', m.cislo, 'nazev', m.nazev); end if;
  vys := case when m.mistnost_id = p_mistnost then 'nalezeno' else 'jinde' end;
  select * into z from inventura_zaznamy where inventura_id = p_inventura and polozka_id = m.id;
  if found and z.vysledek = vys and z.nalezeno_v = p_mistnost then
    return jsonb_build_object('vysledek', 'uz', 'cislo', m.cislo, 'nazev', m.nazev);
  end if;
  insert into inventura_zaznamy (inventura_id, polozka_id, vysledek, nalezeno_v) values (p_inventura, m.id, vys, p_mistnost)
  on conflict (inventura_id, polozka_id) do update set vysledek = excluded.vysledek, nalezeno_v = excluded.nalezeno_v, kdy = now(), kdo = auth.uid(), vyreseno = null;
  return jsonb_build_object('vysledek', vys, 'cislo', m.cislo, 'nazev', m.nazev, 'patri', maj_nazev_mistnosti(m.mistnost_id));
end $$;

create or replace function inventura_bez_stitku(p_inventura uuid, p_mistnost uuid, p_popis text) returns uuid
language plpgsql security definer set search_path = public as $$
declare s uuid := inv_smi(p_inventura, p_mistnost); r uuid;
begin
  if coalesce(btrim(p_popis), '') = '' then raise exception 'Napište, co to je.'; end if;
  insert into inventura_nalezy (inventura_id, mistnost_id, popis) values (p_inventura, p_mistnost, btrim(p_popis)) returning id into r;
  return r;
end $$;

-- Místnost hotová: co v ní mělo být a nenašlo se, je „chybí“.
create or replace function inventura_mistnost_hotova(p_inventura uuid, p_mistnost uuid) returns int
language plpgsql security definer set search_path = public as $$
declare s uuid := inv_smi(p_inventura, p_mistnost); n int;
begin
  insert into inventura_zaznamy (inventura_id, polozka_id, vysledek)
  select p_inventura, m.id, 'chybi' from majetek m
   where m.skola_id = s and m.mistnost_id = p_mistnost and m.stav not in ('vyrazeno', 'zapujceno')
     and not exists (select 1 from inventura_zaznamy z where z.inventura_id = p_inventura and z.polozka_id = m.id)
  on conflict do nothing;
  get diagnostics n = row_count;
  update inventura_mistnosti set hotovo = now() where inventura_id = p_inventura and mistnost_id = p_mistnost;
  return n;
end $$;

-- Vyřešení rozdílu (vedení): presunuto / vraceno (u „jinde“), naslo_se / vyrazeno / ponechano (u „chybí“).
create or replace function inventura_vyres(p_inventura uuid, p_polozka uuid, p_jak text) returns void
language plpgsql security definer set search_path = public as $$
declare s uuid := maj_kontrola(); z inventura_zaznamy; m majetek;
begin
  select z2.* into z from inventura_zaznamy z2 join inventury i on i.id = z2.inventura_id
   where z2.inventura_id = p_inventura and z2.polozka_id = p_polozka and i.skola_id = s and i.uzavrena is null;
  if not found then raise exception 'Rozdíl nenalezen.'; end if;
  select * into m from majetek where id = p_polozka;
  if z.vysledek = 'jinde' and p_jak = 'presunuto' then
    perform presun_polozky(array[p_polozka], z.nalezeno_v, 'při inventuře');
  elsif z.vysledek = 'jinde' and p_jak = 'vraceno' then
    perform maj_pohyb(p_polozka, 'inventura', 'Při inventuře nalezeno v ' || maj_nazev_mistnosti(z.nalezeno_v) || ', vráceno na místo');
  elsif z.vysledek = 'chybi' and p_jak = 'naslo_se' then
    update inventura_zaznamy set vysledek = 'nalezeno', nalezeno_v = m.mistnost_id, vyreseno = 'naslo_se' where inventura_id = p_inventura and polozka_id = p_polozka;
    return;
  elsif z.vysledek = 'chybi' and p_jak = 'vyrazeno' then
    perform vyrad_polozku(p_polozka, 'Manko zjištěné při inventuře k ' || (select to_char(k_datu, 'FMDD. FMMM. YYYY') from inventury where id = p_inventura));
  elsif z.vysledek = 'chybi' and p_jak = 'ponechano' then
    perform maj_pohyb(p_polozka, 'inventura', 'Při inventuře nenalezeno, zatím ponecháno v evidenci');
  else
    raise exception 'Takhle rozdíl vyřešit nejde.';
  end if;
  update inventura_zaznamy set vyreseno = p_jak where inventura_id = p_inventura and polozka_id = p_polozka;
end $$;

-- Věc bez štítku: založit jako novou položku (p jsonb jako u nova_polozka), nebo zrušit.
create or replace function inventura_nalez_vyres(p_nalez uuid, p jsonb) returns text
language plpgsql security definer set search_path = public as $$
declare s uuid := maj_kontrola(); n inventura_nalezy; ids uuid[];
begin
  select x.* into n from inventura_nalezy x join inventury i on i.id = x.inventura_id where x.id = p_nalez and i.skola_id = s and i.uzavrena is null and x.vyreseno is null;
  if not found then raise exception 'Nález nenalezen.'; end if;
  if p is null then update inventura_nalezy set vyreseno = 'zruseno' where id = p_nalez; return null; end if;
  ids := maj_zaloz(s, jsonb_set(p, '{mistnost_id}', to_jsonb(n.mistnost_id::text)), 1, 'Nalezeno při inventuře (přebytek)');
  update inventura_nalezy set vyreseno = 'zalozeno', polozka_id = ids[1] where id = p_nalez;
  insert into inventura_zaznamy (inventura_id, polozka_id, vysledek, nalezeno_v) values (n.inventura_id, ids[1], 'nalezeno', n.mistnost_id);
  return (select cislo from majetek where id = ids[1]);
end $$;

create or replace function uzavri_inventuru(p_inventura uuid) returns void
language plpgsql security definer set search_path = public as $$
declare s uuid; x int;
begin
  if moje_role() not in ('reditelka', 'zastupce') then raise exception 'Inventuru uzavírá vedení školy.'; end if;
  s := moje_skola();
  if not exists (select 1 from inventury where id = p_inventura and skola_id = s and uzavrena is null) then raise exception 'Inventura neprobíhá.'; end if;
  select count(*) into x from inventura_mistnosti where inventura_id = p_inventura and hotovo is null;
  if x > 0 then raise exception 'Ještě % % bez kontroly.', x, case when x = 1 then 'místnost je' when x < 5 then 'místnosti jsou' else 'místností je' end; end if;
  select count(*) into x from inventura_zaznamy where inventura_id = p_inventura and vysledek <> 'nalezeno' and vyreseno is null;
  x := x + (select count(*) from inventura_nalezy where inventura_id = p_inventura and vyreseno is null);
  if x > 0 then raise exception 'Nejdřív vyřešte rozdíly (zbývá %).', x; end if;
  insert into majetek_pohyby (skola_id, polozka_id, druh, popis)
  select s, z.polozka_id, 'inventura', 'Inventura k ' || to_char(i.k_datu, 'FMDD. FMMM. YYYY') || ': nalezeno · ' || maj_nazev_mistnosti(z.nalezeno_v)
    from inventura_zaznamy z join inventury i on i.id = z.inventura_id where z.inventura_id = p_inventura and z.vysledek = 'nalezeno';
  update inventury set uzavrena = now() where id = p_inventura;
end $$;

-- ---------------------------------------------------------------- práva na funkce
revoke execute on function je_majetek(), moje_mistnost(uuid), majetek_priprav(), uloz_mistnost(uuid, text, uuid, boolean), uloz_kategorii(text, text),
  nova_polozka(jsonb, int), uprav_polozku(uuid, jsonb), presun_polozky(uuid[], uuid, text), zapujc_polozku(uuid, text, date), vrat_polozku(uuid),
  nahlas_zavadu(uuid, text), oprav_polozku(uuid, text, text), vyrad_polozku(uuid, text, date), stitky_vytisteny(uuid[]), import_majetku(jsonb),
  uloz_kontrolu(uuid, uuid, text, int, date, text), kontrola_hotova(uuid, date, text), zahaj_inventuru(date, text[]), inventura_kontroluje(uuid, uuid, text),
  inventura_sken(uuid, uuid, text), inventura_bez_stitku(uuid, uuid, text), inventura_mistnost_hotova(uuid, uuid), inventura_vyres(uuid, uuid, text),
  inventura_nalez_vyres(uuid, jsonb), uzavri_inventuru(uuid) from anon, public;
grant execute on function je_majetek(), moje_mistnost(uuid), majetek_priprav(), uloz_mistnost(uuid, text, uuid, boolean), uloz_kategorii(text, text),
  nova_polozka(jsonb, int), uprav_polozku(uuid, jsonb), presun_polozky(uuid[], uuid, text), zapujc_polozku(uuid, text, date), vrat_polozku(uuid),
  nahlas_zavadu(uuid, text), oprav_polozku(uuid, text, text), vyrad_polozku(uuid, text, date), stitky_vytisteny(uuid[]), import_majetku(jsonb),
  uloz_kontrolu(uuid, uuid, text, int, date, text), kontrola_hotova(uuid, date, text), zahaj_inventuru(date, text[]), inventura_kontroluje(uuid, uuid, text),
  inventura_sken(uuid, uuid, text), inventura_bez_stitku(uuid, uuid, text), inventura_mistnost_hotova(uuid, uuid), inventura_vyres(uuid, uuid, text),
  inventura_nalez_vyres(uuid, jsonb), uzavri_inventuru(uuid) to authenticated;

-- Archiv: u změn majetku ukázat inventární číslo.
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
           when 'majetek' then coalesce(a.zmena -> 'po' ->> 'cislo', a.zmena ->> 'cislo') || ' ' || coalesce(a.zmena -> 'po' ->> 'nazev', a.zmena ->> 'nazev')
           else null end
    from audit_log a
    left join uzivatele u on u.id = a.kdo
   where a.skola_id = moje_skola()
   order by a.kdy desc, a.id desc
   limit least(greatest(coalesce(p_limit, 300), 1), 1000);
end $$;
