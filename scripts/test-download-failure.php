<?php
/**
 * Vérifie le diagnostic d'échec de téléchargement (src/DownloadDiagnosis.php).
 *
 * Aucune base, aucun réseau : des journaux yt-dlp en entrée, la raison lisible
 * attendue en sortie. Les cas viennent des vrais journaux de la file d'attente
 * (la vague de contrôles anti-robot du 28 septembre 2026) et des formes que
 * yt-dlp donne à ses lignes ERROR.
 *
 *   php scripts/test-download-failure.php
 */

require_once __DIR__ . '/../src/DownloadDiagnosis.php';

$failures = 0;
$checks   = 0;

function check(string $label, mixed $got, mixed $want): void
{
    global $failures, $checks;
    $checks++;
    if ($got === $want) return;
    $failures++;
    printf(
        "  ✗ %s\n      attendu : %s\n      obtenu  : %s\n",
        $label,
        var_export($want, true),
        var_export($got, true)
    );
}

/** Écrit un journal jetable et rend la raison qu'en tire le diagnostic. */
function describeLog(string $contents, int $exitCode = 1): string
{
    $file = tempnam(sys_get_temp_dir(), 'gullify-dl-');
    file_put_contents($file, $contents);
    $reason = DownloadDiagnosis::describe($file, $exitCode);
    unlink($file);
    return $reason;
}

// ── Les échecs qu'on sait nommer ─────────────────────────────────────────────
// L'apostrophe de « you’re » est bien la typographique : c'est celle que
// YouTube envoie, et la chercher telle quelle serait un piège.
$botCheck = "[youtube] Extracting URL: https://music.youtube.com/watch?v=7Fr_JCWbXco\n"
          . "ERROR: [youtube] 7Fr_JCWbXco: Sign in to confirm you’re not a bot. "
          . "Use --cookies-from-browser or --cookies for the authentication. See  "
          . "https://github.com/yt-dlp/yt-dlp/wiki/FAQ#how-do-i-pass-cookies-to-yt-dlp\n";

check(
    'contrôle anti-robot',
    describeLog($botCheck),
    'YouTube demande une vérification anti-robot : réessayez dans quelques minutes'
);

check(
    'trop de requêtes',
    describeLog("ERROR: unable to download video data: HTTP Error 429: Too Many Requests\n"),
    'YouTube limite les requêtes du serveur : réessayez plus tard'
);

check(
    'réservé aux abonnés',
    describeLog("ERROR: [youtube] abc: This video is available to Music Premium members\n"),
    'Ce disque est réservé aux abonnés YouTube Premium'
);

check(
    'titres retirés',
    describeLog("ERROR: [youtube] sM-qBQeCbwk: Video unavailable\n"),
    'Ces titres ne sont plus disponibles sur YouTube'
);

check(
    'disque plein',
    describeLog("ERROR: unable to open for writing: [Errno 28] No space left on device\n"),
    "Plus d'espace disque sur le serveur"
);

check(
    'lien inconnu',
    describeLog("ERROR: Unsupported URL: https://exemple.test/album\n"),
    'Lien non reconnu par yt-dlp'
);

// Le contrôle anti-robot prime sur les titres indisponibles : c'est lui qui
// dit s'il vaut la peine de réessayer, et YouTube masque souvent les deux dans
// le même journal.
check(
    'anti-robot avant indisponible',
    describeLog("ERROR: [youtube] a: Video unavailable\n" . $botCheck),
    'YouTube demande une vérification anti-robot : réessayez dans quelques minutes'
);

// ── Le repli sur la dernière ligne ERROR ─────────────────────────────────────
check(
    'préfixe et identifiant retirés',
    describeLog("ERROR: [youtube] AbCdEfGhIjK: Requested format is not available. "
              . "Use --list-formats for a list of available formats\n"),
    'Échec : Requested format is not available'
);

check(
    'ligne ERROR sans décorations',
    describeLog("ERROR: unable to write file\n"),
    'Échec : unable to write file'
);

check(
    'la DERNIÈRE ligne ERROR gagne',
    describeLog("ERROR: premier souci\nERROR: dernier souci\n"),
    'Échec : dernier souci'
);

check(
    'une ligne interminable est coupée',
    describeLog('ERROR: ' . str_repeat('a', 300) . "\n"),
    'Échec : ' . str_repeat('a', 120)
);

// ── Le dernier recours ───────────────────────────────────────────────────────
check(
    'journal sans ligne ERROR',
    describeLog("[download] Downloading item 1 of 12\n", 2),
    'Échec du téléchargement (code: 2)'
);

check(
    'journal vide',
    describeLog(''),
    'Échec du téléchargement (code: 1)'
);

check(
    'journal absent',
    DownloadDiagnosis::describe('/tmp/gullify-journal-qui-nexiste-pas.log', 1),
    'Échec du téléchargement (code: 1)'
);

// ── Bilan ────────────────────────────────────────────────────────────────────
echo "\n";
if ($failures === 0) {
    echo "✓ {$checks} vérifications, aucune erreur.\n";
    exit(0);
}
echo "✗ {$failures} erreur(s) sur {$checks} vérifications.\n";
exit(1);
