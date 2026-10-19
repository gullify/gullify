<?php
/**
 * Gullify API v2 - Ping (no auth)
 * GET /api/v2/ping.php → {server, apiVersion, connexion, comptes}
 *
 * `connexion` dit au client quel écran de connexion montrer :
 * « courriel » (comptes de la maison, COMPTES_URL posé) ou « nom_utilisateur ».
 */
require_once __DIR__ . '/_v2.php';
require_once __DIR__ . '/../../../src/Comptes.php';

$comptes = Comptes::actif();

v2_ok([
    'server'     => 'Gullify',
    'apiVersion' => 'v2',
    'connexion'  => $comptes ? 'courriel' : 'nom_utilisateur',
    'comptes'    => $comptes,
]);
