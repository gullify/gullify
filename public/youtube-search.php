<?php
/**
 * YouTube Music Search API
 * Uses ytmusicapi (Python) to get artist info and albums from YouTube Music.
 */

ini_set('display_errors', 0);
error_reporting(E_ALL);

header('Content-Type: application/json');

require_once __DIR__ . '/../src/AppConfig.php';

$artistName = $_GET['artist'] ?? '';

if (empty($artistName)) {
    echo json_encode(['error' => true, 'message' => 'Artist name required']);
    exit;
}

// Step 1: Find the artist's Topic channel with yt-dlp
$topicSearchCmd = "timeout 20 yt-dlp --extractor-args \"youtube:player_client=default\" --print '%(channel_id)s' "
    . escapeshellarg("ytsearch1:$artistName - Topic") . " 2>/dev/null | head -1";
$channelId = trim(shell_exec($topicSearchCmd));

if (empty($channelId)) {
    echo json_encode(['error' => false, 'albums' => [], 'message' => 'Artist Topic channel not found']);
    exit;
}

// Step 2: Use ytmusicapi (Python) to fetch artist info and albums
$pythonScript = AppConfig::getPythonPath() . '/get-ytmusic-albums.py';
// Use venv python if available (Docker installs ytmusicapi there)
$python = file_exists('/opt/ytdlp/bin/python3') ? '/opt/ytdlp/bin/python3' : 'python3';
$pythonCmd = $python . " " . escapeshellarg($pythonScript) . " " . escapeshellarg($channelId) . " 2>&1";
$output = shell_exec($pythonCmd);

if (empty($output)) {
    error_log("YouTube search: Empty output from Python script for channel $channelId");
    echo json_encode(['error' => false, 'albums' => [], 'debug' => 'Empty Python output', 'channelId' => $channelId]);
    exit;
}

$pythonResult = json_decode($output, true);

if (json_last_error() !== JSON_ERROR_NONE || !is_array($pythonResult)) {
    error_log("YouTube search: JSON decode error: " . json_last_error_msg() . " - Output: $output");
    echo json_encode(['error' => false, 'artist' => null, 'albums' => [], 'debug' => 'JSON decode error: ' . json_last_error_msg()]);
    exit;
}

echo json_encode([
    'error' => false,
    'artistName' => $artistName,
    'artist' => $pythonResult['artist'] ?? null,
    'albums' => $pythonResult['albums'] ?? []
]);
