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
