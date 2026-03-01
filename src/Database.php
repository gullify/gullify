<?php
/**
 * Gullify - MySQL Database class for Music Library
 */
require_once __DIR__ . '/AppConfig.php';

class Database {
    private $db;
    private $lastUpdate;

    public function __construct() {
        try {
            $this->db = AppConfig::getDB();

            $stmt = $this->db->query('SELECT last_update FROM library_status ORDER BY id DESC LIMIT 1');
            $result = $stmt->fetch();
            $this->lastUpdate = $result ? $result['last_update'] : 0;

        } catch (PDOException $e) {
            throw new Exception("Database connection failed: " . $e->getMessage());
        }
    }

    public function needsUpdate() {
        return $this->lastUpdate < (time() - 3600);
    }

    public function getLibrary($user) {
        $stmt = $this->db->prepare('
            SELECT
                a.id,
                a.name,
                a.image,
                COUNT(DISTINCT al.id) as album_count,
                COUNT(s.id) as song_count
            FROM artists a
            LEFT JOIN albums al ON a.id = al.artist_id
            LEFT JOIN songs s ON al.id = s.album_id
            WHERE a.user = ?
            GROUP BY a.id, a.name, a.image
            ORDER BY a.name ASC
        ');
        $stmt->execute([$user]);

        $artists = [];
        while ($row = $stmt->fetch()) {
            $artists[] = [
                'id' => $row['id'],
                'name' => $row['name'],
                'image' => $row['image'],
                'album_count' => $row['album_count'],
                'song_count' => $row['song_count']
            ];
        }

        return ['artists' => $artists];
    }

    public function getAlbumSongs($albumId) {
        $stmt = $this->db->prepare('
            SELECT
                s.*,
                al.name as album_name,
                al.artwork,
                a.name as artist_name,
                a.id as artist_id
            FROM songs s
            JOIN albums al ON s.album_id = al.id
            JOIN artists a ON al.artist_id = a.id
            WHERE s.album_id = ?
            ORDER BY s.track_number ASC, s.title ASC
        ');
        $stmt->execute([$albumId]);
        return $stmt->fetchAll();
    }

    public function getArtistAlbums($artistId) {
        $stmt = $this->db->prepare('
            SELECT
                al.*,
                COUNT(s.id) as song_count,
                SUM(s.duration) as total_duration
            FROM albums al
            LEFT JOIN songs s ON al.id = s.album_id
            WHERE al.artist_id = ?
            GROUP BY al.id
            ORDER BY al.name ASC
        ');
        $stmt->execute([$artistId]);
        return $stmt->fetchAll();
    }

    public function getArtistImage($artistId) {
        $stmt = $this->db->prepare('SELECT image FROM artists WHERE id = ?');
        $stmt->execute([$artistId]);
        $result = $stmt->fetch();
        return $result ? $result['image'] : null;
    }

    public function getAlbumArtwork($albumId) {
        $stmt = $this->db->prepare('SELECT artwork FROM albums WHERE id = ?');
        $stmt->execute([$albumId]);
        $result = $stmt->fetch();
        return $result ? $result['artwork'] : null;
    }

    public function searchSongs($query, $user) {
        $searchTerm = "%{$query}%";
        $stmt = $this->db->prepare('
            SELECT
                s.*,
                al.name as album_name,
                al.artwork,
                a.name as artist_name,
                a.id as artist_id
            FROM songs s
            JOIN albums al ON s.album_id = al.id
            JOIN artists a ON al.artist_id = a.id
            WHERE a.user = ?
            AND (
                s.title LIKE ? OR
                a.name LIKE ? OR
                al.name LIKE ?
            )
            ORDER BY a.name ASC, al.name ASC, s.track_number ASC
            LIMIT 100
        ');
        $stmt->execute([$user, $searchTerm, $searchTerm, $searchTerm]);
        return $stmt->fetchAll();
    }

    public function trackPlay($songId, $user, $duration, $completed, $source = 'player') {
        try {
            $this->db->beginTransaction();

            $stmt = $this->db->prepare('
                INSERT INTO play_history (song_id, user, play_duration, completed, source)
                VALUES (?, ?, ?, ?, ?)
            ');
            $stmt->execute([$songId, $user, $duration, $completed ? 1 : 0, $source]);

            $stmt = $this->db->prepare('
                INSERT INTO song_stats (song_id, play_count, first_played_at, last_played_at, total_play_time, skip_count)
                VALUES (?, 1, NOW(), NOW(), ?, ?)
                ON DUPLICATE KEY UPDATE
                    play_count = play_count + 1,
                    last_played_at = NOW(),
                    total_play_time = total_play_time + ?,
                    skip_count = skip_count + ?
            ');
            $skipIncrement = $completed ? 0 : 1;
            $stmt->execute([$songId, $duration, $skipIncrement, $duration, $skipIncrement]);

            $this->db->commit();
            return true;
        } catch (Exception $e) {
            $this->db->rollBack();
            error_log("Failed to track play: " . $e->getMessage());
            return false;
        }
    }

    public function getTopSongs($limit = 50, $user = null) {
        $sql = 'SELECT * FROM top_songs';
        $params = [];

        if ($user) {
            $sql = '
                SELECT ts.*
                FROM top_songs ts
                JOIN albums al ON ts.album = al.name
                JOIN artists a ON al.artist_id = a.id
                WHERE a.user = ?
                ORDER BY ts.play_count DESC
                LIMIT ?
            ';
            $params = [$user, $limit];
        } else {
            $sql .= ' LIMIT ?';
            $params = [$limit];
        }

        $stmt = $this->db->prepare($sql);
        $stmt->execute($params);
        return $stmt->fetchAll();
    }

    public function getRecentPlays($limit = 50, $user = null) {
        $sql = 'SELECT * FROM recent_plays';
        $params = [];

        if ($user) {
            $sql .= ' WHERE user = ?';
            $params[] = $user;
        }

        $sql .= ' ORDER BY played_at DESC LIMIT ?';
        $params[] = $limit;

        $stmt = $this->db->prepare($sql);
        $stmt->execute($params);
        return $stmt->fetchAll();
    }

    public function isFavorite($songId, $user) {
        $stmt = $this->db->prepare('SELECT 1 FROM favorites WHERE song_id = ? AND user = ?');
        $stmt->execute([$songId, $user]);
        return $stmt->fetchColumn() !== false;
    }

    public function addToFavorites($songId, $user) {
        if ($this->isFavorite($songId, $user)) return true;
        $stmt = $this->db->prepare('INSERT INTO favorites (song_id, user) VALUES (?, ?)');
        return $stmt->execute([$songId, $user]);
    }

    public function removeFromFavorites($songId, $user) {
        $stmt = $this->db->prepare('DELETE FROM favorites WHERE song_id = ? AND user = ?');
        return $stmt->execute([$songId, $user]);
    }

    public function getFavorites($user) {
        $stmt = $this->db->prepare('
            SELECT
                s.*,
                al.name as album_name,
                al.id as album_id,
                a.name as artist_name,
                a.id as artist_id,
                f.created_at as favorited_at
            FROM favorites f
            JOIN songs s ON f.song_id = s.id
            JOIN albums al ON s.album_id = al.id
            JOIN artists a ON al.artist_id = a.id
            WHERE f.user = ?
            ORDER BY f.created_at DESC
        ');
        $stmt->execute([$user]);
        $results = $stmt->fetchAll();
        foreach ($results as &$row) {
            $row['artworkUrl'] = 'serve_image.php?album_id=' . $row['album_id'];
        }
        return $results;
    }

    public function isArtistFavorite($artistId, $user) {
        $stmt = $this->db->prepare('SELECT 1 FROM favorite_artists WHERE artist_id = ? AND user = ?');
        $stmt->execute([$artistId, $user]);
        return $stmt->fetchColumn() !== false;
    }

    public function addArtistToFavorites($artistId, $user) {
        if ($this->isArtistFavorite($artistId, $user)) return true;
        $stmt = $this->db->prepare('INSERT INTO favorite_artists (artist_id, user) VALUES (?, ?)');
        return $stmt->execute([$artistId, $user]);
    }

    public function removeArtistFromFavorites($artistId, $user) {
        $stmt = $this->db->prepare('DELETE FROM favorite_artists WHERE artist_id = ? AND user = ?');
        return $stmt->execute([$artistId, $user]);
    }

    public function getFavoriteArtists($user) {
        $stmt = $this->db->prepare('
            SELECT
                a.id,
                a.name,
                (a.image IS NOT NULL AND a.image != "") as has_image,
                fa.created_at as favorited_at,
                (SELECT COUNT(*) FROM albums WHERE artist_id = a.id) as album_count,
                (SELECT COUNT(*) FROM songs s JOIN albums al ON s.album_id = al.id WHERE al.artist_id = a.id) as song_count
            FROM favorite_artists fa
            JOIN artists a ON fa.artist_id = a.id
            WHERE fa.user = ?
            ORDER BY fa.created_at DESC
        ');
        $stmt->execute([$user]);
        $results = $stmt->fetchAll();
        foreach ($results as &$row) {
            $row['imageUrl'] = $row['has_image'] ? 'serve_image.php?artist_id=' . $row['id'] : null;
        }
        return $results;
    }

    public function isAlbumFavorite($albumId, $user) {
        $stmt = $this->db->prepare('SELECT 1 FROM favorite_albums WHERE album_id = ? AND user = ?');
        $stmt->execute([$albumId, $user]);
        return $stmt->fetchColumn() !== false;
    }

    public function addAlbumToFavorites($albumId, $user) {
        if ($this->isAlbumFavorite($albumId, $user)) return true;
        $stmt = $this->db->prepare('INSERT INTO favorite_albums (album_id, user) VALUES (?, ?)');
        return $stmt->execute([$albumId, $user]);
    }

    public function removeAlbumFromFavorites($albumId, $user) {
        $stmt = $this->db->prepare('DELETE FROM favorite_albums WHERE album_id = ? AND user = ?');
        return $stmt->execute([$albumId, $user]);
    }

    public function getFavoriteAlbums($user) {
        $stmt = $this->db->prepare('
            SELECT
                al.id,
                al.name,
                al.year,
                a.id as artist_id,
                a.name as artist_name,
                fa.created_at as favorited_at,
                (SELECT COUNT(*) FROM songs WHERE album_id = al.id) as song_count
            FROM favorite_albums fa
            JOIN albums al ON fa.album_id = al.id
            JOIN artists a ON al.artist_id = a.id
            WHERE fa.user = ?
            ORDER BY fa.created_at DESC
        ');
        $stmt->execute([$user]);
        $results = $stmt->fetchAll();
        foreach ($results as &$row) {
            $row['artworkUrl'] = 'serve_image.php?album_id=' . $row['id'];
        }
        return $results;
    }

    public function createPlaylist($name, $user) {
        $stmt = $this->db->prepare('INSERT INTO playlists (name, user) VALUES (?, ?)');
        if ($stmt->execute([$name, $user])) {
            return $this->db->lastInsertId();
        }
        return false;
    }

    public function renamePlaylist($playlistId, $newName, $user) {
        $stmt = $this->db->prepare('UPDATE playlists SET name = ? WHERE id = ? AND user = ?');
        return $stmt->execute([$newName, $playlistId, $user]);
    }

    public function deletePlaylist($playlistId, $user) {
        $stmt = $this->db->prepare('DELETE FROM playlists WHERE id = ? AND user = ?');
        return $stmt->execute([$playlistId, $user]);
    }

    public function getPlaylists($user) {
        $stmt = $this->db->prepare('
            SELECT p.*, COUNT(ps.id) as song_count
            FROM playlists p
            LEFT JOIN playlist_songs ps ON p.id = ps.playlist_id
            WHERE p.user = ?
            GROUP BY p.id
            ORDER BY p.name ASC
        ');
        $stmt->execute([$user]);
        return $stmt->fetchAll();
    }

    public function getPlaylistSongs($playlistId, $user) {
        $stmt = $this->db->prepare('SELECT 1 FROM playlists WHERE id = ? AND user = ?');
        $stmt->execute([$playlistId, $user]);
        if ($stmt->fetchColumn() === false) return false;

        $stmt = $this->db->prepare('
            SELECT
                s.*,
                al.name as album_name,
                al.id as album_id,
                a.name as artist_name,
                a.id as artist_id,
                ps.id as playlist_song_id,
                ps.track_order
            FROM playlist_songs ps
            JOIN songs s ON ps.song_id = s.id
            JOIN albums al ON s.album_id = al.id
            JOIN artists a ON al.artist_id = a.id
            WHERE ps.playlist_id = ?
            ORDER BY ps.track_order ASC, s.title ASC
        ');
        $stmt->execute([$playlistId]);
        $results = $stmt->fetchAll();
        foreach ($results as &$row) {
            $row['artworkUrl'] = 'serve_image.php?album_id=' . $row['album_id'];
        }
        return $results;
    }

    public function addToPlaylist($playlistId, $songId) {
        $stmt = $this->db->prepare('SELECT 1 FROM playlist_songs WHERE playlist_id = ? AND song_id = ?');
        $stmt->execute([$playlistId, $songId]);
        if ($stmt->fetchColumn()) return true;

        $stmt = $this->db->prepare('SELECT MAX(track_order) as max_order FROM playlist_songs WHERE playlist_id = ?');
        $stmt->execute([$playlistId]);
        $maxOrder = $stmt->fetchColumn() ?? -1;
        $nextOrder = $maxOrder + 1;

        $stmt = $this->db->prepare('INSERT INTO playlist_songs (playlist_id, song_id, track_order) VALUES (?, ?, ?)');
        return $stmt->execute([$playlistId, $songId, $nextOrder]);
    }

    public function removeFromPlaylist($playlistSongId, $user) {
        $stmt = $this->db->prepare('
            SELECT 1 FROM playlist_songs ps
            JOIN playlists p ON ps.playlist_id = p.id
            WHERE ps.id = ? AND p.user = ?
        ');
        $stmt->execute([$playlistSongId, $user]);
        if ($stmt->fetchColumn() === false) return false;

        $stmt = $this->db->prepare('DELETE FROM playlist_songs WHERE id = ?');
        return $stmt->execute([$playlistSongId]);
    }

    public function getOrCreateArtist($name, $user) {
        $stmt = $this->db->prepare('SELECT id FROM artists WHERE name = ? AND user = ?');
        $stmt->execute([$name, $user]);
        $id = $stmt->fetchColumn();
        if ($id) return $id;

        $stmt = $this->db->prepare('INSERT INTO artists (name, user) VALUES (?, ?)');
        $stmt->execute([$name, $user]);
        return $this->db->lastInsertId();
    }

    public function getOrCreateAlbum($artistId, $name, $year = null, $artwork = null) {
        $stmt = $this->db->prepare('SELECT id FROM albums WHERE artist_id = ? AND name = ?');
        $stmt->execute([$artistId, $name]);
        $id = $stmt->fetchColumn();
        if ($id) {
            if ($year) {
                $this->db->prepare('UPDATE albums SET year = ? WHERE id = ?')->execute([$year, $id]);
            }
            if ($artwork) {
                $this->db->prepare('UPDATE albums SET artwork = ? WHERE id = ?')->execute([$artwork, $id]);
            }
            return $id;
        }
        $stmt = $this->db->prepare('INSERT INTO albums (artist_id, name, year, artwork) VALUES (?, ?, ?, ?)');
        $stmt->execute([$artistId, $name, $year, $artwork]);
        return $this->db->lastInsertId();
    }

    public function getSong($songId) {
        $stmt = $this->db->prepare('SELECT * FROM songs WHERE id = ?');
        $stmt->execute([$songId]);
        return $stmt->fetch();
    }

    public function getSongByPath($filePath, $username) {
        $stmt = $this->db->prepare('
            SELECT s.*
            FROM songs s
            JOIN albums al ON s.album_id = al.id
            JOIN artists a ON al.artist_id = a.id
            WHERE s.file_path = ? AND a.user = ?
        ');
        $stmt->execute([$filePath, $username]);
        return $stmt->fetch();
    }

    public function updateSong($songId, $data) {
        $fields = [];
        $params = [];
        foreach ($data as $key => $value) {
            $fields[] = "`$key` = ?";
            $params[] = $value;
        }
        if (empty($fields)) return false;
        $params[] = $songId;
        $sql = 'UPDATE songs SET ' . implode(', ', $fields) . ' WHERE id = ?';
        $stmt = $this->db->prepare($sql);
        return $stmt->execute($params);
    }

    public function getConnection() {
        return $this->db;
    }

    public function close() {
        $this->db = null;
    }
}
