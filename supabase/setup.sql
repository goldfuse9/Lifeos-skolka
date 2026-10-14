-- Školka — celé nastavení databáze pro Supabase (schema.sql + pilot.sql + doplňky vč. superadmina).
-- Vložte celé do Supabase → SQL Editor → New query → Run. Spouští se jednou.

-- =============================================================================
-- Školka — datový model pro ostrý provoz (Supabase / PostgreSQL)
-- -----------------------------------------------------------------------------
-- Prototyp v tomhle repozitáři běží bez serveru. Aby šly skutečné údaje dětí
-- sdílet mezi tablety tříd, ředitelnou a rodiči, potřebuje to databázi
-- s přihlášením a právy podle role. Tohle je výchozí návrh:
--
--   ředitelka   vidí a mění vše ve své škole, včetně jídelny
--   zástupce    jako ředitelka (bez jídelny); když učí, má i tablet své třídy
--   učitelka    vidí děti svých tříd (dnes i přesunuté), zapisuje docházku,
--               úrazy, třídní knihu; nevidí platby ani rodná čísla
--   hospodářka  platby, stravné, docházku a kontakty; nemění matriku
--   kuchařka    jen jídelna: jídelníček, jídla a suroviny, diety (z dětí vidí
--               jméno, třídu, alergie a dnešní docházku — nic dalšího)
--   rodič       jen své děti: omluvenky, pověřené osoby, souhlasy, zprávy
--
-- Kam se kdo přihlásí (desky aplikace):
--   ředitelna  ← ředitelka, zástupce, hospodářka   (webová aplikace vedení)
--   jídelna    ← kuchařka, ředitelka
--   tablet     ← učitelka, zástupce, který učí
--   LifeOS     ← rodič — mobilní aplikace LifeOS se připojí ke stejné
--               databázi jako role 'rodic'; vidí jen to, co pustí tyto zásady
--               (RLS), takže tablet, ředitelna, jídelna i LifeOS sdílejí
--               jedna data a nikdo nevidí víc, než má.
--
-- Každá změna osobních údajů jde do audit_log (kdo, kdy, co) — GDPR.
-- =============================================================================

create extension if not exists pgcrypto;

create type role_t as enum ('reditelka', 'zastupce', 'ucitelka', 'hospodarka', 'kucharka', 'rodic');

create table skoly (
  id uuid primary key default gen_random_uuid(),
  nazev text not null,
  izo text not null, red_izo text not null, cast_skoly text not null default '01',
  rozliseni text not null default 'bez', doba_provozu numeric(4,1),
  kontakt text
);

create table uzivatele (
  id uuid primary key references auth.users on delete cascade,
  skola_id uuid not null references skoly,
  jmeno text not null,
  role role_t not null,
  uvazek numeric(3,2) default 1,
  zdravotni_prukaz boolean,            -- jen personál jídelny
  skoleni_hygieny date                 -- jen personál jídelny
);

create table tridy (
  id uuid primary key default gen_random_uuid(),
  skola_id uuid not null references skoly,
  nazev text not null, kod text not null, barva text,
  kapacita int not null, provoz char(1) not null default 'C'      -- C celodenní, P polodenní
);

create table ucitel_trida (
  ucitel_id uuid references uzivatele on delete cascade,
  trida_id uuid references tridy on delete cascade,
  primary key (ucitel_id, trida_id)
);

create table deti (
  id uuid primary key default gen_random_uuid(),
  skola_id uuid not null references skoly,
  trida_id uuid references tridy,
  jmeno text not null, prijmeni text not null,
  rodne_cislo text,                    -- nebo kod_cizince (RRMMDDX000)
  kod_cizince text,
  datum_narozeni date not null, pohlavi char(1) not null,
  obcanstvi text not null default 'CZ', znalost_cj text,
  obec text, adresa text, dorucovaci_adresa text, spadovy boolean default true,
  zahajeni date not null, kod_zahajeni text, zpusob_ppv text, odklad boolean default false,
  po_stupen int default 0 check (po_stupen between 0 and 5),
  spz text, spz_plati_do date, ivp boolean default false, asistent boolean default false, plpp_do date,
  iv_overeni text,                     -- 'ok' / 'ne' u individuálního vzdělávání
  pojistovna text, ockovani boolean, alergie text,
  variabilni_symbol text check (variabilni_symbol ~ '^[0-9]{1,10}$'),
  osvobozen_od_skolkovneho boolean not null default false,   -- PPV, odklad: školkovné 0 Kč
  ukonceno date, duvod_ukonceni text,
  vytvoreno timestamptz default now(),
  unique (skola_id, variabilni_symbol)
);

create table zastupci (
  id uuid primary key default gen_random_uuid(),
  dite_id uuid not null references deti on delete cascade,
  uzivatel_id uuid references uzivatele,      -- účet rodiče v aplikaci
  jmeno text not null, telefon text, email text, poradi int default 1
);

create table poverene_osoby (
  id uuid primary key default gen_random_uuid(),
  dite_id uuid not null references deti on delete cascade,
  jmeno text not null, zmocneni_od date not null default current_date, zruseno date
);

create table souhlasy (
  dite_id uuid references deti on delete cascade,
  druh text not null,                  -- 'foto_trida', 'foto_web', 'jmeno'
  udelen boolean not null, zmeneno timestamptz default now(), zmenil uuid references uzivatele,
  primary key (dite_id, druh)
);

create table dochazka (
  dite_id uuid references deti on delete cascade,
  den date not null,
  stav text not null,                  -- 'pritomen', 'omluven', 'neomluven'
  prichod time, odchod time, vyzvedl text, omluvenka text,
  trida_dnes uuid references tridy,    -- přesun / sloučení tříd na den
  strava_prihlasena boolean not null default true,
  omluva_zadana timestamptz,           -- kdy rodič omluvil; včas = do uzávěrky školky
  primary key (dite_id, den)
);

create table urazy (
  id uuid primary key default gen_random_uuid(),
  skola_id uuid not null references skoly,
  cislo int not null, rok int not null,
  dite_id uuid not null references deti,
  kdy timestamptz not null, kde text, co text not null, osetreni text, svedek text,
  komentar text,                         -- volný komentář učitelky z tabletu
  zapsal uuid not null references uzivatele,
  dny_absence int default 0, zaznam_odeslan date,
  unique (skola_id, rok, cislo)
);

create table tridni_kniha (
  trida_id uuid references tridy on delete cascade,
  den date not null,
  tema text not null, cinnosti text[] not null, pouceni text[] not null default '{}',
  pritomno int, chybelo int, zapsal uuid references uzivatele,
  primary key (trida_id, den)
);

create table zadosti (                 -- zápis / přijímací řízení
  id uuid primary key default gen_random_uuid(),
  skola_id uuid not null references skoly,
  rok int not null, reg_cislo text not null,
  jmeno text not null, rodne_cislo text not null, datum_narozeni date not null,
  spadovy boolean, sourozenec boolean,
  poradi int, vysledek text,           -- 'prijato' / 'neprijato'
  rozhodnuti_odeslano date,
  unique (skola_id, rok, reg_cislo)
);

-- ----------------------------------------------------------------- finance
-- Všechny částky NUMERIC(10, 2) — nikdy float. Konto dítěte drží zůstatek
-- (kladný = přeplatek, záporný = dluh); každý pohyb jde podvojně do knihy
-- ucetni_pohyby, která se jen doplňuje (oprava = protizápis, ne úprava).
create table financni_nastaveni (
  skola_id uuid primary key references skoly on delete cascade,
  ucet text not null,                          -- číslo účtu školky (předčíslí-číslo/banka) nebo IBAN
  skolkovne numeric(10,2) not null check (skolkovne >= 0),
  omluva_dni_predem int not null default 1 check (omluva_dni_predem between 0 and 7),
  omluva_do time not null default '08:00',
  splatnost_den int not null default 15 check (splatnost_den between 1 and 28),
  vs_schema text not null default 'rok_poradi' check (vs_schema in ('rok_poradi', 'prefix_poradi', 'rucne')),
  vs_prefix text not null default '' check (vs_prefix ~ '^[0-9]{0,6}$'),
  vs_delka int not null default 6 check (vs_delka between 4 and 10)
);

create table sazby_stravneho (
  skola_id uuid references skoly on delete cascade,
  kategorie text not null check (kategorie in ('3-6', '7+')),
  cena numeric(10,2) not null check (cena >= 0),
  primary key (skola_id, kategorie)
);

create table konta (
  dite_id uuid primary key references deti on delete cascade,
  saldo numeric(10,2) not null default 0
);

create table ucetni_pohyby (
  id uuid primary key default gen_random_uuid(),
  skola_id uuid not null references skoly,
  datum date not null,
  md text not null,                            -- má dáti: 'dite:<uuid>', 'banka', 'vynosy:skolkovne' …
  dal text not null,
  castka numeric(10,2) not null check (castka > 0),
  popis text not null,
  doklad text not null default '',             -- id předpisu nebo platby
  vytvoreno timestamptz not null default now(),
  check (md <> dal)
);
create index on ucetni_pohyby (skola_id, md);
create index on ucetni_pohyby (skola_id, dal);

create table predpisy (
  id uuid primary key default gen_random_uuid(),
  dite_id uuid not null references deti on delete cascade,
  obdobi char(7) not null check (obdobi ~ '^[0-9]{4}-[0-9]{2}$'),   -- '2026-10'
  castka numeric(10,2) not null check (castka >= 0),
  uhrazeno numeric(10,2) not null default 0 check (uhrazeno >= 0),
  stav text not null default 'otevreno' check (stav in ('otevreno', 'castecne_zaplaceno', 'zaplaceno')),
  splatnost date not null,
  vystaveno date not null default current_date,
  unique (dite_id, obdobi)
);

create table predpis_polozky (
  predpis_id uuid references predpisy on delete cascade,
  poradi int not null,
  druh text not null check (druh in ('skolkovne', 'stravne')),
  popis text not null,
  mnozstvi int not null,
  cena numeric(10,2) not null,
  castka numeric(10,2) not null,
  primary key (predpis_id, poradi)
);

create table platby (
  id uuid primary key default gen_random_uuid(),
  skola_id uuid not null references skoly,
  datum date not null,
  castka numeric(10,2) not null check (castka > 0),
  vs text not null default '',
  protiucet text not null default '', nazev text not null default '',
  zdroj text not null default 'gpc',           -- 'gpc' | 'api' | 'rucne'
  doklad text not null default '',             -- číslo dokladu banky
  dite_id uuid references deti,
  nacteno timestamptz not null default now()
);
create unique index platby_doklad on platby (skola_id, doklad) where doklad <> '';

create table nesparovane_platby (
  platba_id uuid primary key references platby on delete cascade,
  duvod text not null,
  vyreseno boolean not null default false,
  vyresil uuid references uzivatele,
  vyreseno_kdy timestamptz
);

create table upominky (
  id uuid primary key default gen_random_uuid(),
  dite_id uuid not null references deti on delete cascade,
  obdobi char(7) not null,
  kanal text not null check (kanal in ('push', 'email')),
  odeslano timestamptz not null default now()
);

-- Zůstatek konta se upraví s každým pohybem; pohyby se nemažou ani nemění.
create or replace function pohyb_do_konta() returns trigger language plpgsql as $$
begin
  if new.md like 'dite:%' then
    insert into konta (dite_id, saldo) values (substr(new.md, 6)::uuid, -new.castka)
      on conflict (dite_id) do update set saldo = konta.saldo - new.castka;
  end if;
  if new.dal like 'dite:%' then
    insert into konta (dite_id, saldo) values (substr(new.dal, 6)::uuid, new.castka)
      on conflict (dite_id) do update set saldo = konta.saldo + new.castka;
  end if;
  return new;
end $$;
create trigger t_pohyb_do_konta after insert on ucetni_pohyby for each row execute function pohyb_do_konta();

create or replace function pohyby_jen_pridavat() returns trigger language plpgsql as $$
begin raise exception 'Účetní pohyby se nemění ani nemažou — opravte je protizápisem.'; end $$;
create trigger t_pohyby_jen_pridavat before update or delete on ucetni_pohyby for each row execute function pohyby_jen_pridavat();

create table zpravy (
  id uuid primary key default gen_random_uuid(),
  skola_id uuid not null references skoly,
  komu text not null, predmet text not null, text text not null,
  odeslal uuid references uzivatele, odeslano timestamptz default now()
);

create table porady (
  id uuid primary key default gen_random_uuid(),
  skola_id uuid not null references skoly,
  den date not null, druh text not null, program text not null, usneseni text, pritomni text[]
);

-- ----------------------------------------------------------------- jídelna
create table suroviny (
  id uuid primary key default gen_random_uuid(),
  skola_id uuid not null references skoly,
  nazev text not null,
  alergeny smallint[] not null default '{}'  -- 1–14 podle nařízení EU 1169/2011
);
create table jidla (
  id uuid primary key default gen_random_uuid(),
  skola_id uuid not null references skoly,
  nazev text not null,
  druh text not null check (druh in ('svacina', 'polevka', 'obed', 'napoj'))
);
create table jidlo_suroviny (
  jidlo_id uuid references jidla on delete cascade,
  surovina_id uuid references suroviny,
  primary key (jidlo_id, surovina_id)
);
create table nahrady (                  -- co dostanou děti bez daného alergenu
  jidlo_id uuid references jidla on delete cascade,
  alergen smallint not null check (alergen between 1 and 14),
  text text not null,
  primary key (jidlo_id, alergen)
);
create table jidelnicek (
  skola_id uuid not null references skoly,
  den date not null,
  chod text not null check (chod in ('prs', 'pol', 'obed', 'sv', 'nap')),
  jidlo_id uuid references jidla,
  zverejneno boolean not null default false,
  primary key (skola_id, den, chod)
);
create table diety (                    -- co si kuchyně vede k dítěti sama
  dite_id uuid primary key references deti on delete cascade,
  doporuceni_lekare boolean not null default false,
  poznamka text
);

create table audit_log (
  id bigserial primary key,
  skola_id uuid, kdo uuid, kdy timestamptz default now(),
  tabulka text not null, zaznam text, akce text not null, zmena jsonb
);

-- ----------------------------------------------------------------- práva
create or replace function moje_role() returns role_t language sql stable security definer as
  $$ select role from uzivatele where id = auth.uid() $$;
create or replace function moje_skola() returns uuid language sql stable security definer as
  $$ select skola_id from uzivatele where id = auth.uid() $$;
create or replace function je_vedeni() returns boolean language sql stable as
  $$ select moje_role() in ('reditelka', 'zastupce', 'zastupce') $$;
create or replace function moje_dite(d uuid) returns boolean language sql stable security definer as $$
  select case moje_role()
    when 'reditelka' then exists (select 1 from deti where id = d and skola_id = moje_skola())
    when 'zastupce' then exists (select 1 from deti where id = d and skola_id = moje_skola())
    when 'hospodarka' then exists (select 1 from deti where id = d and skola_id = moje_skola())
    when 'ucitelka' then exists (
      select 1 from deti x join ucitel_trida ut on ut.trida_id = x.trida_id
      where x.id = d and ut.ucitel_id = auth.uid()
      union
      select 1 from dochazka y join ucitel_trida ut on ut.trida_id = y.trida_dnes
      where y.dite_id = d and y.den = current_date and ut.ucitel_id = auth.uid())
    when 'rodic' then exists (select 1 from zastupci z where z.dite_id = d and z.uzivatel_id = auth.uid())
  end $$;

alter table deti enable row level security;
create policy deti_cist on deti for select using (moje_dite(id));
create policy deti_menit on deti for all using (je_vedeni() and skola_id = moje_skola());

alter table zastupci enable row level security;
create policy zast_cist on zastupci for select using (moje_dite(dite_id));
create policy zast_menit on zastupci for all using (je_vedeni() and moje_dite(dite_id));

alter table poverene_osoby enable row level security;
create policy pov_cist on poverene_osoby for select using (moje_dite(dite_id));
create policy pov_menit on poverene_osoby for all using (moje_role() in ('reditelka', 'zastupce', 'rodic') and moje_dite(dite_id));

alter table souhlasy enable row level security;
create policy sou_cist on souhlasy for select using (moje_dite(dite_id));
create policy sou_menit on souhlasy for all using (moje_role() in ('reditelka', 'zastupce', 'rodic') and moje_dite(dite_id));

alter table dochazka enable row level security;
create policy doch_cist on dochazka for select using (moje_dite(dite_id));
create policy doch_menit on dochazka for all using (moje_role() in ('reditelka', 'zastupce', 'ucitelka', 'rodic') and moje_dite(dite_id));

alter table urazy enable row level security;
create policy uraz_cist on urazy for select using (moje_role() not in ('hospodarka', 'kucharka') and moje_dite(dite_id));
create policy uraz_zapsat on urazy for insert with check (moje_role() in ('reditelka', 'zastupce', 'ucitelka') and moje_dite(dite_id));
create policy uraz_menit on urazy for update using (je_vedeni() and skola_id = moje_skola());

alter table tridni_kniha enable row level security;
create policy kniha on tridni_kniha for all using (
  je_vedeni() or exists (select 1 from ucitel_trida ut where ut.trida_id = tridni_kniha.trida_id and ut.ucitel_id = auth.uid()));

alter table predpisy enable row level security;
create policy plat_cist on predpisy for select using (moje_role() in ('reditelka', 'zastupce', 'hospodarka', 'rodic') and moje_dite(dite_id));
create policy plat_menit on predpisy for all using (moje_role() in ('reditelka', 'zastupce', 'hospodarka') and moje_dite(dite_id));
alter table predpis_polozky enable row level security;
create policy polozky_cist on predpis_polozky for select using (exists (select 1 from predpisy p where p.id = predpis_id and moje_dite(p.dite_id)));
alter table konta enable row level security;
create policy konta_cist on konta for select using (moje_role() in ('reditelka', 'zastupce', 'hospodarka', 'rodic') and moje_dite(dite_id));
create or replace function je_finance() returns boolean language sql stable as
  $$ select moje_role() in ('reditelka', 'zastupce', 'hospodarka') $$;
alter table financni_nastaveni enable row level security;
create policy fn_cist on financni_nastaveni for select using (skola_id = moje_skola());
create policy fn_menit on financni_nastaveni for all using (je_finance() and skola_id = moje_skola());
alter table sazby_stravneho enable row level security;
create policy ss_cist on sazby_stravneho for select using (skola_id = moje_skola());
create policy ss_menit on sazby_stravneho for all using (je_finance() and skola_id = moje_skola());
alter table ucetni_pohyby enable row level security;
create policy up_cist on ucetni_pohyby for select using (je_finance() and skola_id = moje_skola());
create policy up_vlozit on ucetni_pohyby for insert with check (je_finance() and skola_id = moje_skola());
alter table platby enable row level security;
create policy pl_fin on platby for all using (je_finance() and skola_id = moje_skola());
alter table nesparovane_platby enable row level security;
create policy np_fin on nesparovane_platby for all using (je_finance() and exists (select 1 from platby p where p.id = platba_id and p.skola_id = moje_skola()));
alter table upominky enable row level security;
create policy upo_cist on upominky for select using (moje_role() in ('reditelka', 'zastupce', 'hospodarka', 'rodic') and moje_dite(dite_id));
create policy upo_psat on upominky for insert with check (je_finance() and moje_dite(dite_id));

alter table zadosti enable row level security;
create policy zapis on zadosti for all using (je_vedeni() and skola_id = moje_skola());

alter table porady enable row level security;
create policy porady on porady for all using (moje_role() in ('reditelka', 'zastupce', 'ucitelka') and skola_id = moje_skola());

alter table zpravy enable row level security;
create policy zpravy_cist on zpravy for select using (skola_id = moje_skola());
create policy zpravy_psat on zpravy for insert with check (moje_role() in ('reditelka', 'zastupce', 'hospodarka') and skola_id = moje_skola());

alter table audit_log enable row level security;
create policy audit on audit_log for select using (je_vedeni() and skola_id = moje_skola());

-- Učitelky a hospodářka rodná čísla nevidí: čtou pohled bez nich.
create view deti_trida with (security_invoker = true) as
  select id, trida_id, jmeno, prijmeni, datum_narozeni, alergie, ukonceno from deti;

-- ----------------------------------------------------------------- audit
create or replace function zapis_audit() returns trigger language plpgsql security definer as $$
begin
  insert into audit_log (skola_id, kdo, tabulka, zaznam, akce, zmena)
  values (moje_skola(), auth.uid(), tg_table_name, to_jsonb(coalesce(new, old)) ->> 'id', tg_op,
          case when tg_op = 'UPDATE' then jsonb_build_object('pred', to_jsonb(old), 'po', to_jsonb(new)) else to_jsonb(coalesce(new, old)) end);
  return coalesce(new, old);
end $$;

create trigger a_deti after insert or update or delete on deti for each row execute function zapis_audit();
create trigger a_zastupci after insert or update or delete on zastupci for each row execute function zapis_audit();
create trigger a_pov after insert or update or delete on poverene_osoby for each row execute function zapis_audit();
create trigger a_souhlasy after insert or update or delete on souhlasy for each row execute function zapis_audit();
create trigger a_urazy after insert or update or delete on urazy for each row execute function zapis_audit();
create trigger a_predpisy after update on predpisy for each row execute function zapis_audit();

-- ----------------------------------------------------------------- jídelna: práva
alter table suroviny enable row level security;
alter table jidla enable row level security;
alter table jidlo_suroviny enable row level security;
alter table nahrady enable row level security;
alter table jidelnicek enable row level security;
alter table diety enable row level security;
create or replace function je_kuchyne() returns boolean language sql stable as
  $$ select moje_role() in ('kucharka', 'reditelka') $$;
create policy sur on suroviny for all using (je_kuchyne() and skola_id = moje_skola());
create policy jid_cist on jidla for select using (skola_id = moje_skola());
create policy jid_menit on jidla for all using (je_kuchyne() and skola_id = moje_skola());
create policy js on jidlo_suroviny for all using (je_kuchyne());
create policy nah_cist on nahrady for select using (true);
create policy nah_menit on nahrady for all using (je_kuchyne());
-- Učitelky a rodiče (LifeOS) vidí jen zveřejněný jídelníček.
create policy jdl_cist on jidelnicek for select using (skola_id = moje_skola() and (zverejneno or je_kuchyne()));
create policy jdl_menit on jidelnicek for all using (je_kuchyne() and skola_id = moje_skola());
create policy die on diety for all using (je_kuchyne());

-- Kuchyně z dětí vidí jen to, co k vaření potřebuje.
-- Pohled běží s právy vlastníka (kuchařka k tabulce deti přístup nemá),
-- proto filtruje školu a roli sám.
create view deti_jidelna as
  select d.id, d.trida_id, d.jmeno, left(d.prijmeni, 1) as prijmeni, d.alergie
  from deti d
  where d.ukonceno is null and d.skola_id = moje_skola() and moje_role() in ('kucharka', 'reditelka', 'zastupce');
create trigger a_platby after update on platby for each row execute function zapis_audit();
create trigger a_nesparovane after update on nesparovane_platby for each row execute function zapis_audit();
create trigger a_fin_nastaveni after insert or update on financni_nastaveni for each row execute function zapis_audit();

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

-- Náhled kódu: LifeOS ukáže, kterému dítěti kód patří, ještě před propojením.
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

-- =============================================================================
-- Školka — doplněk 13. 10. 2026 (c): SUPERADMIN a pozvánky
-- -----------------------------------------------------------------------------
--   • superadmin (provozovatel LifeOS) zakládá školky, zve ředitelky,
--     aktivuje/blokuje školky a vede předplatné; dětská data nevidí
--   • ředitelka zve zaměstnance (učitelky, kuchařky…) a blokuje jejich účty
--   • účet vzniká registrací s kódem pozvánky — bez tajného klíče v aplikaci
--   • blokovaná školka nebo účet = žádný přístup (vynucuje moje_role(), na
--     které stojí všechny zásady RLS)
-- Spusťte jednou v Supabase → SQL Editor. Pak na konci souboru přidejte
-- sebe jako superadmina (řádek „insert into superadmini …“).
-- =============================================================================

-- ------------------------------------------------------------- tabulky
create table if not exists superadmini (
  uzivatel_id uuid primary key references auth.users on delete cascade,
  jmeno text not null,
  vytvoreno timestamptz not null default now()
);
alter table superadmini enable row level security;   -- žádné zásady: čtou se jen přes funkce

alter table skoly add column if not exists stav text not null default 'aktivni';
do $$ begin
  alter table skoly add constraint skoly_stav check (stav in ('ceka', 'aktivni', 'blokovana'));
exception when duplicate_object then null; end $$;
alter table skoly add column if not exists tarif text not null default 'pilot';
alter table skoly add column if not exists predplatne_do date;
-- Poznámka správce je v samostatné tabulce: ředitelka čte celý řádek své
-- školky, poznámku provozovatele vidět nemá.
create table if not exists skoly_admin (
  skola_id uuid primary key references skoly on delete cascade,
  poznamka text
);
alter table skoly_admin enable row level security;   -- žádné zásady: jen přes funkce
do $$ begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'skoly' and column_name = 'poznamka_admin') then
    execute 'insert into skoly_admin (skola_id, poznamka) select id, poznamka_admin from skoly where poznamka_admin is not null on conflict do nothing';
    execute 'alter table skoly drop column poznamka_admin';
  end if;
end $$;
alter table skoly add column if not exists vytvoreno timestamptz not null default now();

alter table uzivatele add column if not exists aktivni boolean not null default true;
alter table uzivatele add column if not exists email text;
update uzivatele u set email = lower(a.email) from auth.users a where a.id = u.id and u.email is null and a.email is not null;

create table if not exists pozvanky (
  kod text primary key,                       -- 8 znaků bez 0/O/1/I (ABCD-EFGH)
  skola_id uuid not null references skoly on delete cascade,
  email text not null,
  jmeno text not null,
  role role_t not null check (role <> 'rodic'),
  trida_id uuid references tridy on delete set null,
  vytvoril uuid,
  vytvoreno timestamptz not null default now(),
  plati_do timestamptz not null default now() + interval '30 days',
  prijato timestamptz, prijal uuid,
  zruseno timestamptz
);
alter table pozvanky enable row level security;     -- čte se jen přes funkce

-- ------------------------------------------------------------- práva
create or replace function je_superadmin() returns boolean language sql stable security definer set search_path = public as
  $$ select exists (select 1 from superadmini where uzivatel_id = auth.uid()) $$;

-- Role platí, jen když je účet aktivní a školka aktivní. Na moje_role()
-- stojí všechny zásady RLS — blokace tak platí pro tablet, ředitelnu,
-- jídelnu i LifeOS najednou.
-- Pozor na NULL: účet bez role (nová registrace, blokovaný účet či školka)
-- má moje_role() = NULL. Kontroly typu „if not (moje_role() in (…) and
-- moje_dite(…))“ by s NULL neprošly jako zákaz — proto obě funkce vracejí
-- vždy true/false.
create or replace function je_vedeni() returns boolean language sql stable set search_path = public as
  $$ select coalesce(moje_role() in ('reditelka', 'zastupce'), false) $$;
create or replace function moje_dite(d uuid) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(case moje_role()
    when 'reditelka' then exists (select 1 from deti where id = d and skola_id = moje_skola())
    when 'zastupce' then exists (select 1 from deti where id = d and skola_id = moje_skola())
    when 'hospodarka' then exists (select 1 from deti where id = d and skola_id = moje_skola())
    when 'ucitelka' then exists (
      select 1 from deti x join ucitel_trida ut on ut.trida_id = x.trida_id
      where x.id = d and ut.ucitel_id = auth.uid()
      union
      select 1 from dochazka y join ucitel_trida ut on ut.trida_id = y.trida_dnes
      where y.dite_id = d and y.den = current_date and ut.ucitel_id = auth.uid())
    when 'rodic' then exists (select 1 from zastupci z where z.dite_id = d and z.uzivatel_id = auth.uid())
  end, false) $$;

create or replace function moje_role() returns role_t language sql stable security definer set search_path = public as
  $$ select u.role from uzivatele u join skoly s on s.id = u.skola_id
     where u.id = auth.uid() and u.aktivni and s.stav = 'aktivni' $$;
create or replace function moje_skola() returns uuid language sql stable security definer set search_path = public as
  $$ select u.skola_id from uzivatele u join skoly s on s.id = u.skola_id
     where u.id = auth.uid() and u.aktivni and s.stav = 'aktivni' $$;

-- Proč účet nemá přístup (pro srozumitelnou hlášku po přihlášení).
create or replace function muj_stav() returns table (role text, skola text, stav_skoly text, aktivni boolean, superadmin boolean)
language sql stable security definer set search_path = public as $$
  select u.role::text, s.nazev, s.stav, u.aktivni, je_superadmin()
  from (select auth.uid() id) me
  left join uzivatele u on u.id = me.id
  left join skoly s on s.id = u.skola_id
$$;

create or replace function novy_kod() returns text language plpgsql volatile as $$
declare abc constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; b bytea := uuid_send(gen_random_uuid()); k text := '';
begin
  for i in 0..7 loop k := k || substr(abc, get_byte(b, i) % 32 + 1, 1); end loop;
  return k;
end $$;

-- ------------------------------------------------- superadmin: školky
create or replace function admin_skoly()
returns table (id uuid, nazev text, izo text, kontakt text, stav text, tarif text, predplatne_do date, poznamka text, vytvoreno timestamptz,
               deti int, tridy int, zamestnanci int, rodice int, reditelky jsonb, pozvanky jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  if not je_superadmin() then raise exception 'Jen pro správce LifeOS.'; end if;
  return query
    select s.id, s.nazev, s.izo, s.kontakt, s.stav, s.tarif, s.predplatne_do, (select a.poznamka from skoly_admin a where a.skola_id = s.id), s.vytvoreno,
      (select count(*)::int from deti d where d.skola_id = s.id and d.ukonceno is null),
      (select count(*)::int from tridy t where t.skola_id = s.id),
      (select count(*)::int from uzivatele u where u.skola_id = s.id and u.role <> 'rodic'),
      (select count(*)::int from uzivatele u where u.skola_id = s.id and u.role = 'rodic'),
      coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'jmeno', u.jmeno, 'email', u.email, 'aktivni', u.aktivni) order by u.jmeno)
                from uzivatele u where u.skola_id = s.id and u.role = 'reditelka'), '[]'),
      coalesce((select jsonb_agg(jsonb_build_object('kod', p.kod, 'jmeno', p.jmeno, 'email', p.email, 'plati_do', p.plati_do) order by p.vytvoreno)
                from pozvanky p where p.skola_id = s.id and p.role = 'reditelka' and p.prijato is null and p.zruseno is null and p.plati_do > now()), '[]')
    from skoly s order by s.nazev;
end $$;

create or replace function admin_zaloz_skolu(p_nazev text, p_izo text default '', p_red_izo text default '', p_kontakt text default null, p_tarif text default 'pilot', p_predplatne_do date default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare id uuid;
begin
  if not je_superadmin() then raise exception 'Jen pro správce LifeOS.'; end if;
  if coalesce(trim(p_nazev), '') = '' then raise exception 'Chybí název školky.'; end if;
  insert into skoly (nazev, izo, red_izo, kontakt, stav, tarif, predplatne_do)
  values (trim(p_nazev), coalesce(p_izo, ''), coalesce(p_red_izo, ''), p_kontakt, 'ceka', coalesce(p_tarif, 'pilot'), p_predplatne_do)
  returning skoly.id into id;
  insert into financni_nastaveni (skola_id, ucet, skolkovne) values (id, '', 0) on conflict do nothing;
  return id;
end $$;

create or replace function admin_uprav_skolu(p_id uuid, p_nazev text default null, p_kontakt text default null, p_stav text default null, p_tarif text default null, p_predplatne_do date default null, p_poznamka text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not je_superadmin() then raise exception 'Jen pro správce LifeOS.'; end if;
  if p_stav is not null and p_stav not in ('ceka', 'aktivni', 'blokovana') then raise exception 'Neznámý stav školky.'; end if;
  update skoly set
    nazev = coalesce(nullif(trim(p_nazev), ''), nazev),
    kontakt = coalesce(p_kontakt, kontakt),
    stav = coalesce(p_stav, stav),
    tarif = coalesce(p_tarif, tarif),
    predplatne_do = case when p_predplatne_do is null then predplatne_do else p_predplatne_do end
  where id = p_id;
  if not found then raise exception 'Školka neexistuje.'; end if;
  if p_poznamka is not null then
    insert into skoly_admin (skola_id, poznamka) values (p_id, p_poznamka)
    on conflict (skola_id) do update set poznamka = excluded.poznamka;
  end if;
end $$;

create or replace function admin_pozvi_reditelku(p_skola uuid, p_jmeno text, p_email text) returns text
language plpgsql security definer set search_path = public as $$
declare k text := novy_kod();
begin
  if not je_superadmin() then raise exception 'Jen pro správce LifeOS.'; end if;
  if not exists (select 1 from skoly where id = p_skola) then raise exception 'Školka neexistuje.'; end if;
  if coalesce(trim(p_jmeno), '') = '' or p_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Vyplňte jméno a platný e-mail.'; end if;
  update pozvanky set zruseno = now() where skola_id = p_skola and lower(email) = lower(trim(p_email)) and prijato is null and zruseno is null;
  insert into pozvanky (kod, skola_id, email, jmeno, role, vytvoril) values (k, p_skola, lower(trim(p_email)), trim(p_jmeno), 'reditelka', auth.uid());
  return substr(k, 1, 4) || '-' || substr(k, 5, 4);
end $$;

create or replace function admin_nastav_ucet(p_uzivatel uuid, p_aktivni boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not je_superadmin() then raise exception 'Jen pro správce LifeOS.'; end if;
  update uzivatele set aktivni = p_aktivni where id = p_uzivatel and role <> 'rodic';
  if not found then raise exception 'Účet neexistuje.'; end if;
end $$;

create or replace function admin_zrus_pozvanku(p_kod text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (je_superadmin() or exists (select 1 from pozvanky p where p.kod = upper(regexp_replace(p_kod, '[^A-Za-z0-9]', '', 'g')) and p.skola_id = moje_skola() and moje_role() in ('reditelka', 'zastupce'))) then
    raise exception 'Pozvánku nemůžete zrušit.';
  end if;
  update pozvanky set zruseno = now() where kod = upper(regexp_replace(p_kod, '[^A-Za-z0-9]', '', 'g')) and prijato is null;
end $$;

-- ------------------------------------------- ředitelka: zaměstnanci školy
create or replace function zamestnanci_skoly()
returns table (id uuid, jmeno text, email text, role text, aktivni boolean, trida text, pozvanka text, plati_do timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not je_vedeni() then raise exception 'Přístupy spravuje vedení školy.'; end if;
  return query
    select u.id, u.jmeno, u.email, u.role::text, u.aktivni,
      (select string_agg(t.nazev, ', ') from ucitel_trida ut join tridy t on t.id = ut.trida_id where ut.ucitel_id = u.id), null::text, null::timestamptz
    from uzivatele u where u.skola_id = moje_skola() and u.role <> 'rodic'
    union all
    select null, p.jmeno, p.email, p.role::text, null, (select t.nazev from tridy t where t.id = p.trida_id),
      substr(p.kod, 1, 4) || '-' || substr(p.kod, 5, 4), p.plati_do
    from pozvanky p where p.skola_id = moje_skola() and p.prijato is null and p.zruseno is null and p.plati_do > now()
    order by 2;
end $$;

create or replace function pozvi_zamestnance(p_jmeno text, p_email text, p_role text, p_trida uuid default null) returns text
language plpgsql security definer set search_path = public as $$
declare k text := novy_kod();
begin
  if not je_vedeni() then raise exception 'Zaměstnance zve vedení školy.'; end if;
  if p_role not in ('zastupce', 'ucitelka', 'hospodarka', 'kucharka') then raise exception 'Tuto roli pozvat nejde.'; end if;
  if p_role = 'ucitelka' and p_trida is null then raise exception 'Vyberte třídu.'; end if;
  if p_trida is not null and not exists (select 1 from tridy where id = p_trida and skola_id = moje_skola()) then raise exception 'Třída do školky nepatří.'; end if;
  if coalesce(trim(p_jmeno), '') = '' or p_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Vyplňte jméno a platný e-mail.'; end if;
  if exists (select 1 from uzivatele where skola_id = moje_skola() and lower(email) = lower(trim(p_email))) then raise exception 'Tento e-mail už ve školce přístup má.'; end if;
  update pozvanky set zruseno = now() where skola_id = moje_skola() and lower(email) = lower(trim(p_email)) and prijato is null and zruseno is null;
  insert into pozvanky (kod, skola_id, email, jmeno, role, trida_id, vytvoril)
  values (k, moje_skola(), lower(trim(p_email)), trim(p_jmeno), p_role::role_t, p_trida, auth.uid());
  return substr(k, 1, 4) || '-' || substr(k, 5, 4);
end $$;

create or replace function nastav_ucet_zamestnance(p_uzivatel uuid, p_aktivni boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not je_vedeni() then raise exception 'Přístupy spravuje vedení školy.'; end if;
  if p_uzivatel = auth.uid() then raise exception 'Sama sebe zablokovat nemůžete.'; end if;
  update uzivatele set aktivni = p_aktivni where id = p_uzivatel and skola_id = moje_skola() and role not in ('rodic', 'reditelka');
  if not found then raise exception 'Účet ve školce není (ředitelku blokuje jen správce LifeOS).'; end if;
end $$;

-- ------------------------------------------------- přijetí pozvánky
-- Nový uživatel se zaregistruje (e-mail + heslo) a zadá kód. E-mail musí
-- sedět s pozvánkou — kód sám nestačí.
create or replace function prijmi_pozvanku(p_kod text) returns table (role text, skola text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  me uuid := auth.uid();
  mail text := lower(coalesce(auth.jwt() ->> 'email', (select email from auth.users where id = auth.uid())));
  p pozvanky;
begin
  if me is null then raise exception 'Nejste přihlášeni.'; end if;
  if exists (select 1 from uzivatele where id = me) then raise exception 'Tento účet už ve školce je.'; end if;
  select * into p from pozvanky
   where kod = upper(regexp_replace(coalesce(p_kod, ''), '[^A-Za-z0-9]', '', 'g')) and prijato is null and zruseno is null and plati_do > now()
   for update;
  if not found then raise exception 'Kód pozvánky neplatí — je překlepnutý, použitý nebo propadlý.'; end if;
  if lower(p.email) <> mail then raise exception 'Pozvánka patří jinému e-mailu — zaregistrujte se e-mailem, na který přišla.'; end if;
  insert into uzivatele (id, skola_id, jmeno, role, email) values (me, p.skola_id, p.jmeno, p.role, p.email);
  if p.trida_id is not null then insert into ucitel_trida values (me, p.trida_id) on conflict do nothing; end if;
  -- první ředitelka školky ji tím aktivuje
  if p.role = 'reditelka' then update skoly set stav = 'aktivni' where id = p.skola_id and stav = 'ceka'; end if;
  update pozvanky set prijato = now(), prijal = me where kod = p.kod;
  return query select p.role::text, (select nazev from skoly where id = p.skola_id);
end $$;

-- Ředitelka už nesmí měnit uzivatele přímo (aktivace jde jen přes funkce).
drop policy if exists uziv_menit on uzivatele;
create policy uziv_menit on uzivatele for update using (moje_role() = 'reditelka' and skola_id = moje_skola() and id <> auth.uid())
  with check (moje_role() = 'reditelka' and skola_id = moje_skola() and role <> 'reditelka');

-- Jídelna: stejná kontrola, odolná vůči NULL (účet bez role nesmí projít).
create or replace function zverejni_jidelnicek(p_dny jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare
  sk uuid := moje_skola();
  r jsonb; j uuid; s uuid; dr text; n int := 0;
begin
  if not coalesce(moje_role() in ('kucharka', 'reditelka'), false) then raise exception 'Jídelníček zveřejňuje jídelna.'; end if;
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
  if not coalesce(moje_role() in ('kucharka', 'reditelka'), false) then raise exception 'Náhrady nastavuje jídelna.'; end if;
  update skoly set nahrady_obedu = p where id = moje_skola();
  return p;
end $$;

-- Stav, tarif a předplatné mění jen správce LifeOS (nebo funkce v databázi,
-- např. přijetí pozvánky). Zásada skola_menit pustí vedení k ostatním polím.
create or replace function hlidej_skolu() returns trigger language plpgsql set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon') and not je_superadmin()
     and (new.stav, new.tarif, new.predplatne_do) is distinct from (old.stav, old.tarif, old.predplatne_do) then
    raise exception 'Stav školky a předplatné mění jen správce LifeOS.';
  end if;
  return new;
end $$;
drop trigger if exists b_hlidej_skolu on skoly;
create trigger b_hlidej_skolu before update on skoly for each row execute function hlidej_skolu();

drop trigger if exists a_pozvanky on pozvanky;
create trigger a_pozvanky after insert or update on pozvanky for each row execute function zapis_audit();

revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;

-- -----------------------------------------------------------------------------
-- SEBE jako superadmina (upravte e-mail na svůj účet v Authentication → Users):
-- insert into superadmini (uzivatel_id, jmeno) select id, 'Roman' from auth.users where email = 'vas@email.cz' on conflict do nothing;
-- -----------------------------------------------------------------------------

-- =============================================================================
-- Školka — bezpečnostní opravy z auditu 14. 10. 2026 (nálezy E1–E19, F1–F12,
-- C10–C11, D3–D9, A9, E14–E15). Spusťte jednou v Supabase → SQL Editor po
-- migraci 2026-10-13c. Jde spustit opakovaně.
--
-- POZOR do budoucna: tabulka deti a uzivatele mají práva po sloupcích. Řádek
-- „grant select, insert, update, delete on all tables … to authenticated“
-- v novějších migracích by je zase otevřel — po něm je nutné tento soubor
-- (část E5/E7) spustit znovu. Hlídá to testy/bezpecnost.sh.
-- =============================================================================

-- E1: pohledy nesmí jít zapisovat (deti_jidelna běží s právy vlastníka → obchází RLS)
revoke insert, update, delete, truncate on deti_jidelna, deti_trida from authenticated, anon;
alter view deti_jidelna set (security_barrier = true);

-- E2: pozvánka — e-mail musí být známý a neprázdný, anonymní účet pozvánku nepřijme
create or replace function prijmi_pozvanku(p_kod text) returns table (role text, skola text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  me uuid := auth.uid();
  mail text := lower(nullif(coalesce(nullif(auth.jwt() ->> 'email', ''), (select email from auth.users where id = auth.uid())), ''));
  p pozvanky;
begin
  if me is null then raise exception 'Nejste přihlášeni.'; end if;
  if mail is null or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'Pozvánku přijme jen účet s e-mailem.';
  end if;
  if exists (select 1 from uzivatele where id = me) then raise exception 'Tento účet už ve školce je.'; end if;
  select * into p from pozvanky
   where kod = upper(regexp_replace(coalesce(p_kod, ''), '[^A-Za-z0-9]', '', 'g')) and prijato is null and zruseno is null and plati_do > now()
   for update;
  if not found then raise exception 'Kód pozvánky neplatí — je překlepnutý, použitý nebo propadlý.'; end if;
  if lower(p.email) is distinct from mail then raise exception 'Pozvánka patří jinému e-mailu — zaregistrujte se e-mailem, na který přišla.'; end if;
  insert into uzivatele (id, skola_id, jmeno, role, email) values (me, p.skola_id, p.jmeno, p.role, p.email);
  if p.trida_id is not null then insert into ucitel_trida values (me, p.trida_id) on conflict do nothing; end if;
  if p.role = 'reditelka' then update skoly set stav = 'aktivni' where id = p.skola_id and stav = 'ceka'; end if;
  update pozvanky set prijato = now(), prijal = me where kod = p.kod;
  return query select p.role::text, (select nazev from skoly where id = p.skola_id);
end $$;

-- E3: jídelna — diety, vazby jídlo–surovina a náhrady jen ve vlastní školce
create or replace function skola_ditete(d uuid) returns uuid language sql stable security definer set search_path = public as
  $$ select skola_id from deti where id = d $$;
drop policy if exists die on diety;
create policy die on diety for all using (je_kuchyne() and skola_ditete(dite_id) = moje_skola())
  with check (je_kuchyne() and skola_ditete(dite_id) = moje_skola());
drop policy if exists js on jidlo_suroviny;
create policy js on jidlo_suroviny for all
  using (je_kuchyne() and exists (select 1 from jidla j where j.id = jidlo_id and j.skola_id = moje_skola()))
  with check (je_kuchyne() and exists (select 1 from jidla j where j.id = jidlo_id and j.skola_id = moje_skola())
              and exists (select 1 from suroviny s where s.id = surovina_id and s.skola_id = moje_skola()));
drop policy if exists nah_cist on nahrady;
create policy nah_cist on nahrady for select using (exists (select 1 from jidla j where j.id = jidlo_id and j.skola_id = moje_skola()));
drop policy if exists nah_menit on nahrady;
create policy nah_menit on nahrady for all using (je_kuchyne() and exists (select 1 from jidla j where j.id = jidlo_id and j.skola_id = moje_skola()));

-- E4: třídní kniha — vedení jen vlastní školky, učitelka jen své třídy
drop policy if exists kniha on tridni_kniha;
create policy kniha on tridni_kniha for all using (
  (je_vedeni() and exists (select 1 from tridy t where t.id = trida_id and t.skola_id = moje_skola()))
  or (moje_role() = 'ucitelka' and je_ucitelka_tridy(trida_id)));

-- E5: citlivé sloupce dětí — učitelka a hospodářka je přímo nečtou
-- (RLS je řádková; sloupce se omezí právy a vedení/rodič čtou citlivé údaje přes funkci)
revoke select on deti from authenticated;
grant select (id, skola_id, trida_id, jmeno, prijmeni, datum_narozeni, pohlavi, obcanstvi, znalost_cj, spadovy, zahajeni,
  po_stupen, ivp, asistent, plpp_do, alergie, variabilni_symbol, osvobozen_od_skolkovneho, ukonceno, vytvoreno, znacka) on deti to authenticated;
create or replace function deti_osobni(p_dite uuid default null)
returns table (id uuid, rodne_cislo text, kod_cizince text, obec text, adresa text, dorucovaci_adresa text, pojistovna text, ockovani boolean,
               spz text, spz_plati_do date, kod_zahajeni text, zpusob_ppv text, odklad boolean, iv_overeni text, duvod_ukonceni text)
language sql stable security definer set search_path = public as $$
  select d.id, d.rodne_cislo, d.kod_cizince, d.obec, d.adresa, d.dorucovaci_adresa, d.pojistovna, d.ockovani, d.spz, d.spz_plati_do,
         d.kod_zahajeni, d.zpusob_ppv, d.odklad, d.iv_overeni, d.duvod_ukonceni
  from deti d
  where (p_dite is null or d.id = p_dite)
    and ((je_vedeni() and d.skola_id = moje_skola()) or (moje_role() = 'rodic' and moje_dite(d.id)))
$$;

-- E6: účetní pohyb do konta dítěte (trigger s právy vlastníka + kontrola školky)
create or replace function pohyb_do_konta() returns trigger language plpgsql security definer set search_path = public as $$
declare d uuid;
begin
  foreach d in array array[case when new.md like 'dite:%' then substr(new.md, 6)::uuid end, case when new.dal like 'dite:%' then substr(new.dal, 6)::uuid end] loop
    if d is not null and not exists (select 1 from deti where id = d and skola_id = new.skola_id) then
      raise exception 'Dítě do této školky nepatří.';
    end if;
  end loop;
  if new.md like 'dite:%' then
    insert into konta (dite_id, saldo) values (substr(new.md, 6)::uuid, -new.castka)
      on conflict (dite_id) do update set saldo = konta.saldo - new.castka;
  end if;
  if new.dal like 'dite:%' then
    insert into konta (dite_id, saldo) values (substr(new.dal, 6)::uuid, new.castka)
      on conflict (dite_id) do update set saldo = konta.saldo + new.castka;
  end if;
  return new;
end $$;
alter table ucetni_pohyby drop constraint if exists ucetni_pohyby_ucty;
alter table ucetni_pohyby add constraint ucetni_pohyby_ucty check (
  md ~ '^(dite:[0-9a-f-]{36}|banka|pokladna|vynosy:[a-z_]+)$' and dal ~ '^(dite:[0-9a-f-]{36}|banka|pokladna|vynosy:[a-z_]+)$') not valid;

-- E7: ředitelka mění jen „měkké“ údaje zaměstnanců; role, id, e-mail a blokace jen přes funkce
drop policy if exists uziv_menit on uzivatele;
create policy uziv_menit on uzivatele for update
  using (moje_role() = 'reditelka' and skola_id = moje_skola() and id <> auth.uid() and role not in ('reditelka', 'rodic'))
  with check (moje_role() = 'reditelka' and skola_id = moje_skola() and role not in ('reditelka', 'rodic'));
revoke update on uzivatele from authenticated;
grant update (jmeno, uvazek, zdravotni_prukaz, skoleni_hygieny) on uzivatele to authenticated;

-- E8: vazby napříč školkami (třída, učitelka, přesun na den, úraz)
drop policy if exists ut_menit on ucitel_trida;
create policy ut_menit on ucitel_trida for all
  using (je_vedeni() and exists (select 1 from tridy t where t.id = trida_id and t.skola_id = moje_skola()))
  with check (je_vedeni() and exists (select 1 from tridy t where t.id = trida_id and t.skola_id = moje_skola())
              and exists (select 1 from uzivatele u where u.id = ucitel_id and u.skola_id = moje_skola() and u.role in ('ucitelka', 'zastupce', 'reditelka')));
drop policy if exists deti_menit on deti;
create policy deti_menit on deti for all using (je_vedeni() and skola_id = moje_skola())
  with check (je_vedeni() and skola_id = moje_skola() and (trida_id is null or exists (select 1 from tridy t where t.id = trida_id and t.skola_id = moje_skola())));
drop policy if exists doch_menit on dochazka;
create policy doch_menit on dochazka for all using (moje_role() in ('reditelka', 'zastupce', 'ucitelka') and moje_dite(dite_id))
  with check (moje_role() in ('reditelka', 'zastupce', 'ucitelka') and moje_dite(dite_id)
              and (trida_dnes is null or exists (select 1 from tridy t where t.id = trida_dnes and t.skola_id = moje_skola())));
drop policy if exists uraz_zapsat on urazy;
create policy uraz_zapsat on urazy for insert with check (moje_role() in ('reditelka', 'zastupce', 'ucitelka') and moje_dite(dite_id)
  and skola_id = moje_skola() and zapsal = auth.uid());

-- E9: rodič neomlouvá zpětně a nepřepisuje „neomluven“
create or replace function omluv_dite(p_dite uuid, p_od date, p_do date, p_duvod text default null)
returns table (den date, obed_odhlasen boolean)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  ted timestamp := now() at time zone 'Europe/Prague';
  dni int := 1; do_ time := '08:00';
  d date; rodic boolean := coalesce(moje_role() = 'rodic', false);
begin
  if not (moje_role() in ('rodic', 'reditelka', 'zastupce', 'ucitelka') and moje_dite(p_dite)) then
    raise exception 'Toto dítě omluvit nemůžete.';
  end if;
  if p_do < p_od or p_do > p_od + 31 then raise exception 'Omluvit jde nejvýš měsíc dopředu.'; end if;
  if rodic and p_od < ted::date then raise exception 'Zpětně omlouvá jen školka.'; end if;
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
        where dochazka.stav <> 'pritomen' and not (rodic and dochazka.stav = 'neomluven');
      den := d; obed_odhlasen := ted < (d - dni) + do_;
      return next;
    end if;
    d := d + 1;
  end loop;
end $$;

-- E10: číslo úrazu přiděluje databáze (učitelka nevidí úrazy jiných tříd)
create or replace function cislo_urazu() returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform pg_advisory_xact_lock(hashtext('urazy:' || new.skola_id || ':' || new.rok));
  new.cislo := coalesce((select max(cislo) from urazy where skola_id = new.skola_id and rok = new.rok), 0) + 1;
  return new;
end $$;
drop trigger if exists b_cislo_urazu on urazy;
create trigger b_cislo_urazu before insert on urazy for each row execute function cislo_urazu();

-- E17: SECURITY DEFINER / triggery s pevnou search_path
alter function zapis_audit() set search_path = public;
alter function pohyby_jen_pridavat() set search_path = public;
alter function je_kuchyne() set search_path = public;
alter function je_finance() set search_path = public;
alter function novy_kod() set search_path = public;

-- E19: audit změn účtů, přiřazení tříd a diet
drop trigger if exists a_uzivatele on uzivatele;
create trigger a_uzivatele after insert or update or delete on uzivatele for each row execute function zapis_audit();
drop trigger if exists a_ucitel_trida on ucitel_trida;
create trigger a_ucitel_trida after insert or update or delete on ucitel_trida for each row execute function zapis_audit();
drop trigger if exists a_diety on diety;
create trigger a_diety after insert or update or delete on diety for each row execute function zapis_audit();

-- E11/E12: smazání účtu / dítěte
alter table zastupci drop constraint if exists zastupci_uzivatel_id_fkey,
  add constraint zastupci_uzivatel_id_fkey foreign key (uzivatel_id) references uzivatele on delete set null;
alter table predpisy drop constraint if exists predpisy_dite_id_fkey, add constraint predpisy_dite_id_fkey foreign key (dite_id) references deti on delete restrict;
alter table konta drop constraint if exists konta_dite_id_fkey, add constraint konta_dite_id_fkey foreign key (dite_id) references deti on delete restrict;
revoke delete on deti from authenticated;   -- dítě se ukončuje (deti.ukonceno), nemaže

-- E18: obrana do hloubky proti výchozím grantům Supabase
revoke all on all tables in schema public from anon;
revoke truncate, references, trigger on all tables in schema public from authenticated;
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke all on functions from anon, public;

-- E14 + E15/F11: uplatnění kódu rodiče — jedna školka na účet, omezený počet pokusů.
-- Neplatný kód nevyhazuje výjimku (ta by smazala i záznam o pokusu), ale vrátí
-- prázdný výsledek; LifeOS pak ukáže „Kód neplatí.“ Po 10 chybných pokusech za
-- 15 minut je účet na 15 minut zablokovaný.
create table if not exists pokusy_kodu (
  uzivatel_id uuid not null,
  kdy timestamptz not null default now()
);
create index if not exists pokusy_kodu_kdo on pokusy_kodu (uzivatel_id, kdy);
alter table pokusy_kodu enable row level security;   -- žádné zásady: jen přes funkce

create or replace function hlidej_pokusy_kodu() returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Nejste přihlášeni.'; end if;
  delete from pokusy_kodu where kdy < now() - interval '1 day';
  if (select count(*) from pokusy_kodu where uzivatel_id = auth.uid() and kdy > now() - interval '15 minutes') >= 10 then
    raise exception 'Příliš mnoho chybných pokusů. Zkuste to za 15 minut, nebo požádejte ve školce o nový kód.';
  end if;
end $$;

create or replace function nahled_kodu(p_kod text)
returns table (jmeno text, prijmeni text, datum_narozeni date, skola text, trida text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform hlidej_pokusy_kodu();
  return query
    select d.jmeno, d.prijmeni, d.datum_narozeni, s.nazev, t.nazev
    from parovaci_kody k join deti d on d.id = k.dite_id join skoly s on s.id = k.skola_id left join tridy t on t.id = d.trida_id
    where k.kod = upper(regexp_replace(coalesce(p_kod, ''), '[^A-Za-z0-9]', '', 'g'))
      and k.pouzito is null and k.zruseno is null and k.plati_do > now() and s.stav = 'aktivni';
  if not found then insert into pokusy_kodu (uzivatel_id) values (auth.uid()); end if;
end $$;

create or replace function uplatni_kod(p_kod text, p_jmeno text default null)
returns table (dite_id uuid, jmeno text, prijmeni text, datum_narozeni date, skola text, trida text, telefon_skoly text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  me uuid := auth.uid();
  k parovaci_kody;
begin
  perform hlidej_pokusy_kodu();
  select pk.* into k from parovaci_kody pk join skoly s on s.id = pk.skola_id
   where pk.kod = upper(regexp_replace(coalesce(p_kod, ''), '[^A-Za-z0-9]', '', 'g'))
     and pk.pouzito is null and pk.zruseno is null and pk.plati_do > now() and s.stav = 'aktivni'
   for update of pk;
  if not found then
    insert into pokusy_kodu (uzivatel_id) values (me);
    return;
  end if;
  if exists (select 1 from uzivatele u where u.id = me and u.role <> 'rodic') then
    raise exception 'Tento účet patří zaměstnanci školy, rodičovský kód na něj nejde použít.';
  end if;
  if exists (select 1 from uzivatele u where u.id = me and u.skola_id <> k.skola_id) then
    raise exception 'Tento telefon je už propojený s jinou školkou. Dítě z další školky zatím propojit nejde.';
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

-- F11: kódy z plně náhodných bajtů (7. bajt UUID v4 nese verzi → jen 16 možností)
create or replace function nahodny_kod() returns text language plpgsql volatile set search_path = public as $$
declare abc constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; b bytea := uuid_send(gen_random_uuid()); k text := ''; i int;
begin
  foreach i in array array[0, 1, 2, 3, 4, 5, 10, 11] loop k := k || substr(abc, get_byte(b, i) % 32 + 1, 1); end loop;
  return k;
end $$;
create or replace function novy_kod() returns text language sql volatile set search_path = public as $$ select nahodny_kod() $$;
create or replace function vytvor_kod_rodice(p_dite uuid, p_zastupce uuid default null) returns text
language plpgsql security definer set search_path = public as $$
declare k text := nahodny_kod();
begin
  if not (je_vedeni() and exists (select 1 from deti where id = p_dite and skola_id = moje_skola())) then
    raise exception 'Kód pro rodiče vydává jen vedení školy.';
  end if;
  if p_zastupce is not null and not exists (select 1 from zastupci where id = p_zastupce and dite_id = p_dite) then
    raise exception 'Zástupce k tomuto dítěti nepatří.';
  end if;
  update parovaci_kody set zruseno = now()
   where dite_id = p_dite and zastupce_id is not distinct from p_zastupce and pouzito is null and zruseno is null;
  insert into parovaci_kody (kod, skola_id, dite_id, zastupce_id, vytvoril, plati_do)
  values (k, moje_skola(), p_dite, p_zastupce, auth.uid(), now() + interval '14 days');
  return substr(k, 1, 4) || '-' || substr(k, 5, 4);
end $$;

-- D9/F12: autor zápisu u dítěte je vždy přihlášený účet (nejde podvrhnout)
create or replace function autor_udalosti() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null then
    new.zapsal := auth.uid();
    new.zapsal_jmeno := coalesce((select jmeno from uzivatele where id = auth.uid()), new.zapsal_jmeno);
  end if;
  return new;
end $$;
drop trigger if exists b_autor_udalosti on udalosti_ditete;
create trigger b_autor_udalosti before insert on udalosti_ditete for each row execute function autor_udalosti();
drop policy if exists ud_psat on udalosti_ditete;
create policy ud_psat on udalosti_ditete for insert with check (moje_role() in ('reditelka', 'zastupce', 'ucitelka')
  and moje_dite(dite_id) and skola_id = moje_skola());

-- F8/A9: zprávy podle adresáta. komu = 'vse' | 'zamestnanci' | 'trida:<uuid>' | 'dite:<uuid>'
create or replace function smi_zpravu(p_komu text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(case
    when moje_role() is null then false
    when p_komu = 'vse' then true
    when moje_role() in ('reditelka', 'zastupce', 'hospodarka') then true
    when p_komu = 'zamestnanci' then moje_role() <> 'rodic'
    when p_komu like 'trida:%' then
      case moje_role()
        when 'ucitelka' then je_ucitelka_tridy(nullif(substr(p_komu, 7), '')::uuid)
        when 'rodic' then exists (select 1 from deti d join zastupci z on z.dite_id = d.id
                                  where z.uzivatel_id = auth.uid() and d.trida_id::text = substr(p_komu, 7))
        else false end
    when p_komu like 'dite:%' then
      case moje_role() when 'rodic' then exists (select 1 from zastupci z where z.uzivatel_id = auth.uid() and z.dite_id::text = substr(p_komu, 6))
                       when 'ucitelka' then moje_dite(nullif(substr(p_komu, 6), '')::uuid)
                       else false end
    else false end, false)
$$;
drop policy if exists zpravy_cist on zpravy;
create policy zpravy_cist on zpravy for select using (skola_id = moje_skola() and smi_zpravu(komu));

-- práva po migraci (bez otevření sloupců deti/uzivatele — viz hlavička)
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
revoke execute on function hlidej_pokusy_kodu(), nahodny_kod() from authenticated;

-- B1/B4: ředitelna v ostrém provozu — měsíční souhrn docházky (Supabase vrací
-- nejvýš 1000 řádků, celý rok docházky by se nevešel).
create or replace function dochazka_souhrn(p_od date, p_do date)
returns table (dite_id uuid, mesic text, pritomen int, omluven int, neomluven int)
language sql stable security definer set search_path = public as $$
  select x.dite_id, to_char(x.den, 'YYYY-MM'),
         count(*) filter (where x.stav = 'pritomen')::int,
         count(*) filter (where x.stav = 'omluven')::int,
         count(*) filter (where x.stav = 'neomluven')::int
  from dochazka x join deti d on d.id = x.dite_id
  where coalesce(moje_role() in ('reditelka', 'zastupce', 'hospodarka'), false)
    and d.skola_id = moje_skola() and x.den between p_od and p_do
  group by x.dite_id, to_char(x.den, 'YYYY-MM')
$$;
grant execute on function dochazka_souhrn(date, date) to authenticated;

-- =============================================================================
-- Jídelna v ostrém provozu (C1–C8, C13, C15, C16)
-- Alergeny a náhrady se ukládají přímo k chodu v jídelníčku (náhrada platí jen
-- pro ten den; vypnutí náhrad je jen skryje, nesmaže). Katalog jídel a surovin
-- kuchyně je pracovní pomůcka → jeden JSON na školku.
-- =============================================================================
alter table jidelnicek add column if not exists alergeny smallint[];
alter table jidelnicek add column if not exists nahrady jsonb;

create table if not exists jidelna_katalog (
  skola_id uuid primary key references skoly on delete cascade,
  data jsonb not null,
  zmeneno timestamptz not null default now(),
  zmenil uuid
);
alter table jidelna_katalog enable row level security;
drop policy if exists katalog on jidelna_katalog;
create policy katalog on jidelna_katalog for all using (coalesce(je_kuchyne(), false) and skola_id = moje_skola())
  with check (coalesce(je_kuchyne(), false) and skola_id = moje_skola());
grant select, insert, update on jidelna_katalog to authenticated;

drop function if exists zverejni_jidelnicek(jsonb);
create or replace function zverejni_jidelnicek(p_dny jsonb, p_od date default null, p_do date default null) returns int
language plpgsql security definer set search_path = public as $$
declare
  sk uuid := moje_skola();
  r jsonb; j uuid; dr text; n int := 0; vden date; a smallint[];
begin
  if not coalesce(moje_role() in ('kucharka', 'reditelka'), false) then raise exception 'Jídelníček zveřejňuje jídelna.'; end if;
  if p_dny is null or jsonb_typeof(p_dny) <> 'array' then raise exception 'Chybná data jídelníčku.'; end if;
  -- R1: mazání vyprázdněných chodů jen v jednom týdnu (pondělí až pátek)
  if not (p_od is null or (p_do is not null and extract(isodow from p_od) = 1 and p_do = p_od + 4)) then
    raise exception 'Zveřejňuje se vždy jeden týden (pondělí až pátek).';
  end if;
  for r in select * from jsonb_array_elements(p_dny) loop
    vden := (r->>'den')::date;
    if extract(isodow from vden) > 5 then raise exception 'Jídelníček je jen na pracovní dny (% je víkend).', vden; end if;
    if p_od is not null and (vden < p_od or vden > p_do) then raise exception 'Den % není v zveřejňovaném týdnu.', vden; end if;
    if coalesce(r->>'chod', '') not in ('prs', 'pol', 'obed', 'sv', 'nap') then raise exception 'Neznámý chod.'; end if;
    if coalesce(trim(r->>'nazev'), '') = '' then raise exception 'Chybí název jídla (%).', vden; end if;
    a := coalesce(array(select jsonb_array_elements_text(coalesce(r->'alergeny', '[]'::jsonb))::smallint order by 1), '{}');
    if exists (select 1 from unnest(a) x where x < 1 or x > 14) then raise exception 'Alergeny jsou čísla 1–14.'; end if;
    dr := case r->>'chod' when 'pol' then 'polevka' when 'obed' then 'obed' when 'nap' then 'napoj' else 'svacina' end;
    select id into j from jidla where skola_id = sk and nazev = trim(r->>'nazev') and druh = dr limit 1;
    if j is null then insert into jidla (skola_id, nazev, druh) values (sk, trim(r->>'nazev'), dr) returning id into j; end if;
    insert into jidelnicek (skola_id, den, chod, jidlo_id, zverejneno, alergeny, nahrady)
      values (sk, vden, r->>'chod', j, true, a, coalesce(r->'nahrady', '{}'::jsonb))
      on conflict (skola_id, den, chod) do update set jidlo_id = excluded.jidlo_id, zverejneno = true, alergeny = excluded.alergeny, nahrady = excluded.nahrady;
    n := n + 1;
  end loop;
  -- vyprázdněné chody v zveřejňovaném týdnu zmizí i rodičům
  if p_od is not null then
    delete from jidelnicek x where x.skola_id = sk and x.den between p_od and p_do
      and not exists (select 1 from jsonb_array_elements(p_dny) e where (e->>'den')::date = x.den and e->>'chod' = x.chod);
  end if;
  return n;
end $$;

create or replace function jidelnicek_tyden(p_od date, p_do date)
returns table (den date, chod text, nazev text, alergeny smallint[], nahrady jsonb)
language sql stable security definer set search_path = public as $$
  select j.den, j.chod, x.nazev,
         coalesce(j.alergeny, (select array_agg(distinct a order by a) from jidlo_suroviny js join suroviny s on s.id = js.surovina_id, unnest(s.alergeny) a where js.jidlo_id = x.id), '{}'),
         case when (select nahrady_obedu from skoly where id = moje_skola()) then
           coalesce(j.nahrady, (select jsonb_object_agg(n.alergen, n.text) from nahrady n where n.jidlo_id = x.id), '{}'::jsonb)
         else '{}'::jsonb end
  from jidelnicek j join jidla x on x.id = j.jidlo_id
  where j.skola_id = moje_skola() and j.zverejneno and j.den between p_od and p_do
  order by j.den, array_position(array['prs', 'pol', 'obed', 'sv', 'nap'], j.chod)
$$;

-- kuchyně: celý jídelníček (i se skrytými náhradami) pro desku jídelny
create or replace function jidelnicek_kuchyne(p_od date, p_do date)
returns table (den date, chod text, nazev text, alergeny smallint[], nahrady jsonb, zverejneno boolean)
language sql stable security definer set search_path = public as $$
  select j.den, j.chod, x.nazev,
         coalesce(j.alergeny, (select array_agg(distinct a order by a) from jidlo_suroviny js join suroviny s on s.id = js.surovina_id, unnest(s.alergeny) a where js.jidlo_id = x.id), '{}'),
         coalesce(j.nahrady, (select jsonb_object_agg(n.alergen, n.text) from nahrady n where n.jidlo_id = x.id), '{}'::jsonb), j.zverejneno
  from jidelnicek j join jidla x on x.id = j.jidlo_id
  where coalesce(je_kuchyne(), false) and j.skola_id = moje_skola() and j.den between p_od and p_do
$$;

-- počty jídel na den podle tříd (odhlášené obědy z omluvenek rodičů)
create or replace function obedy_den(p_den date)
returns table (trida_id uuid, trida text, barva text, deti int, odhlaseno int)
language sql stable security definer set search_path = public as $$
  select t.id, t.nazev, t.barva,
         count(d.id)::int,
         count(d.id) filter (where exists (select 1 from dochazka x where x.dite_id = d.id and x.den = p_den and x.strava_prihlasena = false))::int
  from tridy t left join deti d on d.trida_id = t.id and d.ukonceno is null and (d.zahajeni is null or d.zahajeni <= p_den)
  where coalesce(je_kuchyne(), false) and t.skola_id = moje_skola()
  group by t.id, t.nazev, t.barva order by t.nazev
$$;

-- děti s alergií pro kuchyni (jméno, první písmeno příjmení, třída, alergie, dieta)
create or replace function deti_diety()
returns table (dite_id uuid, jmeno text, trida_id uuid, alergie text, doporuceni_lekare boolean, poznamka text)
language sql stable security definer set search_path = public as $$
  select d.id, d.jmeno || ' ' || left(d.prijmeni, 1) || '.', d.trida_id, d.alergie, coalesce(x.doporuceni_lekare, false), x.poznamka
  from deti d left join diety x on x.dite_id = d.id
  where coalesce(je_kuchyne(), false) and d.skola_id = moje_skola() and d.ukonceno is null
    and (coalesce(trim(d.alergie), '') <> '' or x.dite_id is not null)
  order by d.jmeno
$$;
grant execute on function zverejni_jidelnicek(jsonb, date, date), jidelnicek_tyden(date, date), jidelnicek_kuchyne(date, date), obedy_den(date), deti_diety() to authenticated;

-- D14: „dnes“ podle Prahy (Supabase běží v UTC — mezi půlnocí a 2:00 by byl včerejšek)
create or replace function dnes_praha() returns date language sql stable set search_path = public as
  $$ select (now() at time zone 'Europe/Prague')::date $$;
alter table poverene_osoby alter column zmocneni_od set default (now() at time zone 'Europe/Prague')::date;
alter table predpisy alter column vystaveno set default (now() at time zone 'Europe/Prague')::date;
create or replace function moje_dite(d uuid) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(case moje_role()
    when 'reditelka' then exists (select 1 from deti where id = d and skola_id = moje_skola())
    when 'zastupce' then exists (select 1 from deti where id = d and skola_id = moje_skola())
    when 'hospodarka' then exists (select 1 from deti where id = d and skola_id = moje_skola())
    when 'ucitelka' then exists (
      select 1 from deti x join ucitel_trida ut on ut.trida_id = x.trida_id
      where x.id = d and ut.ucitel_id = auth.uid()
      union
      select 1 from dochazka y join ucitel_trida ut on ut.trida_id = y.trida_dnes
      where y.dite_id = d and y.den = dnes_praha() and ut.ucitel_id = auth.uid())
    when 'rodic' then exists (select 1 from zastupci z where z.dite_id = d and z.uzivatel_id = auth.uid())
  end, false) $$;
CREATE OR REPLACE FUNCTION public.uprav_udaje_rodicem(p_dite uuid, p_alergie text DEFAULT NULL::text, p_telefon text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_poverene text[] DEFAULT NULL::text[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not (moje_role() = 'rodic' and moje_dite(p_dite)) then raise exception 'Údaje tohoto dítěte měnit nemůžete.'; end if;
  if p_alergie is not null then update deti set alergie = nullif(trim(p_alergie), '') where id = p_dite; end if;
  if p_telefon is not null or p_email is not null then
    update zastupci set telefon = coalesce(nullif(trim(p_telefon), ''), telefon), email = coalesce(nullif(trim(p_email), ''), email)
     where dite_id = p_dite and uzivatel_id = auth.uid();
  end if;
  if p_poverene is not null then
    update poverene_osoby set zruseno = dnes_praha()
     where dite_id = p_dite and zruseno is null and not (jmeno = any(p_poverene));
    insert into poverene_osoby (dite_id, jmeno)
      select p_dite, x from unnest(p_poverene) x
      where trim(x) <> '' and not exists (select 1 from poverene_osoby o where o.dite_id = p_dite and o.jmeno = x and o.zruseno is null);
  end if;
end $function$;
grant execute on function dnes_praha() to authenticated;

-- A8: rodič odpojí dítě v telefonu (Odpojit / Odebrat kartu / Smazat vše) —
-- zruší se i propojení na serveru; bez dalších dětí zmizí i účet rodiče ve školce.
create or replace function odpoj_rodice(p_dite uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Nejste přihlášeni.'; end if;
  update zastupci set uzivatel_id = null where dite_id = p_dite and uzivatel_id = auth.uid();
  delete from zastupci where dite_id = p_dite and uzivatel_id is null and poradi = 9 and telefon is null and email is null;
  if not exists (select 1 from zastupci where uzivatel_id = auth.uid()) then
    delete from uzivatele where id = auth.uid() and role = 'rodic';
  end if;
end $$;
grant execute on function odpoj_rodice(uuid) to authenticated;

-- =============================================================================
-- Regresní audit (R1, R8, R9, R12): jídelníček se ukládá po jednotlivých chodech
-- (návrh i zveřejněný). Dvě otevřené desky si nepřepíší celý týden a nic se
-- nemaže hromadně podle rozsahu.
-- =============================================================================
create or replace function uloz_chody(p_chody jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare
  sk uuid := moje_skola();
  r jsonb; j uuid; dr text; n int := 0; vden date; a smallint[];
begin
  if not coalesce(moje_role() in ('kucharka', 'reditelka'), false) then raise exception 'Jídelníček upravuje jídelna.'; end if;
  if p_chody is null or jsonb_typeof(p_chody) <> 'array' then raise exception 'Chybná data jídelníčku.'; end if;
  for r in select * from jsonb_array_elements(p_chody) loop
    begin
      vden := (r->>'den')::date;
    exception when others then raise exception 'Neplatné datum v jídelníčku.';
    end;
    if vden is null then raise exception 'Chybí den.'; end if;
    if extract(isodow from vden) > 5 then raise exception 'Jídelníček je jen na pracovní dny (% je víkend).', to_char(vden, 'DD. MM. YYYY'); end if;
    if coalesce(r->>'chod', '') not in ('prs', 'pol', 'obed', 'sv', 'nap') then raise exception 'Neznámý chod.'; end if;
    if coalesce((r->>'smazat')::boolean, false) then
      delete from jidelnicek where skola_id = sk and den = vden and chod = r->>'chod';
      n := n + 1; continue;
    end if;
    if coalesce(trim(r->>'nazev'), '') = '' then raise exception 'Chybí název jídla (%).', to_char(vden, 'DD. MM.'); end if;
    begin
      a := coalesce(array(select jsonb_array_elements_text(coalesce(r->'alergeny', '[]'::jsonb))::smallint order by 1), '{}');
    exception when others then raise exception 'Alergeny jsou čísla 1–14.';
    end;
    if exists (select 1 from unnest(a) x where x < 1 or x > 14) then raise exception 'Alergeny jsou čísla 1–14.'; end if;
    if r ? 'nahrady' and jsonb_typeof(r->'nahrady') <> 'object' then raise exception 'Chybné náhrady.'; end if;
    dr := case r->>'chod' when 'pol' then 'polevka' when 'obed' then 'obed' when 'nap' then 'napoj' else 'svacina' end;
    select id into j from jidla where skola_id = sk and nazev = trim(r->>'nazev') and druh = dr limit 1;
    if j is null then insert into jidla (skola_id, nazev, druh) values (sk, trim(r->>'nazev'), dr) returning id into j; end if;
    insert into jidelnicek (skola_id, den, chod, jidlo_id, zverejneno, alergeny, nahrady)
      values (sk, vden, r->>'chod', j, coalesce((r->>'zverejnit')::boolean, false), a, coalesce(r->'nahrady', '{}'::jsonb))
      on conflict (skola_id, den, chod) do update set jidlo_id = excluded.jidlo_id, zverejneno = excluded.zverejneno,
        alergeny = excluded.alergeny, nahrady = excluded.nahrady;
    n := n + 1;
  end loop;
  return n;
end $$;

do $$ begin
  alter table jidelnicek add constraint jidelnicek_pracovni_den check (extract(isodow from den) <= 5) not valid;
exception when duplicate_object then null; end $$;

create or replace function nahled_kodu(p_kod text)
returns table (jmeno text, prijmeni text, datum_narozeni date, skola text, trida text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform hlidej_pokusy_kodu();
  -- R4: datum narození se v náhledu nevrací (jméno, školka a třída k potvrzení stačí)
  return query
    select d.jmeno, d.prijmeni, null::date, s.nazev, t.nazev
    from parovaci_kody k join deti d on d.id = k.dite_id join skoly s on s.id = k.skola_id left join tridy t on t.id = d.trida_id
    where k.kod = upper(regexp_replace(coalesce(p_kod, ''), '[^A-Za-z0-9]', '', 'g'))
      and k.pouzito is null and k.zruseno is null and k.plati_do > now() and s.stav = 'aktivni';
  if not found then insert into pokusy_kodu (uzivatel_id) values (auth.uid()); end if;
end $$;

-- R5: k dítěti jde připojit jen účet rodiče téže školky
drop policy if exists zast_menit on zastupci;
create policy zast_menit on zastupci for all using (je_vedeni() and exists (select 1 from deti d where d.id = dite_id and d.skola_id = moje_skola()))
  with check (je_vedeni() and exists (select 1 from deti d where d.id = dite_id and d.skola_id = moje_skola())
    and (uzivatel_id is null or exists (select 1 from uzivatele u where u.id = uzivatel_id and u.skola_id = moje_skola() and u.role = 'rodic')));

-- R6: akce a alba jen pro třídy vlastní školky, platby jen pro děti vlastní školky
do $$ declare p record; begin
  for p in select policyname, tablename from pg_policies where tablename in ('akce', 'alba', 'platby') and cmd in ('INSERT', 'ALL', 'UPDATE') loop
    execute format('drop policy %I on %I', p.policyname, p.tablename);
  end loop;
end $$;
create policy akce_psat on akce for all using (je_vedeni() and skola_id = moje_skola() or (moje_role() = 'ucitelka' and skola_id = moje_skola() and trida_id is not null and je_ucitelka_tridy(trida_id)))
  with check (skola_id = moje_skola() and (trida_id is null or exists (select 1 from tridy t where t.id = trida_id and t.skola_id = moje_skola()))
    and (je_vedeni() or (moje_role() = 'ucitelka' and trida_id is not null and je_ucitelka_tridy(trida_id))));
create policy alba_psat on alba for all using (skola_id = moje_skola() and (je_vedeni() or (moje_role() = 'ucitelka' and je_ucitelka_tridy(trida_id))))
  with check (skola_id = moje_skola() and exists (select 1 from tridy t where t.id = trida_id and t.skola_id = moje_skola())
    and (je_vedeni() or (moje_role() = 'ucitelka' and je_ucitelka_tridy(trida_id))));
create policy platby_psat on platby for all using (coalesce(je_finance(), false) and skola_id = moje_skola())
  with check (coalesce(je_finance(), false) and skola_id = moje_skola() and (dite_id is null or exists (select 1 from deti d where d.id = dite_id and d.skola_id = moje_skola())));

-- R10: odpojení smaže jen vlastní, právě odpojený záznam zástupce
create or replace function odpoj_rodice(p_dite uuid) returns void
language plpgsql security definer set search_path = public as $$
declare z uuid[];
begin
  if auth.uid() is null then raise exception 'Nejste přihlášeni.'; end if;
  with u as (update zastupci set uzivatel_id = null where dite_id = p_dite and uzivatel_id = auth.uid() returning id) select array_agg(id) into z from u;
  if z is null then return; end if;
  delete from zastupci where id = any(z) and poradi = 9 and telefon is null and email is null;
  if not exists (select 1 from zastupci where uzivatel_id = auth.uid()) then
    delete from uzivatele where id = auth.uid() and role = 'rodic';
  end if;
end $$;

-- D13: rodič nedostane „omluveno“ za den, kdy už dítě je ve školce
create or replace function omluv_dite(p_dite uuid, p_od date, p_do date, p_duvod text default null)
returns table (den date, obed_odhlasen boolean)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  ted timestamp := now() at time zone 'Europe/Prague';
  dni int := 1; do_ time := '08:00';
  d date; rodic boolean := coalesce(moje_role() = 'rodic', false); zapsano boolean;
begin
  if not (moje_role() in ('rodic', 'reditelka', 'zastupce', 'ucitelka') and moje_dite(p_dite)) then
    raise exception 'Toto dítě omluvit nemůžete.';
  end if;
  if p_do < p_od or p_do > p_od + 31 then raise exception 'Omluvit jde nejvýš měsíc dopředu.'; end if;
  if rodic and p_od < ted::date then raise exception 'Zpětně omlouvá jen školka.'; end if;
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
  if rodic and not found then raise exception 'V tyto dny už dítě ve školce je — omluvit nejde.'; end if;
end $$;

-- zprávy: adresát musí být platný (vse / zamestnanci / třída nebo dítě vlastní školky)
create or replace function hlidej_zpravu() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not (new.komu in ('vse', 'zamestnanci')
          or (new.komu like 'trida:%' and exists (select 1 from tridy t where t.id::text = substr(new.komu, 7) and t.skola_id = new.skola_id))
          or (new.komu like 'dite:%' and exists (select 1 from deti d where d.id::text = substr(new.komu, 6) and d.skola_id = new.skola_id))) then
    raise exception 'Neplatný adresát zprávy.';
  end if;
  return new;
end $$;
drop trigger if exists b_hlidej_zpravu on zpravy;
create trigger b_hlidej_zpravu before insert or update on zpravy for each row execute function hlidej_zpravu();

-- R7: práva i u funkcí přidaných v této migraci
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
revoke execute on function hlidej_pokusy_kodu(), nahodny_kod() from authenticated;

-- R2: podrobnosti záznamu o úrazu pro ČŠI (druh, část těla, zdroj, příčina, opatření)
alter table urazy add column if not exists zaznam jsonb;
