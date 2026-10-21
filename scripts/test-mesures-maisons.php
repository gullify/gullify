<?php
/**
 * Essai de l'historique des maisons (MesuresMaisons), sur une base MySQL JETABLE seulement (il vide
 * ses tables) : TEST_JETABLE=oui php scripts/test-mesures-maisons.php
 */
declare(strict_types=1);

if (getenv('TEST_JETABLE') !== 'oui') {
    fwrite(STDERR, "Base jetable seulement : TEST_JETABLE=oui\n");
    exit(2);
}
require_once __DIR__ . '/../src/MesuresMaisons.php';

$echecs = 0;
function verifier(bool $vrai, string $quoi): void
{
    global $echecs;
    echo ($vrai ? 'ok   ' : 'ÉCHEC ') . $quoi . "\n";
    $echecs += $vrai ? 0 : 1;
}

$db = AppConfig::getDB();
foreach (['mesures_brutes', 'mesures_heures', 'mesures_jours', 'mesures_etat'] as $t) {
    $db->exec("DROP TABLE IF EXISTS $t");
}
$m = new MesuresMaisons($db);

// Trois heures d'échantillons d'une minute, avec une coupure de 20 minutes.
$fin = intdiv(time(), 60) * 60;
$lot = [];
for ($t = $fin - 3 * 3600; $t <= $fin; $t += 60) {
    if ($t > $fin - 3600 && $t <= $fin - 2400) {
        continue;
    }
    $lot[] = ['t' => $t, 'v' => ['up' => 1000 + $t - $fin, 'cpu' => ($t / 60) % 2 ? 10 : 30, 'disque_utilise:/' => 5e9,
                                 'temp_disque:sdb' => 41, 'app:gullieats' => 1, 'mauvais nom' => 3, 'x' => 'abc']];
}
$lot[count($lot) - 1]['smart'] = [['nom' => 'sdb', 'sain' => true, 'temp' => 41]];
$lot[count($lot) - 1]['sauvegarde'] = '2026-10-21-0429';
$n = 0;
foreach (array_chunk($lot, MesuresMaisons::PAR_ENVOI) as $morceau) {
    $n += $m->recevoir('le251', $morceau);
}
verifier($n === count($lot), "échantillons reçus ($n)");
verifier($m->recevoir('le251', array_slice($lot, 0, 50)) === 0, 'un lot renvoyé ne compte pas deux fois');
verifier((int)$db->query("SELECT COUNT(*) FROM mesures_brutes WHERE serie IN ('mauvais nom', 'x')")->fetchColumn() === 0,
         'séries mal nommées ou non numériques ignorées');
$vieux = $m->recevoir('le251', [['t' => time() - 3 * 86400, 'v' => ['up' => 1]]]);
verifier($vieux === 0, 'échantillon de plus de deux jours ignoré');

$h = $m->historique('le251', '6h');
verifier(count($h['series']['cpu']) === count($lot), '6 h : un point par minute');
$cpu = array_column($h['series']['cpu'], 1);
verifier(min($cpu) === 10.0 && max($cpu) === 30.0, '6 h : les valeurs');
$h = $m->historique('le251', '24h');
$p = array_column($h['series']['cpu'], 1);
verifier(abs(array_sum($p) / count($p) - 20) < 3, '24 h : moyennes sur 5 min (' . round(array_sum($p) / count($p), 1) . ')');
verifier(max(array_column($h['series']['cpu'], 2)) === 30.0, '24 h : le maximum garde la pointe');
$np = count($h['presence']);
verifier($np >= 31 && $np <= 34, "24 h : présence, la coupure de 20 min manque ($np créneaux de 5 min sur 37)");
$h = $m->historique('le251', '7j');
$heures = $h['series']['up'];
$creux = array_filter($h['presence'], fn($x) => $x[1] < 0.9);
verifier(count($heures) >= 3 && count($creux) >= 1, '7 j : par heure, l\'heure de la coupure est incomplète');
verifier(abs($h['series']['cpu'][1][1] - 20) < 0.01, '7 j : moyenne horaire exacte');
$h = $m->historique('le251', '1an');
verifier(count($h['series']['up']) >= 1 && $h['series']['temp_disque:sdb'][0][1] == 41, '1 an : par jour');
verifier(($h['etat']['smart'][0]['nom'] ?? '') === 'sdb' && $h['etat']['sauvegarde'] === '2026-10-21-0429', 'état : SMART et sauvegarde');
verifier($m->historique('inconnue', '24h')['series'] === [], 'maison sans mesures : vide');
try {
    $m->historique('le251', '2h');
    verifier(false, 'période inconnue refusée');
} catch (DomainException $e) {
    verifier(true, 'période inconnue refusée');
}
$trop = array_fill(0, MesuresMaisons::PAR_ENVOI + 1, ['t' => time(), 'v' => []]);
try {
    $m->recevoir('le251', $trop);
    verifier(false, 'envoi trop gros refusé');
} catch (DomainException $e) {
    verifier(true, 'envoi trop gros refusé');
}

echo $echecs ? "\n$echecs échec(s)\n" : "\nTout est bon.\n";
exit($echecs ? 1 : 0);
