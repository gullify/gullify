<?php
/**
 * Gullify — Custom radio stations + per-user state.
 *
 * Two tables, both auto-created on first use:
 *
 *   radio_custom_stations   — stations the user typed in / imported
 *   radio_user_state        — favorite/hidden flag keyed by (user, station_id)
 *
 * The station_id used in radio_user_state is either:
 *   - the Radio Browser UUID for catalog stations, or
 *   - "custom:N" for a custom_stations.id row
 *
 * This lets us merge the catalog and the user's stations into one list,
 * decorate each item with favorite + hidden flags, and operate on either
 * with the same identifier.
 */

require_once __DIR__ . '/AppConfig.php';

class RadioStations
{
    public static function ensureTables(): void
    {
        static $bootstrapped = false;
        if ($bootstrapped) return;
        $bootstrapped = true;
        try {
            $db = AppConfig::getDB();
            $db->exec("
                CREATE TABLE IF NOT EXISTS radio_custom_stations (
                    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    user VARCHAR(100) NOT NULL,
                    name VARCHAR(200) NOT NULL,
                    stream_url TEXT NOT NULL,
                    logo TEXT NULL,
                    homepage TEXT NULL,
                    genres TEXT NULL,
                    country VARCHAR(80) NULL,
                    language VARCHAR(80) NULL,
                    bitrate INT NULL,
                    format VARCHAR(20) NULL,
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    INDEX idx_custom_user (user)
                )
            ");
            $db->exec("
                CREATE TABLE IF NOT EXISTS radio_user_state (
                    user VARCHAR(100) NOT NULL,
                    station_id VARCHAR(120) NOT NULL,
                    is_favorite TINYINT(1) NOT NULL DEFAULT 0,
                    is_hidden TINYINT(1) NOT NULL DEFAULT 0,
                    sort_order INT NOT NULL DEFAULT 0,
                    PRIMARY KEY (user, station_id),
                    INDEX idx_state_fav (user, is_favorite),
                    INDEX idx_state_hid (user, is_hidden)
                )
            ");
        } catch (\Throwable $e) {
            error_log('RadioStations::ensureTables failed: ' . $e->getMessage());
        }
    }

    /** Return a station array shaped like the Radio Browser format. */
    public static function listCustom(string $user): array
    {
        self::ensureTables();
        $db = AppConfig::getDB();
        $stmt = $db->prepare("
            SELECT id, name, stream_url, logo, homepage, genres, country, language, bitrate, format
            FROM radio_custom_stations
            WHERE user = ?
            ORDER BY name ASC
        ");
        $stmt->execute([$user]);
        $rows = $stmt->fetchAll(\PDO::FETCH_ASSOC);
        $out = [];
        foreach ($rows as $r) {
            $out[] = [
                'id'       => 'custom:' . $r['id'],
                'custom'   => true,
                'name'     => $r['name'],
                'country'  => $r['country'] ?? '',
                'state'    => '',
                'language' => $r['language'] ?? '',
                'genres'   => array_values(array_filter(array_map('trim', explode(',', (string)($r['genres'] ?? ''))))),
                'streams'  => [[
                    'url'     => $r['stream_url'],
                    'format'  => $r['format'] ?: 'MP3',
                    'bitrate' => (int)($r['bitrate'] ?: 128),
                    'secure'  => str_starts_with((string)$r['stream_url'], 'https://'),
                ]],
                'logo'     => $r['logo'] ?: null,
                'website'  => $r['homepage'] ?: null,
            ];
        }
        return $out;
    }

    public static function getState(string $user): array
    {
        self::ensureTables();
        $db = AppConfig::getDB();
        $stmt = $db->prepare("SELECT station_id, is_favorite, is_hidden FROM radio_user_state WHERE user = ?");
        $stmt->execute([$user]);
        $out = [];
        foreach ($stmt->fetchAll(\PDO::FETCH_ASSOC) as $r) {
            $out[$r['station_id']] = [
                'favorite' => (bool)$r['is_favorite'],
                'hidden'   => (bool)$r['is_hidden'],
            ];
        }
        return $out;
    }

    public static function addCustom(string $user, array $data): int|false
    {
        self::ensureTables();
        $name      = trim((string)($data['name'] ?? ''));
        $streamUrl = trim((string)($data['stream_url'] ?? $data['url'] ?? ''));
        if ($name === '' || $streamUrl === '') return false;
        if (!filter_var($streamUrl, FILTER_VALIDATE_URL)) return false;

        $genres = $data['genres'] ?? '';
        if (is_array($genres)) $genres = implode(',', $genres);

        $db = AppConfig::getDB();
        $stmt = $db->prepare("
            INSERT INTO radio_custom_stations
                (user, name, stream_url, logo, homepage, genres, country, language, bitrate, format)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ");
        $stmt->execute([
            $user,
            mb_substr($name, 0, 200),
            $streamUrl,
            $data['logo']     ?? null,
            $data['homepage'] ?? null,
            $genres ?: null,
            $data['country']  ?? null,
            $data['language'] ?? null,
            isset($data['bitrate']) ? (int)$data['bitrate'] : null,
            $data['format']   ?? null,
        ]);
        return (int)$db->lastInsertId();
    }

    public static function removeCustom(string $user, int $id): bool
    {
        self::ensureTables();
        $db = AppConfig::getDB();
        $stmt = $db->prepare("DELETE FROM radio_custom_stations WHERE user = ? AND id = ?");
        $stmt->execute([$user, $id]);
        $del = $stmt->rowCount() > 0;
        // Clean up any state row tied to this custom station
        $sid = 'custom:' . $id;
        $db->prepare("DELETE FROM radio_user_state WHERE user = ? AND station_id = ?")
            ->execute([$user, $sid]);
        return $del;
    }

    public static function toggleFlag(string $user, string $stationId, string $flag): array
    {
        self::ensureTables();
        if (!in_array($flag, ['is_favorite', 'is_hidden'], true)) {
            throw new \InvalidArgumentException('bad flag');
        }
        $db = AppConfig::getDB();
        // Upsert the row first
        $stmt = $db->prepare("
            INSERT INTO radio_user_state (user, station_id, is_favorite, is_hidden)
            VALUES (?, ?, 0, 0)
            ON DUPLICATE KEY UPDATE user = user
        ");
        $stmt->execute([$user, $stationId]);
        // Toggle
        $stmt = $db->prepare("UPDATE radio_user_state SET $flag = 1 - $flag WHERE user = ? AND station_id = ?");
        $stmt->execute([$user, $stationId]);
        // Return new state
        $stmt = $db->prepare("SELECT is_favorite, is_hidden FROM radio_user_state WHERE user = ? AND station_id = ?");
        $stmt->execute([$user, $stationId]);
        $row = $stmt->fetch(\PDO::FETCH_ASSOC) ?: [];
        return [
            'favorite' => (bool)($row['is_favorite'] ?? false),
            'hidden'   => (bool)($row['is_hidden']   ?? false),
        ];
    }

    public static function setFlagBulk(string $user, array $stationIds, string $flag, int $value): int
    {
        self::ensureTables();
        if (!in_array($flag, ['is_favorite', 'is_hidden'], true)) return 0;
        if (!$stationIds) return 0;
        $db = AppConfig::getDB();
        $n = 0;
        foreach ($stationIds as $sid) {
            $stmt = $db->prepare("
                INSERT INTO radio_user_state (user, station_id, $flag) VALUES (?, ?, ?)
                ON DUPLICATE KEY UPDATE $flag = VALUES($flag)
            ");
            $stmt->execute([$user, (string)$sid, (int)$value]);
            $n++;
        }
        return $n;
    }
}
