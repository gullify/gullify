<?php
/**
 * Gullify - Audio Streaming Endpoint
 * Supports HTTP range requests for seeking.
 * Uses StorageFactory to support both local and SFTP backends.
 *
 * `&karaoke=1` sert la version voix atténuée du titre si elle a déjà été
 * rendue (voir src/Karaoke.php) ; sinon l'original part comme d'habitude —
 * la lecture ne s'arrête jamais parce qu'un karaoké manque.
 */
require_once __DIR__ . '/../src/AppConfig.php';
require_once __DIR__ . '/../src/Auth.php';
require_once __DIR__ . '/../src/Storage/StorageInterface.php';
require_once __DIR__ . '/../src/Storage/LocalStorage.php';
require_once __DIR__ . '/../src/Storage/SFTPStorage.php';
require_once __DIR__ . '/../src/Storage/StorageFactory.php';
require_once __DIR__ . '/../src/Karaoke.php';

ini_set('max_execution_time', 0);

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Range');
header('Access-Control-Expose-Headers: Content-Range, Accept-Ranges, Content-Length');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

/**
 * Qui a le droit d'écouter.
 *
 * Le flux est lu par une balise `<audio>` ou par le lecteur du système :
 * aucun des deux ne peut poser un en-tête `Authorization`. Le jeton voyage
 * donc dans l'adresse — c'est ce que font Subsonic et Jellyfin, pour la même
 * raison. Il apparaît alors dans les journaux du serveur : c'est le prix de
 * cette contrainte.
 *
 * Les appels internes (share.php et party.php passent par ffmpeg sur
 * 127.0.0.1) n'ont pas de session. Ils arrivent en boucle locale, jamais par
 * le proxy — une requête venue du dehors porte l'adresse de Caddy.
 */
function streamAutorise(): bool {
    $distant = $_SERVER['REMOTE_ADDR'] ?? '';
    if ($distant === '127.0.0.1' || $distant === '::1') {
        return true;
    }

    $entete = $_SERVER['HTTP_AUTHORIZATION']
        ?? (function_exists('apache_request_headers')
            ? (apache_request_headers()['Authorization'] ?? '')
            : '');
    $jeton = preg_match('/^Bearer\s+(\S+)$/i', trim((string)$entete), $m)
        ? $m[1]
        : ($_GET['token'] ?? $_COOKIE['gullify_session'] ?? null);

    if (!is_string($jeton) || $jeton === '') {
        return false;
    }
    try {
        return !empty((new Auth())->getSession($jeton));
    } catch (Throwable $e) {
        error_log('stream.php : vérification du jeton impossible — ' . $e->getMessage());
        return false;
    }
}

if (!streamAutorise()) {
    header('HTTP/1.0 401 Unauthorized');
    exit('Authentification requise');
}

$relativePath = $_GET['path'] ?? '';
if ($relativePath === '') {
    header('HTTP/1.0 400 Bad Request');
    exit('Missing path parameter');
}

// Aucune remontée de dossier, quel que soit le stockage. La vérification par
// `realpath` plus bas ne vaut que pour le stockage local : sur une instance
// en SFTP, le chemin était concaténé tel quel et « ../ » sortait du dossier
// de musique.
if (str_contains($relativePath, "\0")
    || preg_match('#(?:^|[\\/])\.\.(?:[\\/]|$)#', $relativePath)
    || preg_match('#^[/\\]#', $relativePath)
    || preg_match('#^[A-Za-z]:#', $relativePath)) {
    header('HTTP/1.0 403 Forbidden');
    exit('Chemin refusé');
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

// ── Version karaoké ───────────────────────────────────────────────────────────
// Rendu déjà en cache : c'est lui qu'on sert, comme un fichier local ordinaire.
$karaoke = false;
if (!empty($_GET['karaoke']) && $storage->getType() === 'local') {
    $rendered = Karaoke::readyFor($relativePath, $filePath);
    if ($rendered !== null) {
        $filePath = $rendered;
        $karaoke  = true;
    }
}

$size  = $karaoke ? filesize($filePath) : $storage->stat($filePath)['size'];
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
