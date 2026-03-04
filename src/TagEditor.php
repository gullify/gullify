<?php
/**
 * Gullify - ID3 Tag Editor
 * Handles writing tags to files and updating the database.
 */
require_once __DIR__ . '/AppConfig.php';
require_once __DIR__ . '/Storage/StorageFactory.php';
require_once __DIR__ . '/ArtworkManager.php';

class TagEditor {
    private $db;
    private $getID3;
    private $artworkManager;

    public function __construct() {
        $this->db = AppConfig::getDB();
        require_once AppConfig::getVendorPath() . '/getid3/getid3.php';
        $this->getID3 = new \getID3;
        require_once AppConfig::getVendorPath() . '/getid3/write.php';
        $this->artworkManager = new ArtworkManager();
    }

    public function getAlbumTags(int $albumId): ?array {
        // 1. Get album info
        $stmt = $this->db->prepare("
            SELECT al.id, al.name as album_name, al.year, al.genre, ar.name as artist_name
            FROM albums al
            JOIN artists ar ON al.artist_id = ar.id
            WHERE al.id = ?
        ");
        $stmt->execute([$albumId]);
        $album = $stmt->fetch();
        if (!$album) return null;

        // 2. Get songs info (including per-track artist for compilations)
        $stmt = $this->db->prepare("
            SELECT s.id, s.title as db_title, s.track_number as track, s.file_path,
                   ta.name as track_artist
            FROM songs s
            LEFT JOIN artists ta ON s.artist_id = ta.id
            WHERE s.album_id = ?
            ORDER BY s.track_number ASC, s.title ASC
        ");
        $stmt->execute([$albumId]);
        $songs = $stmt->fetchAll();

        // 3. For each song, identify filename
        foreach ($songs as &$song) {
            $song['filename'] = basename($song['file_path']);
        }

        return [
            'album' => $album,
            'songs' => $songs
        ];
    }

    public function updateSongTags(int $songId, array $tags, bool $writeFile = true): bool {
        // 1. Get song info and path
        $stmt = $this->db->prepare("
            SELECT s.file_path, a.user, s.album_id, al.artist_id
            FROM songs s
            JOIN albums al ON s.album_id = al.id
            JOIN artists a ON al.artist_id = a.id
            WHERE s.id = ?
        ");
        $stmt->execute([$songId]);
        $song = $stmt->fetch();
        if (!$song) return false;

        $storage = StorageFactory::forUser($song['user']);
        $fullPath = $storage->getPathBase() . '/' . $song['file_path'];
        
        error_log("TagEditor: Attempting to update tags for song ID $songId at $fullPath");

        // 2. Update physical file
        if ($writeFile) {
            if ($storage->getType() === 'local') {
                $res = $this->writeTagsToLocalFile($fullPath, $tags);
                if (!$res) error_log("TagEditor: FAILED to write tags to local file $fullPath");
            } else {
                // For SFTP: Download -> Write -> Upload
                error_log("TagEditor: SFTP update initiated for $fullPath");
                $tmpFile = sys_get_temp_dir() . '/tag_edit_' . uniqid() . '.' . pathinfo($fullPath, PATHINFO_EXTENSION);
                $data = $storage->readFile($fullPath);
                file_put_contents($tmpFile, $data);
                
                $this->writeTagsToLocalFile($tmpFile, $tags);
                
                $res = $storage->writeFile($fullPath, $tmpFile);
                if (!$res) error_log("TagEditor: FAILED to upload SFTP file back to $fullPath");
                @unlink($tmpFile);
            }
        }

        // 3. Update Database
        try {
            $this->db->beginTransaction();

            // Update song title/track
            if (isset($tags['title'])) {
                $stmt = $this->db->prepare("UPDATE songs SET title = ? WHERE id = ?");
                $stmt->execute([$tags['title'], $songId]);
            }
            if (isset($tags['track_number'])) {
                $stmt = $this->db->prepare("UPDATE songs SET track_number = ? WHERE id = ?");
                $stmt->execute([intval($tags['track_number']), $songId]);
            }

            // Handle Artist change (complex: might need to create new artist record)
            if (isset($tags['artist'])) {
                $newArtistId = $this->getOrCreateArtist($tags['artist'], $song['user']);
                $stmt = $this->db->prepare("UPDATE albums SET artist_id = ? WHERE id = ?");
                $stmt->execute([$newArtistId, $song['album_id']]);
            }

            // Handle Album change
            if (isset($tags['album'])) {
                $stmt = $this->db->prepare("UPDATE albums SET name = ? WHERE id = ?");
                $stmt->execute([$tags['album'], $song['album_id']]);
            }
            
            if (isset($tags['year'])) {
                $stmt = $this->db->prepare("UPDATE albums SET year = ? WHERE id = ?");
                $stmt->execute([intval($tags['year']), $song['album_id']]);
            }

            if (isset($tags['genre'])) {
                $stmt = $this->db->prepare("UPDATE albums SET genre = ? WHERE id = ?");
                $stmt->execute([$tags['genre'], $song['album_id']]);
            }

            $this->db->commit();

            // 4. Post-update: check if we need to fetch/update artwork or artist image
            if (isset($tags['artist'])) {
                $this->artworkManager->updateArtistImage((int)$newArtistId);
            }
            if (isset($tags['album']) || isset($tags['artist']) || isset($tags['year'])) {
                $this->artworkManager->updateAlbumArtwork((int)$song['album_id']);
            }

            return true;
        } catch (Exception $e) {
            $this->db->rollBack();
            return false;
        }
    }

    public function batchSave(array $songsData): array {
        $results = ['saved' => 0, 'failed' => 0, 'results' => [], 'errors' => []];
        
        foreach ($songsData as $songData) {
            $songId = (int)$songData['song_id'];
            $tags = $songData['tags'];
            
            if ($this->updateSongTags($songId, $tags)) {
                $results['saved']++;
                $results['results'][] = ['song_id' => $songId];
            } else {
                $results['failed']++;
                $results['errors'][] = ['song_id' => $songId, 'error' => 'Failed to save tags'];
            }
        }
        
        return $results;
    }

    public function renameFile(int $songId, string $newFilename): array {
        // 1. Get song info
        $stmt = $this->db->prepare("
            SELECT s.file_path, a.user
            FROM songs s
            JOIN albums al ON s.album_id = al.id
            JOIN artists a ON al.artist_id = a.id
            WHERE s.id = ?
        ");
        $stmt->execute([$songId]);
        $song = $stmt->fetch();
        if (!$song) return ['success' => false, 'error' => 'Song not found in DB'];

        $storage = StorageFactory::forUser($song['user']);
        $oldRelativePath = $song['file_path'];
        $dir = dirname($oldRelativePath);
        $ext = pathinfo($oldRelativePath, PATHINFO_EXTENSION);
        
        $cleanName = pathinfo($newFilename, PATHINFO_FILENAME);
        $newRelativePath = ($dir === '.' ? '' : $dir . '/') . $cleanName . '.' . $ext;

        if ($oldRelativePath === $newRelativePath) return ['success' => true, 'new_file_path' => $oldRelativePath, 'new_filename' => basename($oldRelativePath)];

        $musicRoot = $storage->getPathBase();
        $oldFullPath = $musicRoot . '/' . $oldRelativePath;
        $newFullPath = $musicRoot . '/' . $newRelativePath;

        // 2. Physical rename
        try {
            if ($storage->rename($oldFullPath, $newFullPath)) {
                // 3. Update DB
                $stmt = $this->db->prepare("UPDATE songs SET file_path = ? WHERE id = ?");
                $stmt->execute([$newRelativePath, $songId]);
                
                return [
                    'success' => true,
                    'data' => [
                        'new_file_path' => $newRelativePath,
                        'new_filename' => basename($newRelativePath)
                    ]
                ];
            } else {
                return ['success' => false, 'error' => "Storage layer failed to rename. Check permissions at $oldFullPath"];
            }
        } catch (Exception $e) {
            return ['success' => false, 'error' => $e->getMessage()];
        }
    }

    private function writeTagsToLocalFile(string $path, array $tags): bool {
        if (!is_writable($path)) {
            error_log("TagEditor: File is not writable: $path");
            return false;
        }

        $tagwriter = new \getid3_writetags;
        $tagwriter->filename = $path;
        $tagwriter->tagformats = ['id3v2.3', 'id3v1'];
        $tagwriter->overwrite_tags = true;
        $tagwriter->tag_encoding = 'UTF-8';

        $tagData = [];
        if (isset($tags['title']))  $tagData['title'][]  = $tags['title'];
        if (isset($tags['artist'])) $tagData['artist'][] = $tags['artist'];
        if (isset($tags['album']))  $tagData['album'][]  = $tags['album'];
        if (isset($tags['year']))   $tagData['year'][]   = $tags['year'];
        if (isset($tags['track_number'])) $tagData['track_number'][] = $tags['track_number'];
        if (isset($tags['genre']))        $tagData['genre'][]        = $tags['genre'];
        if (isset($tags['album_artist'])) $tagData['band'][]         = $tags['album_artist']; // TPE2

        $tagwriter->tag_data = $tagData;
        $result = $tagwriter->WriteTags();
        
        if (!$result) {
            error_log("TagEditor: getID3 error: " . implode(", ", $tagwriter->errors));
        }
        
        return $result;
    }

    private function getOrCreateArtist(string $name, string $user): int {
        $stmt = $this->db->prepare("SELECT id FROM artists WHERE name = ? AND user = ?");
        $stmt->execute([$name, $user]);
        $id = $stmt->fetchColumn();
        if ($id) return (int)$id;

        $stmt = $this->db->prepare("INSERT INTO artists (name, user) VALUES (?, ?)");
        $stmt->execute([$name, $user]);
        return (int)$this->db->lastInsertId();
    }
}
