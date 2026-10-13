// Lokální „Supabase“ pro testy: /rest/v1/* → PostgREST, /auth/v1/* = zjednodušené
// GoTrue (anonymní účty, registrace e-mail+heslo, přihlášení heslem, obnova
// relace). CONFIRM=1 napodobí výchozí Supabase s potvrzováním e-mailu.
// Proměnné: PROXY_PORT (3102), PGRST_PORT (3101), PGHOST, PGPORT, DB.
const http = require('http');
const crypto = require('crypto');
const { execFileSync } = require('child_process');
const jwt = require('./jwt.js');
const PROXY_PORT = +(process.env.PROXY_PORT || 3102), PGRST_PORT = +(process.env.PGRST_PORT || 3101);
const CONF = process.env.CONFIRM === '1';
const PSQL = (q) => execFileSync('psql', ['-h', process.env.PGHOST || '/home/claude/.pgtest', '-p', process.env.PGPORT || '5499', '-U', 'postgres', '-d', process.env.DB || 'skolka_test', '-tAc', q]).toString().trim();
const lit = (s) => "'" + String(s).replace(/'/g, "''") + "'";
const hash = (h) => crypto.createHash('sha256').update('sul:' + h).digest('hex');
const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' };
const send = (res, code, o) => { res.writeHead(code, Object.assign({ 'content-type': 'application/json' }, cors)); res.end(JSON.stringify(o)); };
const user = (uid, email) => ({ id: uid, email: email || '', aud: 'authenticated', role: 'authenticated', is_anonymous: !email, identities: email ? [{ id: uid }] : [] });
const sess = (uid, email) => ({ access_token: jwt(uid, email), refresh_token: 'r-' + uid, expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600, token_type: 'bearer', user: user(uid, email) });
const bad = { error: 'invalid_grant', error_description: 'Invalid login credentials', msg: 'Invalid login credentials', error_code: 'invalid_credentials' };
http.createServer((req, res) => {
  if (req.method === 'OPTIONS') { res.writeHead(204, cors); return res.end(); }
  if (req.url.startsWith('/auth/v1/')) {
    let b = ''; req.on('data', (c) => (b += c)); req.on('end', () => {
      try {
        const d = JSON.parse(b || '{}');
        if (req.url.startsWith('/auth/v1/signup')) {
          const uid = crypto.randomUUID();
          if (!d.email) { PSQL(`insert into auth.users(id, is_anonymous) values (${lit(uid)}, true)`); return send(res, 200, sess(uid)); }
          const email = String(d.email).trim().toLowerCase();
          if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return send(res, 400, { msg: 'Unable to validate email address: invalid format', code: 400, error_code: 'validation_failed' });
          if ((d.password || '').length < 8) return send(res, 422, { msg: 'Password should be at least 8 characters.', code: 422, error_code: 'weak_password' });
          if (PSQL(`select count(*) from auth.users where email = ${lit(email)}`) !== '0') {
            if (CONF) return send(res, 200, Object.assign(user(crypto.randomUUID(), email), { identities: [] }));
            return send(res, 422, { msg: 'User already registered', code: 422, error_code: 'user_already_exists' });
          }
          PSQL(`insert into auth.users(id, email, is_anonymous, heslo, potvrzeno) values (${lit(uid)}, ${lit(email)}, false, ${lit(hash(d.password))}, ${CONF ? 'false' : 'true'})`);
          return send(res, 200, CONF ? user(uid, email) : sess(uid, email));
        }
        if (req.url.startsWith('/auth/v1/token')) {
          if (req.url.includes('grant_type=password')) {
            const email = String(d.email || '').trim().toLowerCase();
            const r = PSQL(`select id || '|' || coalesce(heslo, '') || '|' || coalesce(potvrzeno, true) from auth.users where email = ${lit(email)}`);
            const [uid, h, pot] = r.split('|');
            if (!uid || !h || h !== hash(d.password || '')) return send(res, 400, bad);
            if (pot === 'false') return send(res, 400, { code: 400, error_code: 'email_not_confirmed', msg: 'Email not confirmed' });
            return send(res, 200, sess(uid, email));
          }
          const r = String(d.refresh_token || '');
          if (!/^r-[0-9a-f-]{36}$/.test(r)) return send(res, 400, { message: 'Invalid Refresh Token', error_code: 'refresh_token_not_found' });
          const uid = r.slice(2);
          const email = PSQL(`select coalesce(email, '') from auth.users where id = ${lit(uid)}`);
          return send(res, 200, sess(uid, email || undefined));
        }
        if (req.url.startsWith('/auth/v1/logout') || req.url.startsWith('/auth/v1/recover') || req.url.startsWith('/auth/v1/resend')) { res.writeHead(204, cors); return res.end(); }
        if (req.url.startsWith('/auth/v1/user')) {
          const t = (req.headers.authorization || '').split('.')[1];
          const p = JSON.parse(Buffer.from(t || 'e30', 'base64url'));
          return send(res, 200, user(p.sub, p.email));
        }
        res.writeHead(404, cors); return res.end('{}');
      } catch (e) { return send(res, 500, { msg: String(e.message || e) }); }
    });
    return;
  }
  if (!req.url.startsWith('/rest/v1')) { res.writeHead(404, cors); return res.end('{}'); }
  const opts = { host: '127.0.0.1', port: PGRST_PORT, path: req.url.slice('/rest/v1'.length) || '/', method: req.method, headers: Object.assign({}, req.headers, { host: '127.0.0.1:' + PGRST_PORT }) };
  const p = http.request(opts, (r) => { res.writeHead(r.statusCode, Object.assign({}, r.headers, cors)); r.pipe(res); });
  p.on('error', (e) => { res.writeHead(502, cors); res.end(String(e)); });
  req.pipe(p);
}).listen(PROXY_PORT, () => console.log('proxy ' + PROXY_PORT + ' → postgrest ' + PGRST_PORT + (CONF ? ' (potvrzování e-mailu)' : '')));
