<?php
/**
 * Accorder ou retirer le rôle Dev d'une maison GulliOS, depuis l'atelier (la toute première
 * maison Dev n'a personne pour la désigner) :
 *
 *   docker exec gullify php scripts/registre-dev.php <nom> oui|non
 *
 * La maison doit déjà être inscrite (elle s'inscrit d'elle-même, GulliOS 1.31).
 */
declare(strict_types=1);

require_once __DIR__ . '/../src/RegistreMaisons.php';

[$_moi, $nom, $choix] = $argv + [null, '', ''];
if ($nom === '' || !in_array($choix, ['oui', 'non'], true)) {
    fwrite(STDERR, "usage : php scripts/registre-dev.php <nom> oui|non\n");
    exit(2);
}
if (!RegistreMaisons::actif()) {
    fwrite(STDERR, "Le registre n'est pas configuré ici.\n");
    exit(1);
}
$ok = (new RegistreMaisons())->fixerDev(strtolower($nom), $choix === 'oui');
echo $ok ? "{$nom} : Dev = {$choix}\n" : "{$nom} : maison inconnue (pas encore inscrite)\n";
exit($ok ? 0 : 1);
