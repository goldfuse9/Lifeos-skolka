#!/bin/bash
# Celý testovací cyklus školky v lokálním testovacím režimu:
# stack → reset dat → bezpečnostní testy DB → E2E v prohlížeči.
#   testy/spust-vse.sh [databáze] [port PostgREST] [port proxy] [port webu]
set -u
cd "$(dirname "$0")"
DB=${1:-skolka_lokal}; PR=${2:-3001}; PX=${3:-3002}; WEB=${4:-8767}
./lokalni/stack.sh "$DB" "$PR" "$PX" "$WEB" || exit 1
[ -d node_modules/playwright ] || npm i --silent >/dev/null
./reset.sh "$DB" >/dev/null
echo "######## bezpečnost (databáze)"; ./bezpecnost.sh "$DB"; B=$?
echo "######## E2E (prohlížeč)"; TEST_DB=$DB PROXY_PORT=$PX WEB_PORT=$WEB node e2e/spust.js; E=$?
F=0
echo "######## Finance API (Python, pytest)"
PG="psql -h ${PGHOST_TEST:-/home/claude/.pgtest} -p ${PGPORT_TEST:-5499} -U postgres -q"
$PG -d postgres -c "drop database if exists ${DB}_fin with (force)" -c "create database ${DB}_fin" >/dev/null 2>&1
$PG -d "${DB}_fin" -f lokalni/supabase-stub.sql >/dev/null 2>&1; $PG -d "${DB}_fin" -f ../supabase/setup.sql >/dev/null 2>&1
(cd ../server && TEST_DATABASE_URL="postgresql://postgres@/${DB}_fin?host=${PGHOST_TEST:-/home/claude/.pgtest}&port=${PGPORT_TEST:-5499}" python3 -m pytest -q tests 2>&1 | tail -1) | tee /tmp/skolka-fin.out
grep -q "passed" /tmp/skolka-fin.out && ! grep -q "failed\|error" /tmp/skolka-fin.out || F=1
L=0
LIFEOS=${LIFEOS_DIR:-/home/claude/lifeos-sv2/mobile}
if [ -d "$LIFEOS/node_modules" ]; then
  echo "######## LifeOS ↔ server (Jest integrační test)"
  ./reset.sh "$DB" >/dev/null
  KOD=$(TEST_DB=$DB node -e "console.log(require('./e2e/spolecne').sqlJako('aaaaaaaa-0000-4000-8000-000000000001','reditelka@test.cz',\"select vytvor_kod_rodice('00000000-0000-4000-8000-000000000101');\"))")
  OUT=$(cd "$LIFEOS" && SKOLKA_TEST_URL=http://localhost:$PX SKOLKA_TEST_KOD=$KOD SKOLKA_TEST_PSQL="psql -h ${PGHOST_TEST:-/home/claude/.pgtest} -p ${PGPORT_TEST:-5499} -U postgres -d $DB -qAt" npx jest skolkaserver 2>&1); echo "$OUT" | grep -E "Tests:|✕"
  echo "$OUT" | grep -q "Tests:.*failed" && L=1
else
  echo "######## LifeOS přeskočen (nastavte LIFEOS_DIR na …/lifeos/mobile s node_modules)"
fi
./reset.sh "$DB" >/dev/null
echo; [[ $B == 0 && $E == 0 && $L == 0 && $F == 0 ]] && echo "VŠE PROŠLO" || echo "NĚCO SELHALO (bezpečnost=$B, e2e=$E, finance=$F, lifeos=$L)"
[[ $B == 0 && $E == 0 && $L == 0 && $F == 0 ]]
