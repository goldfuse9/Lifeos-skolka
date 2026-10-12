from datetime import date, datetime, time
from decimal import Decimal as D

import pytest

from finance.gpc import parsuj, radek_075
from finance.model import Dite, DochazkaDen, Nastaveni, Platba, SchemaVS, StavPredpisu
from finance.penize import format_kc, kc, z_haleru
from finance.predpisy import kategorie_stravneho, omluveno_vcas, spocti_predpis
from finance.sluzby import Finance, ucet_ditete
from finance.spayd import iban_z_cz, qr_svg, spayd
from finance.uloziste import PametoveUloziste
from finance.vs import dalsi_vs, normalizuj, zkontroluj

S = "ms-slunicko"


def nastaveni(**kw):
    base = dict(skolka_id=S, nazev="MŠ Sluníčko", ucet="19-2000145399/0800", skolkovne="900",
                stravne={"3-6": "48", "7+": "52"}, omluva_dni_predem=1, omluva_do=time(8, 0), splatnost_den=15)
    base.update(kw)
    return Nastaveni(**base)


def svet():
    db = PametoveUloziste()
    db.uloz_nastaveni(nastaveni())
    ema = Dite("ema", "Ema", "Králová", date(2022, 3, 5), "260012")
    oli = Dite("oli", "Oliver", "Novák", date(2020, 11, 2), "260013", osvobozen_od_skolkovneho=True)
    for d in (ema, oli):
        db.uloz_dite(S, d)
    # říjen 2026: 22 pracovních dní, Ema 1 den omluvená včas, 1 den pozdě
    dny = [date(2026, 10, d) for d in range(1, 32) if date(2026, 10, d).weekday() < 5]
    doch = [DochazkaDen("ema", d) for d in dny] + [DochazkaDen("oli", d) for d in dny]
    doch[0].omluva_zadana = datetime(2026, 9, 30, 7, 30)    # 1. 10.: omluva den předem 7:30 → včas
    doch[1].omluva_zadana = datetime(2026, 10, 2, 6, 50)    # 2. 10.: omluva ráno týž den → pozdě, platí se
    db.pridej_dochazku(doch)
    return db, Finance(db, S), ema, oli


# ------------------------------------------------------------------ peníze
def test_float_je_zakazany():
    with pytest.raises(TypeError):
        kc(0.1)
    assert kc("1 234,5") == D("1234.50")
    assert z_haleru("000000045000") == D("450.00")
    assert format_kc(D("12345.5")) == "12 345,50 Kč"


# ---------------------------------------------------------------- předpisy
def test_kategorie_a_omluva():
    assert kategorie_stravneho(date(2020, 11, 2), date(2026, 10, 5)) == "3-6"   # do 31. 8. 2027 bude mít 6
    assert kategorie_stravneho(date(2020, 3, 2), date(2026, 10, 5)) == "7+"     # do 31. 8. 2027 bude mít 7
    n = nastaveni()
    assert omluveno_vcas(date(2026, 10, 2), datetime(2026, 10, 1, 8, 0), n)
    assert not omluveno_vcas(date(2026, 10, 2), datetime(2026, 10, 1, 8, 1), n)
    assert not omluveno_vcas(date(2026, 10, 2), None, n)


def test_predpis_skolkovne_a_stravne():
    db, f, ema, oli = svet()
    p = f.vystav_predpis(ema, "2026-10")
    assert [x.druh for x in p.polozky] == ["skolkovne", "stravne"]
    assert p.polozky[1].mnozstvi == 21                      # 22 dní − 1 včas omluvený
    assert p.castka == D("900.00") + 21 * D("48.00")       # 1 908 Kč
    assert p.splatnost == date(2026, 11, 15)
    po = f.vystav_predpis(oli, "2026-10")
    assert po.polozky[0].castka == D("0.00")               # osvobozen od školkovného
    assert po.castka == 22 * D("48.00")
    assert f.vystav_predpis(ema, "2026-10") is None        # podruhé se nevystaví
    assert f.saldo("ema") == D("-1908.00")


# ------------------------------------------------------------------- QR
def test_spayd_a_qr():
    db, f, ema, _ = svet()
    f.vystav_predpis(ema, "2026-10")
    s = spayd(db.nastaveni(S).ucet, f.k_uhrade("ema"), ema.vs, f.zprava_platby(ema, "2026-10"))
    assert s == "SPD*1.0*ACC:CZ6508000000192000145399*AM:1908.00*CC:CZK*MSG:SKOLKOVNE/STRAVNE RIJEN 2026 - EMA KRALOVA*X-VS:260012"
    assert qr_svg(s).startswith("<?xml") or "<svg" in qr_svg(s)
    with pytest.raises(ValueError):
        iban_z_cz("123456789/0800")                          # nesedí kontrolní součet


# ------------------------------------------------------------------ .gpc
def test_gpc_parser():
    radky = [
        "074" + "0000002000145399" + "MS SLUNICKO".ljust(20) + "011026" + "0" * 14 + "+" + "0" * 14 + "+" + "0" * 14 + "0" + "0" * 14 + "0" + "001" + "311026" + " " * 14,
        radek_075("2000145399", "0000001234567890", "1", 190800, "2", "0000260012", "0800", "KRALOVA JANA", date(2026, 11, 3)),
        radek_075("2000145399", "0000000987654321", "2", 50000, "1", "0", "0300", "NAKUP", date(2026, 11, 3)),
        "078" + "zprava pro prijemce".ljust(125),
    ]
    v = parsuj(("\r\n".join(radky)).encode("cp1250"))
    assert v.ucet == "2000145399" and v.datum == date(2026, 10, 31)
    assert len(v.transakce) == 2
    t = v.transakce[0]
    assert (t.castka, t.vs, t.protiucet, t.datum, t.prichozi) == (D("1908.00"), "260012", "1234567890/0800", date(2026, 11, 3), True)
    assert v.transakce[1].castka == D("-500.00") and not v.transakce[1].prichozi


# ---------------------------------------------------------------- párování
def test_parovani_presne_preplatek_nedoplatek_nesparovano():
    db, f, ema, oli = svet()
    f.vystav_predpis(ema, "2026-10")
    f.vystav_predpis(oli, "2026-10")
    # nedoplatek
    r = f.zpracuj_platbu(Platba("p1", date(2026, 11, 3), D("1000"), "0000260012", doklad="d1"))
    assert (r.vysledek, r.zbyva_doplatit) == ("nedoplatek", D("908.00"))
    assert db.predpis("ema", "2026-10").stav == StavPredpisu.CASTECNE
    # doplatek přesně
    r = f.zpracuj_platbu(Platba("p2", date(2026, 11, 4), D("908"), "260012", doklad="d2"))
    assert r.vysledek == "presne" and db.predpis("ema", "2026-10").stav == StavPredpisu.ZAPLACENO
    # přeplatek → kredit, který se odečte z dalšího předpisu
    r = f.zpracuj_platbu(Platba("p3", date(2026, 11, 4), D("1100"), "260013", doklad="d3"))
    assert (r.vysledek, r.preplatek) == ("preplatek", D("44.00"))
    assert f.saldo("oli") == D("44.00") and f.k_uhrade("oli") == D("0.00")
    # nespárovaná (rodič spletl VS)
    r = f.zpracuj_platbu(Platba("p4", date(2026, 11, 5), D("650"), "77001", doklad="d4"))
    assert r.vysledek == "nesparovano" and len(db.nesparovane(S)) == 1
    # duplicitní načtení téhož výpisu nic nezdvojí
    assert f.zpracuj_platbu(Platba("p1b", date(2026, 11, 3), D("1000"), "260012", doklad="d1")).vysledek == "duplicita"
    # ruční spárování hospodářkou
    r = f.sparuj_rucne("p4", "ema")
    assert r.vysledek == "preplatek" and f.saldo("ema") == D("650.00") and not db.nesparovane(S)
    # podvojnost: součet MD = součet Dal přes všechny účty
    md = sum((p.castka for p in db.vsechny_pohyby()), D("0"))
    assert md == sum((p.castka for p in db.vsechny_pohyby()), D("0"))
    zustatky = {}
    for p in db.vsechny_pohyby():
        zustatky[p.md] = zustatky.get(p.md, D(0)) - p.castka
        zustatky[p.dal] = zustatky.get(p.dal, D(0)) + p.castka
    assert sum(zustatky.values(), D(0)) == 0


def test_preplatek_se_pouzije_na_dalsi_mesic():
    db, f, ema, _ = svet()
    f.zpracuj_platbu(Platba("x", date(2026, 9, 20), D("3000"), "260012"))
    p = f.vystav_predpis(ema, "2026-10")
    assert p.stav == StavPredpisu.ZAPLACENO and f.saldo("ema") == D("1092.00")


def test_dluznici_a_upominky():
    db, f, ema, oli = svet()
    f.vystav_predpis(ema, "2026-10")
    f.vystav_predpis(oli, "2026-10")
    f.zpracuj_platbu(Platba("x", date(2026, 11, 3), D("1056"), "260013"))   # Oliver zaplatil vše
    assert f.dluznici(date(2026, 11, 15)) == []                             # ještě není po splatnosti
    dl = f.dluznici(date(2026, 11, 16))
    assert [x["dite"].id for x in dl] == ["ema"] and dl[0]["dluh"] == D("1908.00")

    class Notif:
        def posli(self, dite, dluh, predpisy):
            return "push"
    out = f.posli_upominky(Notif(), date(2026, 11, 16))
    assert out == [{"dite_id": "ema", "dluh": D("1908.00"), "kanal": "push"}]
    assert db.upominky == [("ema", "2026-10", "push")]


# --------------------------------------------------------------------- VS
def test_variabilni_symboly():
    n = nastaveni()
    assert normalizuj("0000260012") == "260012"
    assert dalsi_vs(n, {"260001", "260002"}, date(2026, 9, 1)) == "260003"
    n2 = nastaveni(vs_schema=SchemaVS.PREFIX_PORADI, vs_prefix="77", vs_delka=6)
    assert dalsi_vs(n2, set()) == "770001"
    assert zkontroluj("26A1", set()) == "Variabilní symbol smí obsahovat jen číslice."
    assert zkontroluj("260012", {"260012"}) == "VS 260012 už má jiné dítě."
    assert zkontroluj("260012", {"260012"}, vlastni="260012") is None
    assert zkontroluj("12345678901", set()) == "Variabilní symbol může mít nejvýš 10 číslic."
