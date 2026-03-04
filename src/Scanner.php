<?php
/**
 * Gullify - Library Scanner
 * Scans music directories and populates the database.
 *
 * 3 scan modes:
 *   1. scanUserIncremental() - Full library scan (filesystem names, batch commits, artwork pass)
 *   2. scanArtist()          - Single-artist scan (ID3 titles, year extraction, change tracking)
 *   3. updateMissingArtwork()- Artwork-only pass for albums with NULL/empty artwork
 */
require_once __DIR__ . '/AppConfig.php';
require_once __DIR__ . '/PathHelper.php';
require_once __DIR__ . '/Storage/StorageInterface.php';
require_once __DIR__ . '/Storage/LocalStorage.php';
require_once __DIR__ . '/Storage/SFTPStorage.php';
require_once __DIR__ . '/Storage/StorageFactory.php';
require_once __DIR__ . '/ArtworkManager.php';

class Scanner {
    private $db;
    private $basePath;
    private $getID3;
    private $pathHelper;
    private $artworkManager;
    private $skipArtwork = false;

    /** @var StorageInterface|null Current user's storage backend */
    private ?StorageInterface $storage = null;
    /** Path prefix stripped from absolute paths to produce DB file_path values */
    private string $scanPathBase = '';

    private $artistCache = [];
    private $albumCache = [];
    private $existingSongPaths = [];

    private $audioExtensions = ['mp3', 'm4a', 'flac', 'ogg', 'wav', 'aac', 'wma', 'opus', 'aiff'];

    private $songsProcessed = 0;
    private $songsAdded = 0;
    private $totalFilesFound = 0;
    private $batchSize = 100;
    private $currentStatus = 'idle';

    private function saveProgress(string $status, ?string $currentFile = null): void {
        $cachePath = AppConfig::getDataPath() . '/cache';
        if (!is_dir($cachePath)) {
            @mkdir($cachePath, 0775, true);
        }
        $progressFile = $cachePath . '/scan-progress.json';
        $data = [
            'status' => $status,
            'processed' => $this->songsProcessed,
            'total' => $this->totalFilesFound,
            'added' => $this->songsAdded,
            'current_file' => $currentFile,
            'timestamp' => time()
        ];
        @file_put_contents($progressFile, json_encode($data));
    }

    private function countFilesRecursive(string $dir): int {
        // FAST PATH: Local storage
        if ($this->storage->getType() === 'local') {
            $extensions = implode('|', $this->audioExtensions);
            // Use find command: it's incredibly fast
            $cmd = "find " . escapeshellarg($dir) . " -type f -regextype posix-extended -regex '.*\.(" . $extensions . ")$' | wc -l";
            $count = (int) shell_exec($cmd);
            return $count > 0 ? $count : 0;
        }

        // SFTP PATH: Attempt remote command if possible, or fallback
        // Since listing is slow, we'll return 0 if we can't do it instantly 
        // to trigger the animated progress bar instead of hanging.
        return 0; 
    }

    public function __construct(bool $skipArtwork = false) {
        $this->skipArtwork = $skipArtwork;
        $this->basePath = AppConfig::getMusicBasePath();
        $this->pathHelper = new PathHelper();
        $this->artworkManager = new ArtworkManager();

        require_once AppConfig::getVendorPath() . '/getid3/getid3.php';
        $this->getID3 = new \getID3;

        try {
            $this->db = AppConfig::getDB();
        } catch (PDOException $e) {
            throw new Exception("Failed to connect to database: " . $e->getMessage());
        }

        $this->ensureSchema();
    }

    // =========================================================================
    // Schema migrations
    // =========================================================================

    private function ensureSchema(): void {
        if (!$this->columnExists('artists', 'album_count')) {
            $this->db->exec("ALTER TABLE artists ADD COLUMN album_count INT DEFAULT 0");
        }
        if (!$this->columnExists('artists', 'song_count')) {
            $this->db->exec("ALTER TABLE artists ADD COLUMN song_count INT DEFAULT 0");
        }
        if (!$this->columnExists('artists', 'genre')) {
            $this->db->exec("ALTER TABLE artists ADD COLUMN genre VARCHAR(100) NULL");
        }
        if (!$this->columnExists('albums', 'created_at')) {
            $this->db->exec("ALTER TABLE albums ADD COLUMN created_at DATETIME DEFAULT CURRENT_TIMESTAMP");
        }
        if (!$this->columnExists('albums', 'is_compilation')) {
            $this->db->exec("ALTER TABLE albums ADD COLUMN is_compilation TINYINT(1) NOT NULL DEFAULT 0");
        }
        if (!$this->columnExists('songs', 'artist_id')) {
            $this->db->exec("ALTER TABLE songs ADD COLUMN artist_id INT NULL");
        }
    }

    private function columnExists(string $table, string $column): bool {
        $dbName = AppConfig::get('mysql.database');
        $stmt = $this->db->prepare("SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? AND COLUMN_NAME = ?");
        $stmt->execute([$dbName, $table, $column]);
        return (bool) $stmt->fetchColumn();
    }

    // =========================================================================
    // Public accessors
    // =========================================================================

    public function getAllUsers(): array {
        return $this->pathHelper->getActiveUsernames();
    }

    public function getUserPathRelative(string $username): ?string {
        $fullPath = $this->pathHelper->getUserPath($username);
        if (!$fullPath) return null;
        if (str_starts_with($fullPath, $this->basePath . '/')) {
            return substr($fullPath, strlen($this->basePath . '/'));
        }
        return $fullPath;
    }

    /**
     * Wipes all data for a specific user from the database.
     */
    public function clearUserLibrary(string $user): void {
        echo "Clearing library for user: $user...\n";
        
        // We delete by cascading: Artists -> Albums -> Songs
        // Since artists are linked to users, we start there.
        try {
            $this->db->beginTransaction();
            
            // 1. Get all artist IDs for this user
            $stmt = $this->db->prepare("SELECT id FROM artists WHERE user = ?");
            $stmt->execute([$user]);
            $artistIds = $stmt->fetchAll(PDO::FETCH_COLUMN);
            
            if (!empty($artistIds)) {
                $placeholders = implode(',', array_fill(0, count($artistIds), '?'));
                
                // 2. Delete songs belonging to these artists' albums
                $stmt = $this->db->prepare("
                    DELETE s FROM songs s
                    JOIN albums al ON s.album_id = al.id
                    WHERE al.artist_id IN ($placeholders)
                ");
                $stmt->execute($artistIds);
                
                // 3. Delete albums
                $stmt = $this->db->prepare("DELETE FROM albums WHERE artist_id IN ($placeholders)");
                $stmt->execute($artistIds);
                
                // 4. Delete artists
                $stmt = $this->db->prepare("DELETE FROM artists WHERE user = ?");
                $stmt->execute([$user]);
            }
            
            $this->db->commit();
            echo "Library cleared successfully.\n";
        } catch (Exception $e) {
            $this->db->rollBack();
            echo "Error clearing library: " . $e->getMessage() . "\n";
        }
    }

    // =========================================================================
    // Mode 1: Full Library Scan (incremental)
    // =========================================================================

    public function scanUserIncremental(string $user): void {
        // Initialise storage backend for this user
        $this->storage = StorageFactory::forUser($user);

        if ($this->storage->getType() === 'sftp') {
            $musicRoot = $this->storage->getMusicRoot();
            $this->scanPathBase = $musicRoot; // file_path relative to sftp_path
        } else {
            $relPath = $this->getUserPathRelative($user);
            if (!$relPath) {
                throw new Exception("No music directory found for user: $user");
            }
            $musicRoot = $this->basePath . '/' . $relPath;
            $this->scanPathBase = $this->basePath; // keeps existing behavior (includes music_dir prefix)
        }

        if (!$this->storage->isDir($musicRoot)) {
            throw new Exception("Music directory not found or not accessible: $musicRoot");
        }

        echo "Starting incremental scan for user: $user\n";
        echo "Storage type: " . $this->storage->getType() . "\n";

        if ($this->storage->getType() === 'local') {
            $this->saveProgress('counting', 'Counting files...');
            $this->totalFilesFound = $this->countFilesRecursive($musicRoot);
            echo "Found {$this->totalFilesFound} audio files.\n";
        } else {
            $this->totalFilesFound = 0; // Unknown for SFTP to save time
            echo "SFTP: Skipping initial file count to speed up scan.\n";
        }

        $this->loadUserCache($user);
        $pathsToKeep = [];
        $this->songsProcessed = 0;
        $this->songsAdded = 0;

        echo "Scanning directory: $musicRoot\n";
        $this->saveProgress('scanning');

        $this->scanDirectoryRecursive($musicRoot, $user, $pathsToKeep);

        // Commit any remaining batch
        if ($this->db->inTransaction()) {
            $this->db->commit();
        }

        echo "\nProcessed: {$this->songsProcessed} files, Added/Updated: {$this->songsAdded}\n";

        // Prune deleted songs in batches
        $pathsInDb = array_keys($this->existingSongPaths[$user] ?? []);
        $pathsToDelete = array_diff($pathsInDb, $pathsToKeep);

        if (!empty($pathsToDelete)) {
            $this->saveProgress('pruning', 'Removing deleted files...');
            echo "Pruning " . count($pathsToDelete) . " deleted/moved songs...\n";
            $idsToDelete = [];
            foreach ($pathsToDelete as $path) {
                echo "  [-] Removing: $path\n";
                $idsToDelete[] = $this->existingSongPaths[$user][$path]['id'];
            }
            foreach (array_chunk($idsToDelete, 500) as $chunk) {
                $this->db->exec('DELETE FROM songs WHERE id IN (' . implode(',', $chunk) . ')');
            }
            echo "  Successfully pruned " . count($pathsToDelete) . " songs.\n";
        } else {
            echo "No songs to prune (all " . count($pathsInDb) . " existing songs were found on disk).\n";
        }

        // Artwork pass: fill in missing artwork for all albums
        if (!$this->skipArtwork) {
            $this->saveProgress('artwork', 'Downloading and caching covers...');
            echo "Updating missing artwork for $user...\n";
            $this->updateMissingArtwork($user);
            
            $this->saveProgress('artist_images', 'Downloading artist images...');
            echo "Updating missing artist images for $user...\n";
            $this->updateArtistImagesForUser($user);
        }

        $this->saveProgress('stats', 'Updating database statistics...');
        echo "Updating artist statistics for $user...\n";
        $this->updateArtistStatsForUser($user);

        // Clean up orphaned albums/artists left behind by ID3 tag changes
        $this->saveProgress('cleanup', 'Cleaning up orphaned entries...');
        $cleaned = $this->cleanupOrphans($user);
        if ($cleaned['albums'] > 0 || $cleaned['artists'] > 0) {
            echo "Orphan cleanup: removed {$cleaned['albums']} album(s) and {$cleaned['artists']} artist(s).\n";
        }

        // Re-merge songs that belong to known compilations but ended up under other artists
        $remerged = $this->reapplyCompilations($user);
        if ($remerged > 0) {
            echo "Compilations: re-merged {$remerged} song(s) back into compilation albums.\n";
        }

        // Update library status
        $this->db->exec('INSERT INTO library_status (last_update) VALUES (' . time() . ')');

        echo "Incremental scan completed for user: $user\n";
        $this->saveProgress('idle', 'Scan completed!');
    }

    /**
     * Remove albums with no songs and artists with no albums for a given user.
     * Returns counts of deleted rows.
     */
    public function cleanupOrphans(string $user): array {
        // Albums that belong to this user but have no songs
        $stmt = $this->db->prepare("
            DELETE al FROM albums al
            JOIN artists ar ON al.artist_id = ar.id
            WHERE ar.user = ?
            AND al.id NOT IN (SELECT DISTINCT album_id FROM songs)
        ");
        $stmt->execute([$user]);
        $albumsDeleted = $stmt->rowCount();

        // Artists that belong to this user but have no albums
        $stmt = $this->db->prepare("
            DELETE FROM artists
            WHERE user = ?
            AND id NOT IN (SELECT DISTINCT artist_id FROM albums)
        ");
        $stmt->execute([$user]);
        $artistsDeleted = $stmt->rowCount();

        return ['artists' => $artistsDeleted, 'albums' => $albumsDeleted];
    }

    /**
     * After a scan, re-attach songs that ended up under other artists
     * but whose album name matches a known is_compilation album for this user.
     * Returns the number of songs re-merged.
     */
    public function reapplyCompilations(string $user): int {
        // Ensure "Various Artists" exists for this user
        $variousArtistsId = $this->getArtistId('Various Artists', $user);

        // Load all compilation albums for this user
        $stmt = $this->db->prepare("
            SELECT al.id, al.artist_id, LOWER(TRIM(al.name)) AS name_lower
            FROM albums al
            JOIN artists ar ON al.artist_id = ar.id
            WHERE ar.user = ? AND al.is_compilation = 1
        ");
        $stmt->execute([$user]);
        $compilations = $stmt->fetchAll(PDO::FETCH_ASSOC);
        if (empty($compilations)) return 0;

        $totalMerged = 0;

        foreach ($compilations as $comp) {
            // Ensure the compilation album is attributed to "Various Artists"
            if ((int)$comp['artist_id'] !== $variousArtistsId) {
                $this->db->prepare("UPDATE albums SET artist_id = ? WHERE id = ?")
                         ->execute([$variousArtistsId, $comp['id']]);
            }

            // Find sibling albums with same name NOT marked as compilation
            $stmt = $this->db->prepare("
                SELECT al.id
                FROM albums al
                JOIN artists ar ON al.artist_id = ar.id
                WHERE ar.user = ?
                  AND LOWER(TRIM(al.name)) = ?
                  AND al.id != ?
                  AND al.is_compilation = 0
            ");
            $stmt->execute([$user, $comp['name_lower'], $comp['id']]);
            $dupes = $stmt->fetchAll(PDO::FETCH_COLUMN);

            if (empty($dupes)) continue;

            $ph = implode(',', array_fill(0, count($dupes), '?'));

            // Count songs being moved
            $countStmt = $this->db->prepare("SELECT COUNT(*) FROM songs WHERE album_id IN ($ph)");
            $countStmt->execute($dupes);
            $totalMerged += (int)$countStmt->fetchColumn();

            // Move songs to compilation album, preserving track artist from source album
            // COALESCE keeps existing songs.artist_id if set, otherwise fills from source album's artist
            $this->db->prepare("
                UPDATE songs s
                JOIN albums al ON s.album_id = al.id
                SET s.album_id = ?, s.artist_id = COALESCE(s.artist_id, al.artist_id)
                WHERE s.album_id IN ($ph)
            ")->execute([$comp['id'], ...$dupes]);

            // Delete now-empty duplicate albums
            $this->db->prepare("DELETE FROM albums WHERE id IN ($ph)")
                     ->execute($dupes);
        }

        // Clean up artists that now have no albums
        $this->db->prepare("
            DELETE FROM artists
            WHERE user = ?
            AND id NOT IN (SELECT DISTINCT artist_id FROM albums)
        ")->execute([$user]);

        return $totalMerged;
    }

    private function scanDirectoryRecursive(string $dir, string $user, array &$pathsToKeep): void {
        $items = $this->storage->listDir($dir);
        foreach ($items as $item) {
            $path = $dir . '/' . $item['name'];
            if ($item['is_dir']) {
                $this->scanDirectoryRecursive($path, $user, $pathsToKeep);
            } elseif ($this->isAudioFile($item['name'])) {
                $this->processSongFile($path, $user, $pathsToKeep);
            }
        }
    }

    private function processSongFile(string $songPath, string $user, array &$pathsToKeep): void {
        $relativePath = str_replace($this->scanPathBase . '/', '', $songPath);
        $pathsToKeep[] = $relativePath;
        $this->songsProcessed++;

        if ($this->songsProcessed % 10 === 0) {
            $this->saveProgress('scanning', $relativePath);
        }

        if ($this->songsProcessed % 100 === 0) {
            echo "  [{$this->songsProcessed}/{$this->totalFilesFound}] {$relativePath}\n";
        }

        // Compute file hash
        $fileHash = $this->computeFileHash($songPath);

        // Skip if file unchanged
        if (isset($this->existingSongPaths[$user][$relativePath])) {
            if ($this->existingSongPaths[$user][$relativePath]['hash'] === $fileHash) {
                $pathsToKeep[] = $relativePath;
                return;
            }
        }

        // If file exists but hash changed, we delete it first to re-insert with fresh metadata
        if (isset($this->existingSongPaths[$user][$relativePath])) {
            if (!$this->db->inTransaction()) $this->db->beginTransaction();
            $this->db->exec('DELETE FROM songs WHERE id = ' . $this->existingSongPaths[$user][$relativePath]['id']);
        }

        // Start batch transaction if needed
        if (!$this->db->inTransaction()) {
            $this->db->beginTransaction();
        }

        // Extract metadata
        $metadata = $this->extractBasicMetadata($songPath);

        // Use ID3 tags if available
        $trackArtistName = $metadata['artist'];    // TPE1: actual performer
        $albumArtistName = $metadata['albumArtist']; // TPE2: album/band artist
        $albumName       = $metadata['album'];
        $title           = $metadata['title'];
        $isCompilation   = $metadata['isCompilation'];

        // Fallback to path logic if core tags are missing
        if (!$trackArtistName || !$albumName || !$title) {
            $pathParts = explode('/', $relativePath);
            $numParts = count($pathParts);

            if ($numParts >= 3) {
                if (!$title) $title = pathinfo($pathParts[$numParts - 1], PATHINFO_FILENAME);
                if (!$albumName) $albumName = $pathParts[$numParts - 2];
                if (!$trackArtistName) $trackArtistName = $pathParts[$numParts - 3];
            } else if ($numParts == 2) {
                if (!$title) $title = pathinfo($pathParts[1], PATHINFO_FILENAME);
                if (!$trackArtistName) $trackArtistName = $pathParts[0];
                if (!$albumName) $albumName = 'Album inconnu';
            } else {
                if (!$title) $title = pathinfo($pathParts[0], PATHINFO_FILENAME);
                if (!$trackArtistName) $trackArtistName = 'Artiste inconnu';
                if (!$albumName) $albumName = 'Album inconnu';
            }
        }

        // Clean up names
        $trackArtistName = $trackArtistName ?: 'Artiste inconnu';
        $albumArtistName = $albumArtistName  ?: $trackArtistName; // TPE2 fallback to TPE1
        $albumName       = $albumName        ?: 'Album inconnu';
        $title           = $title            ?: pathinfo($songPath, PATHINFO_FILENAME);

        // Also detect "Various Artists" TPE2 as compilation
        if (!$isCompilation && strtolower(trim($albumArtistName)) === 'various artists') {
            $isCompilation = true;
        }

        // Determine album-level artist and optional per-song artist
        if ($isCompilation) {
            // Album belongs to "Various Artists"; song stores its own performer
            $artistId      = $this->getArtistId('Various Artists', $user);
            $trackArtistId = $this->getArtistId($trackArtistName, $user);
        } else {
            // Normal album: group by album artist (TPE2 preferred over TPE1)
            $artistId      = $this->getArtistId($albumArtistName, $user);
            $trackArtistId = null; // inherit from album
        }

        // Propagate ID3 genre to the artist if not already set (manual tags take priority)
        if (!empty($metadata['genre'])) {
            $this->db->prepare(
                "UPDATE artists SET genre = ? WHERE id = ? AND (genre IS NULL OR genre = '')"
            )->execute([$metadata['genre'], $artistId]);
        }
        $albumId = $this->getAlbumId($artistId, $albumName, true, $metadata['genre']);

        // Mark album as compilation if detected during scan
        if ($isCompilation) {
            $this->db->prepare(
                "UPDATE albums SET is_compilation = 1 WHERE id = ? AND is_compilation = 0"
            )->execute([$albumId]);
        }

        $stmt = $this->db->prepare('
            INSERT INTO songs (album_id, artist_id, title, track_number, duration, file_path, file_hash)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ');
        $stmt->execute([
            $albumId,
            $trackArtistId,
            $title,
            $metadata['trackNumber'],
            $metadata['duration'],
            $relativePath,
            $fileHash,
        ]);

        // Write derived tags back to the file so future scans read proper metadata
        if (!empty($metadata['tagsToWrite']) &&
            ($this->storage === null || $this->storage->getType() !== 'sftp')) {
            $this->writeBackDerivedTags($songPath, $metadata['tagsToWrite']);
        }

        $this->songsAdded++;

        if ($this->songsAdded % $this->batchSize === 0) {
            $this->db->commit();
            echo "  Committed batch ({$this->songsAdded} songs added/updated so far)\n";
        }
    }

    // =========================================================================
    // Mode 2: Single Artist Scan
    // =========================================================================

    /**
     * Scan a single artist's directory with full ID3 metadata.
     * Returns a change report.
     */
    public function scanArtist(int $artistId, string $user): array {
        $changes = [
            'new_albums' => [],
            'new_songs' => [],
            'removed_albums' => [],
            'removed_songs' => [],
            'updated_songs' => [],
            'updated_artwork' => [],
            'updated_years' => [],
        ];

        // Get artist info
        $stmt = $this->db->prepare('SELECT id, name FROM artists WHERE id = ? AND user = ?');
        $stmt->execute([$artistId, $user]);
        $artist = $stmt->fetch();
        if (!$artist) {
            throw new Exception('Artist not found');
        }

        // Ensure storage is set for this user
        $this->storage = StorageFactory::forUser($user);
        $this->scanPathBase = $this->storage->getPathBase();

        $userPath = $this->storage->getMusicRoot();

        $artistDir = $userPath . '/' . $artist['name'];
        if (!$this->storage->isDir($artistDir)) {
            $changes['removed_albums'][] = "Artist folder '{$artist['name']}' not found";
            return $changes;
        }

        // Load existing data
        $existingAlbums = $this->getExistingAlbumsForArtist($artistId);
        $existingSongs = $this->getExistingSongsForArtist($artistId);

        // Scan filesystem
        $foundAlbums = []; // name => ['name' => ..., 'path' => ...]
        $foundSongs = [];  // relativePath => ['file' => ..., 'path' => ..., 'relative_path' => ..., 'album' => ..., 'artist_id' => ...]

        $this->scanArtistFolder($artistDir, $artistId, $user, $foundAlbums, $foundSongs);

        // Sync albums
        foreach ($foundAlbums as $name => $data) {
            if (!isset($existingAlbums[$name])) {
                $stmt = $this->db->prepare('INSERT INTO albums (artist_id, name) VALUES (?, ?)');
                $stmt->execute([$artistId, $name]);
                $changes['new_albums'][] = $name;
            }
        }

        // Remove empty albums that no longer exist on disk
        foreach ($existingAlbums as $name => $albumId) {
            if (!isset($foundAlbums[$name])) {
                $stmt = $this->db->prepare('SELECT COUNT(*) FROM songs WHERE album_id = ?');
                $stmt->execute([$albumId]);
                if ($stmt->fetchColumn() == 0) {
                    $this->db->prepare('DELETE FROM albums WHERE id = ?')->execute([$albumId]);
                    $changes['removed_albums'][] = $name;
                }
            }
        }

        // Sync songs
        foreach ($foundSongs as $relativePath => $songData) {
            $fullPath = $songData['path'];
            $fileHash = $this->computeFileHash($fullPath);

            if (!isset($existingSongs[$relativePath])) {
                // New song — use full ID3 metadata
                $this->addSongWithID3($songData, $fileHash, $artistId);
                $changes['new_songs'][] = $songData['file'];
            } elseif ($existingSongs[$relativePath]['file_hash'] !== $fileHash) {
                // Changed song — update
                $this->updateSongWithID3($existingSongs[$relativePath]['id'], $songData, $fileHash);
                $changes['updated_songs'][] = $songData['file'];
            }
        }

        // Remove songs no longer on disk
        foreach ($existingSongs as $relativePath => $songData) {
            if (!isset($foundSongs[$relativePath])) {
                $this->db->prepare('DELETE FROM songs WHERE id = ?')->execute([$songData['id']]);
                $changes['removed_songs'][] = $songData['title'];
            }
        }

        // Update missing artwork
        $artworkUpdated = $this->updateArtworkForArtist($artistId, $foundAlbums);
        $changes['updated_artwork'] = $artworkUpdated;

        // Update missing album years from ID3
        $yearsUpdated = $this->updateAlbumYearsForArtist($artistId, $foundAlbums);
        $changes['updated_years'] = $yearsUpdated;

        // Update artist stats (album_count + song_count for this artist)
        $this->db->prepare('
            UPDATE artists SET album_count = (
                SELECT COUNT(*) FROM albums WHERE artist_id = ?
            ) WHERE id = ?
        ')->execute([$artistId, $artistId]);
        $this->db->prepare('
            UPDATE artists SET song_count = (
                SELECT COUNT(*) FROM songs s
                JOIN albums al ON s.album_id = al.id
                WHERE al.artist_id = ?
            ) WHERE id = ?
        ')->execute([$artistId, $artistId]);

        return $changes;
    }

    // =========================================================================
    // Mode 2b: Single Album Rescan
    // =========================================================================

    /**
     * Rescan all songs in a single album.
     * Re-reads ID3 metadata (with filename fallback), updates title/track_number/duration,
     * and writes back derived tags to the files when applicable.
     */
    public function scanAlbum(int $albumId, string $user): array {
        // Verify album belongs to user; fetch is_compilation flag
        $stmt = $this->db->prepare('
            SELECT al.id, al.name, al.is_compilation, ar.name AS artist_name
            FROM albums al
            JOIN artists ar ON al.artist_id = ar.id
            WHERE al.id = ? AND ar.user = ?
        ');
        $stmt->execute([$albumId, $user]);
        $album = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$album) {
            throw new Exception('Album not found');
        }

        $isCompilation = (bool)$album['is_compilation']
            || strtolower(trim($album['artist_name'])) === 'various artists';

        $stmt = $this->db->prepare('SELECT id, file_path, title, track_number FROM songs WHERE album_id = ?');
        $stmt->execute([$albumId]);
        $songs = $stmt->fetchAll(PDO::FETCH_ASSOC);

        if (empty($songs)) {
            return ['songs_updated' => 0, 'tags_written' => 0, 'errors' => 0,
                    'album' => $album['name'], 'artist' => $album['artist_name']];
        }

        $this->storage = StorageFactory::forUser($user);
        $this->scanPathBase = $this->storage->getPathBase();

        $updated     = 0;
        $tagsWritten = 0;
        $errors      = 0;

        foreach ($songs as $song) {
            $absPath = rtrim($this->scanPathBase, '/') . '/' . ltrim($song['file_path'], '/');

            if (!$this->storage->fileExists($absPath)) {
                echo "  MISSING: {$song['file_path']}\n";
                $errors++;
                continue;
            }

            $localPath = $this->getLocalPathForAnalysis($absPath);
            $metadata  = $this->extractBasicMetadata($localPath);
            $fileHash  = $this->computeFileHash($absPath);
            $this->cleanupTempFile($localPath, $absPath);

            $title = $metadata['title'] ?: pathinfo($song['file_path'], PATHINFO_FILENAME);

            // For compilations, resolve per-track artist_id from the derived artist name
            $trackArtistId = null;
            if ($isCompilation && !empty($metadata['artist'])) {
                $trackArtistNorm = strtolower(trim($metadata['artist']));
                if ($trackArtistNorm !== 'various artists') {
                    $trackArtistId = $this->getArtistId($metadata['artist'], $user);
                }
            }

            $this->db->prepare('
                UPDATE songs SET title = ?, track_number = ?, duration = ?, file_hash = ?, artist_id = ? WHERE id = ?
            ')->execute([$title, $metadata['trackNumber'], $metadata['duration'], $fileHash, $trackArtistId, $song['id']]);

            if (!empty($metadata['tagsToWrite']) &&
                ($this->storage === null || $this->storage->getType() !== 'sftp')) {
                $this->writeBackDerivedTags($absPath, $metadata['tagsToWrite']);
                $tagsWritten++;
            }

            $updated++;
        }

        return [
            'songs_updated' => $updated,
            'tags_written'  => $tagsWritten,
            'errors'        => $errors,
            'album'         => $album['name'],
            'artist'        => $album['artist_name'],
        ];
    }

    private function scanArtistFolder(string $artistPath, int $artistId, string $user, array &$foundAlbums, array &$foundSongs): void {
        $items = $this->storage->listDir($artistPath);

        foreach ($items as $item) {
            $itemPath = $artistPath . '/' . $item['name'];

            if ($item['is_dir']) {
                $foundAlbums[$item['name']] = ['name' => $item['name'], 'path' => $itemPath];
                $this->scanAlbumFolder($itemPath, $artistId, $item['name'], $user, $foundSongs);
            } elseif ($this->isAudioFile($item['name'])) {
                // Loose file in artist dir
                $relativePath = str_replace($this->scanPathBase . '/', '', $itemPath);
                $foundSongs[$relativePath] = [
                    'file' => $item['name'],
                    'path' => $itemPath,
                    'relative_path' => $relativePath,
                    'album' => 'Singles',
                    'artist_id' => $artistId,
                ];
            }
        }
    }

    private function scanAlbumFolder(string $albumPath, int $artistId, string $albumName, string $user, array &$foundSongs): void {
        $items = $this->storage->listDir($albumPath);

        foreach ($items as $item) {
            $filePath = $albumPath . '/' . $item['name'];

            if (!$item['is_dir'] && $this->isAudioFile($item['name'])) {
                $relativePath = str_replace($this->scanPathBase . '/', '', $filePath);
                $foundSongs[$relativePath] = [
                    'file' => $item['name'],
                    'path' => $filePath,
                    'relative_path' => $relativePath,
                    'album' => $albumName,
                    'artist_id' => $artistId,
                ];
            }
        }
    }

    private function addSongWithID3(array $songData, string $fileHash, int $artistId): void {
        $localPath = $this->getLocalPathForAnalysis($songData['path']);
        $metadata  = $this->extractBasicMetadata($localPath);
        $title     = $metadata['title'] ?: pathinfo($songData['file'], PATHINFO_FILENAME);
        $this->cleanupTempFile($localPath, $songData['path']);

        // Get or create album (with year from ID3)
        $stmt = $this->db->prepare('SELECT id, year FROM albums WHERE artist_id = ? AND name = ?');
        $stmt->execute([$artistId, $songData['album']]);
        $album = $stmt->fetch();

        if ($album) {
            $albumId = $album['id'];
            if (empty($album['year']) && $metadata['year']) {
                $this->db->prepare('UPDATE albums SET year = ? WHERE id = ?')->execute([$metadata['year'], $albumId]);
            }
        } else {
            $stmt = $this->db->prepare('INSERT INTO albums (artist_id, name, year) VALUES (?, ?, ?)');
            $stmt->execute([$artistId, $songData['album'], $metadata['year']]);
            $albumId = (int) $this->db->lastInsertId();
        }

        $stmt = $this->db->prepare('
            INSERT INTO songs (album_id, title, track_number, duration, file_path, file_hash)
            VALUES (?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
                album_id = VALUES(album_id),
                title = VALUES(title),
                track_number = VALUES(track_number),
                duration = VALUES(duration),
                file_hash = VALUES(file_hash)
        ');
        $stmt->execute([
            $albumId,
            $title,
            $metadata['trackNumber'],
            $metadata['duration'],
            $songData['relative_path'],
            $fileHash,
        ]);

        // Write back filename-derived tags if needed
        if (!empty($metadata['tagsToWrite']) &&
            ($this->storage === null || $this->storage->getType() !== 'sftp')) {
            $this->writeBackDerivedTags($songData['path'], $metadata['tagsToWrite']);
        }
    }

    private function updateSongWithID3(int $songId, array $songData, string $fileHash): void {
        $localPath = $this->getLocalPathForAnalysis($songData['path']);
        $metadata  = $this->extractBasicMetadata($localPath);
        $title     = $metadata['title'] ?: pathinfo($songData['file'], PATHINFO_FILENAME);
        $this->cleanupTempFile($localPath, $songData['path']);

        $stmt = $this->db->prepare('UPDATE songs SET title = ?, track_number = ?, duration = ?, file_hash = ? WHERE id = ?');
        $stmt->execute([$title, $metadata['trackNumber'], $metadata['duration'], $fileHash, $songId]);

        if (!empty($metadata['tagsToWrite']) &&
            ($this->storage === null || $this->storage->getType() !== 'sftp')) {
            $this->writeBackDerivedTags($songData['path'], $metadata['tagsToWrite']);
        }
    }

    private function getExistingAlbumsForArtist(int $artistId): array {
        $stmt = $this->db->prepare('SELECT id, name FROM albums WHERE artist_id = ?');
        $stmt->execute([$artistId]);
        $albums = [];
        while ($row = $stmt->fetch()) {
            $albums[$row['name']] = $row['id'];
        }
        return $albums;
    }

    private function getExistingSongsForArtist(int $artistId): array {
        $stmt = $this->db->prepare('
            SELECT s.id, s.file_path, s.file_hash, s.title, al.name as album_name
            FROM songs s
            JOIN albums al ON s.album_id = al.id
            WHERE al.artist_id = ?
        ');
        $stmt->execute([$artistId]);
        $songs = [];
        while ($row = $stmt->fetch()) {
            $songs[$row['file_path']] = $row;
        }
        return $songs;
    }

    /**
     * Update artwork for albums of a specific artist.
     * - Albums with no artwork: always fetch.
     * - Albums with existing artwork: refresh only if a cover file on disk
     *   (folder.jpg, cover.jpg, …) is newer than the cached JPEG.
     */
    private function updateArtworkForArtist(int $artistId, array $foundAlbums): array {
        $updated   = [];
        $cachePath = AppConfig::getDataPath() . '/cache/artwork';
        $coverFiles = ['folder.jpg', 'Folder.jpg', 'cover.jpg', 'Cover.jpg', 'front.jpg', 'album.jpg'];

        $stmt = $this->db->prepare('SELECT id, name FROM albums WHERE artist_id = ?');
        $stmt->execute([$artistId]);

        while ($album = $stmt->fetch()) {
            $albumId   = (int)$album['id'];
            $cacheFile = $cachePath . '/album_' . $albumId . '.jpg';
            $cacheMtime = @filemtime($cacheFile) ?: 0;

            $hasArtwork = $cacheMtime > 0;

            if (!$hasArtwork) {
                // No cache at all — run full artwork fetch
                if ($this->artworkManager->updateAlbumArtwork($albumId)) {
                    $updated[] = $album['name'];
                }
                continue;
            }

            // Has artwork — refresh only if a cover file on disk is newer
            if (!isset($foundAlbums[$album['name']])) continue;

            $albumPath = $foundAlbums[$album['name']]['path'];
            foreach ($coverFiles as $f) {
                $fullPath = $albumPath . '/' . $f;
                if ($this->storage->fileExists($fullPath)) {
                    $fileMtime = $this->storage->stat($fullPath)['mtime'] ?? 0;
                    if ($fileMtime > $cacheMtime) {
                        if ($this->artworkManager->updateAlbumArtwork($albumId)) {
                            $updated[] = $album['name'];
                        }
                        break;
                    }
                }
            }
        }

        return $updated;
    }

    /**
     * Update year for albums of a specific artist that have none, using ID3 tags.
     */
    private function updateAlbumYearsForArtist(int $artistId, array $foundAlbums): array {
        $updated = [];
        $stmt = $this->db->prepare('SELECT id, name FROM albums WHERE artist_id = ? AND (year IS NULL OR year = 0)');
        $stmt->execute([$artistId]);

        while ($album = $stmt->fetch()) {
            if (isset($foundAlbums[$album['name']])) {
                $albumPath = $foundAlbums[$album['name']]['path'];
                // Find first audio file in the album directory via storage
                $firstAudioFile = null;
                foreach ($this->storage->listDir($albumPath) as $item) {
                    if (!$item['is_dir'] && $this->isAudioFile($item['name'])) {
                        $firstAudioFile = $albumPath . '/' . $item['name'];
                        break;
                    }
                }
                if ($firstAudioFile !== null) {
                    $localPath = $this->getLocalPathForAnalysis($firstAudioFile);
                    $metadata  = $this->extractFullMetadata($localPath);
                    $this->cleanupTempFile($localPath, $firstAudioFile);
                    if ($metadata['year']) {
                        $this->db->prepare('UPDATE albums SET year = ? WHERE id = ?')->execute([$metadata['year'], $album['id']]);
                        $updated[] = $album['name'] . ' (' . $metadata['year'] . ')';
                    }
                }
            }
        }
        return $updated;
    }

    // =========================================================================
    // Mode 3: Artwork-only scan
    // =========================================================================

    /**
     * Update missing artwork for all albums of a user.
     * Checks folder cover files, then falls back to embedded ID3 APIC.
     */
    public function updateMissingArtwork(string $user): int {
        $stmt = $this->db->prepare('
            SELECT al.id, al.name, ar.name as artist_name
            FROM albums al
            JOIN artists ar ON al.artist_id = ar.id
            WHERE ar.user = ? AND (al.artwork IS NULL OR al.artwork = "" OR al.artwork NOT LIKE "album_%")
        ');
        $stmt->execute([$user]);

        $albums = $stmt->fetchAll();
        $total = count($albums);
        echo "  Found $total albums needing artwork cache\n";

        $updated = 0;
        foreach ($albums as $i => $album) {
            if (($i + 1) % 50 === 0 || $i === 0) {
                echo "  [{$i}/{$total}] Checking: {$album['artist_name']} / {$album['name']}\n";
            }

            if ($this->artworkManager->updateAlbumArtwork((int)$album['id'])) {
                $updated++;
            }
        }

        echo "  Updated artwork for $updated albums\n";
        return $updated;
    }

    // =========================================================================
    // Metadata extraction helpers
    // =========================================================================

    /**
     * Basic metadata for full library scan.
     * For local files, we use getID3 to get tags.
     * For SFTP, we try to be smart with the filename to avoid downloads.
     */
    private function extractBasicMetadata(string $filePath): array {
        $result = [
            'duration' => 0,
            'trackNumber' => 0,
            'artist' => null,
            'albumArtist' => null,
            'isCompilation' => false,
            'album' => null,
            'title' => null,
            'genre' => null,
            'year' => null,
            'tagsToWrite' => null,
        ];

        // For SFTP, skip ID3 — too expensive without local file access
        if ($this->storage !== null && $this->storage->getType() === 'sftp') {
            $basename = pathinfo($filePath, PATHINFO_FILENAME);
            if (preg_match('/^(.+?)\s+-\s+(\d{1,2})\s+-\s+(.+)$/', $basename, $m)) {
                $result['artist']      = trim($m[1]);
                $result['trackNumber'] = (int)$m[2];
                $result['title']       = trim($m[3]);
            } elseif (preg_match('/^(\d{1,2})\s*[-\.]\s*/', $basename, $m)) {
                $result['trackNumber'] = (int)$m[1];
            }
            return $result;
        }

        try {
            $fileInfo = $this->getID3->analyze($filePath);
            \getid3_lib::CopyTagsToComments($fileInfo);

            $result['duration'] = isset($fileInfo['playtime_seconds']) ? round($fileInfo['playtime_seconds']) : 0;
            
            // Track Number
            if (isset($fileInfo['comments']['track_number'][0])) {
                $result['trackNumber'] = intval($fileInfo['comments']['track_number'][0]);
            }

            if ($result['trackNumber'] == 0) {
                $filename = basename($filePath);
                if (preg_match('/^(\d{1,2})\s*[-\.]\s*/', $filename, $matches)) {
                    $result['trackNumber'] = intval($matches[1]);
                }
            }

            // Artist (TPE1), Album Artist (TPE2), Album, Title, Genre
            if (isset($fileInfo['comments']['artist'][0])) {
                $result['artist'] = $this->cleanArtistName($fileInfo['comments']['artist'][0]);
            }
            // TPE2 → getID3 maps it to 'band' after CopyTagsToComments
            if (isset($fileInfo['comments']['band'][0])) {
                $result['albumArtist'] = trim($fileInfo['comments']['band'][0]);
            } elseif (isset($fileInfo['comments']['album_artist'][0])) {
                $result['albumArtist'] = trim($fileInfo['comments']['album_artist'][0]);
            }
            // TCMP (iTunes compilation flag)
            if (isset($fileInfo['comments']['part_of_a_compilation'][0])) {
                $result['isCompilation'] = (int)$fileInfo['comments']['part_of_a_compilation'][0] === 1;
            } elseif (isset($fileInfo['id3v2']['TCMP'][0]['data'])) {
                $result['isCompilation'] = (int)$fileInfo['id3v2']['TCMP'][0]['data'] === 1;
            }
            if (isset($fileInfo['comments']['album'][0]))  $result['album']  = trim($fileInfo['comments']['album'][0]);
            if (isset($fileInfo['comments']['title'][0]))  $result['title']  = trim($fileInfo['comments']['title'][0]);
            if (isset($fileInfo['comments']['genre'][0]))  $result['genre']  = trim($fileInfo['comments']['genre'][0]);
            if (isset($fileInfo['comments']['year'][0]))   $result['year']   = trim($fileInfo['comments']['year'][0]);
            elseif (isset($fileInfo['comments']['date'][0])) $result['year'] = substr(trim($fileInfo['comments']['date'][0]), 0, 4);

            // Filename-based artist fallback: "Artist - NN - Title.mp3"
            // Triggers when TPE1 is absent, empty, or a generic placeholder
            $artistNorm = strtolower(trim($result['artist'] ?? ''));
            if ($result['artist'] === null || $result['artist'] === '' || $artistNorm === 'various artists') {
                $basename = pathinfo($filePath, PATHINFO_FILENAME);
                if (preg_match('/^(.+?)\s+-\s+(\d{1,2})\s+-\s+(.+)$/', $basename, $m)) {
                    $result['artist'] = trim($m[1]);
                    if ($result['trackNumber'] === 0) $result['trackNumber'] = (int)$m[2];
                    if ($result['title'] === null)    $result['title']       = trim($m[3]);
                    // Schedule tag write-back so future scans read proper metadata
                    $result['tagsToWrite'] = [
                        'artist'       => $result['artist'],
                        'title'        => $result['title'],
                        'track_number' => $result['trackNumber'] ?: null,
                        'album'        => $result['album'],
                        'album_artist' => $result['albumArtist'],
                        'genre'        => $result['genre'],
                        'year'         => $result['year'],
                    ];
                }
            }

            return $result;
        } catch (\Exception $e) {
            return $result;
        }
    }

    /**
     * Write derived tags (artist, title, etc.) back to the MP3 file using getID3.
     * Preserves any existing album/genre/year tags that were already present.
     * Only called for local files when artist was missing from ID3 but found in filename.
     */
    private function writeBackDerivedTags(string $filePath, array $tags): void {
        require_once AppConfig::getVendorPath() . '/getid3/write.php';

        if (!is_writable($filePath)) {
            echo "  [tag-write] Not writable: $filePath\n";
            return;
        }

        $tagwriter = new \getid3_writetags;
        $tagwriter->filename     = $filePath;
        $tagwriter->tagformats   = ['id3v2.3', 'id3v1'];
        $tagwriter->overwrite_tags = true;
        $tagwriter->tag_encoding = 'UTF-8';

        $tagData = [];
        if (!empty($tags['artist']))       $tagData['artist'][]       = $tags['artist'];
        if (!empty($tags['title']))        $tagData['title'][]        = $tags['title'];
        if (!empty($tags['album']))        $tagData['album'][]        = $tags['album'];
        if (!empty($tags['album_artist'])) $tagData['band'][]         = $tags['album_artist'];
        if (!empty($tags['genre']))        $tagData['genre'][]        = $tags['genre'];
        if (!empty($tags['year']))         $tagData['year'][]         = $tags['year'];
        if (!empty($tags['track_number'])) $tagData['track_number'][] = $tags['track_number'];

        $tagwriter->tag_data = $tagData;
        if (!$tagwriter->WriteTags()) {
            echo "  [tag-write] Error: " . implode(', ', $tagwriter->errors) . "\n";
        } else {
            echo "  [tag-write] " . basename($filePath) . "\n";
        }
    }

    /**
     * Cleans artist names to extract the primary artist (handles collaborations).
     */
    private function cleanArtistName(string $name): string {
        $name = trim($name);
        // Split by common separators: , ; / and common "feat" patterns
        $separators = ['/', ';', ',', ' feat.', ' Feat.', ' ft.', ' FT.', ' & '];
        
        foreach ($separators as $sep) {
            if (str_contains($name, $sep)) {
                $parts = explode($sep, $name);
                $name = trim($parts[0]);
            }
        }
        
        return $name ?: 'Artiste inconnu';
    }

    /**
     * Full metadata for artist scan (title, year, track number, duration).
     */
    private function extractFullMetadata(string $filePath): array {
        try {
            $fileInfo = $this->getID3->analyze($filePath);
            getid3_lib::CopyTagsToComments($fileInfo);

            $duration = isset($fileInfo['playtime_seconds']) ? round($fileInfo['playtime_seconds']) : 0;
            $trackNumber = 0;

            if (isset($fileInfo['comments']['track_number'][0])) {
                $trackNumber = intval($fileInfo['comments']['track_number'][0]);
            }

            if ($trackNumber == 0) {
                $filename = basename($filePath);
                if (preg_match('/^(\d{1,2})\s*[-\.]\s*/', $filename, $matches)) {
                    $trackNumber = intval($matches[1]);
                }
            }

            $year = $this->extractYear($fileInfo);

            return [
                'duration' => $duration,
                'trackNumber' => $trackNumber,
                'year' => $year,
            ];
        } catch (\Exception $e) {
            return ['duration' => 0, 'trackNumber' => 0, 'year' => null];
        }
    }

    /**
     * Extract song title from ID3 tags with filename fallback.
     */
    private function extractSongTitle(string $filePath, string $fallbackFilename): string {
        try {
            $fileInfo = $this->getID3->analyze($filePath);
            getid3_lib::CopyTagsToComments($fileInfo);

            $title = $fileInfo['comments']['title'][0] ?? null;
            if ($title && trim($title) !== '') {
                return trim($title);
            }
        } catch (\Exception $e) {
            // Fall through to filename
        }
        return $fallbackFilename;
    }

    /**
     * Extract year from ID3 tags (multi-level fallback).
     */
    private function extractYear(array $fileInfo): ?int {
        $year = null;

        if (isset($fileInfo['comments']['year'][0])) {
            $year = intval($fileInfo['comments']['year'][0]);
        } elseif (isset($fileInfo['comments']['date'][0])) {
            $year = intval(substr($fileInfo['comments']['date'][0], 0, 4));
        } elseif (isset($fileInfo['comments']['recording_time'][0])) {
            $year = intval(substr($fileInfo['comments']['recording_time'][0], 0, 4));
        } elseif (isset($fileInfo['id3v2']['TDRC'][0]['data'])) {
            $year = intval(substr($fileInfo['id3v2']['TDRC'][0]['data'], 0, 4));
        } elseif (isset($fileInfo['id3v2']['TYER'][0]['data'])) {
            $year = intval($fileInfo['id3v2']['TYER'][0]['data']);
        }

        // Validate year is reasonable
        if ($year && ($year < 1900 || $year > 2100)) {
            return null;
        }
        return $year ?: null;
    }

    public function updateArtistImagesForUser(string $user): void {
        $stmt = $this->db->prepare('
            SELECT id, name FROM artists 
            WHERE user = ? AND (image IS NULL OR image = "" OR image NOT LIKE "artist_%")
        ');
        $stmt->execute([$user]);

        $artists = $stmt->fetchAll();
        $total = count($artists);
        echo "  Found $total artists needing images\n";

        foreach ($artists as $i => $artist) {
            if (($i + 1) % 10 === 0 || $i === 0) {
                echo "  [{$i}/{$total}] Checking image for: {$artist['name']}\n";
            }

            $this->artworkManager->updateArtistImage((int)$artist['id']);
        }
    }

    // =========================================================================
    // Shared helpers
    // =========================================================================

    private function isAudioFile(string $path): bool {
        $ext = strtolower(pathinfo($path, PATHINFO_EXTENSION));
        return in_array($ext, $this->audioExtensions);
    }

    /**
     * Compute a file hash.
     * Local: MD5 of file contents. SFTP: MD5 of "size|mtime" (avoids full download).
     */
    private function computeFileHash(string $absPath): string {
        if ($this->storage->getType() === 'local') {
            return (string) @md5_file($absPath);
        }
        $s = $this->storage->stat($absPath);
        return md5($s['size'] . '|' . $s['mtime']);
    }

    /**
     * For SFTP: download the file to a temp location so getID3 can analyse it.
     * For local: return the path unchanged.
     * Caller is responsible for calling cleanupTempFile() afterward.
     */
    private function getLocalPathForAnalysis(string $absPath): string {
        if ($this->storage->getType() === 'local') {
            return $absPath;
        }
        $ext     = pathinfo($absPath, PATHINFO_EXTENSION);
        $tmpPath = sys_get_temp_dir() . '/gullify_' . uniqid() . '.' . $ext;
        $data    = $this->storage->readFile($absPath);
        file_put_contents($tmpPath, $data);
        return $tmpPath;
    }

    /**
     * Remove a temp file created by getLocalPathForAnalysis() if it differs from the original path.
     */
    private function cleanupTempFile(string $localPath, string $originalPath): void {
        if ($localPath !== $originalPath && file_exists($localPath)) {
            @unlink($localPath);
        }
    }

    private function loadUserCache(string $user): void {
        $this->artistCache[$user] = [];
        $this->existingSongPaths[$user] = [];

        $stmt = $this->db->prepare('SELECT id, name FROM artists WHERE user = ?');
        $stmt->execute([$user]);
        while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
            $this->artistCache[$user][$row['name']] = $row['id'];
        }

        $songStmt = $this->db->prepare('
            SELECT s.id, s.file_path, s.file_hash, al.name as album_name, ar.id as artist_id
            FROM songs s
            JOIN albums al ON s.album_id = al.id
            JOIN artists ar ON al.artist_id = ar.id
            WHERE ar.user = ?
        ');
        $songStmt->execute([$user]);

        while ($row = $songStmt->fetch(PDO::FETCH_ASSOC)) {
            $this->existingSongPaths[$user][$row['file_path']] = ['id' => $row['id'], 'hash' => $row['file_hash']];
            if (!isset($this->albumCache[$row['artist_id']])) {
                $this->albumCache[$row['artist_id']] = [];
            }
            if (!isset($this->albumCache[$row['artist_id']][$row['album_name']])) {
                $albumId = $this->getAlbumId($row['artist_id'], $row['album_name'], false);
                if ($albumId) {
                    $this->albumCache[$row['artist_id']][$row['album_name']] = $albumId;
                }
            }
        }
    }

    private function getArtistId(string $name, string $user, bool $autoCreate = true): ?int {
        if (isset($this->artistCache[$user][$name])) {
            return $this->artistCache[$user][$name];
        }
        if ($autoCreate) {
            $stmt = $this->db->prepare('INSERT INTO artists (name, user) VALUES (?, ?)');
            $stmt->execute([$name, $user]);
            $id = (int) $this->db->lastInsertId();
            $this->artistCache[$user][$name] = $id;
            return $id;
        }
        return null;
    }

    private function getAlbumId(int $artistId, string $name, bool $autoCreate = true, ?string $genre = null): ?int {
        if (isset($this->albumCache[$artistId][$name])) {
            return $this->albumCache[$artistId][$name];
        }
        if ($autoCreate) {
            $stmt = $this->db->prepare('INSERT INTO albums (artist_id, name, genre) VALUES (?, ?, ?)');
            $stmt->execute([$artistId, $name, $genre ?: null]);
            $id = (int) $this->db->lastInsertId();
            if (!isset($this->albumCache[$artistId])) $this->albumCache[$artistId] = [];
            $this->albumCache[$artistId][$name] = $id;
            return $id;
        }
        $stmt = $this->db->prepare('SELECT id FROM albums WHERE artist_id = ? AND name = ?');
        $stmt->execute([$artistId, $name]);
        $id = $stmt->fetchColumn() ?: null;
        // Update genre only if not already set (don't overwrite manual assignments)
        if ($id && $genre) {
            $this->db->prepare('UPDATE albums SET genre = ? WHERE id = ? AND (genre IS NULL OR genre = "")')
                     ->execute([$genre, $id]);
        }
        return $id ?: null;
    }

    private function updateArtistStatsForUser(string $user): void {
        echo "Updating artist statistics (album and song counts) for $user...\n";
        
        // Update album_count first
        $stmt = $this->db->prepare('
            UPDATE artists a
            SET a.album_count = (
                SELECT COUNT(*) FROM albums WHERE artist_id = a.id
            )
            WHERE a.user = ?
        ');
        $stmt->execute([$user]);

        // Then update song_count
        $stmt = $this->db->prepare('
            UPDATE artists a
            SET a.song_count = (
                SELECT COUNT(*) 
                FROM songs s 
                JOIN albums al ON s.album_id = al.id 
                WHERE al.artist_id = a.id
            )
            WHERE a.user = ?
        ');
        $stmt->execute([$user]);
        
        echo "Statistics updated.\n";
    }
}
