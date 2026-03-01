<?php
/**
 * Gullify - Storage Factory
 * Returns the appropriate StorageInterface implementation for a given user.
 */
require_once __DIR__ . '/StorageInterface.php';
require_once __DIR__ . '/LocalStorage.php';
require_once __DIR__ . '/SFTPStorage.php';
require_once __DIR__ . '/../AppConfig.php';

class StorageFactory {
    /**
     * Return the correct storage backend for the given username.
     * Reads storage_type and sftp_* columns from the users table.
     */
    public static function forUser(string $username): StorageInterface {
        $db   = AppConfig::getDB();
        $stmt = $db->prepare(
            'SELECT storage_type, sftp_host, sftp_port, sftp_user, sftp_password, sftp_path, music_directory
             FROM users WHERE username = ?'
        );
        $stmt->execute([$username]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);

        if ($user && ($user['storage_type'] ?? 'local') === 'sftp'
            && !empty($user['sftp_host']) && !empty($user['sftp_path'])
        ) {
            $password = self::decryptPassword($user['sftp_password'] ?? '');
            return new SFTPStorage(
                $user['sftp_host'],
                (int) ($user['sftp_port'] ?? 22),
                $user['sftp_user'],
                $password,
                $user['sftp_path']
            );
        }

        $basePath  = AppConfig::getMusicBasePath();
        $musicDir  = $user['music_directory'] ?? '';
        $musicRoot = $basePath . ($musicDir ? '/' . $musicDir : '');
        return new LocalStorage($basePath, $musicRoot);
    }

    // -------------------------------------------------------------------------
    // Password encryption helpers
    // -------------------------------------------------------------------------

    /**
     * Encrypt an SFTP password for storage in the database.
     * Uses AES-256-CBC with key derived from APP_SECRET.
     */
    public static function encryptPassword(string $plaintext): string {
        $key    = self::deriveKey();
        $iv     = random_bytes(16);
        $cipher = openssl_encrypt($plaintext, 'AES-256-CBC', $key, OPENSSL_RAW_DATA, $iv);
        // Store as base64(iv + ciphertext)
        return base64_encode($iv . $cipher);
    }

    /**
     * Decrypt an SFTP password retrieved from the database.
     */
    public static function decryptPassword(string $encoded): string {
        if (empty($encoded)) return '';
        $raw = base64_decode($encoded, true);
        if ($raw === false || strlen($raw) < 17) return '';
        $iv         = substr($raw, 0, 16);
        $ciphertext = substr($raw, 16);
        $key        = self::deriveKey();
        $decrypted  = openssl_decrypt($ciphertext, 'AES-256-CBC', $key, OPENSSL_RAW_DATA, $iv);
        return $decrypted !== false ? $decrypted : '';
    }

    /**
     * Derive a 32-byte key from APP_SECRET.
     */
    private static function deriveKey(): string {
        $secret = AppConfig::getSecret();
        return hash('sha256', $secret, true); // binary, 32 bytes
    }
}
