"""QR platba — SPAYD (Short Payment Descriptor, standard ČBA).

    SPD*1.0*ACC:CZ6508000000192000145399*AM:1950.00*CC:CZK*MSG:SKOLKOVNE...*X-VS:260012

Pozn.: variabilní symbol se ve SPAYD zapisuje klíčem `X-VS` (klíč `VS`
standard nezná a bankovní aplikace by ho ignorovaly). Číslo účtu musí být
IBAN — český tvar „předčíslí-číslo/banka“ se převede.

Na PyPI není pro SPAYD udržovaná knihovna, proto je zápis tady (formát je
krátký a pevně daný); QR obrázek kreslí knihovna `qrcode`.
"""
from __future__ import annotations

import re
import unicodedata
from decimal import Decimal

from .penize import kc

_VAHY_PREDCISLI = [10, 5, 8, 4, 2, 1]
_VAHY_CISLA = [6, 3, 7, 9, 10, 5, 8, 4, 2, 1]


def _mod11(cislice: str, vahy: list[int]) -> bool:
    return sum(int(c) * v for c, v in zip(cislice.zfill(len(vahy)), vahy)) % 11 == 0


def iban_z_cz(ucet: str) -> str:
    """'19-2000145399/0800' → 'CZ6508000000192000145399' (s kontrolou čísla účtu)."""
    text = ucet.replace(" ", "").upper()
    if text.startswith("CZ"):
        if not re.fullmatch(r"CZ\d{22}", text) or not over_iban(text):
            raise ValueError("Neplatný IBAN.")
        return text
    m = re.fullmatch(r"(?:(\d{1,6})-)?(\d{2,10})/(\d{4})", text)
    if not m:
        raise ValueError("Číslo účtu zadejte jako předčíslí-číslo/kód banky, např. 19-2000145399/0800.")
    predcisli, cislo, banka = m.group(1) or "0", m.group(2), m.group(3)
    if not _mod11(predcisli, _VAHY_PREDCISLI) or not _mod11(cislo, _VAHY_CISLA):
        raise ValueError("Číslo účtu nesedí (kontrolní součet) — zkontrolujte ho.")
    bban = banka + predcisli.zfill(6) + cislo.zfill(10)
    kontrola = 98 - int(bban + "123500") % 97  # C=12, Z=35, "00"
    return f"CZ{kontrola:02d}{bban}"


def over_iban(iban: str) -> bool:
    s = iban[4:] + iban[:4]
    cisla = "".join(str(int(c, 36)) for c in s)
    return int(cisla) % 97 == 1


def _text(hodnota: str, maxlen: int) -> str:
    """Bez diakritiky a hvězdiček (oddělovač SPAYD), velkými písmeny — přečte to každá banka."""
    t = unicodedata.normalize("NFKD", hodnota).encode("ascii", "ignore").decode("ascii")
    t = re.sub(r"[*\r\n]+", " ", t).strip().upper()
    return t[:maxlen]


def spayd(ucet: str, castka: Decimal, vs: str, zprava: str, mena: str = "CZK") -> str:
    am = kc(castka)
    if am < 0:
        raise ValueError("Částka QR platby nesmí být záporná.")
    vs_c = (vs or "").strip()
    if vs_c and (not vs_c.isdigit() or len(vs_c) > 10):
        raise ValueError("VS musí být 1–10 číslic.")
    casti = ["SPD", "1.0", f"ACC:{iban_z_cz(ucet)}", f"AM:{am:.2f}", f"CC:{mena}"]
    if zprava:
        casti.append(f"MSG:{_text(zprava, 60)}")
    if vs_c:
        casti.append(f"X-VS:{vs_c}")
    return "*".join(casti)


def qr_svg(text: str, velikost_modulu: int = 8) -> str:
    """QR kód jako SVG (úroveň opravy M — doporučení ČBA)."""
    import qrcode
    import qrcode.image.svg

    qr = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, box_size=velikost_modulu, border=4,
                       image_factory=qrcode.image.svg.SvgPathImage)
    qr.add_data(text)
    qr.make(fit=True)
    return qr.make_image().to_string(encoding="unicode")
