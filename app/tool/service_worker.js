// Le service worker de l'app web Gullify.
//
// Il remplace, à la construction (voir build-web.sh), celui que Flutter
// génère — lequel se DÉSINSCRIT de lui-même : Flutter a abandonné la mise en
// cache par défaut, et laisse donc l'app sans aucun service worker actif. Or
// un navigateur exige un service worker muni d'un gestionnaire `fetch` pour
// considérer une page comme une application installable. Sans lui, Chrome ne
// propose qu'un raccourci — et un raccourci n'utilise pas les icônes du
// manifeste.
//
// Il ne met RIEN en cache, volontairement : une app de 44 Mo mise en cache
// servirait des versions périmées après chaque déploiement, ce qui est un
// problème pire que l'absence de mode hors ligne.
//
// Le gestionnaire `fetch` ne s'interpose que sur les navigations. Les autres
// requêtes — et surtout le flux audio, qui se lit par plages (Range) — ne
// sont pas touchées : les faire transiter par un service worker casse la
// lecture par plages sur plusieurs navigateurs.

self.addEventListener('install', () => {
  // Prendre la main tout de suite : sinon la première visite reste sans
  // service worker, et c'est précisément elle qui décide de l'installation.
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', (event) => {
  if (event.request.mode === 'navigate') {
    event.respondWith(fetch(event.request));
  }
  // Tout le reste suit son cours normal, sans passer par ici.
});
