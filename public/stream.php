<?php
/**
 * Gullify - Audio Streaming Endpoint
 * Supports HTTP range requests for seeking.
 * Uses StorageFactory to support both local and SFTP backends.
 */
require_once __DIR__ . '/../src/AppConfig.php';
require_once __DIR__ . '/../src/Storage/StorageInterface.php';
require_once __DIR__ . '/../src/Storage/LocalStorage.php';
require_once __DIR__ . '/../src/Storage/SFTPStorage.php';
require_once __DIR__ . '/../src/Storage/StorageFactory.php';

ini_set('max_execution_time', 0);

$relativePath = $_GET['path'] ?? '';
if ($relativePath === '') {
    header('HTTP/1.0 400 Bad Request');
    exit('Missing path parameter');
}

// ── Determine which user owns this file ──────────────────────────────────────
// Look up the song by file_path in the DB to find the owning user.
try {
    $db   = AppConfig::getDB();
    $stmt = $db->prepare(
        'SELECT ar.user
         FROM songs s
         JOIN albums al ON s.album_id = al.id
         JOIN artists ar ON al.artist_id = ar.id
         WHERE s.file_path = ?
         LIMIT 1'
    );
    $stmt->execute([$relativePath]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
} catch (Exception $e) {
    $row = null;
}

$username = $row['user'] ?? null;

// ── Resolve storage backend ───────────────────────────────────────────────────
if ($username) {
    $storage = StorageFactory::forUser($username);
} else {
    // Fallback: treat as local file under music base path
    $basePath = AppConfig::getMusicBasePath();
    $storage  = new LocalStorage($basePath, $basePath);
}

$filePath = $storage->getPathBase() . '/' . $relativePath;

// ── Security: for local storage, validate path stays within music base ────────
if ($storage->getType() === 'local') {
    $realBase = realpath($storage->getPathBase());
    $realFile = realpath($filePath);
    if ($realBase === false || $realFile === false || strpos($realFile, $realBase) !== 0) {
        header('HTTP/1.0 403 Forbidden');
        exit('Access denied');
    }
}

if (!$storage->fileExists($filePath)) {
    header('HTTP/1.0 404 Not Found');
    exit('File not found');
}

$size  = $storage->stat($filePath)['size'];
$begin = 0;
$end   = $size - 1;

if (isset($_SERVER['HTTP_RANGE'])) {
    if (preg_match('/bytes=\h*(\d+)-(\d*)[\D.*]?/i', $_SERVER['HTTP_RANGE'], $matches)) {
        $begin = intval($matches[1]);
        if (!empty($matches[2])) {
            $end = intval($matches[2]);
        }
    }
}

// ── Determine content type ────────────────────────────────────────────────────
$ext = strtolower(pathinfo($filePath, PATHINFO_EXTENSION));
$mimeTypes = [
    'mp3'  => 'audio/mpeg',
    'flac' => 'audio/flac',
    'm4a'  => 'audio/mp4',
    'ogg'  => 'audio/ogg',
    'wav'  => 'audio/wav',
    'aac'  => 'audio/aac',
    'wma'  => 'audio/x-ms-wma',
    'opus' => 'audio/opus',
    'aiff' => 'audio/aiff',
];
$contentType = $mimeTypes[$ext] ?? 'audio/mpeg';

header('Content-Type: ' . $contentType);
header('Accept-Ranges: bytes');

if (isset($_SERVER['HTTP_RANGE'])) {
    header('HTTP/1.1 206 Partial Content');
    header('Content-Range: bytes ' . $begin . '-' . $end . '/' . $size);
    header('Content-Length: ' . ($end - $begin + 1));
} else {
    header('Content-Length: ' . $size);
}

if (ob_get_level()) {
    ob_end_clean();
}

// ── Stream data ───────────────────────────────────────────────────────────────
$length = $end - $begin + 1;

if ($storage->getType() === 'local') {
    // Chunked streaming for local files — avoids loading the full range into memory
    $handle = fopen($filePath, 'rb');
    fseek($handle, $begin);
    $bufSize  = 1024 * 64; // 64 KB chunks
    $sent     = 0;
    while ($sent < $length && !feof($handle)) {
        $chunk = min($bufSize, $length - $sent);
        echo fread($handle, $chunk);
        $sent += $chunk;
        flush();
    }
    fclose($handle);
} else {
    // SFTP: read the range in one call (phpseclib handles it natively)
    echo $storage->readRange($filePath, $begin, $length);
}
