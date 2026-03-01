<?php
/**
 * Gullify - Radio API
 * Get random songs and track play statistics
 * Migrated from radio_api_mysql.php
 */

header('Content-Type: application/json');

require_once __DIR__ . '/../../src/AppConfig.php';
require_once __DIR__ . '/../../src/Database.php';
require_once __DIR__ . '/../../src/PathHelper.php';

try {
    $db = new Database();
    $conn = $db->getConnection();

    $action = $_GET['action'] ?? 'get_random';

    if ($action === 'get_random') {
        // Get parameters
        $limit = isset($_GET['limit']) ? intval($_GET['limit']) : 20;
        $limit = min($limit, 100); // Max 100 songs at a time
        $user = $_GET['user'] ?? null;
        $genre = $_GET['genre'] ?? null;

        // Get recently played song IDs (last 30 plays only for better performance)
        $stmt = $conn->query('SELECT song_id FROM play_history ORDER BY played_at DESC LIMIT 30');
        $recentlyPlayed = array_unique(array_column($stmt->fetchAll(), 'song_id'));

        // Use optimized random selection method instead of ORDER BY RAND()
        $countSql = "
            SELECT COUNT(*) as total
            FROM songs s
            JOIN albums al ON s.album_id = al.id
            JOIN artists a ON al.artist_id = a.id
            WHERE 1=1
        ";

        $countParams = [];
        if ($user) {
            $countSql .= " AND a.user = ?";
            $countParams[] = $user;
        }
        if ($genre) {
            $countSql .= " AND (al.genre = ? OR a.genre = ?)";
            $countParams[] = $genre;
            $countParams[] = $genre;
        }

        $stmt = $conn->prepare($countSql);
        $stmt->execute($countParams);
        $totalSongs = $stmt->fetch()['total'];

        if ($totalSongs == 0) {
            echo json_encode([
                'success' => true,
                'songs' => [],
                'count' => 0
            ]);
            exit;
        }

        // Select random songs with weighted preference for less-played songs
        $sql = "
            SELECT
                s.id,
                s.title,
                s.track_number,
                s.duration,
                s.file_path,
                al.id as album_id,
                al.name as album,
                a.id as artist_id,
                a.name as artist,
                COALESCE(ss.play_count, 0) as play_count
            FROM songs s
            JOIN albums al ON s.album_id = al.id
            JOIN artists a ON al.artist_id = a.id
            LEFT JOIN song_stats ss ON s.id = ss.song_id
            WHERE 1=1
        ";

        $params = [];

        if ($user) {
            $sql .= " AND a.user = ?";
            $params[] = $user;
        }

        if ($genre) {
            $sql .= " AND (al.genre = ? OR a.genre = ?)";
            $params[] = $genre;
            $params[] = $genre;
        }

        if (!empty($recentlyPlayed)) {
            $placeholders = implode(',', array_fill(0, count($recentlyPlayed), '?'));
            $sql .= " AND s.id NOT IN ($placeholders)";
            $params = array_merge($params, $recentlyPlayed);
        }

        $sql .= " ORDER BY (RAND() / (1 + COALESCE(ss.play_count, 0))) ASC LIMIT ?";
        $params[] = $limit;

        $stmt = $conn->prepare($sql);
        $stmt->execute($params);

        $pathHelper = new PathHelper();
        $userMusicPath = $pathHelper->getUserPath($user);

        $songs = [];
        while ($row = $stmt->fetch()) {
            $songs[] = [
                'id' => $row['id'],
                'title' => $row['title'],
                'trackNumber' => (int)$row['track_number'],
                'duration' => (int)$row['duration'],
                'filePath' => $row['file_path'],
                'albumId' => $row['album_id'],
                'album' => $row['album'],
                'artworkUrl' => 'serve_image.php?album_id=' . $row['album_id'],
                'artistId' => $row['artist_id'],
                'artist' => $row['artist']
            ];
        }

        echo json_encode([
            'success' => true,
            'songs' => $songs,
            'count' => count($songs)
        ]);

    } elseif ($action === 'track_play' || $action === 'record_play') {
        // Track a song play
        $songId = $_POST['song_id'] ?? null;
        $user = $_POST['user'] ?? null;
        $duration = $_POST['duration_played'] ?? $_POST['duration'] ?? 0;
        $completed = $_POST['completed'] ?? false;

        if ($songId) {
            $result = $db->trackPlay($songId, $user, $duration, $completed, 'radio');

            echo json_encode([
                'success' => $result,
                'message' => $result ? 'Play tracked' : 'Failed to track play'
            ]);
        } else {
            echo json_encode([
                'success' => false,
                'message' => 'song_id required'
            ]);
        }

    } elseif ($action === 'get_stats') {
        // Get play statistics
        $songId = $_GET['song_id'] ?? null;

        if ($songId) {
            $stmt = $conn->prepare('SELECT * FROM song_stats WHERE song_id = ?');
            $stmt->execute([$songId]);
            $stats = $stmt->fetch();

            echo json_encode([
                'success' => true,
                'stats' => $stats
            ]);
        } else {
            echo json_encode([
                'success' => false,
                'message' => 'song_id required'
            ]);
        }

    } else {
        echo json_encode([
            'success' => false,
            'message' => 'Unknown action'
        ]);
    }

    $db->close();

} catch (Exception $e) {
    error_log("Radio API error: " . $e->getMessage());

    echo json_encode([
        'success' => false,
        'message' => $e->getMessage()
    ]);
}
