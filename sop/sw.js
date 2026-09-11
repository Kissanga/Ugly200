const CACHE_NAME = 'sopapp-v3';
const STATIC_ASSETS = [
  './',
  './index.html',
  './icon-192.png',
  './icon-512.png',
];

// Precache with cache:'reload' so install always takes fresh files from the
// server — a plain addAll() may copy stale icons/HTML out of the HTTP cache
// into the new cache (seen with the v1.53 icon change).
self.addEventListener('install', e => {
  self.skipWaiting();
  e.waitUntil(caches.open(CACHE_NAME).then(cache => cache.addAll(STATIC_ASSETS.map(u => new Request(u, { cache: 'reload' })))));
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

// HTML → network-first, so a new release always reaches the phone when online
// (a cache-first index.html is what pinned Brain+ phones to stale builds).
// Other same-origin assets → cache-first. Cross-origin (Worker, CDN) → untouched;
// SOP content is cached by the app itself in IndexedDB, not here.
self.addEventListener('fetch', e => {
  const { request } = e;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin || request.method !== 'GET') return;
  if (url.pathname.endsWith('/version.json')) return;

  const isHTML = request.mode === 'navigate' || request.destination === 'document' ||
    /\/(index\.html)?$/.test(url.pathname);

  if (isHTML) {
    // cache: 'no-cache' makes the request revalidate with the server; a plain
    // fetch() may be answered from the browser's HTTP cache (GitHub Pages sends
    // max-age=600), which would still hand out a stale index.html.
    e.respondWith(
      fetch(new Request(request.url, { cache: 'no-cache', credentials: 'same-origin' })).then(response => {
        if (response && response.status === 200) {
          const clone = response.clone();
          caches.open(CACHE_NAME).then(cache => cache.put('./index.html', clone));
        }
        return response;
      }).catch(() => caches.match('./index.html'))
    );
    return;
  }

  e.respondWith(
    caches.match(request).then(cached => cached || fetch(request).then(response => {
      if (response.status === 200) {
        const clone = response.clone();
        caches.open(CACHE_NAME).then(cache => cache.put(request, clone));
      }
      return response;
    }))
  );
});
