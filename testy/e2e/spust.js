// Spustí E2E testy po jednom (každý na čerstvě obnovených datech).
//   node e2e/spust.js [název…]   bez názvu = všechny
const { execSync } = require('child_process');
const path = require('path');
const { souhrn, DB } = require('./spolecne');
const VSE = ['superadmin', 'pristupy', 'ucitele', 'porady', 'pozvanka-potvrzeni', 'tablet-rodic', 'uloziste', 'reditelna', 'jidelna', 'tablet', 'zpravy', 'ucet', 'zkusebni'];
(async () => {
  const vyber = process.argv.slice(2).length ? process.argv.slice(2) : VSE;
  for (const n of vyber) {
    execSync(`${path.join(__dirname, '..', 'reset.sh')} ${DB}`, { stdio: 'ignore' });
    console.log(`\n== ${n}`);
    try { await require('./' + n)(); } catch (e) { require('./spolecne').kontrola(n + ' doběhl', false, String(e).split('\n')[0]); await require('./spolecne').konec(); }
  }
  process.exit(souhrn() ? 1 : 0);
})();
