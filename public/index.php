<?php
/**
 * gullify.app — la page d'accueil publique de GulliFY.
 *
 * Elle ne demande aucune connexion : elle dit ce qu'est GulliFY, donne l'app
 * (web ou Android) et explique comment l'installer. Tout ce qui demande un
 * compte vit DANS l'app — y compris l'administration des utilisateurs et du
 * stockage, portée depuis la vieille interface web (voir
 * `app/lib/screens/admin/`). C'est ce qui permet de n'entretenir qu'une seule
 * interface.
 *
 * La version de l'APK est lue dans `download/version.json`, écrit par
 * `build-app.sh` : pas d'appel réseau au chargement de la page.
 */
declare(strict_types=1);

const APK_LATEST = 'https://download.gullify.app/gullify-latest.apk';

$manifest = @file_get_contents(__DIR__ . '/download/version.json');
$apkVersion = null;
if ($manifest !== false) {
    $j = json_decode($manifest, true);
    $apkVersion = is_array($j) ? ($j['versionName'] ?? null) : null;
}

$apk = __DIR__ . '/download/gullify.apk';
$apkSize = is_file($apk) ? round(filesize($apk) / 1048576) : null;

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
<title>GulliFY — votre musique, partout</title>
<meta name="description" content="Votre bibliothèque musicale, sur le web, sur Android, en voiture et au salon.">
<meta name="theme-color" content="#14161C">
<link rel="icon" href="/favicon.ico">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<style>
  /* La palette est celle de l'app (voir app/lib/theme.dart) : même surface
     sombre, même accent indigo, même gris de texte secondaire. La page et
     l'app doivent se ressembler — c'est tout l'objet de la manœuvre. */
  :root {
    /* Le vert de la marque : celui du fond de l'icône. Il colore le « FY » du
       logo — chaque entité de la gamme a le sien (GulliTV en rouge, GulliVR
       en mauve). */
    --fy: #2C6774;
    --bg: #14161C;
    --fg: #EDEFF3;
    --muted: #9BA0AA;
    --accent: #4A5FE8;
    --line: rgba(255, 255, 255, .12);
    --card: rgba(255, 255, 255, .05);
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    background: var(--bg);
    color: var(--fg);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    line-height: 1.6;
    /* Un halo d'accent en haut, comme le fond de l'app. */
    background-image:
      radial-gradient(900px 500px at 50% -12%, rgba(74, 95, 232, .30), transparent 70%);
    background-repeat: no-repeat;
  }
  .wrap { max-width: 940px; margin: 0 auto; padding: 0 22px; }

  header { text-align: center; padding: 76px 0 20px; }
  header img { width: 92px; height: 92px; border-radius: 22px; }
  .fy { color: var(--fy); }
  h1 {
    font-size: clamp(38px, 7vw, 62px); font-weight: 800;
    letter-spacing: -1.8px; margin: 22px 0 8px;
  }
  .tagline { color: var(--muted); font-size: clamp(17px, 2.4vw, 21px); margin: 0; }

  .actions {
    display: flex; flex-wrap: wrap; gap: 14px;
    justify-content: center; margin: 34px 0 8px;
  }
  .btn {
    display: inline-flex; align-items: center; gap: 10px;
    padding: 15px 28px; border-radius: 30px;
    text-decoration: none; font-weight: 700; font-size: 16.5px;
    border: 1px solid transparent; transition: transform .12s ease;
  }
  .btn:active { transform: translateY(1px); }
  .btn-primary {
    background: var(--accent); color: #fff;
    box-shadow: 0 14px 34px rgba(74, 95, 232, .38);
  }
  .btn-ghost {
    background: var(--card); color: var(--fg); border-color: var(--line);
  }
  .btn small { font-weight: 500; opacity: .75; }

  section { padding: 54px 0 0; }
  h2 {
    font-size: 13px; font-weight: 700; letter-spacing: 1.1px;
    text-transform: uppercase; color: var(--accent); margin: 0 0 18px;
  }

  .grid { display: grid; gap: 16px; grid-template-columns: repeat(auto-fit, minmax(262px, 1fr)); }
  .card {
    background: var(--card); border: 1px solid var(--line);
    border-radius: 20px; padding: 24px 22px;
  }
  .card h3 { margin: 0 0 6px; font-size: 18px; font-weight: 700; }
  .card p, .card ol { color: var(--muted); margin: 8px 0 0; font-size: 15px; }
  .card ol { padding-left: 20px; }
  .card ol li { margin: 5px 0; }
  .card a { color: var(--fg); }
  kbd {
    background: rgba(255, 255, 255, .10); border: 1px solid var(--line);
    border-radius: 6px; padding: 2px 7px; font-size: .88em;
    font-family: inherit; color: var(--fg);
  }

  .features { list-style: none; padding: 0; margin: 0; }
  .features li {
    padding: 13px 0; border-top: 1px solid var(--line);
    color: var(--muted); font-size: 15.5px;
  }
  .features li:first-child { border-top: 0; }
  .features b { color: var(--fg); font-weight: 600; }

  footer {
    margin-top: 64px; padding: 26px 0 40px;
    border-top: 1px solid var(--line);
    color: var(--muted); font-size: 13.5px;
    display: flex; flex-wrap: wrap; gap: 8px 20px; justify-content: space-between;
  }
  footer a { color: var(--muted); }
</style>
</head>
<body>
<div class="wrap">

  <header>
    <img src="/android-chrome-192x192.png" alt="">
    <h1>Gulli<span class="fy">FY</span></h1>
    <p class="tagline">Votre musique, partout.</p>

    <div class="actions">
      <a class="btn btn-primary" href="/app/">Ouvrir l'app web</a>
      <a class="btn btn-ghost" href="<?= APK_LATEST ?>">
        Android
        <?php if ($apkVersion || $apkSize): ?>
          <small><?= e($apkVersion ? 'v' . $apkVersion : '') ?><?= $apkSize ? ' · ' . $apkSize . ' Mo' : '' ?></small>
        <?php endif; ?>
      </a>
    </div>
  </header>

  <section>
    <h2>La même app, partout</h2>
    <ul class="features">
      <li><b>Une seule application.</b> Le web, Android, Android&nbsp;Auto et Google&nbsp;TV partagent le même code et la même interface.</li>
      <li><b>Votre bibliothèque.</b> Vos fichiers, sur votre serveur — rien à confier à personne.</li>
      <li><b>Paroles et accords</b> qui défilent au rythme de la chanson, karaoké, fondu enchaîné.</li>
      <li><b>Compatible OpenSubsonic</b> : vos autres lecteurs préférés savent s'y brancher.</li>
    </ul>
  </section>

  <section>
    <h2>L'installer</h2>
    <div class="grid">

      <div class="card">
        <h3>Android</h3>
        <p>Téléchargez l'APK et autorisez l'installation depuis cette source
           quand Android le demande. Ensuite, GulliFY se met à jour tout seul.</p>
        <p><a href="<?= APK_LATEST ?>">Télécharger l'APK</a><?php if ($apkVersion): ?>
           — version <?= e($apkVersion) ?><?php endif; ?></p>
      </div>

      <div class="card">
        <h3>Windows</h3>
        <ol>
          <li>Ouvrez <a href="/app/">l'app web</a> dans Chrome ou Edge.</li>
          <li>Cliquez l'icône d'installation dans la barre d'adresse — ou menu
              <kbd>⋯</kbd> → <em>Installer GulliFY</em>.</li>
          <li>Elle s'ouvre alors dans sa propre fenêtre, comme un logiciel.</li>
        </ol>
      </div>

      <div class="card">
        <h3>iPhone et iPad</h3>
        <ol>
          <li>Ouvrez <a href="/app/">l'app web</a> dans Safari.</li>
          <li>Bouton <em>Partager</em> → <em>Sur l'écran d'accueil</em>.</li>
          <li>Elle s'ouvre en plein écran, sans barre de navigateur.</li>
        </ol>
      </div>

      <div class="card">
        <h3>Google TV</h3>
        <p>Installez une app de téléchargement sur le téléviseur, puis saisissez
           <kbd>gullify.app/tv</kbd> à la télécommande : l'APK arrive
           directement.</p>
        <p><a href="/tv?page=1">Voir la marche à suivre</a></p>
      </div>

    </div>
  </section>

  <footer>
    <span>Gulli<span class="fy">FY</span><?= $apkVersion ? ' — app v' . e($apkVersion) : '' ?></span>
    <span><a href="/app/">Ouvrir l'app</a><?php if (is_dir(__DIR__ . '/legacy')): ?>
      · <a href="/legacy/">Ancienne interface web</a><?php endif; ?></span>
  </footer>

</div>
</body>
</html>
