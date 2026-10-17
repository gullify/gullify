<?php
/**
 * Gullify API v2 — Mise à jour du serveur
 *   GET  /api/v2/update.php          → où en est ce serveur
 *   POST /api/v2/update.php {lancer} → demande la mise à jour (admin)
 *
 * Un serveur posé par l'installateur ne contient pas le code : il tire une
 * image déjà construite. Se mettre à jour, pour lui, c'est tirer la suivante
 * et se faire remplacer — ce qu'un conteneur ne peut pas faire de lui-même.
 * D'où le partage des rôles : ici, on écrit une DEMANDE dans un fichier ; à
 * côté, dans la pile, un petit service qui n'a que ce rôle la voit, tire
 * l'image et relance le serveur. La réponse HTTP part avant que le serveur
 * ne tombe, sinon l'app ne saurait jamais que sa demande a été reçue.
 *
 * Un serveur installé depuis le dépôt de code (le mien) n'a pas ce service :
 * il n'y a alors pas de bouton, et l'app renvoie à `./update.sh`.
 */
declare(strict_types=1);

require_once __DIR__ . '/_v2.php';
require_once dirname(__DIR__, 3) . '/src/Compagnon.php';

/**
 * Ce qui fait foi sur « la dernière version du serveur ».
 *
 * Pas la liste des étiquettes du dépôt d'images : elle garde pour toujours
 * celles d'avant, quand le serveur portait le numéro de l'app (3.71, 3.73…).
 * Un serveur en 1.0.0 s'y serait cru en retard de 3.73.3 à jamais. Un
 * manifeste dit une seule chose, celle qu'on veut savoir — comme celui de
 * l'APK, à côté duquel il est publié.
 */
const MAJ_MANIFESTE = 'https://download.gullify.app/serveur.json';
/** Le dépôt d'images est interrogé au plus une fois par heure. */
const MAJ_CACHE = 3600;
/** Un journal muet aussi longtemps n'est plus un travail en cours. */
const MAJ_ABANDON = 900;

$session = v2_auth();
$dossier = Compagnon::dossier();

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (empty($session['user']['is_admin'])) {
        v2_fail('forbidden', "Seul un administrateur peut agir sur le serveur.", 403);
    }
    if (!Compagnon::present()) {
        v2_fail('maj_impossible',
            "Personne n'écoute sur la machine : le compagnon GulliFY n'y tourne pas.", 409);
    }

    // Deux gestes, un seul mécanisme. « redemarrer » relève le serveur sans
    // rien changer — ce qu'on demande quand quelque chose s'est coincé ;
    // « maj » va chercher la version suivante.
    $corps  = json_decode((string)file_get_contents('php://input'), true);
    $action = (is_array($corps) && ($corps['action'] ?? '') === 'redemarrer') ? 'redemarrer' : 'maj';

    if (!Compagnon::demande($action)) {
        v2_fail('maj_impossible', "Je n'ai pas pu déposer la demande sur le disque.", 500);
    }
    v2_ok(['demande' => $action]);
}

$installee  = majVersionInstallee();
$disponible = majVersionPubliee();

v2_ok([
    'installee'  => $installee,
    'disponible' => $disponible,
    // Inconnu n'est pas « à jour » : sans réponse du dépôt, on ne promet rien.
    'aJour'      => ($disponible === null || $installee === null)
        ? null
        : version_compare($disponible, $installee, '<='),
    'possible'   => Compagnon::present(),
    'enCours'    => is_file($dossier . '/demande') || Compagnon::travaille(MAJ_ABANDON),
    'journal'    => Compagnon::journal(),
]);

// ─────────────────────────────────────────────────────────────────────────────

/** La version gravée dans l'image (voir Dockerfile). « dev » = construite à la
 *  main, donc sans version publiée à laquelle se comparer. */
function majVersionInstallee(): ?string {
    $fichier = dirname(__DIR__, 3) . '/VERSION';
    if (!is_file($fichier)) return null;
    $v = trim((string)@file_get_contents($fichier));
    return ($v === '' || $v === 'dev') ? null : $v;
}

/** La dernière version publiée du serveur, ou null si le manifeste ne
 *  répond pas. Il est public : pas de secret à porter ici. */
function majVersionPubliee(): ?string {
    $cache = AppConfig::getDataPath() . '/cache/maj-versions.json';
    if (is_file($cache) && time() - (int)@filemtime($cache) < MAJ_CACHE) {
        $v = trim((string)@file_get_contents($cache));
        return $v !== '' ? $v : null;
    }

    $ch = curl_init(MAJ_MANIFESTE);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 8,
        CURLOPT_USERAGENT      => 'Gullify/serveur',
    ]);
    $corps = curl_exec($ch);
    $code  = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    if ($code !== 200 || !is_string($corps)) return null;

    $version = json_decode($corps, true)['version'] ?? null;
    if (!is_string($version) || !preg_match('/^\d+\.\d+\.\d+$/', $version)) return null;

    if (!is_dir(dirname($cache))) @mkdir(dirname($cache), 0775, true);
    @file_put_contents($cache, $version);
    return $version;
}

