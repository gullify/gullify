<?php
/**
 * Gullify — partage d'une chanson par lien éphémère.
 *
 * Le principe est celui des parties multijoueur : on tire un lien depuis
 * l'app, on l'envoie par SMS, et la personne l'ouvre dans son navigateur sur
 * https://<domaine>/s/<JETON>. Ici il n'y a rien à jouer — juste une chanson
 * à écouter — et le lien meurt tout seul au bout de TTL_HOURS.
 *
 * Ce qui sort du serveur est volontairement étroit : un lien ne donne accès
 * qu'à UNE chanson, jamais à la bibliothèque, jamais au chemin du fichier, et
 * jamais après son échéance. Le jeton est tiré au hasard sur 18 caractères —
 * bien assez pour qu'on ne tombe pas dessus par essais.
 *
 * Les métadonnées affichées (titre, interprète, album) sont recopiées à la
 * création : le lien reste lisible même si la fiche bouge derrière. Le
 * fichier, lui, est retrouvé au moment de l'écoute — un morceau supprimé de
 * la bibliothèque n'est donc plus écoutable, ce qui est exactement ce qu'on
 * veut.
 */

require_once __DIR__ . '/AppConfig.php';
require_once __DIR__ . '/TrackArtist.php';

class SongShare
{
    /** Durée de vie d'un lien. */
    public const TTL_HOURS = 24;

    /** Liens vivants qu'une personne peut avoir en même temps. */
    private const MAX_ACTIVE = 50;

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
    }

    // ──────────────────────────────────────────────────────── cycle de vie ──

    /**
     * Ouvre un lien vers `$songId` pour les prochaines TTL_HOURS.
     *
     * @throws RuntimeException 'song_not_found' si le morceau n'est pas dans
     *         la bibliothèque de cette personne, 'too_many_shares' si elle en
     *         a déjà beaucoup en cours.
     */
    public static function create(string $user, int $songId): array
    {
        self::ensureTables();
        self::purgeExpired();

        $song = self::songRow($user, $songId);
        if (!$song) throw new RuntimeException('song_not_found');

        $db = AppConfig::getDB();
        $stmt = $db->prepare(
            'SELECT COUNT(*) FROM song_shares WHERE owner_user = ? AND expires_at > NOW()'
        );
        $stmt->execute([$user]);
        if ((int)$stmt->fetchColumn() >= self::MAX_ACTIVE) {
            throw new RuntimeException('too_many_shares');
        }

        $token = self::freshToken($db);
        $stmt = $db->prepare(
            'INSERT INTO song_shares
                (token, owner_user, song_id, title, artist, album, album_id, duration, expires_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL ' . self::TTL_HOURS . ' HOUR))'
        );
        $stmt->execute([
            $token,
            $user,
            (int)$song['id'],
            (string)$song['title'],
            (string)($song['artist_name'] ?? ''),
            (string)($song['album_name'] ?? ''),
            (int)$song['album_id'],
            (int)$song['duration'],
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

    /** Échus : la fiche part, et l'éventuel mp3 préparé avec elle. */
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

    // ─────────────────────────────────────────────────────────── morceau ──

    /**
     * Le morceau visé, relu dans la bibliothèque de son propriétaire.
     * Renvoie null s'il a disparu depuis le partage.
     */
    public static function track(array $share): ?array
    {
        return self::songRow((string)$share['owner_user'], (int)$share['song_id']);
    }

    private static function songRow(string $user, int $songId): ?array
    {
        $sql = "SELECT s.id, s.title, s.duration, s.file_path, s.album_id,
                       al.name AS album_name,
                       " . TRACK_ARTIST_NAME . " AS artist_name
                FROM songs s
                JOIN albums al ON s.album_id = al.id
                JOIN artists a ON al.artist_id = a.id
                " . TRACK_ARTIST_JOIN . "
                WHERE s.id = ? AND a.user = ?";
        $stmt = AppConfig::getDB()->prepare($sql);
        $stmt->execute([$songId, $user]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        return $row ?: null;
    }

    // ───────────────────────────────────────────────────────────── cache ──

    /** Dossier des mp3 préparés pour les partages. */
    public static function cacheDir(): string
    {
        $dir = AppConfig::getDataPath() . '/cache/share';
        if (!is_dir($dir)) @mkdir($dir, 0775, true);
        return $dir;
    }

    /** Le mp3 préparé pour ce lien (créé à la première écoute si besoin). */
    public static function cacheFile(int $id): string
    {
        return self::cacheDir() . '/s' . $id . '.mp3';
    }

    private static function dropCache(int $id): void
    {
        @unlink(self::cacheFile($id));
        @unlink(self::cacheFile($id) . '.lock');
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

    /** Millisecondes restantes avant échéance (0 si c'est fini). */
    public static function remainingMs(array $share): int
    {
        $end = strtotime((string)$share['expires_at']) ?: 0;
        return max(0, ($end - time()) * 1000);
    }

    /**
     * Ce qu'on montre de ce lien : jamais le chemin du fichier, jamais
     * l'identité de son auteur.
     */
    public static function publicView(array $share): array
    {
        return [
            'token'       => (string)$share['token'],
            'songId'      => (int)$share['song_id'],
            'title'       => (string)$share['title'],
            'artist'      => (string)$share['artist'],
            'album'       => (string)$share['album'],
            'artworkUrl'  => self::artwork($share['album_id'] === null ? null : (int)$share['album_id']),
            'duration'    => (int)$share['duration'],
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
