#!/bin/bash
# Celý testovací cyklus školky: čistá DB → lokální Supabase → bezpečnost DB → E2E.
# Výsledky: tests/vysledky/ (snímky, e2e.json). Návratový kód 0 = vše prošlo.
cd "$(dirname "$0")"
export DB=${DB:-skolka_test}
./reset.sh || exit 1
./stack.sh
echo; echo "######## Bezpečnost databáze"; ./db/bezpecnost.sh; DBK=$?
echo; echo "######## E2E v prohlížeči";    node e2e/spust.js; E2E=$?
echo; echo "######## Souhrn: databáze $([ $DBK = 0 ] && echo OK || echo SELHÁVÁ) · E2E $([ $E2E = 0 ] && echo OK || echo SELHÁVÁ)"
[ $DBK = 0 ] && [ $E2E = 0 ]
