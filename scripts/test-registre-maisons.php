<?php
/**
 * Essai du registre des maisons GulliOS, sur une base MySQL JETABLE seulement (il crée et vide
 * gullios_maisons) : exige TEST_JETABLE=oui, plus REGISTRY_DOMAIN et GULLIOS_REGISTRE_CLE d'essai.
 *
 *   TEST_JETABLE=oui php scripts/test-registre-maisons.php
 */
declare(strict_types=1);

if (getenv('TEST_JETABLE') !== 'oui') {
    fwrite(STDERR, "Base jetable seulement : TEST_JETABLE=oui\n");
    exit(2);
}
require_once __DIR__ . '/../src/RegistreMaisons.php';

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

AppConfig::getDB()->exec('DROP TABLE IF EXISTS gullios_maisons');
$publiees = [];
$registre = new RegistreMaisons(function (string $nom) use (&$publiees) { return $publiees[$nom] ?? null; });

$paires = [];
function corps(string $nom, array $champs, ?string $secrete = null): array
{
    global $paires;
    $paires[$nom] ??= sodium_crypto_sign_keypair();
    $message = json_encode(['nom' => $nom, 'quand' => time()] + $champs);
    return ['message' => $message, 'signature' => base64_encode(sodium_crypto_sign_detached(
        $message, $secrete ?? sodium_crypto_sign_secretkey($paires[$nom])))];
}
function cle(string $nom): string
{
    global $paires;
    $paires[$nom] ??= sodium_crypto_sign_keypair();
    return base64_encode(sodium_crypto_sign_publickey($paires[$nom]));
}

// Inscription : seulement si la maison publie bien sa clé
refuse(fn() => $registre->inscrire($registre->ouvrir(corps('maison', ['cle' => cle('maison')]), true)[0]),
       'inscription refusée sans clé publiée');
$publiees['maison'] = cle('maison');
$publiees['le251'] = cle('le251');
$e = $registre->inscrire($registre->ouvrir(corps('maison', ['cle' => cle('maison'), 'version' => '1.31',
                                                                   'canal' => 'beta', 'aide' => true]), true)[0]);
verifier($e === ['dev' => false, 'designee' => false], 'maison inscrite, ni Dev ni désignée');
$registre->inscrire($registre->ouvrir(corps('le251', ['cle' => cle('le251'), 'canal' => 'stable', 'aide' => true]), true)[0]);

// Signatures
refuse(fn() => $registre->ouvrir(corps('maison', [], sodium_crypto_sign_secretkey(sodium_crypto_sign_keypair()))),
       'signature d\'une autre clé refusée');
refuse(fn() => $registre->ouvrir(corps('inconnue', [])), 'maison inconnue refusée');
$vieux = json_encode(['nom' => 'maison', 'quand' => time() - 3600]);
refuse(fn() => $registre->ouvrir(['message' => $vieux, 'signature' => base64_encode(
    sodium_crypto_sign_detached($vieux, sodium_crypto_sign_secretkey($paires['maison'])))]), 'message d\'il y a une heure refusé');

// Le rôle Dev
verifier($registre->fixerDev('maison', true), 'maison passée Dev par l\'atelier');
[$m, $x] = $registre->ouvrir(corps('maison', []));
verifier((bool)$x['dev'], 'maison est Dev');
$liste = $registre->liste();
verifier(count($liste) === 2 && $liste[0]['nom'] === 'le251', 'liste des maisons');

$d = $registre->designer('le251');
verifier((bool)preg_match('/^[A-Z0-9]{3}-[A-Z0-9]{3}$/', $d['code']), 'code de désignation ' . $d['code']);
verifier($registre->etat('le251')['designee'] === true, 'le251 désignée');
[$m2, $x2] = $registre->ouvrir(corps('le251', ['code' => 'AAA-AAA']));
refuse(fn() => $registre->devenirDev($m2, $x2), 'mauvais code refusé');
[$m2, $x2] = $registre->ouvrir(corps('le251', ['code' => strtolower($d['code'])]));
verifier($registre->devenirDev($m2, $x2)['dev'] === true, 'bon code (minuscules) : le251 devient Dev');
refuse(fn() => $registre->designer('le251'), 'désigner une maison déjà Dev refusé');

// Cinq mauvais essais annulent le code
$publiees['chalet'] = cle('chalet');
$registre->inscrire($registre->ouvrir(corps('chalet', ['cle' => cle('chalet')]), true)[0]);
$registre->designer('chalet');
for ($i = 0; $i < 5; $i++) {
    [$m3, $x3] = $registre->ouvrir(corps('chalet', ['code' => 'XXX-XXX']));
    try { $registre->devenirDev($m3, $x3); } catch (DomainException) {}
}
verifier($registre->etat('chalet')['designee'] === false, 'cinq essais ratés : code annulé');

// Billet
refuse(fn() => $registre->billet($m, 'chalet'), 'billet refusé : aide coupée sur chalet');
$b = $registre->billet(['nom' => 'maison', 'personne' => 'Maxime'], 'le251');
[$contenu, $sig] = array_map(fn($s) => base64_decode(strtr($s, '-_', '+/')), explode('.', $b['billet']));
$publique = sodium_crypto_sign_publickey_from_secretkey(base64_decode(getenv('GULLIOS_REGISTRE_CLE')));
verifier(sodium_crypto_sign_verify_detached($sig, $contenu, $publique), 'billet signé par l\'atelier');
$c = json_decode($contenu, true);
verifier($c['cible'] === 'le251' && $c['de'] === 'maison' && $c['personne'] === 'Maxime'
         && $c['expire'] > time() && $c['expire'] <= time() + 120, 'contenu du billet');

echo $echecs ? "\n{$echecs} échec(s)\n" : "\nTout passe.\n";
exit($echecs ? 1 : 0);
