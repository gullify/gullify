<?php
/**
 * Genre Scanner — les genres (jusqu'à trois) et l'origine de chaque artiste.
 *
 * Par artiste :
 *   1. Last.fm (clé LASTFM_API_KEY), puis les tags ID3 de ses fichiers (vote à
 *      la majorité), puis MusicBrainz, Deezer et Apple Music — chacun consulté
 *      seulement tant que rien n'est sorti (src/GenreLookup.php) ;
 *   2. l'origine (Québec, France…) : étiquettes Last.fm, ou région MusicBrainz.
 *
 * Quelle que soit la source, les genres sortent de la liste fermée
 * (src/GenreTaxonomy.php) et les origines de la leur (src/Origine.php).
 *
 * Un scan ordinaire traite les artistes sans genre ET ceux que l'analyse
 * Last.fm n'a pas encore vus (`genres_analyse`) : ceux-là gardent leur genre
 * principal, et gagnent leurs genres secondaires et leur origine. --force
 * refait tout, genre principal compris. Ce qui a été choisi à la main dans
 * l'app (`genres_manuel`, `origine_manuelle`) n'est JAMAIS touché.
 *
 * Usage:
 *   php scan-genres.php [username] [--force] [--dry-run] [--limit=N]
 *
 *   --force     recompute every artist (manual choices excepted)
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
require_once __DIR__ . '/../src/GenreLookup.php';
require_once __DIR__ . '/../src/ArtisteGenres.php';
require_once AppConfig::getVendorPath() . '/getid3/getid3.php';

// ── Les catalogues ────────────────────────────────────────────────────────
// La consultation de MusicBrainz, Deezer et Apple Music vit dans
// src/GenreLookup.php : le choix manuel du genre, dans l'app, interroge ainsi
// les mêmes sources que ce scan — ce qui range tout seul est ce qui est
// proposé quand on range à la main.

// ── Extract genre from ID3 tags for a list of files ───────────────────────────
/**
 * Read the genre tag of each file and let the taxonomy pick a winner. The
 * number of files carrying a tag is its vote count, so a lone oddball tag
 * loses to the genre written on the rest of the discography.
 */
function id3GenresFromFiles(array $filePaths, getID3 $getID3): array {
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
    if (empty($counts)) return [];

    $tags = [];
    foreach ($counts as $name => $count) {
        $tags[] = ['name' => (string)$name, 'count' => $count];
    }

    return GenreTaxonomy::pickManyFromTags($tags, GenreLookup::MAX_GENRES);
}

// ── Main ──────────────────────────────────────────────────────────────────────
try {
    $db       = AppConfig::getDB();
    ArtisteGenres::assurerTable($db);
    $getID3   = new getID3();
    $basePath = rtrim(AppConfig::getMusicBasePath(), '/') . '/';
    $lastfm   = trim((string)AppConfig::get('lastfm.api_key')) !== '';

    echo "Taxonomy: " . count(GenreTaxonomy::ALL) . " main genres, " . count(Origine::ALL) . " origins.\n";
    echo "Last.fm: " . ($lastfm ? 'yes' : 'no key (MusicBrainz, Deezer, Apple Music only)') . "\n";
    echo "Mode: " . ($force ? 'force (recompute, manual choices kept)' : 'new and not-yet-analysed artists');
    if ($dryRun) echo " — dry run (nothing written)";
    if ($limit)  echo " — limited to {$limit} artists";
    echo "\n\n";

    $cols = "id, name, user, genre, origine, genres_manuel, origine_manuelle, genres_analyse";
    if ($targetArtist) {
        $stmt = $db->prepare("SELECT $cols FROM artists WHERE id = ?");
        $stmt->execute([$targetArtist]);
    } elseif ($targetUser) {
        $stmt = $db->prepare("SELECT $cols FROM artists WHERE user = ?");
        $stmt->execute([$targetUser]);
    } else {
        $stmt = $db->query("SELECT $cols FROM artists");
    }
    $artists      = $stmt->fetchAll(PDO::FETCH_ASSOC);
    $totalArtists = count($artists);
    $existants    = ArtisteGenres::lire($db, array_column($artists, 'id'));

    echo "Found {$totalArtists} artists.\n\n";

    updateProgress([
        'status'         => 'scanning',
        'processed'      => 0,
        'total'          => $totalArtists,
        'percent'        => 0,
        'current_artist' => '',
    ]);

    $updatedCount = 0;
    $skippedCount = 0;  // rien à faire (déjà analysés, ou choisis à la main)
    $noGenreCount = 0;  // cherchés, rien de probant trouvé
    $onlineCount  = 0;  // trouvés par les catalogues en ligne
    $origineCount = 0;  // origine trouvée
    $traites      = 0;

    foreach ($artists as $index => $artist) {
        $artistId    = (int)$artist['id'];
        $artistName  = $artist['name'];
        $hasGenre    = !empty($artist['genre']);
        $genresMain  = (bool)$artist['genres_manuel'];
        $origineMain = (bool)$artist['origine_manuelle'];
        $analyse     = !empty($artist['genres_analyse']);

        updateProgress([
            'status'         => 'scanning',
            'processed'      => $index,
            'total'          => $totalArtists,
            'percent'        => $totalArtists > 0 ? round(($index / $totalArtists) * 100) : 0,
            'current_artist' => $artistName,
        ]);

        // Ce qu'il y a à chercher pour cet artiste.
        $chercherGenres  = !$genresMain && ($force || !$hasGenre || !$analyse);
        $chercherOrigine = !$origineMain && ($force || (empty($artist['origine']) && !$analyse));
        if (!$chercherGenres && !$chercherOrigine) {
            $skippedCount++;
            continue;
        }
        $traites++;

        // ── Les catalogues en ligne (Last.fm d'abord) ────────────────────────
        // Un scan de fond peut insister (3 essais) : personne n'attend devant
        // son téléphone.
        $found = function_exists('curl_init')
            ? GenreLookup::suggest($artistName, 10, 3, $chercherOrigine)
            : ['genres' => [], 'source' => null, 'origine' => null, 'origine_source' => null];

        $genres = [];
        $source = null;
        if ($chercherGenres) {
            // Last.fm a le premier mot ; puis les tags des fichiers ; puis les
            // autres catalogues (déjà interrogés par suggest, à défaut).
            if ($found['genres'] && $found['source'] === 'lastfm') {
                [$genres, $source] = [$found['genres'], 'lastfm'];
            } else {
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
                $genres = id3GenresFromFiles($filePaths, $getID3);
                $source = 'id3';
                if (!$genres && $found['genres']) {
                    [$genres, $source] = [$found['genres'], $found['source']];
                }
            }

            // Sans --force, un artiste déjà rangé garde son genre principal :
            // l'analyse lui ajoute ce qui lui manque, elle ne le déménage pas.
            if ($hasGenre && !$force) {
                // Ce qui traîne d'un vieux tag est remis d'aplomb au passage :
                // « Music » ou « Other » s'en vont, « Indie » devient
                // « Alternatif / Indie ». Un nom que la liste ne connaît pas du
                // tout (un genre saisi à la main) reste tel quel.
                $deja = [];
                foreach ($existants[$artistId]['genres'] ?? [$artist['genre']] as $g) {
                    if (GenreTaxonomy::isCanonical($g)) $deja[] = $g;
                    elseif (!GenreTaxonomy::isNoise($g)) $deja[] = GenreTaxonomy::classify($g) ?? $g;
                }
                $genres = ArtisteGenres::nettoyer(array_merge($deja, $genres), GenreLookup::MAX_GENRES);
            }
        }

        $origine = $chercherOrigine ? $found['origine'] : null;
        if ($origine !== null) $origineCount++;
        if ($genres && $source !== 'id3' && $source !== null) $onlineCount++;

        $avant = $existants[$artistId]['genres'] ?? [];
        $ligne = "  [{$index}/{$totalArtists}] {$artistName} → "
            . ($genres ? implode(', ', $genres) . " ({$source})" : ($chercherGenres ? '(no genre found)' : '(genres kept)'))
            . ($origine !== null ? " · {$origine} ({$found['origine_source']})" : '');
        echo $ligne . "\n";

        if ($chercherGenres && !$genres) $noGenreCount++;
        elseif ($genres && $genres !== $avant) $updatedCount++;

        // ── Persist ──────────────────────────────────────────────────────────
        if (!$dryRun) {
            if ($genres) ArtisteGenres::poser($db, $artistId, $genres, false);
            if ($origine !== null) {
                $db->prepare('UPDATE artists SET origine = ? WHERE id = ? AND origine_manuelle = 0')
                   ->execute([$origine, $artistId]);
            }
            $db->prepare('UPDATE artists SET genres_analyse = NOW() WHERE id = ?')->execute([$artistId]);
        }

        if ($limit && $traites >= $limit) {
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
        'musicbrainz'    => $onlineCount,
        'origines'       => $origineCount,
    ]);

    echo "\n✓ Genre scan complete!\n";
    echo "  Updated : {$updatedCount} artists\n";
    echo "  Via les catalogues en ligne : {$onlineCount}\n";
    echo "  Origine trouvée : {$origineCount}\n";
    echo "  Nothing to do : {$skippedCount} artists\n";
    echo "  No genre found : {$noGenreCount} artists\n";

} catch (Throwable $e) {
    updateProgress(['status' => 'error', 'error' => $e->getMessage()]);
    echo "ERROR: " . $e->getMessage() . "\n";
    exit(1);
}
