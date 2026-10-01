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

const MAJ_DEPOT = 'registry.gullify.app/gullify';
/** Au-delà, le service d'à côté est considéré comme absent ou mort. */
const MAJ_SIGNE_DE_VIE = 120;
/** Le dépôt d'images est interrogé au plus une fois par heure. */
const MAJ_CACHE = 3600;

$session = v2_auth();
$dossier = AppConfig::getDataPath() . '/maj';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (empty($session['user']['is_admin'])) {
        v2_fail('forbidden', "Seul un administrateur peut agir sur le serveur.", 403);
    }
    if (!majServicePresent($dossier)) {
        v2_fail('maj_impossible',
            "Personne n'écoute sur la machine : le compagnon GulliFY n'y tourne pas.", 409);
    }

    // Deux gestes, un seul mécanisme. « redemarrer » relève le serveur sans
    // rien changer — ce qu'on demande quand quelque chose s'est coincé ;
    // « maj » va chercher la version suivante.
    $corps  = json_decode((string)file_get_contents('php://input'), true);
    $action = (is_array($corps) && ($corps['action'] ?? '') === 'redemarrer') ? 'redemarrer' : 'maj';

    if (!is_dir($dossier)) @mkdir($dossier, 0775, true);
    if (@file_put_contents($dossier . '/demande', $action) === false) {
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
    'possible'   => majServicePresent($dossier),
    'enCours'    => is_file($dossier . '/demande') || majTravaille($dossier),
    'journal'    => majJournal($dossier),
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

/** La plus haute version publiée au dépôt d'images, ou null s'il ne répond
 *  pas. Le dépôt est public en lecture : pas de secret à porter ici. */
function majVersionPubliee(): ?string {
    $cache = AppConfig::getDataPath() . '/cache/maj-versions.json';
    if (is_file($cache) && time() - (int)@filemtime($cache) < MAJ_CACHE) {
        $v = trim((string)@file_get_contents($cache));
        return $v !== '' ? $v : null;
    }

    $url = 'https://' . substr(MAJ_DEPOT, 0, strpos(MAJ_DEPOT, '/'))
         . '/v2/' . substr(MAJ_DEPOT, strpos(MAJ_DEPOT, '/') + 1) . '/tags/list';
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 8,
        CURLOPT_USERAGENT      => 'Gullify/serveur',
    ]);
    $corps = curl_exec($ch);
    $code  = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    if ($code !== 200 || !is_string($corps)) return null;

    $tags = json_decode($corps, true)['tags'] ?? null;
    if (!is_array($tags)) return null;

    $meilleure = null;
    foreach ($tags as $tag) {
        if (!is_string($tag) || !preg_match('/^\d+\.\d+\.\d+$/', $tag)) continue; // « latest » n'est pas une version
        if ($meilleure === null || version_compare($tag, $meilleure, '>')) $meilleure = $tag;
    }
    if ($meilleure !== null) {
        if (!is_dir(dirname($cache))) @mkdir(dirname($cache), 0775, true);
        @file_put_contents($cache, $meilleure);
    }
    return $meilleure;
}

/** Le service d'à côté donne signe de vie en touchant un fichier. Un fichier
 *  qui date prouve qu'il a existé, pas qu'il tourne : on exige du frais. */
function majServicePresent(string $dossier): bool {
    $vie = $dossier . '/present';
    return is_file($vie) && (time() - (int)@filemtime($vie)) < MAJ_SIGNE_DE_VIE;
}

/** Une mise à jour est en cours tant que le journal n'a pas dit « fini ». */
function majTravaille(string $dossier): bool {
    $lignes = majJournal($dossier);
    if (!$lignes) return false;
    return !str_starts_with(end($lignes), 'fini');
}

/** @return string[] */
function majJournal(string $dossier): array {
    $fichier = $dossier . '/journal';
    if (!is_file($fichier)) return [];
    $lignes = preg_split('/\R/', trim((string)@file_get_contents($fichier))) ?: [];
    $lignes = array_values(array_filter($lignes, static fn($l) => trim($l) !== ''));
    return array_slice($lignes, -40); // l'app n'en affiche qu'une poignée
}
