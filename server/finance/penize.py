"""Peníze — výhradně Decimal, nikdy float.

Každá částka v systému prochází funkcí `kc()`: ta odmítne float (už v něm
může být chyba zaokrouhlení, např. 0.1 + 0.2), převede int/str/Decimal na
Decimal a zaokrouhlí na haléře obchodním zaokrouhlením (ROUND_HALF_UP).
V databázi tomu odpovídá NUMERIC(10, 2).
"""
from __future__ import annotations

from decimal import ROUND_HALF_UP, Decimal, InvalidOperation

HALER = Decimal("0.01")
NULA = Decimal("0.00")
MAX = Decimal("99999999.99")  # NUMERIC(10, 2)


def kc(hodnota: Decimal | int | str) -> Decimal:
    """Částka v Kč jako Decimal se dvěma desetinnými místy."""
    if isinstance(hodnota, bool) or isinstance(hodnota, float):
        raise TypeError("Částky se nesmí předávat jako float — použijte Decimal, int nebo str.")
    if isinstance(hodnota, str):
        text = hodnota.strip().replace(" ", "").replace(" ", "").replace(",", ".")
        if text.lower().endswith("kč"):
            text = text[:-2]
        try:
            hodnota = Decimal(text)
        except InvalidOperation as e:
            raise ValueError(f"Neplatná částka: {hodnota!r}") from e
    d = Decimal(hodnota).quantize(HALER, rounding=ROUND_HALF_UP)
    if abs(d) > MAX:
        raise ValueError(f"Částka {d} je mimo rozsah NUMERIC(10, 2).")
    return d


def z_haleru(halere: int | str) -> Decimal:
    """Částka zapsaná v haléřích bez desetinné čárky (formát ABO) → Kč."""
    text = str(halere).strip()
    if not text.lstrip("-").isdigit():
        raise ValueError(f"Částka v haléřích musí být celé číslo: {halere!r}")
    return kc(Decimal(int(text)) / 100)


def na_halere(castka: Decimal) -> int:
    return int((kc(castka) * 100).to_integral_value())


def format_kc(castka: Decimal) -> str:
    """1234.5 → '1 234,50 Kč' (pevná mezera mezi tisíci)."""
    d = kc(castka)
    znam = "-" if d < 0 else ""
    cele, des = f"{abs(d):.2f}".split(".")
    skupiny = []
    while len(cele) > 3:
        skupiny.insert(0, cele[-3:])
        cele = cele[:-3]
    skupiny.insert(0, cele)
    return f"{znam}{' '.join(skupiny)},{des} Kč"
