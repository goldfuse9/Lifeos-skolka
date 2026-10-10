/* =============================================================================
   Service worker — kvůli němu běží tablet i bez wifi ve třídě.
   Stejná strategie jako v LifeOS: napřed cache, síť jen jako záloha.
   Po každé změně souboru zvedněte VERZE, jinak si tablet nechá starou.
   ============================================================================= */

const VERZE = 'skolka-v2';
const SOUBORY = [
  './',
  './index.html',
  './dc.js',
  './shell.js',
  './Trida.dc.html',
  './manifest.webmanifest',
  './icon-180.png',
  './icon-192.png',
  './icon-512.png',
];

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(VERZE)
      .then((c) => c.addAll(SOUBORY.map((u) => new Request(u, { cache: 'reload' }))))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((k) => Promise.all(k.filter((n) => n !== VERZE).map((n) => caches.delete(n))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;

  e.respondWith(
    caches.match(req, { ignoreSearch: true }).then((zCache) => {
      if (zCache) return zCache;

      return fetch(req)
        .then((odpoved) => {
          const u = new URL(req.url);
          const nase = u.origin === location.origin;
          const pismo = u.host.endsWith('googleapis.com') || u.host.endsWith('gstatic.com');
          if (odpoved.ok && (nase || pismo)) {
            const kopie = odpoved.clone();
            caches.open(VERZE).then((c) => c.put(req, kopie));
          }
          return odpoved;
        })
        .catch(() => {
          if (req.mode === 'navigate') return caches.match('./index.html');
          return new Response('', { status: 504, statusText: 'Offline' });
        });
    }),
  );
});
