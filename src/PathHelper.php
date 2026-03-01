<?php
/**
 * Gullify - Music Path Helper
 * Manages music directory paths for users via MySQL database.
 * Supports both local and SFTP storage backends.
 */
require_once __DIR__ . '/AppConfig.php';
require_once __DIR__ . '/Storage/StorageInterface.php';
require_once __DIR__ . '/Storage/LocalStorage.php';
require_once __DIR__ . '/Storage/SFTPStorage.php';
require_once __DIR__ . '/Storage/StorageFactory.php';

class PathHelper {
    private $db;

    public function __construct() {
        $this->db = AppConfig::getDB();
    }

    /**
     * Get all users with their music paths.
     * For local users: returns the full local path.
     * For SFTP users: returns the sftp_path (remote root).
     * Only includes users whose path is accessible.
     * @return array ['username' => 'full_path']
     */
    public function getAllUserPaths(): array {
        $basePath = AppConfig::getMusicBasePath();
        $stmt = $this->db->query("
            SELECT username, music_directory, is_active,
                   storage_type, sftp_host, sftp_path
            FROM users
            WHERE is_active = 1
              AND (
                  (storage_type = 'local' AND music_directory IS NOT NULL AND music_directory != '')
                  OR
                  (storage_type = 'sftp' AND sftp_host IS NOT NULL AND sftp_path IS NOT NULL AND sftp_path != '')
              )
            ORDER BY username
        ");
        $paths = [];
        while ($row = $stmt->fetch()) {
            if (($row['storage_type'] ?? 'local') === 'sftp') {
                // For SFTP users, record their sftp_path as "path"
                // (actual accessibility check would require an SFTP connection — skip here)
                $paths[$row['username']] = $row['sftp_path'];
            } else {
                $fullPath = $basePath . '/' . $row['music_directory'];
                if (is_dir($fullPath)) {
                    $paths[$row['username']] = $fullPath;
                }
            }
        }
        return $paths;
    }

    /**
     * Get music root path for a specific user.
     * Local: /music/Musique  |  SFTP: /remote/path
     */
    public function getUserPath(string $username): ?string {
        $basePath = AppConfig::getMusicBasePath();
        $stmt = $this->db->prepare(
            "SELECT music_directory, storage_type, sftp_path
             FROM users WHERE username = ? AND is_active = 1"
        );
        $stmt->execute([$username]);
        $row = $stmt->fetch();
        if (!$row) return null;

        if (($row['storage_type'] ?? 'local') === 'sftp') {
            return !empty($row['sftp_path']) ? $row['sftp_path'] : null;
        }

        return !empty($row['music_directory'])
            ? $basePath . '/' . $row['music_directory']
            : null;
    }

    /**
     * Check if user has a configured and accessible music directory.
     */
    public function userHasMusicDirectory(string $username): bool {
        $stmt = $this->db->prepare(
            "SELECT music_directory, storage_type, sftp_host, sftp_path
             FROM users WHERE username = ? AND is_active = 1"
        );
        $stmt->execute([$username]);
        $row = $stmt->fetch();
        if (!$row) return false;

        if (($row['storage_type'] ?? 'local') === 'sftp') {
            return !empty($row['sftp_host']) && !empty($row['sftp_path']);
        }

        if (empty($row['music_directory'])) return false;
        $path = AppConfig::getMusicBasePath() . '/' . $row['music_directory'];
        return is_dir($path);
    }

    /**
     * Get list of active usernames with music directories.
     */
    public function getActiveUsernames(): array {
        return array_keys($this->getAllUserPaths());
    }
}
