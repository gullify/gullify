<?php
/**
 * Gullify - Image Serving Endpoint
 * Serves artist/album artwork from local cache, database or filesystem.
 */
require_once __DIR__ . '/../src/AppConfig.php';
require_once __DIR__ . '/../src/PathHelper.php';
require_once __DIR__ . '/../src/Storage/StorageFactory.php';

try {
    $albumId = $_GET['album_id'] ?? null;
    $artistId = $_GET['artist_id'] ?? null;
    $cachePath = AppConfig::getDataPath() . '/cache/artwork';

    if ($albumId) {
        // 1. Try local cache
        $cachedFile = $cachePath . '/album_' . $albumId . '.jpg';
        if (file_exists($cachedFile)) {
            serveLocalFile($cachedFile);
        }

        // 2. Try database (legacy base64)
        $conn = AppConfig::getDB();
        $stmt = $conn->prepare('SELECT artwork FROM albums WHERE id = ?');
        $stmt->execute([$albumId]);
        $imageData = $stmt->fetchColumn();
        if ($imageData && strlen($imageData) > 100) {
            serveBase64($imageData);
        }

        // 3. Last resort: Find on disk and cache on the fly
        $stmt = $conn->prepare('
            SELECT s.file_path, a.user
            FROM songs s
            JOIN albums al ON s.album_id = al.id
            JOIN artists a ON al.artist_id = a.id
            WHERE al.id = ?
            LIMIT 1
        ');
        $stmt->execute([$albumId]);
        $song = $stmt->fetch();

        if ($song) {
            $storage = StorageFactory::forUser($song['user']);
            $albumPath = dirname($storage->getPathBase() . '/' . $song['file_path']);
            $imageFiles = ['folder.jpg', 'Folder.jpg', 'cover.jpg', 'Cover.jpg', 'front.jpg', 'album.jpg'];

            foreach ($imageFiles as $f) {
                $fullImgPath = $albumPath . '/' . $f;
                if ($storage->fileExists($fullImgPath)) {
                    $data = $storage->readFile($fullImgPath);
                    if (!is_dir($cachePath)) mkdir($cachePath, 0775, true);
                    @file_put_contents($cachedFile, $data);
                    serveBinary($data);
                }
            }

            // 4. Extract embedded artwork from ID3 tags (local files only)
            if ($storage->getType() === 'local') {
                $fullFilePath = $storage->getPathBase() . '/' . $song['file_path'];
                if (file_exists($fullFilePath)) {
                    $vendorPath = AppConfig::getVendorPath();
                    if (file_exists($vendorPath . '/getid3/getid3.php')) {
                        require_once $vendorPath . '/getid3/getid3.php';
                        $getID3 = new getID3();
                        $fileInfo = $getID3->analyze($fullFilePath);
                        getid3_lib::CopyTagsToComments($fileInfo);
                        $pic = $fileInfo['comments']['picture'][0] ?? null;
                        if ($pic && !empty($pic['data'])) {
                            $mime = $pic['image_mime'] ?? 'image/jpeg';
                            $data = $pic['data'];
                            if (!is_dir($cachePath)) mkdir($cachePath, 0775, true);
                            @file_put_contents($cachedFile, $data);
                            serveBinary($data, $mime);
                        }
                    }
                }
            }
        }
    } elseif ($artistId) {
        // 1. Try local cache
        $cachedFile = $cachePath . '/artist_' . $artistId . '.jpg';
        if (file_exists($cachedFile)) {
            serveLocalFile($cachedFile);
        }

        // 2. Try database (legacy base64) — cache it as a proper file for future requests
        $conn = AppConfig::getDB();
        $stmt = $conn->prepare('SELECT image FROM artists WHERE id = ?');
        $stmt->execute([$artistId]);
        $imageData = $stmt->fetchColumn();
        if ($imageData && strlen($imageData) > 100) {
            // If it's a filename reference (e.g. "artist_123.jpg"), skip — cache file should exist
            if (!str_starts_with($imageData, 'artist_')) {
                $bin = base64_decode($imageData);
                if ($bin) {
                    if (!is_dir($cachePath)) mkdir($cachePath, 0775, true);
                    @file_put_contents($cachedFile, $bin);
                    serveBinary($bin);
                }
            }
        }

        // 3. Search in artist folder
        $stmt = $conn->prepare('SELECT name, user FROM artists WHERE id = ?');
        $stmt->execute([$artistId]);
        $artist = $stmt->fetch();
        if ($artist) {
            $storage = StorageFactory::forUser($artist['user']);
            $artistPath = $storage->getPathBase() . '/' . $artist['name'];
            $imageFiles = ['artist.jpg', 'folder.jpg', 'cover.jpg'];
            foreach ($imageFiles as $f) {
                $fullImgPath = $artistPath . '/' . $f;
                if ($storage->fileExists($fullImgPath)) {
                    $data = $storage->readFile($fullImgPath);
                    if (!is_dir($cachePath)) mkdir($cachePath, 0775, true);
                    @file_put_contents($cachedFile, $data);
                    serveBinary($data);
                }
            }
        }
    }

    // Default fallback: serve placeholder (no 404 in console)
    servePlaceholder();

} catch (Exception $e) {
    servePlaceholder();
}

function servePlaceholder() {
    $path = __DIR__ . '/logo_gullify_bo.png';
    if (!file_exists($path)) { http_response_code(404); exit; }
    header('Content-Type: image/png');
    header('Cache-Control: public, max-age=300'); // 5 min — re-fetch when real art is available
    header('Content-Length: ' . filesize($path));
    readfile($path);
    exit;
}

function serveLocalFile($path) {
    $mime = 'image/jpeg';
    if (str_ends_with($path, '.png')) $mime = 'image/png';
    $mtime = (int)filemtime($path);
    $etag  = '"' . $mtime . '"';

    header('Cache-Control: no-cache');
    header('Last-Modified: ' . gmdate('D, d M Y H:i:s', $mtime) . ' GMT');
    header('ETag: ' . $etag);

    $ifNoneMatch = trim($_SERVER['HTTP_IF_NONE_MATCH'] ?? '');
    $ifModSince  = $_SERVER['HTTP_IF_MODIFIED_SINCE'] ?? '';

    if ($ifNoneMatch === $etag || ($ifModSince && strtotime($ifModSince) >= $mtime)) {
        http_response_code(304);
        exit;
    }

    header('Content-Type: ' . $mime);
    header('Content-Length: ' . filesize($path));
    readfile($path);
    exit;
}

function serveBase64($data) {
    $mime = 'image/jpeg';
    if (str_starts_with($data, 'iVBORw0KGgo')) $mime = 'image/png';
    $bin = base64_decode($data);
    serveBinary($bin, $mime);
}

function serveBinary($bin, $mime = 'image/jpeg') {
    header('Content-Type: ' . $mime);
    header('Cache-Control: public, max-age=31536000');
    header('Content-Length: ' . strlen($bin));
    echo $bin;
    exit;
}
