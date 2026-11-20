// Backing Pad: funciona offline depois do primeiro uso
const V='bpad-v4';
const CORE=['./','index.html','manifest.webmanifest','icon-192.png','icon-512.png','icon-180.png'];
self.addEventListener('install',e=>{e.waitUntil(caches.open(V).then(c=>c.addAll(CORE)).then(()=>self.skipWaiting()))});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==V).map(k=>caches.delete(k)))).then(()=>self.clients.claim()))});
self.addEventListener('fetch',e=>{
  const req=e.request;if(req.method!=='GET')return;
  const url=new URL(req.url);
  // página: tenta a rede primeiro (pega atualizações), cai para o cache sem internet
  if(req.mode==='navigate'||url.pathname.endsWith('/index.html')){
    e.respondWith(fetch(req).then(r=>{const c=r.clone();caches.open(V).then(x=>x.put(req,c));return r}).catch(()=>caches.match(req).then(r=>r||caches.match('index.html'))));
    return;
  }
  // sons, rastreamento de mãos e ícones: cache primeiro
  const cacheable=url.origin===location.origin||/cdn\.jsdelivr\.net|storage\.googleapis\.com|gleitz\.github\.io/.test(url.host);
  if(!cacheable)return;
  e.respondWith(caches.match(req).then(hit=>hit||fetch(req).then(r=>{if(r.ok){const c=r.clone();caches.open(V).then(x=>x.put(req,c))}return r})));
});
