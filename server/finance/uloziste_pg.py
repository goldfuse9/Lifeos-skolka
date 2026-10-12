"""Úložiště nad PostgreSQL (tabulky z supabase/schema.sql).

psycopg vrací NUMERIC rovnou jako Decimal, takže float se do výpočtů nedostane.
Zůstatek konta (tabulka `konta`) drží trigger z každého zápisu do ucetni_pohyby.
"""
from __future__ import annotations

from datetime import date
from decimal import Decimal

import psycopg
from psycopg.rows import dict_row

from .model import (Dite, DochazkaDen, Nastaveni, NesparovanaPlatba, Platba, Pohyb, Polozka, Predpis,
                    SchemaVS, StavPredpisu)
from .penize import NULA, kc
from .vs import normalizuj


class PgUloziste:
    def __init__(self, conn: psycopg.Connection):
        self.c = conn
        self.c.row_factory = dict_row

    @classmethod
    def pripoj(cls, dsn: str) -> "PgUloziste":
        return cls(psycopg.connect(dsn, autocommit=True))

    def transakce(self):
        """Vše uvnitř proběhne celé, nebo vůbec (vnořené volání = savepoint)."""
        return self.c.transaction()

    def _q(self, sql: str, args: tuple = ()) -> list[dict]:
        with self.c.cursor() as cur:
            cur.execute(sql, args)
            return cur.fetchall() if cur.description else []

    # ------------------------------------------------------------ školka a děti
    def nastaveni(self, skolka_id: str) -> Nastaveni:
        r = self._q("select s.nazev, f.* from financni_nastaveni f join skoly s on s.id = f.skola_id where f.skola_id = %s", (skolka_id,))
        if not r:
            raise KeyError("Školka nemá finanční nastavení.")
        r = r[0]
        sazby = {x["kategorie"]: x["cena"] for x in self._q("select kategorie, cena from sazby_stravneho where skola_id = %s", (skolka_id,))}
        return Nastaveni(skolka_id=str(r["skola_id"]), nazev=r["nazev"], ucet=r["ucet"], skolkovne=r["skolkovne"], stravne=sazby,
                         omluva_dni_predem=r["omluva_dni_predem"], omluva_do=r["omluva_do"], splatnost_den=r["splatnost_den"],
                         vs_schema=SchemaVS(r["vs_schema"]), vs_prefix=r["vs_prefix"], vs_delka=r["vs_delka"])

    def uloz_nastaveni(self, n: Nastaveni) -> None:
        with self.c.transaction():
            self._q("""insert into financni_nastaveni (skola_id, ucet, skolkovne, omluva_dni_predem, omluva_do, splatnost_den, vs_schema, vs_prefix, vs_delka)
                       values (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                       on conflict (skola_id) do update set ucet = excluded.ucet, skolkovne = excluded.skolkovne,
                         omluva_dni_predem = excluded.omluva_dni_predem, omluva_do = excluded.omluva_do, splatnost_den = excluded.splatnost_den,
                         vs_schema = excluded.vs_schema, vs_prefix = excluded.vs_prefix, vs_delka = excluded.vs_delka""",
                    (n.skolka_id, n.ucet, n.skolkovne, n.omluva_dni_predem, n.omluva_do, n.splatnost_den, n.vs_schema.value, n.vs_prefix, n.vs_delka))
            for kat, cena in n.stravne.items():
                self._q("""insert into sazby_stravneho (skola_id, kategorie, cena) values (%s, %s, %s)
                           on conflict (skola_id, kategorie) do update set cena = excluded.cena""", (n.skolka_id, kat, cena))

    @staticmethod
    def _dite(r: dict) -> Dite:
        return Dite(str(r["id"]), r["jmeno"], r["prijmeni"], r["datum_narozeni"], r["variabilni_symbol"] or "",
                    r["osvobozen_od_skolkovneho"], r["ukonceno"] is None)

    def deti(self, skolka_id: str) -> list[Dite]:
        return [self._dite(r) for r in self._q("select * from deti where skola_id = %s order by prijmeni, jmeno", (skolka_id,))]

    def dite(self, dite_id: str) -> Dite | None:
        r = self._q("select * from deti where id = %s", (dite_id,))
        return self._dite(r[0]) if r else None

    def dite_podle_vs(self, skolka_id: str, vs: str) -> Dite | None:
        n = normalizuj(vs)
        if not n:
            return None
        r = self._q("select * from deti where skola_id = %s and ltrim(variabilni_symbol, '0') = %s", (skolka_id, n))
        return self._dite(r[0]) if r else None

    def uloz_dite(self, skolka_id: str, d: Dite) -> None:
        self._q("update deti set variabilni_symbol = %s, osvobozen_od_skolkovneho = %s where id = %s and skola_id = %s",
                (d.vs or None, d.osvobozen_od_skolkovneho, d.id, skolka_id))

    def dochazka(self, dite_id: str, od: date, do: date) -> list[DochazkaDen]:
        return [DochazkaDen(str(r["dite_id"]), r["den"], r["strava_prihlasena"], r["omluva_zadana"])
                for r in self._q("select * from dochazka where dite_id = %s and den between %s and %s order by den", (dite_id, od, do))]

    # ------------------------------------------------------------- předpisy
    def _predpis(self, r: dict) -> Predpis:
        pol = [Polozka(x["druh"], x["popis"], x["mnozstvi"], x["cena"], x["castka"])
               for x in self._q("select * from predpis_polozky where predpis_id = %s order by poradi", (r["id"],))]
        return Predpis(str(r["id"]), str(r["dite_id"]), r["obdobi"], pol, r["castka"], r["splatnost"], r["uhrazeno"],
                       StavPredpisu(r["stav"]), r["vystaveno"])

    def predpisy(self, dite_id: str) -> list[Predpis]:
        return [self._predpis(r) for r in self._q("select * from predpisy where dite_id = %s order by splatnost, obdobi", (dite_id,))]

    def predpis(self, dite_id: str, obdobi: str) -> Predpis | None:
        r = self._q("select * from predpisy where dite_id = %s and obdobi = %s", (dite_id, obdobi))
        return self._predpis(r[0]) if r else None

    def uloz_predpis(self, p: Predpis) -> None:
        with self.c.transaction():
            novy = not self._q("select 1 from predpisy where id = %s", (p.id,))
            self._q("""insert into predpisy (id, dite_id, obdobi, castka, uhrazeno, stav, splatnost, vystaveno)
                       values (%s, %s, %s, %s, %s, %s, %s, coalesce(%s, current_date))
                       on conflict (id) do update set uhrazeno = excluded.uhrazeno, stav = excluded.stav""",
                    (p.id, p.dite_id, p.obdobi, p.castka, p.uhrazeno, p.stav.value, p.splatnost, p.vystaveno))
            if novy:
                for i, x in enumerate(p.polozky):
                    self._q("insert into predpis_polozky (predpis_id, poradi, druh, popis, mnozstvi, cena, castka) values (%s, %s, %s, %s, %s, %s, %s)",
                            (p.id, i, x.druh, x.popis, x.mnozstvi, x.cena, x.castka))

    # -------------------------------------------------------- účetní kniha
    def _skola_ditete(self, ucet: str) -> str | None:
        if ucet.startswith("dite:"):
            r = self._q("select skola_id from deti where id = %s", (ucet[5:],))
            return str(r[0]["skola_id"]) if r else None
        return None

    def zapis_pohyb(self, p: Pohyb) -> None:
        skola = self._skola_ditete(p.md) or self._skola_ditete(p.dal)
        if not skola:
            raise ValueError("Pohyb musí jít na konto dítěte.")
        self._q("insert into ucetni_pohyby (id, skola_id, datum, md, dal, castka, popis, doklad) values (%s, %s, %s, %s, %s, %s, %s, %s)",
                (p.id, skola, p.datum, p.md, p.dal, p.castka, p.popis, p.doklad))

    def pohyby(self, ucet: str) -> list[Pohyb]:
        return [Pohyb(str(r["id"]), r["datum"], r["md"], r["dal"], r["castka"], r["popis"], r["doklad"])
                for r in self._q("select * from ucetni_pohyby where md = %s or dal = %s order by datum, vytvoreno", (ucet, ucet))]

    def saldo(self, ucet: str) -> Decimal:
        if ucet.startswith("dite:"):
            r = self._q("select saldo from konta where dite_id = %s", (ucet[5:],))
            return kc(r[0]["saldo"]) if r else NULA
        r = self._q("select coalesce(sum(case when dal = %s then castka else -castka end), 0) as s from ucetni_pohyby where md = %s or dal = %s", (ucet, ucet, ucet))
        return kc(r[0]["s"])

    # --------------------------------------------------------------- platby
    def platba_podle_dokladu(self, skolka_id: str, doklad: str) -> Platba | None:
        if not doklad:
            return None
        r = self._q("select * from platby where skola_id = %s and doklad = %s", (skolka_id, doklad))
        return self._platba(r[0]) if r else None

    @staticmethod
    def _platba(r: dict) -> Platba:
        return Platba(str(r["id"]), r["datum"], r["castka"], r["vs"], r["protiucet"], r["nazev"], r["zdroj"], r["doklad"])

    def uloz_platbu(self, skolka_id: str, p: Platba, dite_id: str | None) -> None:
        self._q("""insert into platby (id, skola_id, datum, castka, vs, protiucet, nazev, zdroj, doklad, dite_id)
                   values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                   on conflict (id) do update set dite_id = excluded.dite_id""",
                (p.id, skolka_id, p.datum, p.castka, p.vs, p.protiucet, p.nazev, p.zdroj, p.doklad, dite_id))

    def nesparovane(self, skolka_id: str) -> list[NesparovanaPlatba]:
        return [NesparovanaPlatba(self._platba(r), r["duvod"], r["vyreseno"])
                for r in self._q("""select p.*, n.duvod, n.vyreseno from nesparovane_platby n join platby p on p.id = n.platba_id
                                    where p.skola_id = %s and not n.vyreseno order by p.datum""", (skolka_id,))]

    def uloz_nesparovanou(self, skolka_id: str, n: NesparovanaPlatba) -> None:
        self._q("insert into nesparovane_platby (platba_id, duvod) values (%s, %s) on conflict do nothing", (n.platba.id, n.duvod))

    def oznac_vyresenou(self, platba_id: str, dite_id: str) -> None:
        with self.c.transaction():
            self._q("update nesparovane_platby set vyreseno = true, vyreseno_kdy = now() where platba_id = %s", (platba_id,))
            self._q("update platby set dite_id = %s where id = %s", (dite_id, platba_id))

    def zapis_upominku(self, dite_id: str, obdobi: str, kanal: str) -> None:
        self._q("insert into upominky (dite_id, obdobi, kanal) values (%s, %s, %s)", (dite_id, obdobi, kanal))
