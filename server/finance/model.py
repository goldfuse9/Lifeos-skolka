"""Datové typy finančního modulu (odpovídají tabulkám v supabase/schema.sql)."""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime, time
from decimal import Decimal
from enum import Enum

from .penize import NULA, kc


class StavPredpisu(str, Enum):
    OTEVRENO = "otevreno"
    CASTECNE = "castecne_zaplaceno"
    ZAPLACENO = "zaplaceno"


class SchemaVS(str, Enum):
    """Jak školka přiděluje variabilní symboly dětem."""
    ROK_PORADI = "rok_poradi"        # 26 0001 — rok nástupu + pořadí (výchozí)
    PREFIX_PORADI = "prefix_poradi"  # vlastní předčíslí + pořadí, např. 77 0001
    RUCNE = "rucne"                  # ředitelka/hospodářka zadává sama


@dataclass
class Nastaveni:
    """Konfigurace jedné školky (tenanta)."""
    skolka_id: str
    nazev: str
    ucet: str                                   # "123-4567890123/0800" nebo IBAN
    skolkovne: Decimal                          # měsíční úplata
    stravne: dict[str, Decimal]                 # {"3-6": Decimal("48.00"), "7+": Decimal("52.00")}
    omluva_dni_predem: int = 1                  # omluvenka do 8:00 předchozího dne → 1
    omluva_do: time = time(8, 0)
    splatnost_den: int = 15                     # předpis za měsíc M je splatný 15. dne měsíce M+1
    vs_schema: SchemaVS = SchemaVS.ROK_PORADI
    vs_prefix: str = ""
    vs_delka: int = 6                           # počet číslic VS (max. 10)

    def __post_init__(self) -> None:
        self.skolkovne = kc(self.skolkovne)
        self.stravne = {k: kc(v) for k, v in self.stravne.items()}
        if not 1 <= self.splatnost_den <= 28:
            raise ValueError("Den splatnosti musí být 1–28.")
        if not 4 <= self.vs_delka <= 10:
            raise ValueError("Variabilní symbol může mít 4–10 číslic.")


@dataclass
class Dite:
    id: str
    jmeno: str
    prijmeni: str
    datum_narozeni: date
    vs: str
    osvobozen_od_skolkovneho: bool = False      # předškoláci (PPV) a děti s odkladem
    aktivni: bool = True

    @property
    def cele_jmeno(self) -> str:
        return f"{self.jmeno} {self.prijmeni}"


@dataclass
class DochazkaDen:
    dite_id: str
    den: date
    strava_prihlasena: bool = True              # dítě mělo na ten den přihlášené jídlo
    omluva_zadana: datetime | None = None       # kdy rodič omluvenku zadal (None = neomluveno)


@dataclass
class Polozka:
    druh: str                                   # "skolkovne" | "stravne"
    popis: str
    mnozstvi: int
    cena: Decimal
    castka: Decimal


@dataclass
class Predpis:
    id: str
    dite_id: str
    obdobi: str                                 # "2026-10"
    polozky: list[Polozka]
    castka: Decimal
    splatnost: date
    uhrazeno: Decimal = NULA
    stav: StavPredpisu = StavPredpisu.OTEVRENO
    vystaveno: date | None = None

    @property
    def zbyva(self) -> Decimal:
        return kc(self.castka - self.uhrazeno)


@dataclass
class Platba:
    """Příchozí platba z výpisu (.gpc) nebo bankovního API."""
    id: str
    datum: date
    castka: Decimal
    vs: str
    protiucet: str = ""
    nazev: str = ""
    zdroj: str = "gpc"
    doklad: str = ""                            # číslo dokladu banky — brání dvojímu načtení


@dataclass
class NesparovanaPlatba:
    platba: Platba
    duvod: str
    vyreseno: bool = False


@dataclass
class Pohyb:
    """Účetní zápis podvojně: má dáti / dal, vždy kladná částka."""
    id: str
    datum: date
    md: str                                     # účet „má dáti“
    dal: str                                    # účet „dal“
    castka: Decimal
    popis: str
    doklad: str = ""                            # id předpisu nebo platby

    def __post_init__(self) -> None:
        self.castka = kc(self.castka)
        if self.castka <= 0:
            raise ValueError("Účetní pohyb musí mít kladnou částku.")
        if self.md == self.dal:
            raise ValueError("Má dáti a Dal nesmí být stejný účet.")


@dataclass
class VysledekParovani:
    platba_id: str
    dite_id: str | None
    vysledek: str                               # "presne" | "preplatek" | "nedoplatek" | "nesparovano" | "duplicita"
    castka: Decimal
    preplatek: Decimal = NULA
    zbyva_doplatit: Decimal = NULA
    predpisy: list[str] = field(default_factory=list)
