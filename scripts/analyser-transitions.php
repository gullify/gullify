#!/usr/bin/env php
<?php
/**
 * Gullify — calcule à l'avance le profil de transition (et le niveau de normalisation) de tous les morceaux
 * (src/TransitionAnalysis.php), pour que la normalisation du volume joue dès le premier passage.
 *
 * Même mesure que l'app : pas de seconde mesure, pas de cible différente. Les morceaux déjà mesurés sont
 * ignorés (TransitionAnalysis met en cache). Un passage traite au plus --limite morceaux.
 *
 * Usage (sur la maison, à basse priorité) :
 *   nice -n 19 ionice -c3 php analyser-transitions.php [--limite=1000] [--dry]
 */
error_reporting(E_ALL);
ini_set('display_errors', 1);
ini_set('memory_limit', '512M');
ini_set('max_execution_time', 0);

require_once __DIR__ . '/../src/TransitionAnalysis.php';

$limite = 1000;
$sec = false;
foreach (array_slice($argv, 1) as $arg) {
    if (preg_match('/^--limite=(\d+)$/', $arg, $m)) $limite = max(1, (int)$m[1]);
    if ($arg === '--dry') $sec = true;
}

$db = AppConfig::getDB();
TransitionAnalysis::forSongs($db, '', []); // crée la table si besoin
$utilisateurs = $db->query("SELECT DISTINCT ar.user FROM artists ar")->fetchAll(PDO::FETCH_COLUMN) ?: [];

$total = 0;
foreach ($utilisateurs as $user) {
    // les morceaux pas encore dans la table de transitions, en lots de 100
    $sql = "SELECT s.id FROM songs s
              JOIN albums al ON al.id = s.album_id
              JOIN artists ar ON ar.id = al.artist_id
             WHERE ar.user = ?
               AND s.id NOT IN (SELECT song_id FROM song_transitions)
             LIMIT " . (int)($limite - $total);
    $req = $db->prepare($sql);
    $req->execute([$user]);
    $ids = array_map('intval', $req->fetchAll(PDO::FETCH_COLUMN) ?: []);
    if ($ids === []) continue;
    if ($sec) {
        echo "$user : " . count($ids) . " morceau(x) à analyser (au plus $limite)\n";
        $total += count($ids);
    } else {
        foreach (array_chunk($ids, 100) as $lot) {
            $total += count(TransitionAnalysis::forSongs($db, $user, $lot));
        }
        echo "$user : " . count($ids) . " demandé(s)\n";
    }
    if ($total >= $limite) break;
}
echo $sec ? "(simulation, rien écrit)\n" : "Profils calculés : $total\n";
