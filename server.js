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
      if (!C.testToken) hlidejJinyUcet();
    }
    return sb;
  }
  /* Dvě záložky jednoho prohlížeče sdílí přihlášení. Když se v jiné záložce
     přihlásí někdo jiný (nebo se odhlásí), tahle záložka nesmí dál zapisovat
     pod cizím účtem — vrátí se na přihlášení. */
  var prihlasuji = false;
  function hlidejJinyUcet() {
    var konec = function () {
      pamet = null;
      try { if (window.SkolkaUloziste) window.SkolkaUloziste.vycisti(); } catch (e) { /* nic */ }
      location.hash = '#prihlaseni';
      location.reload();
    };
    var zkontroluj = function (uid) {
      if (prihlasuji || !pamet || pamet.role === undefined) return;
      if (!uid || uid !== pamet.id) konec();
    };
    window.addEventListener('storage', function (e) {
      if (e.key !== 'skolka-sb-auth') return;
      var uid = null;
      try { var v = JSON.parse(e.newValue || 'null'); uid = v && v.user ? v.user.id : null; } catch (x) { uid = null; }
      zkontroluj(uid);
    });
  }
  function chyba(e) {
    var m = (e && (e.message || e.error_description)) || String(e || '');
    if (/Invalid login credentials/i.test(m)) return 'E-mail nebo heslo nesedí.';
    if (/Email not confirmed/i.test(m)) return 'E-mail ještě není potvrzený — klikněte na odkaz, který vám přišel, a přihlaste se znovu.';
    if (/Password should be/i.test(m)) return 'Heslo je moc slabé — použijte aspoň 8 znaků.';
    if (/rate limit/i.test(m)) return 'Moc pokusů za sebou — zkuste to za chvíli.';
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
    /* Kdo jsem a smím dál? (blokace školky / účtu, superadmin) */
    var st = ok(await klient().rpc('muj_stav'));
    st = Array.isArray(st) ? st[0] : st;
    if (st && st.superadmin) return { id: uid, jmeno: 'Správce LifeOS', role: 'superadmin', skolaId: null, skola: 'LifeOS', tridy: [] };
    if (!st || !st.role) { var e0 = new Error('Účet zatím nepatří žádné školce. Máte-li kód pozvánky, zvolte „Mám pozvánku“.'); e0.bezSkoly = true; throw e0; }
    if (st.role === 'rodic') throw new Error('Tohle je účet rodiče — rodiče používají aplikaci LifeOS.');
    if (!st.aktivni) throw new Error('Váš přístup je zablokovaný. Obraťte se na ředitelku školky.');
    if (st.stav_skoly === 'ceka') throw new Error('Školka ' + st.skola + ' ještě není aktivní — aktivuje ji správce LifeOS.');
    if (st.stav_skoly !== 'aktivni') throw new Error('Školka ' + st.skola + ' má přístup pozastavený. Obraťte se na správce LifeOS.');
    var u = ok(await klient().from('uzivatele').select('id, jmeno, role, skola_id').eq('id', uid).maybeSingle());
    var t = ok(await klient().from('ucitel_trida').select('trida_id, tridy(nazev, barva)').eq('ucitel_id', uid));
    return {
      id: uid, jmeno: u.jmeno, role: u.role, skolaId: u.skola_id, skola: st.skola || '',
      tridy: t.map(function (x) { return { id: x.trida_id, nazev: x.tridy ? x.tridy.nazev : 'Třída', barva: x.tridy ? x.tridy.barva : '' }; })
    };
  }

  /* Značky ze šatny — stejné klíče jako v desce třídy. Na serveru zatím
     nejsou, takže se dítěti přidělí podle pořadí ve třídě. */
  var ZNACKY = [['snehulak', 'sněhulák'], ['jablko', 'jablíčko'], ['auticko', 'autíčko'], ['kytka', 'kytička'], ['micek', 'míček'], ['motyl', 'motýl'], ['lodicka', 'lodička'], ['srdce', 'srdíčko'], ['hvezda', 'hvězdička'], ['tresne', 'třešničky'], ['muchomurka', 'muchomůrka'], ['mesic', 'měsíček'], ['domecek', 'domeček'], ['destnik', 'deštník'], ['strom', 'stromeček'], ['beruska', 'beruška'], ['rybka', 'rybička'], ['balonek', 'balónek'], ['klic', 'klíček'], ['mracek', 'mráček'], ['mrkev', 'mrkvička'], ['hruska', 'hruška'], ['zvonek', 'zvoneček'], ['duha', 'duha'], ['hrnek', 'hrníček'], ['list', 'lístek'], ['slunce', 'sluníčko'], ['snek', 'šnek']];
  function zn(d, i) { var z = ZNACKY.filter(function (x) { return x[0] === d.znacka; })[0]; return z || ZNACKY[i % ZNACKY.length]; }
  var DRUH_LOG = { teplota: 'teplota', uraz: 'uraz', jidlo: 'poznamka', spanek: 'poznamka', info: 'symptom' };

  /* Řádky ze serveru → dítě tak, jak ho zná deska třídy. */
  function diteProDesku(d, i, doch, vyz, ud, tridaId) {
    var k = {
      id: d.id, name: d.jmeno + ' ' + (d.prijmeni || '').charAt(0) + '.', sym: zn(d, i)[0], symName: zn(d, i)[1],
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

    async prihlas(email, heslo, kod) {
      prihlasuji = true;
      try {
        var uid = mojeId();
        if (!uid) {
          var r = await klient().auth.signInWithPassword({ email: String(email || '').trim(), password: heslo || '' });
          if (r.error) throw r.error;
          uid = r.data.user.id;
        }
        /* Účet bez školky + kód pozvánky (např. po potvrzení e-mailu) */
        if (kod) {
          var st0 = ok(await klient().rpc('muj_stav'));
          st0 = Array.isArray(st0) ? st0[0] : st0;
          if (!st0 || (!st0.role && !st0.superadmin)) ok(await klient().rpc('prijmi_pozvanku', { p_kod: kod }));
        }
        var u = await profil(uid);
        u.email = String(email || '').trim().toLowerCase();
        ulozUcet(u);
        return { ok: true, ucet: u };
      } catch (e) {
        try { if (!C.testToken) await klient().auth.signOut(); } catch (x) { /* nic */ }
        return { ok: false, chyba: chyba(e), bezSkoly: !!(e && e.bezSkoly) };
      } finally { prihlasuji = false; }
    },
    /* Nový účet z pozvánky: e-mail (stejný jako v pozvánce), heslo, kód. */
    async registruj(email, heslo, kod) {
      var self = this;
      prihlasuji = true;
      try {
        var mail = String(email || '').trim().toLowerCase();
        if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(mail)) throw new Error('E-mail nevypadá správně.');
        if (!heslo || heslo.length < 8) throw new Error('Heslo musí mít aspoň 8 znaků.');
        if (!kod) throw new Error('Opište kód z pozvánky.');
        try { if (!C.testToken) await klient().auth.signOut(); } catch (x) { /* nic */ }
        /* Účet už může existovat (např. po potvrzení e-mailu) → nejdřív přihlásit. */
        var p = await klient().auth.signInWithPassword({ email: mail, password: heslo });
        if (!p.error) return self.prihlas(mail, heslo, kod);
        if (/not confirmed/i.test(p.error.message || '') || p.error.code === 'email_not_confirmed') {
          var poslano = false;
          try { var rs = await klient().auth.resend({ type: 'signup', email: mail, options: { emailRedirectTo: location.origin + location.pathname } }); poslano = !rs.error; } catch (x) { /* nic */ }
          return { ok: false, potvrdit: true, chyba: 'E-mail ještě není potvrzený. ' + (poslano ? 'Poslali jsme nový odkaz — klikněte' : 'Klikněte') + ' na odkaz v e-mailu od nás (zkontrolujte i hromadnou poštu nebo spam) a pak to zkuste znovu.' };
        }
        var r = await klient().auth.signUp({ email: mail, password: heslo, options: { emailRedirectTo: location.origin + location.pathname } });
        var existuje = 'Účet s tímto e-mailem už existuje, ale heslo nesedí. Zadejte heslo, které jste si zvolili, nebo použijte „Zapomenuté heslo“.';
        if (r.error) {
          if (/already registered|already exists/i.test(r.error.message || '')) throw new Error(existuje);
          throw r.error;
        }
        /* Supabase u existujícího e-mailu nevrací chybu, jen uživatele bez identit. */
        if (r.data.user && Array.isArray(r.data.user.identities) && r.data.user.identities.length === 0) throw new Error(existuje);
        if (!r.data.session) return { ok: false, potvrdit: true, chyba: 'Poslali jsme vám e-mail. Potvrďte adresu odkazem v něm, pak se vraťte sem a stiskněte tlačítko znovu (e-mail, heslo i kód nechte stejné).' };
        ok(await klient().rpc('prijmi_pozvanku', { p_kod: kod }));
        var u = await profil(r.data.user.id);
        u.email = mail;
        ulozUcet(u);
        return { ok: true, ucet: u };
      } catch (e) {
        return { ok: false, chyba: chyba(e) };
      } finally { prihlasuji = false; }
    },
    async zapomenuteHeslo(email) {
      var r = await klient().auth.resetPasswordForEmail(String(email || '').trim(), { redirectTo: location.origin + location.pathname + '#prihlaseni' });
      if (r.error) throw r.error;
    },
    async odhlas() {
      ulozUcet(null);
      try { if (!C.testToken) await klient().auth.signOut(); } catch (e) { /* nic */ }
    },

    /* ---------------------------------------------------- tablet třídy */
    async nactiTridu(tridaId) {
      var deti = ok(await klient().from('deti').select('id, jmeno, prijmeni, alergie, datum_narozeni, znacka').eq('trida_id', tridaId).is('ukonceno', null).order('prijmeni'));
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
      return ok(await klient().from('dochazka').select('dite_id, den, omluvenka, strava_prihlasena, omluva_potvrzena, omluvu_potvrdil').eq('stav', 'omluven').gte('den', dnes()).in('dite_id', kids.map(function (k) { return k.id; })).order('den').limit(500));
    },
    /* Učitelka potvrdí omluvenku — rodič v LifeOS dostane oznámení. */
    async potvrdOmluvenku(k, od, doDne) {
      return ok(await klient().rpc('potvrd_omluvenku', { p_dite: k.id, p_od: od, p_do: doDne }));
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
      /* Číslo v knize přiděluje databáze (souběžné zápisy, učitelka nevidí úrazy jiných tříd). */
      var u = nactiUcet(), rok = new Date().getFullYear();
      var r = ok(await klient().from('urazy').insert({ skola_id: u.skolaId, cislo: 0, rok: rok, dite_id: k.id, kdy: new Date().toISOString(), kde: x.kde || null, co: x.co, osetreni: x.osetreni || null, svedek: x.svedek || null, komentar: x.komentar || null, zapsal: u.id }).select('cislo').single());
      return r.cislo;
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

    /* --------------------------------------------------------- jídelna */
    /* Zveřejní týden: [{ den, chod, nazev, alergeny, nahrady }] */
    async zverejniJidelnicek(dny) {
      return ok(await klient().rpc('zverejni_jidelnicek', { p_dny: dny }));
    },
    async nahradyObedu() {
      var u = nactiUcet();
      var r = ok(await klient().from('skoly').select('nahrady_obedu').eq('id', u.skolaId).maybeSingle());
      return r ? r.nahrady_obedu !== false : true;
    },
    async nastavNahrady(zap) {
      return ok(await klient().rpc('nastav_nahrady', { p: !!zap }));
    },

    /* ------------------------------------------------ superadmin (správa LifeOS) */
    async adminSkoly() { return ok(await klient().rpc('admin_skoly')); },
    async adminZalozSkolu(x) { return ok(await klient().rpc('admin_zaloz_skolu', { p_nazev: x.nazev, p_izo: x.izo || '', p_red_izo: x.redIzo || '', p_kontakt: x.kontakt || null, p_tarif: x.tarif || 'pilot', p_predplatne_do: x.predplatneDo || null })); },
    async adminUpravSkolu(id, x) { return ok(await klient().rpc('admin_uprav_skolu', { p_id: id, p_nazev: x.nazev || null, p_kontakt: x.kontakt == null ? null : x.kontakt, p_stav: x.stav || null, p_tarif: x.tarif || null, p_predplatne_do: x.predplatneDo || null, p_poznamka: x.poznamka == null ? null : x.poznamka })); },
    async adminPozviReditelku(skolaId, jmeno, email) { return ok(await klient().rpc('admin_pozvi_reditelku', { p_skola: skolaId, p_jmeno: jmeno, p_email: email })); },
    async adminNastavUcet(uid, aktivni) { return ok(await klient().rpc('admin_nastav_ucet', { p_uzivatel: uid, p_aktivni: !!aktivni })); },
    async zrusPozvanku(kod) { return ok(await klient().rpc('admin_zrus_pozvanku', { p_kod: kod })); },

    /* ------------------------------------------- ředitelka: přístupy zaměstnanců */
    async zamestnanci() { return ok(await klient().rpc('zamestnanci_skoly')); },
    async tridySkoly() { return ok(await klient().from('tridy').select('id, nazev').order('nazev')); },
    async pozviZamestnance(x) { return ok(await klient().rpc('pozvi_zamestnance', { p_jmeno: x.jmeno, p_email: x.email, p_role: x.role, p_trida: x.trida || null })); },
    async nastavUcetZamestnance(uid, aktivni) { return ok(await klient().rpc('nastav_ucet_zamestnance', { p_uzivatel: uid, p_aktivni: !!aktivni })); },

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
