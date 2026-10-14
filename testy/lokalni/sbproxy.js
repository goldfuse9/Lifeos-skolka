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
  if (!req.url.startsWith('/rest/v1')) { res.writeHead(404, cors); return res.end('{}'); }
  const opts = { host: '127.0.0.1', port: +(process.env.PGRST_PORT || 3001), path: req.url.slice('/rest/v1'.length) || '/', method: req.method, headers: Object.assign({}, req.headers, { host: '127.0.0.1:3001' }) };
  const p = http.request(opts, (r) => { res.writeHead(r.statusCode, r.headers); r.pipe(res); });
  p.on('error', (e) => { res.writeHead(502); res.end(String(e)); });
  req.pipe(p);
}).listen(+(process.env.PROXY_PORT || 3002), () => console.log('proxy', process.env.PROXY_PORT || 3002, DB));
