<?php
/**
 * Sonde du service d'inscription : tout le parcours, contre une vraie base
 * MySQL (gullify_essai), un DNS factice et des courriels écrits dans un
 * journal. Les avertissements sont promus en échec — un service qui « marche »
 * en crachant des warnings ne marche pas.
 */
declare(strict_types=1);

error_reporting(E_ALL);
set_error_handler(function ($n, $m, $f, $l) { throw new ErrorException("$m ($f:$l)"); });

require_once __DIR__ . '/../src/Registry.php';

$ok = 0;
$ko = 0;

function verifie(string $quoi, bool $vrai, string $detail = ''): void
{
    global $ok, $ko;
    if ($vrai) { $ok++; printf("  ok    %s\n", $quoi); }
    else { $ko++; printf("  ÉCHEC %s %s\n", $quoi, $detail); }
}

function refuse(string $quoi, callable $f): ?string
{
    try { $f(); verifie($quoi . ' (devait refuser)', false); return null; }
    catch (RuntimeException $e) { verifie($quoi, true); return $e->getMessage(); }
}

// Table rase entre deux passages.
$db = AppConfig::getDB();
$db->exec('DROP TABLE IF EXISTS registry_servers');
$db->exec('DROP TABLE IF EXISTS registry_events');
foreach (['/tmp/dns-fictif.json', '/tmp/courriels.log'] as $f) {
    if (is_file($f)) { unlink($f); }
}

$dns = new FakeDns('/tmp/dns-fictif.json');
$poste = new Mailer('journal', 'GulliFY <bonjour@gullify.app>', null, null, '/tmp/courriels.log');
$r = new Registry($dns, $poste);

echo "\n— Les noms qu'on refuse —\n";
verifie('« ab » est trop court', $r->refusDuNom('ab') !== null);
verifie('trente lettres passent', $r->refusDuNom(str_repeat('a', 30)) === null);
verifie('trente-et-une, non', $r->refusDuNom(str_repeat('a', 31)) !== null);
verifie('« Papa » majuscule accepté (ramené en minuscules)', $r->refusDuNom('Papa') === null);
verifie('« pa_pa » refusé', $r->refusDuNom('pa_pa') !== null);
verifie('« -papa » refusé', $r->refusDuNom('-papa') !== null);
verifie('« papa- » refusé', $r->refusDuNom('papa-') !== null);
verifie('« pa--pa » refusé', $r->refusDuNom('pa--pa') !== null);
verifie('« www » réservé', $r->refusDuNom('www') !== null);
verifie('« download » réservé', $r->refusDuNom('download') !== null);
verifie('« chez-papa » accepté', $r->refusDuNom('chez-papa') === null);

echo "\n— Réserver —\n";
refuse('une adresse de courriel bidon', fn() => $r->reserver('chez-papa', 'pas-une-adresse', '1.2.3.4'));
$reservation = $r->reserver('chez-papa', 'papa@exemple.ca', '1.2.3.4');
verifie('la réservation renvoie un identifiant', strlen($reservation) === 32);
verifie('le courriel est parti (journal)', str_contains((string)@file_get_contents('/tmp/courriels.log'), 'chez-papa.gullify.app'));
verifie('le lien de confirmation est dans le courriel',
    (bool)preg_match('/confirmer-serveur\.php\?code=([a-f0-9]{32})/', (string)file_get_contents('/tmp/courriels.log')));
refuse('le même nom, réservé une seconde fois', fn() => $r->reserver('chez-papa', 'autre@exemple.ca', '5.6.7.8'));
verifie('le nom n\'est pas encore publié au DNS', $dns->lookupA('chez-papa.gullify.app') === null);

echo "\n— Confirmer —\n";
refuse('un code inventé', fn() => $r->confirmer('00000000000000000000000000000000'));
preg_match('/code=([a-f0-9]{32})/', (string)file_get_contents('/tmp/courriels.log'), $m);
$fqdn = $r->confirmer($m[1]);
verifie('le nom entier est rendu', $fqdn === 'chez-papa.gullify.app');
verifie('le DNS pointe sur l\'IP de la réservation', $dns->lookupA('chez-papa.gullify.app') === '1.2.3.4');
refuse('le même code, une seconde fois', fn() => $r->confirmer($m[1]));

echo "\n— Le jeton —\n";
$etat = $r->etatReservation($reservation);
verifie('l\'état est « actif »', $etat['state'] === 'active', json_encode($etat));
verifie('le jeton est remis une fois', is_string($etat['token']) && strlen($etat['token']) === 48);
$jeton = $etat['token'];
$encore = $r->etatReservation($reservation);
verifie('et une seule', $encore['token'] === null);
verifie('il ne reste que l\'empreinte en base',
    (string)$db->query("SELECT token_pickup FROM registry_servers WHERE name='chez-papa'")->fetchColumn() === '');

echo "\n— Suivre l'adresse IP —\n";
refuse('un jeton inventé', fn() => $r->majIp('xxxx', '9.9.9.9'));
refuse('une adresse qui n\'en est pas une', fn() => $r->majIp($jeton, 'bonjour'));
$sans = $r->majIp($jeton, '1.2.3.4');
verifie('même adresse : on ne touche pas au DNS', $sans['changed'] === false);
$avec = $r->majIp($jeton, '24.48.72.96');
verifie('adresse changée : le DNS suit', $avec['changed'] === true && $dns->lookupA('chez-papa.gullify.app') === '24.48.72.96');

echo "\n— La limite par connexion —\n";
$r->reserver('maison-un', 'un@exemple.ca', '7.7.7.7');
$r->reserver('maison-deux', 'deux@exemple.ca', '7.7.7.7');
$r->reserver('maison-trois', 'trois@exemple.ca', '7.7.7.7');
refuse('la quatrième depuis la même connexion', fn() => $r->reserver('maison-quatre', 'quatre@exemple.ca', '7.7.7.7'));
$r->reserver('ailleurs', 'cinq@exemple.ca', '8.8.8.8');
verifie('une autre connexion n\'est pas punie', true);

echo "\n— Ce qui échoue, on le note —\n";
$r->noter('cgnat', 'chez-papa', 'adresse 100.70.0.1', '1.2.3.4');
$r->noter('routeur-ferme', null, 'upnp refusé', '5.5.5.5');
$r->noter('cgnat', null, null, '6.6.6.6');
$comptes = $r->comptageDesEchecs();
verifie('deux cas de réseau d\'opérateur', ($comptes['cgnat'] ?? 0) === 2, json_encode($comptes));
verifie('un routeur fermé', ($comptes['routeur-ferme'] ?? 0) === 1);

echo "\n— Révoquer —\n";
$r->revoquer('chez-papa', 'essai');
verifie('le DNS est retiré', $dns->lookupA('chez-papa.gullify.app') === null);
verifie('le nom reste bloqué', $r->refusDuNom('chez-papa') !== null);
refuse('le jeton ne vaut plus rien', fn() => $r->majIp($jeton, '1.1.1.1'));

echo "\n— Entretien : les noms oubliés —\n";
$db->exec("UPDATE registry_servers SET last_seen = DATE_SUB(NOW(), INTERVAL 80 DAY) WHERE name='maison-un'");
$db->exec("UPDATE registry_servers SET state='active', token_hash='x', last_seen = DATE_SUB(NOW(), INTERVAL 100 DAY) WHERE name='maison-deux'");
$db->exec("UPDATE registry_servers SET state='active' WHERE name='maison-un'");
$dns->upsertA('maison-deux.gullify.app', '3.3.3.3');
$bilan = $r->entretien();
verifie('celui de 80 jours est averti', $bilan['avertis'] === 1, json_encode($bilan));
verifie('celui de 100 jours est libéré', $bilan['liberes'] === 1);
verifie('et son DNS retiré', $dns->lookupA('maison-deux.gullify.app') === null);
verifie('son nom redevient libre', $r->refusDuNom('maison-deux') === null);
$deuxieme = $r->entretien();
verifie('on n\'avertit pas deux fois', $deuxieme['avertis'] === 0, json_encode($deuxieme));

printf("\n%s %d vérifications passées, %d en échec\n", $ko ? '✗' : '✓', $ok, $ko);
exit($ko ? 1 : 0);
