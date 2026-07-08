<?php
/**
 * Gullify - Download Album API
 * Manages YouTube album downloads in background
 * Migrated from download_album_api.php
 */

require_once __DIR__ . '/../../src/AppConfig.php';

header('Content-Type: application/json');

$action = $_GET['action'] ?? $_POST['action'] ?? 'list';

// Ensure locale is UTF-8 to preserve accents
setlocale(LC_ALL, 'en_CA.UTF-8', 'en_US.UTF-8', 'fr_CA.UTF-8', 'fr_FR.UTF-8', 'C.UTF-8');
putenv('LC_ALL=en_CA.UTF-8');

$downloadDir = AppConfig::getDataPath() . '/downloads/';
$queueScript = AppConfig::getAppRoot() . '/scripts/process-queue.sh';

// Ensure download directory exists
if (!is_dir($downloadDir)) {
    @mkdir($downloadDir, 0755, true);
}

function sanitizeForPath($name) {
    $name = preg_replace('/\s*[\/\\\\]+\s*/', ' - ', $name);
    $name = preg_replace('/[<>:"|?*]/', '', $name);
    $name = preg_replace('/\s+/', ' ', $name);
    return trim($name);
}

function extractMetadata($url) {
    $command = 'timeout 20 yt-dlp --print "%(uploader)s|%(playlist_title)s|%(title)s" --no-download ' . escapeshellarg($url) . ' 2>/dev/null | head -1';
    $result = shell_exec($command);

    if ($result && strlen(trim($result)) > 0) {
        $parts = explode('|', trim($result));
        $uploader = isset($parts[0]) ? trim($parts[0]) : '';
        $playlistTitle = isset($parts[1]) ? trim($parts[1]) : '';
        $videoTitle = isset($parts[2]) ? trim($parts[2]) : '';

        $artist = $uploader;
        $album = $playlistTitle ? $playlistTitle : $videoTitle;

        $artist = preg_replace('/\s*-\s*Topic$/', '', $artist);
        $artist = preg_replace('/Official$/', '', $artist);
        $artist = trim($artist);

        $album = preg_replace('/^Album\s*-\s*/i', '', $album);
        $album = trim($album);

        if (strlen($artist) > 2 && strlen($album) > 2) {
            return ['artist' => sanitizeForPath($artist), 'album' => sanitizeForPath($album)];
        }
    }

    return null;
}

try {
    switch ($action) {
        case 'start':
            $url = $_POST['url'] ?? '';
            $user = $_POST['user'] ?? '';
            $artistId = $_POST['artist_id'] ?? '';
            $artistName = $_POST['artist_name'] ?? '';
            $albumName = $_POST['album_name'] ?? '';

            if (empty($url) || empty($user) || empty($artistId)) {
                throw new Exception('Missing required parameters');
            }

            if (empty($artistName) || empty($albumName)) {
                $metadata = extractMetadata($url);
                if (!$metadata) {
                    throw new Exception('Failed to extract metadata from URL');
                }
                $artistName = $metadata['artist'];
                $albumName = $metadata['album'];
            } else {
                $artistName = sanitizeForPath($artistName);
                $albumName = sanitizeForPath($albumName);
            }

            $downloadId = uniqid('dl_', true);

            $statusFile = $downloadDir . "{$downloadId}.json";
            $statusData = [
                'id' => $downloadId,
                'status' => 'queued',
                'progress' => 0,
                'message' => 'En attente de demarrage...',
                'artist' => $artistName,
                'album' => $albumName,
                'user' => $user,
                'artist_id' => $artistId,
                'url' => $url,
                'created_at' => date('Y-m-d H:i:s'),
                'updated_at' => date('Y-m-d H:i:s')
            ];

            file_put_contents($statusFile, json_encode($statusData, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE));
            chmod($statusFile, 0666);

            @exec(escapeshellarg($queueScript) . ' > /dev/null 2>&1 &');

            echo json_encode([
                'success' => true,
                'download_id' => $downloadId,
                'message' => 'Telechargement demarre'
            ]);
            break;

        case 'search_ytmusic':
            $query = trim($_GET['query'] ?? '');
            if (!$query) {
                echo json_encode(['success' => false, 'error' => 'query required']);
                break;
            }
            $limit = (int)($_GET['limit'] ?? 10);
            if ($limit < 1)  { $limit = 10; }
            if ($limit > 50) { $limit = 50; }
            $pythonScript = AppConfig::getPythonPath() . '/ytmusic_search.py';
            $pythonBin    = file_exists('/opt/ytdlp/bin/python3') ? '/opt/ytdlp/bin/python3' : 'python3';
            $cmd = $pythonBin . ' ' . escapeshellarg($pythonScript)
                 . ' album ' . escapeshellarg($query) . ' ' . escapeshellarg((string)$limit)
                 . ' 2>/dev/null';
            $output = shell_exec($cmd);
            if (!$output) {
                echo json_encode(['success' => true, 'data' => ['albums' => []]]);
                break;
            }
            $data = json_decode($output, true);
            $albums = array_map(fn($r) => [
                'title'     => $r['title']     ?? '',
                'artist'    => $r['artist']    ?? '',
                'year'      => $r['year']      ?? '',
                'thumbnail' => $r['thumbnail'] ?? '',
                'browseId'  => $r['browseId']  ?? '',
            ], $data['results'] ?? []);
            echo json_encode(['success' => true, 'data' => ['albums' => $albums]]);
            break;

        case 'search_songs':
            // Chansons seules sur YouTube Music (téléchargement à l'unité :
            // l'app construit ensuite https://music.youtube.com/watch?v=ID).
            $query = trim($_GET['query'] ?? '');
            if (!$query) {
                echo json_encode(['success' => false, 'error' => 'query required']);
                break;
            }
            $limit = (int)($_GET['limit'] ?? 10);
            if ($limit < 1)  { $limit = 10; }
            if ($limit > 50) { $limit = 50; }
            $pythonScript = AppConfig::getPythonPath() . '/ytmusic_search.py';
            $pythonBin    = file_exists('/opt/ytdlp/bin/python3') ? '/opt/ytdlp/bin/python3' : 'python3';
            $cmd = $pythonBin . ' ' . escapeshellarg($pythonScript)
                 . ' song ' . escapeshellarg($query) . ' ' . escapeshellarg((string)$limit)
                 . ' 2>/dev/null';
            $output = shell_exec($cmd);
            if (!$output) {
                echo json_encode(['success' => true, 'data' => ['songs' => []]]);
                break;
            }
            $data = json_decode($output, true);
            $songs = array_values(array_filter(array_map(fn($r) => [
                'title'     => $r['title']     ?? '',
                'artist'    => $r['artist']    ?? '',
                'album'     => $r['album']     ?? '',
                'duration'  => $r['duration']  ?? '',
                'thumbnail' => $r['thumbnail'] ?? '',
                'videoId'   => $r['videoId']   ?? '',
            ], $data['results'] ?? []), fn($s) => $s['videoId'] !== ''));
            echo json_encode(['success' => true, 'data' => ['songs' => $songs]]);
            break;

        case 'search_artists':
            // Artistes sur YouTube Music (recherche, onglet Recherche). Au tap,
            // l'app ouvre la discographie de l'artiste (recherche d'albums).
            $query = trim($_GET['query'] ?? '');
            if (!$query) {
                echo json_encode(['success' => false, 'error' => 'query required']);
                break;
            }
            $limit = (int)($_GET['limit'] ?? 10);
            if ($limit < 1)  { $limit = 10; }
            if ($limit > 50) { $limit = 50; }
            $pythonScript = AppConfig::getPythonPath() . '/ytmusic_search.py';
            $pythonBin    = file_exists('/opt/ytdlp/bin/python3') ? '/opt/ytdlp/bin/python3' : 'python3';
            $cmd = $pythonBin . ' ' . escapeshellarg($pythonScript)
                 . ' artist ' . escapeshellarg($query) . ' ' . escapeshellarg((string)$limit)
                 . ' 2>/dev/null';
            $output = shell_exec($cmd);
            if (!$output) {
                echo json_encode(['success' => true, 'data' => ['artists' => []]]);
                break;
            }
            $data = json_decode($output, true);
            $artists = array_values(array_filter(array_map(fn($r) => [
                'name'      => $r['name']      ?? '',
                'browseId'  => $r['browseId']  ?? '',
                'thumbnail' => $r['thumbnail'] ?? '',
            ], $data['results'] ?? []), fn($a) => $a['name'] !== ''));
            echo json_encode(['success' => true, 'data' => ['artists' => $artists]]);
            break;

        case 'artist_albums':
            // Discographie réelle d'un artiste (albums + singles) via son
            // browseId : au tap sur un artiste, l'app affiche SES albums.
            $browseId = trim($_GET['browse_id'] ?? '');
            if (!$browseId) {
                echo json_encode(['success' => false, 'error' => 'browse_id required']);
                break;
            }
            $limit = (int)($_GET['limit'] ?? 50);
            if ($limit < 1)  { $limit = 50; }
            if ($limit > 100) { $limit = 100; }
            $pythonScript = AppConfig::getPythonPath() . '/ytmusic_search.py';
            $pythonBin    = file_exists('/opt/ytdlp/bin/python3') ? '/opt/ytdlp/bin/python3' : 'python3';
            $cmd = $pythonBin . ' ' . escapeshellarg($pythonScript)
                 . ' artist_albums ' . escapeshellarg($browseId) . ' ' . escapeshellarg((string)$limit)
                 . ' 2>/dev/null';
            $output = shell_exec($cmd);
            if (!$output) {
                echo json_encode(['success' => true, 'data' => ['albums' => []]]);
                break;
            }
            $data = json_decode($output, true);
            $albums = array_values(array_filter(array_map(fn($r) => [
                'title'     => $r['title']     ?? '',
                'artist'    => $r['artist']    ?? '',
                'year'      => $r['year']      ?? '',
                'thumbnail' => $r['thumbnail'] ?? '',
                'browseId'  => $r['browseId']  ?? '',
            ], $data['results'] ?? []), fn($a) => $a['browseId'] !== ''));
            echo json_encode(['success' => true, 'data' => ['albums' => $albums]]);
            break;

        case 'related_artists':
            // Artistes similaires (YouTube Music) à partir d'un nom d'artiste.
            $query = trim($_GET['query'] ?? '');
            if (!$query) {
                echo json_encode(['success' => false, 'error' => 'query required']);
                break;
            }
            $pythonScript = AppConfig::getPythonPath() . '/ytmusic_search.py';
            $pythonBin    = file_exists('/opt/ytdlp/bin/python3') ? '/opt/ytdlp/bin/python3' : 'python3';
            $cmd = $pythonBin . ' ' . escapeshellarg($pythonScript)
                 . ' related ' . escapeshellarg($query) . ' 2>/dev/null';
            $output = shell_exec($cmd);
            if (!$output) {
                echo json_encode(['success' => true, 'data' => ['artists' => []]]);
                break;
            }
            $data = json_decode($output, true);
            $artists = array_values(array_filter(array_map(fn($r) => [
                'name'      => $r['name']      ?? '',
                'browseId'  => $r['browseId']  ?? '',
                'thumbnail' => $r['thumbnail'] ?? '',
            ], $data['results'] ?? []), fn($a) => $a['name'] !== ''));
            echo json_encode(['success' => true, 'data' => ['artists' => $artists]]);
            break;

        case 'resolve_album':
            $browseId = trim($_GET['browse_id'] ?? '');
            if (!$browseId) {
                echo json_encode(['success' => false, 'error' => 'browse_id required']);
                break;
            }
            $pythonScript = AppConfig::getPythonPath() . '/ytmusic_search.py';
            $pythonBin = file_exists('/opt/ytdlp/bin/python3') ? '/opt/ytdlp/bin/python3' : 'python3';
            $cmd = $pythonBin . ' ' . escapeshellarg($pythonScript)
                 . ' album_details ' . escapeshellarg($browseId) . ' 2>/dev/null';
            $output = shell_exec($cmd);
            if (!$output) {
                echo json_encode(['success' => false, 'error' => 'Failed to resolve album']);
                break;
            }
            $data = json_decode($output, true);
            $album = $data['album'] ?? null;
            if (!$album || empty($album['audioPlaylistId'])) {
                echo json_encode(['success' => false, 'error' => 'No playlist found for this album']);
                break;
            }
            echo json_encode([
                'success' => true,
                'data' => [
                    'playlistUrl' => 'https://music.youtube.com/playlist?list=' . $album['audioPlaylistId'],
                    'artist' => $album['artist'] ?? '',
                    'title' => $album['title'] ?? '',
                    'year' => $album['year'] ?? '',
                    'track_count' => $album['track_count'] ?? 0,
                    'thumbnail' => $album['thumbnail'] ?? '',
                ]
            ]);
            break;

        case 'status':
            $downloadId = $_GET['download_id'] ?? '';

            if (empty($downloadId)) {
                throw new Exception('Missing download_id parameter');
            }

            $statusFile = $downloadDir . "{$downloadId}.json";

            if (!file_exists($statusFile)) {
                throw new Exception('Download not found');
            }

            $statusData = json_decode(file_get_contents($statusFile), true);

            echo json_encode([
                'success' => true,
                'download' => $statusData
            ]);
            break;

        case 'list':
            $filterUser = $_GET['user'] ?? '';
            $downloads = [];
            $files = glob($downloadDir . 'dl_*.json');

            foreach ($files as $file) {
                $data = json_decode(file_get_contents($file), true);
                if ($data && (!$filterUser || ($data['user'] ?? '') === $filterUser)) {
                    $downloads[] = $data;
                }
            }

            usort($downloads, function($a, $b) {
                return strtotime($b['created_at'] ?? '0') - strtotime($a['created_at'] ?? '0');
            });

            echo json_encode([
                'success' => true,
                'data' => $downloads,
                'count' => count($downloads)
            ]);
            break;

        case 'cancel':
            $downloadId = $_POST['download_id'] ?? '';

            if (empty($downloadId)) {
                throw new Exception('Missing download_id parameter');
            }

            $statusFile = $downloadDir . "{$downloadId}.json";

            if (!file_exists($statusFile)) {
                throw new Exception('Download not found');
            }

            $statusData = json_decode(file_get_contents($statusFile), true);
            $statusData['status'] = 'cancelled';
            $statusData['message'] = 'Annule par l\'utilisateur';
            $statusData['updated_at'] = date('Y-m-d H:i:s');

            file_put_contents($statusFile, json_encode($statusData, JSON_PRETTY_PRINT));

            echo json_encode([
                'success' => true,
                'message' => 'Download cancelled'
            ]);
            break;

        case 'retry':
            $downloadId = $_POST['download_id'] ?? '';

            if (empty($downloadId)) {
                throw new Exception('Missing download_id parameter');
            }

            $statusFile = $downloadDir . "{$downloadId}.json";

            if (!file_exists($statusFile)) {
                throw new Exception('Download not found');
            }

            $statusData = json_decode(file_get_contents($statusFile), true);

            if (!in_array($statusData['status'], ['error', 'cancelled'])) {
                throw new Exception('Only failed or cancelled downloads can be retried');
            }

            $statusData['status'] = 'queued';
            $statusData['progress'] = 0;
            $statusData['message'] = 'En attente de demarrage (reessai)...';
            $statusData['updated_at'] = date('Y-m-d H:i:s');

            file_put_contents($statusFile, json_encode($statusData, JSON_PRETTY_PRINT));

            @exec(escapeshellarg($queueScript) . ' > /dev/null 2>&1 &');

            echo json_encode([
                'success' => true,
                'message' => 'Download queued for retry'
            ]);
            break;

        case 'delete':
            $downloadId = $_POST['download_id'] ?? '';

            if (empty($downloadId)) {
                throw new Exception('Missing download_id parameter');
            }

            $statusFile = $downloadDir . "{$downloadId}.json";
            $logFile = $downloadDir . "{$downloadId}.log";

            if (!file_exists($statusFile)) {
                throw new Exception('Download not found');
            }

            @unlink($statusFile);
            @unlink($logFile);

            echo json_encode([
                'success' => true,
                'message' => 'Download deleted'
            ]);
            break;

        default:
            throw new Exception('Unknown action');
    }

} catch (Exception $e) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'error' => $e->getMessage()
    ]);
}
