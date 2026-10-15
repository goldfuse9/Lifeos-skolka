// Mini „Supabase“ jen pro LOKÁLNÍ testy (nikdy ne produkce): /rest/v1/* → PostgREST, /auth/v1 = anonymní účty + e-mail/heslo.
const http = require('http');
const crypto = require('crypto');
const { execSync } = require('child_process');
const jwt = require('./jwt.js');
const DB = process.env.TEST_DB || 'skolka_lokal';
const PG = process.env.PGHOST_TEST || '/home/claude/.pgtest', PGPORT = process.env.PGPORT_TEST || '5499';
const PSQL = (q) => execSync(`psql -h ${PG} -p ${PGPORT} -U postgres -d ${DB} -tAc "${q}"`).toString().trim();
const hash = (h) => crypto.createHash('sha256').update('sul:' + h).digest('hex');
const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' };
const send = (res, code, o) => { res.writeHead(code, Object.assign({ 'content-type': 'application/json' }, cors)); res.end(JSON.stringify(o)); };
const sess = (uid, email) => ({ access_token: jwt(uid, email), refresh_token: 'r-' + uid, expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600, token_type: 'bearer', user: { id: uid, email: email || '', aud: 'authenticated', role: 'authenticated', is_anonymous: !email } });
const ok = (s) => /^[a-z0-9.@_+-]+$/i.test(s);
const fs = require('fs'), path = require('path');
/* ---- Úložiště (Supabase Storage) pro testy: soubory na disku, oprávnění přes
   RLS tabulky storage.objects — vložení/čtení/smazání řádku jako uživatel. */
const ULOZ = path.join(require('os').tmpdir(), 'skolka-storage-' + DB);
const TAJ = 'lokalni-storage-podpis';
const asUser = (claims, sql) => execSync(`psql -v ON_ERROR_STOP=1 -h ${PG} -p ${PGPORT} -U postgres -d ${DB} -tAq`, {
  input: `begin;\nset local role authenticated;\nselect set_config('request.jwt.claim.sub','${claims.sub}',true), set_config('request.jwt.claims','${JSON.stringify(claims)}',true) \\g /dev/null\n${sql}\ncommit;\n`, stdio: ['pipe', 'pipe', 'pipe'] }).toString().trim();
const podpis = (b, p, exp) => crypto.createHmac('sha256', TAJ).update(b + '/' + p + ':' + exp).digest('hex');
const okCesta = (p) => /^[A-Za-z0-9._-]+(\/[A-Za-z0-9._-]+)*$/.test(p) && !p.includes('..');
function storage(req, res) {
  const u = new URL(req.url, 'http://x');
  const cesta = decodeURIComponent(u.pathname.slice('/storage/v1/object/'.length));
  const tok = (req.headers.authorization || '').replace(/^Bearer /, '').split('.')[1];
  let claims = null; try { claims = JSON.parse(Buffer.from(tok || '', 'base64url')); } catch (e) { claims = null; }
  const chunks = []; req.on('data', (c) => chunks.push(c)); req.on('end', () => {
    const body = Buffer.concat(chunks);
    try {
      // stažení přes podepsaný odkaz (bez přihlášení)
      if (req.method === 'GET' && cesta.startsWith('sign/')) {
        const [b, ...rest] = cesta.slice(5).split('/'); const p = rest.join('/');
        const exp = +(u.searchParams.get('exp') || 0);
        if (!okCesta(p) || u.searchParams.get('token') !== podpis(b, p, exp) || exp < Date.now() / 1000) return send(res, 400, { statusCode: '400', error: 'InvalidSignature', message: 'Invalid signature' });
        const f = path.join(ULOZ, b, p); if (!fs.existsSync(f)) return send(res, 404, { statusCode: '404', error: 'not_found', message: 'Object not found' });
        res.writeHead(200, Object.assign({ 'content-type': (fs.existsSync(f + '.typ') ? fs.readFileSync(f + '.typ', 'utf8') : 'application/octet-stream') }, cors));
        return res.end(fs.readFileSync(f));
      }
      if (!claims || !/^[0-9a-f-]{36}$/.test(claims.sub || '')) return send(res, 400, { statusCode: '403', error: 'Unauthorized', message: 'Invalid JWT' });
      const vidi = (b, p) => okCesta(p) && asUser(claims, `select count(*) from storage.objects where bucket_id = '${b}' and name = '${p}';`) === '1';
      const odkaz = (b, p, exp) => '/object/sign/' + b + '/' + p + '?token=' + podpis(b, p, exp) + '&exp=' + exp;
      if (req.method === 'POST' && cesta.startsWith('sign/')) {
        const d = JSON.parse(body.toString() || '{}'); const exp = Math.floor(Date.now() / 1000) + (+d.expiresIn || 60);
        const [b, ...rest] = cesta.slice(5).split('/');
        if (!/^[a-z0-9_-]+$/.test(b)) return send(res, 400, { message: 'bad bucket' });
        if (rest.length) { const p = rest.join('/'); return vidi(b, p) ? send(res, 200, { signedURL: odkaz(b, p, exp) }) : send(res, 400, { statusCode: '404', error: 'not_found', message: 'Object not found' }); }
        return send(res, 200, (d.paths || []).map((p) => (vidi(b, p) ? { path: p, signedURL: odkaz(b, p, exp), error: null } : { path: p, signedURL: null, error: 'Either the object does not exist or you do not have access to it' })));
      }
      if (req.method === 'POST') {
        const [b, ...rest] = cesta.split('/'); const p = rest.join('/');
        if (!/^[a-z0-9_-]+$/.test(b) || !okCesta(p)) return send(res, 400, { statusCode: '400', error: 'InvalidKey', message: 'Invalid key' });
        const typ = String(req.headers['content-type'] || 'application/octet-stream').split(';')[0];
        const lim = PSQL(`select coalesce(file_size_limit, 0) || '|' || coalesce(array_to_string(allowed_mime_types, ','), '') from storage.buckets where id = '${b}'`);
        if (!lim) return send(res, 404, { statusCode: '404', error: 'Bucket not found', message: 'Bucket not found' });
        const [max, typy] = lim.split('|');
        if (+max && body.length > +max) return send(res, 413, { statusCode: '413', error: 'Payload too large', message: 'The object exceeded the maximum allowed size' });
        if (typy && !typy.split(',').includes(typ)) return send(res, 415, { statusCode: '415', error: 'invalid_mime_type', message: 'mime type ' + typ + ' is not supported' });
        try { asUser(claims, `insert into storage.objects (bucket_id, name, owner, metadata) values ('${b}', '${p}', '${claims.sub}', '{"mimetype":"${typ}","size":${body.length}}');`); }
        catch (e) { const m = String(e.stderr || e.message); return m.includes('duplicate') ? send(res, 409, { statusCode: '409', error: 'Duplicate', message: 'The resource already exists' }) : send(res, 403, { statusCode: '403', error: 'Unauthorized', message: 'new row violates row-level security policy' }); }
        const f = path.join(ULOZ, b, p); fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f, body); fs.writeFileSync(f + '.typ', typ);
        return send(res, 200, { Key: b + '/' + p, Id: crypto.randomUUID() });
      }
      if (req.method === 'DELETE') {
        const b = cesta; const d = JSON.parse(body.toString() || '{}'); const ps = (d.prefixes || []).filter(okCesta);
        if (!/^[a-z0-9_-]+$/.test(b)) return send(res, 400, { message: 'bad bucket' });
        if (!ps.length) return send(res, 200, []);
        const sm = asUser(claims, `delete from storage.objects where bucket_id = '${b}' and name in (${ps.map((p) => "'" + p + "'").join(',')}) returning name;`).split('\n').filter(Boolean);
        sm.forEach((p) => { try { fs.unlinkSync(path.join(ULOZ, b, p)); fs.unlinkSync(path.join(ULOZ, b, p + '.typ')); } catch (e) { /* nic */ } });
        return send(res, 200, sm.map((p) => ({ name: p, bucket_id: b })));
      }
      return send(res, 404, { message: 'not found' });
    } catch (e) { return send(res, 500, { msg: String(e.stderr || e.message || e) }); }
  });
}
http.createServer((req, res) => {
  if (req.method === 'OPTIONS') { res.writeHead(204, cors); return res.end(); }
  if (req.url.startsWith('/auth/v1/')) {
    let b = ''; req.on('data', (c) => (b += c)); req.on('end', () => {
      const d = JSON.parse(b || '{}');
      try {
        if (req.url.startsWith('/auth/v1/signup')) {
          const uid = crypto.randomUUID();
          if (d.email) {
            const email = String(d.email).toLowerCase();
            if (!ok(email)) return send(res, 400, { msg: 'Unable to validate email address: invalid format', code: 400 });
            if ((d.password || '').length < 8) return send(res, 422, { msg: 'Password should be at least 8 characters.', code: 422, error_code: 'weak_password' });
            const CONF = process.env.CONFIRM === '1' || email.endsWith('@potvrdit.test');  // e-maily @potvrdit.test vyžadují potvrzení
            if (PSQL(`select count(*) from auth.users where email='${email}'`) !== '0') {
              if (CONF) return send(res, 200, { id: crypto.randomUUID(), email, identities: [], aud: 'authenticated', role: 'authenticated' });
              return send(res, 422, { msg: 'User already registered', code: 422, error_code: 'user_already_exists' });
            }
            PSQL(`insert into auth.users(id, email, is_anonymous, heslo, potvrzeno) values ('${uid}', '${email}', false, '${hash(d.password)}', ${CONF ? 'false' : 'true'})`);
            if (CONF) return send(res, 200, { id: uid, email, identities: [{ id: uid }], aud: 'authenticated', role: 'authenticated', confirmation_sent_at: new Date().toISOString() });
            return send(res, 200, sess(uid, email));
          }
          PSQL(`insert into auth.users(id, is_anonymous) values ('${uid}', true)`);
          return send(res, 200, sess(uid));
        }
        if (req.url.startsWith('/auth/v1/token')) {
          if (req.url.includes('grant_type=password')) {
            const email = String(d.email || '').toLowerCase();
            if (!ok(email)) return send(res, 400, { error: 'invalid_grant', error_description: 'Invalid login credentials', msg: 'Invalid login credentials', error_code: 'invalid_credentials' });
            const r = PSQL(`select id||'|'||coalesce(heslo,'')||'|'||coalesce(potvrzeno,true) from auth.users where email='${email}'`);
            const [uid, h, pot] = r.split('|');
            if (!uid || (h && h !== hash(d.password || ''))) return send(res, 400, { error: 'invalid_grant', error_description: 'Invalid login credentials', msg: 'Invalid login credentials', error_code: 'invalid_credentials' });
            if (pot === 'false') return send(res, 400, { code: 400, error_code: 'email_not_confirmed', msg: 'Email not confirmed' });
            return send(res, 200, sess(uid, email));
          }
          const r = d.refresh_token || '';
          if (!r.startsWith('r-')) return send(res, 400, { message: 'Invalid Refresh Token' });
          const uid = r.slice(2); const email = PSQL(`select coalesce(email,'') from auth.users where id='${uid}'`);
          return send(res, 200, sess(uid, email || undefined));
        }
        if (req.url.startsWith('/auth/v1/logout')) { res.writeHead(204, cors); return res.end(); }
        if (req.url.startsWith('/auth/v1/recover') || req.url.startsWith('/auth/v1/resend')) return send(res, 200, {});  // jako Supabase
        if (req.url.startsWith('/auth/v1/user')) {
          const t = (req.headers.authorization || '').split('.')[1]; const p = JSON.parse(Buffer.from(t || 'e30', 'base64url'));
          if (req.method === 'PUT' && d.password) {
            if (String(d.password).length < 8) return send(res, 422, { msg: 'Password should be at least 8 characters.', error_code: 'weak_password' });
            if (!/^[0-9a-f-]{36}$/.test(p.sub || '')) return send(res, 401, { msg: 'invalid JWT' });
            PSQL(`update auth.users set heslo='${hash(d.password)}' where id='${p.sub}'`);
          }
          return send(res, 200, { id: p.sub, email: p.email || '', aud: 'authenticated' });
        }
        res.writeHead(404, cors); return res.end('{}');
      } catch (e) { return send(res, 500, { msg: String(e.message || e) }); }
    });
    return;
  }
  if (req.url.startsWith('/storage/v1/')) return storage(req, res);
  if (!req.url.startsWith('/rest/v1')) { res.writeHead(404, cors); return res.end('{}'); }
  const opts = { host: '127.0.0.1', port: +(process.env.PGRST_PORT || 3001), path: req.url.slice('/rest/v1'.length) || '/', method: req.method, headers: Object.assign({}, req.headers, { host: '127.0.0.1:3001' }) };
  const p = http.request(opts, (r) => { res.writeHead(r.statusCode, r.headers); r.pipe(res); });
  p.on('error', (e) => { res.writeHead(502); res.end(String(e)); });
  req.pipe(p);
}).listen(+(process.env.PROXY_PORT || 3002), () => console.log('proxy', process.env.PROXY_PORT || 3002, DB));
