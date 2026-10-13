/* =============================================================================
   Server (Supabase) — sdílená data mezi tabletem, ředitelnou a LifeOS
   -----------------------------------------------------------------------------
   Zapne se, když config.js nastaví window.SKOLKA_SERVER = { url, key }.
   Bez něj aplikace běží jako dřív ve zkušebním provozu (data v prohlížeči).

   Co jde přes server (pilot):
   - přihlášení zaměstnanců (Supabase Auth, e-mail + heslo),
   - tablet třídy: děti třídy, příchod/odchod a kdo vyzvedl, zápisy pro
     rodiče (teplota, příznaky, úraz, poznámka), omluvenky a „vyzvedne jiný“
     od rodičů živě (realtime),
   - ředitelna: kód pro rodiče do LifeOS.
   Práva hlídá databáze (RLS v supabase/setup.sql) — tady se nic neověřuje.
   ============================================================================= */
(function () {
  'use strict';
  var C = window.SKOLKA_SERVER || null;
  var zapnuto = !!(C && C.url && C.key && window.supabase && window.supabase.createClient);
  var sb = null, pamet = null;
  var KLIC = 'skolka-server-ucet';

  function klient() {
    if (!sb) {
      var o = C.testToken
        ? { accessToken: function () { return Promise.resolve(C.testToken); } }
        : { auth: { persistSession: true, autoRefreshToken: true, storageKey: 'skolka-sb-auth' } };
      sb = window.supabase.createClient(C.url, C.key, o);
    }
    return sb;
  }
  function chyba(e) {
    var m = (e && (e.message || e.error_description)) || String(e || '');
    if (/Invalid login credentials/i.test(m)) return 'E-mail nebo heslo nesedí.';
    if (/Failed to fetch|NetworkError|Load failed/i.test(m)) return 'Server není dostupný — zkontrolujte připojení k internetu.';
    return m;
  }
  function ok(r) { if (r.error) throw r.error; return r.data; }
  function dnes() {
    var d = new Date();
    return d.getFullYear() + '-' + (d.getMonth() < 9 ? '0' : '') + (d.getMonth() + 1) + '-' + (d.getDate() < 10 ? '0' : '') + d.getDate();
  }
  function hm(t) { return t ? String(t).slice(0, 5).replace(/^0/, '') : null; }
  function hmZ(iso) { if (!iso) return ''; var d = new Date(iso); return isNaN(d) ? '' : d.getHours() + ':' + (d.getMinutes() < 10 ? '0' : '') + d.getMinutes(); }
  function cas(t) { return t ? (String(t).length < 5 ? '0' + t : String(t)) : null; }
  function ulozUcet(u) {
    pamet = u;
    try { if (u) localStorage.setItem(KLIC, JSON.stringify(u)); else localStorage.removeItem(KLIC); } catch (e) { /* jen v paměti */ }
  }
  function nactiUcet() {
    if (pamet) return pamet;
    try { pamet = JSON.parse(localStorage.getItem(KLIC) || 'null'); } catch (e) { pamet = null; }
    return pamet;
  }
  function mojeId() {
    if (C.testToken) { try { return JSON.parse(atob(C.testToken.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'))).sub; } catch (e) { return null; } }
    return null;
  }

  async function profil(uid) {
    var u = ok(await klient().from('uzivatele').select('id, jmeno, role, skola_id').eq('id', uid).maybeSingle());
    if (!u) throw new Error('Účet zatím nepatří žádné školce — ředitelka ho musí přidat.');
    if (u.role === 'rodic') throw new Error('Tohle je účet rodiče — rodiče používají aplikaci LifeOS.');
    var s = ok(await klient().from('skoly').select('nazev').eq('id', u.skola_id).maybeSingle());
    var t = ok(await klient().from('ucitel_trida').select('trida_id, tridy(nazev, barva)').eq('ucitel_id', uid));
    return {
      id: uid, jmeno: u.jmeno, role: u.role, skolaId: u.skola_id, skola: s ? s.nazev : '',
      tridy: t.map(function (x) { return { id: x.trida_id, nazev: x.tridy ? x.tridy.nazev : 'Třída', barva: x.tridy ? x.tridy.barva : '' }; })
    };
  }

  /* Značky ze šatny — stejné klíče jako v desce třídy. Na serveru zatím
     nejsou, takže se dítěti přidělí podle pořadí ve třídě. */
  var ZNACKY = [['snehulak', 'sněhulák'], ['jablko', 'jablíčko'], ['auticko', 'autíčko'], ['kytka', 'kytička'], ['micek', 'míček'], ['motyl', 'motýl'], ['lodicka', 'lodička'], ['srdce', 'srdíčko'], ['hvezda', 'hvězdička'], ['tresne', 'třešničky'], ['muchomurka', 'muchomůrka'], ['mesic', 'měsíček'], ['domecek', 'domeček'], ['destnik', 'deštník'], ['strom', 'stromeček'], ['beruska', 'beruška'], ['rybka', 'rybička'], ['balonek', 'balónek'], ['klic', 'klíček'], ['mracek', 'mráček'], ['mrkev', 'mrkvička'], ['hruska', 'hruška'], ['zvonek', 'zvoneček'], ['duha', 'duha'], ['hrnek', 'hrníček'], ['list', 'lístek'], ['slunce', 'sluníčko'], ['snek', 'šnek']];
  var DRUH_LOG = { teplota: 'teplota', uraz: 'uraz', jidlo: 'poznamka', spanek: 'poznamka', info: 'symptom' };

  /* Řádky ze serveru → dítě tak, jak ho zná deska třídy. */
  function diteProDesku(d, i, doch, vyz, ud, tridaId) {
    var k = {
      id: d.id, name: d.jmeno + ' ' + (d.prijmeni || '').charAt(0) + '.', sym: ZNACKY[i % ZNACKY.length][0], symName: ZNACKY[i % ZNACKY.length][1],
      allergies: d.alergie ? String(d.alergie).split(/\s*[,;]\s*/).filter(Boolean) : [],
      usualPickup: 'rodiče', pickupToday: null, att: 'expected', arrived: null, left: null, excuse: '',
      temp: null, unwell: null, log: [], cls: tridaId, todayCls: null, noPhoto: false, ppv: false, server: true
    };
    aplikuj(k, doch, vyz, ud);
    return k;
  }
  function aplikuj(k, doch, vyz, ud) {
    k.log = [];
    if (vyz) {
      k.pickupToday = { who: vyz.kdo, when: vyz.kdy || '', note: 'ohlášeno v aplikaci' };
      k.log.push({ t: hmZ(vyz.vytvoreno), type: 'vyzvedani', title: 'Vyzvedává ' + vyz.kdo + (vyz.kdy ? ' ' + vyz.kdy.toLowerCase() : ''), sub: 'Ohlásil rodič v aplikaci' });
    }
    if (doch && doch.stav === 'pritomen') {
      k.att = doch.odchod ? 'left' : 'present'; k.arrived = hm(doch.prichod); k.left = hm(doch.odchod); k.excuse = '';
      if (k.arrived) k.log.push({ t: k.arrived, type: 'dochazka', title: 'Příchod', sub: '' });
      if (k.left) k.log.push({ t: k.left, type: 'dochazka', title: 'Odchod', sub: doch.vyzvedl ? 'Vyzvedl/a ' + doch.vyzvedl : '' });
    } else if (doch && doch.stav === 'omluven') {
      k.att = 'excused'; k.arrived = null; k.left = null;
      k.excuse = (doch.omluvenka || 'omluveno') + ' · omluveno v aplikaci' + (doch.strava_prihlasena ? '' : ' · oběd odhlášen');
    } else {
      k.att = 'expected'; k.arrived = null; k.left = null; k.excuse = '';
    }
    (ud || []).forEach(function (u) {
      k.log.push({ t: hm(u.cas), type: DRUH_LOG[u.druh] || 'poznamka', title: u.titulek + (u.hodnota ? ' ' + u.hodnota : ''), sub: (u.osetreni ? u.osetreni + ' · ' : '') + (u.precteno ? 'rodiče viděli ' + hmZ(u.precteno) : 'odesláno rodičům') });
      if (u.druh === 'teplota') { var v = parseFloat(String(u.hodnota || '').replace(',', '.')); if (!isNaN(v)) k.temp = { value: v, t: hm(u.cas) }; }
    });
    k.log.sort(function (a, b) { return String(a.t).padStart(5, '0') < String(b.t).padStart(5, '0') ? -1 : 1; });
  }

  async function denTridy(ids) {
    var den = dnes();
    var res = await Promise.all([
      klient().from('dochazka').select('dite_id, stav, prichod, odchod, vyzvedl, omluvenka, strava_prihlasena').eq('den', den).in('dite_id', ids),
      klient().from('vyzvednuti').select('dite_id, kdo, kdy, vytvoreno').eq('den', den).in('dite_id', ids).order('vytvoreno'),
      klient().from('udalosti_ditete').select('dite_id, cas, druh, titulek, hodnota, osetreni, precteno').eq('den', den).in('dite_id', ids).order('cas')
    ]);
    var doch = {}, vyz = {}, ud = {};
    ok(res[0]).forEach(function (r) { doch[r.dite_id] = r; });
    ok(res[1]).forEach(function (r) { vyz[r.dite_id] = r; });
    ok(res[2]).forEach(function (r) { (ud[r.dite_id] = ud[r.dite_id] || []).push(r); });
    return { doch: doch, vyz: vyz, ud: ud };
  }

  window.SkolkaServer = {
    zapnuto: zapnuto,
    dnes: dnes,
    chyba: chyba,
    ucet: nactiUcet,

    async prihlas(email, heslo) {
      try {
        var uid = mojeId();
        if (!uid) {
          var r = await klient().auth.signInWithPassword({ email: String(email || '').trim(), password: heslo || '' });
          if (r.error) throw r.error;
          uid = r.data.user.id;
        }
        var u = await profil(uid);
        u.email = String(email || '').trim().toLowerCase();
        ulozUcet(u);
        return { ok: true, ucet: u };
      } catch (e) {
        try { if (!C.testToken) await klient().auth.signOut(); } catch (x) { /* nic */ }
        return { ok: false, chyba: chyba(e) };
      }
    },
    async odhlas() {
      ulozUcet(null);
      try { if (!C.testToken) await klient().auth.signOut(); } catch (e) { /* nic */ }
    },

    /* ---------------------------------------------------- tablet třídy */
    async nactiTridu(tridaId) {
      var deti = ok(await klient().from('deti').select('id, jmeno, prijmeni, alergie, datum_narozeni').eq('trida_id', tridaId).is('ukonceno', null).order('prijmeni'));
      var den = deti.length ? await denTridy(deti.map(function (d) { return d.id; })) : { doch: {}, vyz: {}, ud: {} };
      return deti.map(function (d, i) { return diteProDesku(d, i, den.doch[d.id], den.vyz[d.id], den.ud[d.id], tridaId); });
    },
    /* Znovu načte dnešek a přepíše ho do dětí desky (po změně od rodiče). */
    async obnovDen(kids) {
      if (!kids.length) return;
      var den = await denTridy(kids.map(function (k) { return k.id; }));
      kids.forEach(function (k) { aplikuj(k, den.doch[k.id], den.vyz[k.id], den.ud[k.id]); });
    },
    /* Omluvenky od dneška dál (i na víc dní dopředu) — pro přehled na tabletu. */
    async omluvy(kids) {
      if (!kids.length) return [];
      return ok(await klient().from('dochazka').select('dite_id, den, omluvenka, strava_prihlasena').eq('stav', 'omluven').gte('den', dnes()).in('dite_id', kids.map(function (k) { return k.id; })).order('den').limit(500));
    },
    /* Docházka dítěte podle stavu na desce. */
    async dochazka(k) {
      if (k.att === 'expected') return ok(await klient().from('dochazka').delete().eq('dite_id', k.id).eq('den', dnes()));
      if (k.att === 'excused') return null;
      return ok(await klient().from('dochazka').upsert({
        dite_id: k.id, den: dnes(), stav: 'pritomen', prichod: cas(k.arrived), odchod: k.att === 'left' ? cas(k.left) : null,
        vyzvedl: k.att === 'left' ? (k.pickupToday ? k.pickupToday.who : k.usualPickup || null) : null
      }, { onConflict: 'dite_id,den' }));
    },
    /* Zápis pro rodiče: { druh, titulek, hodnota, text, osetreni, cas } */
    async zapis(k, z, kdo) {
      var u = nactiUcet();
      return ok(await klient().from('udalosti_ditete').insert({
        skola_id: u.skolaId, dite_id: k.id, den: dnes(), cas: cas(z.cas), druh: z.druh, titulek: z.titulek,
        hodnota: z.hodnota || null, text: z.text || null, osetreni: z.osetreni || null, zapsal_jmeno: kdo || u.jmeno
      }));
    },
    /* Kniha úrazů (číslo za rok průběžně). */
    async uraz(k, x) {
      var u = nactiUcet(), rok = new Date().getFullYear();
      var posl = ok(await klient().from('urazy').select('cislo').eq('skola_id', u.skolaId).eq('rok', rok).order('cislo', { ascending: false }).limit(1));
      var cislo = (posl[0] ? posl[0].cislo : 0) + 1;
      ok(await klient().from('urazy').insert({ skola_id: u.skolaId, cislo: cislo, rok: rok, dite_id: k.id, kdy: new Date().toISOString(), kde: x.kde || null, co: x.co, osetreni: x.osetreni || null, svedek: x.svedek || null, komentar: x.komentar || null, zapsal: u.id }));
      return cislo;
    },
    /* Živé změny dnešní docházky a vyzvedávání (omluvenky od rodičů). */
    sleduj(tridaId, priZmene) {
      var t = null, kanal = klient().channel('trida-' + tridaId);
      var hned = function () { clearTimeout(t); t = setTimeout(priZmene, 250); };
      ['dochazka', 'vyzvednuti', 'udalosti_ditete'].forEach(function (tab) {
        kanal.on('postgres_changes', { event: '*', schema: 'public', table: tab }, hned);
      });
      try { kanal.subscribe(); } catch (e) { /* bez realtime — obnoví se po návratu do okna */ }
      var vid = function () { if (document.visibilityState === 'visible') hned(); };
      document.addEventListener('visibilitychange', vid);
      return function () { document.removeEventListener('visibilitychange', vid); try { klient().removeChannel(kanal); } catch (e) { /* nic */ } };
    },

    /* --------------------------------------------- ředitelna: rodiče v LifeOS */
    async detiSkoly() {
      var r = ok(await klient().from('deti').select('id, jmeno, prijmeni, trida_id, tridy(nazev), zastupci(id, jmeno, uzivatel_id, poradi)').is('ukonceno', null).order('prijmeni'));
      return r.map(function (d) {
        return { id: d.id, jmeno: d.jmeno + ' ' + d.prijmeni, trida: d.tridy ? d.tridy.nazev : '',
          zastupci: (d.zastupci || []).sort(function (a, b) { return (a.poradi || 0) - (b.poradi || 0); }).map(function (z) { return { id: z.id, jmeno: z.jmeno, propojen: !!z.uzivatel_id }; }) };
      });
    },
    async kodRodice(diteId, zastupceId) {
      return ok(await klient().rpc('vytvor_kod_rodice', { p_dite: diteId, p_zastupce: zastupceId || null }));
    }
  };
})();
