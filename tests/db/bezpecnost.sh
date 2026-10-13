#!/bin/bash
# Bezpečnostní testy databáze (RLS + funkce) s různými identitami nad testovacími
# daty (supabase/testovaci-data.sql). Ověřuje skutečné výsledky dotazů, ne existenci zásad.
# Použití: DB=skolka_test tests/db/bezpecnost.sh   (nejdřív tests/reset.sh)
export PGHOST=${PGHOST:-/home/claude/.pgtest} PGPORT=${PGPORT:-5499} PGOPTIONS="-c client_min_messages=warning"
DB=${DB:-skolka_test}
P="psql -U postgres -d $DB -tAq"
id() { $P -c "select id from auth.users where email = '$1@test.lifeos.cz'"; }
PASS=0; FAIL=0
t() { # t "název" očekávání(ERR|hodnota) účet "SQL"
  local name="$1" exp="$2" who="$3" sql="$4" uid email out r
  if [ "$who" = anon ]; then out=$(printf "set role anon;\n%s\n" "$sql" | $P 2>&1 | grep -v '^CONTEXT\|^$' | tail -1)
  elif [ "$who" = nikdo ]; then uid=$NOROLE; email=""
  else uid=$(id "$who"); email="$who@test.lifeos.cz"; fi
  if [ "$who" != anon ]; then
    out=$(printf "set role authenticated;\nselect set_config('request.jwt.claim.sub','%s',false), set_config('request.jwt.claims','{\"sub\":\"%s\",\"email\":\"%s\"}',false) \\\\g /dev/null\n%s\n" "$uid" "$uid" "$email" "$sql" | $P 2>&1 | grep -v '^CONTEXT\|^$' | tail -1)
  fi
  if [ "$exp" = ERR ]; then [[ "$out" == *ERROR* ]] && r=PASS || r=FAIL; else [ "$out" = "$exp" ] && r=PASS || r=FAIL; fi
  [ $r = PASS ] && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
  echo "$r  $name  →  $out"
}
NOROLE=$($P -c "insert into auth.users(id, is_anonymous) values (gen_random_uuid(), true) returning id" | head -1)
EMA=eeeeeeee-0000-4000-8000-000000000101; OLI=eeeeeeee-0000-4000-8000-000000000102; ANN=eeeeeeee-0000-4000-8000-000000000105; ADA=eeeeeeee-0000-4000-8000-000000000201
SA=eeeeeeee-0000-4000-8000-00000000000a; SB=eeeeeeee-0000-4000-8000-00000000000b; A1=eeeeeeee-0000-4000-8000-0000000000a1; B1=eeeeeeee-0000-4000-8000-0000000000b1

echo "== oddělení školek"
t "ředitelka A vidí jen svou školku"            1   reditelka.a "select count(*) from skoly;"
t "ředitelka A vidí 6 dětí (jen A)"             6   reditelka.a "select count(*) from deti;"
t "ředitelka A nevidí dítě z B podle ID"        0   reditelka.a "select count(*) from deti where id='$ADA';"
t "ředitelka B nevidí alergie dětí A"           0   reditelka.b "select count(*) from deti where skola_id='$SA';"
t "ředitelka A nezmění dítě z B"                0   reditelka.a "with u as (update deti set alergie='x' where id='$ADA' returning 1) select count(*) from u;"
t "ředitelka A nevloží dítě do B"               ERR reditelka.a "insert into deti (skola_id, jmeno, prijmeni, datum_narozeni, pohlavi, zahajeni) values ('$SB','X','Y','2022-01-01','M','2025-09-01');"
t "ředitelka A nevidí docházku B"               0   reditelka.a "select count(*) from dochazka where dite_id='$ADA';"
t "ředitelka A nevidí zaměstnance B"            0   reditelka.a "select count(*) from uzivatele where skola_id='$SB';"
echo "== učitelka"
t "učitelka A vidí jen děti své třídy (4)"      4   ucitelka.a "select count(*) from deti;"
t "učitelka A nevidí dítě z Berušek"            0   ucitelka.a "select count(*) from deti where id='$ANN';"
t "učitelka A nevidí rodná čísla"               ERR ucitelka.a "select rodne_cislo from deti limit 1;"
t "učitelka A nezapíše docházku cizí třídě"     ERR ucitelka.a "insert into dochazka (dite_id, den, stav) values ('$ANN', current_date + 1, 'pritomen');"
t "učitelka A nevidí platby"                    0   ucitelka.a "select count(*) from platby;"
t "učitelka A nezve zaměstnance"                ERR ucitelka.a "select pozvi_zamestnance('X','x@x.cz','ucitelka','$A1');"
echo "== rodič"
t "rodič A vidí jen své 2 děti"                 2   rodic.a "select count(*) from deti;"
t "rodič A nevidí Olivera"                      0   rodic.a "select count(*) from deti where id='$OLI';"
t "rodič A neomluví cizí dítě"                  ERR rodic.a "select omluv_dite('$OLI', current_date + 1, current_date + 1, 'x');"
t "rodič A omluví své dítě"                     1   rodic.a "select count(*) from omluv_dite('$EMA', current_date + 7, current_date + 7, 'test');"
t "rodič A nezmění údaje cizího dítěte"         ERR rodic.a "select uprav_udaje_rodicem('$OLI', 'hack');"
t "rodič A nevidí úrazy cizích dětí"            0   rodic.a "select count(*) from urazy;"
t "rodič A nevidí kontakty jiných rodičů"       0   rodic.a "select count(*) from zastupci where dite_id='$OLI';"
t "rodič A nevidí zaměstnance"                  1   rodic.a "select count(*) from uzivatele;"
t "rodič B nevidí školku A"                     0   rodic.b "select count(*) from skoly where id='$SA';"
echo "== superadmin"
t "superadmin vidí obě testovací školky"        2   superadmin "select count(*) from admin_skoly() where nazev like '%(test%';"
t "superadmin nečte děti"                       0   superadmin "select count(*) from deti;"
t "superadmin nečte docházku"                   0   superadmin "select count(*) from dochazka;"
t "superadmin nečte úrazy"                      0   superadmin "select count(*) from urazy;"
echo "== správa, blokace, pozvánky"
t "ředitelka nevolá admin_skoly"                ERR reditelka.a "select count(*) from admin_skoly();"
t "učitelka nevolá zamestnanci_skoly"           ERR ucitelka.a "select count(*) from zamestnanci_skoly();"
t "ředitelka nezve ředitelku"                   ERR reditelka.a "select pozvi_zamestnance('X','x@x.cz','reditelka',null);"
t "ředitelka nezve do cizí třídy"               ERR reditelka.a "select pozvi_zamestnance('X','x@x.cz','ucitelka','$B1');"
t "ředitelka nemění stav školky"                ERR reditelka.a "update skoly set stav='blokovana' where id='$SA';"
t "ředitelka nemění předplatné"                 ERR reditelka.a "update skoly set predplatne_do='2099-01-01' where id='$SA';"
t "ředitelka smí měnit kontakt"                 1   reditelka.a "with u as (update skoly set kontakt=kontakt where id='$SA' returning 1) select count(*) from u;"
t "ředitelka nečte poznámky správce"            0   reditelka.a "select count(*) from skoly_admin;"
t "ředitelka nečte superadminy"                 0   reditelka.a "select count(*) from superadmini;"
t "ředitelka nečte pozvánky přímo"              0   reditelka.a "select count(*) from pozvanky;"
t "ředitelka si nepřidá superadmina"            ERR reditelka.a "insert into superadmini values ('$(id reditelka.a)','x');"
t "ředitelka nevloží pozvánku přímo"            ERR reditelka.a "insert into pozvanky(kod,skola_id,email,jmeno,role) values ('AAAAAAAA','$SA','a@a.cz','a','reditelka');"
t "ředitelka neblokuje účet z B"                ERR reditelka.a "select nastav_ucet_zamestnance('$(id ucitelka.b)', false);"
t "ředitelka neblokuje sama sebe"               ERR reditelka.a "select nastav_ucet_zamestnance('$(id reditelka.a)', false);"
t "ředitelka nepovýší učitelku na ředitelku"    ERR reditelka.a "update uzivatele set role='reditelka' where email='ucitelka.a@test.lifeos.cz';"
t "ředitelka nepřesune učitelku do B"           ERR reditelka.a "update uzivatele set skola_id='$SB' where email='ucitelka.a@test.lifeos.cz';"
t "existující účet nepřijme pozvánku"           ERR reditelka.a "select prijmi_pozvanku('XXXXXXXX');"
t "zablokovaná učitelka nemá roli"              ""  zablokovana.a "select moje_role();"
t "zablokovaná učitelka nevidí děti"            0   zablokovana.a "select count(*) from deti;"
echo "== účet bez role (libovolná anonymní registrace)"
t "bez role: neomluví dítě"                     ERR nikdo "select omluv_dite('$EMA', current_date, current_date, 'x');"
t "bez role: nezmění alergie"                   ERR nikdo "select uprav_udaje_rodicem('$EMA', 'hack');"
t "bez role: nezveřejní jídelníček"             ERR nikdo "select zverejni_jidelnicek('[]');"
t "bez role: nepřepne náhrady"                  ERR nikdo "select nastav_nahrady(false);"
t "bez role: nepotvrdí omluvenku"               ERR nikdo "select potvrd_omluvenku('$EMA', current_date, current_date);"
t "bez role: nevidí děti"                       0   nikdo "select count(*) from deti;"
t "bez role: nevidí školky"                     0   nikdo "select count(*) from skoly;"
t "bez role: nevolá zamestnanci_skoly"          ERR nikdo "select count(*) from zamestnanci_skoly();"
echo "== anon (bez přihlášení)"
t "anon nemá admin funkce"                      ERR anon "select count(*) from admin_skoly();"
t "anon nečte skoly"                            ERR anon "select count(*) from skoly;"
t "anon nečte děti"                             ERR anon "select count(*) from deti;"
$P -c "delete from auth.users where id = '$NOROLE'" >/dev/null
echo "---- PASS $PASS · FAIL $FAIL"
[ $FAIL -eq 0 ]
