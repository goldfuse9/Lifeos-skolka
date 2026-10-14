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
L=0
LIFEOS=${LIFEOS_DIR:-/home/claude/lifeos-a/mobile}
if [ -d "$LIFEOS/node_modules" ]; then
  echo "######## LifeOS ↔ server (Jest integrační test)"
  ./reset.sh "$DB" >/dev/null
  KOD=$(TEST_DB=$DB node -e "console.log(require('./e2e/spolecne').sqlJako('aaaaaaaa-0000-4000-8000-000000000001','reditelka@test.cz',\"select vytvor_kod_rodice('00000000-0000-4000-8000-000000000101');\"))")
  OUT=$(cd "$LIFEOS" && SKOLKA_TEST_URL=http://localhost:$PX SKOLKA_TEST_KOD=$KOD npx jest skolkaserver 2>&1); echo "$OUT" | grep -E "Tests:|✕"
  echo "$OUT" | grep -q "Tests:.*failed" && L=1
else
  echo "######## LifeOS přeskočen (nastavte LIFEOS_DIR na …/lifeos/mobile s node_modules)"
fi
./reset.sh "$DB" >/dev/null
echo; [[ $B == 0 && $E == 0 && $L == 0 ]] && echo "VŠE PROŠLO" || echo "NĚCO SELHALO (bezpečnost=$B, e2e=$E, lifeos=$L)"
[[ $B == 0 && $E == 0 && $L == 0 ]]
