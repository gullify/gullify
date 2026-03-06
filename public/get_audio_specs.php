<?php
/**
 * Lightweight endpoint: returns audio specs (format, bitrate, sample rate) for a file.
 * Usage: get_audio_specs.php?path=Artist/Album/song.mp3
 */
header('Content-Type: application/json');

require_once __DIR__ . '/../src/AppConfig.php';
require_once __DIR__ . '/../src/auth_required.php';
require_once __DIR__ . '/../src/PathHelper.php';
require_once __DIR__ . '/../src/Storage/StorageFactory.php';

$relativePath = $_GET['path'] ?? '';
if (!$relativePath) {
    echo json_encode(['error' => true]);
    exit;
}

try {
    $user = $_SESSION['username'];
    $storage = StorageFactory::forUser($user);
    $absPath = $storage->getPathBase() . '/' . ltrim($relativePath, '/');

    // Only local files — SFTP would require downloading
    if ($storage->getType() !== 'local' || !file_exists($absPath)) {
        $ext = strtoupper(pathinfo($relativePath, PATHINFO_EXTENSION));
        echo json_encode(['format' => $ext ?: '?', 'bitrate' => null, 'sampleRate' => null]);
        exit;
    }

    $vendorPath = AppConfig::getVendorPath();
    require_once $vendorPath . '/getid3/getid3.php';

    $getID3 = new getID3();
    $getID3->option_tag_id3v1 = false;
    $getID3->option_tag_id3v2 = false;
    $getID3->option_tag_lyrics3 = false;
    $getID3->option_tag_apetag = false;
    $getID3->option_extra_info = false;

    $info = $getID3->analyze($absPath);

    $ext = strtoupper(pathinfo($relativePath, PATHINFO_EXTENSION));
    $bitrate = isset($info['audio']['bitrate']) ? (int)round($info['audio']['bitrate'] / 1000) : null;
    $sampleRate = isset($info['audio']['sample_rate']) ? $info['audio']['sample_rate'] / 1000 : null;

    echo json_encode([
        'format' => $ext ?: '?',
        'bitrate' => $bitrate,
        'sampleRate' => $sampleRate,
    ]);
} catch (Exception $e) {
    echo json_encode(['error' => true]);
}
