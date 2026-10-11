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
  variabilni_symbol text unique,
  ukonceno date, duvod_ukonceni text,
  vytvoreno timestamptz default now()
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

create table predpisy (
  dite_id uuid references deti on delete cascade,
  mesic date not null,                 -- první den měsíce
  skolne int not null, stravne int not null, obedu int not null,
  zaplaceno numeric(10,2) default 0, upominka date,
  primary key (dite_id, mesic)
);

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
