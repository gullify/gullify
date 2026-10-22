<?php
/**
 * Essai des maisons amies (AmiesMaisons), sur une base MySQL JETABLE seulement (il vide ses tables) :
 * TEST_JETABLE=oui GULLIOS_REGISTRE_CLE=<clé d'essai> php scripts/test-amies-maisons.php
 */
declare(strict_types=1);

if (getenv('TEST_JETABLE') !== 'oui') {
    fwrite(STDERR, "Base jetable seulement : TEST_JETABLE=oui\n");
    exit(2);
}
require_once __DIR__ . '/../src/AmiesMaisons.php';

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

$db = AppConfig::getDB();
$db->exec('DROP TABLE IF EXISTS gullios_amies');
$db->exec('CREATE TABLE IF NOT EXISTS gullios_maisons (nom VARCHAR(63) NOT NULL PRIMARY KEY, cle VARCHAR(64) NOT NULL,
           version VARCHAR(40) NULL, vue_le DATETIME NULL)');
$db->exec("DELETE FROM gullios_maisons");
$db->exec("INSERT INTO gullios_maisons (nom, cle, version, vue_le) VALUES ('maison', 'x', '1.47', NOW()), ('le251', 'y', '1.47', NOW()),
           ('chalet', 'z', '1.46', NULL)");
$a = new AmiesMaisons($db);
$publique = sodium_crypto_sign_publickey_from_secretkey(base64_decode(getenv('GULLIOS_REGISTRE_CLE')));

verifier(refuse(fn() => $a->geste('maison', 'inviter', 'inconnue')), 'inviter une maison qui n\'existe pas : refusé');
verifier(refuse(fn() => $a->geste('maison', 'inviter', 'maison')), 's\'inviter soi-même : refusé');
$l = $a->geste('maison', 'inviter', 'le251');
verifier($l[0]['etat'] === 'envoyee' && !isset($l[0]['billet']), 'invitation envoyée, pas de billet');
$l = $a->liste('le251');
verifier($l[0]['nom'] === 'maison' && $l[0]['etat'] === 'recue', 'le251 voit l\'invitation reçue');
verifier(refuse(fn() => $a->geste('maison', 'accepter', 'le251')), 'accepter sa propre invitation : refusé');
$l = $a->geste('le251', 'accepter', 'maison');
verifier($l[0]['etat'] === 'amie' && isset($l[0]['billet']), 'acceptée : amies, avec un billet');

[$c, $s] = array_map(fn($x) => base64_decode(strtr($x, '-_', '+/')), explode('.', $l[0]['billet']));
$contenu = json_decode($c, true);
verifier(sodium_crypto_sign_verify_detached($s, $c, $publique), 'billet signé par la clé du registre');
verifier($contenu['usage'] === 'amie' && $contenu['de'] === 'le251' && $contenu['chez'] === 'maison' && !isset($contenu['cible']),
         'billet : de le251, chez maison, sans « cible » (inutilisable pour le bureau)');
verifier($contenu['expire'] > time() + 3600, 'billet valable des heures');
verifier($a->liste('maison')[0]['etat'] === 'amie', 'amie des deux côtés');

$a->geste('chalet', 'inviter', 'maison');
$l = $a->geste('maison', 'inviter', 'chalet');
verifier(count($l) === 2 && $l[0]['nom'] === 'chalet' && $l[0]['etat'] === 'amie', 'inviter qui nous a invitées = accepter');
verifier($l[0]['vue_il_y_a'] === null, 'maison jamais vue : vue_il_y_a null');

$l = $a->geste('le251', 'retirer', 'maison');
verifier($l === [], 'retirée par le251');
verifier(count($a->liste('maison')) === 1, 'et disparue chez maison');
verifier(refuse(fn() => $a->geste('maison', 'sauter', 'le251')), 'geste inconnu : refusé');

echo $echecs ? "\n$echecs échec(s)\n" : "\nTout est bon.\n";
exit($echecs ? 1 : 0);
