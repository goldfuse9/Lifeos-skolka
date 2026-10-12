"""Úlohy na pozadí (Celery).

Spuštění:  CELERY_BROKER_URL=redis://… DATABASE_URL=… celery -A finance.ulohy worker -B
- 1. den v měsíci v 6:00 se vystaví předpisy za uplynulý měsíc (stravné podle skutečné docházky).
- Výpisy z bankovního API / nahrané .gpc se párují úlohou `zpracuj_vypis_ulohou`.
"""
from __future__ import annotations

import os
from datetime import date, timedelta

from celery import Celery
from celery.schedules import crontab

from .sluzby import Finance
from .zpracovani import zpracuj_vypis

app = Celery("skolka_finance", broker=os.environ.get("CELERY_BROKER_URL", "memory://"))
app.conf.timezone = "Europe/Prague"
app.conf.beat_schedule = {
    "predpisy-za-minuly-mesic": {"task": "finance.ulohy.vystav_predpisy_vsech_skolek", "schedule": crontab(minute=0, hour=6, day_of_month=1)},
}


def _db():
    from .uloziste_pg import PgUloziste
    return PgUloziste.pripoj(os.environ["DATABASE_URL"])


def minuly_mesic(dnes: date | None = None) -> str:
    d = (dnes or date.today()).replace(day=1) - timedelta(days=1)
    return f"{d.year}-{d.month:02d}"


@app.task(name="finance.ulohy.vystav_predpisy_vsech_skolek")
def vystav_predpisy_vsech_skolek(obdobi: str | None = None) -> dict:
    db = _db()
    obdobi = obdobi or minuly_mesic()
    out = {}
    for r in db._q("select skola_id from financni_nastaveni"):
        out[str(r["skola_id"])] = len(Finance(db, str(r["skola_id"])).vystav_mesic(obdobi))
    return {"obdobi": obdobi, "vystaveno": out}


@app.task(name="finance.ulohy.zpracuj_vypis_ulohou")
def zpracuj_vypis_ulohou(skolka_id: str, obsah: bytes, zdroj: str = "gpc") -> dict:
    v = zpracuj_vypis(Finance(_db(), skolka_id), obsah, zdroj)
    return {"pocty": v["pocty"], "chyby": v["chyby"]}
