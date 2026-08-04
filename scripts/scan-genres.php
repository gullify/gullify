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
 * Strip the Lucene operators for the unquoted (loose) search. Left in place,
 * a name like "(50 First Dates) UB-40" is read as a grouping expression and
 * brings back an unrelated artist.
 */
function luceneStrip(string $s): string {
    $s = str_replace(
        ['+', '-', '&&', '||', '!', '(', ')', '{', '}', '[', ']', '^', '"', '~', '*', '?', ':', '\\', '/'],
        ' ',
        $s
    );
    return trim(preg_replace('/\s+/', ' ', $s));
}

/**
 * Guard against the loose search bringing back somebody else entirely: the
 * name found must look like the one asked for, or the match must be one
 * MusicBrainz itself is confident about. A missing genre beats a wrong one.
 */
function mbNameMatches(string $wanted, string $found, int $score): bool {
    $a = GenreTaxonomy::normalize($wanted);
    $b = GenreTaxonomy::normalize($found);
    if ($a === '' || $b === '') return false;
    if ($a === $b) return true;
    if (str_contains($a, $b) || str_contains($b, $a)) return true;

    return $score >= 90;
}

/**
 * Perform a single MusicBrainz curl GET and return decoded JSON array or null.
 * Enforces the 1 req/sec rate limit via the $lastCall static.
 *
 * Sur une longue série, MusicBrainz refuse ponctuellement une requête (503) même
 * en respectant la cadence : sans reprise, l'artiste repartait sans genre pour
 * une simple contrariété de passage. On repasse donc jusqu'à deux fois, en
 * laissant le serveur souffler.
 */
function mbGet(string $url, float &$lastCall): ?array {
    for ($attempt = 0; $attempt < 3; $attempt++) {
        $elapsed = microtime(true) - $lastCall;
        $wait    = 1.05 + ($attempt * 2.0);   // 1 s, puis 3 s, puis 5 s
        if ($elapsed < $wait) usleep((int)(($wait - $elapsed) * 1_000_000));
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

        if ($status === 200 && $body) return json_decode($body, true) ?: null;
        // 503 = cadence refusée, 0 = réseau : ça vaut la peine de réessayer.
        if ($status !== 503 && $status !== 0) return null;
    }

    return null;
}

/**
 * Look an artist up on MusicBrainz and return its MBID, or null.
 *
 * Tries the exact quoted search first, then an unquoted one for the names that
 * don't match character for character (punctuation, "UB-40" vs "UB40").
 */
function mbFindArtistId(string $name, float &$lastCall): ?string {
    $nameLower = strtolower(trim($name));

    foreach (['quoted', 'loose'] as $mode) {
        $term = $mode === 'quoted'
            ? '"' . luceneEscape($name) . '"'
            : luceneStrip($name);
        if (trim($term, '" ') === '') continue;

        $searchUrl = 'https://musicbrainz.org/ws/2/artist/?' . http_build_query([
            'query' => 'artist:' . $term,
            'fmt'   => 'json',
            'limit' => '5',
        ]);

        $data = mbGet($searchUrl, $lastCall);
        if (empty($data['artists'])) continue;

        // Prefer an exact name match; otherwise the first result that still
        // looks like the artist we asked for.
        $best = null;
        foreach ($data['artists'] as $a) {
            if (strtolower($a['name'] ?? '') === $nameLower) { $best = $a; break; }
        }
        if (!$best) {
            foreach ($data['artists'] as $a) {
                if (mbNameMatches($name, (string)($a['name'] ?? ''), (int)($a['score'] ?? 0))) {
                    $best = $a;
                    break;
                }
            }
        }

        if ($best && !empty($best['id'])) return (string)$best['id'];
    }

    return null;
}

/**
 * Query MusicBrainz for an artist's weighted tags (curated genres + user tags,
 * merged by name, best vote count kept).
 *
 * The taxonomy decides which of them wins — a single "top tag" is a poor
 * signal, since the most-voted tag is often not a genre at all ("seen live",
 * "canadian") or too broad ("folk") next to a far more telling one further
 * down the list ("néo-trad").
 *
 * Falls back to an unquoted loose search when the exact search finds nothing.
 * Rate-limited to 1 req/sec (MusicBrainz policy).
 *
 * @return array<array{name: string, count: int}>
 */
function musicbrainzTags(string $artistName): array {
    static $lastCall = 0.0;

    // ── Step 1: Search ────────────────────────────────────────────────────────
    // Beaucoup de noms traînent le titre du film ou de la compilation dont ils
    // viennent : « (50 First Dates) Bob Marley ». Tel quel, rien ne sort ; sans
    // le préfixe, l'artiste se trouve du premier coup.
    $mbid     = null;
    $stripped = trim(preg_replace('/^\s*\([^)]*\)\s*/', '', $artistName));
    foreach ([$artistName, $stripped] as $candidate) {
        if ($candidate === '' || ($candidate !== $artistName && $candidate === trim($artistName))) {
            continue;
        }
        $mbid = mbFindArtistId($candidate, $lastCall);
        if ($mbid) break;
    }

    if (!$mbid) return [];

    // ── Step 2: Fetch tags + curated genres ───────────────────────────────────
    $detail = mbGet(
        "https://musicbrainz.org/ws/2/artist/{$mbid}?inc=tags+genres&fmt=json",
        $lastCall
    );
    if (!$detail) return [];

    // Curated genres first: same names as the tags, but vetted. A name seen in
    // both keeps its best count.
    $merged = [];
    foreach ([$detail['genres'] ?? [], $detail['tags'] ?? []] as $list) {
        foreach ($list as $entry) {
            $name = trim($entry['name'] ?? '');
            if ($name === '') continue;
            $count = max(0, (int)($entry['count'] ?? 0));
            $key   = mb_strtolower($name, 'UTF-8');
            if (!isset($merged[$key]) || $count > $merged[$key]['count']) {
                $merged[$key] = ['name' => $name, 'count' => $count];
            }
        }
    }

    return array_values($merged);
}

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
            $mbGenre = GenreTaxonomy::pickFromTags(musicbrainzTags($artistName));
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
