"""Služby finančního modulu: konto dítěte, předpisy, párování plateb, dlužníci.

Konto (saldo) je účet `dite:<id>` v podvojné knize:
  předpis  … MD dite:<id>    / Dal vynosy:skolkovne | vynosy:stravne
  platba   … MD banka         / Dal dite:<id>
Zůstatek ze strany Dal: kladný = přeplatek (kredit), záporný = dluh.
Úhrady předpisů se z kreditů rozpouštějí od nejstaršího předpisu (FIFO),
takže stav předpisů jde kdykoli spočítat znovu a nemůže se rozejít s kontem.
"""
from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import date
from decimal import Decimal

from .model import (Dite, NesparovanaPlatba, Platba, Pohyb, Predpis, StavPredpisu, VysledekParovani)
from .penize import NULA, kc
from .predpisy import nazev_obdobi, rozsah_obdobi, spocti_predpis
from .uloziste import Uloziste

UCET_BANKA = "banka"
UCET_VYNOS = {"skolkovne": "vynosy:skolkovne", "stravne": "vynosy:stravne"}


def ucet_ditete(dite_id: str) -> str:
    return f"dite:{dite_id}"


def _id() -> str:
    return uuid.uuid4().hex


@dataclass
class Finance:
    db: Uloziste
    skolka_id: str

    # ---------------------------------------------------------------- konto
    def saldo(self, dite_id: str) -> Decimal:
        return self.db.saldo(ucet_ditete(dite_id))

    def k_uhrade(self, dite_id: str) -> Decimal:
        """Kolik má rodič teď zaplatit: dluh na kontě (předpisy minus přeplatek)."""
        return kc(max(NULA, -self.saldo(dite_id)))

    def vyrovnej(self, dite_id: str) -> list[Predpis]:
        """Rozpustí kredity konta do předpisů od nejstaršího a uloží jejich stav."""
        kredity = kc(sum((p.castka for p in self.db.pohyby(ucet_ditete(dite_id)) if p.dal == ucet_ditete(dite_id)), NULA))
        zmenene = []
        for p in self.db.predpisy(dite_id):
            uhrazeno = kc(min(p.castka, max(NULA, kredity)))
            kredity -= uhrazeno
            stav = (StavPredpisu.ZAPLACENO if uhrazeno >= p.castka
                    else StavPredpisu.CASTECNE if uhrazeno > 0 else StavPredpisu.OTEVRENO)
            if uhrazeno != p.uhrazeno or stav != p.stav:
                p.uhrazeno, p.stav = uhrazeno, stav
                self.db.uloz_predpis(p)
                zmenene.append(p)
        return zmenene

    # ------------------------------------------------------------ předpisy
    def vystav_predpis(self, dite: Dite, obdobi: str) -> Predpis | None:
        """Vystaví předpis za měsíc a zaúčtuje ho. Opakované spuštění nic nezdvojí."""
        with self.db.transakce():
            return self._vystav(dite, obdobi)

    def _vystav(self, dite: Dite, obdobi: str) -> Predpis | None:
        if self.db.predpis(dite.id, obdobi):
            return None
        nast = self.db.nastaveni(self.skolka_id)
        od, do = rozsah_obdobi(obdobi)
        p = spocti_predpis(dite, obdobi, self.db.dochazka(dite.id, od, do), nast, _id())
        self.db.uloz_predpis(p)
        for pol in p.polozky:
            if pol.castka > 0:
                self.db.zapis_pohyb(Pohyb(_id(), do, ucet_ditete(dite.id), UCET_VYNOS[pol.druh], pol.castka,
                                          f"{pol.popis} — {dite.cele_jmeno}", p.id))
        if p.castka == 0:
            p.stav = StavPredpisu.ZAPLACENO
            self.db.uloz_predpis(p)
        self.vyrovnej(dite.id)
        return self.db.predpis(dite.id, obdobi)

    def vystav_mesic(self, obdobi: str) -> list[Predpis]:
        """Předpisy pro všechny aktivní děti školky (úloha na konci měsíce)."""
        out = []
        for d in self.db.deti(self.skolka_id):
            if d.aktivni:
                p = self.vystav_predpis(d, obdobi)
                if p:
                    out.append(p)
        return out

    def zprava_platby(self, dite: Dite, obdobi: str) -> str:
        return f"Skolkovne/Stravne {nazev_obdobi(obdobi)} - {dite.cele_jmeno}"

    # -------------------------------------------------------------- platby
    def zpracuj_platbu(self, platba: Platba) -> VysledekParovani:
        """Párovací engine: najde dítě podle VS a vyrovná předpisy."""
        with self.db.transakce():
            return self._zpracuj(platba)

    def _zpracuj(self, platba: Platba) -> VysledekParovani:
        platba.castka = kc(platba.castka)
        if platba.doklad and self.db.platba_podle_dokladu(self.skolka_id, platba.doklad):
            return VysledekParovani(platba.id, None, "duplicita", platba.castka)
        if platba.castka <= 0:
            raise ValueError("Párují se jen příchozí platby s kladnou částkou.")
        dite = self.db.dite_podle_vs(self.skolka_id, platba.vs)
        if dite is None:
            self.db.uloz_platbu(self.skolka_id, platba, None)
            self.db.uloz_nesparovanou(self.skolka_id, NesparovanaPlatba(platba, "VS nepatří žádnému dítěti" if platba.vs else "Platba nemá VS"))
            return VysledekParovani(platba.id, None, "nesparovano", platba.castka)
        return self._pripis(platba, dite)

    def _pripis(self, platba: Platba, dite: Dite) -> VysledekParovani:
        dluh = self.k_uhrade(dite.id)
        self.db.uloz_platbu(self.skolka_id, platba, dite.id)
        self.db.zapis_pohyb(Pohyb(_id(), platba.datum, UCET_BANKA, ucet_ditete(dite.id), platba.castka,
                                  f"Platba VS {platba.vs or '—'} — {dite.cele_jmeno}", platba.id))
        zmenene = [p.id for p in self.vyrovnej(dite.id)]
        if platba.castka == dluh:
            vysl, prepl, zbyva = "presne", NULA, NULA
        elif platba.castka > dluh:
            vysl, prepl, zbyva = "preplatek", kc(platba.castka - dluh), NULA
        else:
            vysl, prepl, zbyva = "nedoplatek", NULA, kc(dluh - platba.castka)
        return VysledekParovani(platba.id, dite.id, vysl, platba.castka, prepl, zbyva, zmenene)

    def sparuj_rucne(self, platba_id: str, dite_id: str) -> VysledekParovani:
        """Hospodářka přiřadí nespárovanou platbu dítěti."""
        with self.db.transakce():
            return self._sparuj(platba_id, dite_id)

    def _sparuj(self, platba_id: str, dite_id: str) -> VysledekParovani:
        n = next((x for x in self.db.nesparovane(self.skolka_id) if x.platba.id == platba_id), None)
        if n is None:
            raise KeyError("Nespárovaná platba neexistuje nebo už je vyřešená.")
        dite = self.db.dite(dite_id)
        if dite is None:
            raise KeyError("Dítě neexistuje.")
        vysl = self._pripis(n.platba, dite)
        self.db.oznac_vyresenou(platba_id, dite_id)
        return vysl

    # ------------------------------------------------------- dlužníci, upomínky
    def dluznici(self, k_datu: date | None = None) -> list[dict]:
        """Děti se záporným kontem, které mají aspoň jeden předpis po splatnosti."""
        k_datu = k_datu or date.today()
        out = []
        for d in self.db.deti(self.skolka_id):
            dluh = self.k_uhrade(d.id)
            if dluh <= 0:
                continue
            po_splatnosti = [p for p in self.db.predpisy(d.id) if p.stav != StavPredpisu.ZAPLACENO and p.splatnost < k_datu]
            if po_splatnosti:
                out.append({"dite": d, "dluh": dluh, "predpisy": po_splatnosti,
                            "nejstarsi_splatnost": min(p.splatnost for p in po_splatnosti)})
        return sorted(out, key=lambda x: (x["nejstarsi_splatnost"], x["dite"].prijmeni))

    def posli_upominky(self, notifikator, k_datu: date | None = None) -> list[dict]:
        """Hromadné upomínky dlužníkům. `notifikator.posli(dite, dluh, predpisy)` vrátí kanál ("push"/"email")."""
        odeslano = []
        for x in self.dluznici(k_datu):
            kanal = notifikator.posli(x["dite"], x["dluh"], x["predpisy"])
            for p in x["predpisy"]:
                self.db.zapis_upominku(x["dite"].id, p.obdobi, kanal)
            odeslano.append({"dite_id": x["dite"].id, "dluh": x["dluh"], "kanal": kanal})
        return odeslano
