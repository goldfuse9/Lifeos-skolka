/* =============================================================================
   Service worker — kvůli němu běží tablet i bez wifi ve třídě.
   Stejná strategie jako v LifeOS: napřed cache, síť jen jako záloha.
   Po každé změně souboru zvedněte VERZE, jinak si tablet nechá starou.
   ============================================================================= */

const VERZE = 'skolka-v32';
const SOUBORY = [
  './',
  './index.html',
  './dc.js',
  './qrcode.js',
  './vendor/supabase-2.115.0.js',
  './config.js',
  './server.js',
  './shell.js',
  './Trida.dc.html',
  './Reditel.dc.html',
  './Jidelna.dc.html',
  './Prihlaseni.dc.html',
  './Admin.dc.html',
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

/* Naše soubory: napřed síť (ať je vždy poslední verze a skořápka sedí
   k deskám), cache jen když síť nejde — tablet tak funguje i bez wifi.
   Písma: napřed cache, mění se zřídka. */
self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const u = new URL(req.url);
  const nase = u.origin === location.origin;
  const pismo = u.host.endsWith('googleapis.com') || u.host.endsWith('gstatic.com');
  if (!nase && !pismo) return;

  if (pismo) {
    e.respondWith(caches.match(req).then((z) => z || fetch(req).then((o) => {
      if (o.ok) { const k = o.clone(); caches.open(VERZE).then((c) => c.put(req, k)); }
      return o;
    })));
    return;
  }

  e.respondWith(
    fetch(req, { cache: 'no-cache' })
      .then((odpoved) => {
        if (odpoved.ok) { const kopie = odpoved.clone(); caches.open(VERZE).then((c) => c.put(req, kopie)); }
        return odpoved;
      })
      .catch(() => caches.match(req, { ignoreSearch: true })
        .then((z) => z || (req.mode === 'navigate' ? caches.match('./index.html') : new Response('', { status: 504, statusText: 'Offline' })))),
  );
});
