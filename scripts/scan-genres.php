<?php
/**
 * Genre Scanner
 *
 * Priority chain per artist:
 *   1. ID3 tags from sample files (majority vote) — preserves manual tags
 *   2. MusicBrainz API (community-voted tags, industry standard, free/no key)
 *
 * Usage:
 *   php scan-genres.php [username] [--force]
 *
 *   --force   overwrite genres that are already set (default: skip tagged artists)
 */

error_reporting(E_ALL);
ini_set('display_errors', 1);
ini_set('memory_limit', '1024M');
ini_set('max_execution_time', 7200);

require_once __DIR__ . '/../src/AppConfig.php';
$dataPath    = AppConfig::getDataPath();
$lockFile    = $dataPath . '/cache/music-genre-scan.lock';
$progressFile = $dataPath . '/cache/genre-scan-progress.json';

// ── Lock ──────────────────────────────────────────────────────────────────────
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

function updateProgress(array $data): void {
    global $progressFile;
    $data['timestamp'] = time();
    file_put_contents($progressFile, json_encode($data));
}

register_shutdown_function(function () {
    global $lockFile;
    if (file_exists($lockFile)) unlink($lockFile);
});

// ── Args ──────────────────────────────────────────────────────────────────────
$targetUser = null;
$force      = false;
foreach (array_slice($argv ?? [], 1) as $arg) {
    if ($arg === '--force') $force = true;
    elseif ($arg !== '--all') $targetUser = $arg;
}

require_once __DIR__ . '/../src/PathHelper.php';
require_once AppConfig::getVendorPath() . '/getid3/getid3.php';

// ── MusicBrainz helper ────────────────────────────────────────────────────────
/**
 * Escape a string for use inside a Lucene quoted phrase.
 * Backslash-escapes the characters that are special inside quotes: \ and "
 */
function luceneEscape(string $s): string {
    return str_replace(['\\', '"'], ['\\\\', '\\"'], $s);
}

/**
 * Perform a single MusicBrainz curl GET and return decoded JSON array or null.
 * Enforces the 1 req/sec rate limit via the $lastCall static.
 */
function mbGet(string $url, float &$lastCall): ?array {
    $elapsed = microtime(true) - $lastCall;
    if ($elapsed < 1.05) usleep((int)((1.05 - $elapsed) * 1_000_000));
    $lastCall = microtime(true);

    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 10,
        CURLOPT_USERAGENT      => 'Gullify/1.0 (self-hosted; https://github.com/gullify)',
        CURLOPT_HTTPHEADER     => ['Accept: application/json'],
        CURLOPT_FOLLOWLOCATION => true,
    ]);
    $body   = curl_exec($ch);
    $status = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($status !== 200 || !$body) return null;
    return json_decode($body, true) ?: null;
}

/**
 * Query MusicBrainz for an artist's top genre.
 * Uses curated genres first, then user-voted tags.
 * Falls back to an unquoted loose search when the exact search finds nothing.
 * Rate-limited to 1 req/sec (MusicBrainz policy).
 */
function musicbrainzGenre(string $artistName): ?string {
    static $lastCall = 0.0;

    $nameLower = strtolower(trim($artistName));

    // ── Step 1: Search (exact quoted, then loose) ─────────────────────────────
    $mbid = null;
    foreach (['quoted', 'loose'] as $mode) {
        $q = $mode === 'quoted'
            ? 'artist:"' . luceneEscape($artistName) . '"'
            : 'artist:' . luceneEscape($artistName);

        $searchUrl = 'https://musicbrainz.org/ws/2/artist/?' . http_build_query([
            'query' => $q,
            'fmt'   => 'json',
            'limit' => '5',
        ]);

        $data = mbGet($searchUrl, $lastCall);
        if (empty($data['artists'])) continue;

        // Prefer exact name match; fall back to first result
        $best = null;
        foreach ($data['artists'] as $a) {
            if (strtolower($a['name'] ?? '') === $nameLower) {
                $best = $a;
                break;
            }
        }
        if (!$best) $best = $data['artists'][0];

        $mbid = $best['id'] ?? null;
        if ($mbid) break;
    }

    if (!$mbid) return null;

    // ── Step 2: Fetch tags + curated genres ───────────────────────────────────
    $detail = mbGet(
        "https://musicbrainz.org/ws/2/artist/{$mbid}?inc=tags+genres&fmt=json",
        $lastCall
    );
    if (!$detail) return null;

    // Curated genres (higher quality, lower vote threshold)
    $genres = $detail['genres'] ?? [];
    if (!empty($genres)) {
        usort($genres, fn($a, $b) => ($b['count'] ?? 0) - ($a['count'] ?? 0));
        foreach ($genres as $g) {
            $name = trim($g['name'] ?? '');
            if ($name) return ucwords($name);
        }
    }

    // User-voted tags (broader but noisier — require ≥1 net vote)
    $tags = $detail['tags'] ?? [];
    usort($tags, fn($a, $b) => ($b['count'] ?? 0) - ($a['count'] ?? 0));
    foreach ($tags as $tag) {
        $name = trim($tag['name'] ?? '');
        if ($name && ($tag['count'] ?? 0) >= 1) {
            return ucwords($name);
        }
    }

    return null;
}

// ── Genre taxonomy ────────────────────────────────────────────────────────────
/**
 * Build a map: lowercase sub/parent genre → canonical parent genre name
 */
function buildGenreMap(PDO $db): array {
    $parents  = [];
    $map      = [];
    $stmt     = $db->query("SELECT id, name, parent_id FROM genres ORDER BY parent_id ASC");
    $rows     = $stmt->fetchAll(PDO::FETCH_ASSOC);
    foreach ($rows as $r) {
        if ($r['parent_id'] === null) {
            $parents[$r['id']] = $r['name'];
            $map[strtolower($r['name'])] = $r['name'];
        }
    }
    foreach ($rows as $r) {
        if ($r['parent_id'] !== null && isset($parents[$r['parent_id']])) {
            $map[strtolower($r['name'])] = $parents[$r['parent_id']];
        }
    }
    return $map;
}

/**
 * Map a raw genre string to the closest canonical genre, or return it title-cased.
 */
function canonicalizeGenre(string $genre, array $genreMap): string {
    // Strip ID3v1 numeric codes like "(13)" or "(13)Alternative"
    $genre = trim(preg_replace('/^\(\d+\)/', '', $genre));
    if ($genre === '') return '';

    $lower = strtolower($genre);

    // Exact match
    if (isset($genreMap[$lower])) return $genreMap[$lower];

    // Partial match (e.g. "Alternative Rock" → "Rock")
    foreach ($genreMap as $key => $parent) {
        if (str_contains($lower, $key) || str_contains($key, $lower)) {
            return $parent;
        }
    }

    return ucwords(strtolower($genre));
}

// ── Extract genre from ID3 tags for a list of files ───────────────────────────
function id3GenreFromFiles(array $filePaths, getID3 $getID3, array $genreMap): ?string {
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
                $canonical = canonicalizeGenre($raw, $genreMap);
                if ($canonical !== '') {
                    $counts[$canonical] = ($counts[$canonical] ?? 0) + 1;
                }
            }
        } catch (Throwable) {
            // Corrupted / unsupported file — skip
        }
    }
    if (empty($counts)) return null;
    arsort($counts);
    return array_key_first($counts);
}

// ── Main ──────────────────────────────────────────────────────────────────────
try {
    $db       = AppConfig::getDB();
    $getID3   = new getID3();
    $basePath = rtrim(AppConfig::getMusicBasePath(), '/') . '/';
    $genreMap = buildGenreMap($db);

    echo "Loaded " . count($genreMap) . " genre mappings.\n";
    echo "Mode: " . ($force ? 'force (overwrite existing genres)' : 'skip already-tagged artists') . "\n\n";

    // Artists to process
    if ($targetUser) {
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
    $skippedCount = 0;
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

        $genre = id3GenreFromFiles($filePaths, $getID3, $genreMap);
        $source = 'id3';

        // ── Step 2: MusicBrainz fallback ─────────────────────────────────────
        if (!$genre && function_exists('curl_init')) {
            $mbGenre = musicbrainzGenre($artistName);
            if ($mbGenre) {
                $genre  = canonicalizeGenre($mbGenre, $genreMap);
                $source = 'musicbrainz';
                $mbCount++;
            }
        }

        if (!$genre) {
            $skippedCount++;
            echo "  [{$index}/{$totalArtists}] {$artistName} → (no genre found)\n";
            continue;
        }

        // ── Persist ──────────────────────────────────────────────────────────
        $db->prepare("UPDATE artists SET genre = ? WHERE id = ?")->execute([$genre, $artistId]);
        $db->prepare("UPDATE albums SET genre = ? WHERE artist_id = ? AND (genre IS NULL OR genre = '')")
           ->execute([$genre, $artistId]);

        $updatedCount++;
        echo "  [{$index}/{$totalArtists}] {$artistName} → {$genre} ({$source})\n";
    }

    updateProgress([
        'status'         => 'completed',
        'processed'      => $totalArtists,
        'total'          => $totalArtists,
        'percent'        => 100,
        'current_artist' => '',
        'updated'        => $updatedCount,
        'skipped'        => $skippedCount,
        'musicbrainz'    => $mbCount,
    ]);

    echo "\n✓ Genre scan complete!\n";
    echo "  Updated : {$updatedCount} artists\n";
    echo "  Via MusicBrainz : {$mbCount}\n";
    echo "  Skipped : {$skippedCount} artists\n";

} catch (Throwable $e) {
    updateProgress(['status' => 'error', 'error' => $e->getMessage()]);
    echo "ERROR: " . $e->getMessage() . "\n";
    exit(1);
}
