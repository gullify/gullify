<?php
/**
 * Gullify API v2 - Discover other users' libraries (read-only)
 *
 *   GET /api/v2/users.php?action=list
 *       → { users:[{id,username,fullName,artistCount,albumCount,songCount,avatarUrl}], count }
 *       Active users other than the caller, richest library first.
 *
 *   GET /api/v2/users.php?action=library&user=X&limit=&offset=
 *       → { artists:[{id,name,imageUrl,hasImage,albumCount,songCount}], total, ... }
 *       The artist list of user X. Same shape as library.php's `library`
 *       action, so the app reuses its Artist mapper. READ-ONLY: browsing
 *       another user's library never mutates anything.
 *
 * Artist/album/song detail and streaming are keyed by global id (see
 * library.php `artist`/`album` and stream.php), so once the app has an
 * artist id it navigates and plays through the existing endpoints.
 */
require_once __DIR__ . '/_v2.php';
require_once __DIR__ . '/../../../src/Database.php';
require_once __DIR__ . '/../../../src/Avatar.php';

$ctx    = v2_auth();
$me     = $ctx['user']['username'];
$action = $_GET['action'] ?? 'list';

try {
    $conn = (new Database())->getConnection();

    if ($action === 'list') {
        // artists.album_count / song_count are maintained counters — cheap to sum.
        $stmt = $conn->prepare('
            SELECT u.id, u.username, u.full_name,
                   COUNT(a.id)                    AS artist_count,
                   COALESCE(SUM(a.album_count),0) AS album_count,
                   COALESCE(SUM(a.song_count),0)  AS song_count
            FROM users u
            LEFT JOIN artists a ON a.user = u.username
            WHERE u.is_active = 1 AND u.username <> ?
            GROUP BY u.id, u.username, u.full_name
            ORDER BY song_count DESC, u.username ASC
        ');
        $stmt->execute([$me]);

        $users = [];
        while ($r = $stmt->fetch()) {
            $users[] = [
                'id'          => (int) $r['id'],
                'username'    => $r['username'],
                'fullName'    => ($r['full_name'] ?? '') !== '' ? $r['full_name'] : null,
                'artistCount' => (int) $r['artist_count'],
                'albumCount'  => (int) $r['album_count'],
                'songCount'   => (int) $r['song_count'],
                'avatarUrl'   => Avatar::url((int) $r['id']),
            ];
        }
        v2_ok(['users' => $users, 'count' => count($users)]);
    }

    if ($action === 'library') {
        $target = trim((string) ($_GET['user'] ?? ''));
        if ($target === '') {
            v2_fail('missing_user', 'user parameter required', 400);
        }
        // Only browse real, active users.
        $chk = $conn->prepare('SELECT 1 FROM users WHERE username = ? AND is_active = 1');
        $chk->execute([$target]);
        if (!$chk->fetchColumn()) {
            v2_fail('not_found', 'Unknown user', 404);
        }

        $limit  = isset($_GET['limit']) ? (int) $_GET['limit'] : 5000;
        $offset = isset($_GET['offset']) ? (int) $_GET['offset'] : 0;
        $limit  = max(1, min(9999, $limit));
        $offset = max(0, $offset);

        $stmt = $conn->prepare('
            SELECT id, name,
                   (image IS NOT NULL AND image != "") AS has_image,
                   album_count, song_count
            FROM artists
            WHERE user = ?
            ORDER BY name ASC
            LIMIT ? OFFSET ?
        ');
        $stmt->execute([$target, $limit, $offset]);

        $artists = [];
        while ($row = $stmt->fetch()) {
            $hasImage  = (bool) $row['has_image'];
            $artists[] = [
                'id'         => (int) $row['id'],
                'name'       => $row['name'],
                'imageUrl'   => $hasImage ? 'serve_image.php?artist_id=' . $row['id'] : null,
                'hasImage'   => $hasImage,
                'albumCount' => (int) $row['album_count'],
                'songCount'  => (int) $row['song_count'],
            ];
        }

        $cnt = $conn->prepare('SELECT COUNT(*) FROM artists WHERE user = ?');
        $cnt->execute([$target]);
        $total = (int) $cnt->fetchColumn();

        v2_ok([
            'artists'  => $artists,
            'total'    => $total,
            'limit'    => $limit,
            'offset'   => $offset,
            'has_more' => ($offset + $limit) < $total,
        ]);
    }

    v2_fail('unknown_action', 'Unknown users action: ' . $action, 400);
} catch (Throwable $e) {
    error_log('API v2 users error: ' . $e->getMessage());
    v2_fail('server_error', 'Server error', 500);
}
