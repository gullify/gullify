<?php
/**
 * Essai des postes des maisons (PostesMaisons), sur une base MySQL JETABLE seulement (il vide ses tables) :
 * TEST_JETABLE=oui php scripts/test-postes-maisons.php
 */
declare(strict_types=1);

if (getenv('TEST_JETABLE') !== 'oui') {
    fwrite(STDERR, "Base jetable seulement : TEST_JETABLE=oui\n");
    exit(2);
}
require_once __DIR__ . '/../src/PostesMaisons.php';

$echecs = 0;
function verifier(bool $vrai, string $quoi): void
{
    global $echecs;
    echo ($vrai ? 'ok   ' : 'ÉCHEC ') . $quoi . "\n";
    $echecs += $vrai ? 0 : 1;
}
function refuse(callable $f): bool
{
    try {
        $f();
        return false;
    } catch (DomainException $e) {
        return true;
    }
}
/** Un message signé par un poste. */
function message(string $secrete, array $champs): array
{
    $brut = json_encode(['quand' => time(), ...$champs]);
    return ['message' => $brut, 'signature' => base64_encode(sodium_crypto_sign_detached($brut, $secrete))];
}

$db = AppConfig::getDB();
$db->exec('DROP TABLE IF EXISTS gullios_postes');
$db->exec('CREATE TABLE IF NOT EXISTS gullios_maisons (nom VARCHAR(63) NOT NULL PRIMARY KEY, cle VARCHAR(64) NOT NULL,
           dev TINYINT(1) NOT NULL DEFAULT 0)');
$db->exec('DELETE FROM gullios_maisons');
$db->exec("INSERT INTO gullios_maisons (nom, cle, dev) VALUES ('maison', 'x', 0), ('le251', 'y', 0)");
$p = new PostesMaisons($db);

$k1 = sodium_crypto_sign_keypair();
[$s1, $c1] = [sodium_crypto_sign_secretkey($k1), base64_encode(sodium_crypto_sign_publickey($k1))];
$k2 = sodium_crypto_sign_keypair();
[$s2, $c2] = [sodium_crypto_sign_secretkey($k2), base64_encode(sodium_crypto_sign_publickey($k2))];
$base = ['maison' => 'maison', 'poste' => 'poste-maxime', 'version' => '1.57', 'canal' => 'beta'];

verifier(refuse(fn() => $p->ouvrir(message($s1, [...$base, 'maison' => 'inconnue', 'cle' => $c1]))), 'maison inconnue : refusé');
verifier(refuse(fn() => $p->ouvrir(message($s2, [...$base, 'cle' => $c1]))), 'signé par une autre clé que celle annoncée : refusé');
[$m, $l] = $p->ouvrir(message($s1, [...$base, 'cle' => $c1]));
$e = $p->signe($m, $l);
verifier($e['etat'] === 'demande' && $e['dev'] === false, 'premier signe de vie : en demande');
verifier(refuse(fn() => $p->mesures(...$p->ouvrir(message($s1, [...$base, 'cle' => $c1, 'echantillons' => []])))),
         'mesures d\'un poste en demande : refusées');

[$m, $l] = $p->ouvrir(message($s2, [...$base, 'cle' => $c2]));
$p->signe($m, $l);
verifier(count($p->liste('maison')) === 1, 'réinstallé avant d\'être accepté : la demande est remplacée, pas doublée');

$liste = $p->geste('maison', false, 'accepter', 'poste-maxime');
verifier($liste[0]['etat'] === 'accepte', 'la maison accepte');
verifier(refuse(fn() => $p->ouvrir(message($s1, [...$base, 'cle' => $c1]))), 'accepté : une autre clé ne passe plus');
[$m, $l] = $p->ouvrir(message($s2, [...$base, 'cle' => $c2]));
verifier($p->signe($m, $l)['etat'] === 'accepte', 'accepté : son signe de vie le dit');

$t = time() - 120;
$n = $p->mesures(...$p->ouvrir(message($s2, [...$base, 'cle' => $c2, 'echantillons' => [
    ['t' => $t, 'v' => ['cpu' => 12.5, 'mem_total' => 16e9, 'mem_utilisee' => 5e9, 'lat_internet' => 4]],
    ['t' => $t + 60, 'v' => ['cpu' => 20.0]]]])));
verifier($n === 2, 'accepté : ses mesures sont reçues');
$liste = $p->liste('maison');
verifier(($liste[0]['courbes']['cpu'] ?? []) === [12.5, 20.0], 'la liste rend la courbe de la dernière heure');
verifier(isset($p->historique('maison', 'poste-maxime', '6h')['series']), 'l\'historique du poste se lit');
verifier(refuse(fn() => $p->historique('le251', 'poste-maxime', '6h')), 'une autre maison ne lit pas son historique');

verifier(refuse(fn() => $p->geste('maison', false, 'dev-oui', 'poste-maxime')), 'canal dev : refusé si la maison n\'est pas Dev');
$db->exec("UPDATE gullios_maisons SET dev = 1 WHERE nom = 'maison'");
$p->geste('maison', true, 'dev-oui', 'poste-maxime');
verifier($p->etat('maison', 'poste-maxime')['dev'] === true, 'maison Dev : le poste reçoit le canal dev');
$db->exec("UPDATE gullios_maisons SET dev = 0 WHERE nom = 'maison'");
verifier($p->etat('maison', 'poste-maxime')['dev'] === false, 'la maison n\'est plus Dev : son poste non plus');

verifier(refuse(fn() => $p->geste('le251', false, 'accepter', 'poste-maxime')), 'une autre maison ne l\'accepte pas');
verifier($p->geste('maison', false, 'retirer', 'poste-maxime') === [], 'la maison le retire');
[$m, $l] = $p->ouvrir(message($s1, [...$base, 'cle' => $c1]));
verifier($p->signe($m, $l)['etat'] === 'demande', 'retiré : il peut redemander (une nouvelle demande)');

echo $echecs ? "\n$echecs échec(s)\n" : "\nTout est bon.\n";
exit($echecs ? 1 : 0);
