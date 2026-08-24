<?php
/**
 * Gullify - Download Album API
 * Manages YouTube album downloads in background
 * Migrated from download_album_api.php
 */

require_once __DIR__ . '/../../src/AppConfig.php';

header('Content-Type: application/json');

$action = $_GET['action'] ?? $_POST['action'] ?? 'list';

// Ensure locale is UTF-8 to preserve accents
setlocale(LC_ALL, 'en_CA.UTF-8', 'en_US.UTF-8', 'fr_CA.UTF-8', 'fr_FR.UTF-8', 'C.UTF-8');
putenv('LC_ALL=en_CA.UTF-8');

$downloadDir = AppConfig::getDataPath() . '/downloads/';
$queueScript = AppConfig::getAppRoot() . '/scripts/process-queue.sh';

// Ensure download directory exists
if (!is_dir($downloadDir)) {
    @mkdir($downloadDir, 0755, true);
}

function sanitizeForPath($name) {
    $name = preg_replace('/\s*[\/\\\\]+\s*/', ' - ', $name);
    $name = preg_replace('/[<>:"|?*]/', '', $name);
    $name = preg_replace('/\s+/', ' ', $name);
    return trim($name);
}

/**
 * Clé de comparaison souple d'un nom d'artiste/album/titre : casse, accents,
 * ponctuation et espaces multiples ignorés. « Cœur de pirate » et
 * « Coeur De Pirate » désignent le même artiste.
 */
function normalizeName($name) {
    $name = (string) $name;
    $name = str_replace(['œ', 'Œ', 'æ', 'Æ'], ['oe', 'oe', 'ae', 'ae'], $name);
    if (function_exists('transliterator_transliterate')) {
        $t = transliterator_transliterate('Any-Latin; Latin-ASCII; Lower()', $name);
        if ($t !== false) $name = $t;
    } else {
        $t = @iconv('UTF-8', 'ASCII//TRANSLIT', $name);
        if ($t !== false) $name = $t;
    }
    $name = mb_strtolower($name, 'UTF-8');
    $name = preg_replace('/[^a-z0-9]+/', ' ', $name);
    return trim(preg_replace('/\s+/', ' ', $name));
}

/**
 * Albums déjà présents dans la bibliothèque de [$user], indexés par
 * « artiste|album » normalisé => nombre de pistes.
 */
function libraryAlbumIndex($user) {
    static $cache = [];
    if (isset($cache[$user])) return $cache[$user];

    $index = [];
    try {
        $db = AppConfig::getDB();
        $stmt = $db->prepare('
            SELECT ar.name AS artist, al.name AS album, COUNT(s.id) AS tracks
            FROM albums al
            JOIN artists ar ON ar.id = al.artist_id
            LEFT JOIN songs s ON s.album_id = al.id
            WHERE ar.user = ?
            GROUP BY al.id
        ');
        $stmt->execute([$user]);
        foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
            if ((int) $row['tracks'] === 0) continue; // album fantôme, pas un doublon
            $key = normalizeName($row['artist']) . '|' . normalizeName($row['album']);
            $index[$key] = [
                'artist'      => $row['artist'],
                'album'       => $row['album'],
                'track_count' => (int) $row['tracks'],
            ];
        }
    } catch (Throwable $e) {
        error_log('download.php: index bibliothèque indisponible — ' . $e->getMessage());
    }

    return $cache[$user] = $index;
}

/**
 * Titres déjà présents pour les artistes cités, sous forme d'ensemble
 * « artiste|titre » normalisé (annotation des chansons trouvées sur YouTube).
 *
 * @param string[] $artistNames
 */
function librarySongIndex($user, array $artistNames) {
    $artistNames = array_values(array_unique(array_filter(array_map('trim', $artistNames))));
    if (!$artistNames) return [];

    $index = [];
    try {
        $db = AppConfig::getDB();
        $ph = implode(',', array_fill(0, count($artistNames), '?'));
        $stmt = $db->prepare("
            SELECT ar.name AS artist, s.title, s.track_artist
            FROM songs s
            JOIN albums al ON al.id = s.album_id
            JOIN artists ar ON ar.id = al.artist_id
            WHERE ar.user = ? AND (ar.name IN ($ph) OR s.track_artist IN ($ph))
        ");
        $stmt->execute(array_merge([$user], $artistNames, $artistNames));
        foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
            $title = normalizeName($row['title']);
            $index[normalizeName($row['artist']) . '|' . $title] = true;
            if (!empty($row['track_artist'])) {
                $index[normalizeName($row['track_artist']) . '|' . $title] = true;
            }
        }
    } catch (Throwable $e) {
        error_log('download.php: index des titres indisponible — ' . $e->getMessage());
    }

    return $index;
}

/**
 * Téléchargement du même album déjà en file (ou en cours) pour cet
 * utilisateur — un double appui ne doit pas le lancer deux fois.
 *
 * @return array|null
 */
function findQueuedDownload($downloadDir, $user, $artist, $album, $url) {
    $wanted = normalizeName($artist) . '|' . normalizeName($album);
    foreach (glob($downloadDir . 'dl_*.json') as $file) {
        $data = json_decode((string) @file_get_contents($file), true);
        if (!is_array($data)) continue;
        if (($data['user'] ?? '') !== $user) continue;
        if (!in_array($data['status'] ?? '', ['queued', 'downloading', 'scanning'], true)) continue;

        $sameAlbum = ($artist !== '' && $album !== '')
            && (normalizeName($data['artist'] ?? '') . '|' . normalizeName($data['album'] ?? '')) === $wanted;
        $sameUrl = $url !== '' && ($data['url'] ?? '') === $url;
        if ($sameAlbum || $sameUrl) {
            return [
                'kind'        => 'queue',
                'artist'      => $data['artist'] ?? $artist,
                'album'       => $data['album'] ?? $album,
                'download_id' => $data['id'] ?? '',
                'status'      => $data['status'] ?? '',
            ];
        }
    }
    return null;
}

/**
 * Doublon éventuel pour cette demande : déjà en file, ou déjà rangé dans la
 * bibliothèque. Renvoie null si la voie est libre.
 *
 * [$title] n'est renseigné que pour une chanson seule : on compare alors le
 * titre, pas l'album (elles atterrissent toutes dans « Singles », qui
 * ressemblerait sinon à un doublon dès la deuxième chanson d'un artiste).
 */
function findDuplicate($downloadDir, $user, $artist, $album, $url, $title = '') {
    $queued = findQueuedDownload($downloadDir, $user, $artist, $album, $url);
    if ($queued) return $queued;

    if ($title !== '' && $artist !== '') {
        $songs = librarySongIndex($user, [$artist]);
        if (isset($songs[normalizeName($artist) . '|' . normalizeName($title)])) {
            return ['kind' => 'song', 'artist' => $artist, 'album' => $title];
        }
        return null;
    }

    if ($artist === '' || $album === '') return null;

    $index = libraryAlbumIndex($user);
    $key = normalizeName($artist) . '|' . normalizeName($album);
    if (isset($index[$key])) {
        return [
            'kind'        => 'library',
            'artist'      => $index[$key]['artist'],
            'album'       => $index[$key]['album'],
            'track_count' => $index[$key]['track_count'],
        ];
    }
    return null;
}

/**
 * Nouvelles sorties YouTube Music (albums seulement), en cache 3 h : la page
 * est la même pour tout le monde et l'appel python coûte plusieurs secondes.
 * On rend toujours la page entière — c'est rankNewReleases() qui la reclasse
 * par utilisateur, et l'appelant qui tranche.
 */
function fetchNewReleases() {
    $cacheFile = AppConfig::getDataPath() . '/cache/yt_new_releases.json';
    $stale = null;
    if (is_readable($cacheFile)) {
        $cached = json_decode((string) @file_get_contents($cacheFile), true);
        if (is_array($cached) && $cached) {
            if (time() - (int) @filemtime($cacheFile) < 3 * 3600) {
                return $cached;
            }
            $stale = $cached; // périmé : filet si YouTube ne répond pas
        }
    }

    $pythonScript = AppConfig::getPythonPath() . '/ytmusic_search.py';
    $pythonBin    = file_exists('/opt/ytdlp/bin/python3') ? '/opt/ytdlp/bin/python3' : 'python3';
    $output = shell_exec(
        $pythonBin . ' ' . escapeshellarg($pythonScript) . ' new_releases 100 2>/dev/null'
    );
    $data = $output ? json_decode($output, true) : null;
    $albums = array_values(array_filter(array_map(fn($r) => [
        'title'     => $r['title']     ?? '',
        'artist'    => $r['artist']    ?? '',
        'year'      => $r['year']      ?? '',
        'thumbnail' => $r['thumbnail'] ?? '',
        'browseId'  => $r['browseId']  ?? '',
    ], $data['results'] ?? []), fn($a) => $a['browseId'] !== '' && $a['title'] !== ''));

    if (!$albums) {
        return $stale ?: [];
    }

    if (!is_dir(dirname($cacheFile))) {
        @mkdir(dirname($cacheFile), 0775, true);
    }
    @file_put_contents($cacheFile, json_encode($albums, JSON_UNESCAPED_UNICODE));
    return $albums;
}

/**
 * Les sorties récentes des artistes que [$user] possède déjà, trouvées hors
 * ligne par scripts/refresh-new-releases.php.
 *
 * C'est la vraie source de « Nouveautés ». La page publique de YouTube Music
 * (voir fetchNewReleases) est un fourre-tout mondial qui ne bouge presque pas
 * et ne ressemble en rien à ce que l'app YouTube Music affiche ; elle ne sert
 * plus que de remplissage quand cette liste-ci est courte.
 */
function personalNewReleases($user) {
    if ($user === '') return [];
    $file = AppConfig::getDataPath() . '/cache/personal_new_releases.json';
    if (!is_readable($file)) return [];
    $all = json_decode((string) @file_get_contents($file), true);
    if (!is_array($all)) return [];

    $mine = [];
    foreach ($all as $entry) {
        if (!is_array($entry) || ($entry['user'] ?? '') !== $user) continue;
        $mine[] = [
            'title'     => $entry['title']     ?? '',
            'artist'    => $entry['artist']    ?? '',
            'year'      => (string) ($entry['year'] ?? ''),
            'thumbnail' => $entry['thumbnail'] ?? '',
            'browseId'  => $entry['browseId']  ?? '',
            'becauseOf' => $entry['becauseOf'] ?? '',
        ];
    }
    // Le script écrit déjà du plus récent au plus ancien ; on le refait ici
    // parce que le filtrage par utilisateur ne garantit pas l'ordre du fichier.
    usort($mine, fn($a, $b) => (int) $b['year'] <=> (int) $a['year']);
    return $mine;
}

/**
 * Les artistes de la bibliothèque de [$user], normalisés, en ensemble.
 */
function libraryArtistSet($user) {
    if ($user === '') return [];
    $artists = [];
    foreach (libraryAlbumIndex($user) as $entry) {
        $artists[normalizeName($entry['artist'])] = true;
    }
    unset($artists['']);
    return $artists;
}

/**
 * Les artistes crédités sur une sortie : YouTube les colle en une seule
 * chaîne (« A, B & C », « A feat. B »), qu'il faut redécouper pour espérer
 * reconnaître l'un d'eux dans la bibliothèque.
 *
 * @return string[] noms normalisés
 */
function splitArtistNames($credit) {
    $parts = preg_split(
        '/\s*(?:,|&|\/|\bfeat\.?\b|\bft\.?\b|\bwith\b|\bavec\b|\bx\b)\s*/iu',
        (string) $credit
    ) ?: [];
    $names = [];
    foreach ($parts as $part) {
        $name = normalizeName($part);
        if ($name !== '') $names[] = $name;
    }
    return $names;
}

/**
 * Reclasse les nouveautés par pertinence pour [$user].
 *
 * YouTube sert la même page mondiale à tout le monde : préciser le pays n'y
 * change rien (CA, US, FR et JP renvoient les mêmes albums), d'où le mélange
 * de Schlager allemand, de pièces radiophoniques et de mixes de DJ qui rendait
 * la liste si étrange. Faute de pouvoir la filtrer à la source, on la trie :
 * en tête les artistes déjà écoutés, en queue le bruit et ce qu'on possède
 * déjà. Rien n'est jeté — l'ordre de YouTube départage les ex æquo (tri stable
 * depuis PHP 8) et « Charger plus » finit par tout montrer.
 */
function rankNewReleases($user, array $albums) {
    $known = libraryArtistSet($user);

    // Sorties qui ne sont pas vraiment de la musique à écouter : pièces
    // radiophoniques allemandes (« Folge 12 : … »), mixes de club, karaoké,
    // musique de gym et compilations d'échantillons.
    $noise = '/\b(folge\s*\d+|h(ö|o)rspiel|dj\s?mix|megamix|club\s?mix|karaok|'
           . 'workout|fitness|aerobic|sampler|nightcore)\b/iu';
    // Alphabet non latin : illisible pour un francophone, donc en fin de liste.
    $foreign = '/[\p{Cyrillic}\p{Arabic}\p{Devanagari}\p{Han}\p{Hangul}'
             . '\p{Hiragana}\p{Katakana}\p{Hebrew}\p{Thai}\p{Bengali}'
             . '\p{Tamil}\p{Telugu}\p{Greek}]/u';

    foreach ($albums as &$album) {
        $credit = $album['artist'] ?? '';
        $album['known_artist'] = false;
        foreach (splitArtistNames($credit) as $name) {
            if (isset($known[$name])) {
                $album['known_artist'] = true;
                break;
            }
        }

        $text  = $credit . ' ' . ($album['title'] ?? '');
        $score = 0;
        if ($album['known_artist'])           $score += 3;
        if (!empty($album['in_library']))     $score -= 4; // déjà rangé ici
        if (preg_match($noise, $text))        $score -= 1;
        if (preg_match($foreign, $text))      $score -= 1;
        $album['_score'] = $score;
    }
    unset($album);

    usort($albums, fn($a, $b) => $b['_score'] <=> $a['_score']);
    return array_map(function ($album) {
        unset($album['_score']);
        return $album;
    }, $albums);
}

/**
 * Marque d'un `in_library` les albums trouvés sur YouTube qui sont déjà dans
 * la bibliothèque : la pastille évite de les retélécharger par distraction.
 */
function markAlbumsInLibrary($user, array $albums) {
    if ($user === '' || !$albums) return $albums;
    $index = libraryAlbumIndex($user);
    foreach ($albums as &$album) {
        $key = normalizeName($album['artist'] ?? '') . '|' . normalizeName($album['title'] ?? '');
        $album['in_library'] = isset($index[$key]);
    }
    return $albums;
}

/** Idem pour les chansons trouvées à l'unité. */
function markSongsInLibrary($user, array $songs) {
    if ($user === '' || !$songs) return $songs;
    $index = librarySongIndex($user, array_column($songs, 'artist'));
    foreach ($songs as &$song) {
        $key = normalizeName($song['artist'] ?? '') . '|' . normalizeName($song['title'] ?? '');
        $song['in_library'] = isset($index[$key]);
    }
    return $songs;
}

/** Message affiché à l'utilisateur quand on refuse un doublon. */
function duplicateMessage(array $dup) {
    if (($dup['kind'] ?? '') === 'queue') {
        return sprintf(
            '« %s » de %s est déjà en cours de téléchargement.',
            $dup['album'], $dup['artist']
        );
    }
    if (($dup['kind'] ?? '') === 'song') {
        return sprintf(
            '« %s » de %s est déjà dans la bibliothèque.',
            $dup['album'], $dup['artist']
        );
    }
    $tracks = (int) ($dup['track_count'] ?? 0);
    return sprintf(
        '« %s » de %s est déjà dans la bibliothèque (%d piste%s).',
        $dup['album'], $dup['artist'], $tracks, $tracks > 1 ? 's' : ''
    );
}

function extractMetadata($url) {
    $command = 'timeout 20 yt-dlp --print "%(uploader)s|%(playlist_title)s|%(title)s" --no-download ' . escapeshellarg($url) . ' 2>/dev/null | head -1';
    $result = shell_exec($command);

    if ($result && strlen(trim($result)) > 0) {
        $parts = explode('|', trim($result));
        $uploader = isset($parts[0]) ? trim($parts[0]) : '';
        $playlistTitle = isset($parts[1]) ? trim($parts[1]) : '';
        $videoTitle = isset($parts[2]) ? trim($parts[2]) : '';

        $artist = $uploader;
        $album = $playlistTitle ? $playlistTitle : $videoTitle;

        $artist = preg_replace('/\s*-\s*Topic$/', '', $artist);
        $artist = preg_replace('/Official$/', '', $artist);
        $artist = trim($artist);

        $album = preg_replace('/^Album\s*-\s*/i', '', $album);
        $album = trim($album);

        if (strlen($artist) > 2 && strlen($album) > 2) {
            return ['artist' => sanitizeForPath($artist), 'album' => sanitizeForPath($album)];
        }
    }

    return null;
}

/**
 * Résout (et met en cache) l'URL audio directe d'une vidéo YouTube pour la
 * pré-écoute. Les URLs googlevideo sont liées à l'IP du serveur et expirent
 * (~6 h) : on les proxifie ensuite, jamais on ne les renvoie au téléphone.
 */
function resolvePreviewUrl($videoId) {
    $cacheDir = AppConfig::getDataPath() . '/cache/preview/';
    if (!is_dir($cacheDir)) {
        @mkdir($cacheDir, 0755, true);
    }
    $cacheFile = $cacheDir . $videoId . '.txt';

    if (is_file($cacheFile)) {
        $cached = trim((string)@file_get_contents($cacheFile));
        if ($cached !== '') {
            // Réutilisable tant que le paramètre expire= laisse une marge.
            if (preg_match('/[?&]expire=(\d+)/', $cached, $m)) {
                if ((int)$m[1] - 120 > time()) {
                    return $cached;
                }
            } elseif (filemtime($cacheFile) > time() - 1800) {
                return $cached;
            }
        }
    }

    $watchUrl = 'https://music.youtube.com/watch?v=' . $videoId;
    $ytBin = file_exists('/opt/ytdlp/bin/yt-dlp') ? '/opt/ytdlp/bin/yt-dlp' : 'yt-dlp';
    // m4a (AAC) de préférence : progressif et seekable, lu partout par ExoPlayer.
    $cmd = 'timeout 30 ' . escapeshellarg($ytBin)
         . ' -f ' . escapeshellarg('bestaudio[ext=m4a]/bestaudio')
         . ' -g ' . escapeshellarg($watchUrl) . ' 2>/dev/null | head -1';
    $direct = trim((string)shell_exec($cmd));
    if ($direct !== '' && strpos($direct, 'http') === 0) {
        @file_put_contents($cacheFile, $direct);
        @chmod($cacheFile, 0666);
        return $direct;
    }
    return null;
}

/**
 * Proxifie le flux audio direct vers le client en relayant les requêtes Range
 * (le seek fonctionne), sans jamais exposer l'URL googlevideo éphémère.
 */
function streamPreview($directUrl) {
    // Coupe toute compression/bufferisation : on relaie des octets bruts.
    @ini_set('zlib.output_compression', 'Off');
    while (ob_get_level() > 0) { @ob_end_clean(); }

    $reqHeaders = ['Accept: */*'];
    if (!empty($_SERVER['HTTP_RANGE'])) {
        $reqHeaders[] = 'Range: ' . $_SERVER['HTTP_RANGE'];
    }

    $ch = curl_init($directUrl);
    curl_setopt_array($ch, [
        CURLOPT_HTTPHEADER     => $reqHeaders,
        CURLOPT_FOLLOWLOCATION => true,
        CURLOPT_TIMEOUT        => 120,
        CURLOPT_CONNECTTIMEOUT => 15,
        CURLOPT_HEADERFUNCTION => function ($ch, $line) {
            $l = trim($line);
            if (preg_match('#^HTTP/[\d.]+\s+(\d+)#', $l, $m)) {
                http_response_code((int)$m[1]);
            } elseif (
                stripos($l, 'content-type:') === 0 ||
                stripos($l, 'content-length:') === 0 ||
                stripos($l, 'content-range:') === 0 ||
                stripos($l, 'accept-ranges:') === 0
            ) {
                header($l, true);
            }
            return strlen($line);
        },
        CURLOPT_WRITEFUNCTION => function ($ch, $data) {
            echo $data;
            flush();
            return strlen($data);
        },
    ]);
    // Remplace le Content-Type JSON par défaut si la source n'en fournit pas.
    header('Content-Type: audio/mp4');
    header('Accept-Ranges: bytes');
    header('Cache-Control: no-store');
    curl_exec($ch);
    curl_close($ch);
}

try {
    switch ($action) {
        case 'start':
            $url = $_POST['url'] ?? '';
            $user = $_POST['user'] ?? '';
            $artistId = $_POST['artist_id'] ?? '';
            $artistName = $_POST['artist_name'] ?? '';
            $albumName = $_POST['album_name'] ?? '';

            if (empty($url) || empty($user) || empty($artistId)) {
                throw new Exception('Missing required parameters');
            }

            if (empty($artistName) || empty($albumName)) {
                $metadata = extractMetadata($url);
                if (!$metadata) {
                    throw new Exception('Failed to extract metadata from URL');
                }
                $artistName = $metadata['artist'];
                $albumName = $metadata['album'];
            } else {
                $artistName = sanitizeForPath($artistName);
                $albumName = sanitizeForPath($albumName);
            }

            // Rien ne se télécharge deux fois sans le dire : « force » permet
            // de reprendre quand même (album incomplet, meilleure version…).
            $force = filter_var($_POST['force'] ?? $_GET['force'] ?? false, FILTER_VALIDATE_BOOLEAN);
            if (!$force) {
                $songTitle = trim($_POST['title'] ?? $_GET['title'] ?? '');
                $dup = findDuplicate($downloadDir, $user, $artistName, $albumName, $url, $songTitle);
                if ($dup) {
                    echo json_encode([
                        'success' => false,
                        'error' => duplicateMessage($dup),
                        'duplicate' => $dup,
                    ], JSON_UNESCAPED_UNICODE);
                    break;
                }
            }

            $downloadId = uniqid('dl_', true);

            $statusFile = $downloadDir . "{$downloadId}.json";
            $statusData = [
                'id' => $downloadId,
                'status' => 'queued',
                'progress' => 0,
                'message' => 'En attente de demarrage...',
                'artist' => $artistName,
                'album' => $albumName,
                'user' => $user,
                'artist_id' => $artistId,
                'url' => $url,
                'created_at' => date('Y-m-d H:i:s'),
                'updated_at' => date('Y-m-d H:i:s')
            ];

            file_put_contents($statusFile, json_encode($statusData, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE));
            chmod($statusFile, 0666);

            @exec(escapeshellarg($queueScript) . ' > /dev/null 2>&1 &');

            echo json_encode([
                'success' => true,
                'download_id' => $downloadId,
                'message' => 'Telechargement demarre'
            ]);
            break;

        case 'check_duplicate':
            // Appelé avant d'ouvrir la fenêtre de confirmation : l'app prévient
            // que l'album est déjà là plutôt que de le retélécharger.
            $user = $_GET['user'] ?? $_POST['user'] ?? '';
            $artistName = sanitizeForPath($_GET['artist'] ?? $_POST['artist'] ?? '');
            $albumName = sanitizeForPath($_GET['album'] ?? $_POST['album'] ?? '');
            $url = $_GET['url'] ?? $_POST['url'] ?? '';
            $songTitle = trim($_GET['title'] ?? $_POST['title'] ?? '');

            if (empty($user)) {
                throw new Exception('Missing user parameter');
            }

            $dup = findDuplicate($downloadDir, $user, $artistName, $albumName, $url, $songTitle);
            echo json_encode([
                'success' => true,
                'data' => [
                    'duplicate' => $dup ? $dup + ['message' => duplicateMessage($dup)] : null,
                ],
            ], JSON_UNESCAPED_UNICODE);
            break;

        case 'preview':
            // Pré-écoute d'une chanson YouTube (avant téléchargement) : on
            // proxifie son flux audio. Réponse binaire (pas d'envelope JSON).
            $videoId = trim($_GET['video_id'] ?? '');
            if (!preg_match('/^[A-Za-z0-9_-]{5,20}$/', $videoId)) {
                http_response_code(400);
                echo json_encode(['success' => false, 'error' => 'invalid video_id']);
                break;
            }
            $direct = resolvePreviewUrl($videoId);
            if (!$direct) {
                http_response_code(502);
                echo json_encode(['success' => false, 'error' => 'Failed to resolve preview']);
                break;
            }
            streamPreview($direct);
            break;

        case 'search_ytmusic':
            $query = trim($_GET['query'] ?? '');
            if (!$query) {
                echo json_encode(['success' => false, 'error' => 'query required']);
                break;
            }
            $limit = (int)($_GET['limit'] ?? 10);
            if ($limit < 1)  { $limit = 10; }
            if ($limit > 50) { $limit = 50; }
            $pythonScript = AppConfig::getPythonPath() . '/ytmusic_search.py';
            $pythonBin    = file_exists('/opt/ytdlp/bin/python3') ? '/opt/ytdlp/bin/python3' : 'python3';
            $cmd = $pythonBin . ' ' . escapeshellarg($pythonScript)
                 . ' album ' . escapeshellarg($query) . ' ' . escapeshellarg((string)$limit)
                 . ' 2>/dev/null';
            $output = shell_exec($cmd);
            if (!$output) {
                echo json_encode(['success' => true, 'data' => ['albums' => []]]);
                break;
            }
            $data = json_decode($output, true);
            $albums = markAlbumsInLibrary(
                $_GET['user'] ?? '',
                array_map(fn($r) => [
                    'title'     => $r['title']     ?? '',
                    'artist'    => $r['artist']    ?? '',
                    'year'      => $r['year']      ?? '',
                    'thumbnail' => $r['thumbnail'] ?? '',
                    'browseId'  => $r['browseId']  ?? '',
                ], $data['results'] ?? [])
            );
            echo json_encode(['success' => true, 'data' => ['albums' => $albums]]);
            break;

        case 'new_releases':
            // Nouvelles sorties YouTube Music, affichées dans l'onglet
            // Recherche quand le champ est vide. Albums seulement : les
            // singles noient la liste sans intéresser personne. La page de
            // YouTube étant un fourre-tout mondial, on la reclasse pour cet
            // utilisateur avant de n'en servir que le début.
            $limit = (int)($_GET['limit'] ?? 30);
            if ($limit < 1)   { $limit = 30; }
            if ($limit > 100) { $limit = 100; }
            $user = $_GET['user'] ?? '';

            // D'abord les sorties des artistes que l'utilisateur écoute — la
            // seule liste qui se renouvelle vraiment et sur laquelle il a
            // envie de cliquer. Le fourre-tout mondial de YouTube complète
            // derrière, et seulement s'il reste de la place.
            $mine   = markAlbumsInLibrary($user, personalNewReleases($user));
            $mine   = array_values(array_filter($mine, fn($a) => empty($a['in_library'])));
            $seen   = [];
            foreach ($mine as $album) $seen[$album['browseId']] = true;

            $albums = $mine;
            if (count($albums) < $limit) {
                $global = rankNewReleases($user, markAlbumsInLibrary($user, fetchNewReleases()));
                foreach ($global as $album) {
                    if (isset($seen[$album['browseId'] ?? ''])) continue;
                    $albums[] = $album;
                }
            }

            echo json_encode([
                'success' => true,
                'data' => ['albums' => array_slice($albums, 0, $limit)],
            ]);
            break;

        case 'search_songs':
            // Chansons seules sur YouTube Music (téléchargement à l'unité :
            // l'app construit ensuite https://music.youtube.com/watch?v=ID).
            $query = trim($_GET['query'] ?? '');
            if (!$query) {
                echo json_encode(['success' => false, 'error' => 'query required']);
                break;
            }
            $limit = (int)($_GET['limit'] ?? 10);
            if ($limit < 1)  { $limit = 10; }
            if ($limit > 50) { $limit = 50; }
            $pythonScript = AppConfig::getPythonPath() . '/ytmusic_search.py';
            $pythonBin    = file_exists('/opt/ytdlp/bin/python3') ? '/opt/ytdlp/bin/python3' : 'python3';
            $cmd = $pythonBin . ' ' . escapeshellarg($pythonScript)
                 . ' song ' . escapeshellarg($query) . ' ' . escapeshellarg((string)$limit)
                 . ' 2>/dev/null';
            $output = shell_exec($cmd);
            if (!$output) {
                echo json_encode(['success' => true, 'data' => ['songs' => []]]);
                break;
            }
            $data = json_decode($output, true);
            $songs = array_values(array_filter(array_map(fn($r) => [
                'title'     => $r['title']     ?? '',
                'artist'    => $r['artist']    ?? '',
                'album'     => $r['album']     ?? '',
                'duration'  => $r['duration']  ?? '',
                'thumbnail' => $r['thumbnail'] ?? '',
                'videoId'   => $r['videoId']   ?? '',
            ], $data['results'] ?? []), fn($s) => $s['videoId'] !== ''));
            $songs = markSongsInLibrary($_GET['user'] ?? '', $songs);
            echo json_encode(['success' => true, 'data' => ['songs' => $songs]]);
            break;

        case 'search_artists':
            // Artistes sur YouTube Music (recherche, onglet Recherche). Au tap,
            // l'app ouvre la discographie de l'artiste (recherche d'albums).
            $query = trim($_GET['query'] ?? '');
            if (!$query) {
                echo json_encode(['success' => false, 'error' => 'query required']);
                break;
            }
            $limit = (int)($_GET['limit'] ?? 10);
            if ($limit < 1)  { $limit = 10; }
            if ($limit > 50) { $limit = 50; }
            $pythonScript = AppConfig::getPythonPath() . '/ytmusic_search.py';
            $pythonBin    = file_exists('/opt/ytdlp/bin/python3') ? '/opt/ytdlp/bin/python3' : 'python3';
            $cmd = $pythonBin . ' ' . escapeshellarg($pythonScript)
                 . ' artist ' . escapeshellarg($query) . ' ' . escapeshellarg((string)$limit)
                 . ' 2>/dev/null';
            $output = shell_exec($cmd);
            if (!$output) {
                echo json_encode(['success' => true, 'data' => ['artists' => []]]);
                break;
            }
            $data = json_decode($output, true);
            $artists = array_values(array_filter(array_map(fn($r) => [
                'name'      => $r['name']      ?? '',
                'browseId'  => $r['browseId']  ?? '',
                'thumbnail' => $r['thumbnail'] ?? '',
            ], $data['results'] ?? []), fn($a) => $a['name'] !== ''));
            echo json_encode(['success' => true, 'data' => ['artists' => $artists]]);
            break;

        case 'artist_albums':
            // Discographie réelle d'un artiste (albums + singles) via son
            // browseId : au tap sur un artiste, l'app affiche SES albums.
            $browseId = trim($_GET['browse_id'] ?? '');
            if (!$browseId) {
                echo json_encode(['success' => false, 'error' => 'browse_id required']);
                break;
            }
            $limit = (int)($_GET['limit'] ?? 50);
            if ($limit < 1)  { $limit = 50; }
            if ($limit > 100) { $limit = 100; }
            $pythonScript = AppConfig::getPythonPath() . '/ytmusic_search.py';
            $pythonBin    = file_exists('/opt/ytdlp/bin/python3') ? '/opt/ytdlp/bin/python3' : 'python3';
            $cmd = $pythonBin . ' ' . escapeshellarg($pythonScript)
                 . ' artist_albums ' . escapeshellarg($browseId) . ' ' . escapeshellarg((string)$limit)
                 . ' 2>/dev/null';
            $output = shell_exec($cmd);
            if (!$output) {
                echo json_encode(['success' => true, 'data' => ['albums' => []]]);
                break;
            }
            $data = json_decode($output, true);
            $albums = markAlbumsInLibrary(
                $_GET['user'] ?? '',
                array_values(array_filter(array_map(fn($r) => [
                    'title'     => $r['title']     ?? '',
                    'artist'    => $r['artist']    ?? '',
                    'year'      => $r['year']      ?? '',
                    'thumbnail' => $r['thumbnail'] ?? '',
                    'browseId'  => $r['browseId']  ?? '',
                ], $data['results'] ?? []), fn($a) => $a['browseId'] !== ''))
            );
            echo json_encode(['success' => true, 'data' => ['albums' => $albums]]);
            break;

        case 'related_artists':
            // Artistes similaires (YouTube Music) à partir d'un nom d'artiste.
            $query = trim($_GET['query'] ?? '');
            if (!$query) {
                echo json_encode(['success' => false, 'error' => 'query required']);
                break;
            }
            $pythonScript = AppConfig::getPythonPath() . '/ytmusic_search.py';
            $pythonBin    = file_exists('/opt/ytdlp/bin/python3') ? '/opt/ytdlp/bin/python3' : 'python3';
            $cmd = $pythonBin . ' ' . escapeshellarg($pythonScript)
                 . ' related ' . escapeshellarg($query) . ' 2>/dev/null';
            $output = shell_exec($cmd);
            if (!$output) {
                echo json_encode(['success' => true, 'data' => ['artists' => []]]);
                break;
            }
            $data = json_decode($output, true);
            $artists = array_values(array_filter(array_map(fn($r) => [
                'name'      => $r['name']      ?? '',
                'browseId'  => $r['browseId']  ?? '',
                'thumbnail' => $r['thumbnail'] ?? '',
            ], $data['results'] ?? []), fn($a) => $a['name'] !== ''));
            echo json_encode(['success' => true, 'data' => ['artists' => $artists]]);
            break;

        case 'resolve_album':
            $browseId = trim($_GET['browse_id'] ?? '');
            if (!$browseId) {
                echo json_encode(['success' => false, 'error' => 'browse_id required']);
                break;
            }
            $pythonScript = AppConfig::getPythonPath() . '/ytmusic_search.py';
            $pythonBin = file_exists('/opt/ytdlp/bin/python3') ? '/opt/ytdlp/bin/python3' : 'python3';
            $cmd = $pythonBin . ' ' . escapeshellarg($pythonScript)
                 . ' album_details ' . escapeshellarg($browseId) . ' 2>/dev/null';
            $output = shell_exec($cmd);
            if (!$output) {
                echo json_encode(['success' => false, 'error' => 'Failed to resolve album']);
                break;
            }
            $data = json_decode($output, true);
            $album = $data['album'] ?? null;
            if (!$album || empty($album['audioPlaylistId'])) {
                echo json_encode(['success' => false, 'error' => 'No playlist found for this album']);
                break;
            }
            echo json_encode([
                'success' => true,
                'data' => [
                    'playlistUrl' => 'https://music.youtube.com/playlist?list=' . $album['audioPlaylistId'],
                    'artist' => $album['artist'] ?? '',
                    'title' => $album['title'] ?? '',
                    'year' => $album['year'] ?? '',
                    'track_count' => $album['track_count'] ?? 0,
                    'thumbnail' => $album['thumbnail'] ?? '',
                ]
            ]);
            break;

        case 'status':
            $downloadId = $_GET['download_id'] ?? '';

            if (empty($downloadId)) {
                throw new Exception('Missing download_id parameter');
            }

            $statusFile = $downloadDir . "{$downloadId}.json";

            if (!file_exists($statusFile)) {
                throw new Exception('Download not found');
            }

            $statusData = json_decode(file_get_contents($statusFile), true);

            echo json_encode([
                'success' => true,
                'download' => $statusData
            ]);
            break;

        case 'list':
            $filterUser = $_GET['user'] ?? '';
            $downloads = [];
            $files = glob($downloadDir . 'dl_*.json');

            foreach ($files as $file) {
                $data = json_decode(file_get_contents($file), true);
                if ($data && (!$filterUser || ($data['user'] ?? '') === $filterUser)) {
                    $downloads[] = $data;
                }
            }

            usort($downloads, function($a, $b) {
                return strtotime($b['created_at'] ?? '0') - strtotime($a['created_at'] ?? '0');
            });

            echo json_encode([
                'success' => true,
                'data' => $downloads,
                'count' => count($downloads)
            ]);
            break;

        case 'cancel':
            $downloadId = $_POST['download_id'] ?? '';

            if (empty($downloadId)) {
                throw new Exception('Missing download_id parameter');
            }

            $statusFile = $downloadDir . "{$downloadId}.json";

            if (!file_exists($statusFile)) {
                throw new Exception('Download not found');
            }

            $statusData = json_decode(file_get_contents($statusFile), true);
            $statusData['status'] = 'cancelled';
            $statusData['message'] = 'Annule par l\'utilisateur';
            $statusData['updated_at'] = date('Y-m-d H:i:s');

            file_put_contents($statusFile, json_encode($statusData, JSON_PRETTY_PRINT));

            echo json_encode([
                'success' => true,
                'message' => 'Download cancelled'
            ]);
            break;

        case 'retry':
            $downloadId = $_POST['download_id'] ?? '';

            if (empty($downloadId)) {
                throw new Exception('Missing download_id parameter');
            }

            $statusFile = $downloadDir . "{$downloadId}.json";

            if (!file_exists($statusFile)) {
                throw new Exception('Download not found');
            }

            $statusData = json_decode(file_get_contents($statusFile), true);

            if (!in_array($statusData['status'], ['error', 'cancelled'])) {
                throw new Exception('Only failed or cancelled downloads can be retried');
            }

            $statusData['status'] = 'queued';
            $statusData['progress'] = 0;
            $statusData['message'] = 'En attente de demarrage (reessai)...';
            $statusData['updated_at'] = date('Y-m-d H:i:s');

            file_put_contents($statusFile, json_encode($statusData, JSON_PRETTY_PRINT));

            @exec(escapeshellarg($queueScript) . ' > /dev/null 2>&1 &');

            echo json_encode([
                'success' => true,
                'message' => 'Download queued for retry'
            ]);
            break;

        case 'delete':
            $downloadId = $_POST['download_id'] ?? '';

            if (empty($downloadId)) {
                throw new Exception('Missing download_id parameter');
            }

            $statusFile = $downloadDir . "{$downloadId}.json";
            $logFile = $downloadDir . "{$downloadId}.log";

            if (!file_exists($statusFile)) {
                throw new Exception('Download not found');
            }

            @unlink($statusFile);
            @unlink($logFile);

            echo json_encode([
                'success' => true,
                'message' => 'Download deleted'
            ]);
            break;

        default:
            throw new Exception('Unknown action');
    }

} catch (Exception $e) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'error' => $e->getMessage()
    ]);
}
