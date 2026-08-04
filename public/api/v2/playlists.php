<?php
/**
 * Gullify API v2 - Playlists (native)
 *   GET  ?action=list                          → [{id, name, songCount}]
 *   GET  ?action=songs&id=N                    → [{...song, playlistSongId}]
 *   POST ?action=create      {name}            → {id}
 *   POST ?action=rename      {id, name}        → null
 *   POST ?action=delete      {id}              → null
 *   POST ?action=add_song    {id, song_id}     → null
 *   POST ?action=add_album   {id, album_id}    → {added}
 *   POST ?action=remove_song {playlist_song_id} → null
 */
require_once __DIR__ . '/_v2.php';
require_once __DIR__ . '/../../../src/Database.php';

$ctx      = v2_auth();
$username = $ctx['user']['username'];
$action   = $_GET['action'] ?? $_POST['action'] ?? 'list';
$body     = v2_body();

try {
    $db = new Database();

    switch ($action) {
        case 'list':
            $rows = $db->getPlaylists($username);
            v2_ok(array_map(fn($p) => [
                'id'        => (int)$p['id'],
                'name'      => $p['name'],
                'songCount' => (int)$p['song_count'],
            ], $rows));

        case 'songs':
            $id   = (int)($_GET['id'] ?? 0);
            $rows = $db->getPlaylistSongs($id, $username);
            if ($rows === false) v2_fail('not_found', 'Playlist not found', 404);
            v2_ok(array_map(fn($s) => [
                'id'             => (int)$s['id'],
                'title'          => $s['title'],
                'filePath'       => $s['file_path'],
                'duration'       => (int)($s['duration'] ?? 0),
                'trackNumber'    => isset($s['track_number']) ? (int)$s['track_number'] : null,
                'albumId'        => (int)$s['album_id'],
                'albumName'      => $s['album_name'],
                'artistId'       => $s['artist_id'] !== null ? (int)$s['artist_id'] : null,
                'artistName'     => $s['artist_name'],
                'artworkUrl'     => $s['artworkUrl'],
                'playlistSongId' => (int)$s['playlist_song_id'],
            ], $rows));

        case 'create':
            $name = trim((string)($body['name'] ?? ''));
            if ($name === '') v2_fail('invalid_request', 'Missing name');
            $id = $db->createPlaylist($name, $username);
            if ($id === false) v2_fail('server_error', 'Could not create playlist', 500);
            v2_ok(['id' => (int)$id]);

        case 'rename':
            $id   = (int)($body['id'] ?? 0);
            $name = trim((string)($body['name'] ?? ''));
            if (!$id || $name === '') v2_fail('invalid_request', 'Missing id or name');
            $db->renamePlaylist($id, $name, $username);
            v2_ok();

        case 'delete':
            $id = (int)($body['id'] ?? 0);
            if (!$id) v2_fail('invalid_request', 'Missing id');
            $db->deletePlaylist($id, $username);
            v2_ok();

        case 'add_song':
            $id     = (int)($body['id'] ?? 0);
            $songId = (int)($body['song_id'] ?? 0);
            if (!$id || !$songId) v2_fail('invalid_request', 'Missing id or song_id');
            // Ownership check (addToPlaylist itself doesn't verify user)
            if ($db->getPlaylistSongs($id, $username) === false) {
                v2_fail('not_found', 'Playlist not found', 404);
            }
            $db->addToPlaylist($id, $songId);
            v2_ok();

        case 'add_album':
            // Tout un album d'un coup (jeu « Défricheur » : un album gardé
            // rejoint la playlist en entier). Les titres déjà présents sont
            // ignorés par addToPlaylist.
            $id      = (int)($body['id'] ?? 0);
            $albumId = (int)($body['album_id'] ?? 0);
            if (!$id || !$albumId) v2_fail('invalid_request', 'Missing id or album_id');
            if ($db->getPlaylistSongs($id, $username) === false) {
                v2_fail('not_found', 'Playlist not found', 404);
            }
            $stmt = $db->getConnection()->prepare('
                SELECT s.id
                FROM songs s
                JOIN albums al ON s.album_id = al.id
                JOIN artists a ON al.artist_id = a.id
                WHERE al.id = ? AND a.user = ?
                ORDER BY s.track_number ASC, s.id ASC
            ');
            $stmt->execute([$albumId, $username]);
            $added = 0;
            foreach ($stmt->fetchAll(PDO::FETCH_COLUMN) as $songId) {
                if ($db->addToPlaylist($id, (int)$songId)) $added++;
            }
            v2_ok(['added' => $added]);

        case 'remove_song':
            $psId = (int)($body['playlist_song_id'] ?? 0);
            if (!$psId) v2_fail('invalid_request', 'Missing playlist_song_id');
            if ($db->removeFromPlaylist($psId, $username) === false) {
                v2_fail('not_found', 'Playlist song not found', 404);
            }
            v2_ok();

        default:
            v2_fail('invalid_request', 'Unknown action: ' . $action);
    }
} catch (Throwable $e) {
    error_log('API v2 playlists error: ' . $e->getMessage());
    v2_fail('server_error', 'Playlist operation failed', 500);
}
