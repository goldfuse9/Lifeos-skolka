-- =============================================================================
-- Školka — doplněk 15. 10. 2026 (g): AKCE a TŘÍDNÍ SCHŮZKY s odpověďmi rodičů.
-- Spusťte v Supabase → SQL Editor po migraci 2026-10-15f-archiv. Jde spustit opakovaně.
--
-- akce             výlet, besídka… (druh 'akce') nebo třídní schůzka (druh 'schuzka');
--                  trida_id = null → celá školka (zakládá jen vedení)
-- akce_odpovedi    rodič za své dítě: přijdeme / nepřijdeme (jen funkcí odpovez_na_akci)
-- =============================================================================

alter table akce add column if not exists druh text not null default 'akce';
alter table akce add column if not exists s_sebou text[] not null default '{}';
alter table akce add column if not exists program text;
alter table akce add column if not exists vytvoril uuid references uzivatele default auth.uid();
alter table akce drop constraint if exists akce_hodnoty;
alter table akce add constraint akce_hodnoty check (
  druh in ('akce', 'schuzka')
  and length(btrim(nazev)) between 1 and 120
  and length(coalesce(misto, '')) <= 120 and length(coalesce(poznamka, '')) <= 2000 and length(coalesce(program, '')) <= 2000
  and coalesce(array_length(s_sebou, 1), 0) <= 20
) not valid;
create index if not exists akce_skola_den on akce (skola_id, den);

create table if not exists akce_odpovedi (
  akce_id uuid not null references akce on delete cascade,
  dite_id uuid not null references deti on delete cascade,
  odpoved text not null check (odpoved in ('ano', 'ne')),
  kdy timestamptz not null default now(),
  kdo uuid references uzivatele default auth.uid(),
  primary key (akce_id, dite_id)
);
alter table akce_odpovedi enable row level security;
drop policy if exists akce_odpovedi_cist on akce_odpovedi;
create policy akce_odpovedi_cist on akce_odpovedi for select using (
  exists (select 1 from akce a where a.id = akce_id and a.skola_id = moje_skola())
  and (moje_role() <> 'rodic' or exists (select 1 from zastupci z where z.dite_id = akce_odpovedi.dite_id and z.uzivatel_id = auth.uid()))
);
revoke insert, update, delete, truncate on akce_odpovedi from authenticated, anon;
grant select on akce_odpovedi to authenticated;

-- rodič odpoví za své dítě (do dne akce; změnit odpověď jde)
create or replace function odpovez_na_akci(p_akce uuid, p_dite uuid, p_odpoved text) returns text
language plpgsql security definer set search_path = public as $$
declare a akce; d deti;
begin
  if moje_role() is distinct from 'rodic' then raise exception 'Na pozvánku odpovídá rodič.'; end if;
  if p_odpoved not in ('ano', 'ne') then raise exception 'Neplatná odpověď.'; end if;
  if not exists (select 1 from zastupci z where z.dite_id = p_dite and z.uzivatel_id = auth.uid()) then raise exception 'Za toto dítě odpovídat nemůžete.'; end if;
  select * into d from deti where id = p_dite;
  select * into a from akce where id = p_akce and skola_id = d.skola_id and (trida_id is null or trida_id = d.trida_id);
  if not found then raise exception 'Akce neexistuje.'; end if;
  if a.jen_info then raise exception 'Na tuto akci se neodpovídá.'; end if;
  if a.den < dnes_praha() then raise exception 'Akce už proběhla.'; end if;
  insert into akce_odpovedi (akce_id, dite_id, odpoved) values (p_akce, p_dite, p_odpoved)
  on conflict (akce_id, dite_id) do update set odpoved = excluded.odpoved, kdy = now(), kdo = auth.uid();
  return p_odpoved;
end $$;
revoke execute on function odpovez_na_akci(uuid, uuid, text) from anon, public;
grant execute on function odpovez_na_akci(uuid, uuid, text) to authenticated;

drop trigger if exists a_akce on akce;
create trigger a_akce after insert or update or delete on akce for each row execute function zapis_audit();
