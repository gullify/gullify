<?php
/**
 * Gullify - OpenSubsonic API
 *
 * Implements the Subsonic/OpenSubsonic REST API so standard clients
 * (DSub, Symfonium, Substreamer, Ultrasonic, etc.) can connect.
 *
 * Endpoint: /rest/{method}.view
 * Auth: query params u/p or u/t+s (token-based)
 * Response: XML (default) or JSON (f=json)
 */

require_once __DIR__ . '/../../src/AppConfig.php';
require_once __DIR__ . '/../../src/Auth.php';
require_once __DIR__ . '/../../src/Database.php';
require_once __DIR__ . '/../../src/Storage/StorageInterface.php';
require_once __DIR__ . '/../../src/Storage/LocalStorage.php';
require_once __DIR__ . '/../../src/Storage/SFTPStorage.php';
require_once __DIR__ . '/../../src/Storage/StorageFactory.php';

// ── Determine which method was called ────────────────────────────────────────
$uri = $_SERVER['REQUEST_URI'];
$path = parse_url($uri, PHP_URL_PATH);

// Extract method name: /rest/ping.view → ping
if (preg_match('#/rest/(\w+)\.view#', $path, $m)) {
    $method = $m[1];
} else {
    $method = $_GET['method'] ?? 'ping';
}

$format = $_GET['f'] ?? 'xml';

// ── Authentication ───────────────────────────────────────────────────────────
$username = $_GET['u'] ?? $_POST['u'] ?? '';
$password = $_GET['p'] ?? $_POST['p'] ?? '';
$token    = $_GET['t'] ?? $_POST['t'] ?? '';
$salt     = $_GET['s'] ?? $_POST['s'] ?? '';

$authenticatedUser = null;

// ping and getLicense never require auth (Subsonic spec + client compatibility)
if ($method !== 'ping' && $method !== 'getLicense') {
    $auth = new Auth();

    if ($token && $salt) {
        // Token-based auth: token = md5(password + salt)
        // Subsonic requires the plaintext password to verify tokens.
        // We store it in the `subsonic_password` column (auto-created).
        ensureSubsonicPasswordColumn();
        $user = $auth->getUserByUsername($username);
        if ($user && !empty($user['subsonic_password'])) {
            $expected = md5($user['subsonic_password'] . $salt);
            if ($expected === $token) {
                $authenticatedUser = $user;
            } else {
                subsonicError(40, 'Wrong username or password.', $format);
            }
        } elseif ($user) {
            subsonicError(40, 'Subsonic password not set. Go to Gullify Settings to enable Subsonic access.', $format);
        } else {
            subsonicError(40, 'Wrong username or password.', $format);
        }
    } elseif ($password) {
        // Password can be plaintext or hex-encoded with enc: prefix
        $pass = $password;
        if (str_starts_with($pass, 'enc:')) {
            $pass = hex2bin(substr($pass, 4));
        }
        $user = $auth->verifyPassword($username, $pass);
        if ($user) {
            $authenticatedUser = $user;
            // Auto-save plaintext password for future token-based auth
            ensureSubsonicPasswordColumn();
            try {
                $conn = AppConfig::getDB();
                $conn->prepare('UPDATE users SET subsonic_password = ? WHERE id = ?')
                     ->execute([$pass, $user['id']]);
            } catch (Exception $e) {}
        } else {
            subsonicError(40, 'Wrong username or password.', $format);
        }
    } else {
        subsonicError(10, 'Required parameter is missing: authentication.', $format);
    }
}

// ── Auto-migration helper ────────────────────────────────────────────────────
function ensureSubsonicPasswordColumn() {
    static $checked = false;
    if ($checked) return;
    $checked = true;
    try {
        $conn = AppConfig::getDB();
        $stmt = $conn->query("SHOW COLUMNS FROM users LIKE 'subsonic_password'");
        if (!$stmt->fetch()) {
            $conn->exec("ALTER TABLE users ADD COLUMN subsonic_password VARCHAR(255) DEFAULT NULL");
        }
    } catch (Exception $e) {
        // ignore
    }
}

// ── Route to handler ─────────────────────────────────────────────────────────
$db = new Database();
$currentUser = $authenticatedUser['username'] ?? '';

switch ($method) {
    case 'ping':
        subsonicOk([], $format);
        break;

    case 'getLicense':
        subsonicOk(['license' => ['@valid' => 'true', '@email' => 'gullify@local', '@licenseExpires' => '2099-12-31T00:00:00']], $format);
        break;

    case 'getMusicFolders':
        subsonicOk(['musicFolders' => ['musicFolder' => [['@id' => 1, '@name' => 'Music']]]], $format);
        break;

    case 'getArtists':
        handleGetArtists($db, $currentUser, $format);
        break;

    case 'getArtist':
        handleGetArtist($db, $currentUser, $format);
        break;

    case 'getAlbum':
        handleGetAlbum($db, $currentUser, $format);
        break;

    case 'getSong':
        handleGetSong($db, $currentUser, $format);
        break;

    case 'getAlbumList':
    case 'getAlbumList2':
        handleGetAlbumList($db, $currentUser, $format);
        break;

    case 'search2':
    case 'search3':
        handleSearch($db, $currentUser, $format);
        break;

    case 'stream':
        handleStream($db, $currentUser);
        break;

    case 'getCoverArt':
        handleGetCoverArt();
        break;

    case 'scrobble':
        handleScrobble($db, $currentUser, $format);
        break;

    case 'star':
        handleStar($db, $currentUser, $format);
        break;

    case 'unstar':
        handleUnstar($db, $currentUser, $format);
        break;

    case 'getStarred':
    case 'getStarred2':
        handleGetStarred($db, $currentUser, $format);
        break;

    case 'getPlaylists':
        handleGetPlaylists($db, $currentUser, $format);
        break;

    case 'getPlaylist':
        handleGetPlaylist($db, $currentUser, $format);
        break;

    case 'createPlaylist':
        handleCreatePlaylist($db, $currentUser, $format);
        break;

    case 'getRandomSongs':
        handleGetRandomSongs($db, $currentUser, $format);
        break;

    case 'getOpenSubsonicExtensions':
        subsonicOk(['openSubsonicExtensions' => []], $format);
        break;

    case 'getUser':
        subsonicOk(['user' => [
            '@username' => $currentUser,
            '@email' => '',
            '@scrobblingEnabled' => 'true',
            '@adminRole' => ($authenticatedUser['is_admin'] ?? 0) ? 'true' : 'false',
            '@settingsRole' => 'false',
            '@downloadRole' => 'true',
            '@uploadRole' => 'false',
            '@playlistRole' => 'true',
            '@coverArtRole' => 'false',
            '@commentRole' => 'false',
            '@podcastRole' => 'false',
            '@streamRole' => 'true',
            '@jukeboxRole' => 'false',
            '@shareRole' => 'false',
            '@videoConversionRole' => 'false',
            'folder' => [1],
        ]], $format);
        break;

    case 'getIndexes':
        handleGetArtists($db, $currentUser, $format, true);
        break;

    case 'getMusicDirectory':
        handleGetMusicDirectory($db, $currentUser, $format);
        break;

    case 'getGenres':
        handleGetGenres($db, $currentUser, $format);
        break;

    case 'getBookmarks':
        subsonicOk(['bookmarks' => new stdClass()], $format);
        break;

    case 'getScanStatus':
        subsonicOk(['scanStatus' => ['@scanning' => false, '@count' => 0]], $format);
        break;

    case 'getInternetRadioStations':
        subsonicOk(['internetRadioStations' => new stdClass()], $format);
        break;

    case 'getPodcasts':
        subsonicOk(['podcasts' => new stdClass()], $format);
        break;

    default:
        subsonicOk([], $format);
        break;
}

// ── Handlers ─────────────────────────────────────────────────────────────────

function handleGetArtists($db, $user, $format, $asIndexes = false) {
    $library = $db->getLibrary($user);
    $artists = $library['artists'];

    // Group by first letter
    $indexed = [];
    foreach ($artists as $a) {
        $letter = mb_strtoupper(mb_substr($a['name'], 0, 1));
        if (!ctype_alpha($letter)) $letter = '#';
        $indexed[$letter][] = [
            '@id' => 'ar-' . $a['id'],
            '@name' => $a['name'],
            '@albumCount' => (int)$a['album_count'],
            '@coverArt' => 'ar-' . $a['id'],
        ];
    }

    ksort($indexed);
    $indexList = [];
    foreach ($indexed as $letter => $arts) {
        $indexList[] = ['@name' => $letter, 'artist' => $arts];
    }

    if ($asIndexes) {
        subsonicOk(['indexes' => ['index' => $indexList]], $format);
    } else {
        subsonicOk(['artists' => ['index' => $indexList]], $format);
    }
}

function handleGetArtist($db, $user, $format) {
    $id = str_replace('ar-', '', $_GET['id'] ?? '');
    if (!$id) { subsonicError(10, 'Missing id parameter.', $format); return; }

    $albums = $db->getArtistAlbums($id);
    $artistName = '';
    $albumList = [];

    foreach ($albums as $al) {
        if (!$artistName) {
            // Get artist name from DB
            $conn = AppConfig::getDB();
            $stmt = $conn->prepare('SELECT name FROM artists WHERE id = ?');
            $stmt->execute([$id]);
            $artistName = $stmt->fetchColumn() ?: 'Unknown';
        }

        $albumList[] = [
            '@id' => 'al-' . $al['id'],
            '@name' => $al['name'],
            '@artist' => $artistName,
            '@artistId' => 'ar-' . $id,
            '@coverArt' => 'al-' . $al['id'],
            '@songCount' => (int)$al['song_count'],
            '@duration' => (int)($al['total_duration'] ?? 0),
            '@year' => (int)($al['year'] ?? 0),
        ];
    }

    subsonicOk(['artist' => [
        '@id' => 'ar-' . $id,
        '@name' => $artistName,
        '@albumCount' => count($albumList),
        '@coverArt' => 'ar-' . $id,
        'album' => $albumList,
    ]], $format);
}

function handleGetAlbum($db, $user, $format) {
    $id = str_replace('al-', '', $_GET['id'] ?? '');
    if (!$id) { subsonicError(10, 'Missing id parameter.', $format); return; }

    $songs = $db->getAlbumSongs($id);
    if (empty($songs)) { subsonicError(70, 'Album not found.', $format); return; }

    $songList = [];
    foreach ($songs as $s) {
        $songList[] = buildSongChild($s);
    }

    $first = $songs[0];
    subsonicOk(['album' => [
        '@id' => 'al-' . $id,
        '@name' => $first['album_name'],
        '@artist' => $first['artist_name'],
        '@artistId' => 'ar-' . $first['artist_id'],
        '@coverArt' => 'al-' . $id,
        '@songCount' => count($songList),
        '@year' => (int)($first['year'] ?? 0),
        'song' => $songList,
    ]], $format);
}

function handleGetSong($db, $user, $format) {
    $id = str_replace('s-', '', $_GET['id'] ?? '');
    if (!$id) { subsonicError(10, 'Missing id parameter.', $format); return; }

    $conn = AppConfig::getDB();
    $stmt = $conn->prepare('
        SELECT s.*, al.name as album_name, al.year, a.name as artist_name, a.id as artist_id
        FROM songs s
        JOIN albums al ON s.album_id = al.id
        JOIN artists a ON al.artist_id = a.id
        WHERE s.id = ?
    ');
    $stmt->execute([$id]);
    $song = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$song) { subsonicError(70, 'Song not found.', $format); return; }

    subsonicOk(['song' => buildSongChild($song)], $format);
}

function handleGetAlbumList($db, $user, $format) {
    $type = $_GET['type'] ?? 'alphabeticalByName';
    $size = min((int)($_GET['size'] ?? 20), 500);
    $offset = (int)($_GET['offset'] ?? 0);

    $conn = AppConfig::getDB();

    switch ($type) {
        case 'newest':
            $orderBy = 'al.id DESC';
            break;
        case 'random':
            $orderBy = 'RAND()';
            break;
        case 'recent':
            $orderBy = 'al.id DESC';
            break;
        case 'frequent':
        case 'starred':
        case 'alphabeticalByName':
        default:
            $orderBy = 'al.name ASC';
            break;
        case 'alphabeticalByArtist':
            $orderBy = 'a.name ASC, al.name ASC';
            break;
        case 'byYear':
            $fromYear = (int)($_GET['fromYear'] ?? 0);
            $toYear = (int)($_GET['toYear'] ?? 9999);
            $orderBy = 'al.year ASC';
            break;
    }

    $sql = "
        SELECT al.*, a.name as artist_name, a.id as artist_id,
               COUNT(s.id) as song_count, SUM(s.duration) as total_duration
        FROM albums al
        JOIN artists a ON al.artist_id = a.id
        LEFT JOIN songs s ON al.id = s.album_id
        WHERE a.user = ?
    ";
    $params = [$user];

    if ($type === 'byYear' && isset($fromYear)) {
        $sql .= " AND (al.year BETWEEN ? AND ?)";
        $params[] = $fromYear;
        $params[] = $toYear;
    }

    $sql .= " GROUP BY al.id ORDER BY $orderBy LIMIT $size OFFSET $offset";

    $stmt = $conn->prepare($sql);
    $stmt->execute($params);
    $albums = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $albumList = [];
    foreach ($albums as $al) {
        $albumList[] = [
            '@id' => 'al-' . $al['id'],
            '@name' => $al['name'],
            '@artist' => $al['artist_name'],
            '@artistId' => 'ar-' . $al['artist_id'],
            '@coverArt' => 'al-' . $al['id'],
            '@songCount' => (int)$al['song_count'],
            '@duration' => (int)($al['total_duration'] ?? 0),
            '@year' => (int)($al['year'] ?? 0),
        ];
    }

    subsonicOk(['albumList2' => ['album' => $albumList]], $format);
}

function handleSearch($db, $user, $format) {
    $query = trim($_GET['query'] ?? '', ' "');
    $artistCount = min((int)($_GET['artistCount'] ?? 20), 500);
    $artistOffset = (int)($_GET['artistOffset'] ?? 0);
    $albumCount = min((int)($_GET['albumCount'] ?? 20), 500);
    $albumOffset = (int)($_GET['albumOffset'] ?? 0);
    $songCount = min((int)($_GET['songCount'] ?? 20), 500);
    $songOffset = (int)($_GET['songOffset'] ?? 0);

    $conn = AppConfig::getDB();
    $isListAll = ($query === '');
    $like = "%{$query}%";

    // Artists
    $artists = [];
    if ($artistCount > 0) {
        if ($isListAll) {
            $stmt = $conn->prepare("SELECT id, name FROM artists WHERE user = ? ORDER BY name LIMIT ? OFFSET ?");
            $stmt->execute([$user, $artistCount, $artistOffset]);
        } else {
            $stmt = $conn->prepare("SELECT id, name FROM artists WHERE user = ? AND name LIKE ? ORDER BY name LIMIT ? OFFSET ?");
            $stmt->execute([$user, $like, $artistCount, $artistOffset]);
        }
        $artists = array_map(fn($a) => [
            '@id' => 'ar-' . $a['id'],
            '@name' => $a['name'],
            '@coverArt' => 'ar-' . $a['id'],
        ], $stmt->fetchAll(PDO::FETCH_ASSOC));
    }

    // Albums
    $albums = [];
    if ($albumCount > 0) {
        if ($isListAll) {
            $stmt = $conn->prepare("
                SELECT al.*, a.name as artist_name, a.id as artist_id
                FROM albums al JOIN artists a ON al.artist_id = a.id
                WHERE a.user = ? ORDER BY al.name LIMIT ? OFFSET ?
            ");
            $stmt->execute([$user, $albumCount, $albumOffset]);
        } else {
            $stmt = $conn->prepare("
                SELECT al.*, a.name as artist_name, a.id as artist_id
                FROM albums al JOIN artists a ON al.artist_id = a.id
                WHERE a.user = ? AND (al.name LIKE ? OR a.name LIKE ?)
                ORDER BY al.name LIMIT ? OFFSET ?
            ");
            $stmt->execute([$user, $like, $like, $albumCount, $albumOffset]);
        }
        $albums = array_map(fn($al) => [
            '@id' => 'al-' . $al['id'],
            '@name' => $al['name'],
            '@artist' => $al['artist_name'],
            '@artistId' => 'ar-' . $al['artist_id'],
            '@coverArt' => 'al-' . $al['id'],
            '@year' => (int)($al['year'] ?? 0),
        ], $stmt->fetchAll(PDO::FETCH_ASSOC));
    }

    // Songs
    $songList = [];
    if ($songCount > 0) {
        if ($isListAll) {
            $stmt = $conn->prepare("
                SELECT s.*, al.name as album_name, al.year, a.name as artist_name, a.id as artist_id
                FROM songs s
                JOIN albums al ON s.album_id = al.id
                JOIN artists a ON al.artist_id = a.id
                WHERE a.user = ?
                ORDER BY s.title LIMIT ? OFFSET ?
            ");
            $stmt->execute([$user, $songCount, $songOffset]);
            $songList = array_map(fn($s) => buildSongChild($s), $stmt->fetchAll(PDO::FETCH_ASSOC));
        } else {
            $songs = $db->searchSongs($query, $user);
            $songList = array_map(fn($s) => buildSongChild($s), array_slice($songs, $songOffset, $songCount));
        }
    }

    subsonicOk(['searchResult3' => [
        'artist' => $artists,
        'album' => $albums,
        'song' => $songList,
    ]], $format);
}

function handleStream($db, $user) {
    $id = str_replace('s-', '', $_GET['id'] ?? '');
    if (!$id) { http_response_code(400); exit; }

    $conn = AppConfig::getDB();
    $stmt = $conn->prepare('
        SELECT s.file_path, a.user
        FROM songs s
        JOIN albums al ON s.album_id = al.id
        JOIN artists a ON al.artist_id = a.id
        WHERE s.id = ?
    ');
    $stmt->execute([$id]);
    $song = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$song) { http_response_code(404); exit; }

    // Redirect to the existing stream endpoint
    $streamUrl = '/stream.php?path=' . urlencode($song['file_path']);
    header('Location: ' . $streamUrl);
    exit;
}

function handleGetCoverArt() {
    $id = $_GET['id'] ?? '';
    $size = $_GET['size'] ?? '';

    // Route to serve_image.php
    if (str_starts_with($id, 'al-')) {
        $albumId = str_replace('al-', '', $id);
        $url = '/serve_image.php?album_id=' . urlencode($albumId);
    } elseif (str_starts_with($id, 'ar-')) {
        $artistId = str_replace('ar-', '', $id);
        $url = '/serve_image.php?artist_id=' . urlencode($artistId);
    } else {
        http_response_code(404);
        exit;
    }

    header('Location: ' . $url);
    exit;
}

function handleScrobble($db, $user, $format) {
    $id = str_replace('s-', '', $_GET['id'] ?? $_POST['id'] ?? '');
    if (!$id) { subsonicError(10, 'Missing id parameter.', $format); return; }

    $db->trackPlay($id, $user, 0, true, 'subsonic');
    subsonicOk([], $format);
}

function handleStar($db, $user, $format) {
    $id = $_GET['id'] ?? $_POST['id'] ?? '';
    $albumId = $_GET['albumId'] ?? $_POST['albumId'] ?? '';
    $artistId = $_GET['artistId'] ?? $_POST['artistId'] ?? '';

    if ($id) {
        $songId = str_replace('s-', '', $id);
        $db->addToFavorites($songId, $user);
    }
    if ($albumId) {
        $alId = str_replace('al-', '', $albumId);
        $db->addAlbumToFavorites($alId, $user);
    }
    if ($artistId) {
        $arId = str_replace('ar-', '', $artistId);
        $db->addArtistToFavorites($arId, $user);
    }

    subsonicOk([], $format);
}

function handleUnstar($db, $user, $format) {
    $id = $_GET['id'] ?? $_POST['id'] ?? '';
    $albumId = $_GET['albumId'] ?? $_POST['albumId'] ?? '';
    $artistId = $_GET['artistId'] ?? $_POST['artistId'] ?? '';

    if ($id) {
        $songId = str_replace('s-', '', $id);
        $db->removeFromFavorites($songId, $user);
    }
    if ($albumId) {
        $alId = str_replace('al-', '', $albumId);
        $db->removeAlbumFromFavorites($alId, $user);
    }
    if ($artistId) {
        $arId = str_replace('ar-', '', $artistId);
        $db->removeArtistFromFavorites($arId, $user);
    }

    subsonicOk([], $format);
}

function handleGetStarred($db, $user, $format) {
    $favSongs = $db->getFavorites($user);
    $favArtists = $db->getFavoriteArtists($user);
    $favAlbums = $db->getFavoriteAlbums($user);

    $songList = array_map(fn($s) => buildSongChild($s), $favSongs);

    $artistList = array_map(fn($a) => [
        '@id' => 'ar-' . $a['id'],
        '@name' => $a['name'],
        '@coverArt' => 'ar-' . $a['id'],
    ], $favArtists);

    $albumList = array_map(fn($al) => [
        '@id' => 'al-' . $al['id'],
        '@name' => $al['name'],
        '@artist' => $al['artist_name'],
        '@artistId' => 'ar-' . $al['artist_id'],
        '@coverArt' => 'al-' . $al['id'],
        '@year' => (int)($al['year'] ?? 0),
    ], $favAlbums);

    subsonicOk(['starred2' => [
        'artist' => $artistList,
        'album' => $albumList,
        'song' => $songList,
    ]], $format);
}

function handleGetPlaylists($db, $user, $format) {
    $playlists = $db->getPlaylists($user);

    $list = array_map(fn($p) => [
        '@id' => 'pl-' . $p['id'],
        '@name' => $p['name'],
        '@songCount' => (int)$p['song_count'],
        '@public' => 'false',
        '@owner' => $user,
    ], $playlists);

    subsonicOk(['playlists' => ['playlist' => $list]], $format);
}

function handleGetPlaylist($db, $user, $format) {
    $id = str_replace('pl-', '', $_GET['id'] ?? '');
    if (!$id) { subsonicError(10, 'Missing id parameter.', $format); return; }

    $songs = $db->getPlaylistSongs($id, $user);
    if ($songs === false) { subsonicError(70, 'Playlist not found.', $format); return; }

    $songList = array_map(fn($s) => buildSongChild($s), $songs);

    $conn = AppConfig::getDB();
    $stmt = $conn->prepare('SELECT * FROM playlists WHERE id = ? AND user = ?');
    $stmt->execute([$id, $user]);
    $pl = $stmt->fetch(PDO::FETCH_ASSOC);

    subsonicOk(['playlist' => [
        '@id' => 'pl-' . $id,
        '@name' => $pl['name'] ?? 'Unknown',
        '@songCount' => count($songList),
        '@public' => 'false',
        '@owner' => $user,
        'entry' => $songList,
    ]], $format);
}

function handleCreatePlaylist($db, $user, $format) {
    $name = $_GET['name'] ?? $_POST['name'] ?? '';
    if (!$name) { subsonicError(10, 'Missing name parameter.', $format); return; }

    $playlistId = $db->createPlaylist($name, $user);

    // Add songs if provided
    $songIds = $_GET['songId'] ?? $_POST['songId'] ?? [];
    if (!is_array($songIds)) $songIds = [$songIds];
    foreach ($songIds as $sid) {
        $db->addToPlaylist($playlistId, str_replace('s-', '', $sid));
    }

    subsonicOk([], $format);
}

function handleGetRandomSongs($db, $user, $format) {
    $size = min((int)($_GET['size'] ?? 10), 500);

    $conn = AppConfig::getDB();
    $stmt = $conn->prepare('
        SELECT s.*, al.name as album_name, al.year, a.name as artist_name, a.id as artist_id
        FROM songs s
        JOIN albums al ON s.album_id = al.id
        JOIN artists a ON al.artist_id = a.id
        WHERE a.user = ?
        ORDER BY RAND()
        LIMIT ?
    ');
    $stmt->execute([$user, $size]);
    $songs = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $songList = array_map(fn($s) => buildSongChild($s), $songs);

    subsonicOk(['randomSongs' => ['song' => $songList]], $format);
}

function handleGetMusicDirectory($db, $user, $format) {
    $id = $_GET['id'] ?? '';

    if (str_starts_with($id, 'ar-')) {
        // Artist directory → list albums
        $artistId = str_replace('ar-', '', $id);
        $albums = $db->getArtistAlbums($artistId);

        $conn = AppConfig::getDB();
        $stmt = $conn->prepare('SELECT name FROM artists WHERE id = ?');
        $stmt->execute([$artistId]);
        $artistName = $stmt->fetchColumn() ?: 'Unknown';

        $children = array_map(fn($al) => [
            '@id' => 'al-' . $al['id'],
            '@parent' => $id,
            '@isDir' => 'true',
            '@title' => $al['name'],
            '@artist' => $artistName,
            '@coverArt' => 'al-' . $al['id'],
            '@year' => (int)($al['year'] ?? 0),
        ], $albums);

        subsonicOk(['directory' => [
            '@id' => $id,
            '@name' => $artistName,
            'child' => $children,
        ]], $format);

    } elseif (str_starts_with($id, 'al-')) {
        // Album directory → list songs
        $albumId = str_replace('al-', '', $id);
        $songs = $db->getAlbumSongs($albumId);

        $songList = array_map(fn($s) => buildSongChild($s), $songs);
        $albumName = $songs[0]['album_name'] ?? 'Unknown';

        subsonicOk(['directory' => [
            '@id' => $id,
            '@name' => $albumName,
            'child' => $songList,
        ]], $format);

    } else {
        subsonicError(70, 'Directory not found.', $format);
    }
}

function handleGetGenres($db, $user, $format) {
    $conn = AppConfig::getDB();
    $stmt = $conn->prepare("
        SELECT a.genre, COUNT(DISTINCT al.id) as albumCount, COUNT(DISTINCT s.id) as songCount
        FROM artists a
        JOIN albums al ON a.id = al.artist_id
        JOIN songs s ON al.id = s.album_id
        WHERE a.user = ? AND a.genre IS NOT NULL AND a.genre != ''
        GROUP BY a.genre
        ORDER BY a.genre ASC
    ");
    $stmt->execute([$user]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $genres = array_map(fn($r) => [
        '@songCount' => (int)$r['songCount'],
        '@albumCount' => (int)$r['albumCount'],
        '_value' => $r['genre'],
    ], $rows);

    subsonicOk(['genres' => ['genre' => $genres]], $format);
}

// ── Helpers ──────────────────────────────────────────────────────────────────

function stripAtKeys($data) {
    if ($data instanceof stdClass) return $data;
    if (!is_array($data)) return $data;
    $out = [];
    foreach ($data as $k => $v) {
        if ($k === '_value') {
            $out['value'] = $v;
            continue;
        }
        $key = is_string($k) && str_starts_with($k, '@') ? substr($k, 1) : $k;
        $out[$key] = is_array($v) ? stripAtKeys($v) : $v;
    }
    return $out;
}

function buildSongChild($s) {
    $ext = pathinfo($s['file_path'] ?? '', PATHINFO_EXTENSION) ?: 'mp3';
    $mimeTypes = [
        'mp3' => 'audio/mpeg', 'flac' => 'audio/flac', 'm4a' => 'audio/mp4',
        'ogg' => 'audio/ogg', 'wav' => 'audio/wav', 'aac' => 'audio/aac',
        'opus' => 'audio/opus',
    ];

    return [
        '@id' => 's-' . $s['id'],
        '@parent' => 'al-' . $s['album_id'],
        '@isDir' => 'false',
        '@title' => $s['title'],
        '@album' => $s['album_name'] ?? '',
        '@artist' => $s['artist_name'] ?? '',
        '@track' => (int)($s['track_number'] ?? 0),
        '@year' => (int)($s['year'] ?? 0),
        '@coverArt' => 'al-' . $s['album_id'],
        '@size' => (int)($s['file_size'] ?? 0),
        '@contentType' => $mimeTypes[$ext] ?? 'audio/mpeg',
        '@suffix' => $ext,
        '@duration' => (int)($s['duration'] ?? 0),
        '@path' => ($s['artist_name'] ?? '') . '/' . ($s['album_name'] ?? '') . '/' . ($s['title'] ?? '') . '.' . $ext,
        '@albumId' => 'al-' . $s['album_id'],
        '@artistId' => 'ar-' . ($s['artist_id'] ?? ''),
        '@type' => 'music',
    ];
}

function subsonicOk($data, $format) {
    $response = array_merge([
        '@status' => 'ok',
        '@version' => '1.16.1',
        '@type' => 'gullify',
        '@serverVersion' => '1.0.0',
        '@openSubsonic' => true,
    ], $data);

    if ($format === 'json') {
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode(['subsonic-response' => stripAtKeys($response)], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
    } else {
        header('Content-Type: application/xml; charset=utf-8');
        echo '<?xml version="1.0" encoding="UTF-8"?>' . "\n";
        echo '<subsonic-response xmlns="http://subsonic.org/restapi"';
        foreach ($response as $k => $v) {
            if (str_starts_with($k, '@')) {
                $xmlVal = is_bool($v) ? ($v ? 'true' : 'false') : htmlspecialchars((string)$v);
                echo ' ' . substr($k, 1) . '="' . $xmlVal . '"';
            }
        }
        echo '>' . "\n";
        foreach ($response as $k => $v) {
            if (!str_starts_with($k, '@')) {
                xmlElement($k, $v);
            }
        }
        echo '</subsonic-response>';
    }
    exit;
}

function subsonicError($code, $message, $format) {
    $response = [
        '@status' => 'failed',
        '@version' => '1.16.1',
        '@type' => 'gullify',
        '@serverVersion' => '1.0.0',
        '@openSubsonic' => true,
        'error' => ['@code' => $code, '@message' => $message],
    ];

    if ($format === 'json') {
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode(['subsonic-response' => stripAtKeys($response)], JSON_UNESCAPED_UNICODE);
    } else {
        header('Content-Type: application/xml; charset=utf-8');
        echo '<?xml version="1.0" encoding="UTF-8"?>' . "\n";
        echo '<subsonic-response xmlns="http://subsonic.org/restapi"';
        foreach ($response as $k => $v) {
            if (str_starts_with($k, '@')) {
                echo ' ' . substr($k, 1) . '="' . htmlspecialchars($v) . '"';
            }
        }
        echo '>';
        echo '<error code="' . $code . '" message="' . htmlspecialchars($message) . '"/>';
        echo '</subsonic-response>';
    }
    exit;
}

function xmlElement($name, $value, $indent = '  ') {
    if (is_array($value)) {
        // Check if it's an attributes-bearing element
        $attrs = [];
        $children = [];
        $textValue = null;
        foreach ($value as $k => $v) {
            if ($k === '_value') {
                $textValue = $v;
            } elseif (str_starts_with($k, '@')) {
                $attrs[substr($k, 1)] = $v;
            } else {
                $children[$k] = $v;
            }
        }

        if (!empty($attrs) || !empty($children) || $textValue !== null) {
            echo $indent . '<' . $name;
            foreach ($attrs as $ak => $av) {
                $xmlVal = is_bool($av) ? ($av ? 'true' : 'false') : htmlspecialchars((string)$av);
                echo ' ' . $ak . '="' . $xmlVal . '"';
            }
            if ($textValue !== null) {
                echo '>' . htmlspecialchars((string)$textValue) . '</' . $name . '>' . "\n";
            } elseif (empty($children)) {
                echo '/>' . "\n";
            } else {
                echo '>' . "\n";
                foreach ($children as $ck => $cv) {
                    if (is_array($cv) && isset($cv[0])) {
                        // Repeated elements
                        foreach ($cv as $item) {
                            if (is_array($item)) {
                                xmlElement($ck, $item, $indent . '  ');
                            } else {
                                echo $indent . '  <' . $ck . '>' . htmlspecialchars((string)$item) . '</' . $ck . '>' . "\n";
                            }
                        }
                    } elseif (is_array($cv)) {
                        xmlElement($ck, $cv, $indent . '  ');
                    } else {
                        echo $indent . '  <' . $ck . '>' . htmlspecialchars((string)$cv) . '</' . $ck . '>' . "\n";
                    }
                }
                echo $indent . '</' . $name . '>' . "\n";
            }
        } else {
            // It's a list of repeated elements
            foreach ($value as $item) {
                if (is_array($item)) {
                    xmlElement($name, $item, $indent);
                } else {
                    echo $indent . '<' . $name . '>' . htmlspecialchars((string)$item) . '</' . $name . '>' . "\n";
                }
            }
        }
    } else {
        echo $indent . '<' . $name . '>' . htmlspecialchars((string)$value) . '</' . $name . '>' . "\n";
    }
}
