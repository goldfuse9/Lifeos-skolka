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
   Přístupy
   -----------------------------------------------------------------------------
   Přístupy vytváří jen ředitelka (Ředitelna → Přístupy). Jeden člověk = jeden
   přístup; kam se dostane, určuje jeho role:
   - ředitelka → ředitelna + jídelna,
   - zástupkyně → ředitelna + tablet své třídy,
   - hospodářka → ředitelna (jen peníze, děti, docházka, zprávy, archiv),
   - vedoucí jídelny, kuchařka → jen jídelna,
   - učitelka, asistent → jen tablet své třídy.
   Na přihlašovací obrazovce se vybírá Ředitelna / Třída / Jídelna; když tam
   účet nepatří, přihlášení neprojde.
   Ve zkušebním provozu jsou přístupy v úložišti prohlížeče a hesla jako
   otisk SHA-256 (nikdy ne v čitelné podobě). V ostrém provozu je nahradí
   Supabase Auth (supabase/schema.sql) — desky čtou jen window.SkolkaUcet.
   ============================================================================= */
const ROLE = {
  reditelka:  { nazev: 'ředitelka', desky: ['reditel', 'jidelna'], pravo: 'reditelka' },
  zastupce:   { nazev: 'zástupkyně ředitelky', desky: ['reditel', 'trida'], pravo: 'reditelka', trida: true },
  hospodarka: { nazev: 'hospodářka', desky: ['reditel'], pravo: 'hospodarka' },
  ucitelka:   { nazev: 'učitelka', desky: ['trida'], trida: true },
  asistent:   { nazev: 'asistent/ka pedagoga', desky: ['trida'], trida: true },
  vedouci_sj: { nazev: 'vedoucí školní jídelny', desky: ['jidelna'] },
  kucharka:   { nazev: 'kuchařka', desky: ['jidelna'] },
};
const TRIDY = { slunicka: 'Sluníčka', berusky: 'Berušky', motylci: 'Motýlci' };
const NAZEV_DESKY = { reditel: 'Ředitelna', jidelna: 'Jídelna', trida: 'Třída' };
const KLIC_UCTU = 'skolka-prihlaseni-v1';
const KLIC_PRISTUPU = 'skolka-pristupy-v1';

/* Ukázkové přístupy, heslo všech je „skolka“. */
const UKAZKA = [
  ['reditelka', 'Ivana Pokorná', 'reditelka', 'reditelka@ms-slunicko.cz', '', 'c6dd20211789b9259770e984a6687744dd1ce30b8916beaaacaa4e86ca4b61e6'],
  ['zastupkyne', 'Petra Horáková', 'zastupce', 'horakova@ms-slunicko.cz', 'slunicka', 'e8df4adad2c30a189d232db8a848ff269e1a46499be24bbce9097aec5e28881d'],
  ['hospodarka', 'Hana Veselá', 'hospodarka', 'hospodarka@ms-slunicko.cz', '', 'c69b3bc888b023eb061947bcbb1af939a428e1b5c53d16be440a46b3a1d90653'],
  ['vedouci-sj', 'Jaroslava Benešová', 'vedouci_sj', 'jidelna@ms-slunicko.cz', '', '29072fee82ec5a85b1048cdcaeb5b61ce95a3878214239deb2d97eea7e7cca40'],
  ['kucharka', 'Marie Dvořáková', 'kucharka', 'dvorakova@ms-slunicko.cz', '', 'fc28a2d2e9e707c43001bf747f9e3784d477e50d058ac7fec980e9691185da15'],
  ['u-slunicka', 'Alena Benešová', 'ucitelka', 'benesova@ms-slunicko.cz', 'slunicka', '9fd8d104284ca19fbaf10f339116a84450cea784afb2202e98ebcdc23dd1283f'],
  ['u-berusky', 'Jana Králová', 'ucitelka', 'kralova@ms-slunicko.cz', 'berusky', '17c480db7e478818928837b30db5f6386674c4ece9f19e68e80d9e81c1cac9b5'],
  ['u-motylci', 'Lucie Malá', 'ucitelka', 'mala@ms-slunicko.cz', 'motylci', 'cb1674b0eed36f27138a94771479dc5d9f84f09bd5f9a14706934533e66f511d'],
].map(([id, jmeno, kod, email, trida, otisk]) => ({ id, jmeno, kod, email, trida, otisk, aktivni: true, vytvoreno: '2026-09-01', posledni: '' }));

let pameti = null; // když prohlížeč nedovolí úložiště
function nactiPristupy() {
  let raw = null;
  try { raw = localStorage.getItem(KLIC_PRISTUPU); } catch (e) { raw = null; }
  if (raw) { try { return JSON.parse(raw); } catch (e) { /* poškozené — začneme znovu */ } }
  return pameti || UKAZKA.map((u) => Object.assign({}, u));
}
function ulozPristupy(list) {
  pameti = list;
  try { localStorage.setItem(KLIC_PRISTUPU, JSON.stringify(list)); } catch (e) { /* jen v paměti */ }
}
/* Přístup → účet pro desky (role jako popisek, desky, právo, třída). */
function ucetZ(p) {
  const r = ROLE[p.kod] || ROLE.ucitelka;
  return {
    id: p.id, jmeno: p.jmeno, email: p.email, kod: p.kod, trida: p.trida || '',
    role: r.nazev + (r.trida && p.trida && TRIDY[p.trida] ? ' · ' + TRIDY[p.trida] : ''),
    desky: r.desky.slice(), pravo: r.pravo || '',
  };
}
async function otisk(email, heslo) {
  const data = new TextEncoder().encode('skolka|' + email.trim().toLowerCase() + '|' + heslo);
  const h = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(h)).map((b) => b.toString(16).padStart(2, '0')).join('');
}
function noveHeslo() {
  const a = 'abcdefghjkmnpqrstuvwxyz', c = '23456789';
  const r = (s) => s[Math.floor(Math.random() * s.length)];
  return r(a) + r(a) + r(a) + r(a) + '-' + r(c) + r(c) + r(c) + r(c);
}

function nactiUcet() {
  let id = null;
  try { id = localStorage.getItem(KLIC_UCTU); } catch (e) { id = null; }
  if (!id) id = window.__ucetBezUloziste || null;
  const p = nactiPristupy().find((u) => u.id === id && u.aktivni);
  return p ? ucetZ(p) : null;
}

window.SkolkaUcet = {
  role: ROLE, tridy: TRIDY, nazevDesky: NAZEV_DESKY,
  aktualni: nactiUcet,
  muze: (klic) => { const u = nactiUcet(); return !!u && u.desky.includes(klic); },
  /* Přihlašovací obrazovka: oblast (reditel / trida / jidelna), e-mail, heslo. */
  async prihlas(oblast, email, heslo) {
    const mail = String(email || '').trim().toLowerCase();
    const list = nactiPristupy();
    const p = list.find((u) => u.email.toLowerCase() === mail);
    if (!p || !heslo || (await otisk(mail, heslo)) !== p.otisk) return { ok: false, chyba: 'E-mail nebo heslo nesedí.' };
    if (!p.aktivni) return { ok: false, chyba: 'Přístup je zablokovaný. Obraťte se na ředitelku.' };
    const u = ucetZ(p);
    if (!u.desky.includes(oblast)) {
      return { ok: false, chyba: 'Tento přístup do části „' + NAZEV_DESKY[oblast] + '“ nevede. Patří do: ' + u.desky.map((d) => NAZEV_DESKY[d]).join(', ') + '.' };
    }
    p.posledni = new Date().toISOString();
    ulozPristupy(list);
    try { localStorage.setItem(KLIC_UCTU, p.id); localStorage.setItem('skolka-oblast', oblast); } catch (e) { /* jen do zavření */ }
    window.__ucetBezUloziste = p.id;
    otevri(oblast);
    return { ok: true };
  },
  odhlas() {
    try { localStorage.removeItem(KLIC_UCTU); } catch (e) { /* nic */ }
    window.__ucetBezUloziste = null;
    otevri('prihlaseni');
  },
  otevri: (klic) => otevri(klic),
  posledniOblast() { try { return localStorage.getItem('skolka-oblast') || ''; } catch (e) { return ''; } },

  /* ---- správa přístupů: jen ředitelka ---- */
  smiSpravovat() { const u = nactiUcet(); return !!u && u.kod === 'reditelka'; },
  pristupy() { return nactiPristupy().map((p) => Object.assign(ucetZ(p), { aktivni: p.aktivni, vytvoreno: p.vytvoreno, posledni: p.posledni })); },
  /* Vrátí { ok, heslo } — heslo se ukáže jen jednou. */
  async vytvor(udaje) {
    if (!this.smiSpravovat()) return { ok: false, chyba: 'Přístupy vytváří jen ředitelka.' };
    const list = nactiPristupy();
    const email = String(udaje.email || '').trim().toLowerCase();
    const jmeno = String(udaje.jmeno || '').trim();
    if (!jmeno) return { ok: false, chyba: 'Chybí jméno.' };
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return { ok: false, chyba: 'E-mail nevypadá správně.' };
    if (!ROLE[udaje.kod]) return { ok: false, chyba: 'Vyberte roli.' };
    if (ROLE[udaje.kod].trida && !TRIDY[udaje.trida]) return { ok: false, chyba: 'Vyberte třídu.' };
    if (list.some((u) => u.email.toLowerCase() === email)) return { ok: false, chyba: 'Tento e-mail už přístup má.' };
    if (list.some((u) => u.jmeno.toLowerCase() === jmeno.toLowerCase())) return { ok: false, chyba: jmeno + ' už přístup má — jeden člověk má jen jeden přístup.' };
    const heslo = noveHeslo();
    list.push({ id: 'u' + Date.now().toString(36), jmeno, kod: udaje.kod, email, trida: ROLE[udaje.kod].trida ? udaje.trida : '',
      otisk: await otisk(email, heslo), aktivni: true, vytvoreno: new Date().toISOString().slice(0, 10), posledni: '' });
    ulozPristupy(list);
    return { ok: true, heslo };
  },
  async noveHeslo(id) {
    if (!this.smiSpravovat()) return { ok: false };
    const list = nactiPristupy(), p = list.find((u) => u.id === id);
    if (!p) return { ok: false };
    const heslo = noveHeslo();
    p.otisk = await otisk(p.email, heslo);
    ulozPristupy(list);
    return { ok: true, heslo };
  },
  prepniAktivni(id) {
    if (!this.smiSpravovat()) return false;
    const list = nactiPristupy(), p = list.find((u) => u.id === id);
    const ja = nactiUcet();
    if (!p || (ja && ja.id === id)) return false; // sama sebe nezablokuje
    p.aktivni = !p.aktivni;
    ulozPristupy(list);
    return true;
  },
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
