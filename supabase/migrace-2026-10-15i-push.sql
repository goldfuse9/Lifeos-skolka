-- =============================================================================
-- Školka — doplněk 15. 10. 2026 (i): PUSH OZNÁMENÍ do LifeOS (i při zavřené aplikaci).
-- Spusťte v Supabase → SQL Editor po migraci 2026-10-15h-fotky. Jde spustit opakovaně.
--
-- push_tokeny   telefon rodiče (Expo push token) — zapisuje jen funkce uloz_push_token
-- push_fronta   co se má rodičům oznámit; plní ji databáze sama při nové zprávě,
--               akci/schůzce, zveřejněných fotkách a zápisu učitelky
-- Odeslání:     přes rozšíření pg_net na Expo Push API (bez vlastního serveru
--               a bez tajných klíčů). Bez pg_net se fronta jen plní a nic neodchází.
-- Na zamčené obrazovce je jen obecný text — žádné zdravotní podrobnosti.
-- =============================================================================

create table if not exists push_tokeny (
  token text primary key check (token ~ '^(Expo|Exponent)PushToken\[[A-Za-z0-9_-]{10,100}\]$'),
  uzivatel_id uuid not null references uzivatele on delete cascade,
  platforma text check (platforma in ('ios', 'android')),
  aktualizovano timestamptz not null default now()
);
create index if not exists push_tokeny_uzivatel on push_tokeny (uzivatel_id);
alter table push_tokeny enable row level security;
drop policy if exists push_tokeny_vlastni on push_tokeny;
create policy push_tokeny_vlastni on push_tokeny for select using (uzivatel_id = auth.uid());
revoke insert, update, delete, truncate on push_tokeny from authenticated, anon;
grant select on push_tokeny to authenticated;

create table if not exists push_fronta (
  id bigserial primary key,
  token text not null,
  dite_id uuid,
  titulek text not null,
  text text not null,
  obrazovka text not null,
  zaznam text,
  vytvoreno timestamptz not null default now(),
  odeslano timestamptz,
  vysledek text
);
alter table push_fronta enable row level security;    -- nikdo z aplikace ji nečte ani nemění
revoke all on push_fronta from authenticated, anon;

-- telefon rodiče se přihlásí k oznámením (token patří vždy jen jednomu účtu)
create or replace function uloz_push_token(p_token text, p_platforma text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or moje_role() is distinct from 'rodic' then raise exception 'Oznámení si zapíná rodič v aplikaci LifeOS.'; end if;
  insert into push_tokeny (token, uzivatel_id, platforma) values (p_token, auth.uid(), p_platforma)
  on conflict (token) do update set uzivatel_id = excluded.uzivatel_id, platforma = excluded.platforma, aktualizovano = now();
end $$;
create or replace function smaz_push_token(p_token text) returns void
language sql security definer set search_path = public as $$
  delete from push_tokeny where token = p_token and uzivatel_id = auth.uid()
$$;
revoke execute on function uloz_push_token(text, text), smaz_push_token(text) from anon, public;
grant execute on function uloz_push_token(text, text), smaz_push_token(text) to authenticated;

-- do fronty: jedno oznámení na telefon rodiče (u více dětí ve stejné třídě jedno)
create or replace function push_rodicum(p_deti uuid[], p_text text, p_obrazovka text, p_zaznam text, p_bez uuid default null)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into push_fronta (token, dite_id, titulek, text, obrazovka, zaznam)
  select distinct on (t.token) t.token, d.id, coalesce(nullif(s.kratky_nazev, ''), s.nazev) || ' · ' || d.jmeno, p_text, p_obrazovka, p_zaznam
    from deti d
    join skoly s on s.id = d.skola_id
    join zastupci z on z.dite_id = d.id and z.uzivatel_id is not null
    join push_tokeny t on t.uzivatel_id = z.uzivatel_id
   where d.id = any(p_deti) and d.ukonceno is null and (p_bez is null or z.uzivatel_id <> p_bez)
   order by t.token, d.prijmeni, d.jmeno;
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function push_rodicum(uuid[], text, text, text, uuid) from anon, public, authenticated;

create or replace function push_po_zprave() returns trigger language plpgsql security definer set search_path = public as $$
declare deti uuid[];
begin
  if new.od_role = 'rodic' then return new; end if;   -- rodič píše školce — rodičům se nic neoznamuje
  deti := case
    when new.komu = 'vse' then array(select id from deti where skola_id = new.skola_id)
    when new.komu like 'trida:%' then array(select id from deti where skola_id = new.skola_id and trida_id::text = substr(new.komu, 7))
    when new.komu like 'dite:%' then array(select id from deti where skola_id = new.skola_id and id::text = substr(new.komu, 6))
    else '{}'::uuid[] end;
  perform push_rodicum(deti, case when new.odpoved_na is null then 'Nová zpráva: ' || left(new.predmet, 60) else 'Odpověď ve zprávách: ' || left(new.predmet, 60) end,
    'skolka-vlakno', coalesce(new.odpoved_na, new.id)::text, new.odeslal);
  return new;
end $$;
drop trigger if exists push_zpravy on zpravy;
create trigger push_zpravy after insert on zpravy for each row execute function push_po_zprave();

create or replace function push_po_akci() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.jen_info then return new; end if;
  perform push_rodicum(array(select id from deti where skola_id = new.skola_id and (new.trida_id is null or trida_id = new.trida_id)),
    case when new.druh = 'schuzka' then 'Třídní schůzka ' else 'Nová akce: ' || left(new.nazev, 50) || ' · ' end || to_char(new.den, 'FMDD. FMMM.') || ' — odpovězte, jestli přijdete',
    'skolka-akce', new.id::text);
  return new;
end $$;
drop trigger if exists push_akce on akce;
create trigger push_akce after insert on akce for each row execute function push_po_akci();

create or replace function push_po_albu() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.zverejneno is null or (tg_op = 'UPDATE' and old.zverejneno is not null) then return new; end if;
  perform push_rodicum(array(select id from deti where trida_id = new.trida_id), 'Nové fotky: ' || left(new.nazev, 60), 'skolka-fotky', new.id::text);
  return new;
end $$;
drop trigger if exists push_alba on alba;
create trigger push_alba after insert or update of zverejneno on alba for each row execute function push_po_albu();

create or replace function push_po_zapisu() returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform push_rodicum(array[new.dite_id], 'Nový zápis ze školky — klepněte pro podrobnosti.', 'skolka-zapis', new.id::text);
  return new;
end $$;
drop trigger if exists push_udalosti on udalosti_ditete;
create trigger push_udalosti after insert on udalosti_ditete for each row execute function push_po_zapisu();

-- odeslání na Expo Push API, když je k dispozici pg_net (Supabase: Database → Extensions → pg_net)
do $$ begin
  begin
    create extension if not exists pg_net;
  exception when others then
    raise notice 'pg_net není k dispozici — oznámení se jen řadí do fronty (push_fronta).';
  end;
end $$;

create or replace function push_odeslat() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null then return new; end if;
  execute 'select net.http_post(url := $1, body := $2, headers := $3)'
    using 'https://exp.host/--/api/v2/push/send',
          jsonb_build_object('to', new.token, 'title', new.titulek, 'body', new.text, 'sound', 'default',
            'data', jsonb_build_object('screen', new.obrazovka, 'recordId', new.zaznam, 'diteId', new.dite_id)),
          jsonb_build_object('Content-Type', 'application/json', 'Accept', 'application/json');
  update push_fronta set odeslano = now() where id = new.id;
  return new;
exception when others then
  update push_fronta set vysledek = left(sqlerrm, 200) where id = new.id;
  return new;
end $$;
drop trigger if exists push_odeslat on push_fronta;
create trigger push_odeslat after insert on push_fronta for each row execute function push_odeslat();

-- aplikace se zeptá, jestli server push opravdu posílá (jinak dál místní oznámení)
create or replace function push_aktivni() returns boolean language sql stable security definer set search_path = public as $$
  select to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is not null
$$;
revoke execute on function push_aktivni() from anon, public;
grant execute on function push_aktivni() to authenticated;
