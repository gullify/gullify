<?php
/**
 * Essai de la table commune des recettes, sur une base MySQL JETABLE seulement (il vide ses
 * tables) : TEST_JETABLE=oui php scripts/test-table-recettes.php
 */
declare(strict_types=1);

if (getenv('TEST_JETABLE') !== 'oui') {
    fwrite(STDERR, "Base jetable seulement : TEST_JETABLE=oui\n");
    exit(2);
}
require_once __DIR__ . '/../src/TableRecettes.php';

$echecs = 0;
function verifier(bool $vrai, string $quoi): void
{
    global $echecs;
    echo ($vrai ? 'ok   ' : 'ÉCHEC ') . $quoi . "\n";
    $echecs += $vrai ? 0 : 1;
}
function refuse(callable $f, string $quoi): void
{
    try { $f(); verifier(false, $quoi); } catch (DomainException $e) { verifier(true, "$quoi ({$e->getMessage()})"); }
}

$db = AppConfig::getDB();
foreach (['table_jetons', 'table_compteur', 'table_recettes'] as $t) {
    $db->exec("DROP TABLE IF EXISTS $t");
}
$dossier = sys_get_temp_dir() . '/table-essai-' . bin2hex(random_bytes(3));
$t = new TableRecettes($db, $dossier);

$ja = $t->nouveauJeton('maison', 'gullieats');
$jb = $t->nouveauJeton('le251', 'gullieats');
verifier($t->maisonDuJeton($ja) === 'maison' && $t->maisonDuJeton($jb) === 'le251', 'jetons → maisons');
verifier($t->maisonDuJeton(str_repeat('0', 64)) === null && $t->maisonDuJeton('x') === null, 'jeton inconnu refusé');
$ja2 = $t->nouveauJeton('maison', 'gullieats');
verifier($t->maisonDuJeton($ja) === null && $t->maisonDuJeton($ja2) === 'maison', 'un nouveau jeton remplace l\'ancien');

$img = (function () { $i = imagecreatetruecolor(4, 4); ob_start(); imagejpeg($i); return ob_get_clean(); })();
$h = hash('sha256', $img);
$manq = $t->deposer('maison', [
    ['uid' => '1', 'lien' => 'https://www.ricardocuisine.com/recettes/1', 'contenu' => ['titre' => 'Pâté']],
    ['uid' => '2', 'contenu' => ['titre' => 'Tarte de Mimi', 'image' => $h, 'pages' => [$h]]],
]);
verifier($manq === [$h], 'le fichier cité manque');
refuse(fn() => $t->poserFichier($h, 'pas une image'), 'empreinte fausse');
refuse(fn() => $t->poserFichier(hash('sha256', 'abc'), 'abc'), 'pas une image');
$t->poserFichier($h, $img);
verifier($t->aFichier($h) && file_get_contents($t->chemin($h)) === $img, 'fichier posé');
verifier($t->deposer('maison', [['uid' => '2', 'contenu' => ['titre' => 'Tarte de Mimi', 'image' => $h]]]) === [], 'plus rien ne manque');
refuse(fn() => $t->deposer('maison', [['uid' => '../x', 'contenu' => []]]), 'uid refusé');

$c = $t->changements('le251', 0);
verifier(count($c['recettes']) === 2 && $c['recettes'][1]['contenu']['titre'] === 'Tarte de Mimi', 'le251 voit les 2 recettes');
verifier($t->changements('maison', 0)['recettes'] === [], 'on ne se voit pas soi-même');
$fin = $c['fin'];
verifier($t->changements('le251', $fin)['recettes'] === [], 'rien après le curseur');

verifier($t->retirer('maison', ['1']) === 1, 'retirer une recette');
$c = $t->changements('le251', $fin);
verifier(count($c['recettes']) === 1 && $c['recettes'][0]['supprimee'] && $c['recettes'][0]['contenu'] === null, 'pierre tombale suivie');
verifier($t->maisons() !== [] && $t->maisons()[0]['recettes'] === 1, 'maisons : 1 recette restante');
$t->deposer('le251', [['uid' => '9', 'contenu' => ['titre' => 'Sucre à la crème']]]);
verifier($t->retirer('maison', null) === 1, 'arrêter de partager retire tout');
verifier(count($t->maisons()) === 1 && $t->maisons()[0]['nom'] === 'le251', 'il ne reste que le251');

array_map('unlink', glob("$dossier/*/*"));
echo $echecs ? "\n$echecs échec(s)\n" : "\nTout est vert.\n";
exit($echecs ? 1 : 0);
