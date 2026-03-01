<?php
/**
 * Gullify - Radio Stream Proxy
 * Proxies HTTP radio streams through HTTPS to avoid mixed content issues on mobile
 * Migrated from radio_proxy.php
 */

require_once __DIR__ . '/../../src/AppConfig.php';

// Disable output buffering for streaming
if (ob_get_level()) ob_end_clean();

// Get stream URL
$url = $_GET['url'] ?? '';

if (empty($url)) {
    http_response_code(400);
    exit('Missing URL parameter');
}

// Validate URL
if (!filter_var($url, FILTER_VALIDATE_URL)) {
    http_response_code(400);
    exit('Invalid URL');
}

// Only proxy audio streams (basic security check)
$parsed = parse_url($url);
$host = $parsed['host'] ?? '';

// Block localhost and private IPs
if (preg_match('/^(localhost|127\.|192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.)/i', $host)) {
    http_response_code(403);
    exit('Forbidden');
}

// Set headers for audio streaming
header('Content-Type: audio/mpeg');
header('Cache-Control: no-cache, no-store');
header('Accept-Ranges: none');
header('Access-Control-Allow-Origin: *');
header('X-Content-Type-Options: nosniff');

// Create stream context
$ctx = stream_context_create([
    'http' => [
        'timeout' => 10,
        'user_agent' => 'MusicPlayer/1.0',
        'follow_location' => true,
        'max_redirects' => 5,
        'header' => [
            'Accept: audio/mpeg, audio/*, */*',
            'Icy-MetaData: 0'
        ]
    ],
    'ssl' => [
        'verify_peer' => false,
        'verify_peer_name' => false
    ]
]);

// Open stream
$stream = @fopen($url, 'rb', false, $ctx);

if (!$stream) {
    http_response_code(502);
    exit('Could not open stream');
}

// Set script to run indefinitely (for live streams)
set_time_limit(0);
ignore_user_abort(false);

// Stream the content
while (!feof($stream) && !connection_aborted()) {
    $chunk = fread($stream, 8192);
    if ($chunk === false) break;
    echo $chunk;
    flush();
}

fclose($stream);
