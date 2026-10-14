#!/bin/bash
# Obnoví lokální testovací databázi do výchozího stavu: schéma (supabase/setup.sql)
# + smyšlená data (testy/data.sql). Jen lokální PostgreSQL — nikdy produkce.
#   testy/reset.sh [databáze]        (výchozí skolka_lokal)
set -euo pipefail
cd "$(dirname "$0")"
DB=${1:-${TEST_DB:-skolka_lokal}}
PGH=${PGHOST_TEST:-/home/claude/.pgtest}; PGP=${PGPORT_TEST:-5499}
P="psql -h $PGH -p $PGP -U postgres -v ON_ERROR_STOP=1 -q"
[[ "$DB" =~ ^[a-z0-9_]+$ ]] || { echo "neplatný název databáze"; exit 1; }
$P -d postgres -c "select pg_terminate_backend(pid) from pg_stat_activity where datname = '$DB' and pid <> pg_backend_pid()" >/dev/null
$P -d postgres -c "drop database if exists $DB with (force)" -c "create database $DB" 2>&1 | grep -v NOTICE || true
$P -d "$DB" -f lokalni/supabase-stub.sql >/dev/null 2>&1
$P -d "$DB" -f ../supabase/setup.sql 2>&1 | grep -v "NOTICE\|^$" || true
$P -d "$DB" -f data.sql 2>&1 | grep -v "NOTICE\|^$" || true
echo "reset $DB: $($P -d "$DB" -tAc "select count(*) from skoly")|školky $($P -d "$DB" -tAc "select count(*) from deti")|děti $($P -d "$DB" -tAc "select count(*) from uzivatele")|účty"
