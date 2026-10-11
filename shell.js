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
  'Trida.dc.html': 'trida',
  'Reditel.dc.html': 'reditel',
  'Jidelna.dc.html': 'jidelna',
};
/* Na jaký rozměr je která deska nakreslená. Menší okno = deska se celá
   zmenší, aby se vešla; větší okno = roztáhne se. Pod 60 % se už dál
   nezmenšuje (text by byl nečitelný) a okno se dá posunout. */
const ROZMER = {
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
const VYCHOZI = 'trida';

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

async function otevri(klic, zHashe) {
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
    if (!zHashe) location.hash = '#' + klic;
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
otevri(PODLE_JMENA[zacatek] ? zacatek : VYCHOZI, true);

if (navigator.storage && navigator.storage.persist) {
  navigator.storage.persist().catch(() => {});
}

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('sw.js').catch(() => {});
}
