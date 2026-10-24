<?php
/**
 * Une fois (GulliOS 1.50) : pose « *.nom.gullify.app » pour les maisons déjà actives, à l'adresse de
 * leur nom. Les nouvelles le reçoivent à la confirmation, et il suit l'adresse (Registry::poserDns).
 * Sans danger à relancer : upsertA met à jour ce qui existe.
 *   docker compose exec -T app php scripts/registre-dns-sous-domaines.php [--apply]
 */
declare(strict_types=1);

require_once __DIR__ . '/../src/Registry.php';

$apply = in_array('--apply', $argv, true);
$r = new Registry();
$db = AppConfig::getDB();
foreach ($db->query("SELECT name, ip FROM registry_servers WHERE state = 'active' AND ip IS NOT NULL ORDER BY name") as $l) {
    $fqdn = $l['name'] . '.' . $r->domaine();
    echo ($apply ? 'posé  ' : 'à poser ') . "*.$fqdn\n";
    if ($apply) {
        $r->poserDns($fqdn, (string)$l['ip']);
    }
}
echo $apply ? "Fait.\n" : "Essai seulement : --apply pour poser.\n";
