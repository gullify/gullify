<?php
/**
 * Ramène les genres déjà en base dans la liste fermée (src/GenreTaxonomy.php).
 *
 * Une bibliothèque accumule les étiquettes de ses fichiers : « Melodic Death
 * Metal », « Punk Rock », « Music », « Français »… Ce script les traduit une
 * bonne fois en genres principaux :
 *
 *   - une étiquette qui se rattache à un genre de la liste est remplacée par
 *     ce genre (« Melodic Death Metal » → Métal) ;
 *   - une étiquette qui ne dit rien de la musique (« Music », « Various »,
 *     « Canadian ») est effacée : l'artiste repasse « sans genre » et la
 *     détection (scan-genres.php) pourra lui en trouver un vrai ;
 *   - les albums suivent leur artiste, puisque c'est sur eux que s'appuie le
 *     parcours par genre.
 *
 * Sans argument, le script ne fait que MONTRER ce qu'il changerait.
 *
 *   php scripts/reclassify-genres.php            # simulation
 *   php scripts/reclassify-genres.php --apply    # écrit en base
 */

require_once __DIR__ . '/../src/AppConfig.php';
require_once __DIR__ . '/../src/GenreTaxonomy.php';

$apply = in_array('--apply', array_slice($argv ?? [], 1), true);

$db = AppConfig::getDB();

echo $apply
    ? "Mode : écriture en base.\n\n"
    : "Mode : simulation (ajouter --apply pour écrire).\n\n";

// ── Ce que deviennent les étiquettes en place ────────────────────────────────
$values = $db->query("
    SELECT genre, SUM(artists) AS artists, SUM(albums) AS albums FROM (
        SELECT genre, COUNT(*) AS artists, 0 AS albums FROM artists
         WHERE genre IS NOT NULL AND genre != '' GROUP BY genre
        UNION ALL
        SELECT genre, 0, COUNT(*) FROM albums
         WHERE genre IS NOT NULL AND genre != '' GROUP BY genre
    ) t GROUP BY genre ORDER BY artists DESC, albums DESC
")->fetchAll(PDO::FETCH_ASSOC);

$plan    = [];  // étiquette => genre canonique ou null (à effacer)
$kept    = 0;
$mapped  = 0;
$cleared = 0;

foreach ($values as $row) {
    $raw    = $row['genre'];
    $target = GenreTaxonomy::classify($raw);
    $plan[$raw] = $target;

    if ($target === $raw)      { $kept++;    continue; }
    if ($target === null)      { $cleared++; }
    else                       { $mapped++; }

    printf(
        "  %-28s → %-30s (%d artiste·s, %d album·s)\n",
        mb_strimwidth($raw, 0, 28, '…'),
        $target ?? '(effacé)',
        (int)$row['artists'],
        (int)$row['albums']
    );
}

echo "\n";
printf(
    "%d étiquette·s : %d déjà dans la liste, %d ramenée·s à un genre, %d effacée·s.\n",
    count($plan), $kept, $mapped, $cleared
);

if (!$apply) {
    echo "\nRien n'a été écrit.\n";
    exit(0);
}

// ── Écriture ─────────────────────────────────────────────────────────────────
$updArtist = $db->prepare('UPDATE artists SET genre = ? WHERE genre = ?');
$updAlbum  = $db->prepare('UPDATE albums  SET genre = ? WHERE genre = ?');

$db->beginTransaction();
try {
    foreach ($plan as $raw => $target) {
        if ($target === $raw) continue;
        $updArtist->execute([$target, $raw]);
        $updAlbum->execute([$target, $raw]);
    }

    // Le parcours par genre lit albums.genre : un album sans genre hérite de
    // celui de son artiste, sinon il disparaîtrait de la vue « Genres ».
    $filled = $db->exec("
        UPDATE albums al
          JOIN artists a ON al.artist_id = a.id
           SET al.genre = a.genre
         WHERE (al.genre IS NULL OR al.genre = '')
           AND a.genre IS NOT NULL AND a.genre != ''
    ");

    // La table `genres` sert de référence à l'éditeur de tags : on la remet
    // sur la liste, sans sous-genres.
    $db->exec('DELETE FROM genres');
    $insert = $db->prepare('INSERT INTO genres (name, parent_id) VALUES (?, NULL)');
    foreach (GenreTaxonomy::ALL as $genre) {
        $insert->execute([$genre]);
    }

    $db->commit();
} catch (Throwable $e) {
    $db->rollBack();
    echo "ERREUR : {$e->getMessage()}\n";
    exit(1);
}

printf("Albums alignés sur leur artiste : %d.\n", $filled);
printf("Table `genres` remise sur les %d genres de la liste.\n", count(GenreTaxonomy::ALL));

$left = $db->query("
    SELECT COUNT(*) FROM artists WHERE genre IS NULL OR genre = ''
")->fetchColumn();
printf("Artistes sans genre à détecter : %d (php scripts/scan-genres.php).\n", $left);
