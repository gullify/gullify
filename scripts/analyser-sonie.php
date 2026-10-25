#!/usr/bin/env php
<?php
/**
 * Gullify — mesure la sonie des morceaux (EBU R128) pour la normalisation du volume (1.0).
 *
 * Ne mesure que les morceaux sans mesure, ou dont le fichier a changé depuis (empreinte différente).
 * Un fichier illisible est marqué (sans valeur) pour ne pas être réessayé tant qu'il ne change pas.
 *
 * Usage (sur la maison, la nuit, à basse priorité) :
 *   nice -n 19 ionice -c3 php analyser-sonie.php [--limite=200] [--dry]
 *
 * --dry : compte seulement ce qui resterait à faire.
 */
error_reporting(E_ALL);
ini_set('display_errors', 1);
ini_set('memory_limit', '512M');
ini_set('max_execution_time', 0);

require_once __DIR__ . '/../src/Scanner.php';
require_once __DIR__ . '/../src/Loudness.php';

$limite = 200;
$sec = false;
foreach (array_slice($argv, 1) as $arg) {
    if (preg_match('/^--limite=(\d+)$/', $arg, $m)) $limite = max(1, (int)$m[1]);
    if ($arg === '--dry') $sec = true;
}

$scanner = new Scanner(true);
$db = AppConfig::getDB();
$mesures = 0;
$echecs = 0;

foreach ($scanner->getAllUsers() as $user) {
    $requete = $db->prepare(
        "SELECT s.id, s.file_path, s.file_hash
           FROM songs s
           JOIN albums al ON al.id = s.album_id
           JOIN artists ar ON ar.id = al.artist_id
          WHERE ar.user = ?
            AND (s.loudness_hash IS NULL OR s.loudness_hash <> COALESCE(s.file_hash, ''))
          LIMIT " . (int)$limite
    );
    $requete->execute([$user]);
    $aFaire = $requete->fetchAll(PDO::FETCH_ASSOC);
    if ($aFaire === []) continue;

    if ($sec) {
        echo "$user : " . count($aFaire) . " morceau(x) à mesurer (au plus $limite)\n";
        continue;
    }

    $storage = StorageFactory::forUser($user);
    $base = rtrim($storage->getPathBase(), '/');
    $maj = $db->prepare("UPDATE songs SET loudness_lufs = ?, loudness_hash = ? WHERE id = ?");
    foreach ($aFaire as $s) {
        $lufs = Loudness::mesurer($base . '/' . ltrim($s['file_path'], '/'));
        $maj->execute([$lufs, (string)($s['file_hash'] ?? ''), $s['id']]);
        $lufs === null ? $echecs++ : $mesures++;
    }
    echo "$user : " . count($aFaire) . " traité(s)\n";
}

echo $sec ? "(simulation, rien écrit)\n" : "Mesurés : $mesures · illisibles : $echecs\n";
