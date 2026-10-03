/* =============================================================================
   Mini-runtime pro .dc.html desky
   -----------------------------------------------------------------------------
   PROČ TOHLE EXISTUJE

   Napoprvé jsem obrazovky do telefonu překreslil ručně — vzal jsem z plátna
   písmo, barvy a poloměry a kompozici si složil znovu. Výsledek byl „ze
   stejné rodiny, ale jiná aplikace“: skoro správně, a tím pádem špatně.

   Tohle to dělá obráceně. Desky z plátna se nepřepisují, **spouští se tak,
   jak jsou**. Runtime umí přesně to, co jejich kód používá, a nic víc:

     sc-if · sc-for (vnořené až 3×) · {{holes}} v textu i atributech
     onClick/onChange/onScroll · ref · helmet · odkazy mezi deskami

   Když se deska na plátně změní, stáhne se znovu a je hotovo. Žádný přepis,
   takže se ani nedá rozejít.
   -----------------------------------------------------------------------------
   Vykreslení je celé znovu při každém setState. Na těchhle obrazovkách je
   to levné a ušetří to diffování; co se z toho rozbije — ohnisko v poli
   a pozice rolování — se obnovuje ručně níž.
   ============================================================================= */

'use strict';

class DCLogic {
  constructor(props) {
    this.props = props || {};
    this.state = {};
  }
  setState(zmena) {
    const nove = typeof zmena === 'function' ? zmena(this.state) : zmena;
    Object.assign(this.state, nove);
    if (this.__vykresli) this.__vykresli();
  }
  forceUpdate() { if (this.__vykresli) this.__vykresli(); }
  renderVals() { return {}; }
}

/** Tečková cesta: `ui.card`, `r.label`. Nic jiného holes neumí a umět nemají. */
function cesta(obj, klic) {
  const k = String(klic).trim();
  if (k === 'true') return true;
  if (k === 'false') return false;
  if (k === 'null') return null;
  if (/^-?\d+(\.\d+)?$/.test(k)) return Number(k);
  let v = obj;
  for (const cast of k.split('.')) {
    if (v == null) return undefined;
    v = v[cast];
  }
  return v;
}

const HOLE_CELY = /^\{\{([^}]+)\}\}$/;
const HOLE = /\{\{([^}]+)\}\}/g;

function dosad(text, rozsah) {
  return String(text).replace(HOLE, (_, k) => {
    const v = cesta(rozsah, k);
    return v == null ? '' : String(v);
  });
}

/* --------------------------------------------------------------- vykreslení */

function zpracujDeti(rodic, cil, rozsah) {
  for (const uzel of Array.from(rodic.childNodes)) {
    zpracuj(uzel, cil, rozsah);
  }
}

function zpracuj(uzel, cil, rozsah) {
  // Text
  if (uzel.nodeType === 3) {
    const t = uzel.nodeValue;
    cil.appendChild(document.createTextNode(HOLE.test(t) ? dosad(t, rozsah) : t));
    HOLE.lastIndex = 0;
    return;
  }
  if (uzel.nodeType !== 1) return;

  const jmeno = uzel.tagName.toLowerCase();

  if (jmeno === 'helmet') return;

  if (jmeno === 'sc-if') {
    const v = uzel.getAttribute('value') || '';
    const m = v.match(HOLE_CELY);
    const podminka = m ? cesta(rozsah, m[1]) : v;
    if (podminka) zpracujDeti(uzel, cil, rozsah);
    return;
  }

  if (jmeno === 'sc-for') {
    const v = uzel.getAttribute('list') || '';
    const m = v.match(HOLE_CELY);
    const seznam = m ? cesta(rozsah, m[1]) : null;
    const jako = uzel.getAttribute('as') || 'item';
    if (Array.isArray(seznam)) {
      seznam.forEach((polozka, i) => {
        const vnitrni = Object.create(rozsah);
        vnitrni[jako] = polozka;
        vnitrni.$index = i;
        zpracujDeti(uzel, cil, vnitrni);
      });
    }
    return;
  }

  // Obyčejný prvek
  const novy = uzel.namespaceURI && uzel.namespaceURI.includes('svg')
    ? document.createElementNS(uzel.namespaceURI, uzel.tagName)
    : document.createElement(uzel.tagName);

  for (const atr of Array.from(uzel.attributes)) {
    const n = atr.name;
    const h = atr.value;

    if (n.startsWith('hint-')) continue;

    const cely = h.match(HOLE_CELY);

    // Události: onClick="{{fn}}" → posluchač.
    //
    // POZOR NA VELKÁ PÍSMENA. `DOMParser` názvy atributů zmenšuje, takže
    // z `onClick` je v DOM `onclick`. Napoprvé jsem tu měl `/^on[A-Z]/`,
    // což nesedlo NIKDY — a protože to byl celý hole, spadlo to do větve
    // níž a nastavilo inline `onclick` s tělem funkce jako textem.
    // Prohlížeč ho pak zkusil rozparsovat jako příkaz a řekl
    // „Function statements require a function name“.
    //
    // Projevilo se to tak, že se aplikace vykreslila správně a nešlo
    // v ní na nic klepnout. Navigace fungovala (jsou to `<a href>`)
    // a odpočet taky (je to `setInterval`), takže to na první pohled
    // vypadalo hotově.
    if (/^on[a-z]/i.test(n) && n.length > 2) {
      if (cely) {
        const fn = cesta(rozsah, cely[1]);
        if (typeof fn === 'function') novy.addEventListener(n.slice(2).toLowerCase(), fn);
      } else if (h) {
        // Hole to není, takže by to byl inline handler z cizího textu.
        // Ten se nenastavuje.
      }
      continue;
    }

    // ref="{{r}}" → objekt s .current, jako v Reactu
    if (n === 'ref' && cely) {
      const r = cesta(rozsah, cely[1]);
      if (r && typeof r === 'object') r.current = novy;
      continue;
    }

    if (cely) {
      const v = cesta(rozsah, cely[1]);
      // Hodnota pole se musí nastavit jako VLASTNOST, ne atribut —
      // atribut by po prvním psaní přestal odpovídat tomu, co je vidět.
      if (n === 'value' && ('value' in novy)) { novy.value = v == null ? '' : v; continue; }
      if (n === 'checked' || n === 'disabled') { if (v) novy.setAttribute(n, ''); continue; }
      novy.setAttribute(n, v == null ? '' : String(v));
      continue;
    }

    novy.setAttribute(n, HOLE.test(h) ? dosad(h, rozsah) : h);
    HOLE.lastIndex = 0;
  }

  zpracujDeti(uzel, novy, rozsah);
  cil.appendChild(novy);
}

/* ------------------------------------------------------- ohnisko a rolování
   Celé překreslení zahodí to, kde uživatel právě je. U vyhledávání by to
   znamenalo, že po každém písmenu vypadne z pole — tady se to vrací zpátky. */

function kdeJsem(koren) {
  const a = document.activeElement;
  if (!a || !koren.contains(a)) return null;
  const cesta = [];
  let u = a;
  while (u && u !== koren) {
    cesta.unshift(Array.prototype.indexOf.call(u.parentNode.childNodes, u));
    u = u.parentNode;
  }
  const s = {};
  try { s.start = a.selectionStart; s.end = a.selectionEnd; } catch (e) { /* ne u všech polí */ }
  return { cesta, s };
}

function vratMe(koren, kam) {
  if (!kam) return;
  let u = koren;
  for (const i of kam.cesta) {
    if (!u || !u.childNodes[i]) return;
    u = u.childNodes[i];
  }
  if (u && u.focus) {
    u.focus();
    if (kam.s.start != null) { try { u.setSelectionRange(kam.s.start, kam.s.end); } catch (e) { /* ne u všech */ } }
  }
}

/* Pozice rolování se pamatuje podle POŘADÍ rolovatelných prvků, ne podle
   třídy: u SVG je `className` objekt SVGAnimatedString a selektor z něj
   vyjde neplatný. Pořadí po překreslení sedí, protože šablona je táž.

   Vodorovné rolování se hlídá taky. Napoprvé tu bylo jen svislé a projevilo
   se to až u pásu se dvěma stránkami uvnitř karty: překreslení ho vrátilo
   na první stránku, takže se z něj nedalo odejít. Na plátně to nebylo vidět
   — React uzly při překreslení nechává, kdežto tenhle runtime je staví znovu. */
function rolovatelne(koren) {
  return Array.from(koren.querySelectorAll('*')).filter(
    (e) => e.scrollHeight > e.clientHeight + 1 || e.scrollWidth > e.clientWidth + 1
  );
}

function rolovani(koren) {
  return rolovatelne(koren).map((e) => ({ top: e.scrollTop, left: e.scrollLeft }));
}

function vratRolovani(koren, ulozene) {
  const prvky = rolovatelne(koren);
  ulozene.forEach((kde, i) => {
    const e = prvky[i];
    if (!e) return;
    if (kde.top) e.scrollTop = kde.top;
    if (kde.left) e.scrollLeft = kde.left;
  });
}

/* --------------------------------------------------------------- připojení */

const helmetyHotove = new Set();

function nasadHelmet(helmet, klic) {
  if (!helmet || helmetyHotove.has(klic)) return;
  helmetyHotove.add(klic);
  for (const uzel of Array.from(helmet.children)) {
    // Písmo a základní styl. Nic jiného v helmetu není a být nemá.
    if (uzel.tagName === 'STYLE') {
      const s = document.createElement('style');
      s.textContent = uzel.textContent;
      document.head.appendChild(s);
    } else if (uzel.tagName === 'LINK') {
      if (document.querySelector(`link[href="${uzel.getAttribute('href')}"]`)) continue;
      const l = document.createElement('link');
      for (const a of Array.from(uzel.attributes)) l.setAttribute(a.name, a.value);
      document.head.appendChild(l);
    }
  }
}

let aktivni = null;

/**
 * Připojí desku do kořene. `zdroj` je celý text .dc.html souboru.
 */
function pripojDesku(zdroj, koren, klic) {
  if (aktivni) {
    try { if (aktivni.instance.componentWillUnmount) aktivni.instance.componentWillUnmount(); }
    catch (e) { console.warn('componentWillUnmount:', e); }
    aktivni.instance.__vykresli = null;
  }
  koren.textContent = '';

  const doc = new DOMParser().parseFromString(zdroj, 'text/html');
  const xdc = doc.querySelector('x-dc');
  if (!xdc) throw new Error('Deska nemá <x-dc>.');

  nasadHelmet(xdc.querySelector('helmet'), klic);

  const skript = doc.querySelector('script[data-dc-script]');
  if (!skript) throw new Error('Deska nemá logiku.');

  let popis = {};
  try { popis = JSON.parse(skript.getAttribute('data-props') || '{}'); } catch (e) { /* nevadí */ }
  const props = {};
  for (const k of Object.keys(popis)) {
    if (popis[k] && typeof popis[k] === 'object' && 'default' in popis[k]) props[k] = popis[k].default;
  }

  // Logika desky je obyčejná třída bez importů, takže ji stačí vyhodnotit
  // a vrátit. Je to náš vlastní soubor z našeho původu, ne cizí vstup.
  const Trida = new Function('DCLogic', skript.textContent + '\nreturn Component;')(DCLogic);
  const instance = new Trida(props);

  const sablona = xdc;

  instance.__vykresli = function () {
    const ohnisko = kdeJsem(koren);
    const rolky = rolovani(koren);
    const vals = instance.renderVals() || {};
    const frag = document.createDocumentFragment();
    zpracujDeti(sablona, frag, vals);
    koren.textContent = '';
    koren.appendChild(frag);
    vratRolovani(koren, rolky);
    vratMe(koren, ohnisko);
  };

  aktivni = { instance, klic };
  instance.__vykresli();
  if (instance.componentDidMount) {
    try { instance.componentDidMount(); } catch (e) { console.warn('componentDidMount:', e); }
  }
  return instance;
}

window.DC = { pripojDesku, DCLogic };
