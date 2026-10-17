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
SA=aaaaaaaa-0000-4000-8000-0000000000aa; NO=cccccccc-0000-4000-8000-0000000000cc; AN=dddddddd-0000-4000-8000-0000000000dd
BER=00000000-0000-4000-8000-000000000012
OK=0; KO=0
# t "popis" očekávání uid email "SQL"   (očekávání ERR = musí skončit chybou)
t() {
  local name="$1" exp="$2" uid="$3" mail="$4" q="$5" out r
  out=$(printf "begin;\nset local role authenticated;\nselect set_config('request.jwt.claim.sub','%s',true), set_config('request.jwt.claims','{\"sub\":\"%s\",\"email\":\"%s\",\"role\":\"authenticated\"}',true) \\\\g /dev/null\n%s\nrollback;\n" "$uid" "$uid" "$mail" "$q" | $P 2>&1 | grep -v '^CONTEXT\|^$\|^LINE\|^ *\^\|^HINT\|^DETAIL\|^PL/pgSQL\|^SQL statement\|^ ' | tail -1)
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
t "učitelka nevidí rodná čísla" ERR $UB ucitelka.b@test.cz "select rodne_cislo from deti where id='$ADAM';"
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
# příští školní den (v pátek pondělí) — o víkendu omluva nic nevrací
DALSI_DEN="(current_date + case extract(isodow from current_date)::int when 5 then 3 when 6 then 2 else 1 end)"
t "rodič Emy omluví Emu" 1 $RODA "" "select count(*) from omluv_dite('$EMA', $DALSI_DEN + 7, $DALSI_DEN + 7, 'nemoc');"
t "rodič nezapíše docházku napřímo" ERR $RODA "" "insert into dochazka (dite_id, den, stav, prichod) values ('$EMA', current_date + 30, 'pritomen', '08:00');"
t "rodič nevidí účty zaměstnanců" 0 $RODA "" "select count(*) from uzivatele where role<>'rodic';"
t "rodič nevolá zamestnanci_skoly" ERR $RODA "" "select count(*) from zamestnanci_skoly();"
echo "== jídelna / hospodářka"
t "kuchařka nevidí rodná čísla" ERR $KA kucharka@test.cz "select rodne_cislo from deti;"
t "ředitelka čte rodné číslo přes deti_osobni" 220120/0000 $RA reditelka@test.cz "select rodne_cislo from deti_osobni('$TOB');"
t "učitelka nečte deti_osobni" 0 $UA ucitelka@test.cz "select count(*) from deti_osobni();"
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
t "bez role: neplatný kód nic nespáruje" 0 $NO bezrole@test.cz "select count(*) from uplatni_kod('neplatny', 'X');"
echo "== anonymní klíč bez přihlášení"
anon "anon nečte děti" "select count(*) from deti;"
anon "anon nevolá admin_skoly" "select count(*) from admin_skoly();"
anon "anon neomluví dítě" "select omluv_dite('$EMA', current_date, current_date, 'x');"
JB="reset role; insert into jidla (id, skola_id, nazev, druh) values ('00000000-0000-4000-8000-0000000ed002','$B','Oběd B','obed'); insert into suroviny (id, skola_id, nazev, alergeny) values ('00000000-0000-4000-8000-0000000ec002','$B','Mouka B','{1}'); insert into jidlo_suroviny values ('00000000-0000-4000-8000-0000000ed002','00000000-0000-4000-8000-0000000ec002'); insert into nahrady values ('00000000-0000-4000-8000-0000000ed002',1,'Bez lepku B'); set local role authenticated;"
echo "== E1 pohled deti_jidelna"
t "kuchařka nezmění alergie přes deti_jidelna" ERR $KA kucharka@test.cz "update deti_jidelna set alergie=null where id='$TOB';"
t "kuchařka nesmaže dítě přes deti_jidelna" ERR $KA kucharka@test.cz "delete from deti_jidelna where id='$OLI';"
echo "== E2 pozvánka a účet bez e-mailu"
t "anonymní účet (JWT bez e-mailu) nepřijme pozvánku ředitelky" ERR $AN "" "reset role; insert into auth.users (id, is_anonymous) values ('$AN', true); insert into pozvanky (kod, skola_id, email, jmeno, role) values ('RRRRSSSS','$B','r2.b@test.cz','R2','reditelka'); set local role authenticated; select set_config('request.jwt.claims','{\"sub\":\"$AN\",\"role\":\"authenticated\",\"is_anonymous\":true}',true) \\g /dev/null
select * from prijmi_pozvanku('RRRR-SSSS');"
echo "== E3 jídelna napříč školkami"
t "kuchařka A nečte diety dítěte B" 0 $KA kucharka@test.cz "reset role; insert into diety values ('$ADAM', true, 'anafylaxe B'); set local role authenticated; select count(*) from diety where dite_id='$ADAM';"
t "kuchařka A nezmění dietu dítěte B" 0 $KA kucharka@test.cz "reset role; insert into diety values ('$ADAM', true, 'anafylaxe B'); set local role authenticated; with u as (update diety set poznamka='x' where dite_id='$ADAM' returning 1) select count(*) from u;"
t "kuchařka A nesmaže alergeny jídla B" 0 $KA kucharka@test.cz "$JB with d as (delete from jidlo_suroviny where jidlo_id='00000000-0000-4000-8000-0000000ed002' returning 1) select count(*) from d;"
t "kuchařka A nesmaže náhrady jídla B" 0 $KA kucharka@test.cz "$JB with d as (delete from nahrady where jidlo_id='00000000-0000-4000-8000-0000000ed002' returning 1) select count(*) from d;"
t "účet bez role nečte náhrady žádné školky" 0 $NO bezrole@test.cz "$JB select count(*) from nahrady;"
echo "== E4 třídní kniha"
t "ředitelka A nečte třídní knihu B" 0 $RA reditelka@test.cz "reset role; insert into tridni_kniha (trida_id, den, tema, cinnosti) values ('$ZAB', current_date, 'B', '{b}'); set local role authenticated; select count(*) from tridni_kniha where trida_id='$ZAB';"
t "ředitelka A nezapíše do třídní knihy B" ERR $RA reditelka@test.cz "insert into tridni_kniha (trida_id, den, tema, cinnosti) values ('$ZAB', current_date+1, 'x', '{x}');"
echo "== E5 citlivé sloupce"
t "hospodářka nevidí rodná čísla" ERR $HA hospodarka@test.cz "select rodne_cislo from deti limit 1;"
t "učitelka nevidí adresy" ERR $UA ucitelka@test.cz "select adresa from deti limit 1;"
echo "== E6 účetní kniha"
t "hospodářka nezapíše do knihy přímo (jen funkcí vystav_predpisy)" ERR $HA hospodarka@test.cz "with i as (insert into ucetni_pohyby (skola_id, datum, md, dal, castka, popis) values ('$A', current_date, 'dite:$EMA', 'vynosy:skolkovne', 100, 'x') returning 1) select count(*) from i;"
t "hospodářka A nepřipíše pohyb dítěti B" ERR $HA hospodarka@test.cz "insert into ucetni_pohyby (skola_id, datum, md, dal, castka, popis) values ('$A', current_date, 'banka', 'dite:$ADAM', 100, 'x');"
echo "== E7 účty zaměstnanců"
t "ředitelka nedegraduje spoluředitelku" ERR $RA reditelka@test.cz "reset role; insert into auth.users(id,email) values ('aaaaaaaa-0000-4000-8000-0000000000f2','r2@test.cz'); insert into uzivatele (id, skola_id, jmeno, role) values ('aaaaaaaa-0000-4000-8000-0000000000f2','$A','R2','reditelka'); set local role authenticated; with u as (update uzivatele set role='ucitelka', aktivni=false where id='aaaaaaaa-0000-4000-8000-0000000000f2' returning 1) select 1/count(*) from u;"
t "ředitelka nezmění id účtu (převod na jiného uživatele)" ERR $RA reditelka@test.cz "with u as (update uzivatele set id='aaaaaaaa-0000-4000-8000-0000000000aa' where id='$HA' returning 1) select 1/count(*) from u;"
t "ředitelka neudělá z rodiče učitelku" ERR $RA reditelka@test.cz "with u as (update uzivatele set role='ucitelka' where id='$RODA' returning 1) select 1/count(*) from u;"
echo "== E8 vazby napříč školkami"
t "ředitelka B nepřiřadí učitelku A do své třídy" ERR $RB reditelka.b@test.cz "insert into ucitel_trida values ('$UA', '$ZAB');"
t "ředitelka A nepřesune dítě do třídy B" ERR $RA reditelka@test.cz "with u as (update deti set trida_id='$ZAB' where id='$EMA' returning 1) select 1/count(*) from u;"
t "ředitelka A nepřesune dítě na den do třídy B" ERR $RA reditelka@test.cz "insert into dochazka (dite_id, den, stav, trida_dnes) values ('$EMA', current_date+40, 'pritomen', '$ZAB');"
t "učitelka nezapíše úraz do knihy cizí školky" ERR $UA ucitelka@test.cz "insert into urazy (skola_id, cislo, rok, dite_id, kdy, co, zapsal) values ('$B', 999, 2026, '$EMA', now(), 'x', '$UA');"
echo "== E9 omluvenky"
t "rodič neomluví zpětně neomluvenou absenci" ERR $ROD2A "" "reset role; insert into dochazka (dite_id, den, stav) values ('$OLI', current_date-7, 'neomluven') on conflict do nothing; set local role authenticated; select count(*) from omluv_dite('$OLI', current_date-7, current_date-7, 'x');"
echo "== E10 číslování úrazů"
t "učitelka Sluníček zapíše úraz, i když Berušky mají vyšší číslo" 1 $UA ucitelka@test.cz "reset role; delete from urazy where skola_id='$A'; insert into urazy (skola_id, cislo, rok, dite_id, kdy, co, zapsal) values ('$A', 1, extract(year from now())::int, '$EMA', now(), 'a', '$UA'), ('$A', 2, extract(year from now())::int, '$TOB', now(), 'b', '$U2A'); set local role authenticated; with i as (insert into urazy (skola_id, cislo, rok, dite_id, kdy, co, zapsal) values ('$A', (select coalesce(max(cislo),0)+1 from urazy where skola_id='$A' and rok=extract(year from now())::int), extract(year from now())::int, '$EMA', now(), 'c', '$UA') returning 1) select count(*) from i;"
echo "== E12 mazání dítěte"
t "ředitelka nesmaže dítě (finanční záznamy)" ERR $RA reditelka@test.cz "with d as (delete from deti where id='$OLI' returning 1) select 1/count(*) from d;"
echo "== E14 kód cizí školky"
t "rodič školky A neuplatní kód školky B" ERR $RODA "" "reset role; insert into parovaci_kody (kod, skola_id, dite_id, plati_do) values ('CCCCDDDD','$B','$ADAM', now()+interval '1 day'); set local role authenticated; select dite_id from uplatni_kod('CCCC-DDDD','X');"
echo "== kódy rodičů: limit pokusů"
POKUSY=$(for i in $(seq 10); do printf "select count(*) from nahled_kodu('ZZZZ-ZZZZ'); "; done)
t "10 chybných pokusů → 11. zablokován" ERR $NO bezrole@test.cz "$POKUSY select count(*) from nahled_kodu('ZZZZ-ZZZZ');"
t "9 chybných pokusů → 10. ještě projde" 0 $NO bezrole@test.cz "$(for i in $(seq 9); do printf "select count(*) from nahled_kodu('ZZZZ-ZZZZ'); "; done) select count(*) from nahled_kodu('ZZZZ-ZZZZ');"
t "neplatný kód vrací prázdno (ne výjimku)" 0 $NO bezrole@test.cz "select count(*) from uplatni_kod('ZZZZ-ZZZZ', 'X');"
t "kód má 8 znaků z 32 možností" 8 $RA reditelka@test.cz "reset role; select length(nahodny_kod());"
echo "== zprávy podle adresáta"
ZPR="reset role; insert into zpravy (skola_id, komu, predmet, text) values ('$A','dite:$OLI','Dluh','x'), ('$A','trida:$BER','Berušky','x'), ('$A','zamestnanci','Porada','x'); set local role authenticated;"
t "rodič Emy nečte zprávu pro Olivera" 0 $RODA "" "$ZPR select count(*) from zpravy where komu='dite:$OLI';"
t "rodič Olivera čte zprávu pro Olivera" 1 $ROD2A "" "$ZPR select count(*) from zpravy where komu='dite:$OLI';"
t "rodič nečte zprávu pro zaměstnance" 0 $RODA "" "$ZPR select count(*) from zpravy where komu='zamestnanci';"
t "rodič Emy nečte zprávu pro Berušky" 0 $RODA "" "$ZPR select count(*) from zpravy where komu like 'trida:%';"
t "kuchařka nečte zprávu pro rodinu" 0 $KA kucharka@test.cz "$ZPR select count(*) from zpravy where komu like 'dite:%';"
t "ředitelka čte všechny zprávy" 4 $RA reditelka@test.cz "$ZPR select count(*) from zpravy;"
echo "== autor zápisu"
t "učitelka nepodvrhne autora události" $UA $UA ucitelka@test.cz "insert into udalosti_ditete (skola_id, dite_id, druh, titulek, zapsal, zapsal_jmeno) values ('$A','$EMA','info','x','$RA','Ředitelka'); select zapsal from udalosti_ditete where titulek='x';"
echo "== odpojení rodiče"
t "rodič odpojí své dítě (server zapomene propojení)" 0 $RODA "" "select odpoj_rodice('$EMA'); select count(*) from deti;"
t "po odpojení rodič nemá účet ve školce" 0 $RODA "" "select odpoj_rodice('$EMA'); reset role; select count(*) from uzivatele where id='$RODA';"
t "cizí rodič neodpojí cizí dítě" 1 $ROD2A "" "select odpoj_rodice('$EMA'); reset role; select count(*) from zastupci where dite_id='$EMA' and uzivatel_id='$RODA';"
echo "== regresní audit (R1, R5, R6, R10, D13, zprávy)"
t "zveřejnění nesmaže jídelníček mimo jeden týden" ERR $KA kucharka@test.cz "select zverejni_jidelnicek('[]', '2000-01-03', '2099-12-31');"
t "ředitelka A nepřipojí k dítěti rodiče školky B" ERR $RA reditelka@test.cz "update zastupci set uzivatel_id='$RODB' where dite_id='$EMA';"
t "ředitelka A nevloží akci pro třídu školky B" ERR $RA reditelka@test.cz "insert into akce (skola_id, trida_id, den, nazev) values ('$A', '$ZAB', current_date + 3, 'x');"
t "hospodářka A nevloží platbu dítěti B" ERR $HA hospodarka@test.cz "insert into platby (skola_id, datum, castka, dite_id) values ('$A', current_date, 100, '$ADAM');"
t "odpoj_rodice cizího dítěte nic nesmaže" 1 $NO bezrole@test.cz "reset role; insert into zastupci (dite_id, jmeno, poradi) values ('$ADAM', 'osiřelý', 9); set local role authenticated; select odpoj_rodice('$ADAM'); reset role; select count(*) from zastupci where dite_id='$ADAM' and jmeno='osiřelý';"
t "rodič nedostane omluvu za den, kdy dítě je ve školce" ERR $RODA "" "reset role; insert into dochazka (dite_id, den, stav, prichod) values ('$EMA', $DALSI_DEN, 'pritomen', '08:00'); set local role authenticated; select count(*) from omluv_dite('$EMA', $DALSI_DEN, $DALSI_DEN, 'x');"
t "zpráva neplatnému adresátovi neprojde" ERR $RA reditelka@test.cz "insert into zpravy (skola_id, komu, predmet, text) values ('$A', 'nesmysl', 'x', 'x');"
t "zpráva pro třídu cizí školky neprojde" ERR $RA reditelka@test.cz "insert into zpravy (skola_id, komu, predmet, text) values ('$A', 'trida:$ZAB', 'x', 'x');"
t "náhled kódu nevrací datum narození" "Ema|" $NO bezrole@test.cz "reset role; insert into parovaci_kody (kod, skola_id, dite_id, plati_do) values ('QQQQRRRR','$A','$EMA', now()+interval '1 day'); set local role authenticated; select jmeno || '|' || coalesce(datum_narozeni::text, '') from nahled_kodu('QQQQ-RRRR');"
t "uloz_chody: víkend odmítnut" ERR $KA kucharka@test.cz "select uloz_chody(jsonb_build_array(jsonb_build_object('den', (date_trunc('week', current_date)::date + 5)::text, 'chod', 'obed', 'nazev', 'x')));"
t "uloz_chody: neplatný alergen česky" ERR $KA kucharka@test.cz "select uloz_chody('[{\"den\":\"2026-10-12\",\"chod\":\"obed\",\"nazev\":\"x\",\"alergeny\":[\"abc\"]}]');"
t "uloz_chody: učitelka nesmí" ERR $UA ucitelka@test.cz "select uloz_chody('[]');"
t "uloz_chody: návrh rodič nevidí" 0 $RODA "" "reset role; set local role authenticated; select set_config('request.jwt.claim.sub','$KA',true) \\g /dev/null
select uloz_chody(jsonb_build_array(jsonb_build_object('den', (date_trunc('week', current_date)::date + 7)::text, 'chod', 'obed', 'nazev', 'Návrh X', 'zverejnit', false)));
select set_config('request.jwt.claim.sub','$RODA',true) \\g /dev/null
select count(*) from jidelnicek_tyden(date_trunc('week', current_date)::date + 7, date_trunc('week', current_date)::date + 11) where nazev='Návrh X';"
echo "== zprávy: kanál rodič–učitelka–vedení"
INS() { echo "with x as (insert into zpravy (komu, predmet, text$3) values ('$1', '', '$2'$4) returning 1) select count(*) from x;"; }
t "rodič napíše do kanálu svého dítěte" 1 $RODA "" "$(INS dite:$EMA 'Dobrý den')"
t "rodič nenapíše do kanálu cizího dítěte" ERR $RODA "" "$(INS dite:$OLI 'x')"
t "rodič nenapíše celé třídě" ERR $RODA "" "$(INS trida:$SLUN 'x')"
t "rodič nenapíše celé školce" ERR $RODA "" "$(INS vse 'x')"
t "rodič nenapíše vedení jako zaměstnanec" ERR $RODA "" "$(INS vedeni:$RODA 'x')"
t "rodič nepodvrhne odesílatele ani jméno" "$RODA|Jana Testová|rodic" $RODA "" "insert into zpravy (komu, predmet, text, odeslal, od_jmeno, od_role) values ('dite:$EMA', '', 'x', '$RA', 'Ředitelka', 'reditelka'); select odeslal || '|' || od_jmeno || '|' || od_role from zpravy where komu='dite:$EMA';"
t "předmět se doplní z textu" "Prosím o zavolání" $RODA "" "insert into zpravy (komu, predmet, text) values ('dite:$EMA', '', 'Prosím o zavolání'); select predmet from zpravy where komu='dite:$EMA';"
t "prázdná zpráva neprojde" ERR $RODA "" "$(INS dite:$EMA '   ')"
t "učitelka napíše rodičům své třídy" 1 $UA ucitelka@test.cz "$(INS trida:$SLUN 'Zítra výlet')"
t "učitelka nenapíše rodičům cizí třídy" ERR $UA ucitelka@test.cz "$(INS trida:$BER 'x')"
t "učitelka nenapíše rodičům dítěte cizí třídy" ERR $UA ucitelka@test.cz "$(INS dite:$TOB 'x')"
t "učitelka napíše rodičům dítěte své třídy" 1 $UA ucitelka@test.cz "$(INS dite:$OLI 'x')"
t "učitelka napíše vedení" 1 $UA ucitelka@test.cz "$(INS vedeni:$UA 'Potřebuji volno')"
t "učitelka nepíše za jinou učitelku" ERR $UA ucitelka@test.cz "$(INS vedeni:$U2A 'x')"
t "učitelka nenapíše celé školce" ERR $UA ucitelka@test.cz "$(INS vse 'x')"
t "kuchařka nenapíše rodičům" ERR $KA kucharka@test.cz "$(INS dite:$EMA 'x')"
VED="reset role; select set_config('request.jwt.claim.sub','$UA',true) \\g /dev/null
insert into zpravy (komu, predmet, text) values ('vedeni:$UA', '', 'Soukromé vedení'); set local role authenticated; select set_config('request.jwt.claim.sub','\$ME',true) \\g /dev/null
"
t "jiná učitelka nečte zprávu kolegyně vedení" 0 $U2A ucitelka2@test.cz "${VED//\$ME/$U2A} select count(*) from zpravy where komu like 'vedeni:%';"
t "rodič nečte zprávy vedení" 0 $RODA "" "${VED//\$ME/$RODA} select count(*) from zpravy where komu like 'vedeni:%';"
t "ředitelka čte zprávu učitelky vedení" 1 $RA reditelka@test.cz "${VED//\$ME/$RA} select count(*) from zpravy where komu like 'vedeni:%';"
t "ředitelka B nenapíše učitelce A" ERR $RB reditelka.b@test.cz "$(INS vedeni:$UA 'x')"
t "ředitelka nenapíše vedení:<rodič>" ERR $RA reditelka@test.cz "$(INS vedeni:$RODA 'x')"
KOR="reset role; select set_config('request.jwt.claim.sub','$RA',true) \\g /dev/null
insert into zpravy (id, komu, predmet, text) values ('99999999-0000-4000-8000-000000000001', 'vse', 'Besídka', 'Ve čtvrtek'), ('99999999-0000-4000-8000-000000000002', 'trida:$BER', 'Berušky', 'x'); set local role authenticated; select set_config('request.jwt.claim.sub','\$ME',true) \\g /dev/null
"
t "rodič odpoví na zprávu celé školce (předmět z vlákna)" "Besídka" $RODA "" "${KOR//\$ME/$RODA} insert into zpravy (komu, predmet, text, odpoved_na) values ('dite:$EMA', '', 'Přijdeme', '99999999-0000-4000-8000-000000000001'); select predmet from zpravy where odpoved_na is not null;"
t "rodič neodpoví na zprávu, kterou nevidí" ERR $RODA "" "${KOR//\$ME/$RODA} insert into zpravy (komu, predmet, text, odpoved_na) values ('dite:$EMA', '', 'x', '99999999-0000-4000-8000-000000000002');"
t "odpověď na odpověď patří do stejného vlákna" 2 $RODA "" "${KOR//\$ME/$RODA} insert into zpravy (id, komu, predmet, text, odpoved_na) values ('99999999-0000-4000-8000-000000000003', 'dite:$EMA', '', 'a', '99999999-0000-4000-8000-000000000001'); insert into zpravy (komu, predmet, text, odpoved_na) values ('dite:$EMA', '', 'b', '99999999-0000-4000-8000-000000000003'); select count(*) from zpravy where odpoved_na='99999999-0000-4000-8000-000000000001';"
t "odpověď rodiče Emy jiný rodič nevidí" 0 $ROD2A "" "${KOR//\$ME/$RODA} insert into zpravy (komu, predmet, text, odpoved_na) values ('dite:$EMA', '', 'Přijdeme', '99999999-0000-4000-8000-000000000001'); select set_config('request.jwt.claim.sub','$ROD2A',true) \\g /dev/null
select count(*) from zpravy where odpoved_na is not null;"
t "zprávu nejde upravit" ERR $RA reditelka@test.cz "${KOR//\$ME/$RA} update zpravy set text='změna';"
t "zprávu nejde smazat" ERR $RA reditelka@test.cz "${KOR//\$ME/$RA} delete from zpravy;"
t "rodič potvrdí zprávu celé školce" 1 $RODA "" "${KOR//\$ME/$RODA} select precti_zpravy(array['99999999-0000-4000-8000-000000000001']::uuid[], true);"
t "rodič nepotvrdí zprávu, kterou nevidí" 0 $RODA "" "${KOR//\$ME/$RODA} select precti_zpravy(array['99999999-0000-4000-8000-000000000002']::uuid[], true);"
t "do přečtení nejde zapsat přímo" ERR $RODA "" "${KOR//\$ME/$RODA} insert into zpravy_precteni (zprava_id, uzivatel_id) values ('99999999-0000-4000-8000-000000000001', '$RODA');"
t "rodič nevidí, kdo další zprávu potvrdil" 0 $ROD2A "" "${KOR//\$ME/$RODA} select precti_zpravy(array['99999999-0000-4000-8000-000000000001']::uuid[], true); select set_config('request.jwt.claim.sub','$ROD2A',true) \\g /dev/null
select count(*) from zpravy_precteni; select count(*) from potvrzeni_zprav(array['99999999-0000-4000-8000-000000000001']::uuid[]);"
t "ředitelka vidí, kdo potvrdil" "Jana Testová|Ema Testová" $RA reditelka@test.cz "${KOR//\$ME/$RODA} select precti_zpravy(array['99999999-0000-4000-8000-000000000001']::uuid[], true); select set_config('request.jwt.claim.sub','$RA',true) \\g /dev/null
select jmeno || '|' || dite from potvrzeni_zprav(array['99999999-0000-4000-8000-000000000001']::uuid[]) where potvrzeno is not null;"
t "učitelka Berušek nevidí potvrzení rodiče ze Sluníček" 0 $U2A ucitelka2@test.cz "${KOR//\$ME/$RODA} select precti_zpravy(array['99999999-0000-4000-8000-000000000001']::uuid[], true); select set_config('request.jwt.claim.sub','$U2A',true) \\g /dev/null
select count(*) from potvrzeni_zprav(array['99999999-0000-4000-8000-000000000001']::uuid[]);"
echo "== porady: čte vedení a učitelky, zapisuje jen vedení"
PSEED="reset role; insert into porady (id, skola_id, den, druh, program) values ('99999999-0000-4000-8000-0000000000a1', '$A', '2026-09-01', 'Pedagogická rada', 'Seed A'), ('99999999-0000-4000-8000-0000000000b1', '$B', '2026-09-01', 'Provozní porada', 'Seed B'); set local role authenticated; select set_config('request.jwt.claim.sub','\$ME',true) \\g /dev/null
"
PINS() { echo "with x as (insert into porady (skola_id, den, druh, program, pritomni) values ('$A', '2026-10-15', 'Pedagogická rada', '$1', array['Jana']) returning 1) select count(*) from x;"; }
t "ředitelka zapíše zápis z porady" 1 $RA reditelka@test.cz "$(PINS 'Plán roku')"
t "zástupkyně zapíše zápis z porady" 1 $ZA zastupce@test.cz "$(PINS 'Plán roku')"
t "učitelka zápis nezapíše" ERR $UA ucitelka@test.cz "$(PINS 'x')"
t "hospodářka zápis nezapíše" ERR $HA hospodarka@test.cz "$(PINS 'x')"
t "rodič zápis nezapíše" ERR $RODA "" "$(PINS 'x')"
t "ředitelka A nezapíše zápis do školky B" ERR $RA reditelka@test.cz "insert into porady (skola_id, den, druh, program) values ('$B', '2026-10-15', 'Pedagogická rada', 'x');"
t "prázdný program neprojde" ERR $RA reditelka@test.cz "$(PINS '   ')"
t "ředitelka čte jen zápisy své školky" 1 $RA reditelka@test.cz "${PSEED//\$ME/$RA} select count(*) from porady;"
t "učitelka zápisy čte" 1 $UA ucitelka@test.cz "${PSEED//\$ME/$UA} select count(*) from porady;"
t "hospodářka zápisy nevidí" 0 $HA hospodarka@test.cz "${PSEED//\$ME/$HA} select count(*) from porady;"
t "kuchařka zápisy nevidí" 0 $KA kucharka@test.cz "${PSEED//\$ME/$KA} select count(*) from porady;"
t "rodič zápisy nevidí" 0 $RODA "" "${PSEED//\$ME/$RODA} select count(*) from porady;"
t "ředitelka B nevidí zápisy školky A" 1 $RB reditelka.b@test.cz "${PSEED//\$ME/$RB} select count(*) from porady where skola_id='$B';"
t "ředitelka B nevidí zápis A" 0 $RB reditelka.b@test.cz "${PSEED//\$ME/$RB} select count(*) from porady where id='99999999-0000-4000-8000-0000000000a1';"
t "zápis nejde upravit" ERR $RA reditelka@test.cz "${PSEED//\$ME/$RA} update porady set program='přepsáno' where id='99999999-0000-4000-8000-0000000000a1';"
t "zápis nejde smazat" ERR $RA reditelka@test.cz "${PSEED//\$ME/$RA} delete from porady where id='99999999-0000-4000-8000-0000000000a1';"
echo "== zápis: žádosti vidí a řídí jen vedení"
NZ="select reg_cislo from nova_zadost(2027, 'Tereza', 'Malá', '225305/0008', '2022-03-05', 'F', true, false, 'mala@test.cz');"
ZSEED="reset role; insert into zadosti (id, skola_id, rok, reg_cislo, jmeno, prijmeni, rodne_cislo, datum_narozeni) values ('99999999-0000-4000-8000-0000000000c1', '$A', 2027, 'Z001', 'Eva', 'A', '220101/0001', '2022-01-01'), ('99999999-0000-4000-8000-0000000000c2', '$B', 2027, 'Z001', 'Iva', 'B', '220202/0002', '2022-02-02'); set local role authenticated; select set_config('request.jwt.claim.sub','\$ME',true) \\g /dev/null
"
t "ředitelka zapíše žádost (Z001)" Z001 $RA reditelka@test.cz "$NZ"
t "druhá žádost dostane Z002" Z002 $RA reditelka@test.cz "$NZ select reg_cislo from nova_zadost(2027, 'Jan', 'Novák', '215101/0007', '2021-01-01', 'M', false, false, '');" 2>/dev/null
t "stejné RČ podruhé neprojde" ERR $RA reditelka@test.cz "$NZ $NZ"
t "zástupkyně zapíše žádost" Z001 $ZA zastupce@test.cz "$NZ"
t "učitelka žádost nezapíše" ERR $UA ucitelka@test.cz "$NZ"
t "hospodářka žádost nezapíše" ERR $HA hospodarka@test.cz "$NZ"
t "rodič žádost nezapíše" ERR $RODA "" "$NZ"
t "žádost nejde vložit přímo (obejít reg. číslo)" ERR $RA reditelka@test.cz "insert into zadosti (skola_id, rok, reg_cislo, jmeno, rodne_cislo, datum_narozeni) values ('$A', 2027, 'Z999', 'X', '1', '2022-01-01');"
t "učitelka žádosti nevidí (rodná čísla)" 0 $UA ucitelka@test.cz "${ZSEED//\$ME/$UA} select count(*) from zadosti;"
t "hospodářka žádosti nevidí" 0 $HA hospodarka@test.cz "${ZSEED//\$ME/$HA} select count(*) from zadosti;"
t "rodič žádosti nevidí" 0 $RODA "" "${ZSEED//\$ME/$RODA} select count(*) from zadosti;"
t "ředitelka vidí jen žádosti své školky" "Eva" $RA reditelka@test.cz "${ZSEED//\$ME/$RA} select string_agg(jmeno, ',') from zadosti;"
t "ředitelka B nezmění výsledek žádosti A" 0 $RB reditelka.b@test.cz "${ZSEED//\$ME/$RB} with u as (update zadosti set vysledek='prijato' where id='99999999-0000-4000-8000-0000000000c1' returning 1) select count(*) from u;"
t "výsledek nejde změnit před rozhodnutím" ERR $RA reditelka@test.cz "${ZSEED//\$ME/$RA} update zadosti set vysledek='prijato' where id='99999999-0000-4000-8000-0000000000c1';"
t "ředitelka nemění jiné údaje žádosti (RČ)" ERR $RA reditelka@test.cz "${ZSEED//\$ME/$RA} update zadosti set rodne_cislo='x' where id='99999999-0000-4000-8000-0000000000c1';"
t "ředitelka žádost nesmaže" ERR $RA reditelka@test.cz "${ZSEED//\$ME/$RA} delete from zadosti where id='99999999-0000-4000-8000-0000000000c1';"
t "rozhodnutí podle kritérií" 1 $RA reditelka@test.cz "${ZSEED//\$ME/$RA} select rozhodni_zapis(2027, '[{\"id\":\"99999999-0000-4000-8000-0000000000c1\",\"vysledek\":\"prijato\",\"poradi\":1},{\"id\":\"99999999-0000-4000-8000-0000000000c2\",\"vysledek\":\"prijato\",\"poradi\":1}]');"
t "učitelka nerozhoduje" ERR $UA ucitelka@test.cz "select rozhodni_zapis(2027, '[]');"
t "odeslání před zveřejněním neprojde" ERR $RA reditelka@test.cz "${ZSEED//\$ME/$RA} select rozhodni_zapis(2027, '[]'); select zapis_krok(2027, 'odeslano');"
t "převod před odesláním neprojde" ERR $RA reditelka@test.cz "${ZSEED//\$ME/$RA} select rozhodni_zapis(2027, '[]'); select zapis_krok(2027, 'zverejneno'); select preved_prijate(2027);"
t "po odeslání výsledek nejde změnit" ERR $RA reditelka@test.cz "${ZSEED//\$ME/$RA} select rozhodni_zapis(2027, '[{\"id\":\"99999999-0000-4000-8000-0000000000c1\",\"vysledek\":\"prijato\",\"poradi\":1}]') \\g /dev/null
select zapis_krok(2027, 'zverejneno') \\g /dev/null
select zapis_krok(2027, 'odeslano') \\g /dev/null
update zadosti set vysledek='neprijato' where id='99999999-0000-4000-8000-0000000000c1';"
t "převod přijatých do kartotéky (a podruhé nic nezdvojí)" "1|0|1" $RA reditelka@test.cz "${ZSEED//\$ME/$RA} select rozhodni_zapis(2027, '[{\"id\":\"99999999-0000-4000-8000-0000000000c1\",\"vysledek\":\"prijato\",\"poradi\":1}]') \\g /dev/null
select zapis_krok(2027, 'zverejneno') \\g /dev/null
select zapis_krok(2027, 'odeslano') \\g /dev/null
select set_config('t.v', preved_prijate(2027) || '|' || preved_prijate(2027), true) \\g /dev/null
reset role;
select current_setting('t.v') || '|' || count(*) from deti where jmeno='Eva' and zahajeni = '2027-09-01' and rodne_cislo = '220101/0001';"
t "stav zápisu jiné školky není vidět" 0 $RB reditelka.b@test.cz "${ZSEED//\$ME/$RA} select rozhodni_zapis(2027, '[]') \\g /dev/null
select set_config('request.jwt.claim.sub','$RB',true) \\g /dev/null
select count(*) from zapis_rocnik where skola_id='$A';"
t "stav zápisu nejde měnit přímo" ERR $RA reditelka@test.cz "insert into zapis_rocnik (skola_id, rok, odeslano) values ('$A', 2027, current_date);"
echo "== dokumenty: vedení upravuje a schvaluje, archiv verzí"
DINS() { echo "with x as (insert into dokumenty (skola_id, klic, html) values ('$A', '$1', '<p>Text</p>') returning 1) select count(*) from x;"; }
SCH="select schval_dokument('skolni-rad', null, null, '<h1>Školní řád</h1><p>Znění</p>');"
t "ředitelka uloží rozpracovaný dokument" 1 $RA reditelka@test.cz "$(DINS skolni-rad)"
t "zástupkyně uloží dokument" 1 $ZA zastupce@test.cz "$(DINS svp)"
t "učitelka dokument neuloží" ERR $UA ucitelka@test.cz "$(DINS skolni-rad)"
t "hospodářka dokument neuloží" ERR $HA hospodarka@test.cz "$(DINS skolni-rad)"
t "rodič dokument neuloží" ERR $RODA "" "$(DINS skolni-rad)"
t "ředitelka A neuloží dokument do školky B" ERR $RA reditelka@test.cz "insert into dokumenty (skola_id, klic, html) values ('$B', 'svp', 'x');"
t "schválení přímo (bez funkce) neprojde" ERR $RA reditelka@test.cz "insert into dokumenty (skola_id, klic, schvaleno, verze) values ('$A', 'gdpr', current_date, 5);"
t "verzi nejde přepsat přímo" ERR $RA reditelka@test.cz "$(DINS skolni-rad) update dokumenty set verze = 9 where klic='skolni-rad';"
t "schválení: verze 1, pak 2" "1|2" $RA reditelka@test.cz "select schval_dokument('skolni-rad', null, null, 'v1') || '|' || schval_dokument('skolni-rad', '<p>nové</p>', null, 'v2');"
t "archiv drží obě schválená znění" "v1,v2" $RA reditelka@test.cz "select schval_dokument('skolni-rad', null, null, 'v1') \\g /dev/null
select schval_dokument('skolni-rad', null, null, 'v2') \\g /dev/null
select string_agg(html, ',' order by verze) from dokumenty_verze where klic='skolni-rad';"
t "úprava po schválení se označí" t $RA reditelka@test.cz "$SCH update dokumenty set html='<p>změna</p>' where klic='skolni-rad'; select upraveno_po_schvaleni from dokumenty where klic='skolni-rad';"
t "nové schválení příznak úpravy zruší" f $RA reditelka@test.cz "$SCH update dokumenty set html='<p>změna</p>' where klic='skolni-rad'; $SCH select upraveno_po_schvaleni from dokumenty where klic='skolni-rad';"
t "učitelka neschvaluje" ERR $UA ucitelka@test.cz "$SCH"
t "hospodářka neschvaluje" ERR $HA hospodarka@test.cz "$SCH"
t "prázdné znění neschválí" ERR $RA reditelka@test.cz "select schval_dokument('svp', null, null, '  ');"
t "dokument nejde smazat" ERR $RA reditelka@test.cz "$(DINS svp) delete from dokumenty where klic='svp';"
t "archiv verzí nejde měnit" ERR $RA reditelka@test.cz "$SCH update dokumenty_verze set html='podvrh';"
t "učitelka dokumenty nevidí" 0 $UA ucitelka@test.cz "reset role; insert into dokumenty (skola_id, klic, html) values ('$A','svp','x'); set local role authenticated; select set_config('request.jwt.claim.sub','$UA',true) \\g /dev/null
select count(*) from dokumenty;"
t "ředitelka B nevidí dokumenty A" 0 $RB reditelka.b@test.cz "reset role; insert into dokumenty (skola_id, klic, html) values ('$A','svp','x'); set local role authenticated; select set_config('request.jwt.claim.sub','$RB',true) \\g /dev/null
select count(*) from dokumenty;"
echo "== platby: předpisy, párování a kniha jen funkcemi"
FSET="select uloz_financni_nastaveni('19-2000145399/0800', 900, 48, 52, 15) \\g /dev/null
"
# Ema: 3 obědy v září, z toho jeden omluvený včas (nepočítá se) a jeden pozdě (počítá se)
DOCH="reset role; insert into dochazka (dite_id, den, stav, strava_prihlasena, omluva_zadana) values
 ('$EMA', '2026-09-01', 'pritomen', true, null),
 ('$EMA', '2026-09-02', 'omluven', true, '2026-09-01 07:00+02'),
 ('$EMA', '2026-09-03', 'omluven', true, '2026-09-03 07:30+02'),
 ('$EMA', '2026-09-04', 'omluven', false, null);
set local role authenticated; select set_config('request.jwt.claim.sub','\$ME',true) \\g /dev/null
"
t "hospodářka ceny nenastaví" ERR $HA hospodarka@test.cz "$FSET"
t "učitelka ceny nenastaví" ERR $UA ucitelka@test.cz "$FSET"
t "přímá změna nastavení neprojde" ERR $RA reditelka@test.cz "update financni_nastaveni set skolkovne = 1;"
t "ředitelka vystaví předpisy za září (3 děti)" 3 $RA reditelka@test.cz "$FSET select vystav_predpisy('2026-09');"
t "podruhé nic nezdvojí" 0 $RA reditelka@test.cz "$FSET select vystav_predpisy('2026-09') \\g /dev/null
select vystav_predpisy('2026-09');"
t "stravné předem: provozní dny září (21 × 48 Kč, bez svátku 28. 9.)" "21|1008.00|1908.00" $RA reditelka@test.cz "${DOCH//\$ME/$RA} $FSET select vystav_predpisy('2026-09') \\g /dev/null
select q.mnozstvi || '|' || q.castka || '|' || p.castka from predpisy p join predpis_polozky q on q.predpis_id = p.id and q.druh = 'stravne' where p.dite_id = '$EMA';"
t "podvojnost: pohyby dítěte = předpis" "1908.00|1908.00" $RA reditelka@test.cz "${DOCH//\$ME/$RA} $FSET select vystav_predpisy('2026-09') \\g /dev/null
select (select sum(castka) from ucetni_pohyby where md = 'dite:$EMA') || '|' || (select castka from predpisy where dite_id = '$EMA');"
t "hospodářka předpisy vystaví" 3 $HA hospodarka@test.cz "reset role; set local role authenticated; select set_config('request.jwt.claim.sub','$RA',true) \\g /dev/null
$FSET select set_config('request.jwt.claim.sub','$HA',true) \\g /dev/null
select vystav_predpisy('2026-09');"
t "běžící měsíc jde vystavit předem" 1 $RA reditelka@test.cz "$FSET select (vystav_predpisy(to_char(current_date, 'YYYY-MM')) > 0)::int;"
t "příští měsíc jde vystavit předem" 1 $RA reditelka@test.cz "$FSET select (vystav_predpisy(to_char(current_date + interval '1 month', 'YYYY-MM')) > 0)::int;"
t "za dva měsíce dopředu nejde" ERR $RA reditelka@test.cz "$FSET select vystav_predpisy(to_char(current_date + interval '2 month', 'YYYY-MM'));"
t "učitelka předpisy nevystaví" ERR $UA ucitelka@test.cz "select vystav_predpisy('2026-09');"
t "rodič předpisy nevystaví" ERR $RODA "" "select vystav_predpisy('2026-09');"
t "přímý zápis do účetní knihy neprojde" ERR $HA hospodarka@test.cz "insert into ucetni_pohyby (skola_id, datum, md, dal, castka, popis) values ('$A', current_date, 'banka', 'dite:$EMA', 1000, 'podvrh');"
t "přímá změna předpisu neprojde" ERR $RA reditelka@test.cz "$FSET select vystav_predpisy('2026-09') \\g /dev/null
update predpisy set stav = 'zaplaceno';"
t "přímá platba neprojde" ERR $HA hospodarka@test.cz "insert into platby (skola_id, datum, castka) values ('$A', current_date, 100);"
PL() { echo "select zpracuj_platby('[{\"datum\":\"2026-10-05\",\"castka\":$1,\"vs\":\"$2\",\"protiucet\":\"123/0800\",\"nazev\":\"RODIC\",\"doklad\":\"$3\"}]')"; }
t "platba přesně: konto 0, předpis zaplacen" "1|0.00|zaplaceno" $RA reditelka@test.cz "${DOCH//\$ME/$RA} $FSET select vystav_predpisy('2026-09') \\g /dev/null
select set_config('t.r', ($(PL 1908 260001 D1))->>'presne', true) \\g /dev/null
select current_setting('t.r') || '|' || (select saldo from konta where dite_id='$EMA') || '|' || (select stav from predpisy where dite_id='$EMA');"
t "stejný doklad podruhé se přeskočí" 1 $RA reditelka@test.cz "$FSET select vystav_predpisy('2026-09') \\g /dev/null
$(PL 900 260001 D1) \\g /dev/null
select ($(PL 900 260001 D1))->>'duplicita';"
t "přeplatek zůstane na kontě" "1|100.00" $RA reditelka@test.cz "$FSET select vystav_predpisy('2026-09') \\g /dev/null
select set_config('t.r', (zpracuj_platby(jsonb_build_array(jsonb_build_object('datum', '2026-10-05', 'castka', (select castka + 100 from predpisy where dite_id = '$TOB'), 'vs', '260003', 'protiucet', '123/0800', 'nazev', 'RODIC', 'doklad', 'D2'))))->>'preplatek', true) \\g /dev/null
select current_setting('t.r') || '|' || (select saldo from konta where dite_id='$TOB');"
t "neznámý VS → nespárovaná, ruční spárování" "1|nedoplatek|true" $HA hospodarka@test.cz "reset role; set local role authenticated; select set_config('request.jwt.claim.sub','$RA',true) \\g /dev/null
$FSET select vystav_predpisy('2026-09') \\g /dev/null
select set_config('request.jwt.claim.sub','$HA',true) \\g /dev/null
select set_config('t.r', ($(PL 500 999999 D3))->>'nesparovano', true) \\g /dev/null
select set_config('t.s', (sparuj_platbu((select id from platby where doklad='D3'), '$OLI'))->>'vysledek', true) \\g /dev/null
select current_setting('t.r') || '|' || current_setting('t.s') || '|' || (select vyreseno from nesparovane_platby);"
t "ředitelka B nespáruje platbu školky A" ERR $RB reditelka.b@test.cz "reset role; set local role authenticated; select set_config('request.jwt.claim.sub','$RA',true) \\g /dev/null
$(PL 500 999999 D4) \\g /dev/null
select set_config('request.jwt.claim.sub','$RB',true) \\g /dev/null
select sparuj_platbu((select platba_id from nesparovane_platby limit 1), '$ADAM');"
t "ředitelka B nevidí platby ani knihu školky A" "0|0" $RB reditelka.b@test.cz "reset role; set local role authenticated; select set_config('request.jwt.claim.sub','$RA',true) \\g /dev/null
$FSET select vystav_predpisy('2026-09') \\g /dev/null
$(PL 996 260001 D5) \\g /dev/null
select set_config('request.jwt.claim.sub','$RB',true) \\g /dev/null
select (select count(*) from platby) || '|' || (select count(*) from ucetni_pohyby where md like 'dite:%' or dal like 'dite:%');"
t "učitelka nezpracuje výpis" ERR $UA ucitelka@test.cz "$(PL 100 260001 D6);"
t "rodič vidí jen předpis svého dítěte" "1" $RODA "" "reset role; set local role authenticated; select set_config('request.jwt.claim.sub','$RA',true) \\g /dev/null
$FSET select vystav_predpisy('2026-09') \\g /dev/null
select set_config('request.jwt.claim.sub','$RODA',true) \\g /dev/null
select count(*) from predpisy;"
t "upomínka jen po splatnosti" 1 $HA hospodarka@test.cz "reset role; set local role authenticated; select set_config('request.jwt.claim.sub','$RA',true) \\g /dev/null
$FSET select vystav_predpisy('2026-08') \\g /dev/null
reset role; update predpisy set splatnost = current_date - 1; set local role authenticated;
select set_config('request.jwt.claim.sub','$HA',true) \\g /dev/null
select zapis_upominku('$EMA');"
echo "== nastavení školky: údaje mění vedení, stav a tarif jen správce"
SUP() { echo "with u as (update skoly set $1 where id = '$A' returning 1) select count(*) from u;"; }
t "ředitelka uloží adresu a IČO" 1 $RA reditelka@test.cz "$(SUP "adresa = 'Ulice 1, Praha', ico = '12345678'")"
t "zástupkyně uloží úřední hodiny" 1 $ZA zastupce@test.cz "$(SUP "uredni_hodiny = 'Po 8–10'")"
t "hospodářka údaje nezmění" 0 $HA hospodarka@test.cz "$(SUP "adresa = 'x'")"
t "učitelka údaje nezmění" 0 $UA ucitelka@test.cz "$(SUP "adresa = 'x'")"
t "rodič údaje nezmění" 0 $RODA "" "$(SUP "adresa = 'x'")"
t "ředitelka B nezmění školku A" 0 $RB reditelka.b@test.cz "$(SUP "adresa = 'x'")"
t "ředitelka nezmění tarif" ERR $RA reditelka@test.cz "$(SUP "tarif = 'zdarma'")"
t "ředitelka nezmění stav školky" ERR $RA reditelka@test.cz "$(SUP "stav = 'aktivni', predplatne_do = '2099-01-01'")"
t "prázdný název neprojde" ERR $RA reditelka@test.cz "$(SUP "nazev = '  '")"
t "neplatný druh provozu neprojde" ERR $RA reditelka@test.cz "$(SUP "druh_provozu = 'X'")"
t "omluvenky a VS přes nastavení plateb" "2|10:00:00|prefix_poradi|77|8" $RA reditelka@test.cz "select uloz_financni_nastaveni('19-2000145399/0800', 900, 48, 52, 15, 2, '10:00', 'prefix_poradi', '77', 8) \\g /dev/null
select omluva_dni_predem || '|' || omluva_do || '|' || vs_schema || '|' || vs_prefix || '|' || vs_delka from financni_nastaveni where skola_id = '$A';"
t "nastavení plateb bez nepovinných parametrů nic nepřepíše" "2|prefix_poradi" $RA reditelka@test.cz "select uloz_financni_nastaveni('19-2000145399/0800', 900, 48, 52, 15, 2, '10:00', 'prefix_poradi', '77', 8) \\g /dev/null
select uloz_financni_nastaveni('19-2000145399/0800', 950, 48, 52, 15) \\g /dev/null
select omluva_dni_predem || '|' || vs_schema from financni_nastaveni where skola_id = '$A';"
t "neplatné VS schéma neprojde" ERR $RA reditelka@test.cz "select uloz_financni_nastaveni('1/0800', 900, 48, 52, 15, 1, '08:00', 'nahodne');"
echo "== archiv: skartační plán a záznam změn jen pro vedení"
t "ředitelka uloží skartační plán" 1 $RA reditelka@test.cz "with u as (update skoly set skartacni_plan = '{\"Třídní knihy\": 12}' where id = '$A' returning 1) select count(*) from u;"
t "hospodářka plán nezmění" 0 $HA hospodarka@test.cz "with u as (update skoly set skartacni_plan = '{}' where id = '$A' returning 1) select count(*) from u;"
t "plán musí být objekt" ERR $RA reditelka@test.cz "update skoly set skartacni_plan = '[1,2]' where id = '$A';"
t "záznam změn: úprava karty dítěte se jménem ředitelky" "Ivana Pokorná|deti|UPDATE|$EMA" $RA reditelka@test.cz "update deti set alergie = 'pyl' where id = '$EMA';
select kdo || '|' || tabulka || '|' || akce || '|' || dite from archiv_zmen(5) limit 1;"
t "záznam změn: žádost o přijetí s reg. číslem" "zadosti|Z001" $RA reditelka@test.cz "select reg_cislo from nova_zadost(2027, 'Eva', 'Nová', '225707/0002', '2022-07-07', 'F', true, false, '') \\g /dev/null
select tabulka || '|' || detail from archiv_zmen(5) limit 1;"
t "učitelka archiv nevidí" ERR $UA ucitelka@test.cz "select count(*) from archiv_zmen(5);"
t "hospodářka archiv nevidí" ERR $HA hospodarka@test.cz "select count(*) from archiv_zmen(5);"
t "ředitelka B nevidí změny školky A" 0 $RB reditelka.b@test.cz "reset role; set local role authenticated; select set_config('request.jwt.claim.sub','$RA',true) \\g /dev/null
update deti set alergie = 'x' where id = '$EMA';
select set_config('request.jwt.claim.sub','$RB',true) \\g /dev/null
select count(*) from archiv_zmen(1000) where dite = '$EMA';"
echo "== akce a schůzky: zakládá škola, odpovídá rodič za své dítě"
AKS="reset role; insert into akce (id, skola_id, trida_id, den, nazev) values ('99999999-0000-4000-8000-0000000000e1', '$A', '$SLUN', current_date + 7, 'Výlet'), ('99999999-0000-4000-8000-0000000000e2', '$A', '$BER', current_date + 7, 'Berušky divadlo'), ('99999999-0000-4000-8000-0000000000e3', '$A', '$SLUN', current_date - 1, 'Včera'); set local role authenticated; select set_config('request.jwt.claim.sub','\$ME',true) \\g /dev/null
"
t "učitelka založí akci své třídy" 1 $UA ucitelka@test.cz "with x as (insert into akce (skola_id, trida_id, den, nazev, druh) values ('$A', '$SLUN', current_date + 5, 'Divadlo', 'akce') returning 1) select count(*) from x;"
t "učitelka založí třídní schůzku" 1 $UA ucitelka@test.cz "with x as (insert into akce (skola_id, trida_id, den, nazev, druh) values ('$A', '$SLUN', current_date + 5, 'Třídní schůzka', 'schuzka') returning 1) select count(*) from x;"
t "učitelka nezaloží akci cizí třídy" ERR $UA ucitelka@test.cz "insert into akce (skola_id, trida_id, den, nazev) values ('$A', '$BER', current_date + 5, 'x');"
t "učitelka nezaloží akci celé školky" ERR $UA ucitelka@test.cz "insert into akce (skola_id, trida_id, den, nazev) values ('$A', null, current_date + 5, 'x');"
t "ředitelka založí akci celé školky" 1 $RA reditelka@test.cz "with x as (insert into akce (skola_id, trida_id, den, nazev) values ('$A', null, current_date + 5, 'Besídka') returning 1) select count(*) from x;"
t "rodič akci nezaloží" ERR $RODA "" "insert into akce (skola_id, trida_id, den, nazev) values ('$A', '$SLUN', current_date + 5, 'x');"
t "neplatný druh neprojde" ERR $UA ucitelka@test.cz "insert into akce (skola_id, trida_id, den, nazev, druh) values ('$A', '$SLUN', current_date + 5, 'x', 'mejdan');"
t "rodič vidí akci třídy svého dítěte, ne cizí" "1|0" $RODA "" "${AKS//\$ME/$RODA} select (select count(*) from akce where nazev = 'Výlet') || '|' || (select count(*) from akce where nazev = 'Berušky divadlo');"
t "rodič odpoví za své dítě" ano $RODA "" "${AKS//\$ME/$RODA} select odpovez_na_akci('99999999-0000-4000-8000-0000000000e1', '$EMA', 'ano');"
t "odpověď jde změnit" "ne|1" $RODA "" "${AKS//\$ME/$RODA} select odpovez_na_akci('99999999-0000-4000-8000-0000000000e1', '$EMA', 'ano') \\g /dev/null
select odpovez_na_akci('99999999-0000-4000-8000-0000000000e1', '$EMA', 'ne') || '|' || (select count(*) from akce_odpovedi);"
t "rodič neodpoví za cizí dítě" ERR $RODA "" "${AKS//\$ME/$RODA} select odpovez_na_akci('99999999-0000-4000-8000-0000000000e1', '$TOB', 'ano');"
t "rodič neodpoví na akci cizí třídy" ERR $RODA "" "${AKS//\$ME/$RODA} select odpovez_na_akci('99999999-0000-4000-8000-0000000000e2', '$EMA', 'ano');"
t "na proběhlou akci se neodpovídá" ERR $RODA "" "${AKS//\$ME/$RODA} select odpovez_na_akci('99999999-0000-4000-8000-0000000000e3', '$EMA', 'ano');"
t "učitelka za rodiče neodpoví" ERR $UA ucitelka@test.cz "${AKS//\$ME/$UA} select odpovez_na_akci('99999999-0000-4000-8000-0000000000e1', '$EMA', 'ano');"
t "odpověď nejde vložit přímo" ERR $RODA "" "${AKS//\$ME/$RODA} insert into akce_odpovedi (akce_id, dite_id, odpoved) values ('99999999-0000-4000-8000-0000000000e1', '$EMA', 'ano');"
t "učitelka vidí odpovědi" 1 $UA ucitelka@test.cz "${AKS//\$ME/$RODA} select odpovez_na_akci('99999999-0000-4000-8000-0000000000e1', '$EMA', 'ano') \\g /dev/null
select set_config('request.jwt.claim.sub','$UA',true) \\g /dev/null
select count(*) from akce_odpovedi;"
t "jiný rodič cizí odpověď nevidí" 0 $ROD2A "" "${AKS//\$ME/$RODA} select odpovez_na_akci('99999999-0000-4000-8000-0000000000e1', '$EMA', 'ano') \\g /dev/null
select set_config('request.jwt.claim.sub','$ROD2A',true) \\g /dev/null
select count(*) from akce_odpovedi;"
t "ředitelka B nevidí akce školky A" 0 $RB reditelka.b@test.cz "${AKS//\$ME/$RB} select count(*) from akce where skola_id = '$A';"
echo "== fotky: alba a soubory jen třídě, rodičům až po zveřejnění"
F1=99999999-0000-4000-8000-0000000000f1; F2=99999999-0000-4000-8000-0000000000f2
FSEED="reset role; insert into alba (id, skola_id, trida_id, den, nazev, fotky) values ('$F1', '$A', '$SLUN', current_date, 'Podzim', '{}'), ('$F2', '$A', '$BER', current_date, 'Berušky', '{}');
insert into storage.objects (bucket_id, name) values ('fotky', '$A/$SLUN/$F1/a.jpg');
set local role authenticated; select set_config('request.jwt.claim.sub','\$ME',true) \\g /dev/null
"
FPUB="reset role; update alba set zverejneno = now() where id = '$F1'; set local role authenticated; select set_config('request.jwt.claim.sub','\$ME',true) \\g /dev/null
"
FINS() { echo "with x as (insert into storage.objects (bucket_id, name) values ('fotky', '$1') returning 1) select count(*) from x;"; }
t "učitelka nahraje fotku do alba své třídy" 1 $UA ucitelka@test.cz "${FSEED//\$ME/$UA} $(FINS $A/$SLUN/$F1/b.jpg)"
t "učitelka nenahraje do alba cizí třídy" ERR $UA ucitelka@test.cz "${FSEED//\$ME/$UA} $(FINS $A/$BER/$F2/b.jpg)"
t "podvržená cesta (cizí třída v cestě) neprojde" ERR $UA ucitelka@test.cz "${FSEED//\$ME/$UA} $(FINS $A/$BER/$F1/b.jpg)"
t "rodič fotku nenahraje" ERR $RODA "" "${FSEED//\$ME/$RODA} ${FPUB//\$ME/$RODA} $(FINS $A/$SLUN/$F1/c.jpg)"
t "hospodářka fotku nenahraje" ERR $HA hospodarka@test.cz "${FSEED//\$ME/$HA} $(FINS $A/$SLUN/$F1/c.jpg)"
t "rodič nezveřejněné album nevidí (ani fotku)" "0|0" $RODA "" "${FSEED//\$ME/$RODA} select (select count(*) from alba where id = '$F1') || '|' || (select count(*) from storage.objects where bucket_id = 'fotky');"
t "rodič po zveřejnění album i fotku vidí" "1|1" $RODA "" "${FSEED//\$ME/$RODA} ${FPUB//\$ME/$RODA} select (select count(*) from alba where id = '$F1') || '|' || (select count(*) from storage.objects where bucket_id = 'fotky');"
t "rodič nevidí album cizí třídy" 0 $RODA "" "${FSEED//\$ME/$RODA} reset role; update alba set zverejneno = now(); set local role authenticated; select set_config('request.jwt.claim.sub','$RODA',true) \\g /dev/null
select count(*) from alba where id = '$F2';"
t "rodič z jiné školky fotku nevidí" 0 $RODB "" "${FSEED//\$ME/$RODB} ${FPUB//\$ME/$RODB} select count(*) from storage.objects where bucket_id = 'fotky';"
t "ředitelka B fotku nevidí" 0 $RB reditelka.b@test.cz "${FSEED//\$ME/$RB} select count(*) from storage.objects where bucket_id = 'fotky';"
t "učitelka smaže fotku své třídy" 1 $UA ucitelka@test.cz "${FSEED//\$ME/$UA} with x as (delete from storage.objects where name = '$A/$SLUN/$F1/a.jpg' returning 1) select count(*) from x;"
t "rodič fotku nesmaže" 0 $RODA "" "${FSEED//\$ME/$RODA} ${FPUB//\$ME/$RODA} with x as (delete from storage.objects where bucket_id = 'fotky' returning 1) select count(*) from x;"
t "učitelka nezveřejní album cizí třídy" 0 $UA ucitelka@test.cz "${FSEED//\$ME/$UA} with x as (update alba set zverejneno = now() where id = '$F2' returning 1) select count(*) from x;"
t "učitelka zveřejní album své třídy" 1 $UA ucitelka@test.cz "${FSEED//\$ME/$UA} with x as (update alba set zverejneno = now() where id = '$F1' returning 1) select count(*) from x;"
t "rodič album nezaloží" ERR $RODA "" "insert into alba (skola_id, trida_id, den, nazev) values ('$A', '$SLUN', current_date, 'x');"
echo "== logo školky: jen malý obrázek, mění vedení"
LOGO="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
t "ředitelka nahraje logo (PNG)" 1 $RA reditelka@test.cz "$(SUP "logo = '$LOGO'")"
t "logo odebrat jde" 1 $RA reditelka@test.cz "$(SUP "logo = null")"
t "SVG jako logo neprojde" ERR $RA reditelka@test.cz "$(SUP "logo = 'data:image/svg+xml;base64,PHN2Zz48L3N2Zz4='")"
t "odkaz ven jako logo neprojde" ERR $RA reditelka@test.cz "$(SUP "logo = 'https://example.com/logo.png'")"
t "logo s vloženým HTML neprojde" ERR $RA reditelka@test.cz "$(SUP "logo = 'data:image/png;base64,AA\"><script>x</script>'")"
t "příliš velké logo neprojde" ERR $RA reditelka@test.cz "$(SUP "logo = 'data:image/png;base64,' || repeat('A', 200000)")"
t "učitelka logo nezmění" 0 $UA ucitelka@test.cz "$(SUP "logo = '$LOGO'")"
t "kuchařka logo vidí (hlavička jídelníčku)" 1 $KA kucharka@test.cz "reset role; update skoly set logo = '$LOGO' where id = '$A'; set local role authenticated; select count(*) from skoly where logo is not null;"
echo "== platby z banky: token vidí jen server, napojení jen vedení, QR jen rodič svých dětí"
TOK="DOBRYtokenAbCdEfGhIjKlMnOpQrStUvWx0123456789abcdefghij"
BSEED="reset role; insert into banka_napojeni (skola_id, token) values ('$A', '$TOK'), ('$B', '${TOK}B') on conflict do nothing; set local role authenticated;"
t "ředitelka napojí banku" "" $RA reditelka@test.cz "select uloz_napojeni_banky('$TOK');"
t "zástupkyně napojí banku" "" $ZA zastupce@test.cz "select uloz_napojeni_banky('$TOK');"
t "hospodářka banku nenapojí" ERR $HA hospodarka@test.cz "select uloz_napojeni_banky('$TOK');"
t "učitelka banku nenapojí" ERR $UA ucitelka@test.cz "select uloz_napojeni_banky('$TOK');"
t "rodič banku nenapojí" ERR $RODA "" "select uloz_napojeni_banky('$TOK');"
t "token s jinými znaky neprojde" ERR $RA reditelka@test.cz "select uloz_napojeni_banky('abc;drop table platby;--xxxxxxxxxxxx');"
t "ředitelka token z tabulky nepřečte" ERR $RA reditelka@test.cz "$BSEED select token from banka_napojeni;"
t "hospodářka token z tabulky nepřečte" ERR $HA hospodarka@test.cz "$BSEED select count(*) from banka_napojeni;"
t "stav napojení: jen poslední 4 znaky" "ghij|false" $HA hospodarka@test.cz "$BSEED select (stav_napojeni_banky()->>'token_konec') || '|' || (strpos(stav_napojeni_banky()::text, '$TOK') > 0)::text;"
t "stav napojení: učitelka nic" "-" $UA ucitelka@test.cz "$BSEED select coalesce(stav_napojeni_banky()::text, '-');"
t "ředitelka B nevidí napojení školky A" "hijB" $RB reditelka.b@test.cz "$BSEED select right(stav_napojeni_banky()->>'token_konec', 5);"
t "token z aplikace nejde ani přes banka_ke_stazeni" ERR $RA reditelka@test.cz "$BSEED select token from banka_ke_stazeni(null);"
t "platby za školku nejde zapsat přímo (fin_zpracuj_platby)" ERR $HA hospodarka@test.cz "select fin_zpracuj_platby('$A', '[]', 'api');"
t "výsledek banky nejde podvrhnout (banka_zpracuj)" ERR $RA reditelka@test.cz "select banka_zpracuj('$A', '[]');"
t "muze_stahnout: hospodářka dostane jen svou školku" "$A" $HA hospodarka@test.cz "select muze_stahnout_z_banky();"
t "muze_stahnout: rodič nic" "-" $RODA "" "select coalesce(muze_stahnout_z_banky()::text, '-');"
anon "anon nevolá moje_platby" "select * from moje_platby();"
anon "anon nevolá stav_napojeni_banky" "select stav_napojeni_banky();"
t "moje_platby: rodič Emy vidí jen Emu" "1|$EMA" $RODA "" "select count(*) || '|' || min(dite_id::text) from moje_platby();"
t "moje_platby: ředitelka nic (je pro rodiče)" 0 $RA reditelka@test.cz "select count(*) from moje_platby();"
t "moje_platby: rodič B nevidí děti školky A" 0 $RODB "" "select count(*) from moje_platby() where dite_id in ('$EMA', '$OLI');"
t "VS ve zprávě: krátké VS (1–3 číslice) se nepáruje" "1" $HA hospodarka@test.cz "reset role; update deti set variabilni_symbol = '7' where id = '$EMA'; set local role authenticated; select (zpracuj_platby('[{\"datum\":\"2026-10-01\",\"castka\":100,\"vs\":\"\",\"zprava\":\"skolkovne za 7 mesicu\",\"doklad\":\"t-kratky\"}]')->>'nesparovano');"
echo "== provozní kalendář a platby předem"
t "státní svátky 2027: Velikonoce 26. 3. a 29. 3." "2027-03-26|2027-03-29" $RA reditelka@test.cz "select string_agg(den::text, '|' order by den) from statni_svatky(2027) where nazev like 'Vel%';"
t "28. 10. je zavřeno, 27. 10. otevřeno" "f|t" $RA reditelka@test.cz "select je_provozni_den('$A', '2026-10-28')::text::char || '|' || je_provozni_den('$A', '2026-10-27')::text::char;"
t "ředitelka otevře svátek" 1 $RA reditelka@test.cz "select nastav_kalendar('2026-10-28', '2026-10-28', 'otevreno', 'Provoz zajištěn');"
t "zástupkyně zavře prázdniny (jen 5 všedních dní, víkend je zavřený tak jako tak)" 5 $ZA zastupce@test.cz "select nastav_kalendar('2026-12-28', '2027-01-03', 'zavreno', 'Vánoce');"
t "hospodářka kalendář nemění" ERR $HA hospodarka@test.cz "select nastav_kalendar('2026-10-28', '2026-10-28', 'otevreno');"
t "učitelka kalendář nemění" ERR $UA ucitelka@test.cz "select nastav_kalendar('2026-10-28', '2026-10-28', 'otevreno');"
t "rodič kalendář nemění" ERR $RODA "" "select nastav_kalendar('2026-10-28', '2026-10-28', 'otevreno');"
t "přímý zápis do kalendáře neprojde" ERR $RA reditelka@test.cz "insert into kalendar_skoly (skola_id, den, otevreno) values ('$A', '2026-10-28', true);"
t "ředitelka B kalendář školky A nevidí" 0 $RB reditelka.b@test.cz "reset role; insert into kalendar_skoly (skola_id, den, otevreno) values ('$A', '2026-10-28', true); set local role authenticated; select count(*) from kalendar_skoly;"
KSEED="reset role; insert into kalendar_skoly (skola_id, den, otevreno, poznamka) values ('$A', '2026-10-28', true, 'otevřeno'), ('$A', '2026-10-26', false, 'volno'); set local role authenticated;"
t "otevřený svátek se počítá, zavřený den ne (říjen 21 → 21)" "21" $HA hospodarka@test.cz "$KSEED select vystav_predpisy('2026-10') \\g /dev/null
select q.mnozstvi from predpis_polozky q join predpisy p on p.id = q.predpis_id where p.dite_id = '$EMA' and p.obdobi = '2026-10' and q.druh = 'stravne';"
VSEED="reset role; delete from dochazka where dite_id = '$EMA' and den between '2026-10-01' and '2026-10-31';
insert into dochazka (dite_id, den, stav, strava_prihlasena) values ('$EMA', '2026-10-20', 'omluven', false), ('$EMA', '2026-10-21', 'omluven', false), ('$EMA', '2026-10-22', 'omluven', true), ('$EMA', '2026-10-28', 'omluven', false);
set local role authenticated;"
t "odpočet v dalším předpisu: jen včas odhlášené provozní dny (2 × 48)" "2|-96.00|1764.00" $HA hospodarka@test.cz "$VSEED select vystav_predpisy('2026-10') \\g /dev/null
select vystav_predpisy('2026-11') \\g /dev/null
select q.mnozstvi || '|' || q.castka || '|' || p.castka from predpisy p join predpis_polozky q on q.predpis_id = p.id and q.druh = 'vratka' where p.dite_id = '$EMA' and p.obdobi = '2026-11';"
t "konto po dvou předpisech = součet předpisů (odpočet se nezapočte dvakrát)" "-3672.00|otevreno" $HA hospodarka@test.cz "$VSEED select vystav_predpisy('2026-10') \\g /dev/null
select vystav_predpisy('2026-11') \\g /dev/null
select (select saldo from konta where dite_id = '$EMA') || '|' || (select stav from predpisy where dite_id = '$EMA' and obdobi = '2026-11');"
t "bez předchozího placení předem se nic neodečítá" 0 $HA hospodarka@test.cz "$VSEED select vystav_predpisy('2026-11') \\g /dev/null
select count(*) from predpis_polozky q join predpisy p on p.id = q.predpis_id where p.dite_id = '$EMA' and q.druh = 'vratka';"
t "omluvenka na zavřený den (svátek) se nezapíše" "2027-10-27,2027-10-29" $RODA "" "select string_agg(den::text, ',' order by den) from omluv_dite('$EMA', '2027-10-27', '2027-10-29', 'nemoc');"
t "kuchyně: v zavřený den je odhlášeno všechno" "t" $KA kucharka@test.cz "select (sum(deti) = sum(odhlaseno))::text::char from obedy_den('2026-10-28');"
t "kuchyně: den provozu se svátkem" "false|Vznik Československa" $KA kucharka@test.cz "select (den_provozu('2026-10-28')->>'provozni') || '|' || (den_provozu('2026-10-28')->>'svatek');"
echo "---- $OK PASS, $KO FAIL"
[[ $KO == 0 ]]
