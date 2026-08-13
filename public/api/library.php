<?php
/**
 * Gullify - Library API
 * Migrated from get_library_mysql.php
 */

// Enable error reporting for debugging
error_reporting(E_ALL);
ini_set('display_errors', 0);

// Increase memory limit for large music libraries
ini_set('memory_limit', '1024M');

// Ensure we're outputting JSON
header('Content-Type: application/json');

require_once __DIR__ . '/../../src/AppConfig.php';
require_once __DIR__ . '/../../src/Database.php';
require_once __DIR__ . '/../../src/GameSource.php';
require_once __DIR__ . '/../../src/GenreTaxonomy.php';
require_once __DIR__ . '/../../src/PathHelper.php';
require_once __DIR__ . '/../../src/TrackArtist.php';
require_once __DIR__ . '/../../src/TransitionAnalysis.php';

/**
 * Build an artworkUrl for an album that busts the browser cache when the
 * file changes, by appending the filemtime of the cached JPEG as ?v=.
 */
function albumArtworkUrl(int $albumId): string {
    static $artworkCache = null;
    if ($artworkCache === null) {
        $artworkCache = AppConfig::getDataPath() . '/cache/artwork';
    }
    $file = $artworkCache . '/album_' . $albumId . '.jpg';
    $v = @filemtime($file) ?: 0;
    return 'serve_image.php?album_id=' . $albumId . ($v ? '&v=' . $v : '');
}

/**
 * L'artiste, à condition qu'il appartienne bien à cet utilisateur — sinon
 * null, et l'appelant répond « Artist not found or access denied ».
 *
 * @return array{id: int, name: string}|null
 */
function artistOfUser(PDO $conn, int $artistId, string $user): ?array {
    if (!$artistId) return null;
    $stmt = $conn->prepare('SELECT id, name FROM artists WHERE id = ? AND user = ?');
    $stmt->execute([$artistId, $user]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    return $row ?: null;
}

/**
 * Ce que rend un changement de photo d'artiste : l'adresse de l'image, avec la
 * date du fichier en `v=` pour que le cache du client ne serve pas l'ancienne.
 */
function artistImagePayload(int $artistId): array {
    clearstatcache();
    $v = @filemtime(ArtistImage::cacheFile($artistId)) ?: 0;
    return [
        'artist_id' => $artistId,
        'imageUrl'  => 'serve_image.php?artist_id=' . $artistId . ($v ? '&v=' . $v : ''),
        'version'   => $v,
    ];
}

/**
 * La table des genres ajoutés à la main. La liste principale
 * (GenreTaxonomy::ALL) est fermée et la même pour tout le monde ; ce qu'on y
 * ajoute appartient à l'utilisateur, comme le reste de son rangement.
 */
function customGenresTable(PDO $conn): void {
    static $ready = false;
    if ($ready) return;
    $ready = true;
    $conn->exec("
        CREATE TABLE IF NOT EXISTS custom_genres (
            id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            user VARCHAR(50) NOT NULL,
            name VARCHAR(100) NOT NULL,
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY uniq_custom_genre (user, name)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ");
}

/**
 * Les genres qu'un utilisateur a ajoutés lui-même, par ordre alphabétique.
 * Ceux qui ne se distinguent de la liste principale que par la casse ou les
 * accents sont écartés : le choix du genre ne doit jamais proposer deux fois
 * le même.
 *
 * @return string[]
 */
function customGenres(PDO $conn, string $user): array {
    customGenresTable($conn);
    $stmt = $conn->prepare(
        'SELECT name FROM custom_genres WHERE user = ? ORDER BY name ASC'
    );
    $stmt->execute([$user]);

    $seen = [];
    foreach (GenreTaxonomy::ALL as $g) {
        $seen[GenreTaxonomy::normalize($g)] = true;
    }

    $custom = [];
    foreach ($stmt->fetchAll(PDO::FETCH_COLUMN) as $name) {
        $n = GenreTaxonomy::normalize((string)$name);
        if ($n === '' || isset($seen[$n])) continue;
        $seen[$n] = true;
        $custom[] = (string)$name;
    }

    return $custom;
}

try {
    // Get parameters
    $user = $_GET['user'] ?? $_POST['user'] ?? '';
    $action = isset($_GET['action']) ? $_GET['action'] : 'library';

    // Basic response structure
    $response = [
        'error' => false,
        'message' => '',
        'data' => null
    ];

    $db = new Database();
    $conn = $db->getConnection();

    // Ensure is_compilation column exists (added in compilation feature)
    try {
        $conn->exec("ALTER TABLE albums ADD COLUMN is_compilation TINYINT(1) NOT NULL DEFAULT 0");
    } catch (PDOException $e) {
        // Column already exists — ignore
    }

    if ($action === 'library') {
        // Pagination parameters
        $limit = isset($_GET['limit']) ? intval($_GET['limit']) : 30;
        $offset = isset($_GET['offset']) ? intval($_GET['offset']) : 0;
        $limit = max(1, min(9999, $limit));

        // Get artists with album and song counts (avoid loading blob data)
        $stmt = $conn->prepare('
            SELECT
                id,
                name,
                (image IS NOT NULL AND image != "") as has_image,
                album_count,
                song_count
            FROM artists
            WHERE user = ?
            ORDER BY name ASC
            LIMIT ? OFFSET ?
        ');
        $stmt->execute([$user, $limit, $offset]);

        $artists = [];
        while ($row = $stmt->fetch()) {
            $hasImage = (bool)$row['has_image'];
            $artists[] = [
                'id' => $row['id'],
                'name' => $row['name'],
                'imageUrl' => $hasImage ? 'serve_image.php?artist_id=' . $row['id'] : null,
                'hasImage' => $hasImage,
                'albumCount' => (int)$row['album_count'],
                'songCount' => (int)$row['song_count']
            ];
        }

        // Get total counts directly
        $stmt = $conn->prepare('SELECT COUNT(*) as cnt FROM artists WHERE user = ?');
        $stmt->execute([$user]);
        $totalArtists = (int)$stmt->fetchColumn();

        $stmt = $conn->prepare('SELECT COUNT(*) as cnt FROM songs s JOIN albums al ON s.album_id = al.id JOIN artists a ON al.artist_id = a.id WHERE a.user = ?');
        $stmt->execute([$user]);
        $totalSongs = (int)$stmt->fetchColumn();

        $response['data'] = [
            'artists' => $artists,
            'total' => $totalArtists,
            'totalArtists' => $totalArtists,
            'totalSongs' => $totalSongs,
            'limit' => $limit,
            'offset' => $offset,
            'has_more' => ($offset + $limit) < $totalArtists
        ];

    } elseif ($action === 'artist' || $action === 'artist_albums') {
        $artistId = isset($_GET['id']) ? intval($_GET['id']) : (isset($_GET['artist_id']) ? intval($_GET['artist_id']) : 0);

        // Get artist info
        $stmt = $conn->prepare('SELECT * FROM artists WHERE id = ?');
        $stmt->execute([$artistId]);
        $artist = $stmt->fetch();

        // Get albums
        $stmt = $conn->prepare('
            SELECT
                al.*,
                COUNT(s.id) as song_count,
                SUM(s.duration) as total_duration
            FROM albums al
            LEFT JOIN songs s ON al.id = s.album_id
            WHERE al.artist_id = ?
            GROUP BY al.id
            ORDER BY al.year IS NULL, al.year DESC, al.name ASC
        ');
        $stmt->execute([$artistId]);

        $albums = [];
        $totalSongs = 0;
        $pathHelper = new PathHelper();
        $musicPath = $pathHelper->getUserPath($user);

        while ($row = $stmt->fetch()) {
            $songCount = (int)$row['song_count'];
            $totalSongs += $songCount;

            $albums[] = [
                'id' => $row['id'],
                'name' => $row['name'],
                'artistId' => $row['artist_id'],
                'year' => $row['year'],
                'artworkUrl' => albumArtworkUrl((int)$row['id']),
                'songCount' => $songCount,
                'totalDuration' => (int)$row['total_duration']
            ];
        }

        // Top 5 tracks for the artist (by play count, falls back to first 5)
        $topStmt = $conn->prepare('
            SELECT s.id, s.title, s.duration, s.file_path, s.album_id,
                   al.name AS album_name, al.year,
                   ' . TRACK_ARTIST_NAME . ' AS artist_name,
                   ' . TRACK_ARTIST_ID . ' AS artist_id,
                   COALESCE(ss.play_count, 0) AS play_count
            FROM songs s
            JOIN albums al ON s.album_id = al.id
            JOIN artists a ON al.artist_id = a.id
            ' . TRACK_ARTIST_JOIN . '
            LEFT JOIN song_stats ss ON ss.song_id = s.id
            WHERE al.artist_id = ?
            ORDER BY play_count DESC, s.title ASC
            LIMIT 5
        ');
        $topStmt->execute([$artistId]);
        $topTracks = [];
        while ($row = $topStmt->fetch()) {
            $topTracks[] = [
                'id'         => (int)$row['id'],
                'title'      => $row['title'],
                'duration'   => (int)$row['duration'],
                'filePath'   => $row['file_path'],
                'albumId'    => (int)$row['album_id'],
                'albumName'  => $row['album_name'],
                'albumYear'  => $row['year'],
                'playCount'  => (int)$row['play_count'],
                'artworkUrl' => albumArtworkUrl((int)$row['album_id']),
                'artistId'   => $row['artist_id'] !== null ? (int)$row['artist_id'] : null,
                'artistName' => $row['artist_name'],
            ];
        }

        $response['data'] = [
            'artist' => [
                'id' => $artist['id'],
                'name' => $artist['name'],
                'imageUrl' => 'serve_image.php?artist_id=' . $artist['id'],
                'genre' => $artist['genre'] ?? null
            ],
            'albums' => $albums,
            'topTracks' => $topTracks,
            'totalSongs' => $totalSongs
        ];

    } elseif ($action === 'song_properties') {
        $songId = (int)($_GET['song_id'] ?? 0);
        if (!$songId) {
            $response['error'] = true;
            $response['message'] = 'song_id required';
        } else {
            $stmt = $conn->prepare("
                SELECT s.id, s.title, s.track_number, s.duration, s.file_path, s.file_hash,
                       al.name AS album_name, al.year, al.id AS album_id,
                       ar.name AS artist_name, ar.user,
                       ta.id AS track_artist_id, ta.name AS track_artist_name
                FROM songs s
                JOIN albums al ON s.album_id = al.id
                JOIN artists ar ON al.artist_id = ar.id
                LEFT JOIN artists ta ON s.artist_id = ta.id
                WHERE s.id = ? AND ar.user = ?
            ");
            $stmt->execute([$songId, $user]);
            $song = $stmt->fetch(PDO::FETCH_ASSOC);

            if (!$song) {
                $response['error'] = true;
                $response['message'] = 'Song not found';
            } else {
                require_once __DIR__ . '/../../src/Storage/StorageFactory.php';
                $storage  = StorageFactory::forUser($song['user']);
                $absPath  = $storage->getPathBase() . '/' . ltrim($song['file_path'], '/');
                $stat     = $storage->stat($absPath);
                $ext      = strtoupper(pathinfo($song['file_path'], PATHINFO_EXTENSION));

                $response['data'] = [
                    'id'              => (int)$song['id'],
                    'title'           => $song['title'],
                    'artist'          => $song['artist_name'],
                    'artistId'        => $song['track_artist_id'] ? (int)$song['track_artist_id'] : null,
                    'artistName'      => $song['track_artist_name'] ?: null,
                    'album'           => $song['album_name'],
                    'albumId'         => (int)$song['album_id'],
                    'year'            => $song['year'],
                    'track_number'    => $song['track_number'],
                    'duration'        => (int)$song['duration'],
                    'file_path'       => $song['file_path'],
                    'abs_path'        => $absPath,
                    'file_hash'       => $song['file_hash'],
                    'format'          => $ext ?: '?',
                    'file_size'       => $stat['size'],
                    'mtime'           => $stat['mtime'],
                    'storage_type'    => $storage->getType(),
                ];
            }
        }

    } elseif ($action === 'album' || $action === 'album_songs') {
        $albumId = isset($_GET['id']) ? intval($_GET['id']) : (isset($_GET['album_id']) ? intval($_GET['album_id']) : 0);

        // Get album info
        $stmt = $conn->prepare('
            SELECT al.*, a.name as artist_name, a.id as artist_id
            FROM albums al
            JOIN artists a ON al.artist_id = a.id
            WHERE al.id = ?
        ');
        $stmt->execute([$albumId]);
        $album = $stmt->fetch();

        // Get songs with optional per-track artist (for compilations)
        $stmt = $conn->prepare('
            SELECT s.*, ta.id AS track_artist_id, ta.name AS track_artist_name,
                   COALESCE(ss.play_count, 0) AS play_count
            FROM songs s
            LEFT JOIN artists ta   ON s.artist_id = ta.id
            LEFT JOIN song_stats ss ON ss.song_id = s.id
            WHERE s.album_id = ?
            ORDER BY s.track_number ASC, s.title ASC
        ');
        $stmt->execute([$albumId]);

        $songs = [];
        while ($row = $stmt->fetch()) {
            // Interprète réel de la piste : artiste lié, sinon tag ID3
            // (colonne track_artist) — utile pour les compilations. Sans
            // rien de plus précis, la piste hérite de l'artiste de l'album
            // (le lecteur doit toujours afficher un interprète).
            $trackArtist = $row['track_artist_name']
                ?: (($row['track_artist'] ?? '') !== '' ? $row['track_artist'] : null);
            $songs[] = [
                'id' => $row['id'],
                'title' => $row['title'],
                'trackNumber' => (int)$row['track_number'],
                'duration' => (int)$row['duration'],
                'filePath' => $row['file_path'],
                'albumId' => $row['album_id'],
                'albumName' => $album['name'],
                'artworkUrl' => albumArtworkUrl((int)$row['album_id']),
                // Pas d'identifiant quand le nom ne vient que du tag ID3 :
                // aucune fiche artiste ne lui correspond.
                'artistId' => $row['track_artist_id']
                    ? (int)$row['track_artist_id']
                    : (($trackArtist === null
                        || strcasecmp($trackArtist, (string)$album['artist_name']) === 0)
                        ? (int)$album['artist_id'] : null),
                'artistName' => $trackArtist ?: $album['artist_name'],
                'playCount' => (int)$row['play_count'],
            ];
        }

        $response['data'] = [
            'id' => $album['id'],
            'name' => $album['name'],
            'year' => $album['year'],
            'artworkUrl' => albumArtworkUrl((int)$album['id']),
            'artist' => [
                'id' => $album['artist_id'],
                'name' => $album['artist_name']
            ],
            'songs' => $songs
        ];

    } elseif ($action === 'get_random_artists') {
        $limit = isset($_GET['limit']) ? intval($_GET['limit']) : 12;

        $stmt = $conn->prepare('
            SELECT
                a.id,
                a.name,
                (SELECT COUNT(*) FROM albums WHERE artist_id = a.id) as album_count,
                (SELECT COUNT(*) FROM songs s JOIN albums al ON s.album_id = al.id WHERE al.artist_id = a.id) as song_count
            FROM artists a
            WHERE a.user = ?
            ORDER BY RAND()
            LIMIT ?
        ');
        $stmt->execute([$user, $limit]);
        $artists = [];
        while ($row = $stmt->fetch()) {
            $artists[] = [
                'id' => $row['id'],
                'name' => $row['name'],
                'imageUrl' => 'serve_image.php?artist_id=' . $row['id'],
                'album_count' => (int)$row['album_count'],
                'song_count' => (int)$row['song_count']
            ];
        }
        $response['data'] = ['artists' => $artists];

    } elseif ($action === 'get_stats') {
        // 1. General stats from play_history
        $stmt = $conn->prepare('
            SELECT
                COUNT(*) as totalPlays,
                COALESCE(SUM(ph.play_duration), 0) as totalListenTime,
                COUNT(DISTINCT ph.song_id) as uniqueSongsPlayed,
                ROUND(AVG(CASE WHEN ph.completed = 1 THEN 100 ELSE 0 END)) as completionRate,
                COALESCE(AVG(ph.play_duration), 0) as avgDuration
            FROM play_history ph
            JOIN songs s ON ph.song_id = s.id
            JOIN albums al ON s.album_id = al.id
            JOIN artists a ON al.artist_id = a.id
            WHERE ph.user = ?
        ');
        $stmt->execute([$user]);
        $general = $stmt->fetch(PDO::FETCH_ASSOC);

        // Total skips
        $stmt = $conn->prepare('
            SELECT COALESCE(SUM(ss.skip_count), 0) as totalSkips
            FROM song_stats ss
            JOIN songs s ON ss.song_id = s.id
            JOIN albums al ON s.album_id = al.id
            JOIN artists a ON al.artist_id = a.id
            WHERE a.user = ?
        ');
        $stmt->execute([$user]);
        $skipsRow = $stmt->fetch(PDO::FETCH_ASSOC);
        $totalSkips = (int)($skipsRow['totalSkips'] ?? 0);

        // Format times
        $totalSecs = (int)($general['totalListenTime'] ?? 0);
        $hours = floor($totalSecs / 3600);
        $mins = floor(($totalSecs % 3600) / 60);
        $totalListenTimeFormatted = $hours > 0 ? "{$hours}h {$mins}m" : "{$mins}m";

        $avgSecs = (int)($general['avgDuration'] ?? 0);
        $avgMins = floor($avgSecs / 60);
        $avgRemSecs = $avgSecs % 60;
        $avgDurationFormatted = "{$avgMins}m {$avgRemSecs}s";

        // 2. Top songs
        $stmt = $conn->prepare('
            SELECT s.id, s.title, a.name as artist_name, al.id as album_id, ss.play_count
            FROM song_stats ss
            JOIN songs s ON ss.song_id = s.id
            JOIN albums al ON s.album_id = al.id
            JOIN artists a ON al.artist_id = a.id
            WHERE a.user = ?
            ORDER BY ss.play_count DESC
            LIMIT 20
        ');
        $stmt->execute([$user]);
        $topSongs = [];
        while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
            $topSongs[] = [
                'id' => (int)$row['id'],
                'title' => $row['title'],
                'artist_name' => $row['artist_name'],
                'album_id' => (int)$row['album_id'],
                'artworkUrl' => albumArtworkUrl((int)$row['album_id']),
                'play_count' => (int)$row['play_count'],
            ];
        }

        // 3. Top artists
        $stmt = $conn->prepare('
            SELECT a.id, a.name, COUNT(ph.id) as play_count,
                   (a.image IS NOT NULL AND a.image != "") as has_image
            FROM play_history ph
            JOIN songs s ON ph.song_id = s.id
            JOIN albums al ON s.album_id = al.id
            JOIN artists a ON al.artist_id = a.id
            WHERE ph.user = ?
            GROUP BY a.id, a.name, has_image
            ORDER BY play_count DESC
            LIMIT 12
        ');
        $stmt->execute([$user]);
        $topArtists = [];
        while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
            $topArtists[] = [
                'id' => (int)$row['id'],
                'name' => $row['name'],
                'imageUrl' => $row['has_image'] ? 'serve_image.php?artist_id=' . $row['id'] : 'assets/radio-placeholder.svg',
                'play_count' => (int)$row['play_count'],
            ];
        }

        // 4. Top albums
        $stmt = $conn->prepare('
            SELECT al.id, al.name, a.name as artist_name, COUNT(ph.id) as play_count
            FROM play_history ph
            JOIN songs s ON ph.song_id = s.id
            JOIN albums al ON s.album_id = al.id
            JOIN artists a ON al.artist_id = a.id
            WHERE ph.user = ?
            GROUP BY al.id, al.name, a.name
            ORDER BY play_count DESC
            LIMIT 12
        ');
        $stmt->execute([$user]);
        $topAlbums = [];
        while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
            $topAlbums[] = [
                'id' => (int)$row['id'],
                'name' => $row['name'],
                'artist_name' => $row['artist_name'],
                'artworkUrl' => albumArtworkUrl((int)$row['id']),
                'play_count' => (int)$row['play_count'],
            ];
        }

        // 5. Recent plays
        $stmt = $conn->prepare('
            SELECT s.title, a.name as artist_name, al.id as album_id, ph.played_at
            FROM play_history ph
            JOIN songs s ON ph.song_id = s.id
            JOIN albums al ON s.album_id = al.id
            JOIN artists a ON al.artist_id = a.id
            WHERE ph.user = ?
            ORDER BY ph.played_at DESC
            LIMIT 20
        ');
        $stmt->execute([$user]);
        $recentPlays = [];
        while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
            $recentPlays[] = [
                'title' => $row['title'],
                'artist_name' => $row['artist_name'],
                'album_id' => (int)$row['album_id'],
                'artworkUrl' => albumArtworkUrl((int)$row['album_id']),
                'played_at_iso' => $row['played_at'],
            ];
        }

        // 6. Daily plays (last 30 days)
        $stmt = $conn->prepare('
            SELECT DATE(played_at) as day, COUNT(*) as count
            FROM play_history ph
            JOIN songs s ON ph.song_id = s.id
            JOIN albums al ON s.album_id = al.id
            JOIN artists a ON al.artist_id = a.id
            WHERE ph.user = ? AND played_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
            GROUP BY DATE(played_at)
            ORDER BY day ASC
        ');
        $stmt->execute([$user]);
        $dailyMap = [];
        foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
            $dailyMap[$row['day']] = (int)$row['count'];
        }
        $dailyLabels = [];
        $dailyData = [];
        for ($i = 29; $i >= 0; $i--) {
            $day = date('Y-m-d', strtotime("-{$i} days"));
            $dailyLabels[] = date('d/m', strtotime("-{$i} days"));
            $dailyData[] = $dailyMap[$day] ?? 0;
        }

        // 7. Hourly distribution
        $stmt = $conn->prepare('
            SELECT HOUR(played_at) as hour, COUNT(*) as count
            FROM play_history ph
            JOIN songs s ON ph.song_id = s.id
            JOIN albums al ON s.album_id = al.id
            JOIN artists a ON al.artist_id = a.id
            WHERE ph.user = ?
            GROUP BY HOUR(played_at)
        ');
        $stmt->execute([$user]);
        $hourlyMap = [];
        foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
            $hourlyMap[(int)$row['hour']] = (int)$row['count'];
        }
        $hourlyLabels = [];
        $hourlyData = [];
        for ($h = 0; $h < 24; $h++) {
            $hourlyLabels[] = sprintf('%02dh', $h);
            $hourlyData[] = $hourlyMap[$h] ?? 0;
        }

        // 8. Weekday distribution (MySQL: 1=Sunday ... 7=Saturday)
        $stmt = $conn->prepare('
            SELECT DAYOFWEEK(played_at) as dow, COUNT(*) as count
            FROM play_history ph
            JOIN songs s ON ph.song_id = s.id
            JOIN albums al ON s.album_id = al.id
            JOIN artists a ON al.artist_id = a.id
            WHERE ph.user = ?
            GROUP BY DAYOFWEEK(played_at)
        ');
        $stmt->execute([$user]);
        $weekdayMap = [];
        foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
            $weekdayMap[(int)$row['dow']] = (int)$row['count'];
        }
        $weekdayNames = ['Dim', 'Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam'];
        $weekdayLabels = [];
        $weekdayData = [];
        $maxDow = 0;
        $maxDowCount = 0;
        for ($d = 1; $d <= 7; $d++) {
            $weekdayLabels[] = $weekdayNames[$d - 1];
            $cnt = $weekdayMap[$d] ?? 0;
            $weekdayData[] = $cnt;
            if ($cnt > $maxDowCount) { $maxDowCount = $cnt; $maxDow = $d; }
        }
        $mostActiveDay = $maxDow > 0 ? $weekdayNames[$maxDow - 1] : '—';

        // 9. Library growth (by month, last 12 months)
        $stmt = $conn->prepare('
            SELECT
                DATE_FORMAT(al.created_at, "%Y-%m") as month,
                COUNT(DISTINCT s.id) as songs,
                COUNT(DISTINCT al.id) as albums,
                COUNT(DISTINCT a.id) as artists
            FROM songs s
            JOIN albums al ON s.album_id = al.id
            JOIN artists a ON al.artist_id = a.id
            WHERE a.user = ? AND al.created_at >= DATE_SUB(NOW(), INTERVAL 12 MONTH)
            GROUP BY DATE_FORMAT(al.created_at, "%Y-%m")
            ORDER BY month ASC
        ');
        $stmt->execute([$user]);
        $growthRaw = $stmt->fetchAll(PDO::FETCH_ASSOC);
        $growthLabels  = array_column($growthRaw, 'month');
        $growthSongs   = array_map(fn($r) => (int)$r['songs'],   $growthRaw);
        $growthAlbums  = array_map(fn($r) => (int)$r['albums'],  $growthRaw);
        $growthArtists = array_map(fn($r) => (int)$r['artists'], $growthRaw);

        // 10. Genre chart
        $stmt = $conn->prepare('
            SELECT al.genre, COUNT(DISTINCT a.id) as artist_count
            FROM albums al
            JOIN artists a ON al.artist_id = a.id
            WHERE a.user = ? AND al.genre IS NOT NULL AND al.genre != ""
            GROUP BY al.genre
            ORDER BY artist_count DESC
            LIMIT 10
        ');
        $stmt->execute([$user]);
        $genreRaw = $stmt->fetchAll(PDO::FETCH_ASSOC);
        $genreColors = ['#FF6384','#36A2EB','#FFCE56','#4BC0C0','#9966FF','#FF9F40','#FF6384','#C9CBCF','#7BC8A4','#E8A838'];
        $genreLabels = array_column($genreRaw, 'genre');
        $genreData   = array_map(fn($r) => (int)$r['artist_count'], $genreRaw);
        $genreColorSlice = array_slice($genreColors, 0, count($genreRaw));

        // 11. Genre coverage
        $stmt = $conn->prepare('
            SELECT
                COUNT(DISTINCT a.id) as totalArtists,
                COUNT(DISTINCT CASE WHEN al.genre IS NOT NULL AND al.genre != "" THEN a.id END) as artistsWithGenre
            FROM artists a
            LEFT JOIN albums al ON al.artist_id = a.id
            WHERE a.user = ?
        ');
        $stmt->execute([$user]);
        $coverageRow = $stmt->fetch(PDO::FETCH_ASSOC);
        $covTotal  = (int)($coverageRow['totalArtists'] ?? 0);
        $covWith   = (int)($coverageRow['artistsWithGenre'] ?? 0);
        $covPct    = $covTotal > 0 ? round($covWith / $covTotal * 100) : 0;

        $response['data'] = [
            'general' => [
                'totalPlays'               => (int)($general['totalPlays'] ?? 0),
                'totalListenTimeFormatted' => $totalListenTimeFormatted,
                'uniqueSongsPlayed'        => (int)($general['uniqueSongsPlayed'] ?? 0),
                'completionRate'           => (int)($general['completionRate'] ?? 0),
                'avgDurationFormatted'     => $avgDurationFormatted,
                'totalSkips'               => $totalSkips,
            ],
            'topSongs'       => $topSongs,
            'topArtists'     => $topArtists,
            'topAlbums'      => $topAlbums,
            'recentPlays'    => $recentPlays,
            'dailyPlaysChart'  => ['labels' => $dailyLabels,   'data' => $dailyData],
            'hourlyChart'      => ['labels' => $hourlyLabels,  'data' => $hourlyData],
            'weekdayChart'     => ['labels' => $weekdayLabels, 'data' => $weekdayData],
            'libraryGrowth'    => ['labels' => $growthLabels,  'songs' => $growthSongs, 'albums' => $growthAlbums, 'artists' => $growthArtists],
            'genreChart'       => ['labels' => $genreLabels,   'data' => $genreData,    'colors' => $genreColorSlice],
            'genreCoverage'    => ['totalArtists' => $covTotal, 'artistsWithGenre' => $covWith, 'percent' => $covPct],
            'insights'         => ['mostActiveDay' => $mostActiveDay],
        ];

    } elseif ($action === 'random_songs') {
        // Lecture aléatoire de toute la bibliothèque : échantillon mélangé
        // côté SQL (borné pour garder une file raisonnable). Les jeux peuvent
        // restreindre le vivier (genres, playlists, favoris) — voir GameSource.
        $limit = min(500, max(1, intval($_GET['limit'] ?? 200)));
        [$srcSql, $srcParams] = GameSource::songWhere($user, GameSource::fromRequest());
        $stmt = $conn->prepare("
            SELECT s.id, s.title, s.track_number, s.duration, s.file_path,
                   s.album_id, al.name AS album_name,
                   " . TRACK_ARTIST_ID . " AS artist_id,
                   " . TRACK_ARTIST_NAME . " AS artist_name
            FROM songs s
            JOIN albums al ON s.album_id = al.id
            JOIN artists a ON al.artist_id = a.id
            " . TRACK_ARTIST_JOIN . "
            WHERE a.user = ? $srcSql
            ORDER BY RAND()
            LIMIT $limit
        ");
        $stmt->execute(array_merge([$user], $srcParams));
        $songs = [];
        while ($row = $stmt->fetch()) {
            $songs[] = [
                'id' => (int)$row['id'],
                'title' => $row['title'],
                'trackNumber' => (int)$row['track_number'],
                'duration' => (int)$row['duration'],
                'filePath' => $row['file_path'],
                'albumId' => (int)$row['album_id'],
                'albumName' => $row['album_name'],
                'artworkUrl' => albumArtworkUrl((int)$row['album_id']),
                'artistId' => $row['artist_id'] !== null ? (int)$row['artist_id'] : null,
                'artistName' => $row['artist_name'],
            ];
        }
        $response['data'] = $songs;

    } elseif ($action === 'game_pool') {
        // Matière première des jeux (onglet « Jeux ») :
        //  - tracks : un titre par album daté ET pochetté, mélangé — sert au
        //    jeu « Chrono » (placer le titre sur la frise) et au « Duel
        //    d'années ». Un seul titre par album pour éviter les doublons de
        //    millésime dans une même partie.
        //  - albums : albums pochettés, mélangés — sert à « Pochette mystère ».
        // Les années absurdes sont écartées (tags parfois farfelus).
        // Le vivier peut être restreint (genres, playlists, favoris) : le
        // filtre s'applique DANS la sous-requête, pour que le titre retenu
        // par album soit lui-même dans le vivier.
        $limit = min(300, max(1, intval($_GET['limit'] ?? 150)));
        $source = GameSource::fromRequest();
        [$pickSql, $pickParams] = GameSource::songWhere($user, $source, 's2', 'al2', 'a2');
        $stmt = $conn->prepare("
            SELECT s.id, s.title, s.track_number, s.duration, s.file_path,
                   s.album_id, al.name AS album_name, al.year,
                   " . TRACK_ARTIST_ID . " AS artist_id,
                   " . TRACK_ARTIST_NAME . " AS artist_name
            FROM songs s
            JOIN (
                SELECT MIN(s2.id) AS song_id
                FROM songs s2
                JOIN albums al2 ON s2.album_id = al2.id
                JOIN artists a2 ON al2.artist_id = a2.id
                WHERE a2.user = ?
                  AND al2.year BETWEEN 1900 AND 2100
                  AND al2.artwork IS NOT NULL AND al2.artwork <> ''
                  $pickSql
                GROUP BY s2.album_id
            ) pick ON pick.song_id = s.id
            JOIN albums al ON s.album_id = al.id
            JOIN artists a ON al.artist_id = a.id
            " . TRACK_ARTIST_JOIN . "
            ORDER BY RAND()
            LIMIT $limit
        ");
        $stmt->execute(array_merge([$user], $pickParams));
        $tracks = [];
        while ($row = $stmt->fetch()) {
            $tracks[] = [
                'id' => (int)$row['id'],
                'title' => $row['title'],
                'trackNumber' => (int)$row['track_number'],
                'duration' => (int)$row['duration'],
                'filePath' => $row['file_path'],
                'albumId' => (int)$row['album_id'],
                'albumName' => $row['album_name'],
                'artworkUrl' => albumArtworkUrl((int)$row['album_id']),
                'artistId' => $row['artist_id'] !== null ? (int)$row['artist_id'] : null,
                'artistName' => $row['artist_name'],
                'year' => (int)$row['year'],
            ];
        }

        [$albSql, $albParams] = GameSource::albumWhere($user, $source);
        $stmt = $conn->prepare("
            SELECT al.id, al.name, al.year,
                   a.id AS artist_id, a.name AS artist_name
            FROM albums al
            JOIN artists a ON al.artist_id = a.id
            WHERE a.user = ?
              AND al.artwork IS NOT NULL AND al.artwork <> ''
              $albSql
            ORDER BY RAND()
            LIMIT $limit
        ");
        $stmt->execute(array_merge([$user], $albParams));
        $albums = [];
        while ($row = $stmt->fetch()) {
            $albums[] = [
                'id' => (int)$row['id'],
                'name' => $row['name'],
                'year' => $row['year'] !== null ? (int)$row['year'] : null,
                'artworkUrl' => albumArtworkUrl((int)$row['id']),
                'artistId' => (int)$row['artist_id'],
                'artistName' => $row['artist_name'],
            ];
        }

        $response['data'] = ['tracks' => $tracks, 'albums' => $albums];

    } elseif ($action === 'recent_songs') {
        // « Derniers joués » : titres récemment écoutés (distincts, jouables),
        // ordonnés du plus récent. Pour Android Auto notamment.
        $limit = min(200, max(1, intval($_GET['limit'] ?? 50)));
        $stmt = $conn->prepare("
            SELECT s.id, s.title, s.track_number, s.duration, s.file_path,
                   s.album_id, al.name AS album_name,
                   " . TRACK_ARTIST_ID . " AS artist_id,
                   " . TRACK_ARTIST_NAME . " AS artist_name,
                   MAX(ph.played_at) AS last_played
            FROM play_history ph
            JOIN songs s   ON ph.song_id = s.id
            JOIN albums al ON s.album_id = al.id
            JOIN artists a ON al.artist_id = a.id
            " . TRACK_ARTIST_JOIN . "
            WHERE ph.user = ?
            GROUP BY s.id
            ORDER BY last_played DESC
            LIMIT $limit
        ");
        $stmt->execute([$user]);
        $songs = [];
        while ($row = $stmt->fetch()) {
            $songs[] = [
                'id' => (int)$row['id'],
                'title' => $row['title'],
                'trackNumber' => (int)$row['track_number'],
                'duration' => (int)$row['duration'],
                'filePath' => $row['file_path'],
                'albumId' => (int)$row['album_id'],
                'albumName' => $row['album_name'],
                'artworkUrl' => albumArtworkUrl((int)$row['album_id']),
                'artistId' => $row['artist_id'] !== null ? (int)$row['artist_id'] : null,
                'artistName' => $row['artist_name'],
            ];
        }
        $response['data'] = $songs;

    } elseif ($action === 'song_transitions') {
        // Fondu enchaîné intelligent (idée #79) : ce que fait le son aux bords
        // des titres demandés (silence de fin, descente naturelle, entrée en
        // matière), pour que l'app taille son croisement dessus au lieu de
        // fondre X secondes quoi qu'il arrive. Voir src/TransitionAnalysis.php.
        //
        // L'app n'en demande que deux à la fois (le titre en cours et le
        // suivant) ; la borne est là pour qu'un appel bricolé ne lance pas
        // ffmpeg cinquante fois d'affilée.
        $ids = array_slice(
            array_map('intval', array_filter(explode(',', (string)($_GET['ids'] ?? '')))),
            0,
            4
        );
        $profiles = $ids ? TransitionAnalysis::forSongs($conn, $user, $ids) : [];
        $transitions = [];
        foreach ($profiles as $songId => $p) {
            $transitions[] = [
                'songId'  => (int)$songId,
                'tailMs'  => $p['tailMs'],
                'decayMs' => $p['decayMs'],
                'leadMs'  => $p['leadMs'],
                'levelDb' => $p['levelDb'],
            ];
        }
        $response['data'] = ['transitions' => $transitions];

    } elseif ($action === 'discovery_songs') {
        // « Découverte » : titres jamais joués (absents de play_history),
        // mélangés. Idéal pour redécouvrir sa bibliothèque.
        $limit = min(500, max(1, intval($_GET['limit'] ?? 200)));
        $stmt = $conn->prepare("
            SELECT s.id, s.title, s.track_number, s.duration, s.file_path,
                   s.album_id, al.name AS album_name,
                   " . TRACK_ARTIST_ID . " AS artist_id,
                   " . TRACK_ARTIST_NAME . " AS artist_name
            FROM songs s
            JOIN albums al ON s.album_id = al.id
            JOIN artists a ON al.artist_id = a.id
            " . TRACK_ARTIST_JOIN . "
            LEFT JOIN play_history ph
                ON ph.song_id = s.id AND ph.user = ?
            WHERE a.user = ? AND ph.id IS NULL
            ORDER BY RAND()
            LIMIT $limit
        ");
        $stmt->execute([$user, $user]);
        $songs = [];
        while ($row = $stmt->fetch()) {
            $songs[] = [
                'id' => (int)$row['id'],
                'title' => $row['title'],
                'trackNumber' => (int)$row['track_number'],
                'duration' => (int)$row['duration'],
                'filePath' => $row['file_path'],
                'albumId' => (int)$row['album_id'],
                'albumName' => $row['album_name'],
                'artworkUrl' => albumArtworkUrl((int)$row['album_id']),
                'artistId' => $row['artist_id'] !== null ? (int)$row['artist_id'] : null,
                'artistName' => $row['artist_name'],
            ];
        }
        $response['data'] = $songs;

    } elseif ($action === 'discovery_tracks') {
        // Jeu « Défricheur » : titres jamais joués, pochettés, servis un par
        // un. Contrairement à `discovery_albums`, un album entamé garde ses
        // titres vierges dans le vivier — c'est bien la chanson qu'on juge.
        $limit = min(200, max(1, intval($_GET['limit'] ?? 60)));
        [$srcSql, $srcParams] = GameSource::songWhere($user, GameSource::fromRequest());
        $stmt = $conn->prepare("
            SELECT s.id, s.title, s.track_number, s.duration, s.file_path,
                   s.album_id, al.name AS album_name, al.year,
                   " . TRACK_ARTIST_ID . " AS artist_id,
                   " . TRACK_ARTIST_NAME . " AS artist_name
            FROM songs s
            JOIN albums al ON s.album_id = al.id
            JOIN artists a ON al.artist_id = a.id
            " . TRACK_ARTIST_JOIN . "
            LEFT JOIN play_history ph
                ON ph.song_id = s.id AND ph.user = ?
            WHERE a.user = ? AND ph.id IS NULL
              AND al.artwork IS NOT NULL AND al.artwork <> ''
              -- Trente secondes à faire entendre : les jingles et autres
              -- interludes n'ont rien à se faire juger. Une durée inconnue
              -- (0) reste admise, sinon certaines bibliothèques se videraient.
              AND (s.duration = 0 OR s.duration >= 45)
              $srcSql
            ORDER BY RAND()
            LIMIT $limit
        ");
        $stmt->execute(array_merge([$user, $user], $srcParams));
        $songs = [];
        while ($row = $stmt->fetch()) {
            $songs[] = [
                'id' => (int)$row['id'],
                'title' => $row['title'],
                'trackNumber' => (int)$row['track_number'],
                'duration' => (int)$row['duration'],
                'filePath' => $row['file_path'],
                'albumId' => (int)$row['album_id'],
                'albumName' => $row['album_name'],
                'artworkUrl' => albumArtworkUrl((int)$row['album_id']),
                'artistId' => $row['artist_id'] !== null ? (int)$row['artist_id'] : null,
                'artistName' => $row['artist_name'],
                'year' => $row['year'] !== null ? (int)$row['year'] : null,
            ];
        }
        $response['data'] = ['songs' => $songs];

    } elseif ($action === 'discovery_albums') {
        // Ancienne mouture du Défricheur (albums entiers, app ≤ 2.71) :
        // gardée pour les téléphones pas encore mis à jour.
        // Jeu « Défricheur » : albums pochettés dont AUCUN titre n'a jamais
        // été joué, avec un titre représentatif pour l'extrait de trente
        // secondes. Un album entamé une seule fois n'est plus à défricher :
        // c'est bien l'album entier qui doit être vierge.
        $limit = min(200, max(1, intval($_GET['limit'] ?? 60)));
        [$srcSql, $srcParams] = GameSource::albumWhere($user, GameSource::fromRequest());
        $stmt = $conn->prepare("
            SELECT al.id, al.name, al.year,
                   a.id AS artist_id, a.name AS artist_name,
                   (SELECT COUNT(*) FROM songs sc WHERE sc.album_id = al.id) AS song_count,
                   s.id AS song_id, s.title, s.track_number, s.duration,
                   s.file_path,
                   " . TRACK_ARTIST_NAME . " AS track_artist_name
            FROM albums al
            JOIN artists a ON al.artist_id = a.id
            JOIN songs s ON s.id = (
                -- Le titre servi en extrait : de préférence assez long pour
                -- qu'il y ait quelque chose à entendre, sinon la piste 1.
                SELECT s2.id FROM songs s2
                WHERE s2.album_id = al.id
                ORDER BY (s2.duration >= 60) DESC, s2.track_number ASC, s2.id ASC
                LIMIT 1
            )
            " . TRACK_ARTIST_JOIN . "
            WHERE a.user = ?
              AND al.artwork IS NOT NULL AND al.artwork <> ''
              AND NOT EXISTS (
                  SELECT 1 FROM play_history ph
                  JOIN songs sp ON sp.id = ph.song_id
                  WHERE sp.album_id = al.id AND ph.user = ?
              )
              $srcSql
            ORDER BY RAND()
            LIMIT $limit
        ");
        $stmt->execute(array_merge([$user, $user], $srcParams));
        $albums = [];
        while ($row = $stmt->fetch()) {
            $artwork = albumArtworkUrl((int)$row['id']);
            $albums[] = [
                'id' => (int)$row['id'],
                'name' => $row['name'],
                'year' => $row['year'] !== null ? (int)$row['year'] : null,
                'artworkUrl' => $artwork,
                'artistId' => (int)$row['artist_id'],
                'artistName' => $row['artist_name'],
                'songCount' => (int)$row['song_count'],
                'sample' => [
                    'id' => (int)$row['song_id'],
                    'title' => $row['title'],
                    'trackNumber' => (int)$row['track_number'],
                    'duration' => (int)$row['duration'],
                    'filePath' => $row['file_path'],
                    'albumId' => (int)$row['id'],
                    'albumName' => $row['name'],
                    'artworkUrl' => $artwork,
                    'artistId' => (int)$row['artist_id'],
                    'artistName' => $row['track_artist_name'],
                ],
            ];
        }
        $response['data'] = ['albums' => $albums];

    } elseif ($action === 'search') {
        // `q` historique; `query` accepté aussi (client mobile).
        $query = trim($_GET['q'] ?? $_GET['query'] ?? '');
        $searchTerm = "%{$query}%";

        $stmt = $conn->prepare('
            SELECT
                s.id,
                s.title,
                s.track_number,
                s.duration,
                s.file_path,
                s.album_id,
                al.name as album_name,
                ' . TRACK_ARTIST_NAME . ' as artist_name,
                ' . TRACK_ARTIST_ID . ' as artist_id
            FROM songs s
            JOIN albums al ON s.album_id = al.id
            JOIN artists a ON al.artist_id = a.id
            ' . TRACK_ARTIST_JOIN . '
            WHERE a.user = ?
            AND (
                s.title LIKE ? OR
                a.name LIKE ? OR
                al.name LIKE ? OR
                ta.name LIKE ? OR
                s.track_artist LIKE ?
            )
            ORDER BY a.name ASC, al.name ASC, s.track_number ASC
            LIMIT 100
        ');
        $stmt->execute([$user, $searchTerm, $searchTerm, $searchTerm, $searchTerm, $searchTerm]);

        $songs = [];
        while ($row = $stmt->fetch()) {
            $songs[] = [
                'id' => $row['id'],
                'title' => $row['title'],
                'trackNumber' => (int)$row['track_number'],
                'duration' => (int)$row['duration'],
                'filePath' => $row['file_path'],
                'albumId' => $row['album_id'],
                'albumName' => $row['album_name'],
                'artworkUrl' => albumArtworkUrl((int)$row['album_id']),
                'artistId' => $row['artist_id'] !== null ? (int)$row['artist_id'] : null,
                'artistName' => $row['artist_name']
            ];
        }

        // Artistes et albums correspondants (le client mobile les affiche).
        $artists = [];
        $albums = [];
        if ($query !== '') {
            $stmt = $conn->prepare('
                SELECT id, name
                FROM artists
                WHERE user = ? AND name LIKE ?
                ORDER BY name ASC
                LIMIT 20
            ');
            $stmt->execute([$user, $searchTerm]);
            while ($row = $stmt->fetch()) {
                $artists[] = [
                    'id' => (int)$row['id'],
                    'name' => $row['name'],
                    'imageUrl' => 'serve_image.php?artist_id=' . $row['id'],
                ];
            }

            $stmt = $conn->prepare('
                SELECT al.id, al.name, al.year, a.id AS artist_id, a.name AS artist_name
                FROM albums al
                JOIN artists a ON al.artist_id = a.id
                WHERE a.user = ? AND al.name LIKE ?
                ORDER BY al.name ASC
                LIMIT 20
            ');
            $stmt->execute([$user, $searchTerm]);
            while ($row = $stmt->fetch()) {
                $albums[] = [
                    'id' => (int)$row['id'],
                    'name' => $row['name'],
                    'year' => $row['year'] !== null ? (int)$row['year'] : null,
                    'artistId' => (int)$row['artist_id'],
                    'artistName' => $row['artist_name'],
                    'artworkUrl' => albumArtworkUrl((int)$row['id']),
                ];
            }
        } else {
            // Requête vide : ne rien renvoyer plutôt que toute la bibliothèque.
            $songs = [];
        }

        $response['data'] = ['songs' => $songs, 'artists' => $artists, 'albums' => $albums];

    } elseif ($action === 'get_genres') {
        $stmt = $conn->prepare('
            SELECT
                al.genre,
                COUNT(DISTINCT a.id) as artist_count,
                COUNT(DISTINCT al.id) as album_count
            FROM albums al
            JOIN artists a ON al.artist_id = a.id
            WHERE a.user = ? AND al.genre IS NOT NULL AND al.genre != ""
            GROUP BY al.genre
            ORDER BY al.genre ASC
        ');
        $stmt->execute([$user]);
        $rows = $stmt->fetchAll();

        // Aperçu : jusqu'à 4 pochettes par genre (les albums les plus
        // récents), pour la mosaïque de la vue « Genres » de l'app.
        $covers = [];
        $coverStmt = $conn->prepare('
            SELECT t.genre, t.id FROM (
                SELECT al.genre AS genre, al.id AS id,
                       ROW_NUMBER() OVER (
                           PARTITION BY al.genre ORDER BY al.id DESC
                       ) AS rn
                FROM albums al
                JOIN artists a ON al.artist_id = a.id
                WHERE a.user = ? AND al.genre IS NOT NULL AND al.genre != ""
                  AND al.artwork IS NOT NULL AND al.artwork != ""
            ) t
            WHERE t.rn <= 4
        ');
        $coverStmt->execute([$user]);
        while ($cover = $coverStmt->fetch()) {
            $covers[$cover['genre']][] = albumArtworkUrl((int)$cover['id']);
        }

        $genres = [];
        foreach ($rows as $row) {
            $genres[] = [
                'name' => $row['genre'],
                'artistCount' => (int)$row['artist_count'],
                'albumCount' => (int)$row['album_count'],
                'artworkUrls' => $covers[$row['genre']] ?? []
            ];
        }
        $response['data'] = ['genres' => $genres];

    } elseif ($action === 'get_years') {
        // Machine à remonter le temps (idée #80) : les millésimes présents
        // dans la bibliothèque. L'année vient de l'album — c'est la seule
        // date que porte la bibliothèque. Les années farfelues (tags
        // fantaisistes) sont écartées comme ailleurs.
        $stmt = $conn->prepare('
            SELECT al.year,
                   COUNT(DISTINCT al.id) AS album_count,
                   COUNT(s.id) AS song_count
            FROM albums al
            JOIN artists a ON al.artist_id = a.id
            LEFT JOIN songs s ON s.album_id = al.id
            WHERE a.user = ? AND al.year BETWEEN 1900 AND 2100
            GROUP BY al.year
            ORDER BY al.year DESC
        ');
        $stmt->execute([$user]);
        $rows = $stmt->fetchAll();

        // Aperçu : jusqu'à 4 pochettes par année, comme la vue des genres.
        $covers = [];
        $coverStmt = $conn->prepare('
            SELECT t.year, t.id FROM (
                SELECT al.year AS year, al.id AS id,
                       ROW_NUMBER() OVER (
                           PARTITION BY al.year ORDER BY al.id DESC
                       ) AS rn
                FROM albums al
                JOIN artists a ON al.artist_id = a.id
                WHERE a.user = ? AND al.year BETWEEN 1900 AND 2100
                  AND al.artwork IS NOT NULL AND al.artwork != ""
            ) t
            WHERE t.rn <= 4
        ');
        $coverStmt->execute([$user]);
        while ($cover = $coverStmt->fetch()) {
            $covers[(int)$cover['year']][] = albumArtworkUrl((int)$cover['id']);
        }

        $years = [];
        foreach ($rows as $row) {
            $y = (int)$row['year'];
            $years[] = [
                'year'        => $y,
                'albumCount'  => (int)$row['album_count'],
                'songCount'   => (int)$row['song_count'],
                'artworkUrls' => $covers[$y] ?? [],
            ];
        }
        $response['data'] = ['years' => $years];

    } elseif ($action === 'year_songs') {
        // Le flux d'une année (idée #80) : les titres de cette année-là,
        // mélangés côté serveur, comme la lecture aléatoire d'un genre.
        $year  = (int)($_GET['year'] ?? 0);
        $limit = min(500, max(1, intval($_GET['limit'] ?? 200)));
        if ($year < 1900 || $year > 2100) {
            $response['error'] = true;
            $response['message'] = 'Invalid year';
        } else {
            $stmt = $conn->prepare("
                SELECT s.id, s.title, s.track_number, s.duration, s.file_path,
                       s.album_id, al.name AS album_name,
                       " . TRACK_ARTIST_ID . " AS artist_id,
                       " . TRACK_ARTIST_NAME . " AS artist_name
                FROM songs s
                JOIN albums al ON s.album_id = al.id
                JOIN artists a ON al.artist_id = a.id
                " . TRACK_ARTIST_JOIN . "
                WHERE a.user = ? AND al.year = ?
                ORDER BY RAND()
                LIMIT $limit
            ");
            $stmt->execute([$user, $year]);
            $songs = [];
            while ($row = $stmt->fetch()) {
                $songs[] = [
                    'id' => (int)$row['id'],
                    'title' => $row['title'],
                    'trackNumber' => (int)$row['track_number'],
                    'duration' => (int)$row['duration'],
                    'filePath' => $row['file_path'],
                    'albumId' => (int)$row['album_id'],
                    'albumName' => $row['album_name'],
                    'artworkUrl' => albumArtworkUrl((int)$row['album_id']),
                    'artistId' => $row['artist_id'] !== null ? (int)$row['artist_id'] : null,
                    'artistName' => $row['artist_name'],
                ];
            }
            $response['data'] = $songs;
        }

    } elseif ($action === 'get_genre_taxonomy') {
        // Ce que propose le choix du genre d'un artiste : la liste principale
        // d'abord (fermée, elle ne dépend ni de l'utilisateur ni de ce que
        // contient déjà la bibliothèque), puis les genres que l'utilisateur a
        // ajoutés lui-même, à la fin — la liste principale garde son ordre.
        $custom = customGenres($conn, $user);
        $response['data'] = [
            'genres' => array_merge(GenreTaxonomy::ALL, $custom),
            'custom' => $custom,
        ];

    } elseif ($action === 'add_genre') {
        // Ajoute un genre à la liste proposée, pour ce que la liste
        // principale ne couvre pas. Il vaut ensuite les autres : il se choisit
        // d'un tap et se renomme ou se supprime depuis « Gérer les genres ».
        $name = trim(preg_replace('/\s+/u', ' ', (string)($_POST['name'] ?? $_GET['name'] ?? '')));
        $normalized = GenreTaxonomy::normalize($name);
        $existing = null;
        if ($normalized !== '') {
            foreach (array_merge(GenreTaxonomy::ALL, customGenres($conn, $user)) as $g) {
                if (GenreTaxonomy::normalize($g) === $normalized) {
                    $existing = $g;
                    break;
                }
            }
        }

        if ($name === '' || $normalized === '') {
            $response['error']   = true;
            $response['message'] = 'Il faut un nom de genre.';
        } elseif (mb_strlen($name) > 100) {
            $response['error']   = true;
            $response['message'] = 'Nom de genre trop long (100 caractères).';
        } elseif ($existing !== null) {
            $response['error']   = true;
            $response['message'] = "« {$existing} » est déjà dans la liste.";
        } else {
            customGenresTable($conn);
            $conn->prepare('INSERT INTO custom_genres (user, name) VALUES (?, ?)')
                 ->execute([$user, $name]);
            $response['data'] = ['genre' => $name];
        }

    } elseif ($action === 'suggest_artist_genre') {
        // Ce que les catalogues savent de l'artiste, ramené à la liste fermée :
        // le choix manuel part ainsi des mêmes sources que la détection
        // automatique. Rien n'est écrit — c'est une suggestion, on garde la
        // main.
        $artistId = (int)($_GET['artist_id'] ?? $_POST['artist_id'] ?? 0);
        $stmt = $conn->prepare('SELECT name FROM artists WHERE id = ? AND user = ?');
        $stmt->execute([$artistId, $user]);
        $artistName = $artistId ? (string)($stmt->fetchColumn() ?: '') : '';

        if ($artistName === '') {
            $response['error']   = true;
            $response['message'] = 'Artist not found or access denied';
        } else {
            // Deux allers-retours réseau par artiste : on garde la réponse un
            // mois sur le disque, sinon rouvrir le dialogue refait attendre
            // pour un genre qui, lui, ne bouge pas. Une réponse VIDE ne tient
            // qu'un jour : elle vient aussi bien d'un artiste inconnu au
            // bataillon que d'un refus de passage de MusicBrainz, et on ne va
            // pas s'en tenir là un mois durant.
            $cacheFile = AppConfig::getDataPath() . '/cache/genre-suggest-'
                . md5(mb_strtolower($artistName, 'UTF-8')) . '.json';
            $cached = @filemtime($cacheFile)
                ? json_decode((string)@file_get_contents($cacheFile), true)
                : null;
            if (is_array($cached)) {
                $age    = time() - filemtime($cacheFile);
                $isThin = ($cached['genre'] ?? null) === null && empty($cached['tags']);
                if ($age > ($isThin ? 86400 : 30 * 86400)) $cached = null;
            }

            if (is_array($cached)) {
                $suggestion = $cached;
            } else {
                require_once __DIR__ . '/../../src/GenreLookup.php';
                // Quelqu'un attend devant son téléphone : des appels courts,
                // et une seule reprise — mieux vaut « aucune suggestion »
                // qu'une minute d'attente. Deezer et Apple Music ne sont
                // consultés que si MusicBrainz n'a rien dit (idée #54).
                $suggestion = function_exists('curl_init')
                    ? GenreLookup::suggest($artistName, 4, 2)
                    : ['genre' => null, 'tags' => [], 'source' => null];
                @file_put_contents($cacheFile, json_encode($suggestion, JSON_UNESCAPED_UNICODE));
            }

            $response['data'] = $suggestion + ['artist_id' => $artistId, 'artist' => $artistName];
        }

    } elseif ($action === 'recent_albums') {
        $days = isset($_GET['days']) ? intval($_GET['days']) : 30;
        
        $stmt = $conn->prepare('
            SELECT al.*, a.name as artist_name
            FROM albums al
            JOIN artists a ON al.artist_id = a.id
            WHERE a.user = ? AND al.created_at >= DATE_SUB(NOW(), INTERVAL ? DAY)
            ORDER BY al.created_at DESC
            LIMIT 50
        ');
        $stmt->execute([$user, $days]);
        
        $albums = [];
        while ($row = $stmt->fetch()) {
            $albums[] = [
                'id' => $row['id'],
                'name' => $row['name'],
                'artistName' => $row['artist_name'],
                'year' => $row['year'],
                'artworkUrl' => albumArtworkUrl((int)$row['id']),
                'created_at' => $row['created_at']
            ];
        }
        $response['data'] = $albums;

    } elseif ($action === 'get_artists_by_genre') {
        $genre = isset($_GET['genre']) ? $_GET['genre'] : '';

        if (empty($genre)) {
            $response['error'] = true;
            $response['message'] = 'Genre parameter required';
        } else {
            $stmt = $conn->prepare('
                SELECT DISTINCT
                    a.id,
                    a.name,
                    (a.image IS NOT NULL AND a.image != "") as has_image,
                    COUNT(DISTINCT al.id) as album_count,
                    (SELECT COUNT(*) FROM songs s2 JOIN albums al2 ON s2.album_id = al2.id WHERE al2.artist_id = a.id) as song_count
                FROM artists a
                JOIN albums al ON a.id = al.artist_id
                WHERE a.user = ? AND al.genre = ?
                GROUP BY a.id, a.name
                ORDER BY a.name ASC
            ');
            $stmt->execute([$user, $genre]);

            $artists = [];
            while ($row = $stmt->fetch()) {
                $artists[] = [
                    'id' => $row['id'],
                    'name' => $row['name'],
                    'imageUrl' => $row['has_image'] ? 'serve_image.php?artist_id=' . $row['id'] : null,
                    'albumCount' => (int)$row['album_count'],
                    'songCount' => (int)$row['song_count']
                ];
            }
            $response['data'] = [
                'genre' => $genre,
                'artists' => $artists
            ];
        }

    } elseif ($action === 'get_artists_without_genre') {
        // Les artistes qu'il reste à ranger, par ordre alphabétique. Sert à
        // enchaîner le choix du genre d'un artiste au suivant sans repasser
        // par la bibliothèque ; `total` dit combien il en reste en tout, la
        // liste étant plafonnée.
        $limit = isset($_GET['limit']) ? max(1, min(500, (int)$_GET['limit'])) : 50;

        $stmt = $conn->prepare('
            SELECT
                id,
                name,
                (image IS NOT NULL AND image != "") as has_image,
                album_count,
                song_count
            FROM artists
            WHERE user = ? AND (genre IS NULL OR genre = "")
            ORDER BY name ASC
            LIMIT ?
        ');
        $stmt->execute([$user, $limit]);

        $artists = [];
        while ($row = $stmt->fetch()) {
            $artists[] = [
                'id' => (int)$row['id'],
                'name' => $row['name'],
                'imageUrl' => $row['has_image'] ? 'serve_image.php?artist_id=' . $row['id'] : null,
                'albumCount' => (int)$row['album_count'],
                'songCount' => (int)$row['song_count']
            ];
        }

        $stmt = $conn->prepare('
            SELECT COUNT(*) FROM artists
            WHERE user = ? AND (genre IS NULL OR genre = "")
        ');
        $stmt->execute([$user]);

        $response['data'] = [
            'artists' => $artists,
            'total' => (int)$stmt->fetchColumn()
        ];

    } elseif ($action === 'rename_genre') {
        // Renomme un genre partout (albums + artistes) pour l'utilisateur.
        $from = trim((string)($_POST['from'] ?? ''));
        $to   = trim((string)($_POST['to'] ?? ''));
        if ($from === '' || $to === '') {
            $response['error']   = true;
            $response['message'] = 'from and to required';
        } else {
            $to = mb_substr($to, 0, 100);
            $conn->prepare("
                UPDATE albums al JOIN artists a ON al.artist_id = a.id
                SET al.genre = ? WHERE a.user = ? AND al.genre = ?
            ")->execute([$to, $user, $from]);
            $conn->prepare("UPDATE artists SET genre = ? WHERE user = ? AND genre = ?")
                 ->execute([$to, $user, $from]);

            // Un genre ajouté à la main suit son nom. S'il arrive sur un genre
            // qui existe déjà (liste principale ou autre ajout), les deux n'en
            // font plus qu'un : la ligne de départ n'a plus lieu d'être.
            customGenresTable($conn);
            $sameName = GenreTaxonomy::normalize($from) === GenreTaxonomy::normalize($to);
            if (!$sameName) {
                $conn->prepare('DELETE FROM custom_genres WHERE user = ? AND name = ?')
                     ->execute([$user, $to]);
            }
            if (GenreTaxonomy::isCanonical($to)) {
                $conn->prepare('DELETE FROM custom_genres WHERE user = ? AND name = ?')
                     ->execute([$user, $from]);
            } else {
                $conn->prepare('UPDATE custom_genres SET name = ? WHERE user = ? AND name = ?')
                     ->execute([$to, $user, $from]);
            }

            $response['data'] = ['from' => $from, 'to' => $to];
        }

    } elseif ($action === 'delete_genre') {
        // Retire un genre partout (met à NULL) pour l'utilisateur.
        $genre = trim((string)($_POST['genre'] ?? ''));
        if ($genre === '') {
            $response['error']   = true;
            $response['message'] = 'genre required';
        } else {
            $conn->prepare("
                UPDATE albums al JOIN artists a ON al.artist_id = a.id
                SET al.genre = NULL WHERE a.user = ? AND al.genre = ?
            ")->execute([$user, $genre]);
            $conn->prepare("UPDATE artists SET genre = NULL WHERE user = ? AND genre = ?")
                 ->execute([$user, $genre]);

            // Retirer un genre partout et le laisser dans les choix n'aurait
            // pas de sens : un genre ajouté à la main s'en va avec.
            customGenresTable($conn);
            $conn->prepare('DELETE FROM custom_genres WHERE user = ? AND name = ?')
                 ->execute([$user, $genre]);

            $response['data'] = ['deleted' => $genre];
        }

    } elseif ($action === 'set_artist_genre') {
        // Définit le genre d'un artiste et le propage à tous ses albums, pour
        // rester cohérent avec le filtre par genre (basé sur albums.genre).
        $artistId = (int)($_POST['artist_id'] ?? $_GET['artist_id'] ?? 0);
        $genre    = trim((string)($_POST['genre'] ?? $_GET['genre'] ?? ''));
        if (!$artistId) {
            $response['error']   = true;
            $response['message'] = 'artist_id required';
        } else {
            $stmt = $conn->prepare('SELECT id FROM artists WHERE id = ? AND user = ?');
            $stmt->execute([$artistId, $user]);
            if (!$stmt->fetch()) {
                $response['error']   = true;
                $response['message'] = 'Artist not found or access denied';
            } else {
                $g = $genre === '' ? null : mb_substr($genre, 0, 100);
                $conn->prepare('UPDATE artists SET genre = ? WHERE id = ? AND user = ?')
                     ->execute([$g, $artistId, $user]);
                $conn->prepare('UPDATE albums SET genre = ? WHERE artist_id = ?')
                     ->execute([$g, $artistId]);
                $response['data'] = ['artist_id' => $artistId, 'genre' => $g];
            }
        }

    } elseif ($action === 'artist_image_candidates') {
        // Les photos que YouTube Music et Deezer proposent pour cet artiste
        // (idée #78). La reconnaissance automatique n'accepte que le nom exact
        // et se tait au moindre doute ; ici on montre tout, avec le nom que
        // chaque service donne, pour choisir soi-même — et `q` permet de
        // chercher sous un autre nom quand c'est l'homonyme qui a été trouvé.
        require_once __DIR__ . '/../../src/ArtistImage.php';
        $artistId = (int)($_GET['artist_id'] ?? $_POST['artist_id'] ?? 0);
        $query    = trim((string)($_GET['q'] ?? $_POST['q'] ?? ''));
        $artist   = artistOfUser($conn, $artistId, $user);
        if (!$artist) {
            $response['error']   = true;
            $response['message'] = 'Artist not found or access denied';
        } else {
            $name = $query !== '' ? $query : (string)$artist['name'];
            $response['data'] = [
                'query'      => $name,
                'candidates' => ArtistImage::candidates($name),
            ];
        }

    } elseif ($action === 'set_artist_image') {
        // Change la photo d'un artiste (idée #78) : soit une adresse (lien
        // collé, ou proposition choisie dans la liste), soit une image
        // téléversée depuis le téléphone. Elle est rangée dans le cache, que
        // `serve_image.php` sert avant le dossier et avant le web : le choix
        // fait à la main tient donc jusqu'à ce qu'on le défasse.
        require_once __DIR__ . '/../../src/ArtistImage.php';
        $artistId = (int)($_POST['artist_id'] ?? $_GET['artist_id'] ?? 0);
        $url      = trim((string)($_POST['url'] ?? $_GET['url'] ?? ''));
        $artist   = artistOfUser($conn, $artistId, $user);
        $upload   = $_FILES['image'] ?? null;

        if (!$artist) {
            $response['error']   = true;
            $response['message'] = 'Artist not found or access denied';
        } elseif ($upload && ($upload['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_NO_FILE) {
            if ($upload['error'] !== UPLOAD_ERR_OK) {
                $response['error']   = true;
                $response['message'] = "L'image n'est pas arrivée entière.";
            } elseif (($upload['size'] ?? 0) > ArtistImage::MAX_BYTES) {
                $response['error']   = true;
                $response['message'] = 'Image trop volumineuse (8 Mo au plus).';
            } else {
                $bin = @file_get_contents($upload['tmp_name']);
                if ($bin === false || !ArtistImage::store($artistId, $bin)) {
                    $response['error']   = true;
                    $response['message'] = "Image illisible (JPEG ou PNG attendu).";
                } else {
                    $response['data'] = artistImagePayload($artistId);
                }
            }
        } elseif ($url !== '') {
            $bin = ArtistImage::download($url);
            if ($bin === null) {
                $response['error']   = true;
                $response['message'] = "Rien à télécharger à cette adresse.";
            } elseif (!ArtistImage::store($artistId, $bin)) {
                $response['error']   = true;
                $response['message'] = "Cette adresse ne donne pas une image (JPEG ou PNG attendu).";
            } else {
                $response['data'] = artistImagePayload($artistId);
            }
        } else {
            $response['error']   = true;
            $response['message'] = 'Aucune image reçue.';
        }

    } elseif ($action === 'reset_artist_image') {
        // Défait le choix manuel : l'image du dossier de l'artiste, ou celle
        // du web, reprend la main à la prochaine requête (idée #78).
        require_once __DIR__ . '/../../src/ArtistImage.php';
        $artistId = (int)($_POST['artist_id'] ?? $_GET['artist_id'] ?? 0);
        $artist   = artistOfUser($conn, $artistId, $user);
        if (!$artist) {
            $response['error']   = true;
            $response['message'] = 'Artist not found or access denied';
        } else {
            ArtistImage::forget($artistId);
            $response['data'] = artistImagePayload($artistId);
        }

    } elseif ($action === 'get_favorites') {
        // Returns [{id: songId}] — format expected by ui.js loadInitialData
        $stmt = $conn->prepare('SELECT song_id FROM favorites WHERE user = ?');
        $stmt->execute([$user]);
        $ids = $stmt->fetchAll(PDO::FETCH_COLUMN);
        $response['data'] = array_map(fn($id) => ['id' => (int)$id], $ids);

    } elseif ($action === 'get_all_favorites') {
        // Full details for the Favorites page (songs + their artists/albums deduplicated)
        $stmt = $conn->prepare('
            SELECT s.id, s.title, s.file_path, s.duration,
                   al.id AS album_id, al.name AS album_name, al.year,
                   a.id  AS artist_id, a.name AS artist_name,
                   ' . TRACK_ARTIST_NAME . ' AS track_artist_name,
                   (al.artwork IS NOT NULL AND al.artwork != "") AS has_artwork
            FROM favorites f
            JOIN songs   s  ON f.song_id    = s.id
            JOIN albums  al ON s.album_id   = al.id
            JOIN artists a  ON al.artist_id = a.id
            ' . TRACK_ARTIST_JOIN . '
            WHERE f.user = ?
            ORDER BY s.title ASC
        ');
        $stmt->execute([$user]);
        $rows = $stmt->fetchAll();

        $songs   = [];
        $artists = [];
        $albums  = [];
        $seenArtists = [];
        $seenAlbums  = [];

        foreach ($rows as $row) {
            $songs[] = [
                'id'         => (int)$row['id'],
                'title'      => $row['title'],
                // Interprète de la piste (compilations) ; les sections
                // « artistes »/« albums » ci-dessous gardent, elles,
                // l'artiste de l'album.
                'artist'     => $row['track_artist_name'],
                'album'      => $row['album_name'],
                'filePath'   => $row['file_path'],
                'duration'   => $row['duration'],
                'artworkUrl' => albumArtworkUrl((int)$row['album_id']),
            ];
            if (!isset($seenArtists[$row['artist_id']])) {
                $seenArtists[$row['artist_id']] = true;
                $artists[] = [
                    'id'          => (int)$row['artist_id'],
                    'name'        => $row['artist_name'],
                    'imageUrl'    => 'serve_image.php?artist_id=' . $row['artist_id'],
                    'album_count' => 0,
                ];
            }
            if (!isset($seenAlbums[$row['album_id']])) {
                $seenAlbums[$row['album_id']] = true;
                $albums[] = [
                    'id'          => (int)$row['album_id'],
                    'name'        => $row['album_name'],
                    'year'        => $row['year'],
                    'artist_name' => $row['artist_name'],
                    'artworkUrl'  => albumArtworkUrl((int)$row['album_id']),
                ];
            }
        }
        $response['data'] = compact('songs', 'artists', 'albums');

    } elseif ($action === 'toggle_favorite') {
        // Used by ui.js — checks existence then inserts or deletes
        $songId = (int)($_POST['song_id'] ?? 0);
        if (!$songId) {
            $response['error'] = true;
            $response['message'] = 'Missing song_id';
        } else {
            $stmt = $conn->prepare('SELECT COUNT(*) FROM favorites WHERE song_id = ? AND user = ?');
            $stmt->execute([$songId, $user]);
            $exists = (bool)$stmt->fetchColumn();
            if ($exists) {
                $conn->prepare('DELETE FROM favorites WHERE song_id = ? AND user = ?')->execute([$songId, $user]);
                $response['data'] = ['status' => 'removed'];
            } else {
                $conn->prepare('INSERT IGNORE INTO favorites (song_id, user) VALUES (?, ?)')->execute([$songId, $user]);
                $response['data'] = ['status' => 'added'];
            }
        }

    } elseif ($action === 'add_favorite') {
        $songId = (int)($_POST['song_id'] ?? 0);
        if (!$songId) { $response['error'] = true; $response['message'] = 'Missing song_id'; }
        else {
            $conn->prepare('INSERT IGNORE INTO favorites (song_id, user) VALUES (?, ?)')->execute([$songId, $user]);
            $response['message'] = 'Added to favorites';
        }

    } elseif ($action === 'remove_favorite') {
        $songId = (int)($_POST['song_id'] ?? 0);
        if (!$songId) { $response['error'] = true; $response['message'] = 'Missing song_id'; }
        else {
            $conn->prepare('DELETE FROM favorites WHERE song_id = ? AND user = ?')->execute([$songId, $user]);
            $response['message'] = 'Removed from favorites';
        }

    } elseif ($action === 'get_all_albums') {
        // Plafond élevé : l'app mobile charge toute la bibliothèque d'un coup
        // (index A-Z). L'ancien plafond de 200 tronquait les grandes
        // bibliothèques (le A-Z ne montrait que les premières lettres).
        $limit  = max(1, min(10000, (int)($_GET['limit'] ?? 48)));
        $offset = max(0, (int)($_GET['offset'] ?? 0));
        $sort   = in_array($_GET['sort'] ?? '', ['name', 'artist', 'year', 'recent', 'popular']) ? $_GET['sort'] : 'name';
        $search = trim($_GET['search'] ?? '');
        $genre  = trim($_GET['genre'] ?? '');

        $sortClause = match($sort) {
            'artist'  => 'a.name ASC, al.name ASC',
            'year'    => 'al.year DESC, al.name ASC',
            'recent'  => 'al.created_at DESC, al.name ASC',
            'popular' => 'play_count DESC, al.name ASC',
            default   => 'al.name ASC',
        };

        $params    = [$user];
        $extraSql  = '';
        if ($search !== '') {
            $extraSql .= ' AND (al.name LIKE ? OR a.name LIKE ?)';
            $params[]  = "%$search%";
            $params[]  = "%$search%";
        }
        if ($genre !== '') {
            $extraSql .= ' AND (al.genre = ? OR a.genre = ?)';
            $params[]  = $genre;
            $params[]  = $genre;
        }
        // Millésime (idée #80) : les albums d'une année précise, pour la
        // machine à remonter le temps de la bibliothèque.
        $year = (int)($_GET['year'] ?? 0);
        if ($year > 0) {
            $extraSql .= ' AND al.year = ?';
            $params[]  = $year;
        }

        $countStmt = $conn->prepare("
            SELECT COUNT(*)
            FROM albums al
            JOIN artists a ON al.artist_id = a.id
            WHERE a.user = ? $extraSql
        ");
        $countStmt->execute($params);
        $total = (int)$countStmt->fetchColumn();

        $params[] = $limit;
        $params[] = $offset;
        $stmt = $conn->prepare("
            SELECT al.id, al.name, al.year,
                   a.id AS artist_id, a.name AS artist_name,
                   COUNT(DISTINCT s.id) AS song_count,
                   COALESCE(SUM(ss.play_count), 0) AS play_count
            FROM albums al
            JOIN artists a ON al.artist_id = a.id
            LEFT JOIN songs s ON s.album_id = al.id
            LEFT JOIN song_stats ss ON ss.song_id = s.id
            WHERE a.user = ? $extraSql
            GROUP BY al.id, al.name, al.year, a.id, a.name
            ORDER BY $sortClause
            LIMIT ? OFFSET ?
        ");
        $stmt->execute($params);

        $albums = [];
        while ($row = $stmt->fetch()) {
            $albums[] = [
                'id'         => (int)$row['id'],
                'name'       => $row['name'],
                'artistId'   => (int)$row['artist_id'],
                'artistName' => $row['artist_name'],
                'year'       => $row['year'],
                'artworkUrl' => albumArtworkUrl((int)$row['id']),
                'songCount'  => (int)$row['song_count'],
                'playCount'  => (int)$row['play_count'],
            ];
        }

        $response['data'] = [
            'albums' => $albums,
            'total'  => $total,
            'offset' => $offset,
            'limit'  => $limit,
        ];

    } elseif ($action === 'get_album_genres') {
        // Distinct list of genres across the user's albums + artists
        $stmt = $conn->prepare("
            SELECT genre, COUNT(*) AS n FROM (
                SELECT al.genre AS genre
                FROM albums al
                JOIN artists a ON al.artist_id = a.id
                WHERE a.user = ? AND al.genre IS NOT NULL AND al.genre <> ''
                UNION ALL
                SELECT a.genre AS genre
                FROM artists a
                WHERE a.user = ? AND a.genre IS NOT NULL AND a.genre <> ''
            ) g
            GROUP BY genre
            ORDER BY n DESC, genre ASC
        ");
        $stmt->execute([$user, $user]);
        $genres = [];
        while ($row = $stmt->fetch()) {
            $genres[] = ['name' => $row['genre'], 'count' => (int)$row['n']];
        }
        $response['data'] = ['genres' => $genres];

    } elseif ($action === 'detect_duplicates') {
        // Albums with the same artist + same normalized name (case-insensitive)
        $stmt = $conn->prepare("
            SELECT
                a.id   AS artist_id,
                a.name AS artist_name,
                MIN(al.name) AS canonical_name,
                COUNT(DISTINCT al.id) AS album_count,
                GROUP_CONCAT(DISTINCT al.id   ORDER BY al.id SEPARATOR '|') AS album_ids,
                GROUP_CONCAT(al.name ORDER BY al.id SEPARATOR '\t') AS album_names,
                COUNT(s.id) AS total_songs
            FROM albums al
            JOIN artists a ON al.artist_id = a.id
            LEFT JOIN songs s ON s.album_id = al.id
            WHERE a.user = ?
            GROUP BY a.id, LOWER(TRIM(al.name))
            HAVING COUNT(DISTINCT al.id) > 1
            ORDER BY a.name ASC, MIN(al.name) ASC
        ");
        $stmt->execute([$user]);

        $groups = [];
        while ($row = $stmt->fetch()) {
            $ids   = array_map('intval', explode('|', $row['album_ids']));
            $names = explode("\t", $row['album_names']);
            $groups[] = [
                'artist_id'      => (int)$row['artist_id'],
                'artist_name'    => $row['artist_name'],
                'canonical_name' => $row['canonical_name'],
                'album_count'    => (int)$row['album_count'],
                'album_ids'      => $ids,
                'album_names'    => $names,
                'total_songs'    => (int)$row['total_songs'],
            ];
        }
        $totalRedundant = array_sum(array_map(fn($g) => $g['album_count'] - 1, $groups));
        $response['data'] = [
            'groups'          => $groups,
            'total_groups'    => count($groups),
            'total_redundant' => $totalRedundant,
        ];

    } elseif ($action === 'auto_merge_duplicates') {
        $stmt = $conn->prepare("
            SELECT
                MIN(al.id)   AS target_id,
                MIN(al.name) AS canonical_name,
                GROUP_CONCAT(al.id ORDER BY al.id SEPARATOR '|') AS album_ids
            FROM albums al
            JOIN artists a ON al.artist_id = a.id
            WHERE a.user = ?
            GROUP BY a.id, LOWER(TRIM(al.name))
            HAVING COUNT(al.id) > 1
        ");
        $stmt->execute([$user]);
        $groups = $stmt->fetchAll();

        if (empty($groups)) {
            $response['data'] = ['groups_merged' => 0, 'tags_updated' => 0, 'tags_failed' => 0];
        } else {
            require_once __DIR__ . '/../../src/TagEditor.php';
            $tagEditor    = new TagEditor();
            $groupsMerged = 0;
            $tagsUpdated  = 0;
            $tagsFailed   = 0;

            foreach ($groups as $row) {
                $allIds   = array_map('intval', explode('|', $row['album_ids']));
                $targetId = $allIds[0];
                $toDelete = array_slice($allIds, 1);
                $newName  = $row['canonical_name'];

                $phAll = implode(',', array_fill(0, count($allIds), '?'));
                $songStmt = $conn->prepare("SELECT id FROM songs WHERE album_id IN ($phAll)");
                $songStmt->execute($allIds);
                $songIds = $songStmt->fetchAll(PDO::FETCH_COLUMN);

                $phDel = implode(',', array_fill(0, count($toDelete), '?'));
                $conn->prepare("UPDATE songs SET album_id = ? WHERE album_id IN ($phDel)")
                     ->execute([$targetId, ...$toDelete]);
                $conn->prepare("DELETE FROM albums WHERE id IN ($phDel)")
                     ->execute($toDelete);
                $conn->prepare('UPDATE albums SET name = ? WHERE id = ?')
                     ->execute([$newName, $targetId]);

                foreach ($songIds as $songId) {
                    try {
                        $ok = $tagEditor->updateSongTags((int)$songId, ['album' => $newName]);
                        $ok ? $tagsUpdated++ : $tagsFailed++;
                    } catch (Throwable $e) {
                        $tagsFailed++;
                        error_log("auto_merge: tag write failed for song $songId: " . $e->getMessage());
                    }
                }
                $groupsMerged++;
            }
            $response['data'] = [
                'groups_merged' => $groupsMerged,
                'tags_updated'  => $tagsUpdated,
                'tags_failed'   => $tagsFailed,
            ];
        }

    } elseif ($action === 'rename_album') {
        $albumId = (int)($_POST['album_id'] ?? 0);
        $newName = trim($_POST['name'] ?? '');
        if (!$albumId || $newName === '') {
            $response['error'] = true;
            $response['message'] = 'Missing album_id or name';
        } else {
            // Verify ownership
            $stmt = $conn->prepare('SELECT al.id FROM albums al JOIN artists a ON al.artist_id = a.id WHERE al.id = ? AND a.user = ?');
            $stmt->execute([$albumId, $user]);
            if (!$stmt->fetch()) {
                $response['error'] = true;
                $response['message'] = 'Album not found or permission denied';
            } else {
                $conn->prepare('UPDATE albums SET name = ? WHERE id = ?')->execute([$newName, $albumId]);
                $response['data'] = ['id' => $albumId, 'name' => $newName];
            }
        }

    } elseif ($action === 'merge_albums') {
        $sourceIds = array_values(array_filter(array_map('intval', (array)($_POST['source_ids'] ?? []))));
        $newName   = trim($_POST['new_name'] ?? '');
        if (count($sourceIds) < 2 || $newName === '') {
            $response['error'] = true;
            $response['message'] = 'At least 2 source_ids and new_name are required';
        } else {
            // Verify all albums belong to this user
            $placeholders = implode(',', array_fill(0, count($sourceIds), '?'));
            $stmt = $conn->prepare("
                SELECT al.id FROM albums al
                JOIN artists a ON al.artist_id = a.id
                WHERE al.id IN ($placeholders) AND a.user = ?
            ");
            $stmt->execute([...$sourceIds, $user]);
            $validIds = $stmt->fetchAll(PDO::FETCH_COLUMN);
            if (count($validIds) !== count($sourceIds)) {
                $response['error'] = true;
                $response['message'] = 'Some albums not found or permission denied';
            } else {
                // Collect all song IDs across every selected album BEFORE moving them
                $allPlaceholders = implode(',', array_fill(0, count($sourceIds), '?'));
                $songStmt = $conn->prepare("SELECT id FROM songs WHERE album_id IN ($allPlaceholders)");
                $songStmt->execute($sourceIds);
                $songIds = $songStmt->fetchAll(PDO::FETCH_COLUMN);

                $targetId = $sourceIds[0];
                $toDelete = array_slice($sourceIds, 1);
                $delPlaceholders = implode(',', array_fill(0, count($toDelete), '?'));

                // Move all songs from other albums into target
                $conn->prepare("UPDATE songs SET album_id = ? WHERE album_id IN ($delPlaceholders)")
                     ->execute([$targetId, ...$toDelete]);

                // Delete now-empty albums
                $conn->prepare("DELETE FROM albums WHERE id IN ($delPlaceholders)")
                     ->execute($toDelete);

                // Rename the surviving album
                $conn->prepare('UPDATE albums SET name = ? WHERE id = ?')->execute([$newName, $targetId]);

                // Write new album name to ID3 tags in physical files
                $tagsUpdated = 0;
                $tagsFailed  = 0;
                if (!empty($songIds)) {
                    require_once __DIR__ . '/../../src/TagEditor.php';
                    $tagEditor = new TagEditor();
                    foreach ($songIds as $songId) {
                        try {
                            $ok = $tagEditor->updateSongTags((int)$songId, ['album' => $newName]);
                            $ok ? $tagsUpdated++ : $tagsFailed++;
                        } catch (Throwable $e) {
                            $tagsFailed++;
                            error_log("merge_albums: tag write failed for song $songId: " . $e->getMessage());
                        }
                    }
                }

                $response['data'] = [
                    'target_id'    => $targetId,
                    'name'         => $newName,
                    'merged'       => count($toDelete),
                    'songs_total'  => count($songIds),
                    'tags_updated' => $tagsUpdated,
                    'tags_failed'  => $tagsFailed,
                ];
            }
        }

    } elseif ($action === 'get_users' || $action === 'users') {
        $pathHelper = new PathHelper();
        $usernames = $pathHelper->getActiveUsernames();

        $response['data'] = [
            'users' => $usernames,
            'count' => count($usernames)
        ];

    } elseif ($action === 'detect_compilations') {
        $threshold = max(2, (int)($_GET['threshold'] ?? 3));
        $stmt = $conn->prepare("
            SELECT
                MIN(al.name) AS album_name,
                COUNT(DISTINCT ar.id) AS artist_count,
                GROUP_CONCAT(DISTINCT al.id   ORDER BY al.id SEPARATOR '|') AS album_ids,
                GROUP_CONCAT(DISTINCT ar.name ORDER BY al.id SEPARATOR '\t') AS artist_names,
                COUNT(s.id) AS total_songs
            FROM albums al
            JOIN artists ar ON al.artist_id = ar.id
            LEFT JOIN songs s ON s.album_id = al.id
            WHERE ar.user = ? AND al.is_compilation = 0
            GROUP BY LOWER(TRIM(al.name))
            HAVING COUNT(DISTINCT ar.id) >= ?
            ORDER BY COUNT(DISTINCT ar.id) DESC, MIN(al.name) ASC
        ");
        $stmt->execute([$user, $threshold]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $response['data'] = ['compilations' => array_map(fn($r) => [
            'album_name'   => $r['album_name'],
            'artist_count' => (int)$r['artist_count'],
            'album_ids'    => explode('|', $r['album_ids']),
            'artist_names' => explode("\t", $r['artist_names']),
            'total_songs'  => (int)$r['total_songs'],
        ], $rows)];

    } elseif ($action === 'merge_compilation') {
        $body       = json_decode(file_get_contents('php://input'), true) ?? [];
        $albumIds   = array_map('intval', $body['album_ids']   ?? []);
        $artistName = trim($body['artist_name'] ?? 'Various Artists');
        $albumName  = trim($body['album_name']  ?? '');

        if (empty($albumIds) || !$albumName) {
            $response['error']   = true;
            $response['message'] = 'album_ids and album_name required';
        } else {
            require_once __DIR__ . '/../../src/TagEditor.php';

            // Verify ownership
            $ph = implode(',', array_fill(0, count($albumIds), '?'));
            $stmt = $conn->prepare("
                SELECT COUNT(*) FROM albums al
                JOIN artists ar ON al.artist_id = ar.id
                WHERE al.id IN ($ph) AND ar.user = ?
            ");
            $stmt->execute([...$albumIds, $user]);
            if ((int)$stmt->fetchColumn() !== count($albumIds)) {
                $response['error']   = true;
                $response['message'] = 'Access denied';
            } else {
                // Find or create compilation artist
                $stmt = $conn->prepare("SELECT id FROM artists WHERE name = ? AND user = ?");
                $stmt->execute([$artistName, $user]);
                $variousArtistId = (int)($stmt->fetchColumn() ?: 0);
                if (!$variousArtistId) {
                    $conn->prepare("INSERT INTO artists (name, user) VALUES (?, ?)")->execute([$artistName, $user]);
                    $variousArtistId = (int)$conn->lastInsertId();
                }

                // Find or create compilation album
                $stmt = $conn->prepare("SELECT id FROM albums WHERE artist_id = ? AND LOWER(name) = LOWER(?)");
                $stmt->execute([$variousArtistId, $albumName]);
                $compilationAlbumId = (int)($stmt->fetchColumn() ?: 0);
                if (!$compilationAlbumId) {
                    $conn->prepare("INSERT INTO albums (artist_id, name, is_compilation) VALUES (?, ?, 1)")
                         ->execute([$variousArtistId, $albumName]);
                    $compilationAlbumId = (int)$conn->lastInsertId();
                } else {
                    $conn->prepare("UPDATE albums SET is_compilation = 1 WHERE id = ?")->execute([$compilationAlbumId]);
                }

                // Move all songs to compilation album
                $toDelete = array_values(array_filter($albumIds, fn($id) => $id !== $compilationAlbumId));
                if (!empty($toDelete)) {
                    $phDel = implode(',', array_fill(0, count($toDelete), '?'));
                    $conn->prepare("UPDATE songs SET album_id = ? WHERE album_id IN ($phDel)")
                         ->execute([$compilationAlbumId, ...$toDelete]);
                    $conn->prepare("DELETE FROM albums WHERE id IN ($phDel)")->execute($toDelete);
                }

                // Update ID3 tags
                $editor = new TagEditor();
                $stmt   = $conn->prepare("SELECT id FROM songs WHERE album_id = ?");
                $stmt->execute([$compilationAlbumId]);
                $songIds = $stmt->fetchAll(PDO::FETCH_COLUMN);

                $tagsUpdated = 0; $tagsFailed = 0;
                foreach ($songIds as $songId) {
                    if ($editor->updateSongTags((int)$songId, [
                        'album'        => $albumName,
                        'album_artist' => $artistName,
                    ])) {
                        $tagsUpdated++;
                    } else {
                        $tagsFailed++;
                    }
                }

                // Clean up empty artists
                $conn->prepare("
                    DELETE FROM artists WHERE user = ?
                    AND id NOT IN (SELECT DISTINCT artist_id FROM albums)
                ")->execute([$user]);

                $response['data'] = [
                    'compilation_album_id' => $compilationAlbumId,
                    'artist'       => $artistName,
                    'name'         => $albumName,
                    'songs'        => count($songIds),
                    'tags_updated' => $tagsUpdated,
                    'tags_failed'  => $tagsFailed,
                ];
            }
        }

    } elseif ($action === 'delete_songs') {
        // Delete one or more songs from filesystem + DB
        // Expects JSON body: { "song_ids": [1, 2, ...] }
        $body    = json_decode(file_get_contents('php://input'), true);
        $songIds = array_map('intval', $body['song_ids'] ?? []);

        if (empty($songIds)) {
            $response['error']   = true;
            $response['message'] = 'song_ids required';
        } else {
            require_once __DIR__ . '/../../src/Storage/StorageFactory.php';

            $deleted  = 0;
            $failed   = [];
            $pathBase = null;

            foreach ($songIds as $sid) {
                // Fetch song info — verify it belongs to this user
                $stmt = $conn->prepare("
                    SELECT s.id, s.file_path, ar.user
                    FROM songs s
                    JOIN albums al ON s.album_id = al.id
                    JOIN artists ar ON al.artist_id = ar.id
                    WHERE s.id = ? AND ar.user = ?
                ");
                $stmt->execute([$sid, $user]);
                $song = $stmt->fetch(PDO::FETCH_ASSOC);

                if (!$song) {
                    $failed[] = $sid;
                    continue;
                }

                // Delete file from storage
                $storage  = StorageFactory::forUser($song['user']);
                $absPath  = $storage->getPathBase() . '/' . ltrim($song['file_path'], '/');
                $storage->deleteFile($absPath);

                // Delete from DB
                $conn->prepare("DELETE FROM songs WHERE id = ?")->execute([$sid]);
                $deleted++;
            }

            // Clean up albums/artists that are now empty (for this user)
            $conn->prepare("
                DELETE al FROM albums al
                JOIN artists ar ON al.artist_id = ar.id
                WHERE ar.user = ?
                AND al.id NOT IN (SELECT DISTINCT album_id FROM songs)
            ")->execute([$user]);

            $conn->prepare("
                DELETE FROM artists
                WHERE user = ?
                AND id NOT IN (SELECT DISTINCT artist_id FROM albums)
            ")->execute([$user]);

            $response['data'] = ['deleted' => $deleted, 'failed' => $failed];
        }

    } elseif ($action === 'delete_album') {
        // Delete an album: all its song files + the album folder (if empty) + DB records
        $albumId = (int)($_POST['album_id'] ?? $_GET['album_id'] ?? 0);

        if (!$albumId) {
            $response['error']   = true;
            $response['message'] = 'album_id required';
        } else {
            require_once __DIR__ . '/../../src/Storage/StorageFactory.php';

            // Verify ownership
            $stmt = $conn->prepare("
                SELECT al.id, al.name, ar.user, ar.name AS artist_name
                FROM albums al
                JOIN artists ar ON al.artist_id = ar.id
                WHERE al.id = ? AND ar.user = ?
            ");
            $stmt->execute([$albumId, $user]);
            $album = $stmt->fetch(PDO::FETCH_ASSOC);

            if (!$album) {
                $response['error']   = true;
                $response['message'] = 'Album not found or access denied';
            } else {
                $storage = StorageFactory::forUser($album['user']);

                // Get all songs in album
                $stmt = $conn->prepare("SELECT id, file_path FROM songs WHERE album_id = ?");
                $stmt->execute([$albumId]);
                $songs = $stmt->fetchAll(PDO::FETCH_ASSOC);

                $deletedFiles = 0;
                foreach ($songs as $song) {
                    $absPath = $storage->getPathBase() . '/' . ltrim($song['file_path'], '/');
                    if ($storage->deleteFile($absPath)) {
                        $deletedFiles++;
                    }
                }

                // Try to remove the album directory if it is now empty
                $albumDir = $storage->getMusicRoot() . '/' . $album['artist_name'] . '/' . $album['name'];
                $storage->deleteDir($albumDir);

                // Delete songs + album from DB
                $conn->prepare("DELETE FROM songs WHERE album_id = ?")->execute([$albumId]);
                $conn->prepare("DELETE FROM albums WHERE id = ?")->execute([$albumId]);

                // Delete artist if it now has no albums
                $conn->prepare("
                    DELETE FROM artists
                    WHERE user = ?
                    AND id NOT IN (SELECT DISTINCT artist_id FROM albums)
                ")->execute([$user]);

                $response['data'] = [
                    'deleted_files' => $deletedFiles,
                    'total_songs'   => count($songs),
                ];
            }
        }

    } elseif ($action === 'detect_artist_duplicates') {
        // PHP-based fuzzy similarity — compares all pairs of artist names
        $stmt = $conn->prepare("SELECT id, name FROM artists WHERE user = ? ORDER BY name ASC");
        $stmt->execute([$user]);
        $artists = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $groups = [];
        $grouped = [];
        for ($i = 0; $i < count($artists); $i++) {
            if (isset($grouped[$i])) continue;
            $group = [$artists[$i]];
            for ($j = $i + 1; $j < count($artists); $j++) {
                if (isset($grouped[$j])) continue;
                similar_text(
                    mb_strtolower($artists[$i]['name']),
                    mb_strtolower($artists[$j]['name']),
                    $pct
                );
                if ($pct >= 70) {
                    $group[] = $artists[$j];
                    $grouped[$j] = true;
                }
            }
            if (count($group) >= 2) {
                $ids = array_column($group, 'id');
                // Count songs per group
                $ph  = implode(',', array_fill(0, count($ids), '?'));
                $sst = $conn->prepare("SELECT COUNT(*) FROM songs s JOIN albums al ON s.album_id = al.id WHERE al.artist_id IN ($ph)");
                $sst->execute($ids);
                $groups[] = [
                    'artists'     => $group,
                    'total_songs' => (int)$sst->fetchColumn(),
                ];
            }
        }
        $response['data'] = ['groups' => $groups, 'total_groups' => count($groups)];

    } elseif ($action === 'rename_artist') {
        $artistId = (int)($_POST['artist_id'] ?? 0);
        $newName  = trim($_POST['name'] ?? '');
        if (!$artistId || $newName === '') {
            $response['error']   = true;
            $response['message'] = 'artist_id and name are required';
        } else {
            $stmt = $conn->prepare("SELECT id FROM artists WHERE id = ? AND user = ?");
            $stmt->execute([$artistId, $user]);
            if (!$stmt->fetch()) {
                $response['error']   = true;
                $response['message'] = 'Artist not found or permission denied';
            } else {
                $conn->prepare("UPDATE artists SET name = ? WHERE id = ?")->execute([$newName, $artistId]);

                // Update ID3 artist tag on all songs
                $stmt = $conn->prepare("SELECT s.id FROM songs s JOIN albums al ON s.album_id = al.id WHERE al.artist_id = ?");
                $stmt->execute([$artistId]);
                $songIds = $stmt->fetchAll(PDO::FETCH_COLUMN);

                $tagsUpdated = 0; $tagsFailed = 0;
                if (!empty($songIds)) {
                    require_once __DIR__ . '/../../src/TagEditor.php';
                    $tagEditor = new TagEditor();
                    foreach ($songIds as $sid) {
                        try {
                            $tagEditor->updateSongTags((int)$sid, ['artist' => $newName], true)
                                ? $tagsUpdated++ : $tagsFailed++;
                        } catch (Throwable $e) { $tagsFailed++; }
                    }
                }

                $response['data'] = ['id' => $artistId, 'name' => $newName, 'tags_updated' => $tagsUpdated];
            }
        }

    } elseif ($action === 'merge_artists') {
        $sourceIds = array_values(array_filter(array_map('intval', (array)($_POST['source_ids'] ?? []))));
        $newName   = trim($_POST['new_name'] ?? '');
        if (count($sourceIds) < 2 || $newName === '') {
            $response['error']   = true;
            $response['message'] = 'At least 2 source_ids and new_name are required';
        } else {
            $ph   = implode(',', array_fill(0, count($sourceIds), '?'));
            $stmt = $conn->prepare("SELECT id FROM artists WHERE id IN ($ph) AND user = ?");
            $stmt->execute([...$sourceIds, $user]);
            $validIds = $stmt->fetchAll(PDO::FETCH_COLUMN);
            if (count($validIds) !== count($sourceIds)) {
                $response['error']   = true;
                $response['message'] = 'Some artists not found or permission denied';
            } else {
                $targetId = $sourceIds[0];
                $toDelete = array_slice($sourceIds, 1);
                $delPh    = implode(',', array_fill(0, count($toDelete), '?'));

                // Reassign all albums from duplicates to target
                $conn->prepare("UPDATE albums SET artist_id = ? WHERE artist_id IN ($delPh)")
                     ->execute([$targetId, ...$toDelete]);

                // Rename target artist
                $conn->prepare("UPDATE artists SET name = ? WHERE id = ?")->execute([$newName, $targetId]);

                // Delete now-empty artists
                $conn->prepare("DELETE FROM artists WHERE id IN ($delPh)")->execute($toDelete);

                // Collect all songs of the target artist to update ID3 tags
                $stmt = $conn->prepare("SELECT s.id FROM songs s JOIN albums al ON s.album_id = al.id WHERE al.artist_id = ?");
                $stmt->execute([$targetId]);
                $songIds = $stmt->fetchAll(PDO::FETCH_COLUMN);

                $tagsUpdated = 0; $tagsFailed = 0;
                if (!empty($songIds)) {
                    require_once __DIR__ . '/../../src/TagEditor.php';
                    $tagEditor = new TagEditor();
                    foreach ($songIds as $sid) {
                        try {
                            $ok = $tagEditor->updateSongTags((int)$sid, ['artist' => $newName], true);
                            $ok ? $tagsUpdated++ : $tagsFailed++;
                        } catch (Throwable $e) { $tagsFailed++; }
                    }
                }

                $response['data'] = [
                    'target_id'    => $targetId,
                    'name'         => $newName,
                    'merged'       => count($toDelete),
                    'songs_total'  => count($songIds),
                    'tags_updated' => $tagsUpdated,
                    'tags_failed'  => $tagsFailed,
                ];
            }
        }

    } elseif ($action === 'reset_stats') {
        // Efface tout l'historique d'écoute et les compteurs de l'utilisateur.
        $conn->prepare("DELETE FROM play_history WHERE user = ?")->execute([$user]);
        $conn->prepare("
            DELETE ss FROM song_stats ss
            JOIN songs s   ON ss.song_id = s.id
            JOIN albums al ON s.album_id = al.id
            JOIN artists a ON al.artist_id = a.id
            WHERE a.user = ?
        ")->execute([$user]);
        $response['data'] = ['reset' => true];

    } elseif ($action === 'delete_artist') {
        $artistId = (int)($_POST['artist_id'] ?? $_GET['artist_id'] ?? 0);
        if (!$artistId) {
            $response['error']   = true;
            $response['message'] = 'artist_id required';
        } else {
            require_once __DIR__ . '/../../src/Storage/StorageFactory.php';
            $stmt = $conn->prepare("SELECT id, name, user FROM artists WHERE id = ? AND user = ?");
            $stmt->execute([$artistId, $user]);
            $artist = $stmt->fetch(PDO::FETCH_ASSOC);
            if (!$artist) {
                $response['error']   = true;
                $response['message'] = 'Artist not found or access denied';
            } else {
                $storage = StorageFactory::forUser($artist['user']);

                // Get all songs for this artist
                $stmt = $conn->prepare("
                    SELECT s.id, s.file_path, al.id AS album_id
                    FROM songs s
                    JOIN albums al ON s.album_id = al.id
                    WHERE al.artist_id = ?
                ");
                $stmt->execute([$artistId]);
                $songs = $stmt->fetchAll(PDO::FETCH_ASSOC);

                $deletedFiles = 0;
                foreach ($songs as $song) {
                    $absPath = $storage->getPathBase() . '/' . ltrim($song['file_path'], '/');
                    if ($storage->deleteFile($absPath)) $deletedFiles++;
                }

                // Try to remove album dirs and artist dir
                $stmt = $conn->prepare("SELECT id, name FROM albums WHERE artist_id = ?");
                $stmt->execute([$artistId]);
                $albums = $stmt->fetchAll(PDO::FETCH_ASSOC);
                foreach ($albums as $album) {
                    $albumDir = $storage->getPathBase() . '/' . $artist['name'] . '/' . $album['name'];
                    $storage->deleteDir($albumDir);
                }
                $artistDir = $storage->getPathBase() . '/' . $artist['name'];
                $storage->deleteDir($artistDir);

                // DB cleanup
                $albumIds = array_column($albums, 'id');
                if (!empty($albumIds)) {
                    $ph = implode(',', array_fill(0, count($albumIds), '?'));
                    $conn->prepare("DELETE FROM songs WHERE album_id IN ($ph)")->execute($albumIds);
                    $conn->prepare("DELETE FROM albums WHERE id IN ($ph)")->execute($albumIds);
                }
                $conn->prepare("DELETE FROM artists WHERE id = ?")->execute([$artistId]);

                $response['data'] = ['deleted_files' => $deletedFiles, 'total_songs' => count($songs)];
            }
        }

    } else {
        $response['error'] = true;
        $response['message'] = 'Unknown action';
    }

    $db->close();

    echo json_encode($response);

} catch (Exception $e) {
    error_log("Error in library.php: " . $e->getMessage());

    echo json_encode([
        'error' => true,
        'message' => $e->getMessage(),
        'data' => null
    ]);
}
