<?php
/**
 * Le registre des maisons GulliOS (voir src/RegistreMaisons.php). Toutes les demandes sont des
 * messages signés par une maison : POST {"message": "<json>", "signature": "<base64>"}.
 *
 *   POST ?action=inscrire       message {nom, quand, cle, version, canal, aide}
 *   POST ?action=signe          message {nom, quand, version, canal, aide}      → {dev, designee}
 *   POST ?action=devenir-dev    message {nom, quand, code}                      → {dev, designee}
 *   POST ?action=jeton-table    message {nom, quand, app}                       → {jeton}  (table commune)
 *   POST ?action=mesures        message {nom, quand, echantillons: [{t, v, smart?, sauvegarde?}]} → {recus}
 *   POST ?action=amies          message {nom, quand}                            → [amies] (+ billets, AmiesMaisons)
 *   POST ?action=amie           message {nom, quand, cible, geste: inviter|accepter|retirer} → [amies]
 *   POST ?action=postes         message {nom, quand}                            → [postes] (PostesMaisons, 1.57)
 *   POST ?action=poste          message {nom, quand, cible, geste: accepter|retirer|dev-oui|dev-non} → [postes]
 *   POST ?action=historique-poste message {nom, quand, cible, periode}          → l'historique d'un de ses postes
 * Signées par un POSTE (sa propre clé, voir PostesMaisons) :
 *   POST ?action=poste-signe    message {maison, poste, quand, cle, version, canal} → {etat, dev}
 *   POST ?action=poste-mesures  message {maison, poste, quand, cle, echantillons}   → {recus}
 *   Réservé aux maisons Dev :
 *   POST ?action=maisons        message {nom, quand}                            → [maisons]
 *   POST ?action=designer       message {nom, quand, cible}                     → {code, jours}
 *   POST ?action=annuler        message {nom, quand, cible}
 *   POST ?action=billet         message {nom, quand, cible, personne}           → {billet, adresse}
 *   POST ?action=historique     message {nom, quand, cible, periode}            → l'historique (MesuresMaisons)
 *
 * 404 partout où le registre n'est pas configuré (les serveurs installés chez les gens).
 */
require_once __DIR__ . '/_v2.php';
require_once __DIR__ . '/../../../src/RegistreMaisons.php';
require_once __DIR__ . '/../../../src/TableRecettes.php';
require_once __DIR__ . '/../../../src/MesuresMaisons.php';
require_once __DIR__ . '/../../../src/AmiesMaisons.php';
require_once __DIR__ . '/../../../src/PostesMaisons.php';

if (!RegistreMaisons::actif()) {
    v2_fail('registre_absent', 'Ce serveur ne tient pas le registre des maisons.', 404);
}
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    v2_fail('methode', 'POST seulement.', 405);
}

$action = $_GET['action'] ?? '';
try {
    $registre = new RegistreMaisons();
    // Les postes (1.57) signent avec leur propre clé : ils ne passent pas par ouvrir() des maisons.
    if ($action === 'poste-signe' || $action === 'poste-mesures') {
        $postes = new PostesMaisons();
        [$m, $ligne] = $postes->ouvrir(v2_body());
        v2_ok($action === 'poste-signe' ? $postes->signe($m, $ligne) : ['recus' => $postes->mesures($m, $ligne)]);
    }
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
        case 'mesures':
            if (!$maison || !is_array($m['echantillons'] ?? null)) {
                v2_fail('mesures', 'Échantillons manquants.', 400);
            }
            v2_ok(['recus' => (new MesuresMaisons())->recevoir($m['nom'], $m['echantillons'])]);
        case 'amies':
            if (!$maison) {
                v2_fail('inconnue', 'Maison inconnue.', 403);
            }
            v2_ok((new AmiesMaisons())->liste($m['nom']));
        case 'amie':
            if (!$maison) {
                v2_fail('inconnue', 'Maison inconnue.', 403);
            }
            v2_ok((new AmiesMaisons())->geste($m['nom'], (string)($m['geste'] ?? ''), $cible));
        case 'postes':
        case 'poste':
        case 'historique-poste':
            if (!$maison) {
                v2_fail('inconnue', 'Maison inconnue.', 403);
            }
            $postes = new PostesMaisons();
            if ($action === 'postes') {
                v2_ok($postes->liste($m['nom']));
            }
            if (!preg_match('/^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/', $cible)) {
                v2_fail('cible', 'Poste invalide.', 400);
            }
            v2_ok($action === 'poste'
                ? $postes->geste($m['nom'], (bool)(int)$maison['dev'], (string)($m['geste'] ?? ''), $cible)
                : $postes->historique($m['nom'], $cible, (string)($m['periode'] ?? '24h')));
        case 'historique':
            $dev();
            if (!preg_match('/^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/', $cible)) {
                v2_fail('cible', 'Maison invalide.', 400);
            }
            v2_ok((new MesuresMaisons())->historique($cible, (string)($m['periode'] ?? '24h')));
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
