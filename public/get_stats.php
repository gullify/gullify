<?php
/**
 * Gullify - Statistics API
 * Returns comprehensive listening statistics for the authenticated user.
 */
header('Content-Type: application/json');

require_once __DIR__ . '/../src/AppConfig.php';
require_once __DIR__ . '/../src/Database.php';

// ── Helpers ──────────────────────────────────────────────────────────────────

function formatDuration(int $seconds): string {
    if ($seconds < 60) return "{$seconds}s";
    if ($seconds < 3600) return floor($seconds / 60) . 'min';
    $h = floor($seconds / 3600);
    $m = floor(($seconds % 3600) / 60);
    return $m > 0 ? "{$h}h {$m}min" : "{$h}h";
}

function genreColorPalette(): array {
    return [
        '#6C5CE7','#00B894','#0984E3','#FDCB6E','#E17055',
        '#A29BFE','#55EFC4','#74B9FF','#FD79A8','#D63031',
        '#00CEC9','#E84393','#636E72','#B2BEC3','#2D3436',
    ];
}

// ── Main ─────────────────────────────────────────────────────────────────────

$user = $_GET['user'] ?? '';
if (empty($user)) {
    echo json_encode(['success' => false, 'error' => 'Paramètre user manquant']);
    exit;
}

try {
    $db   = new Database();
    $conn = $db->getConnection();

    // ── 1. General stats ─────────────────────────────────────────────────────
    $stmt = $conn->prepare("
        SELECT
            COUNT(*)                             AS total_plays,
            COALESCE(SUM(ph.play_duration), 0)   AS total_listen_time,
            COUNT(DISTINCT ph.song_id)           AS unique_songs_played,
            COALESCE(SUM(ph.completed = 1), 0)   AS completed_plays,
            COALESCE(SUM(ph.completed = 0), 0)   AS skipped_plays,
            COALESCE(AVG(ph.play_duration), 0)   AS avg_duration
        FROM play_history ph
        JOIN songs s   ON ph.song_id = s.id
        JOIN albums al ON s.album_id = al.id
        JOIN artists a ON al.artist_id = a.id
        WHERE a.user = ?
    ");
    $stmt->execute([$user]);
    $gen = $stmt->fetch();

    $totalPlays     = (int)($gen['total_plays'] ?? 0);
    $totalTime      = (int)($gen['total_listen_time'] ?? 0);
    $uniqueSongs    = (int)($gen['unique_songs_played'] ?? 0);
    $completed      = (int)($gen['completed_plays'] ?? 0);
    $skipped        = (int)($gen['skipped_plays'] ?? 0);
    $avgDur         = (int)($gen['avg_duration'] ?? 0);
    $completionRate = $totalPlays > 0 ? round($completed / $totalPlays * 100) : 0;

    $general = [
        'totalPlays'               => $totalPlays,
        'totalListenTime'          => $totalTime,
        'totalListenTimeFormatted' => formatDuration($totalTime),
        'uniqueSongsPlayed'        => $uniqueSongs,
        'completionRate'           => $completionRate,
        'totalSkips'               => $skipped,
        'avgDuration'              => $avgDur,
        'avgDurationFormatted'     => formatDuration($avgDur),
    ];

    // ── 2. Top songs (20) ────────────────────────────────────────────────────
    $stmt = $conn->prepare("
        SELECT
            s.id, s.title, s.album_id,
            al.name  AS album_name,
            a.id     AS artist_id,
            a.name   AS artist_name,
            ss.play_count
        FROM song_stats ss
        JOIN songs s   ON ss.song_id = s.id
        JOIN albums al ON s.album_id = al.id
        JOIN artists a ON al.artist_id = a.id
        WHERE a.user = ? AND ss.play_count > 0
        ORDER BY ss.play_count DESC
        LIMIT 20
    ");
    $stmt->execute([$user]);
    $topSongs = [];
    while ($r = $stmt->fetch()) {
        $topSongs[] = [
            'id'          => (int)$r['id'],
            'title'       => $r['title'],
            'album_id'    => (int)$r['album_id'],
            'album_name'  => $r['album_name'],
            'artist_id'   => (int)$r['artist_id'],
            'artist_name' => $r['artist_name'],
            'play_count'  => (int)$r['play_count'],
            'artworkUrl'  => 'serve_image.php?album_id=' . $r['album_id'],
        ];
    }

    // ── 3. Top artists (12) ──────────────────────────────────────────────────
    $stmt = $conn->prepare("
        SELECT a.id, a.name, COUNT(ph.id) AS play_count
        FROM play_history ph
        JOIN songs s   ON ph.song_id = s.id
        JOIN albums al ON s.album_id = al.id
        JOIN artists a ON al.artist_id = a.id
        WHERE a.user = ?
        GROUP BY a.id, a.name
        ORDER BY play_count DESC
        LIMIT 12
    ");
    $stmt->execute([$user]);
    $topArtists = [];
    while ($r = $stmt->fetch()) {
        $topArtists[] = [
            'id'         => (int)$r['id'],
            'name'       => $r['name'],
            'play_count' => (int)$r['play_count'],
            'imageUrl'   => 'serve_image.php?artist_id=' . $r['id'],
        ];
    }

    // ── 4. Top albums (12) ───────────────────────────────────────────────────
    $stmt = $conn->prepare("
        SELECT al.id, al.name, a.id AS artist_id, a.name AS artist_name,
               COUNT(ph.id) AS play_count
        FROM play_history ph
        JOIN songs s   ON ph.song_id = s.id
        JOIN albums al ON s.album_id = al.id
        JOIN artists a ON al.artist_id = a.id
        WHERE a.user = ?
        GROUP BY al.id, al.name, a.id, a.name
        ORDER BY play_count DESC
        LIMIT 12
    ");
    $stmt->execute([$user]);
    $topAlbums = [];
    while ($r = $stmt->fetch()) {
        $topAlbums[] = [
            'id'          => (int)$r['id'],
            'name'        => $r['name'],
            'artist_id'   => (int)$r['artist_id'],
            'artist_name' => $r['artist_name'],
            'play_count'  => (int)$r['play_count'],
            'artworkUrl'  => 'serve_image.php?album_id=' . $r['id'],
        ];
    }

    // ── 5. Daily plays — last 30 days ────────────────────────────────────────
    $stmt = $conn->prepare("
        SELECT DATE(ph.played_at) AS day, COUNT(*) AS plays
        FROM play_history ph
        JOIN songs s   ON ph.song_id = s.id
        JOIN albums al ON s.album_id = al.id
        JOIN artists a ON al.artist_id = a.id
        WHERE a.user = ?
          AND ph.played_at >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
        GROUP BY DATE(ph.played_at)
        ORDER BY day ASC
    ");
    $stmt->execute([$user]);
    $dailyRaw = [];
    while ($r = $stmt->fetch()) $dailyRaw[$r['day']] = (int)$r['plays'];

    $dailyLabels = [];
    $dailyData   = [];
    for ($i = 29; $i >= 0; $i--) {
        $day           = date('Y-m-d', strtotime("-{$i} days"));
        $dailyLabels[] = date('d/m', strtotime($day));
        $dailyData[]   = $dailyRaw[$day] ?? 0;
    }
    $dailyPlaysChart = ['labels' => $dailyLabels, 'data' => $dailyData];

    // ── 6. Hourly distribution ────────────────────────────────────────────────
    $stmt = $conn->prepare("
        SELECT HOUR(ph.played_at) AS hour, COUNT(*) AS plays
        FROM play_history ph
        JOIN songs s   ON ph.song_id = s.id
        JOIN albums al ON s.album_id = al.id
        JOIN artists a ON al.artist_id = a.id
        WHERE a.user = ?
        GROUP BY HOUR(ph.played_at)
    ");
    $stmt->execute([$user]);
    $hourlyRaw = [];
    while ($r = $stmt->fetch()) $hourlyRaw[(int)$r['hour']] = (int)$r['plays'];

    $hourlyLabels = [];
    $hourlyData   = [];
    for ($h = 0; $h < 24; $h++) {
        $hourlyLabels[] = sprintf('%02dh', $h);
        $hourlyData[]   = $hourlyRaw[$h] ?? 0;
    }
    $hourlyChart = ['labels' => $hourlyLabels, 'data' => $hourlyData];

    // ── 7. Weekday distribution ───────────────────────────────────────────────
    $stmt = $conn->prepare("
        SELECT DAYOFWEEK(ph.played_at) AS dow, COUNT(*) AS plays
        FROM play_history ph
        JOIN songs s   ON ph.song_id = s.id
        JOIN albums al ON s.album_id = al.id
        JOIN artists a ON al.artist_id = a.id
        WHERE a.user = ?
        GROUP BY DAYOFWEEK(ph.played_at)
    ");
    $stmt->execute([$user]);
    $dowRaw = [];
    while ($r = $stmt->fetch()) $dowRaw[(int)$r['dow']] = (int)$r['plays'];

    // MySQL DAYOFWEEK: 1=Sun … 7=Sat → Mon–Sun
    $dowLabels = ['Lun','Mar','Mer','Jeu','Ven','Sam','Dim'];
    $dowMap    = [2, 3, 4, 5, 6, 7, 1];
    $dowData   = array_map(fn($d) => $dowRaw[$d] ?? 0, $dowMap);
    $weekdayChart = ['labels' => $dowLabels, 'data' => $dowData];

    $maxDowVal     = max($dowData);
    $maxDowIdx     = array_search($maxDowVal, $dowData);
    $mostActiveDay = $maxDowVal > 0 ? $dowLabels[$maxDowIdx] : null;

    // ── 8. Genre chart ────────────────────────────────────────────────────────
    $stmt = $conn->prepare("
        SELECT
            COALESCE(NULLIF(al.genre,''), NULLIF(a.genre,''), 'Inconnu') AS genre,
            COUNT(DISTINCT a.id) AS artist_count
        FROM artists a
        LEFT JOIN albums al ON al.artist_id = a.id
        WHERE a.user = ?
        GROUP BY genre
        HAVING genre != 'Inconnu'
        ORDER BY artist_count DESC
        LIMIT 14
    ");
    $stmt->execute([$user]);
    $palette       = genreColorPalette();
    $genreLabels   = [];
    $genreData     = [];
    $genreColorsOut= [];
    $idx = 0;
    while ($r = $stmt->fetch()) {
        $genreLabels[]     = $r['genre'];
        $genreData[]       = (int)$r['artist_count'];
        $genreColorsOut[]  = $palette[$idx % count($palette)];
        $idx++;
    }
    $genreChart = ['labels' => $genreLabels, 'data' => $genreData, 'colors' => $genreColorsOut];

    // Genre coverage
    $stmt = $conn->prepare("SELECT COUNT(*) FROM artists WHERE user = ?");
    $stmt->execute([$user]);
    $totalArtists = (int)$stmt->fetchColumn();

    $stmt = $conn->prepare("
        SELECT COUNT(DISTINCT a.id)
        FROM artists a
        LEFT JOIN albums al ON al.artist_id = a.id
        WHERE a.user = ?
          AND (NULLIF(al.genre,'') IS NOT NULL OR NULLIF(a.genre,'') IS NOT NULL)
    ");
    $stmt->execute([$user]);
    $artistsWithGenre = (int)$stmt->fetchColumn();

    $genreCoverage = [
        'totalArtists'     => $totalArtists,
        'artistsWithGenre' => $artistsWithGenre,
        'percent'          => $totalArtists > 0 ? round($artistsWithGenre / $totalArtists * 100) : 0,
    ];

    // ── 9. Library growth by month (last 12 months) ───────────────────────────
    $growthLabels  = [];
    $growthSongs   = [];
    $growthAlbums  = [];
    $growthArtists = [];
    try {
        $stmt = $conn->prepare("
            SELECT
                DATE_FORMAT(s.created_at, '%Y-%m') AS month,
                COUNT(DISTINCT s.id)               AS songs,
                COUNT(DISTINCT s.album_id)         AS albums,
                COUNT(DISTINCT al.artist_id)       AS artists
            FROM songs s
            JOIN albums al ON s.album_id = al.id
            JOIN artists a ON al.artist_id = a.id
            WHERE a.user = ?
              AND s.created_at >= DATE_SUB(NOW(), INTERVAL 12 MONTH)
            GROUP BY month
            ORDER BY month ASC
        ");
        $stmt->execute([$user]);
        $growthRaw = $stmt->fetchAll();
        if (count($growthRaw) > 1) {
            foreach ($growthRaw as $r) {
                $d               = new DateTime($r['month'] . '-01');
                $growthLabels[]  = $d->format('M Y');
                $growthSongs[]   = (int)$r['songs'];
                $growthAlbums[]  = (int)$r['albums'];
                $growthArtists[] = (int)$r['artists'];
            }
        }
    } catch (Exception $e) {
        // created_at may not exist on all installations — skip silently
    }
    $libraryGrowth = [
        'labels'  => $growthLabels,
        'songs'   => $growthSongs,
        'albums'  => $growthAlbums,
        'artists' => $growthArtists,
    ];

    // ── 10. Recent plays (20) ────────────────────────────────────────────────
    $stmt = $conn->prepare("
        SELECT
            s.id, s.title, s.album_id,
            al.name AS album_name,
            a.name  AS artist_name,
            ph.played_at,
            ph.play_duration,
            ph.completed
        FROM play_history ph
        JOIN songs s   ON ph.song_id = s.id
        JOIN albums al ON s.album_id = al.id
        JOIN artists a ON al.artist_id = a.id
        WHERE a.user = ?
        ORDER BY ph.played_at DESC
        LIMIT 20
    ");
    $stmt->execute([$user]);
    $recentPlays = [];
    while ($r = $stmt->fetch()) {
        $recentPlays[] = [
            'id'           => (int)$r['id'],
            'title'        => $r['title'],
            'album_id'     => (int)$r['album_id'],
            'album_name'   => $r['album_name'],
            'artist_name'  => $r['artist_name'],
            'artworkUrl'   => 'serve_image.php?album_id=' . $r['album_id'],
            'played_at'    => $r['played_at'],
            'played_at_iso'=> $r['played_at'],
            'duration'     => (int)$r['play_duration'],
            'completed'    => (bool)$r['completed'],
        ];
    }

    // ── Response ──────────────────────────────────────────────────────────────
    echo json_encode([
        'success' => true,
        'data'    => [
            'general'         => $general,
            'topSongs'        => $topSongs,
            'topArtists'      => $topArtists,
            'topAlbums'       => $topAlbums,
            'dailyPlaysChart' => $dailyPlaysChart,
            'hourlyChart'     => $hourlyChart,
            'weekdayChart'    => $weekdayChart,
            'libraryGrowth'   => $libraryGrowth,
            'genreChart'      => $genreChart,
            'genreCoverage'   => $genreCoverage,
            'insights'        => ['mostActiveDay' => $mostActiveDay],
            'recentPlays'     => $recentPlays,
        ],
    ], JSON_UNESCAPED_UNICODE);

} catch (Exception $e) {
    echo json_encode(['success' => false, 'error' => $e->getMessage()]);
}
