<?php
/**
 * Le registre des maisons GulliOS (voir src/RegistreMaisons.php). Toutes les demandes sont des
 * messages signés par une maison : POST {"message": "<json>", "signature": "<base64>"}.
 *
 *   POST ?action=inscrire       message {nom, quand, cle, version, canal, aide}
 *   POST ?action=signe          message {nom, quand, version, canal, aide}      → {dev, designee}
 *   POST ?action=devenir-dev    message {nom, quand, code}                      → {dev, designee}
 *   POST ?action=jeton-table    message {nom, quand, app}                       → {jeton}  (table commune)
 *   Réservé aux maisons Dev :
 *   POST ?action=maisons        message {nom, quand}                            → [maisons]
 *   POST ?action=designer       message {nom, quand, cible}                     → {code, jours}
 *   POST ?action=annuler        message {nom, quand, cible}
 *   POST ?action=billet         message {nom, quand, cible, personne}           → {billet, adresse}
 *
 * 404 partout où le registre n'est pas configuré (les serveurs installés chez les gens).
 */
require_once __DIR__ . '/_v2.php';
require_once __DIR__ . '/../../../src/RegistreMaisons.php';
require_once __DIR__ . '/../../../src/TableRecettes.php';

if (!RegistreMaisons::actif()) {
    v2_fail('registre_absent', 'Ce serveur ne tient pas le registre des maisons.', 404);
}
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    v2_fail('methode', 'POST seulement.', 405);
}

$action = $_GET['action'] ?? '';
try {
    $registre = new RegistreMaisons();
    [$m, $maison] = $registre->ouvrir(v2_body(), $action === 'inscrire');
    $dev = function () use ($maison) {
        if (!$maison || !(int)$maison['dev']) {
            v2_fail('pas_dev', 'Réservé aux maisons Dev.', 403);
        }
    };
    $cible = strtolower((string)($m['cible'] ?? ''));

    switch ($action) {
        case 'inscrire':
            v2_ok($registre->inscrire($m));
        case 'signe':
            v2_ok($registre->signeDeVie($m));
        case 'devenir-dev':
            v2_ok($registre->devenirDev($m, $maison));
        case 'jeton-table':
            if (($m['app'] ?? '') !== 'gullieats') {
                v2_fail('app', 'App inconnue pour la table commune.', 400);
            }
            v2_ok(['jeton' => (new TableRecettes())->nouveauJeton($m['nom'], 'gullieats')]);
        case 'maisons':
            $dev();
            v2_ok($registre->liste());
        case 'designer':
            $dev();
            v2_ok($registre->designer($cible));
        case 'annuler':
            $dev();
            $registre->annuler($cible);
            v2_ok(['ok' => true]);
        case 'billet':
            $dev();
            v2_ok($registre->billet($m, $cible));
        default:
            v2_fail('action_inconnue', 'Action inconnue.', 400);
    }
} catch (DomainException $e) {
    v2_fail('refus', $e->getMessage(), 400);
} catch (Throwable $e) {
    error_log('gullios.php : ' . $e->getMessage());
    v2_fail('erreur', 'Le registre a eu un problème.', 500);
}
