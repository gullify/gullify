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
require_once __DIR__ . '/../../src/PathHelper.php';

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
        $response['data'] = [
            'artist' => [
                'id' => $artist['id'],
                'name' => $artist['name'],
                'imageUrl' => 'serve_image.php?artist_id=' . $artist['id'],
                'genre' => $artist['genre'] ?? null
            ],
            'albums' => $albums,
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
            SELECT s.*, ta.id AS track_artist_id, ta.name AS track_artist_name
            FROM songs s
            LEFT JOIN artists ta ON s.artist_id = ta.id
            WHERE s.album_id = ?
            ORDER BY s.track_number ASC, s.title ASC
        ');
        $stmt->execute([$albumId]);

        $songs = [];
        while ($row = $stmt->fetch()) {
            $songs[] = [
                'id' => $row['id'],
                'title' => $row['title'],
                'trackNumber' => (int)$row['track_number'],
                'duration' => (int)$row['duration'],
                'filePath' => $row['file_path'],
                'albumId' => $row['album_id'],
                'artworkUrl' => albumArtworkUrl((int)$row['album_id']),
                'artistId' => $row['track_artist_id'] ? (int)$row['track_artist_id'] : null,
                'artistName' => $row['track_artist_name'] ?: null,
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

    } elseif ($action === 'search') {
        $query = isset($_GET['q']) ? $_GET['q'] : '';
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
                a.name as artist_name,
                a.id as artist_id
            FROM songs s
            JOIN albums al ON s.album_id = al.id
            JOIN artists a ON al.artist_id = a.id
            WHERE a.user = ?
            AND (
                s.title LIKE ? OR
                a.name LIKE ? OR
                al.name LIKE ?
            )
            ORDER BY a.name ASC, al.name ASC, s.track_number ASC
            LIMIT 100
        ');
        $stmt->execute([$user, $searchTerm, $searchTerm, $searchTerm]);

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
                'artistId' => $row['artist_id'],
                'artistName' => $row['artist_name']
            ];
        }
        $response['data'] = ['songs' => $songs];

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

        $genres = [];
        while ($row = $stmt->fetch()) {
            $genres[] = [
                'name' => $row['genre'],
                'artistCount' => (int)$row['artist_count'],
                'albumCount' => (int)$row['album_count']
            ];
        }
        $response['data'] = ['genres' => $genres];

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
                   (al.artwork IS NOT NULL AND al.artwork != "") AS has_artwork
            FROM favorites f
            JOIN songs   s  ON f.song_id    = s.id
            JOIN albums  al ON s.album_id   = al.id
            JOIN artists a  ON al.artist_id = a.id
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
                'artist'     => $row['artist_name'],
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
        $limit  = max(1, min(200, (int)($_GET['limit'] ?? 48)));
        $offset = max(0, (int)($_GET['offset'] ?? 0));
        $sort   = in_array($_GET['sort'] ?? '', ['name', 'artist', 'year', 'recent']) ? $_GET['sort'] : 'name';
        $search = trim($_GET['search'] ?? '');

        $sortClause = match($sort) {
            'artist' => 'a.name ASC, al.name ASC',
            'year'   => 'al.year DESC, al.name ASC',
            'recent' => 'al.created_at DESC, al.name ASC',
            default  => 'al.name ASC',
        };

        $params    = [$user];
        $searchSql = '';
        if ($search !== '') {
            $searchSql  = ' AND (al.name LIKE ? OR a.name LIKE ?)';
            $params[]   = "%$search%";
            $params[]   = "%$search%";
        }

        $countStmt = $conn->prepare("
            SELECT COUNT(*)
            FROM albums al
            JOIN artists a ON al.artist_id = a.id
            WHERE a.user = ? $searchSql
        ");
        $countStmt->execute($params);
        $total = (int)$countStmt->fetchColumn();

        $params[] = $limit;
        $params[] = $offset;
        $stmt = $conn->prepare("
            SELECT al.id, al.name, al.year,
                   a.id AS artist_id, a.name AS artist_name,
                   COUNT(s.id) AS song_count
            FROM albums al
            JOIN artists a ON al.artist_id = a.id
            LEFT JOIN songs s ON s.album_id = al.id
            WHERE a.user = ? $searchSql
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
            ];
        }

        $response['data'] = [
            'albums' => $albums,
            'total'  => $total,
            'offset' => $offset,
            'limit'  => $limit,
        ];

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
