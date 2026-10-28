const VERSION = 'family-hub-static-v2';
const SHELL = './';
const PRECACHE = ['./', './manifest.webmanifest', './icons/icon.svg', './icons/favicon.svg', './icons/icon-192.png', './icons/icon-512.png', './icons/apple-touch-icon.png'];

self.addEventListener('install', event => {
  event.waitUntil(caches.open(VERSION).then(cache => cache.addAll(PRECACHE)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key.startsWith('family-hub-static-') && key !== VERSION).map(key => caches.delete(key)))).then(() => self.clients.claim()));
});
self.addEventListener('message', event => {
  if (event.data === 'SKIP_WAITING') self.skipWaiting();
});
self.addEventListener('fetch', event => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;
  // No API/auth/user data is stored by this worker. Supabase is cross-origin and bypasses this handler.
  if (/\/(rest|auth|realtime|storage|functions)\//.test(url.pathname)) return;
  if (req.mode === 'navigate') {
    event.respondWith(fetch(req).then(response => {
      if (response.ok) caches.open(VERSION).then(cache => cache.put(SHELL, response.clone()));
      return response;
    }).catch(async () => {
      const cached = await caches.match(SHELL);
      return cached || new Response('<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Нет сети — Family Hub</title><body style="font:16px system-ui;background:#10100f;color:#f0ebdd;padding:12vh 8vw"><h1>Нет подключения</h1><p>Family Hub не может загрузить оболочку приложения. Подключитесь к интернету и попробуйте снова.</p></body></html>', {status: 503, headers: {'Content-Type':'text/html; charset=utf-8'}});
    }));
    return;
  }
  // Cache only static same-origin resources; never cache API data or private family records.
  event.respondWith(fetch(req).then(response => {
    if (response.ok && response.type === 'basic' && /\.(?:js|css|svg|png|webmanifest|woff2?)$/i.test(url.pathname)) {
      const copy = response.clone(); caches.open(VERSION).then(cache => cache.put(req, copy));
    }
    return response;
  }).catch(async () => {
    const cached = await caches.match(req);
    return cached || new Response('Этот ресурс недоступен без подключения к интернету.', {status: 503, headers: {'Content-Type':'text/plain; charset=utf-8'}});
  }));
});
