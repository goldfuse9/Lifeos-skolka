-- =============================================================================
-- Školka — doplněk 15. 10. 2026 (c): DOKUMENTY školy na serveru.
-- Spusťte v Supabase → SQL Editor po migraci 2026-10-15b-zapis. Jde spustit opakovaně.
--
-- dokumenty         rozpracovaný text povinného dokumentu (školní řád, SVP…);
--                   html = null znamená „podle šablony z údajů školky“
-- dokumenty_verze   archiv schválených verzí (co přesně bylo schváleno)
-- Čte a upravuje vedení (ředitelka, zástupkyně). Schválení jde jen funkcí
-- schval_dokument — ta zvýší verzi a uloží znění do archivu.
-- =============================================================================

create table if not exists dokumenty (
  skola_id uuid not null references skoly on delete cascade,
  klic text not null check (klic ~ '^[a-z0-9-]{1,40}$'),
  html text check (html is null or length(html) <= 500000),
  fmt jsonb,
  schvaleno date,
  verze int not null default 0,
  upraveno_po_schvaleni boolean not null default false,
  na_webu boolean not null default false,
  zmeneno timestamptz not null default now(),
  zmenil uuid references uzivatele,
  primary key (skola_id, klic)
);
create table if not exists dokumenty_verze (
  skola_id uuid not null references skoly on delete cascade,
  klic text not null,
  verze int not null,
  html text not null check (length(html) <= 500000),
  fmt jsonb,
  schvaleno date not null,
  schvalil uuid references uzivatele,
  ulozeno timestamptz not null default now(),
  primary key (skola_id, klic, verze)
);

alter table dokumenty enable row level security;
alter table dokumenty_verze enable row level security;
drop policy if exists dokumenty_cist on dokumenty;
create policy dokumenty_cist on dokumenty for select using (je_vedeni() and skola_id = moje_skola());
drop policy if exists dokumenty_vlozit on dokumenty;
create policy dokumenty_vlozit on dokumenty for insert with check (je_vedeni() and skola_id = moje_skola());
drop policy if exists dokumenty_menit on dokumenty;
create policy dokumenty_menit on dokumenty for update using (je_vedeni() and skola_id = moje_skola()) with check (je_vedeni() and skola_id = moje_skola());
drop policy if exists dokumenty_verze_cist on dokumenty_verze;
create policy dokumenty_verze_cist on dokumenty_verze for select using (je_vedeni() and skola_id = moje_skola());

-- klient smí měnit jen text, formát a příznak webu; schválení a verze jen funkcí
revoke all on dokumenty, dokumenty_verze from authenticated, anon;
grant select on dokumenty, dokumenty_verze to authenticated;
grant insert (skola_id, klic, html, fmt, na_webu) on dokumenty to authenticated;
grant update (html, fmt, na_webu) on dokumenty to authenticated;

create or replace function hlidej_dokument() returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.zmeneno := now();
  new.zmenil := coalesce(auth.uid(), new.zmenil);
  if tg_op = 'UPDATE' and current_setting('skolka.schvaluji', true) is distinct from 'ano'
     and old.schvaleno is not null and (new.html is distinct from old.html or new.fmt is distinct from old.fmt) then
    new.upraveno_po_schvaleni := true;
  end if;
  return new;
end $$;
drop trigger if exists b_hlidej_dokument on dokumenty;
create trigger b_hlidej_dokument before insert or update on dokumenty for each row execute function hlidej_dokument();

-- schválení: p_html/p_fmt = stav editoru, p_znenie = výsledné znění (i ze šablony) do archivu
create or replace function schval_dokument(p_klic text, p_html text, p_fmt jsonb, p_zneni text) returns int
language plpgsql security definer set search_path = public as $$
declare s uuid := moje_skola(); v int;
begin
  if not je_vedeni() then raise exception 'Dokumenty schvaluje vedení školy.'; end if;
  if coalesce(btrim(p_zneni), '') = '' then raise exception 'Dokument je prázdný.'; end if;
  if length(p_zneni) > 500000 or length(coalesce(p_html, '')) > 500000 then raise exception 'Dokument je moc dlouhý.'; end if;
  if p_klic !~ '^[a-z0-9-]{1,40}$' then raise exception 'Neplatný dokument.'; end if;
  perform set_config('skolka.schvaluji', 'ano', true);
  insert into dokumenty (skola_id, klic, html, fmt, schvaleno, verze, upraveno_po_schvaleni)
  values (s, p_klic, p_html, p_fmt, dnes_praha(), 1, false)
  on conflict (skola_id, klic) do update set html = excluded.html, fmt = excluded.fmt, schvaleno = dnes_praha(),
    verze = dokumenty.verze + 1, upraveno_po_schvaleni = false
  returning verze into v;
  perform set_config('skolka.schvaluji', '', true);
  insert into dokumenty_verze (skola_id, klic, verze, html, fmt, schvaleno, schvalil)
  values (s, p_klic, v, p_zneni, p_fmt, dnes_praha(), auth.uid());
  return v;
end $$;
revoke execute on function schval_dokument(text, text, jsonb, text) from anon, public;
grant execute on function schval_dokument(text, text, jsonb, text) to authenticated;
