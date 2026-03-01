#!/usr/bin/env php
<?php
/**
 * Background worker to download album from YouTube Music
 * Reads download info from JSON file for proper handling of special characters
 */

if (php_sapi_name() !== 'cli') {
    die("This script must be run from command line\n");
}

if ($argc < 2) {
    die("Usage: download-worker.php <json_file>\n");
}

$statusFile = $argv[1];

if (!file_exists($statusFile)) {
    die("Status file not found: $statusFile\n");
}

// Read download info from JSON file
$statusData = json_decode(file_get_contents($statusFile), true);
if (!$statusData) {
    die("Failed to parse status file: $statusFile\n");
}

$downloadId = $statusData['id'] ?? basename($statusFile, '.json');
$url = $statusData['url'] ?? '';
$artist = $statusData['artist'] ?? '';
$album = $statusData['album'] ?? '';
$user = $statusData['user'] ?? '';
$artistId = $statusData['artist_id'] ?? '';

$logFile = str_replace('.json', '.log', $statusFile);

// Assurer que la locale est UTF-8 pour préserver les accents
setlocale(LC_ALL, 'en_CA.UTF-8', 'en_US.UTF-8', 'fr_CA.UTF-8', 'fr_FR.UTF-8', 'C.UTF-8');
putenv('LC_ALL=en_CA.UTF-8');

// Load app config
require_once __DIR__ . '/../src/AppConfig.php';
require_once __DIR__ . '/../src/Database.php';
require_once __DIR__ . '/../src/PathHelper.php';
require_once __DIR__ . '/../src/Storage/StorageInterface.php';
require_once __DIR__ . '/../src/Storage/LocalStorage.php';
require_once __DIR__ . '/../src/Storage/SFTPStorage.php';
require_once __DIR__ . '/../src/Storage/StorageFactory.php';

$config = AppConfig::getInstance();

// Fonction pour échapper les arguments shell en préservant l'UTF-8
function escapeShellArgUTF8($arg) {
    $escaped = str_replace("'", "'\\''", $arg);
    return "'" . $escaped . "'";
}

// Fonction pour nettoyer les noms de fichiers/dossiers
function sanitizeForPath($name) {
    $name = preg_replace('/\s*[\/\\\\]+\s*/', ' - ', $name);
    $name = preg_replace('/[<>:"|?*]/', '', $name);
    $name = str_replace("\\'", "'", $name);
    $name = str_replace("\\\\", "", $name);
    $name = preg_replace('/\s+/', ' ', $name);
    return trim($name);
}

// Appliquer la sanitization
$artist = sanitizeForPath($artist);
$album = sanitizeForPath($album);

// Mettre à jour les valeurs sanitisées
$statusData['artist'] = $artist;
$statusData['album'] = $album;
file_put_contents($statusFile, json_encode($statusData, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE));

// Fonction pour mettre à jour le statut
function updateStatus($statusFile, $downloadId, $artist, $album, $user, $artistId, $url, $status, $progress, $message) {
    $data = [
        'id' => $downloadId,
        'status' => $status,
        'progress' => $progress,
        'message' => $message,
        'artist' => $artist,
        'album' => $album,
        'user' => $user,
        'artist_id' => $artistId,
        'url' => $url,
        'updated_at' => date('Y-m-d H:i:s')
    ];
    $tmpFile = $statusFile . '.tmp';
    file_put_contents($tmpFile, json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE));
    chmod($tmpFile, 0666);
    rename($tmpFile, $statusFile);
}

// Déterminer le chemin de destination
$storage = StorageFactory::forUser($user);
$destPath = $storage->getMusicRoot();

if (!$destPath) {
    updateStatus($statusFile, $downloadId, $artist, $album, $user, $artistId, $url, 'error', 0, "User path not found: $user");
    exit(1);
}

// For SFTP users, download to a local temp dir first, then upload
$isSftp = $storage->getType() === 'sftp';
$dataPath = AppConfig::getDataPath();
$localTmpDir = $isSftp
    ? $dataPath . '/downloads/tmp_' . $downloadId
    : $destPath . '/' . $artist . '/' . $album;

$albumPath = $isSftp ? $localTmpDir : ($destPath . '/' . $artist . '/' . $album);

// Démarrer le téléchargement
updateStatus($statusFile, $downloadId, $artist, $album, $user, $artistId, $url, 'downloading', 10, 'Démarrage du téléchargement...');

// Créer le répertoire de destination (local)
if (!is_dir($albumPath)) {
    mkdir($albumPath, 0755, true);
}

// Escape special characters for shell
$escapedAlbumPath = escapeShellArgUTF8($albumPath . '/%(playlist_index)s - %(title)s.%(ext)s');

// For ffmpeg metadata
$escapedAlbum = str_replace(['\\', '"'], ['\\\\', '\\"'], $album);
$escapedArtist = str_replace(['\\', '"'], ['\\\\', '\\"'], $artist);

// Commande yt-dlp (no sudo in Docker - runs as www-data)
$command = 'yt-dlp -o ' . $escapedAlbumPath . ' ' .
           '-x --audio-format mp3 --audio-quality 320K ' .
           '--extractor-args "youtube:player-client=default,-tv_simply" ' .
           '--embed-thumbnail --embed-metadata ' .
           '--postprocessor-args "-metadata album=\"' . $escapedAlbum . '\" -metadata album_artist=\"' . $escapedArtist . '\"" ' .
           escapeShellArgUTF8($url) . ' 2>&1';

// Lancer yt-dlp et capturer la sortie
$descriptorspec = [
    0 => ["pipe", "r"],
    1 => ["pipe", "w"],
    2 => ["pipe", "w"]
];

$process = proc_open($command, $descriptorspec, $pipes);
$logHandle = fopen($logFile, 'w');

if (is_resource($process)) {
    fclose($pipes[0]);

    $currentSong = 0;
    $totalSongs = 0;

    while (!feof($pipes[1])) {
        $line = fgets($pipes[1]);
        if ($line === false) continue;

        fwrite($logHandle, $line);

        if (preg_match('/\[download\] Downloading item (\d+) of (\d+)/', $line, $matches)) {
            $currentSong = (int)$matches[1];
            $totalSongs = (int)$matches[2];
            $progress = 10 + (int)(($currentSong / $totalSongs) * 80);
            updateStatus($statusFile, $downloadId, $artist, $album, $user, $artistId, $url, 'downloading', $progress, "Téléchargement: $currentSong/$totalSongs chansons");
        }
    }

    fclose($pipes[1]);
    fclose($pipes[2]);
    fclose($logHandle);

    $exitCode = proc_close($process);

    // Check if files were actually downloaded
    $downloadedFiles = glob($albumPath . '/*.mp3');
    $hasFiles = !empty($downloadedFiles);

    file_put_contents($logFile, "\n\n=== POST-DOWNLOAD ===\n", FILE_APPEND);
    file_put_contents($logFile, "Exit code: $exitCode, Files found: " . count($downloadedFiles) . "\n", FILE_APPEND);

    if ($exitCode === 0 || $hasFiles) {
        // ── SFTP upload: move downloaded files to remote server ───────────────
        if ($isSftp && !empty($downloadedFiles)) {
            updateStatus($statusFile, $downloadId, $artist, $album, $user, $artistId, $url, 'scanning', 85, 'Envoi des fichiers vers le serveur SFTP...');
            $remoteAlbumPath = $destPath . '/' . $artist . '/' . $album;
            $uploadErrors = 0;
            foreach ($downloadedFiles as $localFile) {
                $remotePath = $remoteAlbumPath . '/' . basename($localFile);
                try {
                    $ok = $storage->writeFile($remotePath, $localFile);
                    if ($ok) {
                        @unlink($localFile);
                        file_put_contents($logFile, "Uploaded: " . basename($localFile) . "\n", FILE_APPEND);
                    } else {
                        $uploadErrors++;
                        file_put_contents($logFile, "Upload failed: " . basename($localFile) . "\n", FILE_APPEND);
                    }
                } catch (Exception $e) {
                    $uploadErrors++;
                    file_put_contents($logFile, "Upload error: " . $e->getMessage() . "\n", FILE_APPEND);
                }
            }
            // Clean up local temp dir
            if (is_dir($localTmpDir)) {
                array_map('unlink', glob($localTmpDir . '/*'));
                @rmdir($localTmpDir);
            }
            if ($uploadErrors > 0) {
                file_put_contents($logFile, "Upload completed with $uploadErrors error(s)\n", FILE_APPEND);
            }
        }

        $statusMsg = ($exitCode === 0)
            ? 'Téléchargement terminé, scan en cours...'
            : 'Téléchargement partiel (' . count($downloadedFiles) . ' fichiers), scan en cours...';
        updateStatus($statusFile, $downloadId, $artist, $album, $user, $artistId, $url, 'scanning', 90, $statusMsg);

        // Scan the new artist/album
        $db = new Database();

        if ($artistId === 'new' || empty($artistId)) {
            $realArtistId = $db->getOrCreateArtist($artist, $user);
            file_put_contents($logFile, "Artist ID resolved: $realArtistId for '$artist'\n", FILE_APPEND);

            // Scan via internal API
            $scanUrl = 'http://localhost/api/scan-artist.php?artist_id=' . urlencode($realArtistId) . '&user=' . urlencode($user);
            $scanOutput = shell_exec('curl -sf ' . escapeShellArgUTF8($scanUrl) . ' 2>&1');
            file_put_contents($logFile, "Scan output: $scanOutput\n", FILE_APPEND);
        } else {
            $scanUrl = 'http://localhost/api/scan-artist.php?artist_id=' . urlencode($artistId) . '&user=' . urlencode($user);
            $scanOutput = shell_exec('curl -sf ' . escapeShellArgUTF8($scanUrl) . ' 2>&1');
            file_put_contents($logFile, "Scan output: $scanOutput\n", FILE_APPEND);
        }

        $finalMsg = ($exitCode === 0)
            ? 'Téléchargement et scan terminés avec succès'
            : 'Terminé avec ' . count($downloadedFiles) . ' fichiers (certaines pistes ont échoué)';
        updateStatus($statusFile, $downloadId, $artist, $album, $user, $artistId, $url, 'completed', 100, $finalMsg);
    } else {
        updateStatus($statusFile, $downloadId, $artist, $album, $user, $artistId, $url, 'error', 0, "Échec du téléchargement (code: $exitCode)");
    }
} else {
    updateStatus($statusFile, $downloadId, $artist, $album, $user, $artistId, $url, 'error', 0, 'Impossible de lancer yt-dlp');
}

// Nettoyer les vieux fichiers (plus de 24h)
$files = glob($dataPath . '/downloads/*.{json,log}', GLOB_BRACE);
foreach ($files as $file) {
    if (filemtime($file) < time() - 86400) {
        @unlink($file);
    }
}

exit(0);
