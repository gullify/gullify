<?php
/**
 * La gestion des comptes par « Ma maison » (GulliOS) — contrat de gestion v2.
 *
 *   docker compose -p gullify-serveur exec -T app php /app/scripts/maison-gestion.php <action> [arguments]
 *
 * Actions : resume, personnes, appareils, deconnecter <appareil_id>,
 * reinitialiser <personne_id>, admin <personne_id> oui|non,
 * debloquer <personne_id>, creer <nom> [courriel],
 * v2 : modifier <id> [nom=…] [courriel=…], desactiver <id>, activer <id>,
 * supprimer <id>, definir <id> (secret sur STDIN), photo <id> (image sur
 * STDIN) | photo <id> --retirer,
 * comptes de la maison : lier <id_local> <compte_id>, empreinte <id_local>.
 *
 * Avec les comptes de la maison (COMPTES_URL posé, CONTRAT-COMPTES.md), les
 * mots de passe vivent dans Comptes : reinitialiser, definir et creer
 * répondent une erreur claire ; les comptes naissent à leur première
 * connexion, ou sont reliés par « lier ». `personnes` rend `compte_id`.
 *
 * Les secrets que rendent reinitialiser et creer, et celui que pose definir,
 * sont TEMPORAIRES : la personne doit en choisir un autre à la connexion
 * (users.must_change_password, 403 « changement_requis » ailleurs).
 *
 * Supprimer : voir la politique dans CLAUDE.md (compte, sessions, listes de
 * lecture, favoris, historique et index de sa bibliothèque supprimés ; la
 * musique — les fichiers — n'est jamais touchée).
 *
 * Toujours UN objet JSON sur stdout ; code 0 en cas de succès, 1 et
 * {"erreur": "…"} sinon. Jamais de hash, de jeton ni de mot de passe dans la
 * sortie — sauf le NOUVEAU mot de passe que rendent « reinitialiser » et
 * « creer », une seule fois.
 *
 * Seule exception à la règle des hash (comptes de la maison v1.1) :
 * « empreinte <id> » rend password_hash TEL QUE STOCKÉ, pour que la personne
 * garde son mot de passe actuel. Ma maison le passe directement à Comptes
 * (« importer »), sans jamais l'afficher ni l'écrire.
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
require_once __DIR__ . '/../src/Avatar.php';

/** Taille maximale d'une photo reçue sur STDIN. */
const MG_PHOTO_MAX = 5 * 1024 * 1024;

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
    $st = $db->prepare('SELECT id, username, full_name, is_admin, is_active, must_change_password FROM users WHERE id = ?');
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
    return Comptes::nomUtilisateurLibre($db, $nom);
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

/** Refuse si $u est le dernier administrateur actif. */
function mg_pas_dernier_admin(PDO $db, array $u, string $message): void
{
    if (!$u['is_admin'] || !$u['is_active']) return;
    $st = $db->prepare('SELECT COUNT(*) FROM users WHERE is_admin = 1 AND is_active = 1 AND id <> ?');
    $st->execute([(int)$u['id']]);
    if ((int)$st->fetchColumn() === 0) throw new ErreurGestion($message);
}

/** Une ligne lue sur STDIN (le secret de « definir »), sans le saut de ligne. */
function mg_ligne_stdin(): string
{
    $l = fgets(STDIN);
    return $l === false ? '' : rtrim($l, "\r\n");
}

/** Le propriétaire du dossier de données : les fichiers écrits par root lui reviennent. */
function mg_rendre(string $chemin): void
{
    if (function_exists('posix_getuid') && posix_getuid() === 0) {
        $st = @stat(AppConfig::getDataPath());
        if ($st) {
            @chown($chemin, $st['uid']);
            @chgrp($chemin, $st['gid']);
        }
    }
}

/**
 * Les tables où une personne a des données à elle, par nom d'utilisateur.
 * Certaines naissent à la première utilisation : absentes, on les saute.
 * Les lignes d'albums, titres, statistiques de titres d'un index tombent en
 * cascade avec ses artistes — ce sont des lignes de base, pas des fichiers.
 */
const MG_DONNEES_PERSONNELLES = [
    'playlists' => 'user',          // + playlist_songs en cascade
    'favorites' => 'user',
    'favorite_artists' => 'user',
    'favorite_albums' => 'user',
    'play_history' => 'user',
    'notifications' => 'user',
    'custom_genres' => 'user',
    'radio_custom_stations' => 'user',
    'radio_user_state' => 'user',
    'radio_user_prefs' => 'user',
    'radio_folders' => 'user',
    'podcast_subscriptions' => 'user',
    'podcast_progress' => 'user',
    'song_shares' => 'owner_user',
    'library_stats' => 'user',
    'artists' => 'user',            // l'INDEX de sa bibliothèque (+ albums, songs en cascade)
];

function mg_executer(array $args): array
{
    $action = $args[0] ?? '';
    $connues = ['resume', 'personnes', 'appareils', 'deconnecter', 'reinitialiser', 'admin', 'debloquer', 'creer',
                'modifier', 'desactiver', 'activer', 'supprimer', 'definir', 'photo', 'lier', 'empreinte'];
    if (!in_array($action, $connues, true)) {
        throw new ErreurGestion($action === '' ? 'Aucune action demandée.' : "Action inconnue : $action.");
    }

    // Comptes de la maison : les mots de passe ne sont plus ceux de GulliFY.
    if (Comptes::actif() && in_array($action, ['reinitialiser', 'definir', 'creer'], true)) {
        throw new ErreurGestion(Comptes::MESSAGE_GERE);
    }
    if (!Comptes::actif() && $action === 'lier') {
        throw new ErreurGestion("Cette maison n'utilise pas encore les comptes de la maison (COMPTES_URL absent).");
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
                'contrat'     => 2,
                'version'     => $version === false ? null : trim($version),
                'personnes'   => (int)$db->query('SELECT COUNT(*) FROM users')->fetchColumn(),
                'appareils'   => (int)$db->query("SELECT COUNT(*) FROM sessions WHERE $actives")->fetchColumn(),
                'inscription' => false,
            ];

        case 'personnes':
            $rows = $db->query(
                'SELECT id, username, full_name, is_admin, is_active, must_change_password, compte_id, email,
                        UNIX_TIMESTAMP(created_at) AS cree, UNIX_TIMESTAMP(last_login) AS connexion
                 FROM users ORDER BY id'
            )->fetchAll(PDO::FETCH_ASSOC);
            return ['personnes' => array_map(fn($u) => [
                'id'            => (string)$u['id'],
                'nom'           => trim((string)$u['full_name']) !== '' ? $u['full_name'] : $u['username'],
                'identifiant'   => $u['username'],
                'courriel'      => $u['email'] ?? null,
                'compte_id'     => $u['compte_id'] === null ? null : (string)$u['compte_id'],
                'admin'         => (bool)$u['is_admin'],
                'actif'         => (bool)$u['is_active'],
                'bloque_jusqua' => null,
                'cree'          => mg_date($u['cree']),
                'doit_changer'  => (bool)$u['must_change_password'],
                'derniere_connexion' => mg_date($u['connexion']),
                'photo'         => Avatar::exists((int)$u['id']),
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
            $db->prepare('UPDATE users SET must_change_password = 1 WHERE id = ?')->execute([(int)$u['id']]);
            mg_revoquer_tout($db, (int)$u['id']);
            $db->commit();
            return ['ok' => true, 'secret' => $secret, 'type' => 'mot_de_passe'];

        case 'definir':
            $u = mg_personne($db, mg_id($args, 1));
            $secret = mg_ligne_stdin();
            if (mb_strlen($secret) < 8) {
                throw new ErreurGestion('Le mot de passe doit faire au moins 8 caractères.');
            }
            $db->beginTransaction();
            (new Auth())->updatePassword((int)$u['id'], $secret);
            $db->prepare('UPDATE users SET must_change_password = 1 WHERE id = ?')->execute([(int)$u['id']]);
            mg_revoquer_tout($db, (int)$u['id']);
            $db->commit();
            return ['ok' => true];

        case 'modifier':
            $u = mg_personne($db, mg_id($args, 1));
            $nom = null;
            foreach (array_slice($args, 2) as $a) {
                if (str_starts_with($a, 'nom=')) {
                    $nom = trim(substr($a, 4));
                } elseif (str_starts_with($a, 'courriel=')) {
                    throw new ErreurGestion("GulliFY n'a pas de courriel : on s'y connecte par nom d'utilisateur.");
                } else {
                    throw new ErreurGestion("Argument inconnu : $a (attendu : nom=…).");
                }
            }
            if ($nom === null) throw new ErreurGestion('Rien à modifier (attendu : nom=…).');
            if ($nom === '') throw new ErreurGestion('Le nom ne peut pas être vide.');
            if (mb_strlen($nom) > 100) throw new ErreurGestion('Ce nom est trop long (100 caractères au plus).');
            // Seul le nom AFFICHÉ change : le nom d'utilisateur sert à se
            // connecter et range ses favoris, listes et historique.
            $db->prepare('UPDATE users SET full_name = ? WHERE id = ?')->execute([$nom, (int)$u['id']]);
            return ['ok' => true];

        case 'desactiver':
            $u = mg_personne($db, mg_id($args, 1));
            mg_pas_dernier_admin($db, $u, "C'est le dernier administrateur actif de GulliFY : nomme quelqu'un d'autre avant de le désactiver.");
            $db->beginTransaction();
            $db->prepare('UPDATE users SET is_active = 0 WHERE id = ?')->execute([(int)$u['id']]);
            mg_revoquer_tout($db, (int)$u['id']);
            $db->commit();
            return ['ok' => true];

        case 'activer':
            $u = mg_personne($db, mg_id($args, 1));
            $db->prepare('UPDATE users SET is_active = 1 WHERE id = ?')->execute([(int)$u['id']]);
            return ['ok' => true];

        case 'supprimer':
            $u = mg_personne($db, mg_id($args, 1));
            if ($u['is_admin']) {
                $st = $db->prepare('SELECT COUNT(*) FROM users WHERE is_admin = 1 AND is_active = 1 AND id <> ?');
                $st->execute([(int)$u['id']]);
                if ((int)$st->fetchColumn() === 0) {
                    throw new ErreurGestion("C'est le dernier administrateur de GulliFY : nomme quelqu'un d'autre avant de supprimer ce compte.");
                }
            }
            $tables = $db->query('SHOW TABLES')->fetchAll(PDO::FETCH_COLUMN);
            $db->beginTransaction();
            foreach (MG_DONNEES_PERSONNELLES as $table => $colonne) {
                if (in_array($table, $tables, true)) {
                    $db->prepare("DELETE FROM `$table` WHERE `$colonne` = ?")->execute([$u['username']]);
                }
            }
            // Les sessions tombent en cascade avec le compte.
            $db->prepare('DELETE FROM users WHERE id = ?')->execute([(int)$u['id']]);
            $db->commit();
            Avatar::remove((int)$u['id']);
            return ['ok' => true];

        case 'photo':
            $u = mg_personne($db, mg_id($args, 1));
            if (($args[2] ?? '') === '--retirer') {
                Avatar::remove((int)$u['id']);
                return ['ok' => true];
            }
            if (isset($args[2])) throw new ErreurGestion("Argument inconnu : {$args[2]} (attendu : --retirer).");
            $image = stream_get_contents(STDIN, MG_PHOTO_MAX + 1);
            if ($image === false || $image === '') throw new ErreurGestion("Aucune image reçue.");
            if (strlen($image) > MG_PHOTO_MAX) throw new ErreurGestion('Cette image est trop lourde (5 Mo au plus).');
            // Le VRAI type, lu dans le contenu — jamais une extension annoncée.
            $info = @getimagesizefromstring($image);
            $mime = is_array($info) ? ($info['mime'] ?? '') : '';
            if (!in_array($mime, ['image/jpeg', 'image/png', 'image/webp'], true)) {
                throw new ErreurGestion("Ce fichier n'est pas une image JPEG, PNG ou WebP.");
            }
            $tmp = tempnam(sys_get_temp_dir(), 'photo');
            try {
                file_put_contents($tmp, $image);
                $dirExistait = is_dir(Avatar::dir());
                Avatar::store((int)$u['id'], $tmp, $mime);
                if (!$dirExistait) mg_rendre(Avatar::dir());
                mg_rendre(Avatar::path((int)$u['id']));
            } catch (RuntimeException $e) {
                throw new ErreurGestion("Cette image n'a pas pu être lue.");
            } finally {
                @unlink($tmp);
            }
            return ['ok' => true];

        case 'empreinte':
            $u = mg_personne($db, mg_id($args, 1));
            if ($u['must_change_password']) {
                throw new ErreurGestion('Mot de passe temporaire : rien à reprendre.');
            }
            $st = $db->prepare('SELECT password_hash FROM users WHERE id = ?');
            $st->execute([(int)$u['id']]);
            $hash = (string)$st->fetchColumn();
            if (preg_match('/^\$2[aby]\$\d\d\$[.\/A-Za-z0-9]{53}$/', $hash)) {
                $algo = 'bcrypt';
            } elseif (str_starts_with($hash, '$argon2id$')) {
                $algo = 'argon2id';
            } elseif (str_starts_with($hash, '$argon2i$')) {
                $algo = 'argon2i';
            } else {
                throw new ErreurGestion("Ce mot de passe n'est pas dans un format reprenable.");
            }
            return ['empreinte' => $hash, 'algo' => $algo];

        case 'lier':
            $u = mg_personne($db, mg_id($args, 1));
            $compteId = mg_id($args, 2, 'compte_id');
            if (strlen($compteId) > 64 || !preg_match('/^[A-Za-z0-9_\-]+$/', $compteId)) {
                throw new ErreurGestion('Cet identifiant de compte est invalide.');
            }
            $st = $db->prepare('SELECT id FROM users WHERE compte_id = ?');
            $st->execute([$compteId]);
            $deja = $st->fetchColumn();
            if ($deja !== false && (int)$deja !== (int)$u['id']) {
                throw new ErreurGestion('Ce compte de la maison est déjà relié à un autre compte GulliFY.');
            }
            // Le mot de passe Subsonic retenu jusque-là est l'ancien mot de
            // passe GulliFY : il tombe, place au mot de passe d'application.
            $db->prepare('UPDATE users SET compte_id = ?, subsonic_password = NULL WHERE id = ?')
                ->execute([$compteId, (int)$u['id']]);
            return ['ok' => true];

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
            $db->prepare('UPDATE users SET must_change_password = 1 WHERE id = ?')->execute([(int)$id]);
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
