<?php
/**
 * Gullify - Image Serving Endpoint
 * Serves artist/album artwork from local cache, database or filesystem.
 */
require_once __DIR__ . '/../src/AppConfig.php';
require_once __DIR__ . '/../src/PathHelper.php';
require_once __DIR__ . '/../src/Storage/StorageFactory.php';

header('Access-Control-Allow-Origin: *');

try {
    $albumId = $_GET['album_id'] ?? null;
    $artistId = $_GET['artist_id'] ?? null;
    $cachePath = AppConfig::getDataPath() . '/cache/artwork';

    // Redimensionnement carré optionnel (Android Auto / notification système) :
    // ?size=NNN renvoie l'image recadrée en carré centré de NNN px de côté,
    // comme le fait `BoxFit.cover` dans l'app. La version web/mobile qui ne
    // passe pas `size` continue de recevoir la source telle quelle.
    $reqSize = isset($_GET['size']) ? (int)$_GET['size'] : 0;
    if ($reqSize > 0) $reqSize = max(96, min(1024, $reqSize));
    $GLOBALS['reqSize'] = $reqSize;

    if ($albumId) {
        // 0. Version carrée déjà générée pour cette taille : la servir telle quelle.
        if ($reqSize > 0) {
            $GLOBALS['sqCacheFile'] = $cachePath . '/album_' . $albumId . '_sq' . $reqSize . '.jpg';
            if (file_exists($GLOBALS['sqCacheFile'])) serveResizedCache($GLOBALS['sqCacheFile']);
        }

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
        // 0. Version carrée déjà générée pour cette taille : la servir telle quelle.
        if ($reqSize > 0) {
            $GLOBALS['sqCacheFile'] = $cachePath . '/artist_' . $artistId . '_sq' . $reqSize . '.jpg';
            if (file_exists($GLOBALS['sqCacheFile'])) serveResizedCache($GLOBALS['sqCacheFile']);
        }

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
    // Le client mobile préfère un 404 (il affiche sa propre icône) au
    // placeholder mascotte destiné au web.
    if (($_GET['fallback'] ?? '') === '404') { http_response_code(404); exit; }
    $path = __DIR__ . '/logo_gullify_bo.png';
    if (!file_exists($path)) { http_response_code(404); exit; }
    header('Content-Type: image/png');
    header('Cache-Control: public, max-age=300'); // 5 min — re-fetch when real art is available
    header('Content-Length: ' . filesize($path));
    readfile($path);
    exit;
}

function serveLocalFile($path) {
    $bin = @file_get_contents($path);
    if ($bin === false) servePlaceholder();
    $mime = str_ends_with($path, '.png') ? 'image/png' : 'image/jpeg';
    emit($bin, $mime);
}

/// Sert une version carrée déjà mise en cache : pas de re-traitement.
function serveResizedCache($path) {
    $bin = @file_get_contents($path);
    if ($bin === false) return; // fichier disparu : on retombe sur la génération normale
    $etag = '"' . substr(md5($bin), 0, 16) . '"';
    header('Content-Type: image/jpeg');
    header('Cache-Control: no-cache');
    header('ETag: ' . $etag);
    if (trim($_SERVER['HTTP_IF_NONE_MATCH'] ?? '') === $etag) { http_response_code(304); exit; }
    header('Content-Length: ' . strlen($bin));
    echo $bin;
    exit;
}

function serveBase64($data) {
    $mime = 'image/jpeg';
    if (str_starts_with($data, 'iVBORw0KGgo')) $mime = 'image/png';
    $bin = base64_decode($data);
    emit($bin, $mime);
}

function serveBinary($bin, $mime = 'image/jpeg') {
    emit($bin, $mime);
}

/// Sortie commune : applique le recadrage carré si `?size` est demandé, puis
/// émet avec un ETag basé sur le contenu (revalidation 304 bon marché).
function emit($bin, $mime = 'image/jpeg') {
    $size = $GLOBALS['reqSize'] ?? 0;
    if ($size > 0) {
        $square = squareCrop($bin, $size);
        if ($square !== null) {
            $bin = $square;
            $mime = 'image/jpeg';
            // Mémorise la version carrée pour éviter de retraiter à chaque requête
            // (Android Auto redemande souvent la même pochette).
            $sqFile = $GLOBALS['sqCacheFile'] ?? '';
            if ($sqFile) {
                $dir = dirname($sqFile);
                if (!is_dir($dir)) @mkdir($dir, 0775, true);
                @file_put_contents($sqFile, $bin);
            }
        }
    }
    // Use the content hash as ETag so updates invalidate the browser cache.
    // no-cache here is "must revalidate" — when the data hasn't changed the
    // browser gets a fast 304 (no body); when it has, it gets the new bytes.
    $etag = '"' . substr(md5($bin), 0, 16) . '"';
    header('Content-Type: ' . $mime);
    header('Cache-Control: no-cache');
    header('ETag: ' . $etag);
    header('Last-Modified: ' . gmdate('D, d M Y H:i:s', time()) . ' GMT');
    if (trim($_SERVER['HTTP_IF_NONE_MATCH'] ?? '') === $etag) {
        http_response_code(304);
        exit;
    }
    header('Content-Length: ' . strlen($bin));
    echo $bin;
    exit;
}

/// Recadre l'image en carré centré de `$size` px de côté (équivalent
/// `BoxFit.cover`). Renvoie un JPEG binaire, ou null si GD/décodage échoue.
function squareCrop($bin, $size) {
    if (!function_exists('imagecreatefromstring')) return null;
    $src = @imagecreatefromstring($bin);
    if (!$src) return null;
    $w = imagesx($src);
    $h = imagesy($src);
    if ($w < 1 || $h < 1) { imagedestroy($src); return null; }
    $side = min($w, $h);
    $sx = (int)(($w - $side) / 2);
    $sy = (int)(($h - $side) / 2);
    $dst = imagecreatetruecolor($size, $size);
    imagecopyresampled($dst, $src, 0, 0, $sx, $sy, $size, $size, $side, $side);
    ob_start();
    imagejpeg($dst, null, 88);
    $out = ob_get_clean();
    imagedestroy($src);
    imagedestroy($dst);
    return ($out !== false && $out !== '') ? $out : null;
}
