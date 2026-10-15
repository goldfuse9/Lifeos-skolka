-- Minimální náhrada částí Supabase, které schéma školky potřebuje (role,
-- auth.users, auth.uid(), auth.jwt(), publikace realtime). JEN pro lokální testy.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticator') then create role authenticator login noinherit; end if;
end $$;
grant anon, authenticated to authenticator;
create schema auth;
create table auth.users (id uuid primary key, email text unique, is_anonymous boolean not null default false,
  heslo text,            -- otisk hesla (jen lokální proxy); NULL = přijme libovolné heslo
  potvrzeno boolean);    -- false = e-mail čeká na potvrzení (režim CONFIRM=1)
create function auth.uid() returns uuid language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid $$;
create function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb) $$;
grant usage on schema auth to anon, authenticated;
grant execute on function auth.uid(), auth.jwt() to anon, authenticated;
create publication supabase_realtime;
-- Úložiště souborů (Supabase Storage) — tabulky jako v Supabase; soubory drží
-- lokální proxy (sbproxy.js) a oprávnění ověřuje vložením/čtením řádku jako uživatel.
create schema storage;
create table storage.buckets (id text primary key, name text not null, public boolean default false, file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text references storage.buckets(id), name text not null, owner uuid,
  created_at timestamptz default now(), metadata jsonb, unique (bucket_id, name));
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as $$
  select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1] $$;
grant usage on schema storage to anon, authenticated;
grant select, insert, delete on storage.objects to authenticated;
grant select on storage.buckets to authenticated;
