"""Úložiště: rozhraní, které služby potřebují, a jeho verze v paměti (testy, ukázka).

Verze nad PostgreSQL je v `uloziste_pg.py` a chová se stejně.
"""
from __future__ import annotations

from contextlib import nullcontext
from datetime import date
from decimal import Decimal
from typing import Protocol

from .model import Dite, DochazkaDen, Nastaveni, NesparovanaPlatba, Platba, Pohyb, Predpis
from .penize import NULA, kc
from .vs import normalizuj


class Uloziste(Protocol):
    def nastaveni(self, skolka_id: str) -> Nastaveni: ...
    def uloz_nastaveni(self, n: Nastaveni) -> None: ...
    def deti(self, skolka_id: str) -> list[Dite]: ...
    def dite(self, dite_id: str) -> Dite | None: ...
    def dite_podle_vs(self, skolka_id: str, vs: str) -> Dite | None: ...
    def uloz_dite(self, skolka_id: str, d: Dite) -> None: ...
    def dochazka(self, dite_id: str, od: date, do: date) -> list[DochazkaDen]: ...
    def predpisy(self, dite_id: str) -> list[Predpis]: ...
    def predpis(self, dite_id: str, obdobi: str) -> Predpis | None: ...
    def uloz_predpis(self, p: Predpis) -> None: ...
    def zapis_pohyb(self, p: Pohyb) -> None: ...
    def pohyby(self, ucet: str) -> list[Pohyb]: ...
    def saldo(self, ucet: str) -> Decimal: ...
    def platba_podle_dokladu(self, skolka_id: str, doklad: str) -> Platba | None: ...
    def uloz_platbu(self, skolka_id: str, p: Platba, dite_id: str | None) -> None: ...
    def nesparovane(self, skolka_id: str) -> list[NesparovanaPlatba]: ...
    def uloz_nesparovanou(self, skolka_id: str, n: NesparovanaPlatba) -> None: ...
    def oznac_vyresenou(self, platba_id: str, dite_id: str) -> None: ...
    def zapis_upominku(self, dite_id: str, obdobi: str, kanal: str) -> None: ...
    def transakce(self): ...


class PametoveUloziste:
    def __init__(self) -> None:
        self._nast: dict[str, Nastaveni] = {}
        self._deti: dict[str, tuple[str, Dite]] = {}
        self._doch: list[DochazkaDen] = []
        self._predpisy: dict[tuple[str, str], Predpis] = {}
        self._pohyby: list[Pohyb] = []
        self._platby: dict[str, tuple[str, Platba, str | None]] = {}
        self._nespar: dict[str, tuple[str, NesparovanaPlatba]] = {}
        self.upominky: list[tuple[str, str, str]] = []

    def transakce(self):
        return nullcontext()

    # --- školka a děti
    def nastaveni(self, skolka_id: str) -> Nastaveni:
        return self._nast[skolka_id]

    def uloz_nastaveni(self, n: Nastaveni) -> None:
        self._nast[n.skolka_id] = n

    def deti(self, skolka_id: str) -> list[Dite]:
        return [d for s, d in self._deti.values() if s == skolka_id]

    def dite(self, dite_id: str) -> Dite | None:
        x = self._deti.get(dite_id)
        return x[1] if x else None

    def dite_podle_vs(self, skolka_id: str, vs: str) -> Dite | None:
        n = normalizuj(vs)
        if not n:
            return None
        for s, d in self._deti.values():
            if s == skolka_id and normalizuj(d.vs) == n:
                return d
        return None

    def uloz_dite(self, skolka_id: str, d: Dite) -> None:
        self._deti[d.id] = (skolka_id, d)

    # --- docházka
    def pridej_dochazku(self, dny: list[DochazkaDen]) -> None:
        self._doch.extend(dny)

    def dochazka(self, dite_id: str, od: date, do: date) -> list[DochazkaDen]:
        return [x for x in self._doch if x.dite_id == dite_id and od <= x.den <= do]

    # --- předpisy a účetní kniha
    def predpisy(self, dite_id: str) -> list[Predpis]:
        return sorted((p for (d, _), p in self._predpisy.items() if d == dite_id), key=lambda p: (p.splatnost, p.obdobi))

    def predpis(self, dite_id: str, obdobi: str) -> Predpis | None:
        return self._predpisy.get((dite_id, obdobi))

    def uloz_predpis(self, p: Predpis) -> None:
        self._predpisy[(p.dite_id, p.obdobi)] = p

    def zapis_pohyb(self, p: Pohyb) -> None:
        self._pohyby.append(p)

    def pohyby(self, ucet: str) -> list[Pohyb]:
        return [p for p in self._pohyby if ucet in (p.md, p.dal)]

    def saldo(self, ucet: str) -> Decimal:
        """Zůstatek účtu ze strany Dal: kladný = přeplatek, záporný = dluh."""
        s = NULA
        for p in self._pohyby:
            if p.dal == ucet:
                s += p.castka
            if p.md == ucet:
                s -= p.castka
        return kc(s)

    def vsechny_pohyby(self) -> list[Pohyb]:
        return list(self._pohyby)

    # --- platby
    def platba_podle_dokladu(self, skolka_id: str, doklad: str) -> Platba | None:
        for s, p, _ in self._platby.values():
            if s == skolka_id and doklad and p.doklad == doklad:
                return p
        return None

    def uloz_platbu(self, skolka_id: str, p: Platba, dite_id: str | None) -> None:
        self._platby[p.id] = (skolka_id, p, dite_id)

    def nesparovane(self, skolka_id: str) -> list[NesparovanaPlatba]:
        return [n for s, n in self._nespar.values() if s == skolka_id and not n.vyreseno]

    def uloz_nesparovanou(self, skolka_id: str, n: NesparovanaPlatba) -> None:
        self._nespar[n.platba.id] = (skolka_id, n)

    def oznac_vyresenou(self, platba_id: str, dite_id: str) -> None:
        s, n = self._nespar[platba_id]
        n.vyreseno = True
        s2, p, _ = self._platby[platba_id]
        self._platby[platba_id] = (s2, p, dite_id)

    def zapis_upominku(self, dite_id: str, obdobi: str, kanal: str) -> None:
        self.upominky.append((dite_id, obdobi, kanal))
