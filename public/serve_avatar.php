<?php
/**
 * Gullify - Profile avatar serving endpoint
 * GET /serve_avatar.php?user_id=N  → the user's avatar JPEG, or 404.
 *
 * Public (like serve_image.php): avatars are shown in the "other users"
 * discovery UI, which any authenticated client browses.
 */
require_once __DIR__ . '/../src/Avatar.php';

header('Access-Control-Allow-Origin: *');

$userId = isset($_GET['user_id']) ? (int) $_GET['user_id'] : 0;
if ($userId <= 0 || !Avatar::exists($userId)) {
    http_response_code(404);
    exit;
}

$file = Avatar::path($userId);
header('Content-Type: image/jpeg');
header('Content-Length: ' . filesize($file));
header('Cache-Control: public, max-age=86400');
readfile($file);
