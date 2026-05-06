const CACHE_NAME = 'ugly200-v12';
const STATIC_ASSETS = [
  './',
  './index.html',
  './guide.html',
  './manifest.json',
  './icon-192.png',
  './icon-512.png',
];

// Install: cache all static assets
self.addEventListener('install', e => {
  self.skipWaiting();
  e.waitUntil(
    caches.open(CACHE_NAME).then(cache => cache.addAll(STATIC_ASSETS))
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

// Fetch: cache-first for static assets, network-first for API calls
self.addEventListener('fetch', e => {
  const { request } = e;
  const url = new URL(request.url);

  // Let external API calls (Groq, Notion proxy) go straight to network
  if (!url.origin.startsWith(self.location.origin)) return;

  // Cache-first for same-origin static assets
  e.respondWith(
    caches.match(request).then(cached => {
      if (cached) return cached;
      return fetch(request).then(response => {
        // Only cache valid same-origin GET responses
        if (
          request.method === 'GET' &&
          response.status === 200 &&
          response.type !== 'opaque'
        ) {
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
