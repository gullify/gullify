<?php
/**
 * gullify.app — la page d'accueil publique de GulliFY.
 *
 * Même design que vr.madeli.co : la gamme partage un seul site, seules la
 * couleur d'accent et la teneur changent. Les styles vivent dans
 * assets/base.css (les jetons et la marque) et assets/site.css (la page) ;
 * rien en ligne, rien d'externe.
 *
 * Elle ne demande aucune connexion : elle dit ce qu'est GulliFY, donne l'app
 * (web ou Android) et explique comment l'installer. Tout ce qui demande un
 * compte vit DANS l'app — y compris l'administration des utilisateurs et du
 * stockage. C'est ce qui permet de n'entretenir qu'une seule interface.
 *
 * La version de l'APK est lue dans download/version.json, écrit par
 * build-app.sh : pas d'appel réseau au chargement de la page.
 */
declare(strict_types=1);

const APK_LATEST = 'https://download.gullify.app/gullify-latest.apk';

$manifeste = @file_get_contents(__DIR__ . '/download/version.json');
$version = null;
$notes = null;
if ($manifeste !== false) {
    $j = json_decode($manifeste, true);
    if (is_array($j)) {
        $version = $j['versionName'] ?? null;
        $notes = $j['changelog'] ?? null;
    }
}

$apk = __DIR__ . '/download/gullify.apk';
$poids = is_file($apk) ? round(filesize($apk) / 1048576) : null;

/** Échappement court, la page en est pleine. */
function e(?string $s): string {
    return htmlspecialchars((string)$s, ENT_QUOTES, 'UTF-8');
}
?>
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>GulliFY — votre musique, sur tous vos écrans</title>
<meta name="description" content="Le lecteur de votre bibliothèque musicale : navigateur, Android, Android Auto et Google TV. Vos fichiers, sur votre serveur.">
<meta name="theme-color" content="#07080e">
<link rel="icon" href="/favicon.ico">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="stylesheet" href="/assets/base.css">
<link rel="stylesheet" href="/assets/site.css">
<script src="/assets/site.js" defer></script>
</head>
<body>

<a class="saut" href="#contenu">Aller au contenu</a>

<header class="barre">
  <a class="marque" href="/">
    <img class="marque-signe" src="/assets/gulli-mark.png" width="43" height="60" alt="" decoding="async">
    <span class="marque-mot">Gulli<span class="fy">FY</span></span>
  </a>
  <nav class="barre-nav" aria-label="Liens du site">
    <a href="#atouts">L'app</a>
    <a href="#gamme">La gamme</a>
    <a href="#installation">Installation</a>
    <a href="#serveur">Le serveur</a>
    <a href="#nouveautes">Nouveautés</a>
    <a class="lien-app" href="/app/">Ouvrir l'app</a>
  </nav>
</header>

<main id="contenu">

  <section class="heros">
    <div class="heros-texte">
      <p class="surtitre"><span class="point"></span>Lecteur audio · votre serveur</p>
      <h1 class="marque">
        <img class="marque-signe" src="/assets/gulli-mark.png" width="76" height="108" alt="" decoding="async">
        <span class="marque-mot">Gulli<span class="fy">FY</span></span>
      </h1>
      <p class="promesse">Votre musique, sur tous vos écrans. Vos fichiers, sur
        votre serveur — rien à confier à personne.</p>
      <div class="actions">
        <a class="bouton principal" href="/app/">Ouvrir l'app web</a>
        <a class="bouton secondaire" href="<?= APK_LATEST ?>">
          Télécharger pour Android
          <span class="bouton-version"><?= $version ? 'v' . e($version) : '' ?></span>
        </a>
      </div>
      <ul class="specs">
        <li>Navigateur</li>
        <li>Android</li>
        <li>Android Auto</li>
        <li>Google TV</li>
        <li>Windows &amp; iPhone</li>
        <li>OpenSubsonic</li>
      </ul>
    </div>

    <!-- L'app, dessinée en CSS : pas de capture à refaire à chaque version. -->
    <div class="maquette" aria-hidden="true">
      <div class="maq-corps">
        <div class="maq-rail">
          <p class="maq-marque">
            <img src="/assets/gulli-mark.png" alt="" decoding="async">
            <span class="nom">Gulli<span class="fy">FY</span></span>
          </p>
          <p class="maq-nav"><span class="maq-pastille"></span>Accueil</p>
          <p class="maq-nav actif"><span class="maq-pastille"></span>Bibliothèque</p>
          <p class="maq-nav"><span class="maq-pastille"></span>Recherche</p>
          <p class="maq-nav"><span class="maq-pastille"></span>Radio</p>
          <p class="maq-nav"><span class="maq-pastille"></span>Favoris</p>
          <p class="maq-titre">Playlists</p>
          <p class="maq-nav"><span class="maq-pastille"></span>Route de nuit</p>
          <p class="maq-nav"><span class="maq-pastille"></span>Matins calmes</p>
        </div>
        <div class="maq-liste">
          <p class="maq-entete">Albums <span>2 714 · 23 558 titres</span></p>
          <ul class="maq-titres">
            <li class="maq-piste en-cours">
              <span class="maq-pochette"></span>
              <b>Reel à Aristide</b><i>Bertrand Déraspe</i>
              <span class="maq-duree">3:12</span>
            </li>
            <li class="maq-piste">
              <span class="maq-pochette"></span>
              <b>Chanson à Antoine</b><i>Bertrand Déraspe</i>
              <span class="maq-duree">2:48</span>
            </li>
            <li class="maq-piste">
              <span class="maq-pochette"></span>
              <b>45 Tours</b><i>Jonathan Painchaud</i>
              <span class="maq-duree">4:05</span>
            </li>
            <li class="maq-piste">
              <span class="maq-pochette"></span>
              <b>Contre vent et marées</b><i>Bertrand Déraspe</i>
              <span class="maq-duree">3:37</span>
            </li>
          </ul>
        </div>
      </div>
      <div class="maq-lecteur">
        <span class="maq-pochette"></span>
        <span class="maq-infos">
          <b class="maq-nom">Reel à Aristide</b>
          <span class="maq-artiste">Bertrand Déraspe</span>
        </span>
        <span class="maq-commandes">
          <span class="maq-bouton"></span>
          <span class="maq-bouton jouer"></span>
          <span class="maq-bouton"></span>
        </span>
        <span class="maq-barre-temps"></span>
      </div>
    </div>
  </section>

  <section id="atouts" class="section">
    <h2 class="titre-section reveal">Une seule app, sur tous vos écrans</h2>
    <p class="intro-section reveal">Le navigateur, le téléphone, la voiture et
      le salon partagent le même code et la même interface. Ce que vous
      apprenez quelque part sert partout.</p>

    <div class="grille-atouts">
      <article class="atout reveal">
        <span class="atout-signe" aria-hidden="true">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/></svg>
        </span>
        <h3>Votre bibliothèque</h3>
        <p>Vos fichiers, sur votre serveur. Pochettes, genres et années rangés
          comme vous l'entendez — rien ne part ailleurs.</p>
      </article>

      <article class="atout reveal">
        <span class="atout-signe" aria-hidden="true">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M4 6h16M4 11h10M4 16h13M4 21h7"/></svg>
        </span>
        <h3>Paroles et accords</h3>
        <p>Les paroles défilent au rythme de la chanson, la grille d'accords se
          transpose et défile toute seule pendant que vous jouez.</p>
      </article>

      <article class="atout reveal">
        <span class="atout-signe" aria-hidden="true">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M5 17h14M6.5 17l1.2-5.2A2 2 0 0 1 9.6 10h4.8a2 2 0 0 1 1.9 1.8L17.5 17"/><circle cx="7.5" cy="19" r="1.5"/><circle cx="16.5" cy="19" r="1.5"/></svg>
        </span>
        <h3>Android Auto</h3>
        <p>Toute la bibliothèque au tableau de bord, en gros boutons — et la
          lecture aléatoire d'un genre d'un seul geste.</p>
      </article>

      <article class="atout reveal">
        <span class="atout-signe" aria-hidden="true">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><rect x="2.5" y="5" width="19" height="12.5" rx="2"/><path d="M8.5 21h7"/></svg>
        </span>
        <h3>Google TV</h3>
        <p>Une interface pensée pour la télécommande et pour être lue à trois
          mètres : pochettes en grand, paroles plein écran, jeux à plusieurs.</p>
      </article>

      <article class="atout reveal">
        <span class="atout-signe" aria-hidden="true">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><ellipse cx="12" cy="6" rx="8" ry="3"/><path d="M4 6v12c0 1.7 3.6 3 8 3s8-1.3 8-3V6"/><path d="M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3"/></svg>
        </span>
        <h3>Compatible OpenSubsonic</h3>
        <p>Vos autres lecteurs préférés se branchent sur le même serveur :
          genres, playlists, favoris et recherche y sont exposés.</p>
      </article>

      <article class="atout reveal">
        <span class="atout-signe" aria-hidden="true">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M7 11h4M9 9v4M15.5 11h.01M18 13h.01"/><rect x="2.5" y="6.5" width="19" height="11" rx="4"/></svg>
        </span>
        <h3>Des jeux, à plusieurs</h3>
        <p>Blind test, frise des années, pochette mystère — chacun son
          téléphone, la télé fait l'arbitre.</p>
      </article>
    </div>
  </section>

  <section id="gamme" class="section">
    <div class="bande-cadre">
      <div class="bande-texte">
        <h2 class="titre-section">Une gamme, un même nom</h2>
        <p class="intro-section">Gulli ne bouge pas : chaque lecteur a sa
          couleur et son écran de prédilection. Même façon de faire, même
          façon de s'installer.</p>
      </div>
      <ul class="gamme">
        <li>
          <span class="gamme-signe fy">FY</span>
          <div>
            <h3><span class="nom">Gulli<span class="fy">FY</span></span></h3>
            <p>Votre musique. Navigateur, Android, Android Auto et Google TV.
              Vous y êtes.</p>
          </div>
        </li>
        <li>
          <span class="gamme-signe tv">TV</span>
          <div>
            <h3><span class="nom">Gulli<span class="tv">TV</span></span>
              <span class="bientot">Bientôt</span></h3>
            <p>La télévision : vos chaînes IPTV, leur programme en cours, vos
              favoris.</p>
          </div>
        </li>
        <li>
          <span class="gamme-signe vr">VR</span>
          <div>
            <h3><span class="nom">Gulli<span class="vr">VR</span></span></h3>
            <p>Le casque : vidéo immersive, IPTV et vos sites, sur Meta Quest.
              <a href="https://vr.madeli.co">vr.madeli.co</a></p>
          </div>
        </li>
      </ul>
    </div>
  </section>

  <section id="installation" class="section">
    <h2 class="titre-section reveal">L'installer, en une minute</h2>
    <p class="intro-section reveal">Rien à publier sur un magasin
      d'applications : GulliFY s'installe depuis cette page, et se met à jour
      tout seul ensuite.</p>

    <ol class="etapes">
      <li class="reveal">
        <span class="etape-num">1</span>
        <h3>Android</h3>
        <p>Téléchargez l'APK<?= $poids ? ' (' . $poids . ' Mo)' : '' ?> et
          autorisez l'installation depuis cette source quand Android le
          demande.</p>
        <p><a href="<?= APK_LATEST ?>">Télécharger l'APK</a><?= $version ? ' — version ' . e($version) : '' ?></p>
      </li>
      <li class="reveal">
        <span class="etape-num">2</span>
        <h3>Windows</h3>
        <p>Ouvrez <a href="/app/">l'app web</a> dans Chrome ou Edge, puis
          l'icône d'installation dans la barre d'adresse — ou menu
          <kbd>⋯</kbd> → <em>Installer GulliFY</em>.</p>
        <p>Elle s'ouvre alors dans sa propre fenêtre, comme un logiciel.</p>
      </li>
      <li class="reveal">
        <span class="etape-num">3</span>
        <h3>iPhone et iPad</h3>
        <p>Ouvrez <a href="/app/">l'app web</a> dans Safari, puis
          <em>Partager</em> → <em>Sur l'écran d'accueil</em>.</p>
        <p>Elle s'ouvre en plein écran, sans barre de navigateur.</p>
      </li>
    </ol>

    <p class="apres">
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="2.5" y="5" width="19" height="12.5" rx="2"/><path d="M8.5 21h7"/></svg>
      <span><strong>Sur un téléviseur :</strong> installez une app de
        téléchargement, puis saisissez <kbd>gullify.app/tv</kbd> à la
        télécommande — l'APK arrive directement.
        <a href="/tv?page=1">Voir la marche à suivre</a></span>
    </p>
  </section>

  <section id="serveur" class="section">
    <h2 class="titre-section reveal">Le serveur aussi est à vous</h2>
    <p class="intro-section reveal">L'app n'est que la façade. Derrière, un
      serveur que vous installez chez vous, sur un vieil ordinateur ou un petit
      VPS : la musique ne quitte pas votre disque, et le code est ouvert — vous
      pouvez le lire, le modifier, le faire tourner sans nous.</p>

    <div class="serveur">
      <ul class="serveur-faits">
        <li class="reveal">
          <h3>PHP et MySQL, en trois conteneurs</h3>
          <p>Docker Compose monte l'app, la base et Caddy — qui va chercher
            tout seul le certificat de votre domaine.</p>
        </li>
        <li class="reveal">
          <h3>Vos dossiers, tels quels</h3>
          <p>Un disque local ou un accès SFTP. Le scan lit les tags, récupère
            les pochettes et range albums, genres et années.</p>
        </li>
        <li class="reveal">
          <h3>Plusieurs comptes</h3>
          <p>Chacun sa bibliothèque, ses favoris et ses statistiques.
            L'administration se fait dans l'app, pas dans un fichier.</p>
        </li>
        <li class="reveal">
          <h3>Une API OpenSubsonic</h3>
          <p>Symfonium, DSub, Ultrasonic et les autres se branchent sur le même
            serveur, en plus des apps GulliFY.</p>
        </li>
      </ul>

      <div class="serveur-console reveal">
        <p class="console-titre">Quatre lignes</p>
<pre><code>git clone https://github.com/gullify/gullify.git
cd gullify
cp .env.example .env<span class="commentaire">   # domaine, mots de passe</span>
docker compose up -d</code></pre>
        <p class="console-note">Ouvrez ensuite votre domaine : l'assistant
          crée le premier compte et lance le premier scan.</p>
        <p class="serveur-liens">
          <a class="bouton secondaire" href="https://github.com/gullify/gullify">
            <svg width="18" height="18" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82a7.4 7.4 0 0 1 2-.27c.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8Z"/></svg>
            Le code sur GitHub</a>
          <span class="licence">Logiciel libre —
            <a href="https://www.gnu.org/licenses/agpl-3.0.html">AGPL&#8209;3.0</a></span>
        </p>
      </div>
    </div>
  </section>

  <section id="nouveautes" class="section">
    <h2 class="titre-section reveal">Nouveautés</h2>
    <div class="carte-version reveal">
      <?php if ($version): ?>
        <p class="version-etiquette">Version <?= e($version) ?></p>
      <?php endif; ?>
      <p class="version-notes"><?= $notes
        ? e($notes)
        : 'L\'app se met à jour toute seule : les nouveautés arrivent sans rien faire.' ?></p>
    </div>
  </section>

</main>

<a class="haut" href="#contenu" aria-label="Revenir en haut de la page">
  <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true" focusable="false"><path d="M12 19V6m0 0-6 6m6-6 6 6" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/></svg>
</a>

<footer class="pied">
  <div class="pied-cadre">
    <span class="pied-marque">Gulli<span class="fy">FY</span></span>
    <span class="pied-note">Votre musique, sur votre serveur<?= $version ? ' — app v' . e($version) : '' ?>.</span>
    <span class="pied-liens">
      <a href="/app/">Ouvrir l'app</a> ·
      <a href="/tv?page=1">Google TV</a> ·
      <a href="https://vr.madeli.co">GulliVR</a> ·
      <a href="https://github.com/gullify/gullify">Le code (AGPL-3.0)</a>
    </span>
  </div>
</footer>

</body>
</html>
