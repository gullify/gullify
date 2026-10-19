<?php
/**
 * La gestion des comptes par « Ma maison » (GulliOS) — contrat de gestion v1.
 *
 *   docker compose -p gullify-serveur exec -T app php /app/scripts/maison-gestion.php <action> [arguments]
 *
 * Actions : resume, personnes, appareils, deconnecter <appareil_id>,
 * reinitialiser <personne_id>, admin <personne_id> oui|non,
 * debloquer <personne_id>, creer <nom> [courriel].
 *
 * Toujours UN objet JSON sur stdout ; code 0 en cas de succès, 1 et
 * {"erreur": "…"} sinon. Jamais de hash, de jeton ni de mot de passe dans la
 * sortie — sauf le NOUVEAU mot de passe que rendent « reinitialiser » et
 * « creer », une seule fois.
 *
 * Ce que GulliFY n'a pas :
 *   - pas de courriel dans les comptes (on se connecte par nom d'utilisateur) :
 *     « courriel » vaut null, et celui passé à « creer » est ignoré ;
 *   - pas de verrou après des essais ratés : « bloque_jusqua » vaut null et
 *     « debloquer » répond une erreur ;
 *   - pas d'inscription publique des comptes : « inscription » vaut false.
 *
 * Un « appareil », c'est une ligne de la table sessions (cookie du navigateur
 * ou jeton Bearer de l'app). Son identifiant EST le jeton : on ne le montre
 * donc jamais, on en montre une empreinte (16 premiers caractères du SHA-256).
 */

if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}

// Les avertissements PHP vont sur stderr : stdout ne porte que le JSON.
ini_set('display_errors', 'stderr');
ini_set('log_errors', '0');

require_once __DIR__ . '/../src/AppConfig.php';
require_once __DIR__ . '/../src/Auth.php';
require_once __DIR__ . '/../src/MusicPaths.php';

/** Une session sans activité depuis plus longtemps est morte (cookie de 30 jours, voir auth_required.php). */
const MG_SESSION_MAX = 2592000;

class ErreurGestion extends RuntimeException {}

function mg_sortir(array $donnees, int $code = 0): never
{
    echo json_encode($donnees, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES), "\n";
    exit($code);
}

function mg_date($epoch): ?string
{
    return ($epoch === null || $epoch === '') ? null : gmdate('Y-m-d\TH:i:s\Z', (int)$epoch);
}

function mg_empreinte(string $sessionId): string
{
    return substr(hash('sha256', $sessionId), 0, 16);
}

/** Un nom lisible pour l'appareil, tiré de son User-Agent. */
function mg_nom_appareil(?string $ua): string
{
    $ua = trim((string)$ua);
    if ($ua === '') return 'Appareil inconnu';
    if (stripos($ua, 'Dart/') !== false) return 'App GulliFY';
    if (stripos($ua, 'okhttp') !== false) return 'App Android';
    if ($ua === 'API v2 Client' || $ua === 'API Client') return 'Client API';

    $systemes = ['Android' => 'Android', 'iPhone' => 'iPhone', 'iPad' => 'iPad', 'CrOS' => 'ChromeOS',
                 'Windows' => 'Windows', 'Macintosh' => 'Mac', 'Linux' => 'Linux'];
    $navigateurs = ['Firefox/' => 'Firefox', 'Edg/' => 'Edge', 'OPR/' => 'Opera', 'Chrome/' => 'Chrome', 'Safari/' => 'Safari'];
    $os = null;
    foreach ($systemes as $cle => $nom) {
        if (stripos($ua, $cle) !== false) { $os = $nom; break; }
    }
    $nav = null;
    foreach ($navigateurs as $cle => $nom) {
        if (stripos($ua, $cle) !== false) { $nav = $nom; break; }
    }
    if ($nav && $os) return "$nav sur $os";
    if ($nav || $os) return $nav ?? $os;
    return mb_substr($ua, 0, 60);
}

function mg_id(array $args, int $i, string $quoi = 'personne_id'): string
{
    $v = trim((string)($args[$i] ?? ''));
    if ($v === '') throw new ErreurGestion("Il manque l'argument $quoi.");
    return $v;
}

function mg_personne(PDO $db, string $id): array
{
    if (!ctype_digit($id)) throw new ErreurGestion('Cette personne est introuvable.');
    $st = $db->prepare('SELECT id, username, full_name, is_admin, is_active FROM users WHERE id = ?');
    $st->execute([(int)$id]);
    $u = $st->fetch(PDO::FETCH_ASSOC);
    if (!$u) throw new ErreurGestion('Cette personne est introuvable.');
    return $u;
}

/** 16 caractères lisibles (ni 0/O, ni 1/l/I). */
function mg_mot_de_passe(): string
{
    $alphabet = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    $s = '';
    for ($i = 0; $i < 16; $i++) $s .= $alphabet[random_int(0, strlen($alphabet) - 1)];
    return $s;
}

/** Un nom d'utilisateur valide (lettres, chiffres, _ - .) et libre, tiré du nom. */
function mg_nom_utilisateur(PDO $db, string $nom): string
{
    $base = $nom;
    if (!preg_match('/^[a-zA-Z0-9_\-\.]+$/', $base)) {
        $t = @iconv('UTF-8', 'ASCII//TRANSLIT', $nom);
        $base = strtolower($t !== false ? $t : $nom);
        $base = preg_replace('/[^a-z0-9_\-\.]+/', '.', $base);
        $base = trim(preg_replace('/\.{2,}/', '.', $base), '.-_');
    }
    $base = substr($base, 0, 45);
    if ($base === '') $base = 'compte';

    $st = $db->prepare('SELECT 1 FROM users WHERE username = ?');
    $candidat = $base;
    for ($n = 2; ; $n++) {
        $st->execute([$candidat]);
        if ($st->fetchColumn() === false) return $candidat;
        $candidat = $base . $n;
    }
}

function mg_revoquer_tout(PDO $db, int $userId): void
{
    $db->prepare('DELETE FROM sessions WHERE user_id = ?')->execute([$userId]);
    // Le mot de passe Subsonic gardé en clair (public/rest) est l'ANCIEN mot
    // de passe : le laisser, c'est laisser entrer les clients Subsonic déjà
    // configurés.
    try {
        $db->prepare('UPDATE users SET subsonic_password = NULL WHERE id = ?')->execute([$userId]);
    } catch (PDOException $e) {
        // colonne absente : aucun client Subsonic ne s'est jamais connecté
    }
}

function mg_executer(array $args): array
{
    $action = $args[0] ?? '';
    $connues = ['resume', 'personnes', 'appareils', 'deconnecter', 'reinitialiser', 'admin', 'debloquer', 'creer'];
    if (!in_array($action, $connues, true)) {
        throw new ErreurGestion($action === '' ? 'Aucune action demandée.' : "Action inconnue : $action.");
    }

    // Avant la base : débloquer ne la touche pas.
    if ($action === 'debloquer') {
        throw new ErreurGestion("GulliFY ne bloque pas les comptes après des essais ratés : il n'y a rien à débloquer.");
    }

    try {
        $db = AppConfig::getDB();
    } catch (Throwable $e) {
        fwrite(STDERR, 'Connexion à la base : ' . $e->getMessage() . "\n");
        throw new ErreurGestion('La base de données de GulliFY est injoignable.');
    }
    $actives = 'last_activity >= NOW() - INTERVAL ' . MG_SESSION_MAX . ' SECOND';

    switch ($action) {
        case 'resume':
            $version = @file_get_contents(__DIR__ . '/../VERSION');
            return [
                'version'     => $version === false ? null : trim($version),
                'personnes'   => (int)$db->query('SELECT COUNT(*) FROM users')->fetchColumn(),
                'appareils'   => (int)$db->query("SELECT COUNT(*) FROM sessions WHERE $actives")->fetchColumn(),
                'inscription' => false,
            ];

        case 'personnes':
            $rows = $db->query(
                'SELECT id, username, full_name, is_admin, is_active, UNIX_TIMESTAMP(created_at) AS cree
                 FROM users ORDER BY id'
            )->fetchAll(PDO::FETCH_ASSOC);
            return ['personnes' => array_map(fn($u) => [
                'id'            => (string)$u['id'],
                'nom'           => trim((string)$u['full_name']) !== '' ? $u['full_name'] : $u['username'],
                'identifiant'   => $u['username'],
                'courriel'      => null,
                'admin'         => (bool)$u['is_admin'],
                'actif'         => (bool)$u['is_active'],
                'bloque_jusqua' => null,
                'cree'          => mg_date($u['cree']),
            ], $rows)];

        case 'appareils':
            $rows = $db->query(
                "SELECT s.id AS sid, s.user_id, s.user_agent,
                        UNIX_TIMESTAMP(s.last_activity) AS vu, UNIX_TIMESTAMP(s.created_at) AS cree,
                        u.username, u.full_name
                 FROM sessions s JOIN users u ON u.id = s.user_id
                 WHERE s.$actives
                 ORDER BY s.last_activity DESC"
            )->fetchAll(PDO::FETCH_ASSOC);
            return ['appareils' => array_map(fn($s) => [
                'id'          => mg_empreinte($s['sid']),
                'personne_id' => (string)$s['user_id'],
                'personne'    => trim((string)$s['full_name']) !== '' ? $s['full_name'] : $s['username'],
                'nom'         => mg_nom_appareil($s['user_agent']),
                'vu'          => mg_date($s['vu']),
                'cree'        => mg_date($s['cree']),
            ], $rows)];

        case 'deconnecter':
            $id = strtolower(mg_id($args, 1, 'appareil_id'));
            if (!preg_match('/^[0-9a-f]{16}$/', $id)) throw new ErreurGestion('Cet appareil est introuvable.');
            $trouve = 0;
            $del = $db->prepare('DELETE FROM sessions WHERE id = ?');
            foreach ($db->query('SELECT id FROM sessions')->fetchAll(PDO::FETCH_COLUMN) as $sid) {
                if (hash_equals(mg_empreinte($sid), $id)) {
                    $del->execute([$sid]);
                    $trouve++;
                }
            }
            if ($trouve === 0) throw new ErreurGestion('Cet appareil est introuvable (déjà déconnecté ?).');
            return ['ok' => true];

        case 'reinitialiser':
            $u = mg_personne($db, mg_id($args, 1));
            $secret = mg_mot_de_passe();
            $db->beginTransaction();
            (new Auth())->updatePassword((int)$u['id'], $secret);
            mg_revoquer_tout($db, (int)$u['id']);
            $db->commit();
            return ['ok' => true, 'secret' => $secret, 'type' => 'mot_de_passe'];

        case 'admin':
            $u = mg_personne($db, mg_id($args, 1));
            $choix = strtolower(trim((string)($args[2] ?? '')));
            if (!in_array($choix, ['oui', 'non'], true)) {
                throw new ErreurGestion('Le second argument doit être « oui » ou « non ».');
            }
            if ($choix === 'non' && $u['is_admin']) {
                $st = $db->prepare('SELECT COUNT(*) FROM users WHERE is_admin = 1 AND is_active = 1 AND id <> ?');
                $st->execute([(int)$u['id']]);
                if ((int)$st->fetchColumn() === 0) {
                    throw new ErreurGestion("C'est le dernier administrateur de GulliFY : nomme quelqu'un d'autre avant de lui retirer ce rôle.");
                }
            }
            $db->prepare('UPDATE users SET is_admin = ? WHERE id = ?')->execute([$choix === 'oui' ? 1 : 0, (int)$u['id']]);
            return ['ok' => true];

        case 'creer':
            $nom = trim((string)($args[1] ?? ''));
            if ($nom === '') throw new ErreurGestion('Il manque le nom de la personne.');
            if (mb_strlen($nom) > 100) throw new ErreurGestion('Ce nom est trop long (100 caractères au plus).');
            $identifiant = mg_nom_utilisateur($db, $nom);
            $secret = mg_mot_de_passe();
            // Un compte de la maison lit tout le dossier de musique.
            (new Auth())->createUser($identifiant, $secret, $nom, false, GULLIFY_RACINE);
            $id = $db->lastInsertId();
            return ['ok' => true, 'id' => (string)$id, 'identifiant' => $identifiant,
                    'secret' => $secret, 'type' => 'mot_de_passe'];
    }
    throw new ErreurGestion("Action inconnue : $action.");
}

try {
    mg_sortir(mg_executer(array_slice($argv, 1)));
} catch (ErreurGestion $e) {
    mg_sortir(['erreur' => $e->getMessage()], 1);
} catch (Throwable $e) {
    fwrite(STDERR, get_class($e) . ' : ' . $e->getMessage() . "\n");
    mg_sortir(['erreur' => "GulliFY n'a pas pu faire cette opération."], 1);
}
