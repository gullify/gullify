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
