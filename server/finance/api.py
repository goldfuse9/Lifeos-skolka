"""API pro hospodářku (FastAPI).

Spuštění:  DATABASE_URL=postgresql://… SUPABASE_JWT_SECRET=… uvicorn finance.api:app
Přihlášení: hlavička `Authorization: Bearer <JWT ze Supabase Auth>`. Role a školka
se berou z tabulky `uzivatele`; finance smí ředitelka, zástupkyně a hospodářka.
Částky jsou v JSON vždy textem („1908.00“), nikdy číslem s plovoucí čárkou.
"""
from __future__ import annotations

import os
from dataclasses import dataclass
from datetime import date
from decimal import Decimal
from typing import Annotated

from fastapi import Depends, FastAPI, File, Header, HTTPException, UploadFile
from fastapi.responses import Response
from pydantic import BaseModel

from .model import Dite, Predpis
from .penize import kc
from .predpisy import nazev_obdobi
from .sluzby import Finance, ucet_ditete
from .spayd import qr_svg, spayd
from .uloziste import Uloziste
from .vs import dalsi_vs, normalizuj, zkontroluj
from .zpracovani import zpracuj_vypis

app = FastAPI(title="Školka — finance", version="1.0")

FINANCNI_ROLE = {"reditelka", "zastupce", "hospodarka"}
MAX_VYPIS = 5 * 1024 * 1024


@dataclass
class Prihlaseny:
    uzivatel_id: str
    skolka_id: str
    role: str


_uloziste: Uloziste | None = None


def uloziste() -> Uloziste:
    global _uloziste
    if _uloziste is None:
        from .uloziste_pg import PgUloziste
        _uloziste = PgUloziste.pripoj(os.environ["DATABASE_URL"])
    return _uloziste


def prihlaseny_z_jwt(authorization: Annotated[str | None, Header()] = None, db: Uloziste = Depends(uloziste)) -> Prihlaseny:
    import jwt
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(401, "Chybí přihlášení.")
    try:
        data = jwt.decode(authorization[7:], os.environ["SUPABASE_JWT_SECRET"], algorithms=["HS256"], audience="authenticated")
    except Exception:
        raise HTTPException(401, "Přihlášení vypršelo nebo je neplatné.")
    # Blokace účtu i školky platí i tady (stejně jako moje_role() v databázi).
    r = db._q(  # type: ignore[attr-defined]
        "select u.skola_id, u.role from uzivatele u join skoly s on s.id = u.skola_id"
        " where u.id = %s and u.aktivni and s.stav = 'aktivni'", (data["sub"],))
    if not r:
        raise HTTPException(403, "Účet nemá přístup (neexistuje nebo je zablokovaný).")
    return Prihlaseny(data["sub"], str(r[0]["skola_id"]), r[0]["role"])


def financni(u: Prihlaseny = Depends(prihlaseny_z_jwt)) -> Prihlaseny:
    if u.role not in FINANCNI_ROLE:
        raise HTTPException(403, "Finance vidí jen ředitelka, zástupkyně a hospodářka.")
    return u


def fin(u: Prihlaseny = Depends(financni), db: Uloziste = Depends(uloziste)) -> Finance:
    return Finance(db, u.skolka_id)


def _dite_skolky(f: Finance, dite_id: str) -> Dite:
    d = f.db.dite(dite_id)
    if d is None or d.id not in {x.id for x in f.db.deti(f.skolka_id)}:
        raise HTTPException(404, "Dítě v této školce není.")
    return d


def _castka(d: Decimal) -> str:
    return f"{kc(d):.2f}"


def _predpis(p: Predpis) -> dict:
    return {"id": p.id, "obdobi": p.obdobi, "castka": _castka(p.castka), "uhrazeno": _castka(p.uhrazeno), "zbyva": _castka(p.zbyva),
            "stav": p.stav.value, "splatnost": p.splatnost.isoformat(),
            "polozky": [{"druh": x.druh, "popis": x.popis, "mnozstvi": x.mnozstvi, "cena": _castka(x.cena), "castka": _castka(x.castka)} for x in p.polozky]}


# ------------------------------------------------------------------ výpisy
@app.post("/finance/vypisy")
async def import_vypisu(soubor: UploadFile = File(...), f: Finance = Depends(fin)) -> dict:
    """Ruční import výpisu .gpc: příchozí platby se spárují podle VS."""
    obsah = await soubor.read(MAX_VYPIS + 1)
    if len(obsah) > MAX_VYPIS:
        raise HTTPException(413, "Výpis je větší než 5 MB.")
    v = zpracuj_vypis(f, obsah)
    return {"ucet": v["ucet"], "pocty": v["pocty"], "preskoceno_odchozich": v["preskoceno_odchozich"], "chyby": v["chyby"],
            "platby": [{"platba_id": r.platba_id, "dite_id": r.dite_id, "vysledek": r.vysledek, "castka": _castka(r.castka),
                        "preplatek": _castka(r.preplatek), "zbyva_doplatit": _castka(r.zbyva_doplatit)} for r in v["vysledky"]]}


# -------------------------------------------------------- dlužníci, upomínky
@app.get("/finance/dluznici")
def dluznici(k_datu: date | None = None, f: Finance = Depends(fin)) -> list[dict]:
    return [{"dite_id": x["dite"].id, "jmeno": x["dite"].cele_jmeno, "vs": x["dite"].vs, "dluh": _castka(x["dluh"]),
             "nejstarsi_splatnost": x["nejstarsi_splatnost"].isoformat(), "predpisy": [_predpis(p) for p in x["predpisy"]]}
            for x in f.dluznici(k_datu)]


class Notifikator:
    """Push do aplikace LifeOS, když ji rodič má, jinak e-mail z přihlášky.
    Samotné odeslání obstará fronta zpráv; tady se rozhodne kanál a zapíše upomínka."""

    def __init__(self, db: Uloziste):
        self.db = db

    def posli(self, dite: Dite, dluh: Decimal, predpisy: list[Predpis]) -> str:
        q = getattr(self.db, "_q", None)
        if q is None:
            return "email"
        r = q("select bool_or(uzivatel_id is not null) as app from zastupci where dite_id = %s", (dite.id,))
        return "push" if r and r[0]["app"] else "email"


class UpominkyVstup(BaseModel):
    k_datu: date | None = None


@app.post("/finance/upominky")
def upominky(vstup: UpominkyVstup, f: Finance = Depends(fin)) -> dict:
    """Hromadné upomínky všem dlužníkům po splatnosti."""
    out = f.posli_upominky(Notifikator(f.db), vstup.k_datu)
    return {"odeslano": len(out), "upominky": [{"dite_id": x["dite_id"], "dluh": _castka(x["dluh"]), "kanal": x["kanal"]} for x in out]}


# ------------------------------------------------------- nespárované platby
@app.get("/finance/nesparovane")
def nesparovane(f: Finance = Depends(fin)) -> list[dict]:
    return [{"platba_id": n.platba.id, "datum": n.platba.datum.isoformat(), "castka": _castka(n.platba.castka), "vs": n.platba.vs,
             "protiucet": n.platba.protiucet, "nazev": n.platba.nazev, "duvod": n.duvod} for n in f.db.nesparovane(f.skolka_id)]


class SparovaniVstup(BaseModel):
    dite_id: str


@app.post("/finance/nesparovane/{platba_id}/sparovat")
def sparovat(platba_id: str, vstup: SparovaniVstup, f: Finance = Depends(fin)) -> dict:
    _dite_skolky(f, vstup.dite_id)
    try:
        r = f.sparuj_rucne(platba_id, vstup.dite_id)
    except KeyError as e:
        raise HTTPException(404, str(e.args[0]))
    return {"vysledek": r.vysledek, "preplatek": _castka(r.preplatek), "zbyva_doplatit": _castka(r.zbyva_doplatit)}


# ----------------------------------------------------------- předpisy, konta
@app.post("/finance/predpisy/{obdobi}/vystavit")
def vystavit(obdobi: str, f: Finance = Depends(fin)) -> dict:
    out = f.vystav_mesic(obdobi)
    return {"vystaveno": len(out), "celkem": _castka(sum((p.castka for p in out), Decimal(0)))}


@app.get("/finance/deti/{dite_id}/konto")
def konto(dite_id: str, f: Finance = Depends(fin)) -> dict:
    d = _dite_skolky(f, dite_id)
    return {"dite_id": d.id, "vs": d.vs, "saldo": _castka(f.saldo(d.id)), "k_uhrade": _castka(f.k_uhrade(d.id)),
            "predpisy": [_predpis(p) for p in f.db.predpisy(d.id)],
            "pohyby": [{"datum": p.datum.isoformat(), "popis": p.popis, "castka": _castka(p.castka if p.dal == ucet_ditete(d.id) else -p.castka)}
                       for p in f.db.pohyby(ucet_ditete(d.id))]}


@app.get("/finance/deti/{dite_id}/qr")
def qr(dite_id: str, obdobi: str, format: str = "svg", f: Finance = Depends(fin)):
    """QR platba na aktuální dluh (předpis minus přeplatek)."""
    d = _dite_skolky(f, dite_id)
    if not d.vs:
        raise HTTPException(409, "Dítě nemá variabilní symbol.")
    nast = f.db.nastaveni(f.skolka_id)
    s = spayd(nast.ucet, f.k_uhrade(d.id), normalizuj(d.vs), f.zprava_platby(d, obdobi))
    if format == "text":
        return {"spayd": s, "castka": _castka(f.k_uhrade(d.id)), "zprava": f"{nazev_obdobi(obdobi)} — {d.cele_jmeno}"}
    return Response(qr_svg(s), media_type="image/svg+xml")


# ------------------------------------------------------- variabilní symboly
class VsVstup(BaseModel):
    vs: str


@app.put("/finance/deti/{dite_id}/vs")
def nastav_vs(dite_id: str, vstup: VsVstup, f: Finance = Depends(fin)) -> dict:
    d = _dite_skolky(f, dite_id)
    obsazene = {normalizuj(x.vs) for x in f.db.deti(f.skolka_id) if x.id != d.id and x.vs}
    chyba = zkontroluj(vstup.vs, obsazene)
    if chyba:
        raise HTTPException(422, chyba)
    d.vs = vstup.vs.strip()
    f.db.uloz_dite(f.skolka_id, d)
    return {"dite_id": d.id, "vs": d.vs}


@app.post("/finance/deti/{dite_id}/vs/pridelit")
def pridel_vs(dite_id: str, f: Finance = Depends(fin)) -> dict:
    d = _dite_skolky(f, dite_id)
    obsazene = {normalizuj(x.vs) for x in f.db.deti(f.skolka_id) if x.vs}
    try:
        d.vs = dalsi_vs(f.db.nastaveni(f.skolka_id), obsazene)
    except ValueError as e:
        raise HTTPException(409, str(e))
    f.db.uloz_dite(f.skolka_id, d)
    return {"dite_id": d.id, "vs": d.vs}
