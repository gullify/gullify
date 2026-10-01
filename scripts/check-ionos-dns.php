<?php
/**
 * Vérifie que le client IONOS dit vrai, contre la vraie zone.
 *
 * `src/IonosDns.php` a été écrit d'après la documentation, sans jamais parler
 * au service — la clé n'existait pas encore. Tant que ce script n'est pas passé
 * au vert, cette classe est une hypothèse, pas du code éprouvé.
 *
 * Il pose un enregistrement sur un nom d'essai, le relit, le déplace, le relit
 * encore, puis le retire — et vérifie à chaque étape. Le nom d'essai commence
 * par « verif- » suivi du moment : il ne peut pas marcher sur un vrai serveur.
 *
 * Usage (sur le serveur central, avec la clé dans le .env) :
 *   docker exec gullify php /app/scripts/check-ionos-dns.php
 */
declare(strict_types=1);

require_once __DIR__ . '/../src/AppConfig.php';
require_once __DIR__ . '/../src/IonosDns.php';

$cle = (string)AppConfig::get('registry.ionos_key', '');
$domaine = (string)AppConfig::get('registry.domain', '');

if ($cle === '' || $domaine === '') {
    fwrite(STDERR, "IONOS_API_KEY et REGISTRY_DOMAIN doivent être renseignés dans le .env.\n");
    exit(2);
}

$dns = new IonosDns($cle, $domaine);
$nom = 'verif-' . date('YmdHis') . '.' . $domaine;
$ok = 0;
$ko = 0;

function verifie(string $quoi, bool $vrai, string $detail = ''): void
{
    global $ok, $ko;
    if ($vrai) { $ok++; echo "  ok    $quoi\n"; }
    else { $ko++; echo "  ÉCHEC $quoi $detail\n"; }
}

try {
    echo "Zone : $domaine — nom d'essai : $nom\n\n";

    $id = $dns->upsertA($nom, '203.0.113.10');
    verifie('la création rend un identifiant', $id !== '');
    verifie('et le nom se relit', $dns->lookupA($nom) === '203.0.113.10', (string)$dns->lookupA($nom));

    $id2 = $dns->upsertA($nom, '203.0.113.20');
    verifie('la mise à jour garde le même enregistrement', $id2 === $id, "$id → $id2");
    verifie('et la nouvelle adresse se relit', $dns->lookupA($nom) === '203.0.113.20');

    $dns->deleteA($nom);
    verifie('le retrait fonctionne', $dns->lookupA($nom) === null);

    $dns->deleteA($nom); // deux fois : ne doit pas se plaindre
    verifie('retirer deux fois ne lève rien', true);

    verifie('un nom absent se relit en null', $dns->lookupA('absent-pour-de-bon.' . $domaine) === null);
} catch (Throwable $e) {
    echo "  ÉCHEC exception : " . $e->getMessage() . "\n";
    $ko++;
    // Au cas où l'essai se serait arrêté en laissant une trace dans la zone.
    try { $dns->deleteA($nom); } catch (Throwable) {}
}

printf("\n%s %d vérifications passées, %d en échec\n", $ko ? '✗' : '✓', $ok, $ko);
exit($ko ? 1 : 0);
