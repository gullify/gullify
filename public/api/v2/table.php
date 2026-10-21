<?php
/**
 * La table commune des recettes (voir src/TableRecettes.php). Jeton de la maison en
 * « Authorization: Bearer », délivré par gullios.php?action=jeton-table.
 *
 *   POST ?action=deposer            {recettes: [{uid, lien, contenu}]}   → {manquants: [empreintes]}
 *   POST ?action=retirer            {uids: [..]} ou {tout: true}         → {retirees}
 *   PUT  ?action=fichier&h=<sha256> les octets de l'image
 *   GET  ?action=fichier&h=<sha256>
 *   GET  ?action=changements&depuis=<seq>                                → {recettes, fin, encore}
 *   GET  ?action=maisons                                                 → [{nom, recettes, maj}]
 */
require_once __DIR__ . '/_v2.php';
require_once __DIR__ . '/../../../src/RegistreMaisons.php';
require_once __DIR__ . '/../../../src/TableRecettes.php';

if (!RegistreMaisons::actif()) {
    v2_fail('table_absente', 'Ce serveur ne tient pas la table commune.', 404);
}

try {
    $table = new TableRecettes();
    $entete = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    $maison = preg_match('/^Bearer\s+(\S+)$/', $entete, $m) ? $table->maisonDuJeton($m[1]) : null;
    if ($maison === null) {
        v2_fail('jeton', 'Jeton de la table absent ou refusé.', 401);
    }
    $methode = $_SERVER['REQUEST_METHOD'] ?? 'GET';
    $action = $_GET['action'] ?? '';
    $h = strtolower((string)($_GET['h'] ?? ''));

    if ($action === 'fichier' && $methode === 'GET') {
        if (!$table->aFichier($h)) {
            v2_fail('absent', 'Fichier inconnu.', 404);
        }
        $chemin = $table->chemin($h);
        header('Content-Type: ' . (mime_content_type($chemin) ?: 'application/octet-stream'));
        header('Content-Length: ' . filesize($chemin));
        header('Cache-Control: private, max-age=31536000, immutable');
        readfile($chemin);
        exit;
    }
    if ($action === 'fichier' && $methode === 'PUT') {
        $table->poserFichier($h, (string)file_get_contents('php://input'));
        v2_ok(['ok' => true]);
    }
    if ($action === 'changements' && $methode === 'GET') {
        v2_ok($table->changements($maison, max(0, (int)($_GET['depuis'] ?? 0))));
    }
    if ($action === 'maisons' && $methode === 'GET') {
        v2_ok($table->maisons());
    }
    if ($methode !== 'POST') {
        v2_fail('methode', 'Méthode refusée.', 405);
    }
    $corps = v2_body();
    switch ($action) {
        case 'deposer':
            v2_ok(['manquants' => $table->deposer($maison, (array)($corps['recettes'] ?? []))]);
        case 'retirer':
            v2_ok(['retirees' => $table->retirer($maison, !empty($corps['tout']) ? null : (array)($corps['uids'] ?? []))]);
        default:
            v2_fail('action_inconnue', 'Action inconnue.', 400);
    }
} catch (DomainException $e) {
    v2_fail('refus', $e->getMessage(), 400);
} catch (Throwable $e) {
    error_log('table.php : ' . $e->getMessage());
    v2_fail('erreur', 'La table commune a eu un problème.', 500);
}
