// Shell em cache para abrir offline; dados sempre tentam a rede primeiro.
const VERSAO = "nr-v3";
const SHELL = ["./", "index.html", "manifest.webmanifest", "icons/icon-192.png", "icons/apple-touch-icon.png", "data/fontes.json"];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(VERSAO).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener("activate", e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== VERSAO).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});

async function redePrimeiro(req) {
  const c = await caches.open(VERSAO);
  try {
    const r = await fetch(req, {cache: "no-cache"});
    if (r.ok) c.put(req, r.clone());
    return r;
  } catch (err) {
    const hit = await c.match(req, {ignoreSearch: true});
    if (hit) return hit;
    throw err;
  }
}
async function cacheComAtualizacao(req) {
  const c = await caches.open(VERSAO);
  const hit = await c.match(req);
  const rede = fetch(req).then(r => { if (r.ok || r.type === "opaque") c.put(req, r.clone()); return r; }).catch(() => hit);
  return hit || rede;
}

self.addEventListener("fetch", e => {
  const url = new URL(e.request.url);
  if (e.request.method !== "GET") return;
  if (url.hostname === "api.github.com") return;
  if (url.hostname.endsWith("fonts.googleapis.com") || url.hostname.endsWith("fonts.gstatic.com")) {
    e.respondWith(cacheComAtualizacao(e.request));
    return;
  }
  if (url.origin !== location.origin) return;
  if (e.request.mode === "navigate" || url.pathname.endsWith(".json") || url.pathname.endsWith("/") || url.pathname.endsWith("index.html")) {
    e.respondWith(redePrimeiro(e.request));
    return;
  }
  e.respondWith(cacheComAtualizacao(e.request));
});
