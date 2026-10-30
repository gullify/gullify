<?php
/**
 * Essai des ordres aux maisons (OrdresMaisons), sur une base MySQL JETABLE seulement (il vide ses tables) :
 *   TEST_JETABLE=oui php scripts/test-ordres-maisons.php
 */
declare(strict_types=1);

if (getenv('TEST_JETABLE') !== 'oui') {
    fwrite(STDERR, "Base jetable seulement : TEST_JETABLE=oui\n");
    exit(2);
}
require_once __DIR__ . '/../src/OrdresMaisons.php';

$echecs = 0;
function verifier(bool $vrai, string $quoi): void
{
    global $echecs;
    echo ($vrai ? 'ok   ' : 'ÉCHEC ') . $quoi . "\n";
    if (!$vrai) {
        $echecs++;
    }
}
function refuse(callable $f, string $quoi): void
{
    try {
        $f();
        verifier(false, $quoi);
    } catch (DomainException $e) {
        verifier(true, $quoi . ' (' . $e->getMessage() . ')');
    }
}

AppConfig::getDB()->exec('DROP TABLE IF EXISTS gullios_ordres');
AppConfig::getDB()->exec('DROP TABLE IF EXISTS gullios_maisons_apps');
$o = new OrdresMaisons();

refuse(fn() => $o->ordonner('le251', 'rm -rf /'), 'un geste hors liste est refusé');
refuse(fn() => $o->ordonner('le251', 'maj-app', 'pixdb'), 'une app hors liste est refusée');
refuse(fn() => $o->ordonner('Le 251', 'maj-gullios'), 'un nom de maison invalide est refusé');
$a = $o->ordonner('le251', 'maj-app', 'gulliscan');
verifier($o->ordonner('le251', 'maj-app', 'gulliscan') === $a, 'le même ordre en attente n\'est pas empilé');
$b = $o->ordonner('le251', 'maj-gullios');
verifier($b !== $a, 'un autre geste fait un autre ordre');

$d = 'sha256:' . str_repeat('ab', 32);
$pris = $o->relever('le251', ['gulliscan-maison' => [$d, 'pas-un-digest'], '../x' => [$d]]);
verifier(count($pris) === 2 && $pris[0]['geste'] === 'maj-app' && $pris[0]['app'] === 'gulliscan', 'la maison relève ses deux ordres');
verifier($o->relever('le251', ['gulliscan-maison' => [$d]]) === [], 'un ordre relevé ne revient pas');
verifier($o->relever('maison', []) === [], 'une autre maison ne voit pas les ordres de le251');
$etat = $o->etat();
verifier(($etat['apps']['le251']['images']['gulliscan-maison'] ?? null) === [$d], 'seuls les digests valides sont gardés');
verifier(!isset($etat['apps']['le251']['images']['../x']), 'un nom d\'image invalide est écarté');

verifier($o->rendre('maison', $a, true, 'non')['rendu'] === false, 'une maison ne rend pas l\'ordre d\'une autre');
verifier($o->rendre('le251', $a, true, 'Relancée sur latest.')['rendu'] === true, 'la maison rend son ordre');
verifier($o->rendre('le251', $a, false, 'deux fois')['rendu'] === false, 'un ordre ne se rend qu\'une fois');
$fini = array_values(array_filter($o->etat()['ordres'], fn($x) => (int)$x['id'] === $a))[0];
verifier($fini['etat'] === 'ok' && $fini['sortie'] === 'Relancée sur latest.', 'l\'atelier voit le résultat');
verifier($o->ordonner('le251', 'maj-app', 'gulliscan') !== $a, 'après un ordre fini, un nouveau peut partir');

echo $echecs ? "\n$echecs échec(s)\n" : "\nTout est bon.\n";
exit($echecs ? 1 : 0);
