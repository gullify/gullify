<?php
/**
 * gullify.app/tv — l'APK, pour installer Gullify sur un téléviseur.
 *
 * Une adresse courte parce qu'on la saisit à la télécommande, lettre par
 * lettre, dans une app de téléchargement (Downloader et consorts). Elle
 * renvoie toujours vers le lien « latest » de download.gullify.app, que
 * `build-app.sh` remet à jour à chaque version : rien à changer ici quand
 * une nouvelle sort.
 *
 * Une fois l'app installée, ce chemin ne sert plus : elle se met à jour
 * toute seule (voir `state/app_update.dart`).
 */
declare(strict_types=1);

const LATEST = 'https://download.gullify.app/gullify-latest.apk';

// Le client demande explicitement du HTML (un navigateur de bureau) : on lui
// montre une page. Tout le reste — les gestionnaires de téléchargement des
// téléviseurs — reçoit l'APK directement.
$accept = $_SERVER['HTTP_ACCEPT'] ?? '';
$wantsPage = isset($_GET['page']) || str_contains($accept, 'text/html');

if (!$wantsPage) {
    header('Location: ' . LATEST, true, 302);
    exit;
}

$manifest = @file_get_contents('https://download.gullify.app/version.json');
$version = null;
if ($manifest !== false) {
    $j = json_decode($manifest, true);
    $version = is_array($j) ? ($j['versionName'] ?? null) : null;
}
?>
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Gullify pour Google TV</title>
<link rel="icon" href="/favicon.ico">
<style>
  body {
    margin: 0; min-height: 100vh; display: grid; place-items: center;
    background: #14161C; color: #EDEFF3; padding: 24px;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  }
  .card {
    max-width: 520px; text-align: center;
    background: rgba(255,255,255,.06); border: 1px solid rgba(255,255,255,.14);
    border-radius: 26px; padding: 40px 34px;
  }
  h1 { font-size: 34px; font-weight: 800; letter-spacing: -1px; margin: 0 0 6px; }
  p { color: #9BA0AA; line-height: 1.6; margin: 14px 0 0; }
  code {
    background: rgba(255,255,255,.1); padding: 3px 9px; border-radius: 6px;
    font-size: .95em; color: #EDEFF3;
  }
  a.dl {
    display: inline-block; margin-top: 26px; padding: 16px 30px;
    background: #4A5FE8; color: #fff; text-decoration: none;
    border-radius: 30px; font-weight: 700; font-size: 17px;
    box-shadow: 0 12px 30px rgba(74,95,232,.4);
  }
  ol { text-align: left; color: #9BA0AA; line-height: 1.7; margin-top: 22px; }
</style>
</head>
<body>
<div class="card">
  <h1>Gullify pour Google&nbsp;TV</h1>
  <p><?= $version ? 'Version ' . htmlspecialchars($version, ENT_QUOTES) : 'Dernière version' ?></p>
  <a class="dl" href="<?= LATEST ?>">Télécharger l'APK</a>
  <ol>
    <li>Sur le téléviseur, installe une app de téléchargement (Downloader, par exemple).</li>
    <li>Saisis <code>gullify.app/tv</code> — l'APK arrive directement.</li>
    <li>Autorise l'installation depuis cette source quand Android le demande.</li>
  </ol>
  <p>Ensuite, plus besoin de revenir ici : Gullify vérifie ses mises à jour tout seul et les installe depuis la télé.</p>
</div>
</body>
</html>
