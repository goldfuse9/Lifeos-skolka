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
./reset.sh "$DB" >/dev/null
echo; [[ $B == 0 && $E == 0 ]] && echo "VŠE PROŠLO" || echo "NĚCO SELHALO (bezpečnost=$B, e2e=$E)"
[[ $B == 0 && $E == 0 ]]
