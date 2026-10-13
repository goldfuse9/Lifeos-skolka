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
  'Admin.dc.html': 'admin',
};
/* Na jaký rozměr je která deska nakreslená. Menší okno = deska se celá
   zmenší, aby se vešla; větší okno = roztáhne se. Pod 60 % se už dál
   nezmenšuje (text by byl nečitelný) a okno se dá posunout. */
const ROZMER = {
  prihlaseni: [1194, 834],
  trida: [1194, 834],
  reditel: [1440, 900],
  jidelna: [1440, 900],
  admin: [1440, 900],
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
  superadmin: { nazev: 'správce LifeOS', desky: ['admin'] },
};
const TRIDY = { slunicka: 'Sluníčka', berusky: 'Berušky', motylci: 'Motýlci' };
const NAZEV_DESKY = { reditel: 'Ředitelna', jidelna: 'Jídelna', trida: 'Třída', admin: 'Správa LifeOS' };
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
  if (window.crypto && crypto.subtle && window.isSecureContext !== false) {
    try {
      const h = await crypto.subtle.digest('SHA-256', data);
      return Array.from(new Uint8Array(h)).map((b) => b.toString(16).padStart(2, '0')).join('');
    } catch (e) { /* níž ruční výpočet */ }
  }
  return sha256(data);
}
/* SHA-256 bez crypto.subtle — prohlížeč ho nedá na stránce bez https
   (třeba když se aplikace otevře z počítače v síti přes http://). */
function sha256(bytes) {
  const K = [0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];
  const H = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19];
  const l = bytes.length, n = ((l + 9 + 63) >> 6) << 6, m = new Uint8Array(n);
  m.set(bytes); m[l] = 0x80;
  const dv = new DataView(m.buffer); dv.setUint32(n - 4, l * 8); dv.setUint32(n - 8, Math.floor(l / 0x20000000));
  const w = new Uint32Array(64), r = (x, k) => (x >>> k) | (x << (32 - k));
  for (let o = 0; o < n; o += 64) {
    for (let i = 0; i < 16; i++) w[i] = dv.getUint32(o + i * 4);
    for (let i = 16; i < 64; i++) {
      const s0 = r(w[i - 15], 7) ^ r(w[i - 15], 18) ^ (w[i - 15] >>> 3), s1 = r(w[i - 2], 17) ^ r(w[i - 2], 19) ^ (w[i - 2] >>> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0;
    }
    let [a, b, c, d, e, f, g, h] = H;
    for (let i = 0; i < 64; i++) {
      const t1 = (h + (r(e, 6) ^ r(e, 11) ^ r(e, 25)) + ((e & f) ^ (~e & g)) + K[i] + w[i]) >>> 0;
      const t2 = ((r(a, 2) ^ r(a, 13) ^ r(a, 22)) + ((a & b) ^ (a & c) ^ (b & c))) >>> 0;
      h = g; g = f; f = e; e = (d + t1) >>> 0; d = c; c = b; b = a; a = (t1 + t2) >>> 0;
    }
    H[0] = (H[0] + a) >>> 0; H[1] = (H[1] + b) >>> 0; H[2] = (H[2] + c) >>> 0; H[3] = (H[3] + d) >>> 0;
    H[4] = (H[4] + e) >>> 0; H[5] = (H[5] + f) >>> 0; H[6] = (H[6] + g) >>> 0; H[7] = (H[7] + h) >>> 0;
  }
  return H.map((x) => x.toString(16).padStart(8, '0')).join('');
}
function noveHeslo() {
  const a = 'abcdefghjkmnpqrstuvwxyz', c = '23456789';
  const r = (s) => s[Math.floor(Math.random() * s.length)];
  return r(a) + r(a) + r(a) + r(a) + '-' + r(c) + r(c) + r(c) + r(c);
}

/* Ostrý provoz (server.js + config.js): účet je ze Supabase. */
const SRV = () => (window.SkolkaServer && window.SkolkaServer.zapnuto ? window.SkolkaServer : null);
const SRV_ROLE = { reditelka: 'reditelka', zastupce: 'zastupce', ucitelka: 'ucitelka', hospodarka: 'hospodarka', kucharka: 'kucharka', superadmin: 'superadmin' };
function ucetZeServeru(s) {
  const r = ROLE[SRV_ROLE[s.role] || 'ucitelka'];
  const t = s.tridy[0];
  return {
    id: s.id, jmeno: s.jmeno, email: s.email || '', kod: SRV_ROLE[s.role] || 'ucitelka', trida: t ? t.id : '', tridaNazev: t ? t.nazev : '',
    role: r.nazev + (r.trida && t ? ' · ' + t.nazev : ''), desky: r.desky.filter((d) => d !== 'trida' || !!t), pravo: r.pravo || '',
    server: true, skola: s.skola,
  };
}

function nactiUcet() {
  if (SRV()) { const s = SRV().ucet(); return s ? ucetZeServeru(s) : null; }
  let id = null;
  try { id = localStorage.getItem(KLIC_UCTU); } catch (e) { id = null; }
  if (!id) id = window.__ucetBezUloziste || null;
  const p = nactiPristupy().find((u) => u.id === id && u.aktivni);
  return p ? ucetZ(p) : null;
}

/* Tablet třídy bez dětí nemá co ukázat — místo prázdné desky srozumitelná věta. */
async function prazdnaTrida(u, kam) {
  if (kam !== 'trida' || !SRV() || !u.trida) return null;
  let deti = [];
  try { deti = await SRV().nactiTridu(u.trida); } catch (e) { return null; }
  if (deti.length) return null;
  try { await SRV().odhlas(); } catch (e) { /* nic */ }
  return { ok: false, chyba: 'Účet je v pořádku. Ve třídě ' + (u.tridaNazev || '') + ' ale zatím nejsou žádné děti — tablet se otevře, až je ředitelka do třídy zapíše.' };
}

window.SkolkaUcet = {
  role: ROLE, tridy: TRIDY, nazevDesky: NAZEV_DESKY,
  aktualni: nactiUcet,
  muze: (klic) => { const u = nactiUcet(); return !!u && u.desky.includes(klic); },
  /* Přihlašovací obrazovka: oblast (reditel / trida / jidelna), e-mail, heslo. */
  async prihlas(oblast, email, heslo, kod) {
    const mail = String(email || '').trim().toLowerCase();
    if (SRV()) {
      const r = await SRV().prihlas(mail, heslo, kod);
      if (!r.ok) return r;
      const u = ucetZeServeru(r.ucet);
      if (u.kod === 'superadmin') { otevri('admin'); return { ok: true }; }
      if (!u.desky.includes(oblast)) {
        await SRV().odhlas();
        return { ok: false, chyba: 'Tento přístup do části „' + NAZEV_DESKY[oblast] + '“ nevede.' + (u.desky.length ? ' Patří do: ' + u.desky.map((d) => NAZEV_DESKY[d]).join(', ') + '.' : ' Učitelka zatím nemá přiřazenou třídu.') };
      }
      const prazdna = await prazdnaTrida(u, oblast);
      if (prazdna) return prazdna;
      try { localStorage.setItem('skolka-oblast', oblast); } catch (e) { /* nic */ }
      otevri(oblast);
      return { ok: true };
    }
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
  /* Ostrý provoz: nový účet z pozvánky (e-mail, heslo, kód). */
  async registruj(oblast, email, heslo, kod) {
    if (!SRV()) return { ok: false, chyba: 'Pozvánky fungují jen v ostrém provozu.' };
    const r = await SRV().registruj(email, heslo, kod);
    if (!r.ok) return r;
    const u = ucetZeServeru(r.ucet);
    const kam = u.desky.includes(oblast) ? oblast : u.desky[0];
    const prazdna = await prazdnaTrida(u, kam);
    if (prazdna) return prazdna;
    try { localStorage.setItem('skolka-oblast', kam); } catch (e) { /* nic */ }
    otevri(kam);
    return { ok: true };
  },
  async zapomenuteHeslo(email) {
    if (!SRV()) return { ok: false, chyba: 'Heslo v zkušebním provozu obnoví ředitelka (Přístupy → Nové heslo).' };
    try { await SRV().zapomenuteHeslo(email); return { ok: true }; } catch (e) { return { ok: false, chyba: SRV().chyba(e) }; }
  },
  odhlas() {
    if (SRV()) SRV().odhlas();
    try { localStorage.removeItem(KLIC_UCTU); } catch (e) { /* nic */ }
    window.__ucetBezUloziste = null;
    otevri('prihlaseni');
  },
  otevri: (klic) => otevri(klic),
  posledniOblast() { try { return localStorage.getItem('skolka-oblast') || ''; } catch (e) { return ''; } },

  /* ---- správa přístupů: jen ředitelka ---- */
  smiSpravovat() { const u = nactiUcet(); return !!u && (u.kod === 'reditelka' || (u.server && u.kod === 'zastupce')); },
  server: () => !!SRV(),
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

/* Kam pustit. Přihlašovací obrazovka se ukáže vždy, když o ni někdo
   výslovně požádá (#prihlaseni), nebo když chce tam, kam jeho přístup
   nevede — tiché přesměrování jinam by vypadalo, že ředitelna nejde. */
function kamSmi(klic, vychozi) {
  const u = nactiUcet();
  window.SkolkaUcet.chtel = '';
  if (klic === 'prihlaseni') {
    if (u && vychozi) { const p = posledni(); return p && u.desky.includes(p) ? p : u.desky[0]; }
    return 'prihlaseni';
  }
  if (!u) { window.SkolkaUcet.chtel = klic; return 'prihlaseni'; }
  if (u.desky.includes(klic)) return klic;
  window.SkolkaUcet.chtel = klic;
  return 'prihlaseni';
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

async function otevri(chtene, zHashe, vychozi) {
  const klic = kamSmi(chtene, vychozi);
  const soubor = PODLE_JMENA[klic];
  if (!soubor || prepinam) return;
  prepinam = true;
  try {
    chybaEl.hidden = true;
    nacitam.hidden = false;
    const t = await zdroj(soubor);
    if (klic === 'trida' && SRV()) {
      const u = nactiUcet();
      const deti = await SRV().nactiTridu(u.trida);
      if (!deti.length) throw new Error('Ve třídě ' + u.tridaNazev + ' zatím nejsou žádné děti — tablet se otevře, až je ředitelka do třídy zapíše.');
      window.__skolkaServerTrida = { id: u.trida, nazev: u.tridaNazev, deti, omluvy: await SRV().omluvy(deti).catch(() => []) };
    }
    aktualni = klic;
    prizpusob();
    window.DC.pripojDesku(t, koren, soubor);
    nacitam.hidden = true;
    if (!zHashe || klic !== chtene) history.replaceState(null, '', '#' + klic);
    if (klic !== 'prihlaseni') { try { localStorage.setItem('skolka-posledni-deska', klic); } catch (e) { /* nic */ } }
  } catch (e) {
    nacitam.hidden = true;
    chybaEl.hidden = false;
    chybaEl.textContent = 'Obrazovku se nepodařilo otevřít.\n\n' + (SRV() ? SRV().chyba(e) + '\n\n' : '') + (e && e.stack ? e.stack : e);
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
otevri(PODLE_JMENA[zacatek] ? zacatek : 'prihlaseni', true, !PODLE_JMENA[zacatek]);

if (navigator.storage && navigator.storage.persist) {
  navigator.storage.persist().catch(() => {});
}

if ('serviceWorker' in navigator) {
  /* Když se nasadí nová verze, stránka se jednou sama obnoví — jinak by stará
     skořápka v paměti mohla běžet s novými deskami a přihlášení by nesedělo. */
  const mel = !!navigator.serviceWorker.controller;
  let obnoveno = false;
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    if (!mel || obnoveno) return;
    obnoveno = true;
    location.reload();
  });
  navigator.serviceWorker.register('sw.js').then((r) => r.update()).catch(() => {});
}
