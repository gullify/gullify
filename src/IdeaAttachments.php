<?php
/**
 * Gullify — Pièces jointes du carnet d'idées (idée #84)
 *
 * Une idée (table `dev_ideas`) peut porter des fichiers : capture d'écran de
 * ce qui cloche, maquette, log, n'importe quoi. Les octets vivent dans le
 * volume persistant `data/idea_files/<idea_id>/<file_id>.<ext>` (jamais dans
 * la racine web), la ligne en base garde le nom d'origine et le type MIME.
 * Servis par `public/serve_idea_file.php`, exportés vers Claude par
 * `scripts/process-ideas.sh`.
 */

require_once __DIR__ . '/AppConfig.php';

class IdeaAttachments
{
    /** Taille maximale d'une pièce jointe. */
    public const MAX_BYTES = 10 * 1024 * 1024;

    /** Nombre maximal de pièces jointes par idée. */
    public const MAX_PER_IDEA = 20;

    public static function dir(): string
    {
        return AppConfig::getDataPath() . '/idea_files';
    }

    public static function ensureTable(PDO $db): void
    {
        $db->exec("
            CREATE TABLE IF NOT EXISTS dev_idea_files (
                id INT AUTO_INCREMENT PRIMARY KEY,
                idea_id INT NOT NULL,
                user VARCHAR(255) NOT NULL,
                name VARCHAR(255) NOT NULL,
                mime VARCHAR(120) NOT NULL DEFAULT 'application/octet-stream',
                size INT NOT NULL DEFAULT 0,
                stored_path VARCHAR(500) NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                INDEX (idea_id),
                INDEX (user)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ");
    }

    /** Chemin absolu d'une pièce jointe depuis sa ligne en base. */
    public static function path(array $row): string
    {
        return self::dir() . '/' . $row['stored_path'];
    }

    /** Forme JSON envoyée à l'app. */
    public static function toJson(array $row): array
    {
        return [
            'id'   => (int)$row['id'],
            'name' => $row['name'],
            'mime' => $row['mime'],
            'size' => (int)$row['size'],
            'url'  => 'serve_idea_file.php?id=' . (int)$row['id'],
        ];
    }

    /** Pièces jointes de plusieurs idées, indexées par idea_id. */
    public static function listFor(PDO $db, array $ideaIds, string $user): array
    {
        $ids = array_values(array_filter(array_map('intval', $ideaIds)));
        if ($ids === []) return [];
        $in = implode(',', array_fill(0, count($ids), '?'));
        $stmt = $db->prepare(
            "SELECT * FROM dev_idea_files
             WHERE user = ? AND idea_id IN ($in)
             ORDER BY id ASC"
        );
        $stmt->execute(array_merge([$user], $ids));
        $out = [];
        foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
            $out[(int)$row['idea_id']][] = self::toJson($row);
        }
        return $out;
    }

    public static function countFor(PDO $db, int $ideaId, string $user): int
    {
        $stmt = $db->prepare(
            'SELECT COUNT(*) FROM dev_idea_files WHERE idea_id = ? AND user = ?'
        );
        $stmt->execute([$ideaId, $user]);
        return (int)$stmt->fetchColumn();
    }

    public static function get(PDO $db, int $id, string $user): ?array
    {
        $stmt = $db->prepare('SELECT * FROM dev_idea_files WHERE id = ? AND user = ?');
        $stmt->execute([$id, $user]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        return $row ?: null;
    }

    /**
     * Range un fichier téléversé et renvoie sa forme JSON.
     * `$isUpload` distingue un vrai upload PHP (move_uploaded_file) d'un
     * fichier déjà sur disque (tests / imports).
     */
    public static function store(
        PDO $db,
        int $ideaId,
        string $user,
        string $tmpPath,
        string $name,
        string $mime,
        bool $isUpload = true
    ): array {
        $name = self::safeName($name);
        $mime = self::safeMime($mime, $name);
        $size = (int)@filesize($tmpPath);

        $stmt = $db->prepare(
            'INSERT INTO dev_idea_files (idea_id, user, name, mime, size, stored_path)
             VALUES (?, ?, ?, ?, ?, ?)'
        );
        $stmt->execute([$ideaId, $user, $name, $mime, $size, '']);
        $id = (int)$db->lastInsertId();

        $ext      = self::extension($name);
        $relative = $ideaId . '/' . $id . ($ext === '' ? '' : '.' . $ext);
        $dest     = self::dir() . '/' . $relative;

        if (!is_dir(dirname($dest)) && !@mkdir(dirname($dest), 0775, true) && !is_dir(dirname($dest))) {
            $db->prepare('DELETE FROM dev_idea_files WHERE id = ?')->execute([$id]);
            throw new RuntimeException('Impossible de créer le dossier des pièces jointes');
        }

        $moved = $isUpload ? @move_uploaded_file($tmpPath, $dest) : @copy($tmpPath, $dest);
        if (!$moved) {
            $db->prepare('DELETE FROM dev_idea_files WHERE id = ?')->execute([$id]);
            throw new RuntimeException("Impossible d'enregistrer le fichier");
        }
        @chmod($dest, 0644);

        $db->prepare('UPDATE dev_idea_files SET stored_path = ? WHERE id = ?')
           ->execute([$relative, $id]);

        return self::toJson([
            'id' => $id, 'name' => $name, 'mime' => $mime, 'size' => $size,
        ]);
    }

    public static function delete(PDO $db, int $id, string $user): bool
    {
        $row = self::get($db, $id, $user);
        if ($row === null) return false;
        $path = self::path($row);
        if ($row['stored_path'] !== '' && is_file($path)) @unlink($path);
        $db->prepare('DELETE FROM dev_idea_files WHERE id = ? AND user = ?')
           ->execute([$id, $user]);
        return true;
    }

    /** Supprime toutes les pièces jointes d'une idée (idée effacée). */
    public static function deleteForIdea(PDO $db, int $ideaId, string $user): void
    {
        $stmt = $db->prepare('SELECT * FROM dev_idea_files WHERE idea_id = ? AND user = ?');
        $stmt->execute([$ideaId, $user]);
        foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
            $path = self::path($row);
            if ($row['stored_path'] !== '' && is_file($path)) @unlink($path);
        }
        $db->prepare('DELETE FROM dev_idea_files WHERE idea_id = ? AND user = ?')
           ->execute([$ideaId, $user]);
        $dir = self::dir() . '/' . $ideaId;
        if (is_dir($dir)) @rmdir($dir);
    }

    /** Nom d'origine nettoyé (affiché dans l'app, jamais utilisé tel quel sur disque). */
    public static function safeName(string $name): string
    {
        $name = basename(str_replace('\\', '/', trim($name)));
        $name = preg_replace('/[\x00-\x1F\x7F]/u', '', $name) ?? '';
        $name = trim($name);
        if ($name === '' || $name === '.' || $name === '..') $name = 'fichier';
        return mb_substr($name, 0, 200);
    }

    /** Extension sûre pour le nom sur disque ('' si rien d'exploitable). */
    private static function extension(string $name): string
    {
        $ext = strtolower((string)pathinfo($name, PATHINFO_EXTENSION));
        return preg_match('/^[a-z0-9]{1,8}$/', $ext) ? $ext : '';
    }

    /**
     * Type MIME retenu. Les types annoncés par le client ne sont crus que
     * pour les images (le seul cas servi en ligne) ; tout le reste devient
     * un téléchargement générique, pour qu'un .html téléversé ne puisse pas
     * s'exécuter dans le domaine de Gullify.
     */
    private static function safeMime(string $mime, string $name): string
    {
        $mime = strtolower(trim(strtok($mime, ';') ?: ''));
        $images = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'image/gif', 'image/heic'];
        if (in_array($mime, $images, true)) {
            return $mime === 'image/jpg' ? 'image/jpeg' : $mime;
        }
        if ($mime === '' || !preg_match('~^[a-z0-9.+-]+/[a-z0-9.+-]+$~', $mime)) {
            return 'application/octet-stream';
        }
        // Types inoffensifs et utiles à lire tels quels côté serveur.
        $texts = ['text/plain', 'application/json', 'application/pdf', 'text/csv'];
        return in_array($mime, $texts, true) ? $mime : 'application/octet-stream';
    }

    /** true si le fichier peut être affiché en aperçu (image). */
    public static function isImage(string $mime): bool
    {
        return str_starts_with($mime, 'image/');
    }
}
