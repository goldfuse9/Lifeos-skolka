const crypto = require('crypto');
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
module.exports = (sub, email) => { const pl = { sub, role: 'authenticated', aud: 'authenticated', exp: Math.floor(Date.now() / 1000) + 7200 }; if (email) pl.email = email;
  const h = b64({ alg: 'HS256', typ: 'JWT' }), p = b64(pl);
  return h + '.' + p + '.' + crypto.createHmac('sha256', 'tajny-testovaci-klic-pro-postgrest-0123456789').update(h + '.' + p).digest('base64url'); };
