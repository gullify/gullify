<?php
/**
 * Gullify - Lyrics Endpoint
 * 1. ID3 embedded lyrics (USLT tag)
 * 2. LRClib.net API (free, no key, pure PHP curl)
 * 3. Musixmatch Python script (optional, if installed)
 */
header('Content-Type: application/json');

require_once __DIR__ . '/../src/AppConfig.php';
require_once __DIR__ . '/../src/Storage/StorageFactory.php';

$relativePath = $_GET['path'] ?? '';

if (!$relativePath) {
    echo json_encode(['success' => false, 'error' => 'Missing path parameter']);
    exit;
}

try {
    $db = AppConfig::getDB();

    // Resolve owner + metadata from DB
    $stmt = $db->prepare('
        SELECT a.user, a.name AS artist_name, s.title
        FROM songs s
        JOIN albums al ON s.album_id = al.id
        JOIN artists a  ON al.artist_id = a.id
        WHERE s.file_path = ?
        LIMIT 1
    ');
    $stmt->execute([$relativePath]);
    $songInfo = $stmt->fetch();

    $lyrics = null;
    $artist = $songInfo['artist_name'] ?? '';
    $title  = $songInfo['title']       ?? '';

    // ----------------------------------------------------------------
    // Step 1: ID3 embedded lyrics (local storage only)
    // ----------------------------------------------------------------
    if ($songInfo && ($storage = StorageFactory::forUser($songInfo['user']))->getType() === 'local') {
        $absolutePath = $storage->getPathBase() . '/' . $relativePath;

        if (file_exists($absolutePath)) {
            $vendorPath = AppConfig::getVendorPath();
            if (file_exists($vendorPath . '/getid3/getid3.php')) {
                require_once $vendorPath . '/getid3/getid3.php';
                $getID3   = new getID3();
                $fileInfo = $getID3->analyze($absolutePath);
                getid3_lib::CopyTagsToComments($fileInfo);

                // USLT (unsynchronized lyrics)
                foreach (['tags.id3v2.unsynchronized_lyric', 'comments.unsynchronized_lyric'] as $dotKey) {
                    $val = array_reduce(explode('.', $dotKey), fn($carry, $k) => is_array($carry) ? ($carry[$k] ?? null) : null, $fileInfo);
                    if ($val) { $lyrics = is_array($val) ? $val[0] : $val; break; }
                }
                // Lyrics3
                if (!$lyrics) $lyrics = $fileInfo['lyrics3']['raw']['LYR'] ?? null;
                // Generic comment field
                if (!$lyrics && !empty($fileInfo['comments']['lyrics'])) {
                    $val    = $fileInfo['comments']['lyrics'];
                    $lyrics = is_array($val) ? $val[0] : $val;
                }

                // Enrich artist/title from tags if DB had nothing
                if (!$artist) $artist = $fileInfo['tags']['id3v2']['artist'][0] ?? ($fileInfo['comments']['artist'][0] ?? '');
                if (!$title)  $title  = $fileInfo['tags']['id3v2']['title'][0]  ?? ($fileInfo['comments']['title'][0]  ?? '');
            }
        }
    }

    if ($lyrics) {
        echo json_encode(['success' => true, 'lyrics' => trim($lyrics), 'source' => 'id3']);
        exit;
    }

    // ----------------------------------------------------------------
    // Step 2: LRClib.net (free public API, no key required)
    // ----------------------------------------------------------------
    if ($artist && $title && function_exists('curl_init')) {
        $url = 'https://lrclib.net/api/get?'
             . 'artist_name=' . urlencode($artist)
             . '&track_name=' . urlencode($title);

        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => 8,
            CURLOPT_USERAGENT      => 'Gullify/1.0 (self-hosted music player)',
            CURLOPT_HTTPHEADER     => ['Accept: application/json'],
        ]);
        $body   = curl_exec($ch);
        $status = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($status === 200 && $body) {
            $data = json_decode($body, true);
            // Prefer plain text; fall back to synced LRC (strip timestamps)
            $plain = $data['plainLyrics'] ?? '';
            $synced = $data['syncedLyrics'] ?? '';

            if ($plain) {
                echo json_encode(['success' => true, 'lyrics' => trim($plain), 'source' => 'lrclib']);
                exit;
            }
            if ($synced) {
                // Strip [mm:ss.xx] timestamps from synced lyrics
                $clean = preg_replace('/^\[\d+:\d+\.\d+\]\s?/m', '', $synced);
                echo json_encode(['success' => true, 'lyrics' => trim($clean), 'source' => 'lrclib']);
                exit;
            }
        }
    }

    // ----------------------------------------------------------------
    // Step 3: Musixmatch Python fallback (if module is installed)
    // ----------------------------------------------------------------
    if ($artist && $title) {
        $pythonScript = AppConfig::getPythonPath() . '/fetch_lyrics_musixmatch.py';
        if (file_exists($pythonScript)) {
            // Prefer venv python (has musicxmatch-api installed) over system python
            $python = is_executable('/usr/local/bin/python3-venv') ? 'python3-venv' : 'python3';
            $cmd    = sprintf('%s %s %s %s 2>/dev/null',
                $python,
                escapeshellarg($pythonScript),
                escapeshellarg($artist),
                escapeshellarg($title)
            );
            $output = shell_exec($cmd);
            $result = json_decode($output, true);

            if ($result && !empty($result['success']) && !empty($result['lyrics'])) {
                echo json_encode([
                    'success'        => true,
                    'lyrics'         => $result['lyrics'],
                    'source'         => 'musixmatch',
                    'matched_artist' => $result['artist_name'] ?? '',
                    'matched_title'  => $result['track_name']  ?? '',
                ]);
                exit;
            }
        }
    }

    echo json_encode(['success' => true, 'lyrics' => null]);

} catch (Exception $e) {
    echo json_encode(['success' => false, 'error' => $e->getMessage()]);
}
