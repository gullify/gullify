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

    public function getSession(string $sessionId): array|false {
        $stmt = $this->db->prepare("SELECT * FROM sessions WHERE id = ?");
        $stmt->execute([$sessionId]);
        return $stmt->fetch(PDO::FETCH_ASSOC);
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
