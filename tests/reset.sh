#!/bin/bash
# Založí (nebo vrátí do výchozího stavu) lokální testovací databázi:
# stub Supabase → supabase/setup.sql → testovací účty → supabase/testovaci-data.sql
# Použití: DB=skolka_test tests/reset.sh
set -euo pipefail
cd "$(dirname "$0")/.."
DB=${DB:-skolka_test}
export PGHOST=${PGHOST:-/home/claude/.pgtest} PGPORT=${PGPORT:-5499}
HESLO=${TEST_HESLO:-Test-heslo-2026}
export PGOPTIONS="-c client_min_messages=warning"
P="psql -U postgres -v ON_ERROR_STOP=1 -q"
$P -d postgres -c "drop database if exists $DB with (force)" -c "create database $DB" >/dev/null
$P -d $DB -f tests/lokalni-supabase/stub.sql >/dev/null 2>&1
$P -d $DB -f supabase/setup.sql
$P -d $DB -c "grant usage on schema public to anon, authenticated" >/dev/null
for e in superadmin reditelka.a zastupce.a ucitelka.a ucitelka2.a hospodarka.a kucharka.a zablokovana.a rodic.a rodic2.a reditelka.b ucitelka.b rodic.b; do
  $P -d $DB -c "insert into auth.users (id, email, heslo) values (gen_random_uuid(), '$e@test.lifeos.cz', encode(sha256(convert_to('sul:$HESLO', 'UTF8')), 'hex'))" >/dev/null
done
$P -d $DB -f supabase/testovaci-data.sql
echo "Databáze $DB připravena: $($P -d $DB -tAc "select count(*) from deti") dětí, $($P -d $DB -tAc "select count(*) from uzivatele") účtů ve školkách."
