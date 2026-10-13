#!/bin/bash
# Spustí lokální testovací „Supabase“ + web školky.
#   PostgreSQL (cluster v $PGDATA), PostgREST na PGRST_PORT, proxy na PROXY_PORT,
#   statický web na WEB_PORT. Každý agent/testovací běh může mít vlastní DB a porty.
# Použití: DB=skolka_test PGRST_PORT=3101 PROXY_PORT=3102 WEB_PORT=8801 tests/stack.sh
# Zastavení: tests/stack.sh stop
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DB=${DB:-skolka_test}; PGRST_PORT=${PGRST_PORT:-3101}; PROXY_PORT=${PROXY_PORT:-3102}; WEB_PORT=${WEB_PORT:-8801}
export PGHOST=${PGHOST:-/home/claude/.pgtest} PGPORT=${PGPORT:-5499}
PGDATA=${PGDATA:-/home/claude/.pgtest/data}; PGBIN=${PGBIN:-/usr/lib/postgresql/16/bin}
POSTGREST=${POSTGREST:-/tmp/claude-0/postgrest}
RUN=${RUN_DIR:-/tmp/skolka-test-$DB}; mkdir -p "$RUN"
if [ "${1:-}" = stop ]; then for f in "$RUN"/*.pid; do [ -f "$f" ] && kill "$(cat "$f")" 2>/dev/null; rm -f "$f"; done; echo zastaveno; exit 0; fi
pg_isready -q || su postgres -c "$PGBIN/pg_ctl -D $PGDATA -o '-p $PGPORT -k $PGHOST' -l $PGHOST/log start" >/dev/null
for i in 1 2 3 4 5; do pg_isready -q && break; sleep 1; done
SECRET=$(node -e "console.log(require('$ROOT/tests/lokalni-supabase/jwt.js').SECRET)")
cat > "$RUN/pgrst.conf" <<CONF
db-uri = "postgres://authenticator@/$DB?host=$PGHOST&port=$PGPORT"
db-schemas = "public"
db-anon-role = "anon"
jwt-secret = "$SECRET"
server-port = $PGRST_PORT
CONF
alive() { [ -f "$RUN/$1.pid" ] && kill -0 "$(cat "$RUN/$1.pid")" 2>/dev/null; }
alive postgrest || { nohup "$POSTGREST" "$RUN/pgrst.conf" > "$RUN/postgrest.log" 2>&1 & echo $! > "$RUN/postgrest.pid"; }
alive proxy || { DB=$DB PGRST_PORT=$PGRST_PORT PROXY_PORT=$PROXY_PORT nohup node "$ROOT/tests/lokalni-supabase/proxy.js" > "$RUN/proxy.log" 2>&1 & echo $! > "$RUN/proxy.pid"; }
alive web || { (cd "$ROOT" && nohup python3 -m http.server "$WEB_PORT" --bind 127.0.0.1 > "$RUN/web.log" 2>&1 & echo $! > "$RUN/web.pid"); }
sleep 2
echo "web http://localhost:$WEB_PORT/index.html · supabase http://localhost:$PROXY_PORT (DB $DB)"
