#!/bin/bash
# Spustí lokální testovací „Supabase“: PostgreSQL 16 + PostgREST + mini-proxy (auth)
# + statický web školky. Každá instance má vlastní databázi a porty, takže
# více testovacích agentů může běžet současně bez střetů.
#   testy/lokalni/stack.sh [databáze] [port PostgREST] [port proxy] [port webu]
#   výchozí: skolka_lokal 3001 3002 8767
# Aplikace v testovacím režimu: http://localhost:<web>/index.html?test=<proxy>
# (config.js se v testech přesměruje na http://localhost:<proxy>, viz e2e/spolecne.js)
set -euo pipefail
cd "$(dirname "$0")"
DB=${1:-skolka_lokal}; PR=${2:-3001}; PX=${3:-3002}; WEB=${4:-8767}
PGH=${PGHOST_TEST:-/home/claude/.pgtest}; PGP=${PGPORT_TEST:-5499}
BIN=/usr/lib/postgresql/16/bin
STAV=${TMPDIR:-/tmp}/skolka-lokal-$DB; mkdir -p "$STAV"
# 1) PostgreSQL (jeden cluster pro všechny instance)
if [ ! -d "$PGH/data" ]; then
  mkdir -p "$PGH" && chown postgres "$PGH"
  su postgres -c "$BIN/initdb -D $PGH/data -A trust -U postgres" >/dev/null
fi
if ! su postgres -c "$BIN/pg_ctl -D $PGH/data status" >/dev/null 2>&1; then
  su postgres -c "$BIN/pg_ctl -D $PGH/data -o '-p $PGP -k $PGH' -l $PGH/log start" >/dev/null 2>&1 </dev/null; sleep 2
fi
# 2) databáze (jen když ještě není — jinak ji obnoví testy/reset.sh)
if ! psql -h "$PGH" -p "$PGP" -U postgres -tAc "select 1 from pg_database where datname='$DB'" postgres | grep -q 1; then
  ../reset.sh "$DB"
fi
# 3) PostgREST
PGRST=${PGRST_BIN:-/tmp/claude-0/postgrest}
if [ ! -x "$PGRST" ]; then
  mkdir -p "$(dirname "$PGRST")"
  curl -sSL https://github.com/PostgREST/postgrest/releases/download/v12.2.3/postgrest-v12.2.3-linux-static-x64.tar.xz | tar -xJ -C "$(dirname "$PGRST")"
fi
cat > "$STAV/pgrst.conf" <<CONF
db-uri = "postgres://authenticator@/$DB?host=$PGH&port=$PGP"
db-schemas = "public"
db-anon-role = "anon"
jwt-secret = "tajny-testovaci-klic-pro-postgrest-0123456789"
server-port = $PR
CONF
pgrep -f "postgrest $STAV/pgrst.conf" >/dev/null || (setsid nohup "$PGRST" "$STAV/pgrst.conf" > "$STAV/pgrst.log" 2>&1 </dev/null &)
# 4) proxy (/rest/v1 → PostgREST, /auth/v1 emulace)
pgrep -f "sbproxy.js $DB" >/dev/null || (TEST_DB=$DB PGRST_PORT=$PR PROXY_PORT=$PX FUNCTIONS_PORT=${FUNCTIONS_PORT:-8000} setsid nohup node sbproxy.js "$DB" > "$STAV/proxy.log" 2>&1 </dev/null &)
# 5) statický web
pgrep -f "http.server $WEB" >/dev/null || (cd ../.. && setsid nohup python3 -m http.server "$WEB" > "$STAV/web.log" 2>&1 </dev/null &)
sleep 2
curl -sf "http://localhost:$PX/rest/v1/" -o /dev/null && echo "OK: db=$DB postgrest=$PR proxy=$PX web=$WEB" || { echo "proxy neodpovídá, viz $STAV"; exit 1; }
