<?php
/**
 * Corrige created_at des albums récemment (re)scannés pour refléter la vraie
 * date d'ajout (mtime du dossier) au lieu de la date du scan. Répare les
 * « Nouveautés » inondées par du contenu ancien re-scané.
 *
 * Usage : php fix-album-dates.php <user> [days=3]
 */
require_once __DIR__ . '/../src/AppConfig.php';
require_once __DIR__ . '/../src/Storage/StorageFactory.php';

$user = $argv[1] ?? null;
$days = (int)($argv[2] ?? 3);
if (!$user) { fwrite(STDERR, "Usage: fix-album-dates.php <user> [days]\n"); exit(1); }

$db      = AppConfig::getDB();
$storage = StorageFactory::forUser($user);
$root    = $storage->getMusicRoot();

$stmt = $db->prepare("
    SELECT al.id, al.name AS album, a.name AS artist, al.created_at
    FROM albums al JOIN artists a ON al.artist_id = a.id
    WHERE a.user = ? AND al.created_at >= DATE_SUB(NOW(), INTERVAL ? DAY)
");
$stmt->execute([$user, $days]);
$rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

$fixed = 0;
foreach ($rows as $row) {
    $path = $root . '/' . $row['artist'] . '/' . $row['album'];
    $st = @$storage->stat($path);
    $mtime = (int)($st['mtime'] ?? 0);
    if ($mtime > 0 && date('Y-m-d', $mtime) !== substr($row['created_at'], 0, 10)) {
        $db->prepare("UPDATE albums SET created_at = FROM_UNIXTIME(?) WHERE id = ?")
           ->execute([$mtime, $row['id']]);
        echo str_pad($row['artist'] . ' / ' . $row['album'], 60) . ' → ' . date('Y-m-d', $mtime) . "\n";
        $fixed++;
    }
}
echo "Corrigés : $fixed / " . count($rows) . " albums.\n";
