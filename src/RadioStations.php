<?php
/**
 * Gullify — Radio stations. Chaque utilisateur a sa propre liste (idée #97).
 *
 * Il n'y a plus de catalogue public partagé : le catalogue Radio Browser
 * n'est qu'une *source d'import*. À la première visite, il est transféré
 * dans la liste de l'utilisateur, et à partir de là tout lui appartient —
 * une station supprimée l'est pour de bon, une station modifiée n'est
 * modifiée que chez lui.
 *
 *   radio_custom_stations   — les stations de l'utilisateur (les siennes)
 *   radio_user_state        — favori + dossier, par (user, station_id)
 *   radio_user_prefs        — quand le catalogue a été transféré chez lui
 *
 * Le station_id est toujours "custom:N" (une ligne de radio_custom_stations)
 * depuis le transfert.
 */

require_once __DIR__ . '/AppConfig.php';
require_once __DIR__ . '/RadioStreamResolver.php';

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
                    original_url TEXT NULL,
                    logo TEXT NULL,
                    homepage TEXT NULL,
                    genres TEXT NULL,
                    country VARCHAR(80) NULL,
                    language VARCHAR(80) NULL,
                    bitrate INT NULL,
                    format VARCHAR(20) NULL,
                    is_playlist TINYINT(1) NOT NULL DEFAULT 0,
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at DATETIME NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
                    INDEX idx_custom_user (user)
                )
            ");
            // Best-effort columns for upgrades from the v1 schema (no IF NOT EXISTS for ADD COLUMN on older MySQL)
            foreach (['original_url TEXT NULL', 'is_playlist TINYINT(1) NOT NULL DEFAULT 0',
                      'updated_at DATETIME NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP'] as $col) {
                $colName = strtok($col, ' ');
                try {
                    $db->exec("ALTER TABLE radio_custom_stations ADD COLUMN $col");
                } catch (\Throwable $e) { /* already there */ }
            }
            $db->exec("
                CREATE TABLE IF NOT EXISTS radio_user_state (
                    user VARCHAR(100) NOT NULL,
                    station_id VARCHAR(120) NOT NULL,
                    is_favorite TINYINT(1) NOT NULL DEFAULT 0,
                    is_hidden TINYINT(1) NOT NULL DEFAULT 0,
                    sort_order INT NOT NULL DEFAULT 0,
                    folder_id INT UNSIGNED NULL,
                    PRIMARY KEY (user, station_id),
                    INDEX idx_state_fav (user, is_favorite),
                    INDEX idx_state_hid (user, is_hidden),
                    INDEX idx_state_folder (user, folder_id)
                )
            ");
            try { $db->exec("ALTER TABLE radio_user_state ADD COLUMN folder_id INT UNSIGNED NULL"); } catch (\Throwable $e) {}
            try { $db->exec("ALTER TABLE radio_user_state ADD INDEX idx_state_folder (user, folder_id)"); } catch (\Throwable $e) {}

            // Per-user preferences. `catalog_imported_at` est la date à
            // laquelle le catalogue Radio Browser a été transféré dans la
            // liste de cet utilisateur — une seule fois (idée #97).
            // (`catalog_enabled` est un reste de l'idée #96, plus lu.)
            $db->exec("
                CREATE TABLE IF NOT EXISTS radio_user_prefs (
                    user VARCHAR(100) NOT NULL PRIMARY KEY,
                    catalog_enabled TINYINT(1) NOT NULL DEFAULT 1,
                    catalog_imported_at DATETIME NULL DEFAULT NULL
                )
            ");
            try { $db->exec("ALTER TABLE radio_user_prefs ADD COLUMN catalog_imported_at DATETIME NULL DEFAULT NULL"); } catch (\Throwable $e) {}

            $db->exec("
                CREATE TABLE IF NOT EXISTS radio_folders (
                    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    user VARCHAR(100) NOT NULL,
                    name VARCHAR(120) NOT NULL,
                    color VARCHAR(20) NULL,
                    sort_order INT NOT NULL DEFAULT 0,
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    INDEX idx_folders_user (user)
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
            SELECT id, name, stream_url, original_url, logo, homepage, genres,
                   country, language, bitrate, format, is_playlist
            FROM radio_custom_stations
            WHERE user = ?
            ORDER BY name ASC
        ");
        $stmt->execute([$user]);
        $rows = $stmt->fetchAll(\PDO::FETCH_ASSOC);
        $out = [];
        foreach ($rows as $r) {
            $out[] = [
                'id'           => 'custom:' . $r['id'],
                'custom'       => true,
                'custom_id'    => (int)$r['id'],
                'name'         => $r['name'],
                'country'      => $r['country'] ?? '',
                'state'        => '',
                'language'     => $r['language'] ?? '',
                'original_url' => $r['original_url'] ?? $r['stream_url'],
                'is_playlist'  => (bool)($r['is_playlist'] ?? false),
                'genres'       => array_values(array_filter(array_map('trim', explode(',', (string)($r['genres'] ?? ''))))),
                'streams'      => [[
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
        $stmt = $db->prepare("SELECT station_id, is_favorite, is_hidden, folder_id FROM radio_user_state WHERE user = ?");
        $stmt->execute([$user]);
        $out = [];
        foreach ($stmt->fetchAll(\PDO::FETCH_ASSOC) as $r) {
            $out[$r['station_id']] = [
                'favorite'  => (bool)$r['is_favorite'],
                'hidden'    => (bool)$r['is_hidden'],
                'folder_id' => $r['folder_id'] !== null ? (int)$r['folder_id'] : null,
            ];
        }
        return $out;
    }

    // ── Transfert du catalogue dans la liste de l'utilisateur ────────────
    /** Le catalogue a-t-il déjà été transféré chez cet utilisateur ? */
    public static function catalogImported(string $user): bool
    {
        self::ensureTables();
        try {
            $db = AppConfig::getDB();
            $stmt = $db->prepare("SELECT catalog_imported_at FROM radio_user_prefs WHERE user = ?");
            $stmt->execute([$user]);
            return (bool)$stmt->fetchColumn();
        } catch (\Throwable $e) {
            // En cas de doute, on ne rejoue pas un transfert de 1200 stations.
            error_log('RadioStations::catalogImported failed: ' . $e->getMessage());
            return true;
        }
    }

    /**
     * Réserve le transfert initial du catalogue pour cet utilisateur.
     *
     * Vrai une seule fois : deux requêtes simultanées ne peuvent pas
     * transférer le catalogue deux fois, la pose de la date est atomique.
     */
    public static function claimCatalogImport(string $user): bool
    {
        self::ensureTables();
        try {
            $db = AppConfig::getDB();
            $stmt = $db->prepare("
                INSERT INTO radio_user_prefs (user, catalog_imported_at) VALUES (?, NOW())
                ON DUPLICATE KEY UPDATE
                    catalog_imported_at = IF(catalog_imported_at IS NULL, NOW(), catalog_imported_at)
            ");
            $stmt->execute([$user]);
            // 1 = insertion, 2 = date posée, 0 = elle y était déjà
            return $stmt->rowCount() !== 0;
        } catch (\Throwable $e) {
            error_log('RadioStations::claimCatalogImport failed: ' . $e->getMessage());
            return false;
        }
    }

    /**
     * Copie des stations du catalogue Radio Browser dans la liste de
     * l'utilisateur. Les lignes arrivent déjà au format Radio Browser (voir
     * web-radio.php) : leur URL est celle que Radio Browser a résolue, rien
     * à re-résoudre ici.
     *
     * Ce qu'il possède déjà (même URL de flux) n'est pas dupliqué — pas plus
     * que les jumelles du catalogue, qui servent le même flux sous deux noms
     * (une centaine sur 1200). Les insertions partent par paquets de 200 :
     * transférer 1200 stations ne doit pas coûter 1200 allers-retours SQL.
     *
     * $withState liste les ids de catalogue dont il faut reporter le favori
     * ou le dossier ; le tableau renvoyé associe ces ids à leur « custom:N ».
     *
     * @return array{imported:int, map:array<string,string>}
     */
    public static function importCatalog(string $user, array $stations, array $withState = []): array
    {
        self::ensureTables();
        if (!$stations) return ['imported' => 0, 'map' => []];
        $db = AppConfig::getDB();

        // Ce qu'il a déjà, en une seule requête.
        $stmt = $db->prepare("SELECT stream_url FROM radio_custom_stations WHERE user = ?");
        $stmt->execute([$user]);
        $known = array_flip($stmt->fetchAll(\PDO::FETCH_COLUMN, 0));

        $wanted = array_flip(array_map('strval', $withState));
        $rows = [];          // lignes à insérer
        $urlOfOldId = [];    // id catalogue => URL, pour retrouver la copie

        foreach ($stations as $s) {
            $stream = $s['streams'][0] ?? null;
            $url    = trim((string)($stream['url'] ?? ''));
            $name   = trim((string)($s['name'] ?? ''));
            $oldId  = (string)($s['id'] ?? '');
            if ($name === '' || $url === '' || $oldId === '') continue;
            if (isset($wanted[$oldId])) $urlOfOldId[$oldId] = $url;
            if (isset($known[$url])) continue; // déjà chez lui (ou doublon du catalogue)
            $known[$url] = true;
            $rows[] = [
                $user,
                mb_substr($name, 0, 200),
                $url,
                $url,
                ($s['logo']    ?? null) ?: null,
                ($s['website'] ?? null) ?: null,
                implode(',', array_map('strval', $s['genres'] ?? [])) ?: null,
                ($s['country']  ?? null) ?: null,
                ($s['language'] ?? null) ?: null,
                (int)($stream['bitrate'] ?? 0) ?: null,
                $stream['format'] ?? null,
            ];
        }

        $imported = 0;
        foreach (array_chunk($rows, 200) as $chunk) {
            $values = implode(', ', array_fill(0, count($chunk), '(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)'));
            $stmt = $db->prepare("
                INSERT INTO radio_custom_stations
                    (user, name, stream_url, original_url, logo, homepage, genres, country, language, bitrate, format, is_playlist)
                VALUES $values
            ");
            $stmt->execute(array_merge(...$chunk));
            $imported += count($chunk);
        }

        // Retrouver les copies dont il faut reprendre le favori / le dossier.
        $map = [];
        if ($urlOfOldId) {
            $byUrl = [];
            foreach (array_chunk(array_values(array_unique($urlOfOldId)), 200) as $chunk) {
                $marks = implode(',', array_fill(0, count($chunk), '?'));
                $stmt = $db->prepare("
                    SELECT id, stream_url FROM radio_custom_stations
                    WHERE user = ? AND stream_url IN ($marks)
                ");
                $stmt->execute(array_merge([$user], $chunk));
                foreach ($stmt->fetchAll(\PDO::FETCH_ASSOC) as $r) {
                    $byUrl[$r['stream_url']] = 'custom:' . (int)$r['id'];
                }
            }
            foreach ($urlOfOldId as $oldId => $url) {
                if (isset($byUrl[$url])) $map[$oldId] = $byUrl[$url];
            }
        }
        return ['imported' => $imported, 'map' => $map];
    }

    /**
     * Le transfert lui-même : le catalogue Radio Browser passe dans la liste
     * de l'utilisateur. Renvoie le nombre de stations ajoutées.
     *
     * $initial = le transfert unique, à sa première visite après la mise à
     * jour : ce qu'il avait déjà supprimé ne revient pas, ses favoris et ses
     * dossiers suivent leur copie. Sinon c'est un import demandé à la main,
     * qui reprend le catalogue tel quel — sans jamais dupliquer ce qu'il a.
     */
    public static function transferCatalog(string $user, array $stations, bool $initial): int
    {
        self::ensureTables();
        if ($user === '' || !$stations) return 0;
        $state = $initial ? self::getState($user) : [];

        // Le catalogue sert la même URL de flux sous plusieurs stations (une
        // centaine de jumelles) : une station supprimée doit rester
        // supprimée, y compris sous le nom de sa jumelle.
        $deletedUrls = [];
        foreach ($stations as $s) {
            if (empty(($state[(string)($s['id'] ?? '')] ?? [])['hidden'])) continue;
            $url = trim((string)($s['streams'][0]['url'] ?? ''));
            if ($url !== '') $deletedUrls[$url] = true;
        }

        $keep = [];
        $withState = [];
        foreach ($stations as $s) {
            $sid   = (string)($s['id'] ?? '');
            $flags = $state[$sid] ?? null;
            if ($flags && !empty($flags['hidden'])) continue; // supprimée avant le transfert
            if (isset($deletedUrls[trim((string)($s['streams'][0]['url'] ?? ''))])) continue;
            $keep[] = $s;
            if ($flags && (!empty($flags['favorite']) || ($flags['folder_id'] ?? null) !== null)) {
                $withState[] = $sid;
            }
        }

        $res  = self::importCatalog($user, $keep, $withState);
        $favs = [];
        foreach ($res['map'] as $oldId => $newId) {
            $old = $state[$oldId] ?? null;
            if (!$old) continue;
            if (!empty($old['favorite'])) $favs[] = $newId;
            if (($old['folder_id'] ?? null) !== null) {
                self::moveStations($user, [$newId], (int)$old['folder_id']);
            }
        }
        if ($favs) self::setFlagBulk($user, $favs, 'is_favorite', 1);
        if ($initial) self::forgetCatalogState($user);
        return $res['imported'];
    }

    /**
     * Oublie l'état attaché aux stations du catalogue : depuis le transfert,
     * elles n'existent plus qu'en copies « custom:N », et leurs pierres
     * tombales n'ont plus rien à masquer.
     */
    public static function forgetCatalogState(string $user): int
    {
        self::ensureTables();
        $db = AppConfig::getDB();
        $stmt = $db->prepare("DELETE FROM radio_user_state WHERE user = ? AND station_id NOT LIKE 'custom:%'");
        $stmt->execute([$user]);
        return $stmt->rowCount();
    }

    // ── Folders ──────────────────────────────────────────────────────────
    public static function listFolders(string $user): array
    {
        self::ensureTables();
        $db = AppConfig::getDB();
        // Include station_count so the UI can show "Rock (5)"
        $stmt = $db->prepare("
            SELECT f.id, f.name, f.color, f.sort_order,
                   COUNT(DISTINCT s.station_id) AS station_count
            FROM radio_folders f
            LEFT JOIN radio_user_state s ON s.user = f.user AND s.folder_id = f.id
            WHERE f.user = ?
            GROUP BY f.id, f.name, f.color, f.sort_order
            ORDER BY f.sort_order ASC, f.name ASC
        ");
        $stmt->execute([$user]);
        $out = [];
        foreach ($stmt->fetchAll(\PDO::FETCH_ASSOC) as $r) {
            $out[] = [
                'id'            => (int)$r['id'],
                'name'          => $r['name'],
                'color'         => $r['color'] ?: null,
                'sort_order'    => (int)$r['sort_order'],
                'station_count' => (int)$r['station_count'],
            ];
        }
        return $out;
    }

    public static function createFolder(string $user, string $name, ?string $color = null): int|false
    {
        self::ensureTables();
        $name = trim($name);
        if ($name === '') return false;
        $db = AppConfig::getDB();
        $stmt = $db->prepare("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM radio_folders WHERE user = ?");
        $stmt->execute([$user]);
        $nextOrder = (int)$stmt->fetchColumn();
        $stmt = $db->prepare("INSERT INTO radio_folders (user, name, color, sort_order) VALUES (?, ?, ?, ?)");
        $stmt->execute([$user, mb_substr($name, 0, 120), $color, $nextOrder]);
        return (int)$db->lastInsertId();
    }

    public static function renameFolder(string $user, int $id, string $name, ?string $color = null): bool
    {
        self::ensureTables();
        $name = trim($name);
        if ($name === '') return false;
        $db = AppConfig::getDB();
        $stmt = $db->prepare("UPDATE radio_folders SET name = ?, color = ? WHERE user = ? AND id = ?");
        $stmt->execute([mb_substr($name, 0, 120), $color, $user, $id]);
        return $stmt->rowCount() > 0;
    }

    public static function deleteFolder(string $user, int $id): bool
    {
        self::ensureTables();
        $db = AppConfig::getDB();
        // Drop the folder; rows in radio_user_state become folder_id = NULL
        $db->prepare("UPDATE radio_user_state SET folder_id = NULL WHERE user = ? AND folder_id = ?")
            ->execute([$user, $id]);
        $stmt = $db->prepare("DELETE FROM radio_folders WHERE user = ? AND id = ?");
        $stmt->execute([$user, $id]);
        return $stmt->rowCount() > 0;
    }

    /** Move multiple stations into a folder (or null to unassign). */
    public static function moveStations(string $user, array $stationIds, ?int $folderId): int
    {
        self::ensureTables();
        if (!$stationIds) return 0;
        if ($folderId !== null) {
            // Make sure the folder belongs to this user
            $db = AppConfig::getDB();
            $stmt = $db->prepare("SELECT 1 FROM radio_folders WHERE user = ? AND id = ?");
            $stmt->execute([$user, $folderId]);
            if (!$stmt->fetchColumn()) return 0;
        }
        $db = AppConfig::getDB();
        $n = 0;
        foreach ($stationIds as $sid) {
            $stmt = $db->prepare("
                INSERT INTO radio_user_state (user, station_id, folder_id) VALUES (?, ?, ?)
                ON DUPLICATE KEY UPDATE folder_id = VALUES(folder_id)
            ");
            $stmt->execute([$user, (string)$sid, $folderId]);
            $n++;
        }
        return $n;
    }

    public static function reorderFolders(string $user, array $idsInOrder): int
    {
        self::ensureTables();
        $db = AppConfig::getDB();
        $n = 0;
        foreach ($idsInOrder as $i => $id) {
            $stmt = $db->prepare("UPDATE radio_folders SET sort_order = ? WHERE user = ? AND id = ?");
            $stmt->execute([$i, $user, (int)$id]);
            $n += $stmt->rowCount();
        }
        return $n;
    }

    public static function addCustom(string $user, array $data): int|false
    {
        self::ensureTables();
        $name        = trim((string)($data['name'] ?? ''));
        $originalUrl = trim((string)($data['stream_url'] ?? $data['url'] ?? ''));
        if ($name === '' || $originalUrl === '') return false;
        if (!filter_var($originalUrl, FILTER_VALIDATE_URL)) return false;

        $genres = $data['genres'] ?? '';
        if (is_array($genres)) $genres = implode(',', $genres);

        // Resolve playlists (M3U/PLS) into the actual stream URL + detect codec.
        // Falls back to the original URL if resolution fails or curl is missing.
        $resolved = RadioStreamResolver::resolve($originalUrl);
        $streamUrl  = $resolved['url']       ?? $originalUrl;
        $format     = $resolved['format']    ?? ($data['format'] ?? null);
        $isPlaylist = $resolved['is_playlist'] ?? false;
        if ($format === 'unknown') $format = $data['format'] ?? null;

        $db = AppConfig::getDB();
        $stmt = $db->prepare("
            INSERT INTO radio_custom_stations
                (user, name, stream_url, original_url, logo, homepage, genres, country, language, bitrate, format, is_playlist)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ");
        $stmt->execute([
            $user,
            mb_substr($name, 0, 200),
            $streamUrl,
            $originalUrl,
            $data['logo']     ?? null,
            $data['homepage'] ?? null,
            $genres ?: null,
            $data['country']  ?? null,
            $data['language'] ?? null,
            isset($data['bitrate']) ? (int)$data['bitrate'] : null,
            $format,
            $isPlaylist ? 1 : 0,
        ]);
        return (int)$db->lastInsertId();
    }

    public static function updateCustom(string $user, int $id, array $data): bool
    {
        self::ensureTables();
        $db = AppConfig::getDB();
        $stmt = $db->prepare("SELECT * FROM radio_custom_stations WHERE user = ? AND id = ?");
        $stmt->execute([$user, $id]);
        $row = $stmt->fetch(\PDO::FETCH_ASSOC);
        if (!$row) return false;

        $name = trim((string)($data['name'] ?? $row['name']));
        $originalUrl = trim((string)($data['url'] ?? $data['stream_url'] ?? $row['original_url'] ?? $row['stream_url']));
        if ($name === '' || !filter_var($originalUrl, FILTER_VALIDATE_URL)) return false;

        $genres = $data['genres'] ?? $row['genres'] ?? '';
        if (is_array($genres)) $genres = implode(',', $genres);

        $streamUrl  = $row['stream_url'];
        $format     = $row['format'];
        $isPlaylist = (int)($row['is_playlist'] ?? 0);
        // Re-resolve only if the URL actually changed
        if ($originalUrl !== ($row['original_url'] ?? $row['stream_url'])) {
            $resolved   = RadioStreamResolver::resolve($originalUrl);
            $streamUrl  = $resolved['url']         ?? $originalUrl;
            $format     = $resolved['format']      ?? $format;
            $isPlaylist = !empty($resolved['is_playlist']) ? 1 : 0;
        }

        $stmt = $db->prepare("
            UPDATE radio_custom_stations
            SET name = ?, stream_url = ?, original_url = ?, logo = ?, homepage = ?,
                genres = ?, country = ?, language = ?, bitrate = ?, format = ?, is_playlist = ?
            WHERE user = ? AND id = ?
        ");
        $stmt->execute([
            mb_substr($name, 0, 200),
            $streamUrl,
            $originalUrl,
            array_key_exists('logo', $data)     ? ($data['logo'] ?: null)     : $row['logo'],
            array_key_exists('homepage', $data) ? ($data['homepage'] ?: null) : $row['homepage'],
            $genres ?: null,
            array_key_exists('country',  $data) ? ($data['country']  ?: null) : $row['country'],
            array_key_exists('language', $data) ? ($data['language'] ?: null) : $row['language'],
            array_key_exists('bitrate',  $data) ? (int)$data['bitrate'] : $row['bitrate'],
            $format,
            $isPlaylist,
            $user, $id,
        ]);
        return $stmt->rowCount() > 0;
    }

    public static function getCustom(string $user, int $id): ?array
    {
        self::ensureTables();
        $db = AppConfig::getDB();
        $stmt = $db->prepare("
            SELECT id, name, stream_url, original_url, logo, homepage, genres,
                   country, language, bitrate, format, is_playlist
            FROM radio_custom_stations
            WHERE user = ? AND id = ?
        ");
        $stmt->execute([$user, $id]);
        $row = $stmt->fetch(\PDO::FETCH_ASSOC);
        return $row ?: null;
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

    /**
     * Set a flag on many stations at once. Written as chunked multi-row
     * upserts: épurer un catalogue de 1200 stations d'un coup ne doit pas
     * coûter 1200 allers-retours SQL (idée #96).
     */
    public static function setFlagBulk(string $user, array $stationIds, string $flag, int $value): int
    {
        self::ensureTables();
        if (!in_array($flag, ['is_favorite', 'is_hidden'], true)) return 0;
        $ids = array_values(array_unique(array_filter(array_map('strval', $stationIds), fn($s) => $s !== '')));
        if (!$ids) return 0;
        $db = AppConfig::getDB();
        $n = 0;
        foreach (array_chunk($ids, 200) as $chunk) {
            $values = implode(', ', array_fill(0, count($chunk), '(?, ?, ?)'));
            $stmt = $db->prepare("
                INSERT INTO radio_user_state (user, station_id, $flag) VALUES $values
                ON DUPLICATE KEY UPDATE $flag = VALUES($flag)
            ");
            $params = [];
            foreach ($chunk as $sid) {
                $params[] = $user;
                $params[] = $sid;
                $params[] = (int)$value;
            }
            $stmt->execute($params);
            $n += count($chunk);
        }
        return $n;
    }

    /** Delete several custom stations at once. Returns how many were removed. */
    public static function removeCustomBulk(string $user, array $ids): int
    {
        self::ensureTables();
        $ids = array_values(array_unique(array_map('intval', $ids)));
        $ids = array_values(array_filter($ids, fn($i) => $i > 0));
        if (!$ids) return 0;
        $db = AppConfig::getDB();
        $n = 0;
        foreach (array_chunk($ids, 200) as $chunk) {
            $marks = implode(',', array_fill(0, count($chunk), '?'));
            $stmt = $db->prepare("DELETE FROM radio_custom_stations WHERE user = ? AND id IN ($marks)");
            $stmt->execute(array_merge([$user], $chunk));
            $n += $stmt->rowCount();
            // Drop the state rows tied to those custom stations
            $sids = array_map(fn($i) => 'custom:' . $i, $chunk);
            $stmt = $db->prepare("DELETE FROM radio_user_state WHERE user = ? AND station_id IN ($marks)");
            $stmt->execute(array_merge([$user], $sids));
        }
        return $n;
    }
}
