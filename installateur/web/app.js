// L'installateur, côté page.
//
// Rien de plus qu'il n'en faut : pas de bibliothèque, pas de construction. La
// page interroge l'état en boucle et se met à jour — une installation est
// linéaire, et ce qui compte est qu'on voie toujours où on en est.

const CLE = new URLSearchParams(location.search).get('cle') || '';

/** Appelle l'installateur local. La clé accompagne chaque demande. */
async function api(chemin, options = {}) {
  const reponse = await fetch(chemin, {
    ...options,
    headers: { 'Content-Type': 'application/json', 'X-Cle': CLE, ...(options.headers || {}) },
  });
  if (!reponse.ok) {
    throw new Error(`l'installateur a répondu ${reponse.status}`);
  }
  return reponse.json();
}

const $ = (s) => document.querySelector(s);
const etapes = [...document.querySelectorAll('.etape')];

let etapeAffichee = null;
let dernierJournal = 0;

function montre(nom) {
  if (etapeAffichee === nom) return;
  etapeAffichee = nom;
  if (nom === 'reseau') regardeReseau();
  if (nom === 'fini') verifieDepuisDehors();
  for (const section of etapes) {
    section.hidden = section.dataset.etape !== nom;
  }
  window.scrollTo({ top: 0, behavior: 'smooth' });
}

// ── La boucle d'état ─────────────────────────────────────────────────────────

async function rafraichir() {
  let etat;
  try {
    etat = await api('/api/etat');
  } catch {
    return; // l'installateur s'est peut-être fermé ; la page le dira d'elle-même
  }

  // Le journal, en ajout seulement : on ne réécrit pas tout à chaque tour.
  if (etat.journal && etat.journal.length !== dernierJournal) {
    const journal = $('#journal');
    journal.textContent = etat.journal.join('\n');
    journal.scrollTop = journal.scrollHeight;
    dernierJournal = etat.journal.length;
  }

  $('#jauge').style.width = `${etat.progression || 0}%`;

  if (etat.courriel) $('#rappel-courriel').textContent = etat.courriel;
  if (etat.adresse) {
    $('#adresse-finale').textContent = etat.adresse;
    $('#ouvrir-serveur').href = `https://${etat.adresse}`;
  }

  if (etat.erreur && etapeAffichee === 'installation') {
    const boite = $('#erreur-installation');
    boite.textContent = etat.erreur;
    boite.hidden = false;
  }

  // L'installateur commande : la page suit. C'est lui qui sait, par exemple,
  // que le courriel vient d'être confirmé.
  if (etat.etape && etat.etape !== etapeAffichee) {
    const ordonnees = ['bienvenue', 'docker', 'nom', 'confirmation', 'reglages', 'installation', 'fini'];
    if (ordonnees.indexOf(etat.etape) >= ordonnees.indexOf(etapeAffichee || 'bienvenue')) {
      montre(etat.etape);
      if (etat.etape === 'reglages') chargeDossiers(etat.dossierMusique || '');
    }
  }
}

// ── 1 et 2 : Docker ──────────────────────────────────────────────────────────

async function regardeDocker() {
  const carte = $('#carte-docker');
  carte.innerHTML = '<p class="attente">Je regarde…</p>';
  $('#installer-docker').hidden = true;
  $('#docker-suivant').hidden = true;

  let d;
  try {
    d = await api('/api/docker');
  } catch (e) {
    carte.innerHTML = `<p class="attente">${e.message}</p>`;
    return;
  }

  if (d.demarre && d.compose) {
    carte.innerHTML = `<h2>Tout est prêt</h2><p>Docker ${d.version || ''} tourne sur cette machine.</p>`;
    $('#docker-suivant').hidden = false;
    return;
  }

  carte.innerHTML = `<h2>${d.installe ? 'Presque' : 'Il manque Docker'}</h2><p>${d.explique || ''}</p>`;
  $('#installer-docker').hidden = d.installe; // installé mais arrêté : rien à installer
}

$('#revoir-docker').addEventListener('click', regardeDocker);

$('#installer-docker').addEventListener('click', async () => {
  $('#installer-docker').disabled = true;
  $('#carte-docker').innerHTML = '<p class="attente">Installation en cours… (regarde la fenêtre noire si elle demande quelque chose)</p>';
  await api('/api/docker/installer', { method: 'POST' });
  // Le reste se suit dans le journal ; on revérifie régulièrement.
  const minuteur = setInterval(async () => {
    const d = await api('/api/docker');
    if (d.demarre && d.compose) {
      clearInterval(minuteur);
      $('#installer-docker').disabled = false;
      regardeDocker();
    }
  }, 5000);
});

// ── 3 : le réseau ────────────────────────────────────────────────────────────

const PASTILLES = { ouvert: '✓', ferme: '!', cgnat: '✕', inconnu: '?' };

function montreReseau(d) {
  const carte = $('#carte-reseau');
  const verdict = d.verdict || 'inconnu';

  const details = [];
  if (d.ipLocale) details.push(`Cette machine : ${d.ipLocale}`);
  if (d.ipPublique) details.push(`Vue d'Internet : ${d.ipPublique}`);
  if (d.ipRouteur && d.ipRouteur !== d.ipPublique) details.push(`Ton routeur croit avoir : ${d.ipRouteur}`);
  if (d.routeur) details.push(`Routeur : ${d.routeur}`);

  carte.innerHTML =
    `<div class="verdict-reseau">
       <span class="pastille-verdict ${verdict}">${PASTILLES[verdict] || '?'}</span>
       <div><p>${d.explique || ''}</p>
       ${details.length ? `<div class="detail-reseau">${details.map((l) => `<span>${l}</span>`).join('')}</div>` : ''}
       </div>
     </div>`;

  const marche = $('#marche-reseau');
  marche.textContent = d.marche || '';
  marche.hidden = !d.marche;

  // Trois issues, trois jeux de boutons : ouvrir, continuer, ou continuer en
  // sachant que le serveur ne sera joignable que depuis la maison.
  $('#ouvrir-ports').hidden = !(verdict === 'ferme' && d.upnp);
  $('#reseau-suivant').hidden = verdict !== 'ouvert';
  $('#reseau-quand-meme').hidden = verdict === 'ouvert';
}

async function regardeReseau() {
  $('#carte-reseau').innerHTML = '<p class="attente">Je regarde…</p>';
  for (const id of ['ouvrir-ports', 'reseau-suivant', 'reseau-quand-meme']) $(`#${id}`).hidden = true;
  try {
    montreReseau(await api('/api/reseau'));
  } catch (e) {
    $('#carte-reseau').innerHTML = `<p class="attente">${e.message}</p>`;
  }
}

$('#revoir-reseau').addEventListener('click', regardeReseau);

$('#ouvrir-ports').addEventListener('click', async () => {
  const bouton = $('#ouvrir-ports');
  bouton.disabled = true;
  $('#carte-reseau').innerHTML = '<p class="attente">Je parle à ton routeur…</p>';
  try {
    montreReseau(await api('/api/reseau/ouvrir', { method: 'POST' }));
  } finally {
    bouton.disabled = false;
  }
});

// ── 3 : le nom ───────────────────────────────────────────────────────────────

let minuteurNom = null;
const champNom = $('#nom');
const champCourriel = $('#courriel');
const verdict = $('#verdict-nom');

function nomValide() {
  return verdict.classList.contains('libre') && /\S+@\S+\.\S+/.test(champCourriel.value);
}

function majBoutonReserver() {
  $('#reserver').disabled = !nomValide();
}

champNom.addEventListener('input', () => {
  const nom = champNom.value.trim().toLowerCase();
  verdict.className = 'verdict attente';
  verdict.textContent = nom ? 'Je vérifie…' : '';
  majBoutonReserver();

  clearTimeout(minuteurNom);
  if (!nom) return;

  // On attend que la frappe se calme : inutile d'interroger le service à
  // chaque lettre.
  minuteurNom = setTimeout(async () => {
    try {
      const r = await api(`/api/nom/verifier?nom=${encodeURIComponent(nom)}`);
      if (champNom.value.trim().toLowerCase() !== nom) return; // déjà changé
      verdict.className = `verdict ${r.libre ? 'libre' : 'pris'}`;
      verdict.textContent = r.libre ? `${r.adresse} est libre.` : r.motif;
    } catch (e) {
      verdict.className = 'verdict pris';
      verdict.textContent = e.message;
    }
    majBoutonReserver();
  }, 400);
});

champCourriel.addEventListener('input', majBoutonReserver);

$('#reserver').addEventListener('click', async () => {
  const bouton = $('#reserver');
  bouton.disabled = true;
  $('#erreur-nom').hidden = true;

  const r = await api('/api/nom/reserver', {
    method: 'POST',
    body: JSON.stringify({ nom: champNom.value.trim().toLowerCase(), courriel: champCourriel.value.trim() }),
  });

  if (r.erreur) {
    $('#erreur-nom').textContent = r.erreur;
    $('#erreur-nom').hidden = false;
    bouton.disabled = false;
    return;
  }
  montre('confirmation');
  attendreConfirmation();
});

// ── 4 : l'attente du courriel ────────────────────────────────────────────────

function attendreConfirmation() {
  const minuteur = setInterval(async () => {
    try {
      const r = await api('/api/nom/attendre');
      if (r.confirme) {
        clearInterval(minuteur);
        montre('reglages');
        chargeDossiers('');
      }
    } catch { /* on réessaiera au tour suivant */ }
  }, 3000);
}

// ── 5 : dossier et compte ────────────────────────────────────────────────────

let dossierCourant = '';

async function chargeDossiers(chemin) {
  const r = await api(`/api/dossiers?chemin=${encodeURIComponent(chemin || '')}`);
  dossierCourant = r.chemin;
  $('#chemin-choisi').textContent = r.chemin;
  $('#remonter').disabled = !r.parent;
  $('#remonter').dataset.parent = r.parent || '';

  const liste = $('#liste-dossiers');
  liste.innerHTML = '';

  if (!r.dossiers || r.dossiers.length === 0) {
    const vide = document.createElement('li');
    vide.className = 'vide';
    vide.textContent = r.erreur || "Aucun sous-dossier ici — c'est peut-être le bon.";
    liste.appendChild(vide);
    return;
  }

  for (const nom of r.dossiers) {
    const item = document.createElement('li');
    item.textContent = nom;
    item.addEventListener('click', () => chargeDossiers(`${r.chemin}/${nom}`));
    liste.appendChild(item);
  }
}

$('#remonter').addEventListener('click', (e) => {
  const parent = e.currentTarget.dataset.parent;
  if (parent) chargeDossiers(parent);
});

$('#installer').addEventListener('click', async () => {
  const bouton = $('#installer');
  bouton.disabled = true;
  $('#erreur-reglages').hidden = true;

  const r = await api('/api/reglages', {
    method: 'POST',
    body: JSON.stringify({
      dossierMusique: dossierCourant,
      utilisateur: $('#utilisateur').value.trim(),
      motDePasse: $('#motdepasse').value,
    }),
  });

  if (r.erreur) {
    $('#erreur-reglages').textContent = r.erreur;
    $('#erreur-reglages').hidden = false;
    bouton.disabled = false;
    return;
  }

  montre('installation');
  await api('/api/installer', { method: 'POST' });
});

// ── 7 : la preuve, depuis l'extérieur ────────────────────────────────────────

async function verifieDepuisDehors() {
  const carte = $('#carte-joignable');
  carte.innerHTML = '<h2>Depuis l\'extérieur</h2><p class="attente">Je vérifie si ton serveur répond depuis Internet…</p>';

  let r;
  try {
    r = await api('/api/joignable');
  } catch (e) {
    carte.innerHTML = `<h2>Depuis l'extérieur</h2><p>${e.message}</p>`;
    return;
  }

  if (r.joignable) {
    carte.innerHTML =
      '<h2>Depuis l\'extérieur</h2>' +
      '<p>Ton serveur répond depuis Internet : ta musique te suivra partout.</p>';
    return;
  }

  // Le cas le plus fréquent : le certificat n'est pas encore là, ou le routeur
  // s'est refermé. On le dit sans dramatiser, et on laisse réessayer — rien
  // n'est perdu, le serveur fonctionne déjà chez soi.
  carte.innerHTML =
    '<h2>Depuis l\'extérieur, pas encore</h2>' +
    `<p>Ton serveur ne répond pas encore depuis Internet${r.motif ? ' — ' + r.motif : ''}. ` +
    'Chez toi, il fonctionne déjà. Si tu viens d\'ouvrir ton routeur, laisse-lui une minute.</p>' +
    '<p><button class="bouton secondaire" id="rever-dehors">Réessayer</button></p>';
  $('#rever-dehors').addEventListener('click', verifieDepuisDehors);
}

// ── 8 : fermer ───────────────────────────────────────────────────────────────

$('#fermer').addEventListener('click', async () => {
  await api('/api/fermer', { method: 'POST' });
  document.body.innerHTML =
    '<main class="cadre"><h1>À bientôt</h1>' +
    '<p class="intro">Tu peux fermer cette page.</p></main>';
});

// Les boutons qui ne font qu'avancer d'un écran.
for (const bouton of document.querySelectorAll('[data-aller]')) {
  bouton.addEventListener('click', () => {
    montre(bouton.dataset.aller);
    if (bouton.dataset.aller === 'docker') regardeDocker();
  });
}

montre('bienvenue');
setInterval(rafraichir, 1500);
rafraichir();
