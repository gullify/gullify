<?php
/**
 * Gullify - Scan Artist API
 * Scans a specific artist's directory after a download completes.
 * Called internally by download-worker.php or from the UI.
 */

require_once __DIR__ . '/../../src/Scanner.php';

header('Content-Type: application/json');

$artistId = $_GET['artist_id'] ?? $_POST['artist_id'] ?? null;
$user = $_GET['user'] ?? $_POST['user'] ?? null;

if (!$artistId || !$user) {
    http_response_code(400);
    echo json_encode(['success' => false, 'error' => 'artist_id and user are required']);
    exit(1);
}

try {
    $scanner = new Scanner(false);
    $changes = $scanner->scanArtist((int) $artistId, $user);

    $hasChanges = !empty($changes['new_albums']) ||
                  !empty($changes['new_songs']) ||
                  !empty($changes['removed_albums']) ||
                  !empty($changes['removed_songs']) ||
                  !empty($changes['updated_songs']) ||
                  !empty($changes['updated_artwork']) ||
                  !empty($changes['updated_years']);

    echo json_encode([
        'success' => true,
        'data' => [
            'artist_id' => $artistId,
            'has_changes' => $hasChanges,
            'changes' => $changes,
            'summary' => [
                'new_albums' => count($changes['new_albums']),
                'new_songs' => count($changes['new_songs']),
                'removed_albums' => count($changes['removed_albums']),
                'removed_songs' => count($changes['removed_songs']),
                'updated_songs' => count($changes['updated_songs']),
                'updated_artwork' => count($changes['updated_artwork']),
                'updated_years' => count($changes['updated_years']),
            ],
        ],
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'error' => $e->getMessage()]);
    exit(1);
}
