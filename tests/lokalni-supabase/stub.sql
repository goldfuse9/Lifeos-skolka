-- Minimální náhrada částí Supabase, na kterých stojí supabase/setup.sql:
-- role anon/authenticated/authenticator, schéma auth (users, uid(), jwt()),
-- publikace supabase_realtime. Jen pro lokální testy — do Supabase nepatří.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticator') then create role authenticator login noinherit; end if;
end $$;
grant anon, authenticated to authenticator;
create schema auth;
create table auth.users (
  id uuid primary key, email text unique, is_anonymous boolean not null default false,
  heslo text,                       -- otisk hesla (jen lokální proxy)
  potvrzeno boolean default true    -- e-mail potvrzen (režim CONFIRM=1)
);
create function auth.uid() returns uuid language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid $$;
create function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb) $$;
grant usage on schema auth to anon, authenticated;
grant execute on function auth.uid(), auth.jwt() to anon, authenticated;
create publication supabase_realtime;
