<?php
/**
 * Gullify - Authentication
 * Manages users and sessions via MySQL.
 */
require_once __DIR__ . '/AppConfig.php';

class Auth {
    private $db;

    public function __construct() {
        $this->db = AppConfig::getDB();
    }

    public function createUser(string $username, string $password, ?string $fullName = null, bool $isAdmin = false, ?string $musicDirectory = null): bool {
        $passwordHash = password_hash($password, PASSWORD_DEFAULT);
        $stmt = $this->db->prepare("
            INSERT INTO users (username, password_hash, full_name, is_admin, music_directory)
            VALUES (?, ?, ?, ?, ?)
        ");
        return $stmt->execute([$username, $passwordHash, $fullName, $isAdmin ? 1 : 0, $musicDirectory]);
    }

    public function getUserByUsername(string $username): array|false {
        $stmt = $this->db->prepare("SELECT * FROM users WHERE username = ? AND is_active = 1");
        $stmt->execute([$username]);
        return $stmt->fetch(PDO::FETCH_ASSOC);
    }

    public function getUserById(int $id): array|false {
        $stmt = $this->db->prepare("SELECT * FROM users WHERE id = ? AND is_active = 1");
        $stmt->execute([$id]);
        return $stmt->fetch(PDO::FETCH_ASSOC);
    }

    public function verifyPassword(string $username, string $password): array|false {
        $user = $this->getUserByUsername($username);
        if ($user && password_verify($password, $user['password_hash'])) {
            return $user;
        }
        return false;
    }

    /**
     * Le bon mot de passe d'un compte DÉSACTIVÉ : la connexion le dit
     * clairement (« compte désactivé ») au lieu de « identifiants incorrects ».
     * Seulement avec le bon mot de passe — sans quoi on apprendrait à n'importe
     * qui quels comptes existent.
     */
    public function isDisabledAccount(string $username, string $password): bool {
        $stmt = $this->db->prepare("SELECT password_hash FROM users WHERE username = ? AND is_active = 0");
        $stmt->execute([$username]);
        $hash = $stmt->fetchColumn();
        return is_string($hash) && password_verify($password, $hash);
    }

    /** Le mot de passe est temporaire (posé par « Ma maison ») : à changer avant tout. */
    public static function mustChangePassword(array $user): bool {
        return !empty($user['must_change_password']);
    }

    /**
     * La personne change elle-même son mot de passe temporaire (ou non) :
     * le drapeau tombe, le mot de passe Subsonic gardé (l'ancien) est oublié,
     * et toutes ses autres sessions sont fermées — sauf $keepSessionId.
     */
    public function changeOwnPassword(int $userId, string $newPassword, ?string $keepSessionId): void {
        $this->db->beginTransaction();
        try {
            $this->db->prepare("UPDATE users SET password_hash = ?, must_change_password = 0 WHERE id = ?")
                ->execute([password_hash($newPassword, PASSWORD_DEFAULT), $userId]);
            try {
                $this->db->prepare("UPDATE users SET subsonic_password = NULL WHERE id = ?")->execute([$userId]);
            } catch (PDOException $e) {
                // colonne absente : aucun client Subsonic ne s'est jamais connecté
            }
            $this->db->prepare("DELETE FROM sessions WHERE user_id = ? AND id <> ?")
                ->execute([$userId, (string)$keepSessionId]);
            $this->db->commit();
        } catch (Throwable $e) {
            $this->db->rollBack();
            throw $e;
        }
    }

    public function updateLastLogin(int $userId): bool {
        $stmt = $this->db->prepare("UPDATE users SET last_login = NOW() WHERE id = ?");
        return $stmt->execute([$userId]);
    }

    public function updatePassword(int $userId, string $newPassword): bool {
        $passwordHash = password_hash($newPassword, PASSWORD_DEFAULT);
        $stmt = $this->db->prepare("UPDATE users SET password_hash = ? WHERE id = ?");
        return $stmt->execute([$passwordHash, $userId]);
    }

    public function getAllUsers(): array {
        $stmt = $this->db->query(
            "SELECT id, username, full_name, is_active, is_admin, music_directory,
                    storage_type, sftp_host, sftp_port, sftp_user, sftp_password, sftp_path,
                    created_at, last_login
             FROM users ORDER BY username"
        );
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }

    public function deleteUser(int $userId): bool {
        $stmt = $this->db->prepare("DELETE FROM users WHERE id = ?");
        return $stmt->execute([$userId]);
    }

    public function toggleUserActive(int $userId): bool {
        $stmt = $this->db->prepare("UPDATE users SET is_active = 1 - is_active WHERE id = ?");
        return $stmt->execute([$userId]);
    }

    public function updateMusicDirectory(int $userId, string $directoryName): bool {
        $stmt = $this->db->prepare("UPDATE users SET music_directory = ? WHERE id = ?");
        return $stmt->execute([$directoryName, $userId]);
    }

    public function getMusicDirectory(int $userId): ?string {
        $user = $this->getUserById($userId);
        if (!$user || empty($user['music_directory'])) {
            return null;
        }
        return AppConfig::getMusicBasePath() . '/' . $user['music_directory'];
    }

    public function getAllUsersWithMusicDirs(): array {
        $stmt = $this->db->query("
            SELECT id, username, full_name, music_directory, is_active, is_admin
            FROM users
            ORDER BY username
        ");
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }

    // Session management
    public function createSession(string $sessionId, int $userId, string $ipAddress, string $userAgent): bool {
        $stmt = $this->db->prepare("
            INSERT INTO sessions (id, user_id, ip_address, user_agent, created_at, last_activity)
            VALUES (?, ?, ?, ?, NOW(), NOW())
            ON DUPLICATE KEY UPDATE last_activity = NOW()
        ");
        return $stmt->execute([$sessionId, $userId, $ipAddress, $userAgent]);
    }

    /**
     * La session, avec l'état du compte : `user_active` (désactivé → la
     * session ne vaut plus rien) et `user_must_change` (mot de passe
     * temporaire → seul le changement est permis). Voir sessionUsable().
     */
    public function getSession(string $sessionId): array|false {
        $stmt = $this->db->prepare(
            "SELECT s.*, u.is_active AS user_active, u.must_change_password AS user_must_change
             FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.id = ?"
        );
        $stmt->execute([$sessionId]);
        return $stmt->fetch(PDO::FETCH_ASSOC);
    }

    /** Une session qui ouvre l'app : compte actif, mot de passe définitif. */
    public static function sessionUsable(array|false $session): bool {
        return $session !== false && !empty($session['user_active']) && empty($session['user_must_change']);
    }

    public function updateSessionActivity(string $sessionId): bool {
        $stmt = $this->db->prepare("UPDATE sessions SET last_activity = NOW() WHERE id = ?");
        return $stmt->execute([$sessionId]);
    }

    public function deleteSession(string $sessionId): bool {
        $stmt = $this->db->prepare("DELETE FROM sessions WHERE id = ?");
        return $stmt->execute([$sessionId]);
    }

    public function cleanOldSessions(int $maxAge = 86400): bool {
        $stmt = $this->db->prepare("
            DELETE FROM sessions
            WHERE TIMESTAMPDIFF(SECOND, last_activity, NOW()) > ?
        ");
        return $stmt->execute([$maxAge]);
    }
}
