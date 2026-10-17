<?php
/**
 * Gullify API v2 — Le dossier de musique du serveur
 *   GET  /api/v2/musique-racine.php?chemin=/media   → ce qu'il y a là (admin)
 *   POST /api/v2/musique-racine.php {chemin, a_la_racine?: [id…]}
 *                                                    → c'est désormais la racine
 *
 * Chaque compte lit un dossier SOUS cette racine (users.music_directory) :
 * « Maxime » donne /media/musique/Maxime. La liste des comptes accompagne donc
 * chaque dossier parcouru, pour que l'app dise ce que chacun lira — et
 * a_la_racine remet à « . » (tout le dossier) ceux dont le sous-dossier
 * n'existe pas dans la nouvelle racine.
 *
 * Choisir où est sa musique, c'est choisir ce que Docker monte — pas un
 * réglage du serveur, mais le dessous de ses pieds. Le conteneur ne voit rien
 * d'autre que ce qu'on lui a déjà monté : c'est donc le compagnon, sur la
 * machine, qui regarde pour lui et qui remonte la pile ensuite.
 *
 * Sans compagnon, il n'y a rien à proposer : l'app le dit et renvoie au .env.
 */
declare(strict_types=1);

require_once __DIR__ . '/_v2.php';
require_once dirname(__DIR__, 3) . '/src/Compagnon.php';
require_once dirname(__DIR__, 3) . '/src/MusicPaths.php';

$session = v2_auth();
if (empty($session['user']['is_admin'])) {
    v2_fail('forbidden', "Seul un administrateur peut voir les dossiers du serveur.", 403);
}

if (!Compagnon::present()) {
    v2_fail('compagnon_absent',
        "Personne n'écoute sur la machine : le compagnon GulliFY n'y tourne pas. "
        . "Sans lui, la racine se change dans le .env (MUSIC_HOST_PATH), "
        . "puis en remontant la pile.", 409);
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $corps  = json_decode((string)file_get_contents('php://input'), true);
    $chemin = trim((string)(is_array($corps) ? ($corps['chemin'] ?? '') : ''));

    // Un chemin de la machine, absolu : c'est tout ce qu'on peut vérifier
    // d'ici. Le reste — il existe, il est lisible — relève du compagnon, qui
    // est le seul à pouvoir regarder.
    if ($chemin === '' || $chemin[0] !== '/' || str_contains($chemin, "\n")) {
        v2_fail('chemin_invalide',
            "Donne le chemin complet du dossier sur la machine, par exemple "
            . "/media/musique.", 400);
    }

    // Les comptes d'abord : une fois la demande déposée, le serveur peut
    // tomber d'une seconde à l'autre.
    $aLaRacine = is_array($corps['a_la_racine'] ?? null) ? $corps['a_la_racine'] : [];
    $ids = array_values(array_unique(array_filter(
        array_map('intval', $aLaRacine), static fn(int $id): bool => $id > 0)));
    if ($ids) {
        $place = implode(',', array_fill(0, count($ids), '?'));
        AppConfig::getDB()->prepare(
            "UPDATE users SET music_directory = ? WHERE id IN ($place)
               AND COALESCE(storage_type, 'local') = 'local'"
        )->execute([GULLIFY_RACINE, ...$ids]);
    }

    if (!Compagnon::demande('racine ' . $chemin)) {
        v2_fail('compagnon_muet', "Je n'ai pas pu déposer la demande sur le disque.", 500);
    }
    // Le serveur va tomber et revenir : la réponse part maintenant, et l'app
    // suivra le journal comme elle le fait pour une mise à jour.
    v2_ok(['demande' => 'racine', 'chemin' => $chemin, 'a_la_racine' => $ids]);
}

$chemin = trim((string)($_GET['chemin'] ?? ''));
if ($chemin !== '' && $chemin !== 'depart' && $chemin[0] !== '/') {
    v2_fail('chemin_invalide', "Chemin attendu en absolu.", 400);
}
if (str_contains($chemin, "\n")) {
    v2_fail('chemin_invalide', "Chemin impossible.", 400);
}

$vu = Compagnon::interroge('lister ' . ($chemin === '' ? 'depart' : $chemin));
if ($vu === null) {
    v2_fail('compagnon_muet',
        "Le compagnon n'a pas répondu. Il tourne peut-être, mais plus pour longtemps.", 504);
}

v2_ok([
    'chemin'   => $vu['chemin']   ?? $chemin,
    'parent'   => $vu['parent']   ?? null,
    'depart'   => $vu['depart']   ?? false,
    'erreur'   => $vu['erreur']   ?? null,
    'musique'  => (int)($vu['musique'] ?? 0),
    'dossiers' => array_map(static fn(array $d): array => [
        'nom'     => (string)($d['nom'] ?? ''),
        'chemin'  => (string)($d['chemin'] ?? ''),
        'musique' => (int)($d['musique'] ?? 0),
    ], is_array($vu['dossiers'] ?? null) ? $vu['dossiers'] : []),
    // Là où le serveur lit en ce moment, pour qu'on sache ce qu'on remplace.
    'actuelle' => AppConfig::getMusicHostPath(),
    'comptes'  => comptes_locaux(),
]);

/**
 * Les comptes qui lisent sous la racine (pas ceux en SFTP, qui lisent
 * ailleurs), avec leur sous-dossier : « . » pour tout le dossier, null pour
 * aucun.
 *
 * @return list<array{id:int, nom:string, dossier:?string}>
 */
function comptes_locaux(): array
{
    $lignes = AppConfig::getDB()->query(
        "SELECT id, username, full_name, music_directory FROM users
          WHERE is_active = 1 AND COALESCE(storage_type, 'local') = 'local'
          ORDER BY username"
    )->fetchAll(PDO::FETCH_ASSOC);
    return array_map(static fn(array $u): array => [
        'id'      => (int)$u['id'],
        'nom'     => trim((string)($u['full_name'] ?? '')) !== '' ? (string)$u['full_name'] : (string)$u['username'],
        'dossier' => trim((string)($u['music_directory'] ?? '')) !== '' ? (string)$u['music_directory'] : null,
    ], $lignes);
}
