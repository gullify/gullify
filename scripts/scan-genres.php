<?php
/**
 * Genre Scanner
 *
 * Priority chain per artist:
 *   1. ID3 tags from sample files (majority vote) — preserves manual tags
 *   2. MusicBrainz API (community-voted tags, industry standard, free/no key)
 *
 * Whatever the source, the answer always comes from the closed list of main
 * genres (src/GenreTaxonomy.php): tags that map to nothing ("Music", "seen
 * live", "Noquarterpunk") are dropped rather than written to the library, so
 * an artist stays untagged until something real turns up.
 *
 * Usage:
 *   php scan-genres.php [username] [--force] [--dry-run] [--limit=N]
 *
 *   --force     overwrite genres that are already set (default: skip tagged artists)
 *   --dry-run   show what would be written, touch nothing
 *   --limit=N   stop after N artists processed (handy with --dry-run)
 */

error_reporting(E_ALL);
ini_set('display_errors', 1);
ini_set('memory_limit', '1024M');
ini_set('max_execution_time', 7200);

require_once __DIR__ . '/../src/AppConfig.php';
$dataPath    = AppConfig::getDataPath();
$lockFile    = $dataPath . '/cache/music-genre-scan.lock';
$progressFile = $dataPath . '/cache/genre-scan-progress.json';

// ── Args ──────────────────────────────────────────────────────────────────────
$targetUser   = null;
$force        = false;
$dryRun       = false;
$limit        = 0;    // 0 = tous
$targetArtist = null; // --artist-id=N : ne traite qu'un artiste (post-DL)
foreach (array_slice($argv ?? [], 1) as $arg) {
    if ($arg === '--force') $force = true;
    elseif ($arg === '--dry-run') $dryRun = true;
    elseif (str_starts_with($arg, '--limit=')) {
        $limit = max(0, (int)substr($arg, strlen('--limit=')));
    }
    elseif (str_starts_with($arg, '--artist-id=')) {
        $targetArtist = (int)substr($arg, strlen('--artist-id='));
        $force = true; // un artiste fraîchement téléchargé : on (re)tague
    }
    elseif ($arg !== '--all') $targetUser = $arg;
}

// ── Lock ──────────────────────────────────────────────────────────────────────
// Un essai à blanc n'écrit rien : ni verrou, ni fichier d'avancement — il ne
// doit pas passer pour un scan en cours dans l'app.
if (!$dryRun) {
    if (file_exists($lockFile)) {
        $lockAge = time() - filemtime($lockFile);
        if ($lockAge > 1800) {
            unlink($lockFile);
            echo "Stale lock removed.\n";
        } else {
            echo "Genre scan already in progress (lock age: {$lockAge}s).\n";
            exit(1);
        }
    }
    touch($lockFile);

    register_shutdown_function(function () {
        global $lockFile;
        if (file_exists($lockFile)) unlink($lockFile);
    });
}

function updateProgress(array $data): void {
    global $progressFile, $dryRun;
    if ($dryRun) return;
    $data['timestamp'] = time();
    file_put_contents($progressFile, json_encode($data));
}

require_once __DIR__ . '/../src/PathHelper.php';
require_once __DIR__ . '/../src/GenreTaxonomy.php';
require_once __DIR__ . '/../src/MusicBrainz.php';
require_once AppConfig::getVendorPath() . '/getid3/getid3.php';

// ── MusicBrainz ───────────────────────────────────────────────────────────
// La recherche d'artiste et ses étiquettes vivent dans src/MusicBrainz.php :
// le choix manuel du genre, dans l'app, interroge ainsi la même source que
// ce scan — ce qui range tout seul est ce qui est proposé quand on range à
// la main.

// ── Extract genre from ID3 tags for a list of files ───────────────────────────
/**
 * Read the genre tag of each file and let the taxonomy pick a winner. The
 * number of files carrying a tag is its vote count, so a lone oddball tag
 * loses to the genre written on the rest of the discography.
 */
function id3GenreFromFiles(array $filePaths, getID3 $getID3): ?string {
    $counts = [];
    foreach ($filePaths as $path) {
        if (!file_exists($path)) continue;
        try {
            $info = $getID3->analyze($path);
            getid3_lib::CopyTagsToComments($info);

            $raw = null;
            foreach (['comments.genre', 'tags.id3v2.genre', 'tags.id3v1.genre'] as $dotKey) {
                $val = array_reduce(
                    explode('.', $dotKey),
                    fn($carry, $k) => is_array($carry) ? ($carry[$k] ?? null) : null,
                    $info
                );
                if ($val) { $raw = is_array($val) ? $val[0] : $val; break; }
            }

            if ($raw) {
                $raw = trim((string)$raw);
                if ($raw !== '') $counts[$raw] = ($counts[$raw] ?? 0) + 1;
            }
        } catch (Throwable) {
            // Corrupted / unsupported file — skip
        }
    }
    if (empty($counts)) return null;

    $tags = [];
    foreach ($counts as $name => $count) {
        $tags[] = ['name' => (string)$name, 'count' => $count];
    }

    return GenreTaxonomy::pickFromTags($tags);
}

// ── Main ──────────────────────────────────────────────────────────────────────
try {
    $db       = AppConfig::getDB();
    $getID3   = new getID3();
    $basePath = rtrim(AppConfig::getMusicBasePath(), '/') . '/';

    echo "Taxonomy: " . count(GenreTaxonomy::ALL) . " main genres.\n";
    echo "Mode: " . ($force ? 'force (overwrite existing genres)' : 'skip already-tagged artists');
    if ($dryRun) echo " — dry run (nothing written)";
    if ($limit)  echo " — limited to {$limit} artists";
    echo "\n\n";

    // Artists to process
    if ($targetArtist) {
        $stmt = $db->prepare("SELECT id, name, user, genre FROM artists WHERE id = ?");
        $stmt->execute([$targetArtist]);
    } elseif ($targetUser) {
        $stmt = $db->prepare("SELECT id, name, user, genre FROM artists WHERE user = ?");
        $stmt->execute([$targetUser]);
    } else {
        $stmt = $db->query("SELECT id, name, user, genre FROM artists");
    }
    $artists      = $stmt->fetchAll(PDO::FETCH_ASSOC);
    $totalArtists = count($artists);

    echo "Found {$totalArtists} artists.\n\n";

    updateProgress([
        'status'         => 'scanning',
        'processed'      => 0,
        'total'          => $totalArtists,
        'percent'        => 0,
        'current_artist' => '',
    ]);

    $updatedCount = 0;
    $skippedCount = 0;  // déjà taggés, laissés tels quels
    $noGenreCount = 0;  // cherchés, rien de probant trouvé
    $mbCount      = 0;

    foreach ($artists as $index => $artist) {
        $artistId   = (int)$artist['id'];
        $artistName = $artist['name'];
        $hasGenre   = !empty($artist['genre']);

        updateProgress([
            'status'         => 'scanning',
            'processed'      => $index,
            'total'          => $totalArtists,
            'percent'        => $totalArtists > 0 ? round(($index / $totalArtists) * 100) : 0,
            'current_artist' => $artistName,
        ]);

        // Skip if already tagged and not forcing
        if ($hasGenre && !$force) {
            $skippedCount++;
            continue;
        }

        // ── Step 1: ID3 tags ─────────────────────────────────────────────────
        $stmtSongs = $db->prepare("
            SELECT s.file_path
            FROM   songs s
            JOIN   albums al ON s.album_id = al.id
            WHERE  al.artist_id = ?
            ORDER  BY RAND()
            LIMIT  20
        ");
        $stmtSongs->execute([$artistId]);
        $filePaths = array_map(
            fn($r) => $basePath . $r['file_path'],
            $stmtSongs->fetchAll(PDO::FETCH_ASSOC)
        );

        $genre = id3GenreFromFiles($filePaths, $getID3);
        $source = 'id3';

        // ── Step 2: MusicBrainz fallback ─────────────────────────────────────
        if (!$genre && function_exists('curl_init')) {
            $mbGenre = GenreTaxonomy::pickFromTags(MusicBrainz::tags($artistName));
            if ($mbGenre) {
                $genre  = $mbGenre;
                $source = 'musicbrainz';
                $mbCount++;
            }
        }

        if (!$genre) {
            $noGenreCount++;
            echo "  [{$index}/{$totalArtists}] {$artistName} → (no genre found)\n";
            if ($limit && ($updatedCount + $noGenreCount) >= $limit) {
                echo "\nLimit reached ({$limit}).\n";
                break;
            }
            continue;
        }

        // ── Persist ──────────────────────────────────────────────────────────
        if (!$dryRun) {
            $db->prepare("UPDATE artists SET genre = ? WHERE id = ?")->execute([$genre, $artistId]);
            $db->prepare("UPDATE albums SET genre = ? WHERE artist_id = ? AND (genre IS NULL OR genre = '')")
               ->execute([$genre, $artistId]);
        }

        $updatedCount++;
        echo "  [{$index}/{$totalArtists}] {$artistName} → {$genre} ({$source})\n";

        if ($limit && ($updatedCount + $noGenreCount) >= $limit) {
            echo "\nLimit reached ({$limit}).\n";
            break;
        }
    }

    updateProgress([
        'status'         => 'completed',
        'processed'      => $totalArtists,
        'total'          => $totalArtists,
        'percent'        => 100,
        'current_artist' => '',
        'updated'        => $updatedCount,
        'skipped'        => $skippedCount + $noGenreCount,
        'musicbrainz'    => $mbCount,
    ]);

    echo "\n✓ Genre scan complete!\n";
    echo "  Updated : {$updatedCount} artists\n";
    echo "  Via MusicBrainz : {$mbCount}\n";
    echo "  Already tagged : {$skippedCount} artists\n";
    echo "  No genre found : {$noGenreCount} artists\n";

} catch (Throwable $e) {
    updateProgress(['status' => 'error', 'error' => $e->getMessage()]);
    echo "ERROR: " . $e->getMessage() . "\n";
    exit(1);
}
