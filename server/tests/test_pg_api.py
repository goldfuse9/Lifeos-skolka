"""Celý tok nad skutečným PostgreSQL (schéma ze supabase/schema.sql) a přes API.

Spustí se, jen když je nastavené TEST_DATABASE_URL (jinak se přeskočí).
"""
import os
import time as _t
import uuid
from datetime import date, datetime, time
from decimal import Decimal as D

import pytest

DSN = os.environ.get("TEST_DATABASE_URL")
pytestmark = pytest.mark.skipif(not DSN, reason="TEST_DATABASE_URL není nastavené")


@pytest.fixture()
def svet():
    import jwt
    from fastapi.testclient import TestClient

    from finance import api
    from finance.model import Nastaveni
    from finance.uloziste_pg import PgUloziste

    db = PgUloziste.pripoj(DSN)
    q = db._q
    skola, hosp, ucit = str(uuid.uuid4()), str(uuid.uuid4()), str(uuid.uuid4())
    ema, oli = str(uuid.uuid4()), str(uuid.uuid4())
    q("insert into skoly (id, nazev, izo, red_izo) values (%s, 'MŠ Sluníčko', '1', '2')", (skola,))
    for uid, role in ((hosp, "hospodarka"), (ucit, "ucitelka")):
        q("insert into auth.users (id) values (%s)", (uid,))
        q("insert into uzivatele (id, skola_id, jmeno, role) values (%s, %s, 'X', %s)", (uid, skola, role))
    q("""insert into deti (id, skola_id, jmeno, prijmeni, datum_narozeni, pohlavi, zahajeni, variabilni_symbol, osvobozen_od_skolkovneho)
         values (%s, %s, 'Ema', 'Králová', '2022-03-05', 'F', '2025-09-01', '260012', false),
                (%s, %s, 'Oliver', 'Novák', '2020-11-02', 'M', '2025-09-01', '260013', true)""", (ema, skola, oli, skola))
    q("insert into zastupci (dite_id, jmeno, uzivatel_id) values (%s, 'Jana', %s)", (ema, hosp))
    dny = [date(2026, 10, d) for d in range(1, 32) if date(2026, 10, d).weekday() < 5]
    for d in dny:
        for dite in (ema, oli):
            q("insert into dochazka (dite_id, den, stav) values (%s, %s, 'pritomen')", (dite, d))
    q("update dochazka set omluva_zadana = %s where dite_id = %s and den = %s", (datetime(2026, 9, 30, 7, 30), ema, dny[0]))
    db.uloz_nastaveni(Nastaveni(skola, "MŠ Sluníčko", "19-2000145399/0800", "900", {"3-6": "48", "7+": "52"}, 1, time(8, 0), 15))

    os.environ["SUPABASE_JWT_SECRET"] = "tajne-pro-test-tajne-pro-test-123456"
    api.app.dependency_overrides[api.uloziste] = lambda: db
    tok = lambda uid: jwt.encode({"sub": uid, "aud": "authenticated", "exp": int(_t.time()) + 600}, os.environ["SUPABASE_JWT_SECRET"], algorithm="HS256")
    c = TestClient(api.app)
    yield {"c": c, "db": db, "skola": skola, "ema": ema, "oli": oli, "H": {"Authorization": f"Bearer {tok(hosp)}"},
           "U": {"Authorization": f"Bearer {tok(ucit)}"}}
    api.app.dependency_overrides.clear()


def test_cely_tok(svet):
    from finance.gpc import radek_075
    c, H, ema, oli, db = svet["c"], svet["H"], svet["ema"], svet["oli"], svet["db"]

    assert c.get("/finance/dluznici").status_code == 401
    assert c.get("/finance/dluznici", headers=svet["U"]).status_code == 403       # učitelka finance nevidí

    r = c.post("/finance/predpisy/2026-10/vystavit", headers=H).json()
    assert r == {"vystaveno": 2, "celkem": "2964.00"}                            # 900 + 21×48 a 22×48
    assert c.post("/finance/predpisy/2026-10/vystavit", headers=H).json()["vystaveno"] == 0

    k = c.get(f"/finance/deti/{ema}/konto", headers=H).json()
    assert (k["saldo"], k["k_uhrade"]) == ("-1908.00", "1908.00")
    assert db._q("select saldo from konta where dite_id = %s", (ema,))[0]["saldo"] == D("-1908.00")  # trigger

    q = c.get(f"/finance/deti/{ema}/qr", params={"obdobi": "2026-10", "format": "text"}, headers=H).json()
    assert q["spayd"] == "SPD*1.0*ACC:CZ6508000000192000145399*AM:1908.00*CC:CZK*MSG:SKOLKOVNE/STRAVNE RIJEN 2026 - EMA KRALOVA*X-VS:260012"
    assert c.get(f"/finance/deti/{ema}/qr", params={"obdobi": "2026-10"}, headers=H).headers["content-type"].startswith("image/svg")

    vypis = "\r\n".join([
        radek_075("2000145399", "1234567890", "11", 100000, "2", "260012", "0800", "KRALOVA", date(2026, 11, 3)),
        radek_075("2000145399", "1234567891", "12", 110000, "2", "260013", "0100", "NOVAK", date(2026, 11, 3)),
        radek_075("2000145399", "1234567892", "13", 65000, "2", "77001", "0300", "NEZNAMY", date(2026, 11, 4)),
        radek_075("2000145399", "9999999999", "14", 50000, "1", "0", "0300", "NAKUP", date(2026, 11, 4)),
    ]).encode("cp1250")
    r = c.post("/finance/vypisy", files={"soubor": ("vypis.gpc", vypis)}, headers=H).json()
    assert r["pocty"] == {"nedoplatek": 1, "preplatek": 1, "nesparovano": 1} and r["preskoceno_odchozich"] == 1
    assert c.post("/finance/vypisy", files={"soubor": ("vypis.gpc", vypis)}, headers=H).json()["pocty"] == {"duplicita": 3}

    ns = c.get("/finance/nesparovane", headers=H).json()
    assert len(ns) == 1 and ns[0]["castka"] == "650.00"
    d = c.get("/finance/dluznici", params={"k_datu": "2026-11-20"}, headers=H).json()
    assert [(x["jmeno"], x["dluh"]) for x in d] == [("Ema Králová", "908.00")]
    u = c.post("/finance/upominky", json={"k_datu": "2026-11-20"}, headers=H).json()
    assert u["odeslano"] == 1 and u["upominky"][0]["kanal"] == "push"            # rodič má aplikaci

    r = c.post(f"/finance/nesparovane/{ns[0]['platba_id']}/sparovat", json={"dite_id": ema}, headers=H).json()
    assert r == {"vysledek": "nedoplatek", "preplatek": "0.00", "zbyva_doplatit": "258.00"}
    k = c.get(f"/finance/deti/{ema}/konto", headers=H).json()
    assert k["k_uhrade"] == "258.00" and k["predpisy"][0]["stav"] == "castecne_zaplaceno"
    assert c.get(f"/finance/deti/{oli}/konto", headers=H).json()["saldo"] == "44.00"

    # VS: duplicita odmítnuta, přidělení podle schématu
    assert c.put(f"/finance/deti/{oli}/vs", json={"vs": "260012"}, headers=H).status_code == 422
    assert c.post(f"/finance/deti/{oli}/vs/pridelit", headers=H).json()["vs"].startswith("26")

    # účetní kniha se nedá přepsat
    import psycopg
    with pytest.raises(psycopg.errors.RaiseException):
        db._q("delete from ucetni_pohyby")
    zust = db._q("select coalesce(sum(castka), 0) s from ucetni_pohyby where md = 'banka' and skola_id = %s", (svet["skola"],))[0]["s"]
    assert zust == D("2750.00")


def test_blokace(svet):
    """Zablokovaný účet ani účet zablokované školky finance nevidí (audit E13)."""
    c, H, db = svet["c"], svet["H"], svet["db"]
    assert c.get("/finance/dluznici", headers=H).status_code == 200
    db._q("update uzivatele set aktivni = false where role = 'hospodarka' and skola_id = %s", (svet["skola"],))
    assert c.get("/finance/dluznici", headers=H).status_code == 403
    db._q("update uzivatele set aktivni = true where role = 'hospodarka' and skola_id = %s", (svet["skola"],))
    db._q("update skoly set stav = 'blokovana' where id = %s", (svet["skola"],))
    assert c.get("/finance/dluznici", headers=H).status_code == 403
