#!/bin/bash
# Bezpečnostní testy oprávnění přímo v databázi — každý test běží jako konkrétní
# identita (role authenticated + JWT claims), stejně jako dotaz z aplikace.
#   testy/bezpecnost.sh [databáze]     → vypíše PASS/FAIL, exit 1 při selhání
DB=${1:-${TEST_DB:-skolka_lokal}}
P="psql -h ${PGHOST_TEST:-/home/claude/.pgtest} -p ${PGPORT_TEST:-5499} -U postgres -d $DB -tAq"
A=00000000-0000-4000-8000-000000000001; B=00000000-0000-4000-8000-000000000002
EMA=00000000-0000-4000-8000-000000000101; OLI=00000000-0000-4000-8000-000000000102; TOB=00000000-0000-4000-8000-000000000103; ADAM=00000000-0000-4000-8000-000000000201
SLUN=00000000-0000-4000-8000-000000000011; ZAB=00000000-0000-4000-8000-000000000021
RA=aaaaaaaa-0000-4000-8000-000000000001; UA=aaaaaaaa-0000-4000-8000-000000000002; RODA=aaaaaaaa-0000-4000-8000-000000000003
ZA=aaaaaaaa-0000-4000-8000-000000000004; U2A=aaaaaaaa-0000-4000-8000-000000000005; HA=aaaaaaaa-0000-4000-8000-000000000006
KA=aaaaaaaa-0000-4000-8000-000000000007; ROD2A=aaaaaaaa-0000-4000-8000-000000000008
RB=bbbbbbbb-0000-4000-8000-000000000001; UB=bbbbbbbb-0000-4000-8000-000000000002; RODB=bbbbbbbb-0000-4000-8000-000000000003
SA=aaaaaaaa-0000-4000-8000-0000000000aa; NO=cccccccc-0000-4000-8000-0000000000cc
OK=0; KO=0
# t "popis" očekávání uid email "SQL"   (očekávání ERR = musí skončit chybou)
t() {
  local name="$1" exp="$2" uid="$3" mail="$4" q="$5" out r
  out=$(printf "begin;\nset local role authenticated;\nselect set_config('request.jwt.claim.sub','%s',true), set_config('request.jwt.claims','{\"sub\":\"%s\",\"email\":\"%s\",\"role\":\"authenticated\"}',true) \\\\g /dev/null\n%s\nrollback;\n" "$uid" "$uid" "$mail" "$q" | $P 2>&1 | grep -v '^CONTEXT\|^$\|^LINE\|^ *\^\|^HINT\|^DETAIL' | tail -1)
  if [[ "$exp" == ERR ]]; then [[ "$out" == *ERROR* ]] && r=PASS || r=FAIL; else [[ "$out" == "$exp" ]] && r=PASS || r=FAIL; fi
  [[ $r == PASS ]] && OK=$((OK+1)) || KO=$((KO+1))
  echo "$r  $name  →  $out"
}
anon() { local name="$1" q="$2" out; out=$(printf "begin; set local role anon;\n%s\nrollback;\n" "$q" | $P 2>&1 | grep ERROR | head -1); if [[ -n "$out" ]]; then OK=$((OK+1)); echo "PASS  $name  →  $out"; else KO=$((KO+1)); echo "FAIL  $name"; fi; }

echo "== oddělení školek"
t "ředitelka A vidí jen svou školku" 1 $RA reditelka@test.cz "select count(*) from skoly;"
t "ředitelka A nevidí dítě B" 0 $RA reditelka@test.cz "select count(*) from deti where id='$ADAM';"
t "ředitelka A nevidí úrazy B" 0 $RA reditelka@test.cz "select count(*) from urazy where skola_id='$B';"
t "ředitelka A nevidí události B" 0 $RA reditelka@test.cz "select count(*) from udalosti_ditete where skola_id='$B';"
t "ředitelka A nevidí zákonné zástupce B" 0 $RA reditelka@test.cz "select count(*) from zastupci where dite_id='$ADAM';"
t "ředitelka A nevidí účty B" 0 $RA reditelka@test.cz "select count(*) from uzivatele where skola_id='$B';"
t "ředitelka A nezmění dítě B" 0 $RA reditelka@test.cz "with u as (update deti set alergie='x' where id='$ADAM' returning 1) select count(*) from u;"
t "ředitelka A nevloží dítě do B" ERR $RA reditelka@test.cz "insert into deti (skola_id, trida_id, jmeno, prijmeni, datum_narozeni, zahajeni) values ('$B','$ZAB','X','Y','2022-01-01','2025-09-01');"
t "ředitelka A nepřesune své dítě do B" ERR $RA reditelka@test.cz "update deti set skola_id='$B', trida_id='$ZAB' where id='$EMA';"
t "ředitelka A nevydá kód rodiče k dítěti B" ERR $RA reditelka@test.cz "select vytvor_kod_rodice('$ADAM');"
t "učitelka B nevidí děti A" 0 $UB ucitelka.b@test.cz "select count(*) from deti where skola_id='$A';"
t "učitelka B nezapíše docházku dítěti A" ERR $UB ucitelka.b@test.cz "insert into dochazka (dite_id, den, stav) values ('$EMA', current_date, 'pritomen');"
echo "== učitelka (jen své třídy)"
t "učitelka Sluníček vidí 2 děti" 2 $UA ucitelka@test.cz "select count(*) from deti;"
t "učitelka Sluníček nevidí Tobiáše (Berušky)" 0 $UA ucitelka@test.cz "select count(*) from deti where id='$TOB';"
t "učitelka nevidí rodná čísla" ERR $UA ucitelka@test.cz "select rodne_cislo from deti limit 1;"
t "učitelka nevidí platby" 0 $UA ucitelka@test.cz "select count(*) from platby;"
t "učitelka nezapíše docházku dítěti cizí třídy" ERR $UA ucitelka@test.cz "insert into dochazka (dite_id, den, stav) values ('$TOB', current_date, 'pritomen');"
t "učitelka nezvě zaměstnance" ERR $UA ucitelka@test.cz "select pozvi_zamestnance('X','x@x.cz','ucitelka','$SLUN');"
echo "== rodič (jen své dítě)"
t "rodič Emy vidí 1 dítě" 1 $RODA "" "select count(*) from deti;"
t "rodič Emy nevidí Olivera" 0 $RODA "" "select count(*) from deti where id='$OLI';"
t "rodič Emy nevidí docházku Olivera" 0 $RODA "" "select count(*) from dochazka where dite_id='$OLI';"
t "rodič Emy nevidí cizí zástupce" 0 $RODA "" "select count(*) from zastupci where dite_id<>'$EMA';"
t "rodič Emy nevidí úrazy jiných" 0 $RODA "" "select count(*) from urazy where dite_id<>'$EMA';"
t "rodič Emy neomluví Olivera" ERR $RODA "" "select omluv_dite('$OLI', current_date, current_date, 'x');"
t "rodič Emy nezmění alergie Olivera" ERR $RODA "" "select uprav_udaje_rodicem('$OLI', 'x');"
t "rodič Emy nezmění alergie Adama (B)" ERR $RODA "" "select uprav_udaje_rodicem('$ADAM', 'x');"
t "rodič Emy omluví Emu" 1 $RODA "" "select count(*) from omluv_dite('$EMA', current_date + 7, current_date + 7, 'nemoc');"
t "rodič nezapíše docházku napřímo" ERR $RODA "" "insert into dochazka (dite_id, den, stav, prichod) values ('$EMA', current_date + 30, 'pritomen', '08:00');"
t "rodič nevidí účty zaměstnanců" 0 $RODA "" "select count(*) from uzivatele where role<>'rodic';"
t "rodič nevolá zamestnanci_skoly" ERR $RODA "" "select count(*) from zamestnanci_skoly();"
echo "== jídelna / hospodářka"
t "kuchařka nevidí rodná čísla" ERR $KA kucharka@test.cz "select rodne_cislo from deti limit 1;"
t "kuchařka nevidí zákonné zástupce" 0 $KA kucharka@test.cz "select count(*) from zastupci;"
t "kuchařka zveřejní jídelníček" 0 $KA kucharka@test.cz "select zverejni_jidelnicek('[]');"
t "učitelka nezveřejní jídelníček" ERR $UA ucitelka@test.cz "select zverejni_jidelnicek('[]');"
t "rodič nepřepne náhrady" ERR $RODA "" "select nastav_nahrady(false);"
echo "== superadmin a pozvánky"
t "ředitelka nevolá admin_skoly" ERR $RA reditelka@test.cz "select count(*) from admin_skoly();"
t "superadmin vidí 2 školky" 2 $SA roman@lifeos.cz "select count(*) from admin_skoly();"
t "superadmin nečte děti" 0 $SA roman@lifeos.cz "select count(*) from deti;"
t "superadmin nečte úrazy" 0 $SA roman@lifeos.cz "select count(*) from urazy;"
t "ředitelka nemění stav školky" ERR $RA reditelka@test.cz "update skoly set stav='blokovana' where id='$A';"
t "ředitelka nemění předplatné" ERR $RA reditelka@test.cz "update skoly set predplatne_do='2099-01-01' where id='$A';"
t "ředitelka smí měnit kontakt" 1 $RA reditelka@test.cz "with u as (update skoly set kontakt=kontakt where id='$A' returning 1) select count(*) from u;"
t "ředitelka nečte poznámky správce" 0 $RA reditelka@test.cz "select count(*) from skoly_admin;"
t "ředitelka nečte pozvánky napřímo" 0 $RA reditelka@test.cz "select count(*) from pozvanky;"
t "ředitelka si nepřidá superadmina" ERR $RA reditelka@test.cz "insert into superadmini values ('$RA','x');"
t "ředitelka nevloží pozvánku napřímo" ERR $RA reditelka@test.cz "insert into pozvanky(kod,skola_id,email,jmeno,role) values ('AAAAAAAA','$A','a@a.cz','a','reditelka');"
t "ředitelka nezve ředitelku" ERR $RA reditelka@test.cz "select pozvi_zamestnance('X','x@x.cz','reditelka',null);"
t "ředitelka nezve do třídy B" ERR $RA reditelka@test.cz "select pozvi_zamestnance('X','x@x.cz','ucitelka','$ZAB');"
t "ředitelka neblokuje účet B" ERR $RA reditelka@test.cz "select nastav_ucet_zamestnance('$UB', false);"
t "ředitelka neblokuje sebe" ERR $RA reditelka@test.cz "select nastav_ucet_zamestnance('$RA', false);"
t "ředitelka nepovýší učitelku na ředitelku" ERR $RA reditelka@test.cz "update uzivatele set role='reditelka' where id='$UA';"
t "ředitelka nepřesune učitelku do B" ERR $RA reditelka@test.cz "update uzivatele set skola_id='$B' where id='$UA';"
t "zástupkyně neblokuje ředitelku" ERR $ZA zastupce@test.cz "select nastav_ucet_zamestnance('$RA', false);"
t "pozvánka jde přijmout jen správným e-mailem" ERR $NO jiny@test.cz "select prijmi_pozvanku(pozvi_zamestnance('X','bezrole@test.cz','kucharka',null));"
t "existující účet nepřijme další pozvánku" ERR $RA reditelka@test.cz "select prijmi_pozvanku('XXXXXXXX');"
echo "== blokace"
t "zablokovaná učitelka nic nevidí" 0 $UA ucitelka@test.cz "reset role; update uzivatele set aktivni=false where id='$UA'; set local role authenticated; select count(*) from deti;"
t "zablokovaná školka: ředitelka nic nevidí" 0 $RA reditelka@test.cz "reset role; update skoly set stav='blokovana' where id='$A'; set local role authenticated; select count(*) from deti;"
t "zablokovaná školka: rodič nic nevidí" 0 $RODA "" "reset role; update skoly set stav='blokovana' where id='$A'; set local role authenticated; select count(*) from deti;"
t "zablokovaná školka: rodič neomluví" ERR $RODA "" "reset role; update skoly set stav='blokovana' where id='$A'; set local role authenticated; select omluv_dite('$EMA', current_date + 8, current_date + 8, 'x');"
echo "== účet bez role (libovolná registrace)"
t "bez role: nevidí děti" 0 $NO bezrole@test.cz "select count(*) from deti;"
t "bez role: neomluví dítě" ERR $NO bezrole@test.cz "select omluv_dite('$EMA', current_date, current_date, 'x');"
t "bez role: nezmění alergie" ERR $NO bezrole@test.cz "select uprav_udaje_rodicem('$EMA', 'x');"
t "bez role: nezveřejní jídelníček" ERR $NO bezrole@test.cz "select zverejni_jidelnicek('[]');"
t "bez role: nepřepne náhrady" ERR $NO bezrole@test.cz "select nastav_nahrady(false);"
t "bez role: nepotvrdí omluvenku" ERR $NO bezrole@test.cz "select potvrd_omluvenku('$EMA', current_date, current_date);"
t "bez role: neuplatní neplatný kód" ERR $NO bezrole@test.cz "select * from uplatni_kod('neplatny', 'X');"
echo "== anonymní klíč bez přihlášení"
anon "anon nečte děti" "select count(*) from deti;"
anon "anon nevolá admin_skoly" "select count(*) from admin_skoly();"
anon "anon neomluví dítě" "select omluv_dite('$EMA', current_date, current_date, 'x');"
echo "---- $OK PASS, $KO FAIL"
[[ $KO == 0 ]]
