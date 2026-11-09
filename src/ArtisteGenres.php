<?php
/**
 * Gullify — Les genres (plusieurs) et l'origine d'un artiste, en base.
 *
 *   - `artiste_genres` (artist_id, genre, rang) : jusqu'à trois genres, le
 *     principal au rang 0. `artists.genre` garde le principal, recopié : les
 *     vieux écrans, Subsonic et les jeux le lisent toujours là.
 *   - `artists.origine` : Québec, France… (voir Origine.php).
 *   - `artists.genres_manuel` / `origine_manuelle` : choisis à la main dans
 *     l'app — un scan, même forcé, n'y touche plus.
 *   - `artists.genres_analyse` : quand l'analyse Last.fm (genres + origine) a
 *     tourné pour cet artiste ; un scan ordinaire ne la refait pas.
 *
 * Un artiste supprimé emporte ses genres (clé étrangère en cascade).
 */

require_once __DIR__ . '/GenreTaxonomy.php';
require_once __DIR__ . '/Origine.php';

class ArtisteGenres
{
    /** Crée la table si elle manque (installations d'avant le serveur 1.20.0). */
    public static function assurerTable(PDO $db): void
    {
        static $fait = false;
        if ($fait) return;
        $fait = true;

        $existait = (bool)$db->query("SHOW TABLES LIKE 'artiste_genres'")->fetchColumn();
        if ($existait) return;

        $colonnes = "
                artist_id INT NOT NULL,
                genre VARCHAR(100) NOT NULL,
                rang TINYINT NOT NULL DEFAULT 0,
                PRIMARY KEY (artist_id, genre),
                INDEX idx_artiste_genres_genre (genre)";
        try {
            $db->exec("CREATE TABLE IF NOT EXISTS artiste_genres ($colonnes,
                FOREIGN KEY (artist_id) REFERENCES artists(id) ON DELETE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
        } catch (PDOException $e) {
            // Une vieille base (artists en MyISAM, id d'un autre type) refuse
            // la clé étrangère : la table vient sans, et un artiste supprimé
            // laisse des lignes orphelines, que personne ne lit.
            $db->exec("CREATE TABLE IF NOT EXISTS artiste_genres ($colonnes
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
        }
        // Le genre déjà posé devient le principal : rien ne se perd au passage.
        $db->exec("
            INSERT IGNORE INTO artiste_genres (artist_id, genre, rang)
            SELECT id, genre, 0 FROM artists WHERE genre IS NOT NULL AND genre != ''
        ");
    }

    /**
     * Les genres d'un artiste, nettoyés : sans vide, sans doublon (à la casse
     * et aux accents près), trois au plus, dans l'ordre donné.
     *
     * @param array<mixed> $genres
     * @return array<string>
     */
    public static function nettoyer(array $genres, int $max = 3): array
    {
        $out = [];
        $vus = [];
        foreach ($genres as $g) {
            $g = mb_substr(trim((string)$g), 0, 100);
            if ($g === '') continue;
            $cle = GenreTaxonomy::normalize($g);
            if (isset($vus[$cle])) continue;
            $vus[$cle] = true;
            $out[] = $g;
            if (count($out) >= $max) break;
        }
        return $out;
    }

    /**
     * Pose les genres d'un artiste (le premier = principal) et les recopie
     * comme avant : `artists.genre`, et `albums.genre` — tous les albums si
     * $tousLesAlbums (choix à la main), sinon ceux qui n'en ont pas (scan).
     *
     * @param array<string> $genres déjà nettoyés ; vide = plus aucun genre
     */
    public static function poser(PDO $db, int $artistId, array $genres, bool $tousLesAlbums): void
    {
        self::assurerTable($db);
        $principal = $genres[0] ?? null;

        $db->prepare('DELETE FROM artiste_genres WHERE artist_id = ?')->execute([$artistId]);
        $ins = $db->prepare('INSERT IGNORE INTO artiste_genres (artist_id, genre, rang) VALUES (?, ?, ?)');
        foreach ($genres as $rang => $g) $ins->execute([$artistId, $g, $rang]);

        $db->prepare('UPDATE artists SET genre = ? WHERE id = ?')->execute([$principal, $artistId]);
        if ($tousLesAlbums) {
            $db->prepare('UPDATE albums SET genre = ? WHERE artist_id = ?')->execute([$principal, $artistId]);
        } elseif ($principal !== null) {
            $db->prepare("UPDATE albums SET genre = ? WHERE artist_id = ? AND (genre IS NULL OR genre = '')")
               ->execute([$principal, $artistId]);
        }
    }

    /**
     * Les genres et l'origine de plusieurs artistes d'un coup.
     *
     * @param array<int> $ids
     * @return array<int, array{genres: array<string>, origine: string|null}>
     */
    public static function lire(PDO $db, array $ids): array
    {
        $ids = array_values(array_unique(array_filter(array_map('intval', $ids))));
        if (!$ids) return [];
        self::assurerTable($db);

        $out = [];
        foreach (array_chunk($ids, 500) as $lot) {
            $in = implode(',', array_fill(0, count($lot), '?'));
            $st = $db->prepare("SELECT id, genre, origine FROM artists WHERE id IN ($in)");
            $st->execute($lot);
            foreach ($st->fetchAll(PDO::FETCH_ASSOC) as $r) {
                $out[(int)$r['id']] = ['genres' => [], 'origine' => $r['origine'] ?: null,
                                       '_principal' => $r['genre']];
            }
            $st = $db->prepare("SELECT artist_id, genre FROM artiste_genres WHERE artist_id IN ($in) ORDER BY artist_id, rang");
            $st->execute($lot);
            foreach ($st->fetchAll(PDO::FETCH_ASSOC) as $r) {
                $out[(int)$r['artist_id']]['genres'][] = $r['genre'];
            }
        }
        // Un artiste rangé par un vieux client n'a que `artists.genre`.
        foreach ($out as $id => $v) {
            if (!$v['genres'] && !empty($v['_principal'])) $out[$id]['genres'] = [$v['_principal']];
            unset($out[$id]['_principal']);
        }
        return $out;
    }

    /**
     * Fragment SQL : l'artiste `$a` porte le genre (paramètre `?`), en
     * principal comme en secondaire.
     */
    public static function sqlPorte(string $a = 'a'): string
    {
        return "EXISTS (SELECT 1 FROM artiste_genres agx WHERE agx.artist_id = $a.id AND agx.genre = ?)";
    }
}
