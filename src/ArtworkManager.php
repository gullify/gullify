<?php
/**
 * Gullify - Artwork & Artist Image Manager
 * Handles searching, downloading, and caching of images.
 */
require_once __DIR__ . '/AppConfig.php';
require_once __DIR__ . '/Storage/StorageFactory.php';

class ArtworkManager {
    private $db;

    public function __construct() {
        $this->db = AppConfig::getDB();
    }

    /**
     * Finds and caches an album cover.
     */
    public function updateAlbumArtwork(int $albumId): ?string {
        // 1. Get album and user info
        $stmt = $this->db->prepare("
            SELECT al.name as album_name, ar.name as artist_name, ar.user, s.file_path
            FROM albums al
            JOIN artists ar ON al.artist_id = ar.id
            JOIN songs s ON s.album_id = al.id
            WHERE al.id = ?
            LIMIT 1
        ");
        $stmt->execute([$albumId]);
        $data = $stmt->fetch();
        if (!$data) return null;

        $storage = StorageFactory::forUser($data['user']);
        $albumPath = dirname($storage->getPathBase() . '/' . $data['file_path']);
        
        $cachePath = AppConfig::getDataPath() . '/cache/artwork';
        if (!is_dir($cachePath)) mkdir($cachePath, 0775, true);
        $targetFile = $cachePath . '/album_' . $albumId . '.jpg';

        $imageData = null;

        // 2. Try local files first
        $patterns = ['folder.jpg', 'Folder.jpg', 'cover.jpg', 'Cover.jpg', 'front.jpg', 'album.jpg'];
        foreach ($patterns as $p) {
            $fullPath = $albumPath . '/' . $p;
            if ($storage->fileExists($fullPath)) {
                $imageData = $storage->readFile($fullPath);
                break;
            }
        }

        // 3. Web search fallback
        if (!$imageData) {
            $searchQuery = $data['artist_name'] . " " . $data['album_name'];
            error_log("ArtworkManager: Searching web for album cover: $searchQuery");
            $imageUrl = $this->searchWeb($searchQuery, 'album');
            if ($imageUrl) {
                error_log("ArtworkManager: Found image at $imageUrl, downloading...");
                $imageData = @file_get_contents($imageUrl);
                // Save to local folder for future scans
                if ($imageData && $storage->getType() === 'local' && is_dir($albumPath)) {
                    @file_put_contents($albumPath . '/folder.jpg', $imageData);
                    error_log("ArtworkManager: Saved folder.jpg to $albumPath");
                }
            } else {
                error_log("ArtworkManager: No web image found for $searchQuery");
            }
        }

        if ($imageData) {
            if ($this->saveThumbnail($imageData, $targetFile)) {
                $filename = 'album_' . $albumId . '.jpg';
                $this->db->prepare("UPDATE albums SET artwork = ? WHERE id = ?")->execute([$filename, $albumId]);
                return $filename;
            }
        }

        return null;
    }

    /**
     * Finds and caches an artist image.
     */
    public function updateArtistImage(int $artistId): ?string {
        $stmt = $this->db->prepare("SELECT name, user FROM artists WHERE id = ?");
        $stmt->execute([$artistId]);
        $artist = $stmt->fetch();
        if (!$artist) return null;

        $storage = StorageFactory::forUser($artist['user']);
        $artistDir = $storage->getPathBase() . '/' . $artist['name'];
        
        $cachePath = AppConfig::getDataPath() . '/cache/artwork';
        if (!is_dir($cachePath)) mkdir($cachePath, 0775, true);
        $targetFile = $cachePath . '/artist_' . $artistId . '.jpg';

        $imageData = null;

        // 1. Try local folder
        if ($storage->isDir($artistDir)) {
            $patterns = ['artist.jpg', 'artist.png', 'folder.jpg', 'folder.png'];
            foreach ($patterns as $p) {
                $fullPath = $artistDir . '/' . $p;
                if ($storage->fileExists($fullPath)) {
                    $imageData = $storage->readFile($fullPath);
                    break;
                }
            }
        }

        // 2. Web search fallback
        if (!$imageData) {
            $imageUrl = $this->searchWeb($artist['name'], 'artist');
            if ($imageUrl) {
                $imageData = @file_get_contents($imageUrl);
                // Save to local folder
                if ($imageData && $storage->getType() === 'local' && $storage->isDir($artistDir)) {
                    @file_put_contents($artistDir . '/artist.jpg', $imageData);
                }
            }
        }

        if ($imageData) {
            if ($this->saveThumbnail($imageData, $targetFile)) {
                $filename = 'artist_' . $artistId . '.jpg';
                $this->db->prepare("UPDATE artists SET image = ? WHERE id = ?")->execute([$filename, $artistId]);
                return $filename;
            }
        }

        return null;
    }

    /**
     * Save raw image data as the artwork for an album.
     * 1. Resizes to 500px and saves to cache/artwork/album_X.jpg
     * 2. Updates DB albums.artwork
     * 3. Writes folder.jpg in the album's music directory (local or SFTP)
     */
    public function saveAlbumArtwork(int $albumId, string $imageData): bool {
        $cachePath = AppConfig::getDataPath() . '/cache/artwork';
        if (!is_dir($cachePath)) mkdir($cachePath, 0775, true);
        $targetFile = $cachePath . '/album_' . $albumId . '.jpg';

        if (!$this->saveThumbnail($imageData, $targetFile)) return false;

        $this->db->prepare("UPDATE albums SET artwork = ? WHERE id = ?")
                 ->execute(['album_' . $albumId . '.jpg', $albumId]);

        // Also write folder.jpg into the album directory on the storage backend
        $stmt = $this->db->prepare("
            SELECT ar.user, s.file_path
            FROM songs s
            JOIN albums al ON s.album_id = al.id
            JOIN artists ar ON al.artist_id = ar.id
            WHERE al.id = ?
            LIMIT 1
        ");
        $stmt->execute([$albumId]);
        $row = $stmt->fetch();
        if ($row) {
            $storage   = StorageFactory::forUser($row['user']);
            $albumDir  = dirname($storage->getPathBase() . '/' . ltrim($row['file_path'], '/'));
            $folderJpg = $albumDir . '/folder.jpg';

            // For local storage write directly; for SFTP use a temp file
            if ($storage->getType() === 'local') {
                @file_put_contents($folderJpg, file_get_contents($targetFile));
            } else {
                $tmp = tempnam(sys_get_temp_dir(), 'gullify_artwork_');
                copy($targetFile, $tmp);
                $storage->writeFile($folderJpg, $tmp);
                @unlink($tmp);
            }
        }

        return true;
    }

    /**
     * Save raw image data as the image for an artist.
     * 1. Resizes to 500px and saves to cache/artwork/artist_X.jpg
     * 2. Updates DB artists.image
     * 3. Writes artist.jpg in the artist's music directory (local or SFTP)
     */
    public function saveArtistImage(int $artistId, string $imageData): bool {
        $cachePath = AppConfig::getDataPath() . '/cache/artwork';
        if (!is_dir($cachePath)) mkdir($cachePath, 0775, true);
        $targetFile = $cachePath . '/artist_' . $artistId . '.jpg';

        if (!$this->saveThumbnail($imageData, $targetFile)) return false;

        $this->db->prepare("UPDATE artists SET image = ? WHERE id = ?")
                 ->execute(['artist_' . $artistId . '.jpg', $artistId]);

        // Also write artist.jpg into the artist directory on the storage backend
        $stmt = $this->db->prepare("SELECT name, user FROM artists WHERE id = ?");
        $stmt->execute([$artistId]);
        $row = $stmt->fetch();
        if ($row) {
            $storage   = StorageFactory::forUser($row['user']);
            $artistDir = $storage->getPathBase() . '/' . $row['name'];
            $artistJpg = $artistDir . '/artist.jpg';
            if ($storage->getType() === 'local') {
                if (is_dir($artistDir)) {
                    @file_put_contents($artistJpg, file_get_contents($targetFile));
                }
            } else {
                $tmp = tempnam(sys_get_temp_dir(), 'gullify_artist_');
                copy($targetFile, $tmp);
                $storage->writeFile($artistJpg, $tmp);
                @unlink($tmp);
            }
        }

        return true;
    }

    private function searchWeb(string $query, string $type): ?string {
        $pythonScript = AppConfig::getPythonPath() . '/ytmusic_search.py';
        $pythonBin = file_exists('/opt/ytdlp/bin/python3') ? '/opt/ytdlp/bin/python3' : 'python3';
        $cmd = $pythonBin . ' ' . escapeshellarg($pythonScript) . ' ' . escapeshellarg($type) . ' ' . escapeshellarg($query);
        $output = shell_exec($cmd);
        if ($output) {
            $data = json_decode($output, true);
            if (isset($data['results']) && count($data['results']) > 0) {
                return $data['results'][0]['thumbnail'] ?? null;
            }
        }
        return null;
    }

    private function saveThumbnail(string $imageData, string $targetPath, int $size = 500): bool {
        try {
            $src = @imagecreatefromstring($imageData);
            if (!$src) return false;
            $width = imagesx($src); $height = imagesy($src);
            if ($width > $height) {
                $newWidth = $size; $newHeight = floor($height * ($size / $width));
            } else {
                $newHeight = $size; $newWidth = floor($width * ($size / $height));
            }
            $tmp = imagecreatetruecolor($newWidth, $newHeight);
            imagealphablending($tmp, false); imagesavealpha($tmp, true);
            imagecopyresampled($tmp, $src, 0, 0, 0, 0, $newWidth, $newHeight, $width, $height);
            $result = imagejpeg($tmp, $targetPath, 85);
            imagedestroy($src); imagedestroy($tmp);
            return $result;
        } catch (Exception $e) { return false; }
    }
}
