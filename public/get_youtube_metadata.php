<?php
header('Content-Type: application/json; charset=utf-8');

$url = $_GET['url'] ?? '';
if (empty($url)) {
    echo json_encode(['error' => 'URL non fournie']);
    exit;
}

// Validate URL
if (strpos($url, 'youtube.com') === false && strpos($url, 'youtu.be') === false) {
    echo json_encode(['error' => 'URL YouTube invalide']);
    exit;
}

// Use yt-dlp to extract metadata without downloading
$cmd = 'yt-dlp --no-download --dump-json --flat-playlist ' . escapeshellarg($url) . ' 2>&1';
$output = [];
$returnCode = 0;
exec($cmd, $output, $returnCode);

$rawOutput = implode("\n", $output);

if ($returnCode !== 0) {
    // Try single video mode if playlist fails
    $cmd = 'yt-dlp --no-download --dump-json ' . escapeshellarg($url) . ' 2>&1';
    $output = [];
    exec($cmd, $output, $returnCode);
    $rawOutput = implode("\n", $output);

    if ($returnCode !== 0) {
        echo json_encode(['error' => 'Impossible d\'analyser cette URL', 'details' => $rawOutput]);
        exit;
    }
}

// Parse the JSON output - may be multiple lines for playlists
$entries = [];
foreach ($output as $line) {
    $decoded = json_decode($line, true);
    if ($decoded) {
        $entries[] = $decoded;
    }
}

if (empty($entries)) {
    echo json_encode(['error' => 'Aucune donnée trouvée pour cette URL']);
    exit;
}

// Determine if it's a playlist or single track
$firstEntry = $entries[0];
$trackCount = count($entries);

// Extract metadata
$data = [
    'title' => $firstEntry['playlist_title'] ?? $firstEntry['title'] ?? '',
    'artist' => $firstEntry['artist'] ?? $firstEntry['creator'] ?? $firstEntry['uploader'] ?? $firstEntry['channel'] ?? '',
    'album' => $firstEntry['album'] ?? $firstEntry['playlist_title'] ?? $firstEntry['title'] ?? '',
    'uploader' => $firstEntry['uploader'] ?? $firstEntry['channel'] ?? '',
    'thumbnail' => $firstEntry['thumbnail'] ?? $firstEntry['thumbnails'][0]['url'] ?? '',
    'track_count' => $trackCount,
    'url' => $url,
    'is_playlist' => $trackCount > 1
];

// Clean up artist name - remove " - Topic" from YouTube Music channels
$data['artist'] = preg_replace('/ - Topic$/', '', $data['artist']);

// Clean up album name - remove "Album - " prefix from YouTube Music
$data['album'] = preg_replace('/^Album\s*[-–—]\s*/', '', $data['album']);

echo json_encode(['data' => $data], JSON_UNESCAPED_UNICODE);
