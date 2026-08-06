#!/usr/bin/env php
<?php
/**
 * Gullify - Rendu d'une version karaoké (idée #63)
 *
 * Lancé en tâche de fond par l'API (`api/v2/karaoke.php?action=prepare`), ou
 * à la main pour préparer un titre :
 *
 *   php scripts/render-karaoke.php "Artiste/Album/01 - Titre.mp3"
 *
 * Tout le travail est dans src/Karaoke.php ; ce script n'est là que pour
 * sortir ffmpeg de la requête HTTP.
 */

require_once __DIR__ . '/../src/Karaoke.php';

if (PHP_SAPI !== 'cli') {
    http_response_code(403);
    exit("CLI uniquement\n");
}

$relativePath = $argv[1] ?? '';
if ($relativePath === '') {
    fwrite(STDERR, "Usage: render-karaoke.php <chemin/relatif/du/fichier>\n");
    exit(1);
}

$result = Karaoke::render($relativePath);
echo $result['status'] . ($result['reason'] ? ' (' . $result['reason'] . ')' : '') . "\n";
exit($result['status'] === 'ready' ? 0 : 1);
