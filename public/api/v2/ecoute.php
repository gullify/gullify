<?php
/**
 * Gullify API v2 — « Écouter sur… » : billets d'écoute pour un appareil sans compte ici.
 *
 *   POST ?action=billets {chemins: [file_path…]} → session requise
 *        → {expire, billets: {file_path: billet}}
 *
 * L'app construit elle-même `<serveur>/stream.php?path=…&ecoute=<billet>` et l'envoie à
 * l'appareil choisi. Voir src/BilletEcoute.php.
 */
declare(strict_types=1);

require_once __DIR__ . '/_v2.php';
require_once __DIR__ . '/../../../src/BilletEcoute.php';

$action = $_GET['action'] ?? 'billets';
$body   = v2_body();

if ($action !== 'billets') v2_fail('invalid_request', 'Action inconnue', 400);
if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') v2_fail('invalid_request', 'POST attendu', 405);

$ctx      = v2_auth();
$personne = (string)$ctx['user']['username'];
$chemins  = $body['chemins'] ?? null;
if (!is_array($chemins) || $chemins === [] || count($chemins) > 500) {
    v2_fail('invalid_request', 'De 1 à 500 chemins', 400);
}

$billets = [];
$maintenant = time();
foreach ($chemins as $c) {
    if (!is_string($c) || $c === '' || strlen($c) > 2000) continue;
    $billets[$c] = BilletEcoute::creer($personne, $c, $maintenant);
}
v2_ok(['expire' => $maintenant + BilletEcoute::DUREE, 'billets' => $billets]);
