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

    // « Populaires » = ce que tu écoutes RÉELLEMENT en ce moment : on classe
    // par nombre d'écoutes récentes (play_history, 90 jours) et non par le
    // compteur de toujours (song_stats), qu'un vieux pic gonflé dominait à vie.
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
            COUNT(ph.id) AS play_count,
            MAX(ph.played_at) AS last_played_at
        FROM play_history ph
        JOIN songs s   ON ph.song_id = s.id
        JOIN albums al ON s.album_id = al.id
        JOIN artists a ON al.artist_id = a.id
        WHERE a.user = ?
          AND ph.played_at >= DATE_SUB(NOW(), INTERVAL 90 DAY)
        GROUP BY s.id
        ORDER BY play_count DESC, last_played_at DESC
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
