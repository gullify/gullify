<?php
/**
 * Remplit songs.track_artist (interprète réel, tag ID3) pour les pistes des
 * albums « Various Artists », afin d'afficher « Artiste - Titre » sur les
 * compilations. N'ajoute PAS d'artistes dans la bibliothèque (colonne texte).
 *
 * Usage : php backfill-track-artists.php [user]   (tous les users si absent)
 */
require_once __DIR__ . '/../src/AppConfig.php';
require_once __DIR__ . '/../src/Storage/StorageFactory.php';

$onlyUser = $argv[1] ?? null;
$db = AppConfig::getDB();

// Colonne track_artist (idempotent).
$col = $db->query("SHOW COLUMNS FROM songs LIKE 'track_artist'")->fetch();
if (!$col) {
    $db->exec("ALTER TABLE songs ADD COLUMN track_artist VARCHAR(255) NULL");
    echo "Colonne track_artist ajoutée.\n";
}

$sql = "
    SELECT s.id, s.file_path, a.user
    FROM songs s
    JOIN albums al ON s.album_id = al.id
    JOIN artists a ON al.artist_id = a.id
    WHERE a.name = 'Various Artists'
      AND (s.track_artist IS NULL OR s.track_artist = '')
";
$params = [];
if ($onlyUser) { $sql .= " AND a.user = ?"; $params[] = $onlyUser; }
$stmt = $db->prepare($sql);
$stmt->execute($params);
$rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

$storages = [];
$fixed = 0;
foreach ($rows as $row) {
    $user = $row['user'];
    if (!isset($storages[$user])) {
        $storages[$user] = StorageFactory::forUser($user);
    }
    $abs = $storages[$user]->getPathBase() . '/' . ltrim($row['file_path'], '/');
    // ffprobe : lit le tag artist sans dépendance PHP lourde.
    $cmd = 'ffprobe -v quiet -show_entries format_tags=artist -of '
        . 'default=noprint_wrappers=1:nokey=1 ' . escapeshellarg($abs) . ' 2>/dev/null';
    $artist = trim((string)shell_exec($cmd));
    if ($artist !== '' && strcasecmp($artist, 'Various Artists') !== 0) {
        $db->prepare("UPDATE songs SET track_artist = ? WHERE id = ?")
           ->execute([mb_substr($artist, 0, 255), $row['id']]);
        $fixed++;
    }
}
echo "track_artist rempli pour $fixed / " . count($rows) . " pistes de compilations.\n";
