// Apparitions au défilement. Le script pose `js` sur <html> : sans lui (ou
// sans JavaScript), tout reste visible — les blocs ne sont masqués que si
// quelqu'un est là pour les révéler.
(function () {
  var racine = document.documentElement;
  racine.classList.add('js');

  var blocs = document.querySelectorAll('.reveal');
  if (!('IntersectionObserver' in window)) {
    for (var i = 0; i < blocs.length; i++) blocs[i].classList.add('vu');
    return;
  }

  var observateur = new IntersectionObserver(function (entrees) {
    entrees.forEach(function (e) {
      if (!e.isIntersecting) return;
      e.target.classList.add('vu');
      observateur.unobserve(e.target);
    });
  }, { rootMargin: '0px 0px -10% 0px', threshold: 0.08 });

  blocs.forEach(function (b) { observateur.observe(b); });
})();

// La flèche de retour en haut : elle ne se montre qu'une fois la page
// descendue de plus d'un écran. Le défilement est confié au navigateur (le
// lien pointe vers le début du contenu, et `scroll-behavior` l'adoucit).
(function () {
  var fleche = document.querySelector('.haut');
  if (!fleche) return;

  var visible = false;
  var enAttente = false;

  function mesure() {
    enAttente = false;
    var doit = window.scrollY > window.innerHeight * 0.8;
    if (doit === visible) return;
    visible = doit;
    fleche.classList.toggle('vue', doit);
  }

  window.addEventListener('scroll', function () {
    // Une mesure par image au plus : un défilement en émet des dizaines.
    if (enAttente) return;
    enAttente = true;
    window.requestAnimationFrame(mesure);
  }, { passive: true });

  mesure();
})();
