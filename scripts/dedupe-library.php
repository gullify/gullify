#!/usr/bin/env php
<?php
/**
 * Fusionne les pistes en double dans la base (un fichier = une ligne) et pose
 * l'index d'unicité qui empêche que ça recommence.
 *
 * Le Scanner l'appelle tout seul tant que l'index manque ; ce script sert à le
 * lancer à la main (--dry-run pour compter sans rien changer).
 *
 * Usage : php scripts/dedupe-library.php [--dry-run]
 */

if (php_sapi_name() !== 'cli') {
    die("Ce script doit être lancé en ligne de commande\n");
}

require_once __DIR__ . '/../src/AppConfig.php';
require_once __DIR__ . '/../src/LibraryDedupe.php';

$dryRun = in_array('--dry-run', $argv, true);
$db = AppConfig::getDB();

$stmt = $db->query(
    'SELECT COUNT(*) - COUNT(DISTINCT file_path) FROM songs'
);
$extra = (int) $stmt->fetchColumn();

echo "Pistes en double : $extra ligne(s) en trop\n";

$dedupe = new LibraryDedupe($db);
echo 'Index ' . LibraryDedupe::INDEX_NAME . ' : ' . ($dedupe->indexExists() ? "présent\n" : "absent\n");

if ($dryRun) {
    echo "--dry-run : rien n'a été modifié\n";
    exit(0);
}

$result = $dedupe->run();

echo "Pistes fusionnées : {$result['songs']}\n";
echo "Albums vidés supprimés : {$result['albums']}\n";
echo "Artistes sans rien supprimés : {$result['artists']}\n";
echo 'Index d\'unicité : ' . ($result['indexed'] ? "posé\n" : "REFUSÉ (voir error_log)\n");

exit($result['indexed'] ? 0 : 1);
