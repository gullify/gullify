<?php
/**
 * Gullify - Scan API
 * Migrated from api-mysql.php
 */

require_once __DIR__ . '/../../src/AppConfig.php';
require_once __DIR__ . '/../../src/Database.php';

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST');
header('Access-Control-Allow-Headers: Content-Type');

$action = $_GET['action'] ?? '';

function sendSuccess($data = null) {
    echo json_encode(['success' => true, 'data' => $data]);
    exit;
}

function sendError($message) {
    echo json_encode(['success' => false, 'error' => $message]);
    exit;
}

/**
 * Normalize song data to camelCase for consistent API responses
 */
function normalizeSongData($row) {
    return [
        'id' => (int)$row['id'],
        'title' => $row['title'],
        'trackNumber' => (int)($row['track_number'] ?? 0),
        'duration' => (int)($row['duration'] ?? 0),
        'filePath' => $row['file_path'],
        'albumId' => (int)($row['album_id'] ?? 0),
        'album' => $row['album_name'] ?? null,
        'artworkUrl' => $row['artworkUrl'] ?? ('serve_image.php?album_id=' . ($row['album_id'] ?? 0)),
        'artistId' => (int)($row['artist_id'] ?? 0),
        'artist' => $row['artist_name'] ?? null,
    ];
}

try {
    $lockFile = AppConfig::getDataPath() . '/cache/music-scan.lock';
    $logFile = AppConfig::getDataPath() . '/logs/library-scan.log';
    $scanScript = AppConfig::getAppRoot() . '/scripts/scan-library.php';
    $genreScanScript = AppConfig::getAppRoot() . '/scripts/scan-genres.php';
    
    // Determine the best PHP binary to use for CLI scripts
    $phpBin = (PHP_BINARY && !str_contains(PHP_BINARY, 'apache')) ? PHP_BINARY : 'php';

    switch ($action) {
        case 'force_scan':
            $user = $_GET['user'] ?? null;

            if (file_exists($lockFile)) {
                $lockAge = time() - filemtime($lockFile);
                if ($lockAge > 1800) {
                    unlink($lockFile);
                } else {
                    sendError('Un scan est deja en cours. Veuillez patienter.');
                }
            }

            touch($lockFile);

            $logMsg = "\n========================================\n";
            $logMsg .= "Scan started: " . date('D M d Y H:i:s T') . "\n";
            $logMsg .= "Force scan requested\n";
            if ($user) {
                $logMsg .= "Scanning specific user: $user\n";
            }
            $logMsg .= "========================================\n";
            file_put_contents($logFile, $logMsg, FILE_APPEND);

            $cmd = $phpBin . ' ' . escapeshellarg($scanScript) . ' --clear';
            if ($user) {
                $cmd .= ' ' . escapeshellarg($user);
            }
            $cmd = '(' . $cmd . '; rm -f ' . escapeshellarg($lockFile) . ') >> ' . escapeshellarg($logFile) . ' 2>&1 &';

            exec($cmd);

            sendSuccess([
                'message' => 'Scan complet lance' . ($user ? " pour l'utilisateur $user" : ''),
                'user' => $user
            ]);
            break;

        case 'fast_scan':
            $user = $_GET['user'] ?? null;

            if (file_exists($lockFile)) {
                $lockAge = time() - filemtime($lockFile);
                if ($lockAge > 1800) {
                    unlink($lockFile);
                } else {
                    sendError('Un scan est deja en cours. Veuillez patienter.');
                }
            }

            touch($lockFile);

            $logMsg = "\n========================================\n";
            $logMsg .= "Scan started: " . date('D M d Y H:i:s T') . "\n";
            $logMsg .= "Fast mode: Skipping artwork extraction\n";
            if ($user) {
                $logMsg .= "Scanning specific user: $user\n";
            }
            $logMsg .= "========================================\n";
            file_put_contents($logFile, $logMsg, FILE_APPEND);

            $cmd = $phpBin . ' ' . escapeshellarg($scanScript) . ' --skip-artwork';
            if ($user) {
                $cmd .= ' ' . escapeshellarg($user);
            }
            $cmd = '(' . $cmd . '; rm -f ' . escapeshellarg($lockFile) . ') >> ' . escapeshellarg($logFile) . ' 2>&1 &';

            exec($cmd);

            sendSuccess([
                'message' => 'Scan rapide lance (structure seulement)' . ($user ? " pour l'utilisateur $user" : ''),
                'user' => $user
            ]);
            break;

        case 'artwork_scan':
            $user = $_GET['user'] ?? null;
            if (!$user) sendError('Le parametre user est requis.');

            if (file_exists($lockFile)) {
                $lockAge = time() - filemtime($lockFile);
                if ($lockAge > 1800) {
                    unlink($lockFile);
                } else {
                    sendError('Un scan est deja en cours. Veuillez patienter.');
                }
            }

            touch($lockFile);

            $logMsg = "\n========================================\n";
            $logMsg .= "Scan started: " . date('D M d Y H:i:s T') . "\n";
            $logMsg .= "Artwork-only scan for user: $user\n";
            $logMsg .= "========================================\n";
            file_put_contents($logFile, $logMsg, FILE_APPEND);

            $artworkScript = AppConfig::getAppRoot() . '/scripts/scan-artwork.php';
            $cmd = $phpBin . ' ' . escapeshellarg($artworkScript) . ' ' . escapeshellarg($user);
            $cmd = '(' . $cmd . '; rm -f ' . escapeshellarg($lockFile) . ') >> ' . escapeshellarg($logFile) . ' 2>&1 &';

            exec($cmd);

            sendSuccess([
                'message' => "Scan artwork lance pour l'utilisateur $user",
                'user' => $user
            ]);
            break;

        case 'scan_status':
            $isScanning = file_exists($lockFile);
            $progressFile = AppConfig::getDataPath() . '/cache/scan-progress.json';
            $progressData = null;
            if (file_exists($progressFile)) {
                $progressData = json_decode(file_get_contents($progressFile), true);
                // If the file is too old and we are not scanning, ignore it
                if (!$isScanning && (time() - $progressData['timestamp'] > 60)) {
                    $progressData = null;
                }
            }

            try {
                $db = new Database();
                $conn = $db->getConnection();

                $stmt = $conn->query('SELECT last_update FROM library_status ORDER BY id DESC LIMIT 1');
                $result = $stmt->fetch();
                $lastUpdate = $result ? $result['last_update'] : null;

                $responseData = [
                    'scanning' => $isScanning,
                    'progress' => $progressData,
                    'last_update' => $lastUpdate,
                    'last_update_formatted' => $lastUpdate ? date('Y-m-d H:i:s', $lastUpdate) : null,
                ];

                if ($lastUpdate) {
                    $timeAgo = time() - $lastUpdate;
                    $responseData['time_ago_seconds'] = $timeAgo;
                    $responseData['time_ago_minutes'] = round($timeAgo / 60);
                    $responseData['needs_update'] = $lastUpdate < (time() - 3600);
                } else {
                    $responseData['message'] = 'Aucun scan effectue';
                    $responseData['needs_update'] = true;
                }

                sendSuccess($responseData);
            } catch (Exception $dbError) {
                sendSuccess([
                    'scanning' => $isScanning,
                    'progress' => $progressData,
                    'last_update' => null,
                    'message' => 'Status du scan disponible',
                    'needs_update' => true
                ]);
            }
            break;

        case 'genre_scan':
            $user = $_GET['user'] ?? null;

            $genreLockFile = AppConfig::getDataPath() . '/cache/music-genre-scan.lock';
            if (file_exists($genreLockFile)) {
                $lockAge = time() - filemtime($genreLockFile);
                if ($lockAge > 1800) {
                    unlink($genreLockFile);
                } else {
                    sendError('Un scan de genres est deja en cours. Veuillez patienter.');
                }
            }

            $force = !empty($_GET['force']);
            $genreLogFile = AppConfig::getDataPath() . '/logs/genre-scan.log';
            $cmd = '(' . $phpBin . ' ' . escapeshellarg($genreScanScript);
            if ($user) {
                $cmd .= ' ' . escapeshellarg($user);
            }
            if ($force) {
                $cmd .= ' --force';
            }
            $cmd .= ') >> ' . escapeshellarg($genreLogFile) . ' 2>&1 &';

            exec($cmd);

            sendSuccess([
                'message' => 'Scan des genres lance' . ($user ? " pour l'utilisateur $user" : ''),
                'user' => $user
            ]);
            break;

        case 'genre_scan_status':
            $genreLockFile = AppConfig::getDataPath() . '/cache/music-genre-scan.lock';
            $progressFile = AppConfig::getDataPath() . '/cache/genre-scan-progress.json';
            $isScanning = file_exists($genreLockFile);

            $progress = null;
            if (file_exists($progressFile)) {
                $raw = file_get_contents($progressFile);
                $progress = json_decode($raw, true);
            }

            sendSuccess([
                'scanning' => $isScanning,
                'progress' => $progress ?: [
                    'status' => $isScanning ? 'starting' : 'idle',
                    'processed' => 0,
                    'total' => 0,
                    'percent' => 0,
                    'current_artist' => ''
                ]
            ]);
            break;

        case 'set_artist_genre':
            $artistId = $_POST['artist_id'] ?? null;
            $genre = $_POST['genre'] ?? null;
            $applyToAlbums = ($_POST['apply_to_albums'] ?? '0') === '1';

            if (!$artistId) {
                sendError('artist_id is required');
            }

            $db = new Database();
            $conn = $db->getConnection();

            $stmt = $conn->prepare('UPDATE artists SET genre = ? WHERE id = ?');
            $stmt->execute([$genre ?: null, $artistId]);

            $albumsUpdated = 0;
            if ($applyToAlbums && $genre) {
                $stmt = $conn->prepare('UPDATE albums SET genre = ? WHERE artist_id = ?');
                $stmt->execute([$genre, $artistId]);
                $albumsUpdated = $stmt->rowCount();
            }

            $db->close();

            sendSuccess([
                'message' => 'Genre mis a jour',
                'artist_id' => $artistId,
                'genre' => $genre,
                'albums_updated' => $albumsUpdated
            ]);
            break;

        case 'track_play':
            $songId = $_POST['song_id'] ?? null;
            $user = $_POST['user'] ?? null;
            $duration = $_POST['duration'] ?? 0;
            $completed = $_POST['completed'] ?? false;
            $source = $_POST['source'] ?? 'player';

            if (!$songId || !$user) {
                sendError('song_id and user are required');
            }

            $db = new Database();
            $result = $db->trackPlay($songId, $user, $duration, $completed, $source);
            $db->close();

            if ($result) {
                sendSuccess(['message' => 'Play tracked successfully']);
            } else {
                sendError('Failed to track play');
            }
            break;

        case 'get_top_songs':
            $limit = $_GET['limit'] ?? 50;
            $user = $_GET['user'] ?? null;

            $db = new Database();
            $topSongs = $db->getTopSongs($limit, $user);
            $db->close();

            sendSuccess($topSongs);
            break;

        case 'get_recent_plays':
            $limit = $_GET['limit'] ?? 50;
            $user = $_GET['user'] ?? null;

            $db = new Database();
            $recentPlays = $db->getRecentPlays($limit, $user);
            $db->close();

            sendSuccess($recentPlays);
            break;

        case 'get_favorites':
            $user = $_GET['user'] ?? null;
            if (!$user) sendError('User parameter is required');

            $db = new Database();
            $favorites = $db->getFavorites($user);
            $db->close();

            $normalizedFavorites = array_map('normalizeSongData', $favorites);
            sendSuccess($normalizedFavorites);
            break;

        case 'toggle_favorite':
            $user = $_POST['user'] ?? null;
            $songId = $_POST['song_id'] ?? null;
            if (!$user || !$songId) sendError('User and song_id parameters are required');

            $db = new Database();
            $isFavorite = $db->isFavorite($songId, $user);
            if ($isFavorite) {
                $db->removeFromFavorites($songId, $user);
                $newState = 'removed';
            } else {
                $db->addToFavorites($songId, $user);
                $newState = 'added';
            }
            $db->close();
            sendSuccess(['status' => $newState]);
            break;

        case 'get_playlists':
            $user = $_GET['user'] ?? null;
            if (!$user) sendError('User parameter is required');

            $db = new Database();
            $playlists = $db->getPlaylists($user);
            $db->close();
            sendSuccess($playlists);
            break;

        case 'create_playlist':
            $user = $_POST['user'] ?? null;
            $name = $_POST['name'] ?? null;
            if (!$user || !$name) sendError('User and name parameters are required');

            $db = new Database();
            $playlistId = $db->createPlaylist($name, $user);
            $db->close();

            if ($playlistId) {
                sendSuccess(['id' => $playlistId, 'name' => $name, 'user' => $user]);
            } else {
                sendError('Failed to create playlist.');
            }
            break;

        case 'rename_playlist':
            $user = $_POST['user'] ?? null;
            $playlistId = $_POST['playlist_id'] ?? null;
            $newName = $_POST['name'] ?? null;
            if (!$user || !$playlistId || !$newName) sendError('User, playlist_id, and name parameters are required');

            $db = new Database();
            $result = $db->renamePlaylist($playlistId, $newName, $user);
            $db->close();

            if ($result) {
                sendSuccess(['message' => 'Playlist renamed.']);
            } else {
                sendError('Failed to rename playlist or permission denied.');
            }
            break;

        case 'delete_playlist':
            $user = $_POST['user'] ?? null;
            $playlistId = $_POST['playlist_id'] ?? null;
            if (!$user || !$playlistId) sendError('User and playlist_id parameters are required');

            $db = new Database();
            $result = $db->deletePlaylist($playlistId, $user);
            $db->close();

            if ($result) {
                sendSuccess(['message' => 'Playlist deleted.']);
            } else {
                sendError('Failed to delete playlist or permission denied.');
            }
            break;

        case 'get_playlist_songs':
            $user = $_GET['user'] ?? null;
            $playlistId = $_GET['playlist_id'] ?? null;
            if (!$user || !$playlistId) sendError('User and playlist_id parameters are required');

            $db = new Database();
            $songs = $db->getPlaylistSongs($playlistId, $user);
            $db->close();

            if ($songs === false) {
                sendError('Playlist not found or permission denied.');
            } else {
                $normalizedSongs = array_map('normalizeSongData', $songs);
                sendSuccess($normalizedSongs);
            }
            break;

        case 'add_to_playlist':
            $user = $_POST['user'] ?? null;
            $playlistId = $_POST['playlist_id'] ?? null;
            $songId = $_POST['song_id'] ?? null;
            if (!$user || !$playlistId || !$songId) sendError('User, playlist_id, and song_id parameters are required');

            $db = new Database();
            $result = $db->addToPlaylist($playlistId, $songId);
            $db->close();

            if ($result) {
                sendSuccess(['message' => 'Song added to playlist.']);
            } else {
                sendError('Failed to add song to playlist.');
            }
            break;

        case 'remove_from_playlist':
            $user = $_POST['user'] ?? null;
            $playlistSongId = $_POST['playlist_song_id'] ?? null;
            if (!$user || !$playlistSongId) sendError('User and playlist_song_id parameters are required');

            $db = new Database();
            $result = $db->removeFromPlaylist($playlistSongId, $user);
            $db->close();

            if ($result) {
                sendSuccess(['message' => 'Song removed from playlist.']);
            } else {
                sendError('Failed to remove song from playlist or permission denied.');
            }
            break;

        case 'add_favorite':
            $user = $_POST['user'] ?? null;
            $songId = $_POST['song_id'] ?? null;
            if (!$user || !$songId) sendError('User and song_id parameters are required');

            $db = new Database();
            $result = $db->addToFavorites($songId, $user);
            $db->close();
            if ($result) {
                sendSuccess(['message' => 'Song added to favorites.']);
            } else {
                sendError('Failed to add song to favorites.');
            }
            break;

        case 'remove_favorite':
            $user = $_POST['user'] ?? null;
            $songId = $_POST['song_id'] ?? null;
            if (!$user || !$songId) sendError('User and song_id parameters are required');

            $db = new Database();
            $result = $db->removeFromFavorites($songId, $user);
            $db->close();
            if ($result) {
                sendSuccess(['message' => 'Song removed from favorites.']);
            } else {
                sendError('Failed to remove song from favorites.');
            }
            break;

        // ========== ARTIST FAVORITES ==========

        case 'toggle_favorite_artist':
            $user = $_POST['user'] ?? null;
            $artistId = $_POST['artist_id'] ?? null;
            if (!$user || !$artistId) sendError('User and artist_id parameters are required');

            $db = new Database();
            $isFavorite = $db->isArtistFavorite($artistId, $user);
            if ($isFavorite) {
                $db->removeArtistFromFavorites($artistId, $user);
                $newState = 'removed';
            } else {
                $db->addArtistToFavorites($artistId, $user);
                $newState = 'added';
            }
            $db->close();
            sendSuccess(['status' => $newState, 'isFavorite' => $newState === 'added']);
            break;

        case 'is_artist_favorite':
            $user = $_GET['user'] ?? null;
            $artistId = $_GET['artist_id'] ?? null;
            if (!$user || !$artistId) sendError('User and artist_id parameters are required');

            $db = new Database();
            $isFavorite = $db->isArtistFavorite($artistId, $user);
            $db->close();
            sendSuccess(['isFavorite' => $isFavorite]);
            break;

        case 'get_favorite_artists':
            $user = $_GET['user'] ?? null;
            if (!$user) sendError('User parameter is required');

            $db = new Database();
            $artists = $db->getFavoriteArtists($user);
            $db->close();
            sendSuccess($artists);
            break;

        // ========== ALBUM FAVORITES ==========

        case 'toggle_favorite_album':
            $user = $_POST['user'] ?? null;
            $albumId = $_POST['album_id'] ?? null;
            if (!$user || !$albumId) sendError('User and album_id parameters are required');

            $db = new Database();
            $isFavorite = $db->isAlbumFavorite($albumId, $user);
            if ($isFavorite) {
                $db->removeAlbumFromFavorites($albumId, $user);
                $newState = 'removed';
            } else {
                $db->addAlbumToFavorites($albumId, $user);
                $newState = 'added';
            }
            $db->close();
            sendSuccess(['status' => $newState, 'isFavorite' => $newState === 'added']);
            break;

        case 'is_album_favorite':
            $user = $_GET['user'] ?? null;
            $albumId = $_GET['album_id'] ?? null;
            if (!$user || !$albumId) sendError('User and album_id parameters are required');

            $db = new Database();
            $isFavorite = $db->isAlbumFavorite($albumId, $user);
            $db->close();
            sendSuccess(['isFavorite' => $isFavorite]);
            break;

        case 'get_favorite_albums':
            $user = $_GET['user'] ?? null;
            if (!$user) sendError('User parameter is required');

            $db = new Database();
            $albums = $db->getFavoriteAlbums($user);
            $db->close();
            sendSuccess($albums);
            break;

        // ========== ALL FAVORITES ==========

        case 'get_all_favorites':
            $user = $_GET['user'] ?? null;
            if (!$user) sendError('User parameter is required');

            $db = new Database();
            $songs = $db->getFavorites($user);
            $data = [
                'artists' => $db->getFavoriteArtists($user),
                'albums' => $db->getFavoriteAlbums($user),
                'songs' => array_map('normalizeSongData', $songs)
            ];
            $db->close();
            sendSuccess($data);
            break;

        case 'cleanup_orphans':
            $user = $_GET['user'] ?? $_POST['user'] ?? null;
            if (!$user) sendError('User parameter is required');

            $db = new Database();
            $conn = $db->getConnection();

            // Remove albums (for this user) that have no songs
            $stmt = $conn->prepare("
                DELETE al FROM albums al
                JOIN artists ar ON al.artist_id = ar.id
                WHERE ar.user = :user
                AND al.id NOT IN (SELECT DISTINCT album_id FROM songs)
            ");
            $stmt->execute([':user' => $user]);
            $albumsDeleted = $stmt->rowCount();

            // Remove artists (for this user) that have no albums
            $stmt = $conn->prepare("
                DELETE FROM artists
                WHERE user = :user
                AND id NOT IN (SELECT DISTINCT artist_id FROM albums)
            ");
            $stmt->execute([':user' => $user]);
            $artistsDeleted = $stmt->rowCount();

            $db->close();

            sendSuccess([
                'message'         => "Nettoyage terminé : {$artistsDeleted} artiste(s) et {$albumsDeleted} album(s) supprimés",
                'artists_deleted' => $artistsDeleted,
                'albums_deleted'  => $albumsDeleted,
            ]);
            break;

        default:
            sendError('Action non reconnue');
    }
} catch (Exception $e) {
    sendError('Erreur: ' . $e->getMessage());
}
