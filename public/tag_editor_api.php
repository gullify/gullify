<?php
/**
 * Gullify - Tag Editor API
 */
require_once __DIR__ . '/../src/AppConfig.php';
require_once __DIR__ . '/../src/Database.php';
require_once __DIR__ . '/../src/TagEditor.php';
require_once __DIR__ . '/../src/ArtworkManager.php';
require_once __DIR__ . '/../src/auth_required.php';

header('Content-Type: application/json');

// Get data from POST or JSON body
$inputRaw = file_get_contents('php://input');
$json = json_decode($inputRaw, true);
$action = $_GET['action'] ?? ($json['action'] ?? '');
$user = $_SESSION['username'];

if (!$action) {
    echo json_encode(['success' => false, 'error' => 'No action provided', 'debug_input' => $inputRaw]);
    exit;
}

try {
    $editor = new TagEditor();

    switch ($action) {
        case 'save_tags':
        case 'save_song':
            $songId = intval($_POST['song_id'] ?? ($json['song_id'] ?? 0));
            $tags = $json['tags'] ?? [
                'title' => $_POST['title'] ?? null,
                'artist' => $_POST['artist'] ?? null,
                'album' => $_POST['album'] ?? null,
                'year' => $_POST['year'] ?? null,
                'track_number' => $_POST['track_number'] ?? null,
                'genre' => $_POST['genre'] ?? null,
            ];
            $tags = array_filter($tags, fn($v) => !is_null($v));

            // Normalize 'track' → 'track_number' (JS sends 'track')
            if (isset($tags['track']) && !isset($tags['track_number'])) {
                $tags['track_number'] = $tags['track'];
            }

            $success = $editor->updateSongTags($songId, $tags);

            $data = [];
            $renameFile  = !empty($json['rename_file']);
            $newFilename = $json['new_filename'] ?? null;
            if ($success && $renameFile && $newFilename) {
                $renameResult = $editor->renameFile($songId, $newFilename);
                $data = $renameResult['data'] ?? [];
            }

            echo json_encode(['success' => $success, 'data' => $data]);
            break;

        case 'get_album_tags':
            $albumId = intval($_GET['album_id'] ?? ($json['album_id'] ?? 0));
            if (!$albumId) {
                echo json_encode(['success' => false, 'error' => 'Album ID required']);
                break;
            }
            $data = $editor->getAlbumTags($albumId);
            if ($data) {
                echo json_encode(['success' => true, 'data' => $data]);
            } else {
                echo json_encode(['success' => false, 'error' => 'Album not found']);
            }
            break;

        case 'batch_save':
            $songsData = $json['songs'] ?? [];
            if (empty($songsData)) {
                echo json_encode(['success' => false, 'error' => 'No songs provided']);
                break;
            }
            
            $results = $editor->batchSave($songsData);
            echo json_encode(['success' => true, 'data' => $results]);
            break;

        case 'rename_file':
            $songId = intval($json['song_id'] ?? 0);
            $newFilename = $json['new_filename'] ?? '';
            if (!$songId || !$newFilename) {
                echo json_encode(['success' => false, 'error' => 'Song ID and new filename required']);
                break;
            }
            $result = $editor->renameFile($songId, $newFilename);
            echo json_encode($result);
            break;

        case 'save_album':
            $albumId = intval($_POST['album_id'] ?? ($json['album_id'] ?? 0));
            $tags = $json['tags'] ?? [
                'artist' => $_POST['artist'] ?? null,
                'album' => $_POST['album'] ?? null,
                'year' => $_POST['year'] ?? null,
                'genre' => $_POST['genre'] ?? null,
            ];
            $tags = array_filter($tags, fn($v) => !is_null($v));

            $db = AppConfig::getDB();
            $stmt = $db->prepare("SELECT id FROM songs WHERE album_id = ?");
            $stmt->execute([$albumId]);
            $songIds = $stmt->fetchAll(PDO::FETCH_COLUMN);

            $successCount = 0;
            foreach ($songIds as $songId) {
                if ($editor->updateSongTags((int)$songId, $tags)) {
                    $successCount++;
                }
            }
            echo json_encode(['success' => $successCount > 0, 'updated' => $successCount]);
            break;

        case 'get_ytmusic_artist':
            $query = trim($_GET['artist'] ?? '');
            if (!$query) {
                echo json_encode(['success' => false, 'error' => 'Query required']);
                break;
            }

            $pythonScript = AppConfig::getPythonPath() . '/ytmusic_search.py';
            $pythonBin    = file_exists('/opt/ytdlp/bin/python3') ? '/opt/ytdlp/bin/python3' : 'python3';
            $cmd = $pythonBin . ' ' . escapeshellarg($pythonScript)
                 . ' album ' . escapeshellarg($query) . ' 2>/dev/null';
            $output = shell_exec($cmd);

            if (!$output) {
                echo json_encode(['success' => false, 'error' => 'No response from ytmusic_search.py']);
                break;
            }

            $data = json_decode($output, true);
            if (!$data || empty($data['results'])) {
                echo json_encode(['success' => true, 'data' => ['albums' => []]]);
                break;
            }

            // Transform to the format expected by the JS
            $albums = array_map(fn($r) => [
                'title'     => $r['title']     ?? '',
                'artist'    => $r['artist']    ?? '',
                'year'      => $r['year']      ?? '',
                'thumbnail' => $r['thumbnail'] ?? '',
                'browseId'  => $r['browseId']  ?? '',
            ], $data['results']);

            echo json_encode(['success' => true, 'data' => ['albums' => $albums]]);
            break;

        case 'update_artwork':
            $albumId = intval($_POST['album_id'] ?? 0);
            if (!$albumId) {
                echo json_encode(['success' => false, 'error' => 'album_id required']);
                break;
            }

            // Verify album belongs to current user
            $db = AppConfig::getDB();
            $stmt = $db->prepare("
                SELECT al.id FROM albums al
                JOIN artists ar ON al.artist_id = ar.id
                WHERE al.id = ? AND ar.user = ?
            ");
            $stmt->execute([$albumId, $user]);
            if (!$stmt->fetch()) {
                echo json_encode(['success' => false, 'error' => 'Album not found']);
                break;
            }

            $imageData = null;
            if (!empty($_FILES['artwork']['tmp_name'])) {
                // Uploaded file
                $mime = mime_content_type($_FILES['artwork']['tmp_name']);
                if (!str_starts_with($mime, 'image/')) {
                    echo json_encode(['success' => false, 'error' => 'Le fichier doit être une image']);
                    break;
                }
                $imageData = file_get_contents($_FILES['artwork']['tmp_name']);
            } elseif (!empty($_POST['artwork_url'])) {
                // URL (must be http/https only)
                $url = filter_var($_POST['artwork_url'], FILTER_VALIDATE_URL);
                if (!$url || !preg_match('#^https?://#i', $url)) {
                    echo json_encode(['success' => false, 'error' => 'URL invalide']);
                    break;
                }
                $imageData = @file_get_contents($url);
            }

            if (!$imageData) {
                echo json_encode(['success' => false, 'error' => 'Aucune image fournie']);
                break;
            }

            $artworkManager = new ArtworkManager();
            $ok = $artworkManager->saveAlbumArtwork($albumId, $imageData);
            echo json_encode(['success' => $ok, 'album_id' => $albumId, 'cache_bust' => time()]);
            break;

        case 'update_artist_image':
            $artistId = intval($_POST['artist_id'] ?? 0);
            if (!$artistId) {
                echo json_encode(['success' => false, 'error' => 'artist_id required']);
                break;
            }

            $db = AppConfig::getDB();
            $stmt = $db->prepare("SELECT id FROM artists WHERE id = ? AND user = ?");
            $stmt->execute([$artistId, $user]);
            if (!$stmt->fetch()) {
                echo json_encode(['success' => false, 'error' => 'Artist not found']);
                break;
            }

            $imageData = null;
            if (!empty($_FILES['artwork']['tmp_name'])) {
                $mime = mime_content_type($_FILES['artwork']['tmp_name']);
                if (!str_starts_with($mime, 'image/')) {
                    echo json_encode(['success' => false, 'error' => 'Le fichier doit être une image']);
                    break;
                }
                $imageData = file_get_contents($_FILES['artwork']['tmp_name']);
            } elseif (!empty($_POST['artwork_url'])) {
                $url = filter_var($_POST['artwork_url'], FILTER_VALIDATE_URL);
                if (!$url || !preg_match('#^https?://#i', $url)) {
                    echo json_encode(['success' => false, 'error' => 'URL invalide']);
                    break;
                }
                $imageData = @file_get_contents($url);
            }

            if (!$imageData) {
                echo json_encode(['success' => false, 'error' => 'Aucune image fournie']);
                break;
            }

            $artworkManager = new ArtworkManager();
            $ok = $artworkManager->saveArtistImage($artistId, $imageData);
            echo json_encode(['success' => $ok, 'artist_id' => $artistId, 'cache_bust' => time()]);
            break;

        case 'get_ytmusic_artist_image':
            $query = trim($_GET['artist'] ?? '');
            if (!$query) {
                echo json_encode(['success' => false, 'error' => 'Query required']);
                break;
            }

            $pythonScript = AppConfig::getPythonPath() . '/ytmusic_search.py';
            $pythonBin    = file_exists('/opt/ytdlp/bin/python3') ? '/opt/ytdlp/bin/python3' : 'python3';
            $cmd = $pythonBin . ' ' . escapeshellarg($pythonScript)
                 . ' artist ' . escapeshellarg($query) . ' 2>/dev/null';
            $output = shell_exec($cmd);

            if (!$output) {
                echo json_encode(['success' => false, 'error' => 'No response from ytmusic_search.py']);
                break;
            }

            $data = json_decode($output, true);
            if (!$data || empty($data['results'])) {
                echo json_encode(['success' => true, 'data' => ['artists' => []]]);
                break;
            }

            $artists = array_map(fn($r) => [
                'name'      => $r['name']      ?? $r['title'] ?? '',
                'thumbnail' => $r['thumbnail'] ?? '',
            ], $data['results']);
            echo json_encode(['success' => true, 'data' => ['artists' => $artists]]);
            break;

        default:
            echo json_encode(['success' => false, 'error' => 'Unknown action: ' . $action]);
    }
} catch (Exception $e) {
    echo json_encode(['success' => false, 'error' => $e->getMessage()]);
}
