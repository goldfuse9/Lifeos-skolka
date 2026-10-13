-- Školka — celé nastavení databáze pro Supabase (schema.sql + pilot.sql).
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
