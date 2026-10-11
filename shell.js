/* =============================================================================
   Skořápka — spustí desku třídy a nic jiného nedělá
   -----------------------------------------------------------------------------
   Stejný princip jako v LifeOS: obrazovky jsou desky z plátna „Školka —
   hlavní stránka třídy“ a spouští se beze změny přes dc.js.

   Desky jsou tři: Trida.dc.html (tablet učitelky, #trida),
   Reditel.dc.html (počítač ředitelky — kartotéka, učitelé, matrika, #reditel)
   a Jidelna.dc.html (počítač v kuchyni — jídelníček, alergeny, diety, #jidelna).
   V desce třídy jsou docházka, teplota,
   „není mu dobře“, úraz i poznámka vrstvy uvnitř ní — musí sdílet
   jeden stav dětí, jinak by se zápis teploty neukázal v kartě nahoře
   ani na dlaždici dítěte. Mapa DESKY je tu proto, aby šlo další desky
   (třeba nastavení třídy) přidat stejně jako v LifeOS.
   ============================================================================= */

'use strict';

const DESKY = {
  'Prihlaseni.dc.html': 'prihlaseni',
  'Trida.dc.html': 'trida',
  'Reditel.dc.html': 'reditel',
  'Jidelna.dc.html': 'jidelna',
};
/* Na jaký rozměr je která deska nakreslená. Menší okno = deska se celá
   zmenší, aby se vešla; větší okno = roztáhne se. Pod 60 % se už dál
   nezmenšuje (text by byl nečitelný) a okno se dá posunout. */
const ROZMER = {
  prihlaseni: [1194, 834],
  trida: [1194, 834],
  reditel: [1440, 900],
  jidelna: [1440, 900],
};
const MIN_ZOOM = 0.6;
let aktualni = null;

function prizpusob() {
  const r = ROZMER[aktualni] || [1194, 834];
  const vw = window.innerWidth, vh = window.innerHeight;
  const z = Math.max(MIN_ZOOM, Math.min(1, vw / r[0], vh / r[1]));
  koren.style.setProperty('--z', String(z));
  koren.style.setProperty('--w', Math.max(vw / z, z === MIN_ZOOM ? r[0] : 0) + 'px');
  koren.style.setProperty('--h', Math.max(vh / z, z === MIN_ZOOM ? r[1] : 0) + 'px');
  document.documentElement.style.overflow = z === MIN_ZOOM ? 'auto' : 'hidden';
  document.body.style.overflow = z === MIN_ZOOM ? 'auto' : 'hidden';
}
window.addEventListener('resize', prizpusob);

const PODLE_JMENA = Object.fromEntries(Object.entries(DESKY).map(([s, k]) => [k, s]));

/* =============================================================================
   Účty a přístupy
   -----------------------------------------------------------------------------
   Každý účet vidí jen své desky:
   - vedení (ředitelka, zástupkyně, hospodářka) → ředitelna, webová aplikace;
     ředitelka má navíc jídelnu, zástupkyně, která i učí, svůj tablet,
   - jídelna → jen jídelna,
   - učitelka → jen tablet své třídy.
   Ve zkušebním provozu jsou účty tady a heslo se nekontroluje. V ostrém
   provozu je nahradí přihlášení přes Supabase (tabulka uzivatele, role_t
   v supabase/schema.sql) — desky se nemění, čtou jen window.SkolkaUcet.
   ============================================================================= */
const UCTY = [
  { id: 'reditelka', jmeno: 'Ivana Pokorná', role: 'ředitelka', email: 'reditelka@ms-slunicko.cz', skupina: 'Vedení školky', desky: ['reditel', 'jidelna'], pravo: 'reditelka' },
  { id: 'zastupkyne', jmeno: 'Petra Horáková', role: 'zástupkyně ředitelky', email: 'horakova@ms-slunicko.cz', skupina: 'Vedení školky', desky: ['reditel', 'trida'], pravo: 'reditelka', trida: 'slunicka' },
  { id: 'hospodarka', jmeno: 'Hana Veselá', role: 'hospodářka', email: 'hospodarka@ms-slunicko.cz', skupina: 'Vedení školky', desky: ['reditel'], pravo: 'hospodarka' },
  { id: 'vedouci-sj', jmeno: 'Jaroslava Benešová', role: 'vedoucí školní jídelny', email: 'jidelna@ms-slunicko.cz', skupina: 'Školní jídelna', desky: ['jidelna'] },
  { id: 'kucharka', jmeno: 'Marie Dvořáková', role: 'hlavní kuchařka', email: 'dvorakova@ms-slunicko.cz', skupina: 'Školní jídelna', desky: ['jidelna'] },
  { id: 'u-slunicka', jmeno: 'Alena Benešová', role: 'učitelka · Sluníčka', email: 'benesova@ms-slunicko.cz', skupina: 'Učitelky', desky: ['trida'], trida: 'slunicka' },
  { id: 'u-berusky', jmeno: 'Jana Králová', role: 'učitelka · Berušky', email: 'kralova@ms-slunicko.cz', skupina: 'Učitelky', desky: ['trida'], trida: 'berusky' },
  { id: 'u-motylci', jmeno: 'Lucie Malá', role: 'učitelka · Motýlci', email: 'mala@ms-slunicko.cz', skupina: 'Učitelky', desky: ['trida'], trida: 'motylci' },
];
const NAZEV_DESKY = { reditel: 'Ředitelna', jidelna: 'Jídelna', trida: 'Tablet třídy' };
const KLIC_UCTU = 'skolka-prihlaseni-v1';

function nactiUcet() {
  let id = null;
  try { id = localStorage.getItem(KLIC_UCTU); } catch (e) { id = null; }
  if (!id) id = window.__ucetBezUloziste || null;
  return UCTY.find((u) => u.id === id) || null;
}

window.SkolkaUcet = {
  ucty: UCTY,
  nazevDesky: NAZEV_DESKY,
  aktualni: nactiUcet,
  muze: (klic) => { const u = nactiUcet(); return !!u && u.desky.includes(klic); },
  prihlas(id) {
    const u = UCTY.find((x) => x.id === id);
    if (!u) return false;
    try { localStorage.setItem(KLIC_UCTU, u.id); } catch (e) { /* bez úložiště jen do zavření */ }
    window.__ucetBezUloziste = u.id;
    otevri(u.desky[0]);
    return true;
  },
  odhlas() {
    try { localStorage.removeItem(KLIC_UCTU); } catch (e) { /* nic */ }
    window.__ucetBezUloziste = null;
    otevri('prihlaseni');
  },
  otevri: (klic) => otevri(klic),
};

/* Bez adresy (ikona na ploše) se otevře deska, kde člověk byl naposledy —
   zástupkyně na tabletu tak skončí v tabletu, ne v ředitelně. */
function posledni() { try { return localStorage.getItem('skolka-posledni-deska'); } catch (e) { return null; } }

function kamSmi(klic) {
  const u = nactiUcet();
  if (klic === 'prihlaseni') { const p = posledni(); return u ? (p && u.desky.includes(p) ? p : u.desky[0]) : 'prihlaseni'; }
  if (!u) return 'prihlaseni';
  return u.desky.includes(klic) ? klic : u.desky[0];
}

const koren = document.getElementById('deska');
const nacitam = document.getElementById('nacitam');
const chybaEl = document.getElementById('chyba');

const mezipamet = new Map();

async function zdroj(soubor) {
  if (mezipamet.has(soubor)) return mezipamet.get(soubor);
  const o = await fetch(soubor, { cache: 'no-cache' });
  if (!o.ok) throw new Error(`${soubor}: ${o.status}`);
  const t = await o.text();
  mezipamet.set(soubor, t);
  return t;
}

let prepinam = false;

async function otevri(chtene, zHashe) {
  const klic = kamSmi(chtene);
  const soubor = PODLE_JMENA[klic];
  if (!soubor || prepinam) return;
  prepinam = true;
  try {
    chybaEl.hidden = true;
    nacitam.hidden = false;
    const t = await zdroj(soubor);
    aktualni = klic;
    prizpusob();
    window.DC.pripojDesku(t, koren, soubor);
    nacitam.hidden = true;
    if (!zHashe || klic !== chtene) history.replaceState(null, '', '#' + klic);
    if (klic !== 'prihlaseni') { try { localStorage.setItem('skolka-posledni-deska', klic); } catch (e) { /* nic */ } }
  } catch (e) {
    nacitam.hidden = true;
    chybaEl.hidden = false;
    chybaEl.textContent = 'Obrazovku se nepodařilo otevřít.\n\n' + (e && e.stack ? e.stack : e);
  } finally {
    prepinam = false;
  }
}

document.addEventListener('click', (e) => {
  const a = e.target.closest && e.target.closest('a[href]');
  if (!a) return;
  const href = a.getAttribute('href') || '';
  if (!href.endsWith('.dc.html')) return;
  e.preventDefault();
  const klic = DESKY[href.replace(/^\.?\//, '')];
  if (klic) otevri(klic);
});

window.addEventListener('hashchange', () => {
  const klic = (location.hash || '').slice(1);
  if (PODLE_JMENA[klic]) otevri(klic, true);
});

const zacatek = (location.hash || '').slice(1);
otevri(PODLE_JMENA[zacatek] ? zacatek : 'prihlaseni', true);

if (navigator.storage && navigator.storage.persist) {
  navigator.storage.persist().catch(() => {});
}

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('sw.js').catch(() => {});
}
