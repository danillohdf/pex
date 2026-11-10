/* Plataforma PEX · service worker: guarda a "casca" do app para abrir rápido e sem sinal.
   Os dados (Supabase) nunca passam pelo cache. Ao publicar mudanças, aumente VERSAO. */
const VERSAO = 'pex-v7';
const CASCA = ['./', 'index.html', 'config.js', 'js/supabase.min.js', 'js/backend.js', 'manifest.webmanifest', 'icons/icon.svg', 'icons/icon-192.png', 'icons/apple-touch-icon.png'];
self.addEventListener('install', e => { e.waitUntil(caches.open(VERSAO).then(c => c.addAll(CASCA)).then(() => self.skipWaiting())); });
self.addEventListener('activate', e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== VERSAO).map(k => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener('fetch', e => {
  const u = new URL(e.request.url);
  if(e.request.method !== 'GET') return;
  if(u.origin === location.origin){
    // rede primeiro (pega versão nova), cache se estiver sem sinal
    e.respondWith(fetch(e.request).then(r => { if(r.ok){ const cp = r.clone(); caches.open(VERSAO).then(c => c.put(e.request, cp)); } return r; })
      .catch(() => caches.match(e.request, {ignoreSearch: true}).then(r => r || caches.match('index.html'))));
  } else if(/fonts\.(googleapis|gstatic)\.com$/.test(u.hostname)){
    e.respondWith(caches.match(e.request).then(r => r || fetch(e.request).then(res => { const cp = res.clone(); caches.open(VERSAO).then(c => c.put(e.request, cp)); return res; })));
  }
});
