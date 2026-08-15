<?php
/**
 * Gullify — Transférer un album en corrigeant son artiste ou son titre
 * (idée #94).
 *
 * Le cas courant : un album rangé sous « Katch 22 » alors que c'est « Catch 22 »
 * — l'artiste existe déjà, avec ses autres albums, sa photo et ses favoris.
 * Corriger le nom depuis la fiche de l'album le fait donc REJOINDRE l'artiste
 * en place au lieu d'en créer un deuxième ; s'il s'y trouve déjà un album du
 * même titre, les deux n'en font plus qu'un ; et l'artiste laissé vide s'en va.
 *
 * Deux écritures, pas une :
 *   - la base, que l'app relit tout de suite ;
 *   - les tags des fichiers, TPE2 (« band ») en tête puisque c'est LUI qui
 *     range l'album au scan. Sans ça, le premier fichier retouché ferait
 *     revenir l'erreur au scan suivant.
 * La réécriture recopie le tag existant au complet (pochette incluse) : getID3
 * remplace le tag entier, n'écrire que l'artiste effacerait tout le reste.
 *
 * Les fichiers ne sont PAS déplacés sur le disque. Une fois les tags justes le
 * nom du dossier ne décide plus de rien, et un déplacement à moitié fait
 * couperait la lecture.
 */
require_once __DIR__ . '/AppConfig.php';
require_once __DIR__ . '/AlbumCover.php';
require_once __DIR__ . '/ArtistImage.php';
require_once __DIR__ . '/Storage/StorageFactory.php';

class AlbumMove
{
    /** Longueur des colonnes `artists.name` et `albums.name`. */
    public const MAX_NAME = 255;

    /**
     * Les tags recopiés tels quels d'un fichier à sa version réécrite. Liste
     * fermée : les clés que getID3 rend à la lecture ne se réécrivent pas
     * toutes au même endroit (« text » = TXXX, traité à part), et une clé
     * inconnue partirait dans le mauvais cadre.
     */
    private const KEEP_TAGS = [
        'title', 'artist', 'album', 'band', 'year', 'genre', 'track_number',
        'part_of_a_set', 'part_of_a_compilation', 'comment', 'composer',
        'lyricist', 'publisher', 'encoded_by', 'encoder_settings',
        'original_artist', 'original_album', 'copyright_message', 'bpm',
        'isrc', 'language', 'conductor', 'remixer', 'subtitle', 'media_type',
        'initial_key', 'content_group_description', 'unsynchronised_lyric',
        'album_artist_sort_order', 'album_sort_order', 'performer_sort_order',
        'title_sort_order',
    ];

    /**
     * Corrige l'artiste et/ou le titre d'un album, et le transfère.
     *
     * Un nom vide (ou absent) veut dire « ne change pas celui-là ».
     *
     * @throws InvalidArgumentException nom trop long
     * @throws RuntimeException         album inconnu, ou d'un autre utilisateur
     *
     * @return array{album_id:int,artist_id:int,artist:string,album:string,
     *               changed:bool,moved:bool,renamed:bool,merged:bool,
     *               removed_artist:?string,songs:int,tags_written:int,
     *               tags_failed:int}
     */
    public static function apply(
        PDO $db,
        string $user,
        int $albumId,
        ?string $artist,
        ?string $album
    ): array {
        $row = self::load($db, $albumId, $user);

        $oldArtist   = (string)$row['artist_name'];
        $oldArtistId = (int)$row['artist_id'];
        $newArtist   = self::clean($artist) ?? $oldArtist;
        $newAlbum    = self::clean($album)  ?? (string)$row['name'];

        if (mb_strlen($newArtist) > self::MAX_NAME || mb_strlen($newAlbum) > self::MAX_NAME) {
            throw new InvalidArgumentException(
                'Nom trop long (' . self::MAX_NAME . ' caractères au plus).'
            );
        }

        // Comparaison stricte : corriger la seule casse (« katch22 » →
        // « Katch22 ») est un changement comme un autre.
        $artistChanged = $newArtist !== $oldArtist;
        $albumChanged  = $newAlbum  !== (string)$row['name'];

        $result = [
            'album_id'       => $albumId,
            'artist_id'      => $oldArtistId,
            'artist'         => $oldArtist,
            'album'          => (string)$row['name'],
            'changed'        => false,
            'moved'          => false,
            'renamed'        => false,
            'merged'         => false,
            'removed_artist' => null,
            'songs'          => 0,
            'tags_written'   => 0,
            'tags_failed'    => 0,
        ];
        if (!$artistChanged && !$albumChanged) {
            return $result;
        }

        // Les titres à retagger, relevés AVANT la fusion : après, ils se
        // mélangent à ceux de l'album d'accueil, qui n'ont rien à changer.
        $stmt = $db->prepare('SELECT id, file_path FROM songs WHERE album_id = ?');
        $stmt->execute([$albumId]);
        $songs = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $targetArtistId = $oldArtistId;
        $mergedFrom     = null;
        $removedArtist  = null;

        $db->beginTransaction();
        try {
            if ($artistChanged) {
                $targetArtistId = self::artistId($db, $user, $newArtist);
                if ($targetArtistId === $oldArtistId) {
                    // Le même artiste, autrement orthographié (la base ignore
                    // casse et accents) : c'est sa fiche qu'on corrige.
                    $db->prepare('UPDATE artists SET name = ? WHERE id = ?')
                       ->execute([$newArtist, $oldArtistId]);
                } else {
                    $db->prepare('UPDATE albums SET artist_id = ? WHERE id = ?')
                       ->execute([$targetArtistId, $albumId]);
                    // Les pistes qui portaient l'ancien artiste en propre
                    // (compilations) le suivent.
                    $db->prepare(
                        'UPDATE songs SET artist_id = ? WHERE album_id = ? AND artist_id = ?'
                    )->execute([$targetArtistId, $albumId, $oldArtistId]);
                }
            }

            if ($albumChanged) {
                $db->prepare('UPDATE albums SET name = ? WHERE id = ?')
                   ->execute([$newAlbum, $albumId]);
            }

            // Un album du même nom déjà chez cet artiste : les deux n'en font
            // plus qu'un, sinon la correction laisserait un doublon derrière.
            $twin = $db->prepare(
                'SELECT id FROM albums WHERE artist_id = ? AND name = ? AND id <> ?
                 ORDER BY id ASC LIMIT 1'
            );
            $twin->execute([$targetArtistId, $newAlbum, $albumId]);
            $keepId = (int)($twin->fetchColumn() ?: 0);
            if ($keepId) {
                self::mergeInto($db, $albumId, $keepId);
                $mergedFrom = $albumId;
                $albumId    = $keepId;
            }

            // L'ancien artiste n'a plus rien : il ne doit pas rester en
            // rayon (le scan l'effacerait de toute façon).
            if ($artistChanged && $targetArtistId !== $oldArtistId
                && !self::hasAlbums($db, $oldArtistId)) {
                $db->prepare('UPDATE IGNORE favorite_artists SET artist_id = ? WHERE artist_id = ?')
                   ->execute([$targetArtistId, $oldArtistId]);
                $db->prepare('DELETE FROM artists WHERE id = ?')->execute([$oldArtistId]);
                $removedArtist = $oldArtist;
            }

            self::refreshCounts($db, [$oldArtistId, $targetArtistId]);
            $db->commit();
        } catch (Throwable $e) {
            $db->rollBack();
            throw $e;
        }

        // Après la base seulement : le cache d'images n'est pas transactionnel.
        if ($mergedFrom !== null) {
            AlbumCover::forget($mergedFrom);
        }
        if ($removedArtist !== null) {
            ArtistImage::forget($oldArtistId);
        }

        [$written, $failed] = self::retagSongs(
            $user,
            $songs,
            $albumChanged ? $newAlbum : null,
            $artistChanged ? $newArtist : null,
            $oldArtist
        );

        return [
            'album_id'       => $albumId,
            'artist_id'      => $targetArtistId,
            'artist'         => $newArtist,
            'album'          => $newAlbum,
            'changed'        => true,
            'moved'          => $artistChanged && $targetArtistId !== $oldArtistId,
            'renamed'        => $albumChanged,
            'merged'         => $mergedFrom !== null,
            'removed_artist' => $removedArtist,
            'songs'          => count($songs),
            'tags_written'   => $written,
            'tags_failed'    => $failed,
        ];
    }

    /**
     * L'album, à condition qu'il appartienne bien à cet utilisateur.
     *
     * @return array{id:int,name:string,artist_id:int,artist_name:string}
     */
    private static function load(PDO $db, int $albumId, string $user): array
    {
        $stmt = $db->prepare('
            SELECT al.id, al.name, al.artist_id, ar.name AS artist_name
            FROM albums al
            JOIN artists ar ON al.artist_id = ar.id
            WHERE al.id = ? AND ar.user = ?
        ');
        $stmt->execute([$albumId, $user]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$row) {
            throw new RuntimeException('Album introuvable.');
        }
        return $row;
    }

    /**
     * Nettoie un nom saisi : espaces des deux bouts, suites d'espaces réduites,
     * caractères de contrôle jetés. Rend null quand il ne reste rien — ce qui
     * veut dire « garde le nom actuel ».
     */
    private static function clean(?string $name): ?string
    {
        if ($name === null) return null;
        $name = preg_replace('/[\x00-\x1F\x7F]+/u', '', $name) ?? $name;
        $name = preg_replace('/\s+/u', ' ', $name) ?? $name;
        $name = trim($name);
        return $name === '' ? null : $name;
    }

    /**
     * L'artiste de ce nom chez cet utilisateur, créé au besoin. La comparaison
     * est celle de MySQL (ni casse ni accents) : « catch 22 » retrouve
     * « Catch 22 » et son album va le rejoindre au lieu d'ouvrir un doublon.
     */
    private static function artistId(PDO $db, string $user, string $name): int
    {
        $stmt = $db->prepare('SELECT id FROM artists WHERE user = ? AND name = ? ORDER BY id ASC LIMIT 1');
        $stmt->execute([$user, $name]);
        $id = (int)($stmt->fetchColumn() ?: 0);
        if ($id) return $id;

        $db->prepare('INSERT INTO artists (name, user) VALUES (?, ?)')->execute([$name, $user]);
        return (int)$db->lastInsertId();
    }

    /**
     * Verse les titres de `$from` dans `$into`, puis efface l'album vidé.
     *
     * `UPDATE IGNORE` à cause de l'index d'unicité (album_id, file_path) :
     * si le même fichier figurait déjà dans l'album d'accueil, sa ligne reste
     * en arrière et part avec l'album — le fichier, lui, ne bouge pas.
     */
    private static function mergeInto(PDO $db, int $from, int $into): void
    {
        $db->prepare('UPDATE IGNORE songs SET album_id = ? WHERE album_id = ?')
           ->execute([$into, $from]);
        $db->prepare('UPDATE IGNORE favorite_albums SET album_id = ? WHERE album_id = ?')
           ->execute([$into, $from]);

        // L'année et le genre de l'album vidé valent mieux que rien.
        $db->prepare('
            UPDATE albums a
            JOIN albums b ON b.id = ?
            SET a.year  = COALESCE(a.year, b.year),
                a.genre = COALESCE(NULLIF(a.genre, \'\'), b.genre)
            WHERE a.id = ?
        ')->execute([$from, $into]);

        // Les titres restés derrière et les favoris de l'album partent avec lui
        // (clés étrangères ON DELETE CASCADE).
        $db->prepare('DELETE FROM albums WHERE id = ?')->execute([$from]);
    }

    private static function hasAlbums(PDO $db, int $artistId): bool
    {
        $stmt = $db->prepare('SELECT 1 FROM albums WHERE artist_id = ? LIMIT 1');
        $stmt->execute([$artistId]);
        return (bool)$stmt->fetchColumn();
    }

    /** Remet d'aplomb `album_count` / `song_count` des artistes touchés. */
    private static function refreshCounts(PDO $db, array $artistIds): void
    {
        foreach (array_unique(array_filter($artistIds)) as $id) {
            $db->prepare('
                UPDATE artists a SET
                    a.album_count = (SELECT COUNT(*) FROM albums WHERE artist_id = a.id),
                    a.song_count  = (
                        SELECT COUNT(*) FROM songs s
                        JOIN albums al ON s.album_id = al.id
                        WHERE al.artist_id = a.id
                    )
                WHERE a.id = ?
            ')->execute([$id]);
        }
    }

    /**
     * Réécrit les tags des fichiers de l'album (au mieux : un fichier illisible
     * ou d'un format que getID3 ne sait pas écrire n'annule pas le transfert,
     * il est seulement compté).
     *
     * @param array<int,array{id:int,file_path:string}> $songs
     * @return array{0:int,1:int} [écrits, ratés]
     */
    private static function retagSongs(
        string $user,
        array $songs,
        ?string $album,
        ?string $artist,
        string $oldArtist
    ): array {
        if (!$songs || ($album === null && $artist === null)) return [0, 0];

        try {
            $storage = StorageFactory::forUser($user);
        } catch (Throwable $e) {
            error_log('AlbumMove: stockage indisponible pour ' . $user . ' : ' . $e->getMessage());
            return [0, count($songs)];
        }
        if ($storage->getType() !== 'local') {
            // En SFTP il faudrait rapatrier chaque fichier : la base suffit,
            // et le scan ne relit que ce qui a changé de taille ou de date.
            return [0, count($songs)];
        }

        $base    = rtrim($storage->getPathBase(), '/');
        $written = 0;
        $failed  = 0;
        foreach ($songs as $song) {
            $path = $base . '/' . ltrim((string)$song['file_path'], '/');
            try {
                self::retagFile($path, $album, $artist, $oldArtist) ? $written++ : $failed++;
            } catch (Throwable $e) {
                $failed++;
                error_log('AlbumMove: tags non réécrits sur ' . $path . ' : ' . $e->getMessage());
            }
        }
        return [$written, $failed];
    }

    /**
     * Réécrit le tag d'UN fichier en gardant tout ce qu'il contenait déjà.
     *
     * L'artiste de piste (TPE1) n'est retouché que s'il désignait l'artiste de
     * l'album : sur une compilation, ou un titre « avec un invité », il dit
     * autre chose et c'est juste. TPE2 (« band »), lui, est toujours remis :
     * c'est celui-là que le scan lit pour ranger l'album.
     */
    private static function retagFile(
        string $path,
        ?string $album,
        ?string $artist,
        string $oldArtist
    ): bool {
        require_once AppConfig::getVendorPath() . '/getid3/getid3.php';
        require_once AppConfig::getVendorPath() . '/getid3/write.php';

        if (!is_file($path) || !is_writable($path)) return false;

        $id3  = new getID3();
        $info = $id3->analyze($path);
        $format = $info['fileformat'] ?? '';
        if ($format !== 'mp3' && $format !== 'riff') {
            // FLAC, M4A, OGG : getID3 ne sait pas les réécrire sans outil
            // externe. La base a déjà tranché, le fichier ne bouge pas.
            return false;
        }

        $tags = ($info['tags']['id3v2'] ?? []) ?: ($info['tags']['id3v1'] ?? []);
        $data = [];
        foreach (self::KEEP_TAGS as $key) {
            foreach ((array)($tags[$key] ?? []) as $value) {
                if (is_string($value) && $value !== '') {
                    $data[$key][] = $value;
                }
            }
        }
        // Pochette et champs libres : à recopier, sinon la réécriture les
        // effacerait (getID3 remplace le tag entier).
        foreach (($info['id3v2']['APIC'] ?? []) as $pic) {
            if (!is_array($pic) || !isset($pic['data'], $pic['mime'], $pic['picturetypeid'])) continue;
            $data['attached_picture'][] = [
                'data'          => $pic['data'],
                'mime'          => $pic['mime'],
                'picturetypeid' => $pic['picturetypeid'],
                'description'   => (string)($pic['description'] ?? ''),
            ];
        }
        foreach (($info['id3v2']['TXXX'] ?? []) as $txxx) {
            if (!is_array($txxx) || !isset($txxx['data'])) continue;
            $data['text'][] = [
                'description' => (string)($txxx['description'] ?? ''),
                'data'        => (string)$txxx['data'],
            ];
        }

        if ($album !== null) {
            $data['album'] = [$album];
        }
        if ($artist !== null) {
            $band = (string)($data['band'][0] ?? '');
            $tpe1 = (string)($data['artist'][0] ?? '');
            $data['band'] = [$artist];
            if ($tpe1 === '' || self::sameName($tpe1, $oldArtist) || self::sameName($tpe1, $band)) {
                $data['artist'] = [$artist];
            }
        }

        $writer = new getid3_writetags();
        $writer->filename        = $path;
        $writer->tagformats      = ['id3v2.3', 'id3v1'];
        $writer->overwrite_tags  = true;
        $writer->tag_encoding    = 'UTF-8';
        $writer->tag_data        = $data;

        if ($writer->WriteTags()) return true;

        error_log('AlbumMove: getID3 refuse ' . $path . ' : ' . implode(', ', $writer->errors));
        return false;
    }

    /** Deux noms d'artiste que seule la casse ou les espaces séparent. */
    private static function sameName(string $a, string $b): bool
    {
        return $b !== '' && mb_strtolower(trim($a)) === mb_strtolower(trim($b));
    }
}
