#!/usr/bin/env php
<?php
/**
 * Gullify - Library Scanner CLI
 * Scans music directories and populates the database.
 *
 * Usage:
 *   php scan-library.php                    # Scan all users
 *   php scan-library.php username           # Scan specific user
 *   php scan-library.php --skip-artwork     # Fast scan (no artwork)
 *   php scan-library.php --skip-artwork user # Fast scan for specific user
 */

error_reporting(E_ALL);
ini_set('display_errors', 1);
ini_set('memory_limit', '2048M');
ini_set('max_execution_time', 3600);

require_once __DIR__ . '/../src/Scanner.php';

$skipArtwork = false;
$clearLibrary = false;
$targetUser = null;

// Parse arguments
$args = array_slice($argv, 1);
foreach ($args as $arg) {
    if ($arg === '--skip-artwork') {
        $skipArtwork = true;
    } elseif ($arg === '--clear') {
        $clearLibrary = true;
    } else {
        $targetUser = $arg;
    }
}

echo "========================================\n";
echo "Gullify Library Scanner\n";
echo "Mode: " . ($skipArtwork ? "Fast (skip artwork)" : "Full") . "\n";
if ($clearLibrary) echo "Option: Clear library before scan enabled\n";
echo "Started: " . date('Y-m-d H:i:s') . "\n";
echo "========================================\n\n";

try {
    $scanner = new Scanner($skipArtwork);

    if ($targetUser) {
        if ($clearLibrary) {
            $scanner->clearUserLibrary($targetUser);
        }
        echo "Scanning user: $targetUser\n";
        $scanner->scanUserIncremental($targetUser);
    } else {
        $users = $scanner->getAllUsers();
        echo "Found " . count($users) . " users to scan: " . implode(', ', $users) . "\n\n";

        foreach ($users as $user) {
            if ($clearLibrary) {
                $scanner->clearUserLibrary($user);
            }
            echo "\n--- Scanning user: $user ---\n";
            try {
                $scanner->scanUserIncremental($user);
            } catch (Exception $e) {
                echo "ERROR scanning $user: " . $e->getMessage() . "\n";
            }
        }
    }

    echo "\n========================================\n";
    echo "Scan completed: " . date('Y-m-d H:i:s') . "\n";
    echo "========================================\n";

} catch (Exception $e) {
    echo "FATAL ERROR: " . $e->getMessage() . "\n";
    exit(1);
}
