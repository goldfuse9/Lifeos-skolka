"""Variabilní symboly dětí: přidělení podle nastavení školky a kontrola.

VS je jen číslice, nejvýš 10 (omezení bank). Porovnává se bez úvodních nul —
banka je ve výpisu doplňuje (0000260012 = 260012).
"""
from __future__ import annotations

from datetime import date

from .model import Nastaveni, SchemaVS


def normalizuj(vs: str | int | None) -> str:
    text = "".join(ch for ch in str(vs or "") if not ch.isspace())
    if not text.isdigit():
        return ""
    return text.lstrip("0") or "0"


def zkontroluj(vs: str, obsazene: set[str], vlastni: str | None = None) -> str | None:
    """Vrátí chybu, nebo None. `obsazene` jsou normalizované VS ostatních dětí školky."""
    text = (vs or "").strip()
    if not text:
        return "Variabilní symbol chybí."
    if not text.isdigit():
        return "Variabilní symbol smí obsahovat jen číslice."
    if len(text) > 10:
        return "Variabilní symbol může mít nejvýš 10 číslic."
    n = normalizuj(text)
    if n == "0":
        return "Variabilní symbol nesmí být nula."
    if n in obsazene and n != normalizuj(vlastni):
        return f"VS {text} už má jiné dítě."
    return None


def dalsi_vs(nast: Nastaveni, obsazene: set[str], nastup: date | None = None) -> str:
    """Další volný VS podle schématu školky."""
    if nast.vs_schema == SchemaVS.RUCNE:
        raise ValueError("Školka přiděluje VS ručně.")
    if nast.vs_schema == SchemaVS.ROK_PORADI:
        predcisli = f"{(nastup or date.today()).year % 100:02d}"
    else:
        predcisli = "".join(ch for ch in nast.vs_prefix if ch.isdigit())
        if not predcisli:
            raise ValueError("Pro schéma s předčíslím vyplňte předčíslí.")
    zbyva = nast.vs_delka - len(predcisli)
    if zbyva < 2:
        raise ValueError("Předčíslí je na zvolenou délku VS příliš dlouhé.")
    for poradi in range(1, 10 ** zbyva):
        kandidat = predcisli + str(poradi).zfill(zbyva)
        if normalizuj(kandidat) not in obsazene:
            return kandidat
    raise ValueError("Volné variabilní symboly v této řadě došly — prodlužte délku VS.")
