<?php
/**
 * Gullify - Déduplication de la bibliothèque
 *
 * Un fichier audio ne doit exister qu'une fois en base. Deux scans lancés en
 * même temps sur le même artiste (cas courant : plusieurs téléchargements
 * yt-dlp qui se terminent coup sur coup, chacun déclenchant scan-artist.php)
 * inséraient chacun leur ligne pour le MÊME fichier — d'où des albums dont
 * chaque titre apparaissait deux fois.
 *
 * Cette classe :
 *   1. fusionne les lignes `songs` qui pointent le même fichier (la plus
 *      récente gagne : elle reflète le dernier scan, donc le bon album),
 *      en reportant favoris, playlists, historique et statistiques ;
 *   2. pose l'index d'unicité `uniq_songs_album_path` qui rend le doublon
 *      impossible ensuite (l'INSERT ... ON DUPLICATE KEY UPDATE du Scanner
 *      devient alors réellement actif).
 *
 * L'unicité porte sur (album_id, file_path) et non sur file_path seul : pour
 * un utilisateur SFTP, file_path est relatif à SA racine, donc deux comptes
 * pourraient légitimement stocker « Artiste/Album/01.mp3 ».
 */

require_once __DIR__ . '/AppConfig.php';

class LibraryDedupe {
    public const INDEX_NAME = 'uniq_songs_album_path';

    private PDO $db;

    public function __construct(?PDO $db = null) {
        $this->db = $db ?? AppConfig::getDB();
    }

    /**
     * Vrai si l'index d'unicité est déjà en place (donc plus rien à faire).
     */
    public function indexExists(): bool {
        $stmt = $this->db->prepare(
            "SELECT 1 FROM INFORMATION_SCHEMA.STATISTICS
             WHERE TABLE_SCHEMA = ? AND TABLE_NAME = 'songs' AND INDEX_NAME = ?"
        );
        $stmt->execute([AppConfig::get('mysql.database'), self::INDEX_NAME]);
        return (bool) $stmt->fetchColumn();
    }

    /**
     * Fusionne les doublons puis pose l'index. Idempotent : sans doublon et
     * avec l'index déjà posé, ne fait qu'une poignée de SELECT.
     *
     * @return array{songs:int,albums:int,artists:int,indexed:bool}
     */
    public function run(): array {
        [$songs, $albumIds] = $this->mergeDuplicateSongs();
        [$albums, $artists] = $this->cleanupEmptied($albumIds);
        if ($songs > 0) {
            $this->refreshArtistCounts();
        }

        return [
            'songs'   => $songs,
            'albums'  => $albums,
            'artists' => $artists,
            'indexed' => $this->ensureUniqueIndex(),
        ];
    }

    /**
     * Groupes de lignes `songs` pointant le même fichier (même chemin, quel
     * que soit l'album : d'anciens scans de compilations ont laissé le même
     * fichier rangé sous plusieurs albums).
     *
     * @return array<string,int[]> chemin => ids, du plus ancien au plus récent
     */
    private function findDuplicateGroups(): array {
        $stmt = $this->db->query(
            "SELECT s.id, s.file_path
             FROM songs s
             JOIN (
                 SELECT file_path FROM songs GROUP BY file_path HAVING COUNT(*) > 1
             ) d ON d.file_path = s.file_path
             ORDER BY s.file_path, s.id"
        );

        $groups = [];
        foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
            $groups[$row['file_path']][] = (int) $row['id'];
        }
        return $groups;
    }

    /**
     * Garde une seule ligne par fichier — la plus récente, car c'est celle du
     * dernier scan (bon album, bonnes métadonnées) — et lui rattache tout ce
     * qui pointait les autres.
     *
     * @return array{0:int,1:int[]} lignes supprimées, albums touchés
     */
    private function mergeDuplicateSongs(): array {
        $groups = $this->findDuplicateGroups();
        if (!$groups) return [0, []];

        $deleted  = 0;
        $touched  = [];
        foreach ($groups as $ids) {
            $keep = array_pop($ids); // plus grand id = dernier scan
            if (!$ids) continue;

            $ph = implode(',', array_fill(0, count($ids), '?'));
            $stmt = $this->db->prepare("SELECT DISTINCT album_id FROM songs WHERE id IN ($ph)");
            $stmt->execute($ids);
            foreach ($stmt->fetchAll(PDO::FETCH_COLUMN) as $albumId) {
                $touched[(int) $albumId] = true;
            }

            $this->db->beginTransaction();
            try {
                foreach ($ids as $dup) {
                    $this->reassignReferences($dup, $keep);
                }
                $stmt = $this->db->prepare("DELETE FROM songs WHERE id IN ($ph)");
                $stmt->execute($ids);
                $deleted += $stmt->rowCount();
                $this->db->commit();
            } catch (Throwable $e) {
                $this->db->rollBack();
                throw $e;
            }
        }

        return [$deleted, array_keys($touched)];
    }

    /**
     * Reporte sur [$keep] tout ce qui référençait la ligne [$dup] : favoris,
     * playlists, historique, partages et compteurs d'écoute. Rien ne doit se
     * perdre — c'est la seule raison pour laquelle on ne supprime pas sec.
     */
    private function reassignReferences(int $dup, int $keep): void {
        // Tables à clé unique sur song_id : on déplace ce qui peut l'être,
        // le reste (déjà présent sur $keep) disparaît avec la ligne.
        $this->db->prepare('UPDATE IGNORE favorites SET song_id = ? WHERE song_id = ?')
                 ->execute([$keep, $dup]);
        $this->db->prepare('UPDATE IGNORE playlist_songs SET song_id = ? WHERE song_id = ?')
                 ->execute([$keep, $dup]);

        // Tables sans contrainte d'unicité : tout suit.
        $this->db->prepare('UPDATE play_history SET song_id = ? WHERE song_id = ?')
                 ->execute([$keep, $dup]);
        $this->db->prepare('UPDATE song_shares SET song_id = ? WHERE song_id = ?')
                 ->execute([$keep, $dup]);

        $this->mergeStats($dup, $keep);
    }

    /** Additionne les compteurs d'écoute de [$dup] sur ceux de [$keep]. */
    private function mergeStats(int $dup, int $keep): void {
        $stmt = $this->db->prepare('SELECT * FROM song_stats WHERE song_id = ?');
        $stmt->execute([$dup]);
        $stats = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$stats) return;

        $this->db->prepare('
            INSERT INTO song_stats
                (song_id, play_count, first_played_at, last_played_at, total_play_time, skip_count)
            VALUES (?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
                play_count      = play_count + VALUES(play_count),
                total_play_time = total_play_time + VALUES(total_play_time),
                skip_count      = skip_count + VALUES(skip_count),
                first_played_at = LEAST(
                    COALESCE(first_played_at, VALUES(first_played_at)),
                    COALESCE(VALUES(first_played_at), first_played_at)
                ),
                last_played_at  = GREATEST(
                    COALESCE(last_played_at, VALUES(last_played_at)),
                    COALESCE(VALUES(last_played_at), last_played_at)
                )
        ')->execute([
            $keep,
            (int) ($stats['play_count'] ?? 0),
            $stats['first_played_at'],
            $stats['last_played_at'],
            (int) ($stats['total_play_time'] ?? 0),
            (int) ($stats['skip_count'] ?? 0),
        ]);
        $this->db->prepare('DELETE FROM song_stats WHERE song_id = ?')->execute([$dup]);
    }

    /**
     * Supprime les albums vidés par la fusion (l'ancienne copie d'un fichier
     * pouvait être seule sous un album fantôme) et les artistes qu'ils
     * laissaient sans rien. On ne touche QUE les albums concernés : ailleurs,
     * un album sans piste peut être un scan en cours.
     *
     * @param int[] $albumIds
     * @return array{0:int,1:int} albums supprimés, artistes supprimés
     */
    private function cleanupEmptied(array $albumIds): array {
        if (!$albumIds) return [0, 0];

        $ph = implode(',', array_fill(0, count($albumIds), '?'));
        $stmt = $this->db->prepare("SELECT DISTINCT artist_id FROM albums WHERE id IN ($ph)");
        $stmt->execute($albumIds);
        $artistIds = array_map('intval', $stmt->fetchAll(PDO::FETCH_COLUMN));

        $stmt = $this->db->prepare("
            DELETE al FROM albums al
            LEFT JOIN songs s ON s.album_id = al.id
            WHERE al.id IN ($ph) AND s.id IS NULL
        ");
        $stmt->execute($albumIds);
        $albums = $stmt->rowCount();

        $artists = 0;
        if ($albums > 0 && $artistIds) {
            $ph = implode(',', array_fill(0, count($artistIds), '?'));
            $stmt = $this->db->prepare("
                DELETE ar FROM artists ar
                LEFT JOIN albums al ON al.artist_id = ar.id
                LEFT JOIN songs s ON s.artist_id = ar.id
                WHERE ar.id IN ($ph) AND al.id IS NULL AND s.id IS NULL
            ");
            $stmt->execute($artistIds);
            $artists = $stmt->rowCount();
        }

        return [$albums, $artists];
    }

    /** Recalcule album_count / song_count après une fusion. */
    private function refreshArtistCounts(): void {
        $this->db->exec('
            UPDATE artists a SET
                a.album_count = (SELECT COUNT(*) FROM albums WHERE artist_id = a.id),
                a.song_count  = (
                    SELECT COUNT(*) FROM songs s
                    JOIN albums al ON s.album_id = al.id
                    WHERE al.artist_id = a.id
                )
        ');
    }

    /**
     * Pose l'index d'unicité. Renvoie false (sans lever) si MySQL le refuse :
     * mieux vaut un scan qui marche comme avant qu'un scan qui plante.
     */
    public function ensureUniqueIndex(): bool {
        if ($this->indexExists()) return true;
        try {
            $this->db->exec(
                'ALTER TABLE songs ADD UNIQUE KEY ' . self::INDEX_NAME . ' (album_id, file_path)'
            );
            return true;
        } catch (Throwable $e) {
            error_log('LibraryDedupe: index ' . self::INDEX_NAME . ' non posé — ' . $e->getMessage());
            return false;
        }
    }
}
