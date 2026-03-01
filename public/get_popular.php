<?php
/**
 * Get popular/most played songs
 */
header('Content-Type: application/json');

require_once __DIR__ . '/../src/AppConfig.php';
require_once __DIR__ . '/../src/Database.php';

try {
    $user = $_GET['user'] ?? '';
    $limit = intval($_GET['limit'] ?? 20);

    $db = new Database();
    $conn = $db->getConnection();

    // Check if song_stats has data
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
            a.id as artist_id,
            ss.play_count,
            ss.last_played_at
        FROM song_stats ss
        JOIN songs s ON ss.song_id = s.id
        JOIN albums al ON s.album_id = al.id
        JOIN artists a ON al.artist_id = a.id
        WHERE a.user = ? AND ss.play_count > 0
        ORDER BY ss.play_count DESC
        LIMIT ?
    ');
    $stmt->execute([$user, $limit]);

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
            'artworkUrl' => 'serve_image.php?album_id=' . $row['album_id'],
            'artistId' => (int)$row['artist_id'],
            'artistName' => $row['artist_name'],
            'playCount' => (int)$row['play_count']
        ];
    }

    $db->close();

    echo json_encode(['error' => false, 'data' => $songs]);

} catch (Exception $e) {
    echo json_encode(['error' => true, 'message' => $e->getMessage(), 'data' => []]);
}
