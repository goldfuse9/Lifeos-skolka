-- =============================================================================
-- Školka — doplněk 14. 10. 2026 (b): ZPRÁVY jako komunikační kanál.
-- Spusťte v Supabase → SQL Editor po migraci 2026-10-14-audit. Jde spustit opakovaně.
--
-- Komu (zpravy.komu):
--   vse              celá školka (píše vedení)
--   zamestnanci      zaměstnanci (píše vedení)
--   trida:<id>       rodiče třídy (vedení, učitelka té třídy)
--   dite:<id>        soukromý kanál rodičů dítěte se školkou — vidí rodiče
--                    dítěte, učitelky jeho třídy a vedení; píšou všichni tři
--   vedeni:<uid>     soukromý kanál zaměstnance (učitelky) s vedením
-- Vlákno: odpověď má odpoved_na = první zpráva vlákna. Rodič, který odpovídá
-- na zprávu celé třídě, píše do kanálu svého dítěte — ostatní rodiče odpověď
-- nevidí. Učitelka odpovídá vedení do vedeni:<své uid>.
-- Přečtení a potvrzení: zpravy_precteni (zapisuje jen funkce precti_zpravy).
-- =============================================================================

alter table zpravy add column if not exists odpoved_na uuid references zpravy on delete cascade;
alter table zpravy add column if not exists od_jmeno text;
alter table zpravy add column if not exists od_role text;
create index if not exists zpravy_vlakno on zpravy (odpoved_na);
create index if not exists zpravy_skola_cas on zpravy (skola_id, odeslano desc);

-- kdo zprávu čte (vedení = ředitelka, zástupkyně, hospodářka — ti, kdo mají ředitelnu)
create or replace function smi_zpravu(p_komu text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(case
    when moje_role() is null then false
    when p_komu = 'vse' then true
    when moje_role() in ('reditelka', 'zastupce', 'hospodarka') then true
    when p_komu = 'zamestnanci' then moje_role() <> 'rodic'
    when p_komu like 'vedeni:%' then substr(p_komu, 8) = auth.uid()::text
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

-- kdo kam smí psát
create or replace function smi_psat_zpravu(p_komu text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(case
    when moje_role() is null then false
    when moje_role() in ('reditelka', 'zastupce', 'hospodarka') then true
    when p_komu = 'vedeni:' || auth.uid()::text then moje_role() <> 'rodic'
    when moje_role() = 'ucitelka' then
      (p_komu like 'trida:%' and je_ucitelka_tridy(nullif(substr(p_komu, 7), '')::uuid))
      or (p_komu like 'dite:%' and moje_dite(nullif(substr(p_komu, 6), '')::uuid))
    when moje_role() = 'rodic' then
      p_komu like 'dite:%' and exists (select 1 from zastupci z where z.uzivatel_id = auth.uid() and z.dite_id::text = substr(p_komu, 6))
    else false end, false)
$$;

drop policy if exists zpravy_cist on zpravy;
create policy zpravy_cist on zpravy for select using (skola_id = moje_skola() and smi_zpravu(komu));
drop policy if exists zpravy_psat on zpravy;
create policy zpravy_psat on zpravy for insert with check (skola_id = moje_skola() and smi_psat_zpravu(komu) and odeslal = auth.uid());
revoke update, delete on zpravy from authenticated;

-- adresát, odesílatel, vlákno — doplní a ohlídá databáze (klient je nastavit nemůže)
create or replace function hlidej_zpravu() returns trigger language plpgsql security definer set search_path = public as $$
declare
  ja uuid := auth.uid();
  koren zpravy;
begin
  if ja is not null then
    new.odeslal := ja;
    new.skola_id := coalesce(new.skola_id, moje_skola());
    new.odeslano := now();
    new.od_role := moje_role()::text;
    new.od_jmeno := case
      when moje_role() = 'rodic' then coalesce(
        (select z.jmeno from zastupci z where z.uzivatel_id = ja and new.komu = 'dite:' || z.dite_id::text limit 1),
        (select z.jmeno from zastupci z where z.uzivatel_id = ja limit 1), 'Rodič')
      else (select u.jmeno from uzivatele u where u.id = ja) end;
  end if;
  new.text := btrim(coalesce(new.text, ''));
  if new.text = '' then raise exception 'Zpráva je prázdná.'; end if;
  if length(new.text) > 4000 then raise exception 'Zpráva je moc dlouhá (nejvýš 4000 znaků).'; end if;
  if not (new.komu in ('vse', 'zamestnanci')
          or (new.komu like 'trida:%' and exists (select 1 from tridy t where t.id::text = substr(new.komu, 7) and t.skola_id = new.skola_id))
          or (new.komu like 'dite:%' and exists (select 1 from deti d where d.id::text = substr(new.komu, 6) and d.skola_id = new.skola_id))
          or (new.komu like 'vedeni:%' and exists (select 1 from uzivatele u where u.id::text = substr(new.komu, 8) and u.skola_id = new.skola_id and u.role <> 'rodic'))) then
    raise exception 'Neplatný adresát zprávy.';
  end if;
  if new.odpoved_na is not null then
    select * into koren from zpravy where id = new.odpoved_na and skola_id = new.skola_id;
    if not found or (ja is not null and not smi_zpravu(koren.komu)) then raise exception 'Zpráva, na kterou odpovídáte, neexistuje.'; end if;
    if koren.odpoved_na is not null then
      new.odpoved_na := koren.odpoved_na;
      select * into koren from zpravy where id = new.odpoved_na;
    end if;
    new.predmet := koren.predmet;
  end if;
  new.predmet := coalesce(nullif(btrim(coalesce(new.predmet, '')), ''), left(regexp_replace(new.text, '\s+', ' ', 'g'), 60));
  return new;
end $$;
drop trigger if exists b_hlidej_zpravu on zpravy;
create trigger b_hlidej_zpravu before insert or update on zpravy for each row execute function hlidej_zpravu();

-- přečtení a potvrzení
create table if not exists zpravy_precteni (
  zprava_id uuid not null references zpravy on delete cascade,
  uzivatel_id uuid not null references uzivatele on delete cascade,
  precteno timestamptz not null default now(),
  potvrzeno timestamptz,
  primary key (zprava_id, uzivatel_id)
);
alter table zpravy_precteni enable row level security;
drop policy if exists zp_cist on zpravy_precteni;
create policy zp_cist on zpravy_precteni for select using (uzivatel_id = auth.uid());
revoke insert, update, delete, truncate on zpravy_precteni from authenticated, anon;
grant select on zpravy_precteni to authenticated;

create or replace function precti_zpravy(p_ids uuid[], p_potvrdit boolean default false) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if moje_role() is null then raise exception 'Nejste přihlášeni.'; end if;
  insert into zpravy_precteni (zprava_id, uzivatel_id, potvrzeno)
  select z.id, auth.uid(), case when p_potvrdit then now() end
    from zpravy z
   where z.id = any(coalesce(p_ids, '{}')) and z.skola_id = moje_skola() and smi_zpravu(z.komu) and z.odeslal is distinct from auth.uid()
  on conflict (zprava_id, uzivatel_id) do update set potvrzeno = coalesce(zpravy_precteni.potvrzeno, excluded.potvrzeno);
  get diagnostics n = row_count;
  return n;
end $$;

-- kdo zprávu potvrdil (jen zaměstnanci; učitelka vidí jen rodiče svých dětí)
create or replace function potvrzeni_zprav(p_ids uuid[]) returns table (zprava_id uuid, jmeno text, dite text, precteno timestamptz, potvrzeno timestamptz)
language sql stable security definer set search_path = public as $$
  select p.zprava_id,
         coalesce(z.jmeno, u.jmeno),
         case when d.id is not null then d.jmeno || ' ' || d.prijmeni end,
         p.precteno, p.potvrzeno
    from zpravy_precteni p
    join zpravy m on m.id = p.zprava_id
    join uzivatele u on u.id = p.uzivatel_id
    left join zastupci z on z.uzivatel_id = u.id and u.role = 'rodic'
    left join deti d on d.id = z.dite_id
   where p.zprava_id = any(coalesce(p_ids, '{}'))
     and m.skola_id = moje_skola() and smi_zpravu(m.komu)
     and moje_role() in ('reditelka', 'zastupce', 'hospodarka', 'ucitelka')
     and (u.role <> 'rodic' or moje_role() <> 'ucitelka' or moje_dite(d.id))
$$;

revoke execute on function precti_zpravy(uuid[], boolean), potvrzeni_zprav(uuid[]) from anon, public;
grant execute on function precti_zpravy(uuid[], boolean), potvrzeni_zprav(uuid[]), smi_psat_zpravu(text) to authenticated;
do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'zpravy_precteni') then
    alter publication supabase_realtime add table zpravy_precteni;
  end if;
end $$;
