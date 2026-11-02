#!/usr/bin/env php
<?php
/**
 * Gullify — Pour toi : l'analyse de nuit (src/Gouts*.php).
 *
 *  1. Enrichit les artistes des bibliothèques (Last.fm, sinon YouTube Music +
 *     MusicBrainz) : au plus --enrichir artistes par passage, les plus écoutés
 *     d'abord. Une grosse bibliothèque se complète donc en quelques nuits.
 *  2. Pour chaque personne qui a écouté quelque chose : profil, voisins,
 *     rayons (mix, découvertes, en boucle, perles oubliées, moments, ailleurs).
 *
 * Usage (cron de l'image, 8 h 40 UTC ; à la main, à basse priorité) :
 *   nice -n 19 php analyser-gouts.php [--enrichir=300] [--user=maxime] [--sans-reseau]
 */
error_reporting(E_ALL);
ini_set('display_errors', 1);
ini_set('memory_limit', '768M');
ini_set('max_execution_time', 0);

require_once __DIR__ . '/../src/Gouts.php';
require_once __DIR__ . '/../src/GoutsSources.php';
require_once __DIR__ . '/../src/GoutsRayons.php';

$enrichir = 300;
$seul = null;
$reseau = true;
foreach (array_slice($argv, 1) as $arg) {
    if (preg_match('/^--enrichir=(\d+)$/', $arg, $m)) $enrichir = (int)$m[1];
    if (preg_match('/^--user=(.+)$/', $arg, $m)) $seul = $m[1];
    if ($arg === '--sans-reseau') $reseau = false;
}

$journal = fn(string $m) => print('[' . date('H:i:s') . "] $m\n");
$verrou = fopen(sys_get_temp_dir() . '/analyser-gouts.lock', 'c');
if (!$verrou || !flock($verrou, LOCK_EX | LOCK_NB)) {
    $journal('Une analyse tourne déjà.');
    exit(0);
}

$db = AppConfig::getDB();
Gouts::assurerTables($db);

$utilisateurs = $seul !== null ? [$seul]
    : $db->query("SELECT DISTINCT user FROM play_history WHERE played_at > NOW() - INTERVAL 365 DAY")->fetchAll(PDO::FETCH_COLUMN);

// Un premier profil sans le monde, pour que l'enrichissement sache par quels
// artistes commencer (ceux qu'on écoute).
foreach ($utilisateurs as $u) Gouts::analyserProfil($db, $u);

if ($reseau && $enrichir > 0) {
    $journal('Enrichissement par ' . GoutsSources::source() . " (au plus $enrichir artistes)…");
    $r = GoutsSources::enrichir($db, $enrichir, $journal);
    $journal("  {$r['faits']} faits, {$r['trouves']} trouvés.");
}

foreach ($utilisateurs as $u) {
    $t0 = microtime(true);
    $p = Gouts::analyserProfil($db, $u);
    $r = GoutsRayons::construire($db, $u, $reseau);
    $db->prepare('INSERT INTO gouts_reglages (user, analyse_le) VALUES (?, NOW()) ON DUPLICATE KEY UPDATE analyse_le = NOW()')
       ->execute([$u]);
    $rayons = implode(', ', array_map(fn($k, $v) => "$k $v", array_keys($r), $r));
    $journal(sprintf('%s : %d écoutes, %d titres, %d artistes, %d étiquettes, %d liens de voisinage → %s (%.1f s)',
        $u, $p['ecoutes'], $p['titres'], $p['artistes'], $p['tags'], $p['voisins'], $rayons ?: 'aucun rayon',
        microtime(true) - $t0));
}
// Les sauts nets de plus d'un an ne servent plus au profil.
$db->exec('DELETE FROM gouts_sauts WHERE saute_le < NOW() - INTERVAL 400 DAY');
$journal('Fini.');
