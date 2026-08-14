<?php
/**
 * Gullify — partage par lien éphémère d'une chanson, d'un album ou d'un
 * artiste.
 *
 * Le principe est celui des parties multijoueur : on tire un lien depuis
 * l'app, on l'envoie par SMS, et la personne l'ouvre dans son navigateur sur
 * https://<domaine>/s/<JETON>. Ici il n'y a rien à jouer — juste de la musique
 * à écouter — et le lien meurt tout seul au bout de TTL_HOURS.
 *
 * Ce qui sort du serveur est volontairement étroit : un lien ne donne accès
 * qu'à CE qui a été partagé — une chanson, les titres d'un album, ceux d'un
 * artiste — jamais à la bibliothèque, jamais au chemin des fichiers, et jamais
 * après son échéance. Le jeton est tiré au hasard sur 18 caractères — bien
 * assez pour qu'on ne tombe pas dessus par essais.
 *
 * Les métadonnées affichées (titre, interprète, album) sont recopiées à la
 * création : le lien reste lisible même si la fiche bouge derrière. Les
 * fichiers, eux, sont retrouvés au moment de l'écoute — un morceau supprimé de
 * la bibliothèque n'est donc plus écoutable, ce qui est exactement ce qu'on
 * veut. C'est aussi ce qui borne le partage : la liste des titres est rejouée
 * à chaque requête, si bien qu'un album partagé ne s'ouvre jamais sur autre
 * chose que l'album partagé.
 */

require_once __DIR__ . '/AppConfig.php';
require_once __DIR__ . '/TrackArtist.php';

class SongShare
{
    /** Durée de vie d'un lien. */
    public const TTL_HOURS = 24;

    /** Liens vivants qu'une personne peut avoir en même temps. */
    private const MAX_ACTIVE = 50;

    /** Ce qu'on sait partager. */
    public const KINDS = ['song', 'album', 'artist'];

    /**
     * Titres qu'un lien peut porter au plus. Un artiste à la discographie
     * fleuve ferait sinon une page interminable — et un partage qui ne
     * ressemble plus à un partage.
     */
    private const MAX_TRACKS = 300;

    // ─────────────────────────────────────────────────────────── schéma ──

    /** Création de la table — idempotent, une fois par requête. */
    public static function ensureTables(): void
    {
        static $done = false;
        if ($done) return;
        $done = true;
        try {
            AppConfig::getDB()->exec("
                CREATE TABLE IF NOT EXISTS song_shares (
                    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    token VARCHAR(32) NOT NULL,
                    owner_user VARCHAR(100) NOT NULL,
                    song_id INT UNSIGNED NOT NULL,
                    title VARCHAR(255) NOT NULL,
                    artist VARCHAR(255) NOT NULL DEFAULT '',
                    album VARCHAR(255) NOT NULL DEFAULT '',
                    album_id INT UNSIGNED NULL,
                    duration INT NOT NULL DEFAULT 0,
                    plays INT NOT NULL DEFAULT 0,
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    expires_at DATETIME NOT NULL,
                    last_played_at DATETIME NULL,
                    UNIQUE KEY uniq_share_token (token),
                    INDEX idx_share_owner (owner_user, expires_at),
                    INDEX idx_share_expires (expires_at)
                ) DEFAULT CHARSET=utf8mb4
            ");
        } catch (\Throwable $e) {
            error_log('SongShare::ensureTables failed: ' . $e->getMessage());
        }
        // Colonnes ajoutées après coup (idée #89 : partager aussi un album ou
        // un artiste). Les liens d'avant sont des chansons : `kind` vaut
        // 'song' par défaut et `target_id` est recopié depuis `song_id`.
        $added = false;
        foreach ([
            "ADD COLUMN kind VARCHAR(8) NOT NULL DEFAULT 'song' AFTER owner_user",
            "ADD COLUMN target_id INT UNSIGNED NOT NULL DEFAULT 0 AFTER kind",
            "ADD COLUMN artist_id INT UNSIGNED NULL AFTER album_id",
            "ADD COLUMN track_count INT NOT NULL DEFAULT 1 AFTER duration",
        ] as $alter) {
            try {
                AppConfig::getDB()->exec('ALTER TABLE song_shares ' . $alter);
                $added = true;
            } catch (\Throwable $e) {
                // Déjà là : rien à faire.
            }
        }
        if ($added) {
            try {
                AppConfig::getDB()->exec(
                    'UPDATE song_shares SET target_id = song_id WHERE target_id = 0'
                );
            } catch (\Throwable $e) {
                error_log('SongShare migration failed: ' . $e->getMessage());
            }
        }
    }

    // ──────────────────────────────────────────────────────── cycle de vie ──

    /**
     * Ouvre un lien vers `$targetId` pour les prochaines TTL_HOURS.
     *
     * `$kind` dit ce qu'on partage : une chanson, un album, un artiste. Ce qui
     * est écoutable derrière le lien est arrêté ici — le reste de la
     * bibliothèque n'en fait jamais partie.
     *
     * @throws RuntimeException 'invalid_kind' si le genre est inconnu,
     *         'target_not_found' si la cible n'est pas dans la bibliothèque de
     *         cette personne (ou n'a aucun titre à écouter),
     *         'too_many_shares' si elle a déjà beaucoup de liens en cours.
     */
    public static function create(string $user, string $kind, int $targetId): array
    {
        if (!in_array($kind, self::KINDS, true)) {
            throw new RuntimeException('invalid_kind');
        }
        self::ensureTables();
        self::purgeExpired();

        $card = self::targetCard($user, $kind, $targetId);
        if (!$card) throw new RuntimeException('target_not_found');

        $tracks = self::rows($user, $kind, $targetId);
        if (!$tracks) throw new RuntimeException('target_not_found');

        $db = AppConfig::getDB();
        $stmt = $db->prepare(
            'SELECT COUNT(*) FROM song_shares WHERE owner_user = ? AND expires_at > NOW()'
        );
        $stmt->execute([$user]);
        if ((int)$stmt->fetchColumn() >= self::MAX_ACTIVE) {
            throw new RuntimeException('too_many_shares');
        }

        $duration = 0;
        foreach ($tracks as $t) $duration += (int)$t['duration'];

        $token = self::freshToken($db);
        $stmt = $db->prepare(
            'INSERT INTO song_shares
                (token, owner_user, kind, target_id, song_id, title, artist, album,
                 album_id, artist_id, duration, track_count, expires_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                     DATE_ADD(NOW(), INTERVAL ' . self::TTL_HOURS . ' HOUR))'
        );
        $stmt->execute([
            $token,
            $user,
            $kind,
            $targetId,
            // Historique : la colonne d'origine ne parlait que de chansons.
            $kind === 'song' ? $targetId : 0,
            (string)$card['title'],
            (string)$card['artist'],
            (string)$card['album'],
            $card['album_id'],
            $card['artist_id'],
            $duration,
            count($tracks),
        ]);

        return self::byToken($token) ?? [];
    }

    /** Un jeton d'URL, tiré au hasard et unique. */
    private static function freshToken(PDO $db): string
    {
        for ($try = 0; $try < 20; $try++) {
            $token = substr(bin2hex(random_bytes(12)), 0, 18);
            $stmt = $db->prepare('SELECT 1 FROM song_shares WHERE token = ?');
            $stmt->execute([$token]);
            if (!$stmt->fetchColumn()) return $token;
        }
        return bin2hex(random_bytes(12));
    }

    /** Le lien s'il est encore valable, sinon null (échu = inexistant). */
    public static function byToken(string $token): ?array
    {
        if (!self::validToken($token)) return null;
        self::ensureTables();
        try {
            $stmt = AppConfig::getDB()->prepare(
                'SELECT * FROM song_shares WHERE token = ? AND expires_at > NOW()'
            );
            $stmt->execute([$token]);
            $row = $stmt->fetch(PDO::FETCH_ASSOC);
            return $row ?: null;
        } catch (\Throwable $e) {
            error_log('SongShare::byToken failed: ' . $e->getMessage());
            return null;
        }
    }

    /** Forme acceptable d'un jeton — filtre avant toute requête. */
    public static function validToken(string $token): bool
    {
        return (bool)preg_match('/^[a-f0-9]{12,32}$/i', $token);
    }

    /** Les liens encore vivants d'une personne, du plus récent au plus vieux. */
    public static function listFor(string $user): array
    {
        self::ensureTables();
        self::purgeExpired();
        $stmt = AppConfig::getDB()->prepare(
            'SELECT * FROM song_shares WHERE owner_user = ? AND expires_at > NOW()
             ORDER BY id DESC LIMIT 100'
        );
        $stmt->execute([$user]);
        return $stmt->fetchAll(PDO::FETCH_ASSOC) ?: [];
    }

    /** Coupe un lien avant l'heure. Seul son auteur peut le faire. */
    public static function revoke(string $user, string $token): bool
    {
        if (!self::validToken($token)) return false;
        self::ensureTables();
        $share = null;
        $stmt = AppConfig::getDB()->prepare(
            'SELECT * FROM song_shares WHERE token = ? AND owner_user = ?'
        );
        $stmt->execute([$token, $user]);
        $share = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$share) return false;

        self::dropCache((int)$share['id']);
        $del = AppConfig::getDB()->prepare('DELETE FROM song_shares WHERE id = ?');
        $del->execute([(int)$share['id']]);
        return true;
    }

    /** Échus : la fiche part, et les éventuels mp3 préparés avec elle. */
    public static function purgeExpired(): void
    {
        try {
            $db = AppConfig::getDB();
            $stmt = $db->query('SELECT id FROM song_shares WHERE expires_at <= NOW()');
            $ids = $stmt ? $stmt->fetchAll(PDO::FETCH_COLUMN) : [];
            foreach ($ids as $id) self::dropCache((int)$id);
            if ($ids) {
                $db->exec('DELETE FROM song_shares WHERE expires_at <= NOW()');
            }
        } catch (\Throwable $e) {
            error_log('SongShare::purgeExpired failed: ' . $e->getMessage());
        }
    }

    /** Une écoute de plus (comptée à l'ouverture du flux, pas à chaque octet). */
    public static function countPlay(int $id): void
    {
        try {
            AppConfig::getDB()
                ->prepare('UPDATE song_shares SET plays = plays + 1, last_played_at = NOW() WHERE id = ?')
                ->execute([$id]);
        } catch (\Throwable $e) {
            error_log('SongShare::countPlay failed: ' . $e->getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────── morceaux ──

    /** Le genre de ce lien, y compris pour les fiches d'avant l'idée #89. */
    public static function kind(array $share): string
    {
        $kind = (string)($share['kind'] ?? 'song');
        return in_array($kind, self::KINDS, true) ? $kind : 'song';
    }

    /** L'objet visé : la chanson, l'album ou l'artiste. */
    public static function targetId(array $share): int
    {
        $target = (int)($share['target_id'] ?? 0);
        return $target > 0 ? $target : (int)$share['song_id'];
    }

    /**
     * Les titres écoutables derrière ce lien, relus dans la bibliothèque de
     * son propriétaire — donc vides pour ce qui a été supprimé depuis.
     */
    public static function tracks(array $share): array
    {
        return self::rows(
            (string)$share['owner_user'],
            self::kind($share),
            self::targetId($share)
        );
    }

    /**
     * Un titre précis de ce lien, ou null s'il n'en fait pas partie. C'est le
     * garde-fou du flux : le jeton n'ouvre que ce qui a été partagé.
     */
    public static function track(array $share, ?int $songId = null): ?array
    {
        $tracks = self::tracks($share);
        if ($songId === null) return $tracks[0] ?? null;
        foreach ($tracks as $t) {
            if ((int)$t['id'] === $songId) return $t;
        }
        return null;
    }

    /** Les titres d'une cible, dans l'ordre où on les écoute. */
    private static function rows(string $user, string $kind, int $targetId): array
    {
        [$where, $order] = match ($kind) {
            'album'  => ['s.album_id = ?', 's.track_number ASC, s.title ASC'],
            'artist' => [
                'al.artist_id = ?',
                'al.year IS NULL, al.year DESC, al.name ASC, s.track_number ASC, s.title ASC',
            ],
            default  => ['s.id = ?', 's.id ASC'],
        };
        $sql = "SELECT s.id, s.title, s.duration, s.file_path, s.track_number,
                       s.album_id, al.name AS album_name, al.year,
                       " . TRACK_ARTIST_NAME . " AS artist_name
                FROM songs s
                JOIN albums al ON s.album_id = al.id
                JOIN artists a ON al.artist_id = a.id
                " . TRACK_ARTIST_JOIN . "
                WHERE $where AND a.user = ?
                ORDER BY $order
                LIMIT " . self::MAX_TRACKS;
        try {
            $stmt = AppConfig::getDB()->prepare($sql);
            $stmt->execute([$targetId, $user]);
            return $stmt->fetchAll(PDO::FETCH_ASSOC) ?: [];
        } catch (\Throwable $e) {
            error_log('SongShare::rows failed: ' . $e->getMessage());
            return [];
        }
    }

    /**
     * La carte de visite recopiée à la création : ce qu'on affichera du lien
     * même si la fiche bouge derrière. Null si la cible n'appartient pas à
     * cette personne.
     */
    private static function targetCard(string $user, string $kind, int $targetId): ?array
    {
        $db = AppConfig::getDB();
        if ($kind === 'song') {
            $row = self::rows($user, 'song', $targetId)[0] ?? null;
            if (!$row) return null;
            return [
                'title'     => (string)$row['title'],
                'artist'    => (string)($row['artist_name'] ?? ''),
                'album'     => (string)($row['album_name'] ?? ''),
                'album_id'  => $row['album_id'] === null ? null : (int)$row['album_id'],
                'artist_id' => null,
            ];
        }
        if ($kind === 'album') {
            $stmt = $db->prepare(
                'SELECT al.id, al.name, al.artist_id, a.name AS artist_name
                 FROM albums al JOIN artists a ON al.artist_id = a.id
                 WHERE al.id = ? AND a.user = ?'
            );
            $stmt->execute([$targetId, $user]);
            $row = $stmt->fetch(PDO::FETCH_ASSOC);
            if (!$row) return null;
            return [
                'title'     => (string)$row['name'],
                'artist'    => (string)$row['artist_name'],
                'album'     => '',
                'album_id'  => (int)$row['id'],
                'artist_id' => (int)$row['artist_id'],
            ];
        }
        $stmt = $db->prepare('SELECT id, name FROM artists WHERE id = ? AND user = ?');
        $stmt->execute([$targetId, $user]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$row) return null;
        return [
            'title'     => (string)$row['name'],
            'artist'    => '',
            'album'     => '',
            'album_id'  => null,
            'artist_id' => (int)$row['id'],
        ];
    }

    // ───────────────────────────────────────────────────────────── cache ──

    /** Dossier des mp3 préparés pour les partages. */
    public static function cacheDir(): string
    {
        $dir = AppConfig::getDataPath() . '/cache/share';
        if (!is_dir($dir)) @mkdir($dir, 0775, true);
        return $dir;
    }

    /** Le mp3 préparé d'un titre de ce lien (créé à la première écoute). */
    public static function cacheFile(int $id, int $songId): string
    {
        return self::cacheDir() . '/s' . $id . '_' . $songId . '.mp3';
    }

    /** Tout ce qui a été préparé pour ce lien s'en va avec lui. */
    private static function dropCache(int $id): void
    {
        // Le motif couvre les mp3 par titre comme le fichier unique d'avant
        // l'idée #89 (`s<id>.mp3`), et leurs verrous.
        foreach (glob(self::cacheDir() . '/s' . $id . '[._]*') ?: [] as $file) {
            @unlink($file);
        }
    }

    // ──────────────────────────────────────────────────────────── vitrine ──

    /** URL d'image, servie telle quelle par la page publique comme par l'app. */
    public static function artwork(?int $albumId): string
    {
        if (!$albumId) return '';
        $file = AppConfig::getDataPath() . '/cache/artwork/album_' . $albumId . '.jpg';
        $v = @filemtime($file) ?: 0;
        return 'serve_image.php?album_id=' . $albumId . ($v ? '&v=' . $v : '');
    }

    /**
     * L'image du lien : la pochette pour une chanson ou un album, le portrait
     * pour un artiste.
     */
    public static function shareArtwork(array $share): string
    {
        if (self::kind($share) === 'artist') {
            $artistId = (int)($share['artist_id'] ?? 0);
            return $artistId > 0 ? 'serve_image.php?artist_id=' . $artistId : '';
        }
        return self::artwork($share['album_id'] === null ? null : (int)$share['album_id']);
    }

    /** Millisecondes restantes avant échéance (0 si c'est fini). */
    public static function remainingMs(array $share): int
    {
        $end = strtotime((string)$share['expires_at']) ?: 0;
        return max(0, ($end - time()) * 1000);
    }

    /**
     * Ce qu'on montre de ce lien : jamais le chemin des fichiers, jamais
     * l'identité de son auteur.
     */
    public static function publicView(array $share): array
    {
        return [
            'token'       => (string)$share['token'],
            'kind'        => self::kind($share),
            'targetId'    => self::targetId($share),
            // Compatibilité : les liens de chansons annonçaient `songId`.
            'songId'      => (int)$share['song_id'],
            'title'       => (string)$share['title'],
            'artist'      => (string)$share['artist'],
            'album'       => (string)$share['album'],
            'artworkUrl'  => self::shareArtwork($share),
            'duration'    => (int)$share['duration'],
            'trackCount'  => (int)($share['track_count'] ?? 1),
            'plays'       => (int)$share['plays'],
            'expiresAt'   => (string)$share['expires_at'],
            'remainingMs' => self::remainingMs($share),
        ];
    }

    /** Adresse publique du lien, telle qu'on l'envoie par SMS. */
    public static function url(string $base, string $token): string
    {
        return rtrim($base, '/') . '/s/' . $token;
    }
}
