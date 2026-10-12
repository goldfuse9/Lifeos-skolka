"""Zpracování výpisu .gpc přes párovací engine — společné pro API i Celery úlohu."""
from __future__ import annotations

import uuid
from collections import Counter

from .gpc import parsuj
from .model import Platba
from .sluzby import Finance


def zpracuj_vypis(fin: Finance, obsah: bytes | str, zdroj: str = "gpc") -> dict:
    vypis = parsuj(obsah)
    pocty: Counter[str] = Counter()
    vysledky = []
    preskoceno = 0
    for t in vypis.transakce:
        if not t.prichozi or t.castka <= 0:
            preskoceno += 1          # odchozí platby a storna se nepárují
            continue
        doklad = f"{t.nas_ucet}:{t.doklad}:{t.datum.isoformat() if t.datum else ''}:{t.radek if not t.doklad else ''}"
        p = Platba(id=str(uuid.uuid4()), datum=t.datum or vypis.datum, castka=t.castka, vs=t.vs,
                   protiucet=t.protiucet, nazev=t.nazev, zdroj=zdroj, doklad=doklad)
        if p.datum is None:
            vypis.chyby.append(f"Řádek {t.radek}: chybí datum platby — přeskočen.")
            continue
        r = fin.zpracuj_platbu(p)
        pocty[r.vysledek] += 1
        vysledky.append(r)
    return {"ucet": vypis.ucet, "pocty": dict(pocty), "preskoceno_odchozich": preskoceno,
            "chyby": vypis.chyby, "vysledky": vysledky}
