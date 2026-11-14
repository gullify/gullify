<?php
/**
 * Essai des billets d'écoute (« Écouter sur… »), sans base : APP_SECRET=essai php scripts/test-billet-ecoute.php
 */
declare(strict_types=1);
require_once __DIR__ . '/../src/BilletEcoute.php';

$echecs = 0;
function verifier(bool $vrai, string $quoi): void {
    global $echecs;
    echo ($vrai ? 'ok   ' : 'ÉCHEC ') . $quoi . "\n";
    $echecs += $vrai ? 0 : 1;
}

$t = 1_800_000_000;
$b = BilletEcoute::creer('maxime', 'Harmonium/Harmonium/01 Pour un instant.flac', $t);
verifier(BilletEcoute::verifier($b, 'Harmonium/Harmonium/01 Pour un instant.flac', $t) === 'maxime', 'le billet ouvre son fichier');
verifier(BilletEcoute::verifier($b, 'Harmonium/Harmonium/02 Autre.flac', $t) === null, 'pas un autre fichier');
verifier(BilletEcoute::verifier($b, 'Harmonium/Harmonium/01 Pour un instant.flac', $t + BilletEcoute::DUREE + 1) === null, 'périmé après 12 h');
[$e, $p, $s] = explode('.', $b);
$autre = rtrim(strtr(base64_encode('fred'), '+/', '-_'), '=');
verifier(BilletEcoute::verifier("$e.$autre.$s", 'Harmonium/Harmonium/01 Pour un instant.flac', $t) === null, 'personne changée = refusé');
verifier(BilletEcoute::verifier(($e + 9999) . ".$p.$s", 'Harmonium/Harmonium/01 Pour un instant.flac', $t) === null, 'expiration allongée = refusé');
verifier(BilletEcoute::verifier(['x'], 'a', $t) === null && BilletEcoute::verifier('', 'a', $t) === null, 'forme invalide = refusé');
$b2 = BilletEcoute::creer('marie-ève@x.ca', 'a/b.mp3', $t);
verifier(BilletEcoute::verifier($b2, 'a/b.mp3', $t) === 'marie-ève@x.ca', 'nom avec accent et @');

echo $echecs ? "$echecs échec(s)\n" : "tout passe\n";
exit($echecs ? 1 : 0);
