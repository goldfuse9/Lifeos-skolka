#!/bin/bash
# Pro test e2e/banka.js: napodobené Fio API (3010) + Edge Function banka-sync (8000)
# proti lokální náhradě Supabase. Proxy musí běžet s FUNCTIONS_PORT=8000 (stack.sh).
# Potřebuje deno. JEN lokální testy.
set -euo pipefail
cd "$(dirname "$0")"
DENO=${DENO_BIN:-deno}
SEC=tajny-testovaci-klic-pro-postgrest-0123456789
klic() { node -e "const c=require('crypto'),b=o=>Buffer.from(JSON.stringify(o)).toString('base64url');const h=b({alg:'HS256',typ:'JWT'}),p=b({role:process.argv[1],exp:Math.floor(Date.now()/1000)+86400});console.log(h+'.'+p+'.'+c.createHmac('sha256','$SEC').update(h+'.'+p).digest('base64url'))" "$1"; }
PGH=${PGHOST_TEST:-/home/claude/.pgtest}; PGP=${PGPORT_TEST:-5499}
psql -h "$PGH" -p "$PGP" -U postgres -d postgres -qc "do \$\$ begin if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role nologin bypassrls; end if; end \$\$; grant service_role to authenticator;" >/dev/null
pgrep -f "fio-mock.ts" >/dev/null || (setsid nohup "$DENO" run --allow-net fio-mock.ts > /tmp/skolka-fio-mock.log 2>&1 </dev/null &)
pgrep -f "banka-sync/index.ts" >/dev/null || (SUPABASE_URL=http://localhost:${PROXY_PORT:-3002} SUPABASE_SERVICE_ROLE_KEY=$(klic service_role) SUPABASE_ANON_KEY=$(klic anon) \
  CRON_SECRET=lokalni-cron FIO_API_URL=http://localhost:3010 setsid nohup "$DENO" run --allow-net --allow-env --import-map=banka-import-map.json \
  ../../supabase/functions/banka-sync/index.ts > /tmp/skolka-banka-sync.log 2>&1 </dev/null &)
for i in $(seq 30); do curl -s -m1 -X OPTIONS localhost:8000 -o /dev/null && curl -s -m1 localhost:3010 -o /dev/null && { echo "OK: Fio mock 3010, banka-sync 8000"; exit 0; }; sleep 1; done
echo "nenaběhlo, viz /tmp/skolka-banka-sync.log"; exit 1
