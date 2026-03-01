#!/usr/bin/env php
<?php
/**
 * Gullify - Artwork Scanner CLI
 * Updates missing artwork for albums (cover files + embedded ID3).
 *
 * Usage:
 *   php scan-artwork.php username
 */

error_reporting(E_ALL);
ini_set('display_errors', 1);
ini_set('memory_limit', '1024M');
ini_set('max_execution_time', 1800);

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
    $updated = $scanner->updateMissingArtwork($targetUser);

    echo "\n========================================\n";
    echo "Artwork scan completed: $updated albums updated\n";
    echo "Finished: " . date('Y-m-d H:i:s') . "\n";
    echo "========================================\n";

} catch (Exception $e) {
    echo "FATAL ERROR: " . $e->getMessage() . "\n";
    exit(1);
}
