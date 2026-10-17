-- =============================================================================
-- Školka — automatické stahování plateb z banky každých 15 minut.
-- Spusťte v Supabase → SQL Editor AŽ PO nasazení Edge Function banka-sync.
-- Doplňte dvě hodnoty (<…>) a spusťte. Opakované spuštění úlohu jen přepíše.
--
--   <PROJEKT>      … ref projektu z adresy https://<PROJEKT>.supabase.co
--   <CRON_SECRET>  … stejný řetězec jako: supabase secrets set CRON_SECRET=…
--
-- Proč 15 minut: Fio dovolí jeden dotaz na token za 30 s; rodiče platí hlavně
-- večer a o víkendu, rychleji to nepotřebujeme. Kratší interval jde, delší taky.
-- =============================================================================
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- tajný řetězec do trezoru (ne do textu úlohy)
select vault.create_secret('<CRON_SECRET>', 'banka_cron_secret')
 where not exists (select 1 from vault.secrets where name = 'banka_cron_secret');

select cron.schedule('banka-sync', '*/15 * * * *', $$
  select net.http_post(
    url     := 'https://<PROJEKT>.supabase.co/functions/v1/banka-sync',
    headers := jsonb_build_object('Content-Type', 'application/json',
                 'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'banka_cron_secret')),
    body    := '{}'::jsonb,
    timeout_milliseconds := 60000)
$$);

-- Kontrola: poslední běhy úlohy a odpovědi funkce
--   select * from cron.job_run_details where jobid = (select jobid from cron.job where jobname = 'banka-sync') order by start_time desc limit 5;
--   select status_code, content from net._http_response order by created desc limit 5;
-- Vypnutí: select cron.unschedule('banka-sync');
