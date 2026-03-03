<?php
/**
 * One-time migration: populate songs.artist_id for existing compilation tracks.
 *
 * The incremental scanner skips unchanged files, so songs that were already
 * in the DB before songs.artist_id was added have artist_id = NULL.
 * This script reads TPE1 (track artist) from ID3 tags for every compilation
 * song that still has artist_id = NULL and fills in the correct value.
 *
 * Run from CLI:
 *   php fix-compilation-artists.php
 */

require_once __DIR__ . '/src/AppConfig.php';
require_once __DIR__ . '/src/Storage/StorageInterface.php';
require_once __DIR__ . '/src/Storage/LocalStorage.php';
require_once __DIR__ . '/src/Storage/SFTPStorage.php';
require_once __DIR__ . '/src/Storage/StorageFactory.php';

$getID3Path = AppConfig::getVendorPath() . '/getid3/getid3.php';
if (!file_exists($getID3Path)) {
    echo "ERROR: getID3 not found at $getID3Path\n";
    exit(1);
}
require_once $getID3Path;

$db = AppConfig::getDB();
$getID3 = new getID3;

// Ensure the column exists
$stmt = $db->prepare("SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = ? AND TABLE_NAME = 'songs' AND COLUMN_NAME = 'artist_id'");
$stmt->execute([AppConfig::get('mysql.database')]);
if (!$stmt->fetchColumn()) {
    echo "Adding songs.artist_id column...\n";
    $db->exec("ALTER TABLE songs ADD COLUMN artist_id INT NULL");
}

// Fetch all compilation songs with no track artist
$songs = $db->query("
    SELECT s.id, s.file_path, s.album_id,
           ar.user
    FROM songs s
    JOIN albums al ON s.album_id = al.id
    JOIN artists ar ON al.artist_id = ar.id
    WHERE al.is_compilation = 1
      AND s.artist_id IS NULL
")->fetchAll(PDO::FETCH_ASSOC);

$total = count($songs);
echo "Found $total compilation tracks with no track artist.\n";
if ($total === 0) {
    echo "Nothing to do.\n";
    exit(0);
}

// Cache storage per user, artist IDs per (user, name)
$storageCache = [];
$artistIdCache = [];  // [user][name] => id

function getOrCreateArtist(PDO $db, string $name, string $user, array &$cache): int {
    if (isset($cache[$user][$name])) return $cache[$user][$name];

    $stmt = $db->prepare("SELECT id FROM artists WHERE user = ? AND name = ?");
    $stmt->execute([$user, $name]);
    $id = $stmt->fetchColumn();

    if (!$id) {
        $db->prepare("INSERT INTO artists (name, user) VALUES (?, ?)")->execute([$name, $user]);
        $id = (int)$db->lastInsertId();
        echo "  Created artist: $name (id=$id)\n";
    }

    $cache[$user][$name] = (int)$id;
    return (int)$id;
}

$updated  = 0;
$skipped  = 0;
$errors   = 0;

foreach ($songs as $i => $song) {
    $user = $song['user'];

    // Get (or init) storage for this user
    if (!isset($storageCache[$user])) {
        try {
            $storageCache[$user] = StorageFactory::forUser($user);
        } catch (Exception $e) {
            echo "  SKIP user=$user: " . $e->getMessage() . "\n";
            $storageCache[$user] = null;
        }
    }
    $storage = $storageCache[$user];
    if ($storage === null) { $skipped++; continue; }

    // Skip SFTP users — downloading every file just for tags is too expensive
    if ($storage->getType() === 'sftp') { $skipped++; continue; }

    $absPath = $storage->getPathBase() . '/' . ltrim($song['file_path'], '/');

    if (!file_exists($absPath)) {
        echo "  MISSING: {$song['file_path']}\n";
        $errors++;
        continue;
    }

    // Read ID3
    try {
        $info = $getID3->analyze($absPath);
        getid3_lib::CopyTagsToComments($info);
    } catch (Exception $e) {
        $errors++;
        continue;
    }

    $trackArtist = trim($info['comments']['artist'][0] ?? '');

    if ($trackArtist === '') {
        // Fallback: try to derive from path  Artist/Album/Song.ext
        $parts = explode('/', ltrim($song['file_path'], '/'));
        $count = count($parts);
        if ($count >= 3) {
            $trackArtist = $parts[$count - 3]; // Artist segment
        }
    }

    if ($trackArtist === '') {
        $skipped++;
        continue;
    }

    // Find/create artist and update song
    $artistId = getOrCreateArtist($db, $trackArtist, $user, $artistIdCache);
    $db->prepare("UPDATE songs SET artist_id = ? WHERE id = ?")->execute([$artistId, $song['id']]);
    $updated++;

    if (($i + 1) % 50 === 0 || ($i + 1) === $total) {
        echo "  Progress: " . ($i + 1) . "/$total — updated=$updated skipped=$skipped errors=$errors\n";
    }
}

echo "\nDone. Updated=$updated, Skipped=$skipped, Errors=$errors\n";
