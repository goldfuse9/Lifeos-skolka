// Spustí všechny E2E testy (nebo vybrané: node e2e/spust.js superadmin pristupy).
// Před spuštěním: tests/reset.sh && tests/stack.sh
const T = require('./pomocnik');
const fs = require('fs'), path = require('path');
const VSE = ['superadmin', 'pristupy', 'pozvanka-potvrzeni', 'scenar-trida-rodic'];
(async () => {
  const vyber = process.argv.slice(2).length ? process.argv.slice(2) : VSE;
  const b = await T.prohlizec();
  const souhrn = [];
  for (const n of vyber) {
    console.log('\n== ' + n);
    try { (await require('./' + n)(b)).forEach((v) => souhrn.push(Object.assign({ test: n }, v))); }
    catch (e) { console.log('FAIL  ' + n + ' spadl: ' + String(e.message || e).split('\n')[0]); souhrn.push({ test: n, nazev: 'test doběhl', ok: false, detail: String(e.message || e).split('\n')[0] }); }
  }
  await b.close();
  const f = souhrn.filter((v) => !v.ok);
  fs.writeFileSync(path.join(T.OUT, 'e2e.json'), JSON.stringify(souhrn, null, 1));
  console.log(`\n==== E2E celkem: PASS ${souhrn.length - f.length} · FAIL ${f.length}`);
  f.forEach((v) => console.log('  ✗ ' + v.test + ': ' + v.nazev + (v.detail ? ' (' + v.detail + ')' : '')));
  process.exit(f.length ? 1 : 0);
})();
