<?php
/**
 * Get recent albums - returns albums added recently
 */
header('Content-Type: application/json');

require_once __DIR__ . '/../src/AppConfig.php';
require_once __DIR__ . '/../src/Database.php';

try {
    $user = $_GET['user'] ?? '';
    $days = intval($_GET['days'] ?? 30);
    $limit = intval($_GET['limit'] ?? 200);

    if (empty($user)) {
        echo json_encode(['error' => true, 'message' => 'User required', 'data' => []]);
        exit;
    }

    $db = new Database();
    $conn = $db->getConnection();

    // Check if albums table has created_at column
    $hasCreatedAt = false;
    try {
        $check = $conn->query("SHOW COLUMNS FROM albums LIKE 'created_at'");
        $hasCreatedAt = $check->rowCount() > 0;
    } catch (Exception $e) {}

    if ($hasCreatedAt) {
        $cutoff = date('Y-m-d H:i:s', strtotime("-{$days} days"));
        $stmt = $conn->prepare('
            SELECT
                al.id,
                al.name,
                al.year,
                al.created_at,
                a.id as artist_id,
                a.name as artist_name,
                COUNT(s.id) as song_count
            FROM albums al
            JOIN artists a ON al.artist_id = a.id
            LEFT JOIN songs s ON al.id = s.album_id
            WHERE a.user = ? AND al.created_at >= ?
            GROUP BY al.id
            ORDER BY al.created_at DESC
            LIMIT ?
        ');
        $stmt->execute([$user, $cutoff, $limit]);
    } else {
        // No created_at — return most recent albums by highest ID
        $stmt = $conn->prepare('
            SELECT
                al.id,
                al.name,
                al.year,
                NULL as created_at,
                a.id as artist_id,
                a.name as artist_name,
                COUNT(s.id) as song_count
            FROM albums al
            JOIN artists a ON al.artist_id = a.id
            LEFT JOIN songs s ON al.id = s.album_id
            WHERE a.user = ?
            GROUP BY al.id
            ORDER BY al.id DESC
            LIMIT ?
        ');
        $stmt->execute([$user, $limit]);
    }

    $albums = [];
    while ($row = $stmt->fetch()) {
        $albums[] = [
            'id' => (int)$row['id'],
            'name' => $row['name'],
            'year' => $row['year'],
            'created_at' => $row['created_at'],
            'artworkUrl' => 'serve_image.php?album_id=' . $row['id'],
            'artist_id' => (int)$row['artist_id'],
            'artist_name' => $row['artist_name'],
            'song_count' => (int)$row['song_count']
        ];
    }

    $db->close();

    echo json_encode(['error' => false, 'data' => $albums]);

} catch (Exception $e) {
    echo json_encode(['error' => true, 'message' => $e->getMessage(), 'data' => []]);
}
