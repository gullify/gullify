<?php
// Translate old parameter format to serve_image.php format
// Old: type=artist&id=X or type=album&id=X
// New: artist_id=X or album_id=X
if (isset($_GET['type']) && isset($_GET['id'])) {
    $type = $_GET['type'];
    $id = $_GET['id'];
    if ($type === 'artist') {
        $_GET['artist_id'] = $id;
    } elseif ($type === 'album') {
        $_GET['album_id'] = $id;
    }
}

require_once __DIR__ . '/serve_image.php';
