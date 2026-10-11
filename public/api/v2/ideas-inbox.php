<?php
/**
 * Gullify API v2 — La boîte du développeur.
 *
 *   POST (sans session)        → déposer une idée venue d'un autre serveur
 *   GET  ?action=list          → ce qu'on a reçu              (propriétaire)
 *   POST ?action=adopter       → la verser dans son carnet    (propriétaire)
 *   POST ?action=rejeter       → l'écarter                    (propriétaire)
 *
 * N'importe qui peut écrire ici — c'est tout l'objet : une idée écrite sur le
 * GulliFY de quelqu'un arrive chez le développeur. Mais une seule personne
 * peut LIRE : celle que `IDEAS_INBOX_OWNER` désigne sur ce serveur-ci. Sans
 * ce réglage, ce serveur n'est pas une boîte et refuse tout.
 *
 * Ce qui arrive ici ne part nulle part ensuite : c'est le propriétaire qui
 * décide, idée par idée, ce qu'il verse dans son carnet — et c'est son carnet
 * seul que Claude lit.
 */
declare(strict_types=1);

require_once __DIR__ . '/_v2.php';

/** Au-delà, une adresse a trop écrit dans l'heure. */
const INBOX_PAR_HEURE = 20;
const INBOX_TEXTE_MAX = 2000;

$proprietaire = trim((string)AppConfig::get('ideas.inbox_owner', ''));
if ($proprietaire === '') {
    v2_fail('pas_une_boite', "Ce serveur ne reçoit pas les idées des autres.", 404);
}

$db = AppConfig::getDB();
inboxCreerTable($db);

$action = (string)($_GET['action'] ?? ($_SERVER['REQUEST_METHOD'] === 'POST' ? 'deposer' : 'list'));

// ── Déposer : ouvert, car c'est le but ───────────────────────────────────────

if ($action === 'deposer') {
    $corps = json_decode((string)file_get_contents('php://input'), true);
    if (!is_array($corps)) v2_fail('corps_illisible', "Je n'ai pas compris la demande.", 400);

    $texte = trim((string)($corps['texte'] ?? ''));
    if ($texte === '') v2_fail('texte_vide', "Une idée sans texte n'en est pas une.", 400);

    $empreinte = inboxEmpreinte();
    if (inboxTropEcrit($db, $empreinte)) {
        v2_fail('trop_d_idees', "Trop d'idées envoyées dans l'heure. Réessaie plus tard.", 429);
    }

    $stmt = $db->prepare("
        INSERT INTO dev_ideas_inbox (serveur, utilisateur, texte, ip_empreinte)
        VALUES (?, ?, ?, ?)
    ");
    $stmt->execute([
        mb_substr(trim((string)($corps['serveur'] ?? '')), 0, 190),
        mb_substr(trim((string)($corps['utilisateur'] ?? '')), 0, 190),
        mb_substr($texte, 0, INBOX_TEXTE_MAX),
        $empreinte,
    ]);
    v2_ok(['recue' => true]);
}

// ── Tout le reste : le propriétaire, et personne d'autre ─────────────────────

$session = v2_auth();
$moi = (string)($session['user']['username'] ?? '');
if ($moi !== $proprietaire) {
    v2_fail('forbidden', "Cette boîte n'est pas la vôtre.", 403);
}

switch ($action) {
    case 'list':
        $rows = $db->query("
            SELECT id, serveur, utilisateur, texte, etat, created_at
            FROM dev_ideas_inbox
            WHERE etat = 'nouvelle'
            ORDER BY created_at DESC
            LIMIT 200
        ")->fetchAll(PDO::FETCH_ASSOC);
        v2_ok(['idees' => array_map(static fn($r) => [
            'id'          => (int)$r['id'],
            'serveur'     => $r['serveur'],
            'utilisateur' => $r['utilisateur'],
            'texte'       => $r['texte'],
            'recueLe'     => $r['created_at'],
        ], $rows)]);

    case 'adopter':
        $id = (int)(json_decode((string)file_get_contents('php://input'), true)['id'] ?? 0);
        $stmt = $db->prepare("SELECT * FROM dev_ideas_inbox WHERE id = ? AND etat = 'nouvelle'");
        $stmt->execute([$id]);
        $idee = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$idee) v2_fail('introuvable', "Cette idée n'est plus là.", 404);

        // Versée dans le carnet du propriétaire, en disant d'où elle vient :
        // c'est ce carnet-là, et lui seul, que Claude lit.
        $provenance = trim(($idee['utilisateur'] ?: 'quelqu\'un') . ' · ' . ($idee['serveur'] ?: 'serveur inconnu'));
        $db->prepare("INSERT INTO dev_ideas (user, text) VALUES (?, ?)")
           ->execute([$moi, mb_substr("[$provenance] " . $idee['texte'], 0, INBOX_TEXTE_MAX)]);
        // Relevé AVANT l'UPDATE : après, lastInsertId ne désigne plus rien.
        $neuf = (int)$db->lastInsertId();

        $db->prepare("UPDATE dev_ideas_inbox SET etat = 'adoptee' WHERE id = ?")->execute([$id]);
        v2_ok(['adoptee' => $neuf]);

    case 'rejeter':
        $id = (int)(json_decode((string)file_get_contents('php://input'), true)['id'] ?? 0);
        $db->prepare("UPDATE dev_ideas_inbox SET etat = 'ecartee' WHERE id = ?")->execute([$id]);
        v2_ok(['ok' => true]);

    default:
        v2_fail('action_inconnue', "Action inconnue : $action", 400);
}

// ─────────────────────────────────────────────────────────────────────────────

function inboxCreerTable(PDO $db): void
{
    // Le carnet du propriétaire, aussi : « adopter » y verse les idées, et
    // sur un serveur qui n'a jamais ouvert la page des idées il n'existe pas
    // encore. Trouvé au banc d'essai — l'adoption plantait sans un mot.
    $db->exec("
        CREATE TABLE IF NOT EXISTS dev_ideas (
            id INT AUTO_INCREMENT PRIMARY KEY,
            user VARCHAR(255) NOT NULL,
            text TEXT NOT NULL,
            status VARCHAR(20) NOT NULL DEFAULT 'todo',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            INDEX (user)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ");
    $db->exec("
        CREATE TABLE IF NOT EXISTS dev_ideas_inbox (
            id INT AUTO_INCREMENT PRIMARY KEY,
            serveur VARCHAR(190) NOT NULL DEFAULT '',
            utilisateur VARCHAR(190) NOT NULL DEFAULT '',
            texte TEXT NOT NULL,
            etat VARCHAR(20) NOT NULL DEFAULT 'nouvelle',
            ip_empreinte CHAR(64) NOT NULL DEFAULT '',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            INDEX (etat),
            INDEX (ip_empreinte, created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ");
}

/**
 * De quoi compter ce qu'une même source a écrit, sans garder son adresse.
 *
 * L'empreinte est salée avec le secret du serveur : elle ne sert qu'ici, et
 * ne permet pas de remonter à quelqu'un.
 */
function inboxEmpreinte(): string
{
    $ip = (string)($_SERVER['HTTP_X_FORWARDED_FOR'] ?? $_SERVER['REMOTE_ADDR'] ?? '');
    if (str_contains($ip, ',')) $ip = trim(explode(',', $ip)[0]);
    return hash('sha256', $ip . '|' . (string)AppConfig::get('app.secret', 'gullify'));
}

function inboxTropEcrit(PDO $db, string $empreinte): bool
{
    $stmt = $db->prepare("
        SELECT COUNT(*) FROM dev_ideas_inbox
        WHERE ip_empreinte = ? AND created_at > (NOW() - INTERVAL 1 HOUR)
    ");
    $stmt->execute([$empreinte]);
    return (int)$stmt->fetchColumn() >= INBOX_PAR_HEURE;
}
