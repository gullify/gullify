<?php
/**
 * Gullify — Notifications helper
 *
 * Per-user system message store. Other modules (library scanner, downloads,
 * imports…) call Notifications::add() to push items; the topbar UI polls via
 * /api/notifications.php to render them.
 */

require_once __DIR__ . '/AppConfig.php';

class Notifications
{
    /** Schema bootstrap — runs once per request, idempotent. */
    public static function ensureTable(): void
    {
        static $bootstrapped = false;
        if ($bootstrapped) return;
        $bootstrapped = true;
        try {
            $db = AppConfig::getDB();
            $db->exec("
                CREATE TABLE IF NOT EXISTS notifications (
                    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    user VARCHAR(100) NOT NULL,
                    type VARCHAR(40) NOT NULL,
                    title VARCHAR(200) NOT NULL,
                    message TEXT NULL,
                    data JSON NULL,
                    read_at DATETIME NULL,
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    INDEX idx_notif_user_created (user, created_at DESC),
                    INDEX idx_notif_user_read   (user, read_at)
                )
            ");
        } catch (\Exception $e) {
            error_log('Notifications::ensureTable failed: ' . $e->getMessage());
        }
    }

    /**
     * Insert a notification.
     *
     * @param string $user    Username (matches users.username / artists.user)
     * @param string $type    Short tag, e.g. 'scan_complete', 'download_done', 'import'
     * @param string $title   One-line headline
     * @param string|null $message Longer body, optional
     * @param array  $data    Arbitrary structured payload (will be JSON-encoded)
     * @return int|false    Inserted id, or false on failure
     */
    public static function add(string $user, string $type, string $title, ?string $message = null, array $data = []): int|false
    {
        self::ensureTable();
        try {
            $db = AppConfig::getDB();
            $stmt = $db->prepare("
                INSERT INTO notifications (user, type, title, message, data)
                VALUES (?, ?, ?, ?, ?)
            ");
            $stmt->execute([$user, $type, $title, $message, $data ? json_encode($data, JSON_UNESCAPED_UNICODE) : null]);
            return (int)$db->lastInsertId();
        } catch (\Exception $e) {
            error_log('Notifications::add failed: ' . $e->getMessage());
            return false;
        }
    }

    /** Recent items for a user, newest first. */
    public static function list(string $user, int $limit = 30, int $offset = 0): array
    {
        self::ensureTable();
        try {
            $db = AppConfig::getDB();
            $stmt = $db->prepare("
                SELECT id, type, title, message, data, read_at, created_at
                FROM notifications
                WHERE user = ?
                ORDER BY created_at DESC
                LIMIT ? OFFSET ?
            ");
            $stmt->bindValue(1, $user);
            $stmt->bindValue(2, max(1, min(100, $limit)), PDO::PARAM_INT);
            $stmt->bindValue(3, max(0, $offset), PDO::PARAM_INT);
            $stmt->execute();
            $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
            foreach ($rows as &$r) {
                $r['id']      = (int)$r['id'];
                $r['data']    = $r['data'] ? json_decode($r['data'], true) : null;
                $r['unread']  = empty($r['read_at']);
            }
            return $rows;
        } catch (\Exception $e) {
            error_log('Notifications::list failed: ' . $e->getMessage());
            return [];
        }
    }

    public static function countUnread(string $user): int
    {
        self::ensureTable();
        try {
            $db = AppConfig::getDB();
            $stmt = $db->prepare("SELECT COUNT(*) FROM notifications WHERE user = ? AND read_at IS NULL");
            $stmt->execute([$user]);
            return (int)$stmt->fetchColumn();
        } catch (\Exception $e) {
            return 0;
        }
    }

    /** Mark one or all as read. Pass id=0 to mark all for the user. */
    public static function markRead(string $user, int $id = 0): bool
    {
        self::ensureTable();
        try {
            $db = AppConfig::getDB();
            if ($id > 0) {
                $stmt = $db->prepare("UPDATE notifications SET read_at = NOW() WHERE user = ? AND id = ? AND read_at IS NULL");
                $stmt->execute([$user, $id]);
            } else {
                $stmt = $db->prepare("UPDATE notifications SET read_at = NOW() WHERE user = ? AND read_at IS NULL");
                $stmt->execute([$user]);
            }
            return true;
        } catch (\Exception $e) {
            return false;
        }
    }

    /** Delete one or all of a user's notifications. */
    public static function clear(string $user, int $id = 0): bool
    {
        self::ensureTable();
        try {
            $db = AppConfig::getDB();
            if ($id > 0) {
                $stmt = $db->prepare("DELETE FROM notifications WHERE user = ? AND id = ?");
                $stmt->execute([$user, $id]);
            } else {
                $stmt = $db->prepare("DELETE FROM notifications WHERE user = ?");
                $stmt->execute([$user]);
            }
            return true;
        } catch (\Exception $e) {
            return false;
        }
    }
}
