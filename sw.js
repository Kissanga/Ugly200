const CACHE_NAME = 'ugly200-v96';
const STATIC_ASSETS = [
  './',
  './index.html',
  './guide.html',
  './mp4box.all.min.js',
  './manifest.json',
  './icon-192.png',
  './icon-512.png',
  './icon-192-maskable.png',
  './icon-512-maskable.png',
  './skins/index.json',
  './skins/naked-farm.json',
  './skins/ocean.json',
];

// Install: cache all static assets
// Precache with cache:'reload' so install always takes fresh files from the
// server — a plain addAll() may copy stale icons/HTML out of the HTTP cache
// into the new cache (seen with the v1.53 icon change).
self.addEventListener('install', e => {
  self.skipWaiting();
  e.waitUntil(
    caches.open(CACHE_NAME).then(cache => cache.addAll(STATIC_ASSETS.map(u => new Request(u, { cache: 'reload' }))))
  );
});

// Activate: purge old caches
self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

// Fetch strategy:
//   • HTML / navigations → NETWORK-FIRST (so new releases always reach the
//     device when online; cache is only the offline fallback). Serving the
//     HTML cache-first is what previously pinned phones to an old index.html
//     and made shipped fixes invisible.
//   • Other same-origin static assets (icons, manifest) → cache-first.
//   • Cross-origin API calls (Groq, Notion proxy) → straight to network.
self.addEventListener('fetch', e => {
  const { request } = e;
  const url = new URL(request.url);

  // Let external API calls (Groq, Notion proxy) go straight to network
  if (!url.origin.startsWith(self.location.origin)) return;
  if (request.method !== 'GET') return;
  // version.json is the update signal: always straight to the network, never cached.
  if (url.pathname.endsWith('/version.json')) return;

  const isHTML = request.mode === 'navigate' ||
    request.destination === 'document' ||
    /\/(index\.html)?$/.test(url.pathname);

  if (isHTML) {
    // Network-first: fetch fresh HTML, fall back to cache only when offline.
    // cache:'no-cache' forces revalidation — a plain fetch() may be answered
    // from the HTTP cache (GitHub Pages: max-age=600) and hand out the previous
    // release for up to 10 minutes (also for the SoP iframe page).
    e.respondWith(
      fetch(new Request(request.url, { cache: 'no-cache', credentials: 'same-origin' })).then(response => {
        if (response && response.status === 200 && response.type !== 'opaque') {
          const clone = response.clone();
          caches.open(CACHE_NAME).then(cache => cache.put(request, clone));
        }
        return response;
      }).catch(() =>
        caches.match(request).then(c => c || caches.match('./index.html'))
      )
    );
    return;
  }

  // Cache-first for other same-origin static assets
  e.respondWith(
    caches.match(request).then(cached => {
      if (cached) return cached;
      return fetch(request).then(response => {
        if (response.status === 200 && response.type !== 'opaque') {
          const clone = response.clone();
          caches.open(CACHE_NAME).then(cache => cache.put(request, clone));
        }
        return response;
      });
    }).catch(() => {
      // Offline fallback: serve index.html for navigation requests
      if (request.mode === 'navigate') {
        return caches.match('./index.html');
      }
    })
  );
});

// Handle shortcut action: focus or open the app
self.addEventListener('notificationclick', e => {
  e.notification.close();
  e.waitUntil(
    self.clients.matchAll({ type: 'window' }).then(clients => {
      if (clients.length) return clients[0].focus();
      return self.clients.openWindow('./');
    })
  );
});
