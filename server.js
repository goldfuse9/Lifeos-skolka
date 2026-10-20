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
    if (/row-level security|permission denied/i.test(m)) return 'Na tuto akci nemáte oprávnění (nebo je přístup zablokovaný).';
    if (/duplicate key|already exists/i.test(m)) return 'Takový záznam už existuje.';
    if (/JWT expired|invalid JWT|Auth session missing/i.test(m)) return 'Přihlášení vypršelo — přihlaste se znovu.';
    if (/violates foreign key/i.test(m)) return 'Záznam souvisí s jinými údaji a nejde takhle změnit.';
    if (/violates check constraint|invalid input syntax/i.test(m)) return 'Některý údaj má nesprávný tvar.';
    /* Technické hlášky v angličtině se uživateli neukazují doslova. */
    if (m && /^[\x00-\x7F]*$/.test(m)) { try { console.warn('Server:', m); } catch (x) { /* nic */ } return 'Server školky odpověděl chybou. Zkuste to znovu, případně dejte vědět správci.'; }
    return m;
  }
  function ok(r) { if (r.error) { hlidejOdepreni(r.error); throw r.error; } return r.data; }
  /* Odepřený zápis/čtení během práce (zablokovaný účet nebo školka): ověřit účet
     a případně odhlásit s vysvětlením — data dětí nesmí zůstat na obrazovce. */
  var overuji = false;
  function hlidejOdepreni(e) {
    var m = (e && (e.message || e.code)) || '';
    if (overuji || !/row-level security|permission denied|JWT expired|42501|PGRST301/i.test(String(m))) return;
    overuji = true;
    setTimeout(function () {
      API.overUcet().then(function (o) {
        overuji = false;
        if (o.ok || !window.SkolkaUcet) return;
        window.SkolkaUcet.zEmailu = o.chyba ? { chyba: o.chyba } : null;
        window.SkolkaUcet.odhlas();
      }).catch(function () { overuji = false; });
    }, 0);
  }
  /* Školní rok (září–srpen), do kterého patří dnešek — pro kalendář svátků. */
  function skolniRok() {
    var d = dnes(), y = +d.slice(0, 4), m = +d.slice(5, 7), z = m >= 9 ? y : y - 1;
    return { od: z + '-09-01', do: (z + 1) + '-08-31' };
  }
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
      temp: null, unwell: null, log: [], cls: tridaId, todayCls: null, ppv: false, server: true, female: d.pohlavi === 'F',
      /* Bez písemného souhlasu se dítě nefotí (GDPR) — chybějící souhlas = ne. */
      noPhoto: !(d.souhlasy || []).some(function (x) { return x.druh === 'foto_trida' && x.udelen; })
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

  var API = window.SkolkaServer = {
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
      var r = await klient().auth.resetPasswordForEmail(String(email || '').trim(), { redirectTo: location.origin + location.pathname });
      if (r.error) throw r.error;
    },
    /* Odkaz „nové heslo“ z e-mailu: převezme dočasné přihlášení z adresy. */
    async prevezmiObnovu(access, refresh) {
      var r = await klient().auth.setSession({ access_token: access, refresh_token: refresh });
      if (r.error) throw r.error;
      return r.data.user ? r.data.user.email || '' : '';
    },
    async noveHeslo(heslo) {
      if (!heslo || heslo.length < 8) throw new Error('Heslo musí mít aspoň 8 znaků.');
      var r = await klient().auth.updateUser({ password: heslo });
      if (r.error) throw r.error;
      try { await klient().auth.signOut(); } catch (e) { /* nic */ }
      return true;
    },
    /* Před otevřením desky: platí účet pořád? (blokace, změna třídy, role) */
    async overUcet() {
      var u = nactiUcet();
      if (!u) return { ok: false, chyba: '' };
      try {
        var uid = mojeId();
        if (!uid) { var s0 = await klient().auth.getSession(); uid = s0.data && s0.data.session ? s0.data.session.user.id : null; }
        if (!uid) return { ok: false, chyba: 'Přihlášení vypršelo — přihlaste se znovu.' };
        var p = await profil(uid);
        p.email = u.email; ulozUcet(p);
        return { ok: true };
      } catch (e) {
        if (/Failed to fetch|NetworkError|Load failed/i.test((e && e.message) || '')) return { ok: true, offline: true };
        return { ok: false, chyba: chyba(e) };
      }
    },
    async odhlas() {
      ulozUcet(null);
      try { if (!C.testToken) await klient().auth.signOut(); } catch (e) { /* nic */ }
    },

    /* ---------------------------------------------------- tablet třídy */
    async nactiTridu(tridaId) {
      var deti = ok(await klient().from('deti').select('id, jmeno, prijmeni, alergie, datum_narozeni, znacka, pohlavi, souhlasy(druh, udelen)').eq('trida_id', tridaId).is('ukonceno', null).order('prijmeni'));
      var den = deti.length ? await denTridy(deti.map(function (d) { return d.id; })) : { doch: {}, vyz: {}, ud: {} };
      return deti.map(function (d, i) { return diteProDesku(d, i, den.doch[d.id], den.vyz[d.id], den.ud[d.id], tridaId); });
    },
    /* --------------------------------------------- fotky (alba třídy v úložišti) */
    async albaTridy(tridaId) {
      return ok(await klient().from('alba').select('id, den, druh, nazev, popis, fotky, zverejneno').eq('trida_id', tridaId).order('den', { ascending: false }).order('vytvoreno', { ascending: false }).limit(60));
    },
    async zalozAlbum(x) {
      return ok(await klient().from('alba').insert({ skola_id: nactiUcet().skolaId, trida_id: x.trida_id, den: x.den, nazev: x.nazev, druh: x.druh || 'den', popis: x.popis || null }).select('id').single()).id;
    },
    /* Fotka (už zmenšená) do úložiště; vrátí cestu <škola>/<třída>/<album>/<soubor>.jpg */
    async nahrajFotku(tridaId, albumId, data, typ) {
      var cesta = nactiUcet().skolaId + '/' + tridaId + '/' + albumId + '/' + (crypto.randomUUID ? crypto.randomUUID() : Date.now() + '-' + Math.random().toString(36).slice(2)) + (typ === 'image/png' ? '.png' : '.jpg');
      var r = await klient().storage.from('fotky').upload(cesta, data, { contentType: typ || 'image/jpeg', upsert: false });
      if (r.error) throw r.error;
      return cesta;
    },
    async ulozFotkyAlba(albumId, fotky) { ok(await klient().from('alba').update({ fotky: fotky }).eq('id', albumId)); },
    async smazFotku(cesta) { var r = await klient().storage.from('fotky').remove([cesta]); if (r.error) throw r.error; },
    async zverejnitAlbum(albumId, ano) { ok(await klient().from('alba').update({ zverejneno: ano ? new Date().toISOString() : null }).eq('id', albumId)); },
    /* Dočasné odkazy na fotky (1 h) — cesta → URL. */
    async odkazyFotek(cesty) {
      if (!cesty.length) return {};
      var r = await klient().storage.from('fotky').createSignedUrls(cesty, 3600);
      if (r.error) throw r.error;
      var o = {}; (r.data || []).forEach(function (x) { if (x.signedUrl) o[x.path] = x.signedUrl; });
      return o;
    },

    /* Akce a třídní schůzky třídy (i celoškolní) od včerejška, s odpověďmi rodičů. */
    async akceTridy(tridaId) {
      var vcera = new Date(); vcera.setDate(vcera.getDate() - 1);
      var od = vcera.getFullYear() + '-' + String(vcera.getMonth() + 1).padStart(2, '0') + '-' + String(vcera.getDate()).padStart(2, '0');
      return ok(await klient().from('akce').select('id, trida_id, den, cas, nazev, misto, poznamka, cena, jen_info, druh, s_sebou, program, akce_odpovedi(dite_id, odpoved)')
        .or('trida_id.eq.' + tridaId + ',trida_id.is.null').gte('den', od).order('den').order('cas'));
    },
    async ulozAkci(x) {
      return ok(await klient().from('akce').insert({ skola_id: nactiUcet().skolaId, trida_id: x.trida_id, den: x.den, cas: x.cas || null, nazev: x.nazev, misto: x.misto || null,
        cena: x.cena == null ? null : x.cena, druh: x.druh || 'akce', s_sebou: x.s_sebou || [], program: x.program || null }).select('id').single()).id;
    },
    /* Třídní kniha (povinná dokumentace) — posledních 30 zápisů třídy. */
    async kniha(tridaId) {
      var r = ok(await klient().from('tridni_kniha').select('den, tema, cinnosti, pouceni, pritomno, chybelo, uzivatele(jmeno)').eq('trida_id', tridaId).order('den', { ascending: false }).limit(30));
      return r.map(function (e) { return { date: e.den, theme: e.tema, acts: e.cinnosti || [], safety: e.pouceni || [], by: e.uzivatele ? e.uzivatele.jmeno : '', present: e.pritomno || 0, absent: e.chybelo || 0 }; });
    },
    async zapisKnihy(tridaId, e) {
      ok(await klient().from('tridni_kniha').upsert({ trida_id: tridaId, den: e.date, tema: e.theme, cinnosti: e.acts, pouceni: e.safety, pritomno: e.present, chybelo: e.absent, zapsal: nactiUcet().id }, { onConflict: 'trida_id,den' }));
    },
    /* Dnešní jídla třídy (zveřejněný jídelníček) — alergeny jako názvy. */
    async jidlaDnes() {
      var A = [null, 'lepek', 'korýši', 'vejce', 'ryby', 'arašídy', 'sója', 'mléko', 'ořechy', 'celer', 'hořčice', 'sezam', 'siřičitany', 'vlčí bob', 'měkkýši'];
      var r = ok(await klient().rpc('jidelnicek_tyden', { p_od: dnes(), p_do: dnes() }));
      if (!r.length) return null;
      var obed = r.filter(function (x) { return x.chod === 'obed'; })[0], al = {};
      r.forEach(function (x) { if (x.chod !== 'nap') (x.alergeny || []).forEach(function (n) { if (A[n]) al[A[n]] = true; }); });
      return { name: obed ? obed.nazev.split(',')[0] : r[0].nazev.split(',')[0], allergens: Object.keys(al), chody: r.map(function (x) { return x.chod + ': ' + x.nazev; }) };
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
    async dochazka(k, puvodni) {
      /* Vrácení: obnoví přesně předchozí řádek (např. omluvenku od rodiče). */
      if (puvodni !== undefined) {
        if (puvodni === null) return ok(await klient().from('dochazka').delete().eq('dite_id', k.id).eq('den', dnes()));
        return ok(await klient().from('dochazka').upsert(puvodni, { onConflict: 'dite_id,den' }));
      }
      if (k.att === 'expected') return ok(await klient().from('dochazka').delete().eq('dite_id', k.id).eq('den', dnes()));
      if (k.att === 'excused') return null;
      var radek = {
        dite_id: k.id, den: dnes(), stav: 'pritomen', prichod: cas(k.arrived), odchod: k.att === 'left' ? cas(k.left) : null,
        vyzvedl: k.att === 'left' ? (k.pickupToday ? k.pickupToday.who : k.usualPickup || null) : null
      };
      /* Omluvené dítě přesto přišlo: omluvenka a její potvrzení neplatí. Oběd
         zůstane, jak ho kuchyně objednala (strava_prihlasena se nemění). */
      if (k.excuse || k.wasExcused) { radek.omluvenka = null; radek.omluva_potvrzena = null; radek.omluvu_potvrdil = null; }
      return ok(await klient().from('dochazka').upsert(radek, { onConflict: 'dite_id,den' }));
    },
    /* Řádek docházky dítěte dnes (pro vrácení akce). */
    async dochazkaDnes(diteId) {
      return ok(await klient().from('dochazka').select('dite_id, den, stav, prichod, odchod, vyzvedl, omluvenka, trida_dnes, strava_prihlasena, omluva_zadana, omluva_potvrzena, omluvu_potvrdil').eq('dite_id', diteId).eq('den', dnes()).maybeSingle());
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
    async zverejniJidelnicek(dny, od, doDne) {
      var arg = { p_dny: dny };
      if (od) { arg.p_od = od; arg.p_do = doDne; }
      return ok(await klient().rpc('zverejni_jidelnicek', arg));
    },
    /* Jídelna v ostrém provozu: katalog jídel, jídelníček, počty jídel na den, diety. */
    async nactiJidelnu(od, doDne, den) {
      var u = nactiUcet();
      var r = await Promise.all([
        klient().from('jidelna_katalog').select('data').eq('skola_id', u.skolaId).maybeSingle(),
        klient().rpc('jidelnicek_kuchyne', { p_od: od, p_do: doDne }),
        klient().rpc('obedy_den', { p_den: den }),
        klient().rpc('den_provozu', { p_den: den }).then(function (x) { return x.error ? { data: null, error: null } : x; }),
        klient().rpc('deti_diety'),
        klient().from('skoly').select('nazev, kratky_nazev, adresa, telefon, email, web, ico, logo, nahrady_obedu').eq('id', u.skolaId).maybeSingle(),
        klient().from('uzivatele').select('id', { count: 'exact', head: true }).neq('role', 'rodic').eq('aktivni', true)
      ]);
      var D = r.slice(0, 6).map(ok);
      if (r[6].error) throw r[6].error;
      return { katalog: D[0] ? D[0].data : null, menu: D[1], obedy: D[2], provoz: D[3], diety: D[4], skola: D[5], zamestnancu: r[6].count || 0, den: den };
    },
    async ulozChody(chody) { return ok(await klient().rpc('uloz_chody', { p_chody: chody })); },
    async ulozKatalog(data) {
      var u = nactiUcet();
      ok(await klient().from('jidelna_katalog').upsert({ skola_id: u.skolaId, data: data, zmeneno: new Date().toISOString(), zmenil: u.id }));
    },
    async ulozDietu(diteId, doporuceni, poznamka) {
      ok(await klient().from('diety').upsert({ dite_id: diteId, doporuceni_lekare: !!doporuceni, poznamka: poznamka || null }));
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

    /* --------------------------------------------- majetek a inventarizace
       Ředitelna (vedení, hospodářka) načte celou evidenci; tablet učitelky jen
       místnosti svých tříd (to hlídá databáze). Měnit jde jen funkcemi. */
    async nactiMajetek(tablet) {
      var vse = async function (dotaz) {
        var out = [], od = 0;
        for (;;) { var d = ok(await dotaz().range(od, od + 999)); out = out.concat(d || []); if (!d || d.length < 1000) return out; od += 1000; }
      };
      var u = nactiUcet();
      if (!tablet && u && (u.role === 'reditelka' || u.role === 'zastupce' || u.role === 'hospodarka')) {
        var kat0 = ok(await klient().from('majetek_kategorie').select('kod').limit(1));
        if (!kat0.length) await klient().rpc('majetek_priprav');
      }
      var inv = ok(await klient().from('inventury').select('id, k_datu, zahajena, uzavrena, komise').order('zahajena', { ascending: false }).limit(10));
      var bezi = inv.filter(function (i) { return !i.uzavrena; })[0] || null;
      var r = await Promise.all([
        klient().from('majetek_kategorie').select('kod, nazev, poradi').order('poradi'),
        klient().from('mistnosti').select('id, nazev, trida_id, poradi, aktivni').order('poradi').order('nazev'),
        vse(function () { return klient().from('majetek').select('id, cislo, kategorie, rok, poradi, nazev, druh, mistnost_id, odpovida, vyrobce, seriove, porizeno, cena, dodavatel, doklad, ucetni_druh, zaruka_do, financovani, puvodni_cislo, poznamka, stav, zapujceno_komu, zapujceno_do, vyrazeno, duvod_vyrazeni, stitek_tisk').order('cislo'); }),
        tablet ? Promise.resolve([]) : vse(function () { return klient().from('majetek_pohyby').select('id, polozka_id, kdy, druh, popis, kdo').order('kdy', { ascending: false }); }),
        tablet ? { data: [] } : klient().from('majetek_kontroly').select('id, polozka_id, nazev, interval_mesicu, posledni, dalsi, poznamka').order('dalsi'),
        bezi ? klient().from('inventura_mistnosti').select('mistnost_id, kontroluje, hotovo').eq('inventura_id', bezi.id) : { data: [] },
        bezi ? vse(function () { return klient().from('inventura_zaznamy').select('polozka_id, vysledek, nalezeno_v, kdy, vyreseno').eq('inventura_id', bezi.id).order('polozka_id'); }) : Promise.resolve([]),
        bezi ? klient().from('inventura_nalezy').select('id, mistnost_id, popis, kdy, vyreseno, polozka_id').eq('inventura_id', bezi.id).order('kdy') : { data: [] }
      ]);
      var D = r.map(function (x) { return Array.isArray(x) ? x : ok(x); });
      return { kategorie: D[0], mistnosti: D[1], polozky: D[2], pohyby: D[3], kontroly: D[4], inventury: inv, inventura: bezi,
        invMistnosti: D[5], zaznamy: D[6], nalezy: D[7] };
    },
    async majetekRpc(fn, args) { return ok(await klient().rpc(fn, args || {})); },

    /* --------------------------------------------- pokročilé finance
       Doplňková data k platbám: druh a číslo předpisů, storna, účetní období
       pohybů, slevy, pokladna, vratky, uzávěrky a akce s cenou. */
    async nactiFinanceX() {
      var vse = async function (dotaz) {
        var out = [], od = 0;
        for (;;) { var d = ok(await dotaz().range(od, od + 999)); out = out.concat(d || []); if (!d || d.length < 1000) return out; od += 1000; }
      };
      var od = new Date(); od.setDate(od.getDate() - 120);
      var r = await Promise.all([
        klient().from('financni_nastaveni').select('predkontace, pokladna_pocatek').maybeSingle(),
        vse(function () { return klient().from('predpisy').select('id, dite_id, obdobi, castka, uhrazeno, stav, splatnost, vystaveno, druh, nazev, cislo, storno, storno_duvod, akce_id, predpis_polozky(poradi, druh, popis, mnozstvi, cena, castka)').order('splatnost').order('id'); }),
        vse(function () { return klient().from('ucetni_pohyby').select('id, druh, obdobi_uctu').order('id'); }),
        vse(function () { return klient().from('platby').select('id, zdroj').order('id'); }),
        klient().from('fin_upravy').select('id, dite_id, typ, hodnota, plati_od, plati_do, duvod, rozhodnuti, vytvoreno, zruseno').order('vytvoreno', { ascending: false }),
        vse(function () { return klient().from('pokladna').select('id, cislo, datum, druh, castka, dite_id, ucel, osoba, vytvoreno').order('datum').order('cislo'); }),
        klient().from('fin_vratky').select('id, dite_id, castka, zpusob, ucet, cislo, stav, vytvoreno, odeslano').order('vytvoreno', { ascending: false }),
        klient().from('fin_uzaverky').select('obdobi, uzavreno').order('obdobi'),
        klient().from('akce').select('id, nazev, den, cena, trida_id, akce_odpovedi(dite_id, odpoved)').gt('cena', 0).gte('den', od.toISOString().slice(0, 10)).order('den')
      ]);
      var D = r.map(function (x) { return Array.isArray(x) ? x : ok(x); });
      return { nastaveni: D[0], predpisy: D[1], pohyby: D[2], platby: D[3], upravy: D[4], pokladna: D[5], vratky: D[6], uzaverky: D[7], akce: D[8] };
    },
    async finRpc(fn, args) { return ok(await klient().rpc(fn, args || {})); },

    /* --------------------------------------------- ředitelna: data školky
       Načte vše, co ředitelna v ostrém provozu ukazuje (kartotéka, třídy,
       zaměstnanci, kniha úrazů, souhrn docházky, dnešek, zprávy). Rodná čísla
       a další osobní údaje jen pro vedení (deti_osobni). */
    async nactiReditelnu(od, doDne) {
      var u = nactiUcet(), ved = u && (u.role === 'reditelka' || u.role === 'zastupce');
      var fin = u && (ved || u.role === 'hospodarka');
      var prazdno = Promise.resolve({ data: [], error: null });
      /* Supabase vrací nejvýš 1000 řádků na dotaz — delší tabulky po stránkách. */
      var vse = async function (dotaz) {
        var out = [], od = 0;
        for (;;) { var d = ok(await dotaz().range(od, od + 999)); out = out.concat(d || []); if (!d || d.length < 1000) return { data: out, error: null }; od += 1000; }
      };
      var r = await Promise.all([
        klient().from('skoly').select('id, nazev, kratky_nazev, ico, izo, red_izo, cast_skoly, zrizovatel, rozliseni, adresa, telefon, email, datovka, web, ucet, poverenec, provozni_doba, uredni_hodiny, druh_provozu, doba_provozu, kontakt, skartacni_plan, logo').eq('id', u.skolaId).maybeSingle(),
        klient().from('tridy').select('id, nazev, kod, barva, kapacita, provoz').order('nazev'),
        klient().from('deti').select('id, trida_id, jmeno, prijmeni, datum_narozeni, pohlavi, obcanstvi, znalost_cj, spadovy, zahajeni, po_stupen, ivp, asistent, plpp_do, alergie, variabilni_symbol, ukonceno, znacka, zastupci(id, jmeno, telefon, email, poradi, uzivatel_id), poverene_osoby(id, jmeno, zmocneni_od, zruseno), souhlasy(druh, udelen, zmeneno)').order('prijmeni'),
        ved ? klient().rpc('deti_osobni') : prazdno,
        klient().from('uzivatele').select('id, jmeno, role, email, aktivni').neq('role', 'rodic').order('jmeno'),
        klient().from('ucitel_trida').select('ucitel_id, trida_id'),
        klient().from('urazy').select('id, cislo, rok, dite_id, kdy, kde, co, osetreni, svedek, komentar, zapsal, dny_absence, zaznam_odeslan, zaznam').order('kdy', { ascending: false }).limit(500),
        klient().rpc('dochazka_souhrn', { p_od: od, p_do: doDne }),
        klient().from('dochazka').select('dite_id, stav, prichod, odchod').eq('den', dnes()),
        klient().from('zpravy').select('id, komu, predmet, text, odeslal, odeslano').order('odeslano', { ascending: false }).limit(100),
        klient().from('porady').select('id, den, druh, program, usneseni, pritomni').order('den', { ascending: false }).limit(300),
        ved ? klient().from('zadosti').select('id, rok, reg_cislo, jmeno, prijmeni, rodne_cislo, datum_narozeni, pohlavi, spadovy, sourozenec, email, poradi, vysledek, dite_id').order('reg_cislo') : prazdno,
        ved ? klient().from('zapis_rocnik').select('rok, rozhodnuto, zverejneno, odeslano, preneseno') : prazdno,
        ved ? klient().from('dokumenty').select('klic, html, fmt, schvaleno, verze, upraveno_po_schvaleni, na_webu') : prazdno,
        fin ? klient().from('financni_nastaveni').select('ucet, skolkovne, omluva_dni_predem, omluva_do, splatnost_den, vs_schema, vs_prefix, vs_delka') : prazdno,
        fin ? klient().from('sazby_stravneho').select('kategorie, cena') : prazdno,
        fin ? vse(function () { return klient().from('predpisy').select('id, dite_id, obdobi, castka, uhrazeno, stav, splatnost, vystaveno, predpis_polozky(poradi, druh, popis, mnozstvi, cena, castka)').order('obdobi').order('id'); }) : prazdno,
        fin ? vse(function () { return klient().from('ucetni_pohyby').select('id, datum, md, dal, castka, popis, doklad').order('datum').order('vytvoreno').order('id'); }) : prazdno,
        fin ? vse(function () { return klient().from('platby').select('id, datum, castka, vs, protiucet, nazev, doklad, dite_id').order('datum').order('id'); }) : prazdno,
        fin ? klient().from('nesparovane_platby').select('platba_id, duvod, vyreseno').eq('vyreseno', false) : prazdno,
        fin ? vse(function () { return klient().from('upominky').select('dite_id, obdobi, kanal, odeslano').order('odeslano').order('id'); }) : prazdno,
        fin ? klient().from('konta').select('dite_id, saldo') : prazdno,
        ved ? klient().rpc('archiv_zmen', { p_limit: 300 }) : prazdno,
        /* napojení banky — bez migrace 2026-10-17-banka funkce není a panel se neukáže */
        fin ? klient().rpc('stav_napojeni_banky').then(function (x) { return x.error ? { data: false, error: null } : x; }) : prazdno,
        /* provozní kalendář (svátky a výjimky) na školní rok — bez migrace 2026-10-17c prázdno */
        klient().rpc('kalendar_skoly_obdobi', { p_od: skolniRok().od, p_do: skolniRok().do }).then(function (x) { return x.error ? { data: false, error: null } : x; }),
        /* pokročilé finance (migrace 2026-10-21-finance) — bez ní null a ředitelna jede po staru */
        fin ? API.nactiFinanceX().then(function (x) { return { data: x, error: null }; }).catch(function () { return { data: null, error: null }; }) : prazdno
      ]);
      var D = r.map(ok);
      return { skola: D[0], tridy: D[1], deti: D[2], osobni: D[3], zamestnanci: D[4], ucitelTrida: D[5], urazy: D[6], souhrn: D[7], dnes: D[8], zpravy: D[9], porady: D[10], zadosti: D[11], zapisRocnik: D[12], dokumenty: D[13],
        archiv: D[22], kalendar: D[24], fin: fin ? { nastaveni: D[14][0] || null, sazby: D[15], predpisy: D[16], pohyby: D[17], platby: D[18], nespar: D[19], upominky: D[20], konta: D[21], banka: D[23] === false ? false : Array.isArray(D[23]) ? null : D[23], x: Array.isArray(D[25]) ? null : D[25] } : null };
    },
    /* Dítě: řádek deti + zákonní zástupci + pověřené osoby + souhlasy. */
    async ulozDite(id, radek, zastupci, poverene, souhlasy) {
      if (!id) {
        var nove = ok(await klient().from('deti').insert(Object.assign({ skola_id: nactiUcet().skolaId }, radek)).select('id').single());
        id = nove.id;
      } else if (radek && Object.keys(radek).length) {
        ok(await klient().from('deti').update(radek).eq('id', id));
      }
      var stavajici = ok(await klient().from('zastupci').select('id, uzivatel_id, poradi').eq('dite_id', id));
      for (var i = 0; i < (zastupci || []).length; i++) {
        var z = zastupci[i], byl = stavajici.filter(function (x) { return x.poradi === z.poradi; })[0];
        if (z.jmeno) {
          var data = { jmeno: z.jmeno, telefon: z.telefon || null, email: z.email || null };
          if (byl) ok(await klient().from('zastupci').update(data).eq('id', byl.id));
          else ok(await klient().from('zastupci').insert(Object.assign({ dite_id: id, poradi: z.poradi }, data)));
        } else if (byl && !byl.uzivatel_id) {
          ok(await klient().from('zastupci').delete().eq('id', byl.id));
        }
      }
      if (poverene) {
        var pov = ok(await klient().from('poverene_osoby').select('id, jmeno').eq('dite_id', id).is('zruseno', null));
        var jmena = poverene.map(function (p) { return p.jmeno; });
        for (var j = 0; j < pov.length; j++) if (jmena.indexOf(pov[j].jmeno) === -1) ok(await klient().from('poverene_osoby').update({ zruseno: dnes() }).eq('id', pov[j].id));
        var mame = pov.map(function (p) { return p.jmeno; });
        var pridat = poverene.filter(function (p) { return mame.indexOf(p.jmeno) === -1; }).map(function (p) { return { dite_id: id, jmeno: p.jmeno, zmocneni_od: p.od || dnes() }; });
        if (pridat.length) ok(await klient().from('poverene_osoby').insert(pridat));
      }
      if (souhlasy && souhlasy.length) {
        ok(await klient().from('souhlasy').upsert(souhlasy.map(function (x) { return { dite_id: id, druh: x.druh, udelen: !!x.udelen, zmeneno: new Date().toISOString(), zmenil: nactiUcet().id }; })));
      }
      return id;
    },
    async ulozTridu(id, radek) {
      if (id) { ok(await klient().from('tridy').update(radek).eq('id', id)); return id; }
      return ok(await klient().from('tridy').insert(Object.assign({ skola_id: nactiUcet().skolaId }, radek)).select('id').single()).id;
    },
    async ulozTridyUcitele(ucitel, bylo, ted) {
      var pryc = bylo.filter(function (x) { return ted.indexOf(x) === -1; }), nove = ted.filter(function (x) { return bylo.indexOf(x) === -1; });
      if (pryc.length) ok(await klient().from('ucitel_trida').delete().eq('ucitel_id', ucitel).in('trida_id', pryc));
      if (nove.length) ok(await klient().from('ucitel_trida').insert(nove.map(function (t) { return { ucitel_id: ucitel, trida_id: t }; })));
    },
    /* Zápis z porady: ukládá se jednou, pak už se nemění (dokument). */
    async ulozPoradu(x) {
      return ok(await klient().from('porady').insert({ skola_id: nactiUcet().skolaId, den: x.den, druh: x.druh, program: x.program, usneseni: x.usneseni || null, pritomni: x.pritomni || [] }).select('id').single()).id;
    },
    /* --------------------------------------------- zápis (přijímací řízení) */
    async novaZadost(x) {
      var r = ok(await klient().rpc('nova_zadost', { p_rok: x.rok, p_jmeno: x.jmeno, p_prijmeni: x.prijmeni, p_rc: x.rc, p_narozeni: x.narozeni, p_pohlavi: x.pohlavi || null, p_spadovy: !!x.spadovy, p_sourozenec: !!x.sourozenec, p_email: x.email || null }));
      return (r && r[0]) || r;
    },
    async rozhodniZapis(rok, vysledky) { return ok(await klient().rpc('rozhodni_zapis', { p_rok: rok, p_vysledky: vysledky })); },
    async zmenVysledek(id, vysledek) { ok(await klient().from('zadosti').update({ vysledek: vysledek }).eq('id', id)); },
    async zapisKrok(rok, krok) { return ok(await klient().rpc('zapis_krok', { p_rok: rok, p_krok: krok })); },
    async prevedPrijate(rok) { return ok(await klient().rpc('preved_prijate', { p_rok: rok })); },
    /* --------------------------------------------- dokumenty školy */
    async ulozDokument(klic, x) {
      /* nejdřív úprava, jinak nový řádek (upsert by potřeboval právo měnit i klíč) */
      var data = { html: x.html || null, fmt: x.fmt || null, na_webu: !!x.naWebu };
      var r = ok(await klient().from('dokumenty').update(data).eq('klic', klic).select('klic'));
      if (!r || !r.length) ok(await klient().from('dokumenty').insert(Object.assign({ skola_id: nactiUcet().skolaId, klic: klic }, data)));
    },
    async schvalDokument(klic, html, fmt, zneni) { return ok(await klient().rpc('schval_dokument', { p_klic: klic, p_html: html || null, p_fmt: fmt || null, p_zneni: zneni })); },
    /* --------------------------------------------- platby (funkce v databázi) */
    async ulozFinNastaveni(x) {
      var a = { p_ucet: x.ucet, p_skolkovne: x.skolkovne, p_stravne_36: x.s36, p_stravne_7: x.s7, p_splatnost: x.splatnost };
      if (x.omlDni != null) Object.assign(a, { p_omluva_dni: x.omlDni, p_omluva_do: x.omlDo, p_vs_schema: x.vsSchema, p_vs_prefix: x.vsPrefix, p_vs_delka: x.vsDelka });
      ok(await klient().rpc('uloz_financni_nastaveni', a));
    },
    /* Údaje školky (Nastavení): jen změněné sloupce. */
    async ulozSkolu(radek) { ok(await klient().from('skoly').update(radek).eq('id', nactiUcet().skolaId)); },
    /* Provoz školky: dny od–do otevřít (i ve svátek), zavřít, nebo vrátit na výchozí (svátky zavřeno). */
    async nastavKalendar(od, doDne, stav, poznamka) { return ok(await klient().rpc('nastav_kalendar', { p_od: od, p_do: doDne, p_stav: stav, p_poznamka: poznamka || null })); },
    async kalendar() { var r = skolniRok(); return ok(await klient().rpc('kalendar_skoly_obdobi', { p_od: r.od, p_do: r.do })); },
    async vystavPredpisy(obdobi) { return ok(await klient().rpc('vystav_predpisy', { p_obdobi: obdobi })); },
    async zpracujPlatby(platby) { return ok(await klient().rpc('zpracuj_platby', { p_platby: platby })); },
    /* Napojení banky (Fio): token uloží databáze, přečíst ho z aplikace nejde. Prázdný token = nechat stávající. */
    async ulozNapojeniBanky(token, aktivni) { return ok(await klient().rpc('uloz_napojeni_banky', { p_token: token || null, p_aktivni: aktivni !== false })); },
    /* Stáhnout platby z banky hned (Edge Function banka-sync, jen vlastní školka). */
    async nactiZBanky() {
      var r = await klient().functions.invoke('banka-sync', { body: {} });
      if (r.error) {
        var zprava = r.error.message;
        try { var t = await r.error.context.json(); if (t && t.chyba) zprava = t.chyba; } catch (e) { /* bez těla */ }
        throw new Error(zprava);
      }
      if (r.data && r.data.ok === false) throw new Error(r.data.chyba || 'Banka neodpověděla.');
      return r.data;
    },
    async sparujPlatbu(platba, dite) { return ok(await klient().rpc('sparuj_platbu', { p_platba: platba, p_dite: dite })); },
    async zapisUpominku(dite, kanal) { return ok(await klient().rpc('zapis_upominku', { p_dite: dite, p_kanal: kanal || 'push' })); },
    async archivZmen() { return ok(await klient().rpc('archiv_zmen', { p_limit: 300 })); },
    async ulozUraz(id, radek) { ok(await klient().from('urazy').update(radek).eq('id', id)); },
    async posliZpravu(komu, predmet, text, odpovedNa) {
      var radek = { skola_id: nactiUcet().skolaId, komu: komu, predmet: predmet || '', text: text, odeslal: nactiUcet().id };
      if (odpovedNa) radek.odpoved_na = odpovedNa;
      return ok(await klient().from('zpravy').insert(radek).select('id, komu, predmet, text, odeslal, odeslano, odpoved_na, od_jmeno, od_role').single());
    },

    /* --------------------------------------------- zprávy (tablet, ředitelna)
       Vše, co účet smí číst (RLS), + co už přečetl. Kanály viz migrace 2026-10-14b. */
    async zpravy() {
      var r = await Promise.all([
        klient().from('zpravy').select('id, komu, predmet, text, odeslal, odeslano, odpoved_na, od_jmeno, od_role').order('odeslano', { ascending: false }).limit(400),
        klient().from('zpravy_precteni').select('zprava_id, precteno, potvrzeno').eq('uzivatel_id', nactiUcet().id)
      ]);
      return { zpravy: ok(r[0]), precteni: ok(r[1]) };
    },
    async prectiZpravy(ids, potvrdit) {
      if (!ids || !ids.length) return 0;
      return ok(await klient().rpc('precti_zpravy', { p_ids: ids, p_potvrdit: !!potvrdit }));
    },
    /* Konverzace pro tablet a ředitelnu. Konverzace = první zpráva + odpovědi
       v jednom kanálu; odpovědi rodičů na hromadnou zprávu jsou každá zvlášť
       (soukromý kanál dítěte), první zpráva je u nich citovaná nahoře.
       zajima(m): zda nepřečtená zpráva m patří do počtu „nové“. */
    vlakna(d, zajima) {
      var ja = (nactiUcet() || {}).id, prec = {}, byId = {}, V = {};
      (d.precteni || []).forEach(function (p) { prec[p.zprava_id] = p; });
      (d.zpravy || []).forEach(function (m) { byId[m.id] = m; });
      var hromadny = function (k) { return k === 'vse' || k === 'zamestnanci' || /^trida:/.test(k); };
      (d.zpravy || []).forEach(function (m) {
        var koren = (m.odpoved_na && byId[m.odpoved_na]) || m;
        var klic = koren.id + '|' + m.komu;
        var v = V[klic] || (V[klic] = { klic: klic, koren: koren, kanal: m.komu, hromadna: hromadny(m.komu), zpravy: [], nove: [], posledni: '' });
        v.zpravy.push(m);
        if (m.odeslano > v.posledni) v.posledni = m.odeslano;
        if (m.odeslal !== ja && !prec[m.id] && (!zajima || zajima(m))) v.nove.push(m.id);
      });
      return Object.keys(V).map(function (k) {
        var v = V[k];
        v.zpravy.sort(function (a, b) { return a.odeslano < b.odeslano ? -1 : 1; });
        v.citace = v.zpravy.indexOf(v.koren) === -1;
        v.mojeKoren = v.koren.odeslal === ja;
        v.potvrzeno = !!(prec[v.koren.id] && prec[v.koren.id].potvrzeno);
        return v;
      }).sort(function (a, b) { return (b.nove.length ? 1 : 0) - (a.nove.length ? 1 : 0) || (a.posledni < b.posledni ? 1 : -1); });
    },
    /* Změna zpráv (realtime) + záloha každou minutu a po návratu do okna. */
    sledujZpravy(priZmene) {
      var t = null, kanal = klient().channel('zpravy-' + ((nactiUcet() || {}).id || 'x'));
      var hned = function () { clearTimeout(t); t = setTimeout(priZmene, 300); };
      kanal.on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'zpravy' }, hned);
      try { kanal.subscribe(); } catch (e) { /* bez realtime — interval níže */ }
      var iv = setInterval(hned, 60000);
      var vid = function () { if (document.visibilityState === 'visible') hned(); };
      document.addEventListener('visibilitychange', vid);
      return function () { clearInterval(iv); clearTimeout(t); document.removeEventListener('visibilitychange', vid); try { klient().removeChannel(kanal); } catch (e) { /* nic */ } };
    },
    async potvrzeniZprav(ids) {
      if (!ids || !ids.length) return [];
      return ok(await klient().rpc('potvrzeni_zprav', { p_ids: ids }));
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
