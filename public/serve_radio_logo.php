<?php
/**
 * Gullify — Serve a user-uploaded radio logo from data/cache/radio_logos/
 *
 *   GET ?f=…  → returns the PNG with ETag + 304 revalidation
 *
 * No auth check on read — these are public-ish assets meant to be loaded
 * directly by <img src> tags, like album artwork. We do reject any filename
 * that tries to escape the cache dir.
 */

require_once __DIR__ . '/../src/AppConfig.php';

$name = (string)($_GET['f'] ?? '');
if ($name === '' || !preg_match('/^[A-Za-z0-9_.-]+\.(png|jpe?g|webp)$/i', $name)) {
    http_response_code(400);
    exit;
}

$dir = AppConfig::getDataPath() . '/cache/radio_logos';
$path = realpath($dir . '/' . $name);
if (!$path || !str_starts_with($path, realpath($dir))) {
    http_response_code(404);
    exit;
}
if (!is_file($path)) {
    http_response_code(404);
    exit;
}

$mtime = (int)filemtime($path);
$etag  = '"' . $mtime . '"';
$mime  = 'image/png';
if (preg_match('/\.jpe?g$/i', $name)) $mime = 'image/jpeg';
elseif (preg_match('/\.webp$/i', $name)) $mime = 'image/webp';

header('Cache-Control: no-cache');
header('Last-Modified: ' . gmdate('D, d M Y H:i:s', $mtime) . ' GMT');
header('ETag: ' . $etag);

if (trim($_SERVER['HTTP_IF_NONE_MATCH'] ?? '') === $etag) {
    http_response_code(304);
    exit;
}

header('Content-Type: ' . $mime);
header('Content-Length: ' . filesize($path));
readfile($path);
