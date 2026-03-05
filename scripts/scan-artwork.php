#!/usr/bin/env php
<?php
/**
 * Gullify - Artwork Scanner CLI
 * Regenerates all artwork thumbnails (albums + artists) at current quality settings.
 *
 * Usage:
 *   php scan-artwork.php username
 */

error_reporting(E_ALL);
ini_set('display_errors', 1);
ini_set('memory_limit', '1024M');
ini_set('max_execution_time', 3600);

require_once __DIR__ . '/../src/Scanner.php';

$targetUser = $argv[1] ?? null;

if (!$targetUser) {
    echo "Usage: php scan-artwork.php <username>\n";
    exit(1);
}

echo "========================================\n";
echo "Gullify Artwork Scanner\n";
echo "User: $targetUser\n";
echo "Started: " . date('Y-m-d H:i:s') . "\n";
echo "========================================\n\n";

try {
    $scanner = new Scanner(false);
    $updated = $scanner->regenerateAllArtwork($targetUser);

    echo "\n========================================\n";
    echo "Artwork scan completed: $updated items updated\n";
    echo "Finished: " . date('Y-m-d H:i:s') . "\n";
    echo "========================================\n";

} catch (Exception $e) {
    echo "FATAL ERROR: " . $e->getMessage() . "\n";
    exit(1);
}
