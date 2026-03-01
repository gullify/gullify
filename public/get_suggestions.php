<?php
/**
 * Gullify - Suggestions Endpoint
 * Returns similar songs, artists and albums based on the current track's genre.
 */
header('Content-Type: application/json');

require_once __DIR__ . '/../src/AppConfig.php';

$user     = $_GET['user']      ?? null;
$artistId = isset($_GET['artist_id']) ? (int)$_GET['artist_id'] : null;
$genre    = $_GET['genre']     ?? null;
$filePath = $_GET['file_path'] ?? null;

if (!$user) {
    echo json_encode(['success' => false, 'error' => 'Missing user']);
    exit;
}

try {
    $db = AppConfig::getDB();

    // If file_path provided, resolve artist_id and genre from the DB
    if (!$artistId && !$genre && $filePath) {
        $stmt = $db->prepare('
            SELECT a.id AS artist_id, COALESCE(a.genre, al.genre) AS genre
            FROM songs s
            JOIN albums al ON s.album_id = al.id
            JOIN artists a  ON al.artist_id = a.id
            WHERE s.file_path = ? AND a.user = ?
        ');
        $stmt->execute([$filePath, $user]);
        $row = $stmt->fetch();
        if ($row) {
            $artistId = (int)$row['artist_id'];
            $genre    = $row['genre'];
        }
    }

    // If still no genre but artist_id is known, look up the artist's genre
    if (!$genre && $artistId) {
        $stmt = $db->prepare('SELECT genre FROM artists WHERE id = ? AND user = ?');
        $stmt->execute([$artistId, $user]);
        $row = $stmt->fetch();
        if ($row) $genre = $row['genre'];
    }

    if (!$genre) {
        echo json_encode(['success' => true, 'data' => ['genre' => null, 'artists' => [], 'albums' => [], 'songs' => []]]);
        exit;
    }

    // --- Similar artists ---
    $sql    = 'SELECT a.id FROM artists a WHERE a.user = ? AND a.genre = ?';
    $params = [$user, $genre];
    if ($artistId) { $sql .= ' AND a.id != ?'; $params[] = $artistId; }
    $stmt = $db->prepare($sql);
    $stmt->execute($params);
    $allArtistIds = $stmt->fetchAll(PDO::FETCH_COLUMN);

    $artists = [];
    if (!empty($allArtistIds)) {
        shuffle($allArtistIds);
        $picked       = array_slice($allArtistIds, 0, 10);
        $placeholders = implode(',', array_fill(0, count($picked), '?'));
        $stmt = $db->prepare("
            SELECT a.id, a.name, COUNT(DISTINCT al.id) AS album_count
            FROM artists a
            LEFT JOIN albums al ON a.id = al.artist_id
            WHERE a.id IN ($placeholders)
            GROUP BY a.id, a.name
        ");
        $stmt->execute($picked);
        while ($row = $stmt->fetch()) {
            $artists[] = [
                'id'         => (int)$row['id'],
                'name'       => $row['name'],
                'imageUrl'   => 'serve_image.php?artist_id=' . $row['id'],
                'albumCount' => (int)$row['album_count'],
            ];
        }
    }

    // --- Similar albums ---
    $sql    = '
        SELECT al.id FROM albums al
        JOIN artists a ON al.artist_id = a.id
        WHERE a.user = ? AND (al.genre = ? OR a.genre = ?)
    ';
    $params = [$user, $genre, $genre];
    if ($artistId) { $sql .= ' AND a.id != ?'; $params[] = $artistId; }
    $stmt = $db->prepare($sql);
    $stmt->execute($params);
    $allAlbumIds = $stmt->fetchAll(PDO::FETCH_COLUMN);

    $albums = [];
    if (!empty($allAlbumIds)) {
        shuffle($allAlbumIds);
        $picked       = array_slice($allAlbumIds, 0, 8);
        $placeholders = implode(',', array_fill(0, count($picked), '?'));
        $stmt = $db->prepare("
            SELECT al.id, al.name, al.year, a.name AS artist_name, a.id AS artist_id
            FROM albums al
            JOIN artists a ON al.artist_id = a.id
            WHERE al.id IN ($placeholders)
        ");
        $stmt->execute($picked);
        while ($row = $stmt->fetch()) {
            $albums[] = [
                'id'          => (int)$row['id'],
                'name'        => $row['name'],
                'year'        => $row['year'],
                'artist_name' => $row['artist_name'],
                'artist_id'   => (int)$row['artist_id'],
                'artworkUrl'  => 'serve_image.php?album_id=' . $row['id'],
            ];
        }
    }

    // --- Similar songs ---
    $sql    = '
        SELECT s.id FROM songs s
        JOIN albums al ON s.album_id = al.id
        JOIN artists a  ON al.artist_id = a.id
        WHERE a.user = ? AND (al.genre = ? OR a.genre = ?)
    ';
    $params = [$user, $genre, $genre];
    if ($artistId) { $sql .= ' AND a.id != ?'; $params[] = $artistId; }
    $stmt = $db->prepare($sql);
    $stmt->execute($params);
    $allSongIds = $stmt->fetchAll(PDO::FETCH_COLUMN);

    $songs = [];
    if (!empty($allSongIds)) {
        shuffle($allSongIds);
        $picked       = array_slice($allSongIds, 0, 10);
        $placeholders = implode(',', array_fill(0, count($picked), '?'));
        $stmt = $db->prepare("
            SELECT s.id, s.title, s.file_path, s.duration,
                   al.id AS album_id, al.name AS album_name,
                   a.id  AS artist_id, a.name AS artist_name
            FROM songs s
            JOIN albums al ON s.album_id = al.id
            JOIN artists a  ON al.artist_id = a.id
            WHERE s.id IN ($placeholders)
        ");
        $stmt->execute($picked);
        while ($row = $stmt->fetch()) {
            $songs[] = [
                'id'          => (int)$row['id'],
                'title'       => $row['title'],
                'file_path'   => $row['file_path'],
                'duration'    => $row['duration'],
                'album_id'    => (int)$row['album_id'],
                'album_name'  => $row['album_name'],
                'artist_id'   => (int)$row['artist_id'],
                'artist_name' => $row['artist_name'],
                'artworkUrl'  => 'serve_image.php?album_id=' . $row['album_id'],
            ];
        }
    }

    echo json_encode([
        'success' => true,
        'data'    => [
            'genre'     => $genre,
            'artist_id' => $artistId,
            'artists'   => $artists,
            'albums'    => $albums,
            'songs'     => $songs,
        ],
    ]);

} catch (Exception $e) {
    echo json_encode(['success' => false, 'error' => $e->getMessage()]);
}
