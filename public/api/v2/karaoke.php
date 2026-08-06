<?php
/**
 * Gullify API v2 — Versions karaoké (idée #63)
 *
 *   GET ?path=…            → état, et rendu lancé en tâche de fond si besoin
 *
 * Réponse : {status: "ready"|"rendering"|"unavailable", reason: ?string}
 *   ready       — stream.php?path=…&karaoke=1 sert la version voix atténuée
 *   rendering   — ffmpeg travaille, redemander dans une seconde ou deux
 *   unavailable — définitif pour ce fichier (voir src/Karaoke.php)
 *
 * Le rendu coûte du CPU : cette porte-là demande une session. Le flux, lui,
 * passe par stream.php, qui ne fait que servir un rendu déjà là.
 */
declare(strict_types=1);

require_once __DIR__ . '/_v2.php';
require_once __DIR__ . '/../../../src/Karaoke.php';

v2_auth();

$path = trim((string)($_GET['path'] ?? ''));
if ($path === '') {
    v2_fail('missing_path', 'Paramètre path manquant');
}

$state = Karaoke::prepare($path);
v2_ok(['status' => $state['status'], 'reason' => $state['reason']]);
