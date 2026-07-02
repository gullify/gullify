<?php
/**
 * Gullify app download page.
 * Serves the Android APK built by build-app.sh (public/download/gullify.apk).
 */
$apk = __DIR__ . '/gullify.apk';
$hasApk = is_file($apk);

if (isset($_GET['apk'])) {
    if (!$hasApk) {
        http_response_code(404);
        exit('APK non disponible');
    }
    header('Content-Type: application/vnd.android.package-archive');
    header('Content-Disposition: attachment; filename="gullify.apk"');
    header('Content-Length: ' . filesize($apk));
    readfile($apk);
    exit;
}
?>
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Gullify — Application mobile</title>
    <style>
        body {
            font-family: system-ui, sans-serif;
            background: #0f0f14;
            color: #eee;
            display: flex;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
            margin: 0;
        }
        .card {
            text-align: center;
            padding: 40px;
            max-width: 420px;
        }
        img { width: 96px; height: 96px; }
        h1 { font-size: 1.5rem; }
        p { color: #aaa; line-height: 1.5; }
        .btn {
            display: inline-block;
            margin-top: 16px;
            padding: 14px 28px;
            background: #7c4dff;
            color: #fff;
            border-radius: 12px;
            text-decoration: none;
            font-weight: 600;
        }
        .muted { font-size: .85rem; color: #777; margin-top: 24px; }
    </style>
</head>
<body>
    <div class="card">
        <img src="../android-chrome-192x192.png" alt="Gullify">
        <h1>Gullify pour Android</h1>
        <?php if ($hasApk): ?>
            <p>Installez l'application mobile Gullify sur votre appareil Android
               (autorisez l'installation de sources inconnues si demandé).</p>
            <a class="btn" href="?apk=1">Télécharger l'APK
                (<?= round(filesize($apk) / 1048576) ?> Mo)</a>
            <p class="muted">Version du <?= date('Y-m-d', filemtime($apk)) ?></p>
        <?php else: ?>
            <p>L'APK n'a pas encore été publié sur ce serveur.<br>
               Exécutez <code>./build-app.sh</code> depuis le dépôt pour le générer.</p>
        <?php endif; ?>
    </div>
</body>
</html>
