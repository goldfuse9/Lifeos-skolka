"""Parser bankovních výpisů ve formátu ABO / GPC (.gpc).

Každý řádek má pevnou délku 128 znaků (+ CRLF). Typy záznamů:
  074 … hlavička výpisu (náš účet, zůstatky, datum)
  075 … obratová položka = jedna transakce  ← zajímá nás
  076–079 … doplňující údaje (zprávy, adresy) — přeskakují se
Pozice podle specifikace GPC (Fio banka, ČS, KB), počítáno od 1:

  075:  4–19 náš účet · 20–35 protiúčet · 36–48 číslo dokladu ·
        49–60 částka v haléřích · 61 kód účtování (1 debet, 2 kredit,
        4 storno debetu, 5 storno kreditu) · 62–71 VS ·
        72–81 kód banky + konstantní symbol · 82–91 SS ·
        92–97 valuta · 98–117 název protiúčtu · 119–122 měna ·
        123–128 datum (DDMMRR)

Protiúčet musí být v „editovaném“ tvaru (předčíslí + číslo), ne ve
„vnitřním“ — u některých bank se to volí v internetovém bankovnictví při
exportu. Párování jde podle VS, takže na tvaru protiúčtu nic nezávisí.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from decimal import Decimal

from .penize import z_haleru

# Kódy bank ČNB — slouží k rozpoznání, kde v poli 72–81 kód banky je.
KODY_BANK = {
    "0100", "0300", "0600", "0710", "0800", "2010", "2060", "2070", "2100", "2200", "2220", "2250", "2260", "2275",
    "2600", "2700", "3030", "3050", "3060", "3500", "4000", "4300", "5500", "5800", "6000", "6100", "6200", "6210",
    "6300", "6363", "6700", "6800", "7910", "7950", "7960", "7970", "7990", "8030", "8040", "8060", "8090", "8150",
    "8190", "8198", "8199", "8200", "8220", "8250", "8255", "8265", "8500",
}


@dataclass
class Transakce:
    nas_ucet: str
    protiucet: str
    doklad: str
    castka: Decimal          # kladná = příchozí (kredit), záporná = odchozí
    kod: str                 # 1 debet, 2 kredit, 4 storno debetu, 5 storno kreditu
    vs: str
    ks: str
    ss: str
    nazev: str
    datum: date | None
    radek: int

    @property
    def prichozi(self) -> bool:
        return self.kod == "2"


@dataclass
class Vypis:
    ucet: str = ""
    datum: date | None = None
    transakce: list[Transakce] = None  # type: ignore[assignment]
    chyby: list[str] = None            # type: ignore[assignment]


def _datum(ddmmrr: str) -> date | None:
    if not ddmmrr.isdigit() or ddmmrr == "000000":
        return None
    d, m, r = int(ddmmrr[0:2]), int(ddmmrr[2:4]), int(ddmmrr[4:6])
    try:
        return date(2000 + r, m, d)
    except ValueError:
        return None


def _ucet(cislice16: str, banka: str = "") -> str:
    c = cislice16.strip().lstrip("0")
    if not c:
        return ""
    cislo, predcisli = c[-10:].lstrip("0") or "0", c[:-10].lstrip("0")
    return (f"{predcisli}-" if predcisli else "") + cislo + (f"/{banka}" if banka else "")


def _symbol(text: str) -> str:
    t = text.strip()
    return t.lstrip("0") if t.isdigit() else ""


def _banka_ks(pole: str) -> tuple[str, str]:
    """Pole 72–81: buď „BBBB“ + KS (Fio, KB), nebo „00“ + „BBBB“ + KS (některé banky)."""
    if pole[:4] in KODY_BANK:
        return pole[:4], _symbol(pole[4:])
    if pole[:2] == "00" and pole[2:6] in KODY_BANK:
        return pole[2:6], _symbol(pole[6:])
    return "", _symbol(pole)


def dekoduj(data: bytes) -> str:
    """Výpisy z českých bank bývají ve windows-1250, novější v UTF-8."""
    for kod in ("utf-8", "cp1250"):
        try:
            return data.decode(kod)
        except UnicodeDecodeError:
            continue
    return data.decode("cp1250", errors="replace")


def parsuj(obsah: str | bytes) -> Vypis:
    text = dekoduj(obsah) if isinstance(obsah, bytes) else obsah
    vypis = Vypis(transakce=[], chyby=[])
    for i, raw in enumerate(text.splitlines(), start=1):
        r = raw.rstrip("\r\n")
        if r.startswith("074"):
            vypis.ucet = _ucet(r[3:19])
            vypis.datum = _datum(r[108:114]) if len(r) >= 114 else None
            continue
        if not r.startswith("075"):
            continue
        if len(r) < 117:
            vypis.chyby.append(f"Řádek {i}: záznam 075 je kratší než 117 znaků — přeskočen.")
            continue
        try:
            castka = z_haleru(r[48:60])
        except ValueError:
            vypis.chyby.append(f"Řádek {i}: částka „{r[48:60]}“ není číslo — přeskočen.")
            continue
        kod = r[60]
        if kod not in "1245":
            vypis.chyby.append(f"Řádek {i}: neznámý kód účtování „{kod}“ — přeskočen.")
            continue
        znamenko = 1 if kod in ("2", "4") else -1  # kredit a storno debetu zvyšují zůstatek
        banka, ks = _banka_ks(r[71:81])
        datum = (_datum(r[122:128]) if len(r) >= 128 else None) or _datum(r[91:97]) or vypis.datum
        vypis.transakce.append(Transakce(
            nas_ucet=_ucet(r[3:19]), protiucet=_ucet(r[19:35], banka), doklad=r[35:48].strip(),
            castka=castka * znamenko, kod=kod, vs=_symbol(r[61:71]), ks=ks, ss=_symbol(r[81:91]),
            nazev=r[97:117].strip(), datum=datum, radek=i))
    return vypis


def radek_075(nas_ucet: str, protiucet: str, doklad: str, halere: int, kod: str, vs: str, banka: str,
              nazev: str, datum: date, ks: str = "0", ss: str = "0") -> str:
    """Sestaví řádek 075 (pro testy a ukázkové výpisy)."""
    r = ("075" + nas_ucet.zfill(16)[:16] + protiucet.zfill(16)[:16] + doklad.zfill(13)[:13] + str(halere).zfill(12)
         + kod + vs.zfill(10) + (banka.zfill(4) + ks.zfill(6))[:10] + ss.zfill(10) + "000000"
         + nazev.ljust(20)[:20] + "0" + "0203" + datum.strftime("%d%m%y"))
    assert len(r) == 128, len(r)
    return r
