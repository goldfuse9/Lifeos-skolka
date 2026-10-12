"""Výpočet měsíčního předpisu: školkovné (fixní) + stravné (podle docházky).

Čisté funkce bez databáze — služba (`sluzby.py`) jim dodá data a výsledek uloží.
"""
from __future__ import annotations

import calendar
from datetime import date, datetime, timedelta

from .model import Dite, DochazkaDen, Nastaveni, Polozka, Predpis
from .penize import NULA, kc

MESICE = ["leden", "únor", "březen", "duben", "květen", "červen", "červenec", "srpen", "září", "říjen", "listopad", "prosinec"]


def rozsah_obdobi(obdobi: str) -> tuple[date, date]:
    """'2026-10' → (1. 10. 2026, 31. 10. 2026)."""
    rok, mesic = (int(x) for x in obdobi.split("-"))
    return date(rok, mesic, 1), date(rok, mesic, calendar.monthrange(rok, mesic)[1])


def nazev_obdobi(obdobi: str) -> str:
    rok, mesic = (int(x) for x in obdobi.split("-"))
    return f"{MESICE[mesic - 1]} {rok}"


def kategorie_stravneho(narozeni: date, den: date) -> str:
    """Věková skupina strávníka podle vyhl. 107/2005 Sb.: rozhoduje věk, kterého
    dítě dosáhne v daném školním roce (do 31. 8.). 3–6 let → "3-6", 7 a víc → "7+"."""
    konec_sr = date(den.year + (1 if den.month >= 9 else 0), 8, 31)
    vek = konec_sr.year - narozeni.year - ((konec_sr.month, konec_sr.day) < (narozeni.month, narozeni.day))
    return "7+" if vek >= 7 else "3-6"


def omluveno_vcas(den: date, omluva: datetime | None, nast: Nastaveni) -> bool:
    """Omluvenka se počítá, jen když přišla do uzávěrky (např. do 8:00 předchozího dne)."""
    if omluva is None:
        return False
    uzaverka = datetime.combine(den - timedelta(days=nast.omluva_dni_predem), nast.omluva_do)
    if omluva.tzinfo is not None:
        omluva = omluva.replace(tzinfo=None)  # časy školky jsou v místním čase
    return omluva <= uzaverka


def splatnost_predpisu(obdobi: str, nast: Nastaveni) -> date:
    _, konec = rozsah_obdobi(obdobi)
    dalsi = konec + timedelta(days=1)
    return date(dalsi.year, dalsi.month, nast.splatnost_den)


def spocti_predpis(dite: Dite, obdobi: str, dochazka: list[DochazkaDen], nast: Nastaveni, predpis_id: str) -> Predpis:
    """Předpis za měsíc `obdobi` (počítá se po skončení měsíce — stravné podle skutečnosti)."""
    od, do = rozsah_obdobi(obdobi)
    polozky: list[Polozka] = []

    # Školkovné — fixní sazba, osvobozené děti (PPV, odklad) platí 0 Kč
    if dite.osvobozen_od_skolkovneho:
        polozky.append(Polozka("skolkovne", "Školkovné — osvobozeno", 1, NULA, NULA))
    else:
        polozky.append(Polozka("skolkovne", f"Školkovné {nazev_obdobi(obdobi)}", 1, nast.skolkovne, nast.skolkovne))

    # Stravné — dny s přihlášeným jídlem, bez včas omluvených; po věkových skupinách
    dny: dict[str, int] = {}
    for d in dochazka:
        if d.dite_id != dite.id or not (od <= d.den <= do) or not d.strava_prihlasena:
            continue
        if omluveno_vcas(d.den, d.omluva_zadana, nast):
            continue
        kat = kategorie_stravneho(dite.datum_narozeni, d.den)
        dny[kat] = dny.get(kat, 0) + 1
    for kat in sorted(dny):
        if kat not in nast.stravne:
            raise ValueError(f"Školka nemá sazbu stravného pro kategorii {kat}.")
        cena = nast.stravne[kat]
        polozky.append(Polozka("stravne", f"Stravné {kat} let", dny[kat], cena, kc(cena * dny[kat])))

    castka = kc(sum((p.castka for p in polozky), NULA))
    return Predpis(id=predpis_id, dite_id=dite.id, obdobi=obdobi, polozky=polozky, castka=castka,
                   splatnost=splatnost_predpisu(obdobi, nast), vystaveno=date.today())
