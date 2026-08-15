<?php
/**
 * Gullify - Web Radio API
 *
 * Chaque utilisateur a sa propre liste de stations (idée #97) : ce qu'on
 * renvoie ici, ce sont ses stations à lui. Radio Browser n'est plus un
 * catalogue partagé, seulement une source d'import — transférée une fois
 * chez chacun à sa première visite, puis reprise à la demande.
 *
 * Migrated from web_radio_api.php
 */

require_once __DIR__ . '/../../src/AppConfig.php';

// Boot the Gullify session (with the right cookie name + path).
// The web radio view is always reached from inside the SPA, so we always
// have a logged-in user. auth_required.php handles cookie/session/Bearer
// token flows for us.
require_once __DIR__ . '/../../src/auth_required.php';

require_once __DIR__ . '/../../src/RadioStations.php';

header('Content-Type: application/json');
header('Cache-Control: no-cache');

$user   = $_SESSION['username'] ?? '';
$action = $_GET['action'] ?? 'list';
$cacheFile = AppConfig::getDataPath() . '/cache/web_radio_ca.json';
$cacheDuration = 3600; // 1 hour

/**
 * Get a working Radio Browser API server
 */
function getRadioBrowserServer() {
    $servers = [
        'https://de1.api.radio-browser.info',
        'https://nl1.api.radio-browser.info',
        'https://at1.api.radio-browser.info'
    ];
    return $servers[array_rand($servers)];
}

/**
 * Fetch stations from Radio Browser API
 */
function fetchFromRadioBrowser() {
    $server = getRadioBrowserServer();
    $url = "$server/json/stations/bycountry/canada?hidebroken=true&order=clickcount&reverse=true&limit=1200";

    $ctx = stream_context_create([
        "http" => [
            "timeout" => 30,
            "user_agent" => "MusicPlayer/1.0",
            "header" => "Accept: application/json\r\n"
        ],
        "ssl" => [
            "verify_peer" => false,
            "verify_peer_name" => false
        ]
    ]);

    $data = @file_get_contents($url, false, $ctx);
    if (!$data) {
        return null;
    }

    $stations = json_decode($data, true);
    if (!$stations || !is_array($stations)) {
        return null;
    }

    // Transform to our format
    $transformed = [];
    foreach ($stations as $station) {
        if (empty($station['url_resolved']) && empty($station['url'])) {
            continue;
        }

        $tags = array_filter(array_map('trim', explode(',', $station['tags'] ?? '')));
        $genres = array_slice($tags, 0, 3);
        if (empty($genres)) {
            $genres = ['Radio'];
        }

        $streamUrl = $station['url_resolved'] ?: $station['url'];
        $isHttps = strpos($streamUrl, 'https://') === 0;

        $transformed[] = [
            'id' => $station['stationuuid'],
            'name' => trim($station['name']),
            'country' => 'Canada',
            'state' => $station['state'] ?? '',
            'language' => $station['language'] ?? '',
            'genres' => $genres,
            'streams' => [[
                'url' => $streamUrl,
                'format' => strtoupper($station['codec'] ?? 'MP3'),
                'bitrate' => (int)($station['bitrate'] ?? 128),
                'secure' => $isHttps
            ]],
            'logo' => $station['favicon'] ?: null,
            'website' => $station['homepage'] ?? null,
            'votes' => (int)($station['votes'] ?? 0),
            'clickcount' => (int)($station['clickcount'] ?? 0),
            'secure' => $isHttps
        ];
    }

    usort($transformed, function($a, $b) {
        $scoreA = $a['votes'] + $a['clickcount'];
        $scoreB = $b['votes'] + $b['clickcount'];
        return $scoreB - $scoreA;
    });

    return [
        'updated' => date('c'),
        'source' => 'radio-browser',
        'count' => count($transformed),
        'stations' => $transformed
    ];
}

/**
 * Get stations from cache or fetch fresh
 */
function getStations($cacheFile, $cacheDuration) {
    if (file_exists($cacheFile)) {
        $cacheAge = time() - filemtime($cacheFile);
        if ($cacheAge < $cacheDuration) {
            $cached = json_decode(file_get_contents($cacheFile), true);
            if ($cached && !empty($cached['stations'])) {
                $cached['fromCache'] = true;
                $cached['cacheAge'] = $cacheAge;
                return $cached;
            }
        }
    }

    $fresh = fetchFromRadioBrowser();
    if ($fresh && !empty($fresh['stations'])) {
        @file_put_contents($cacheFile, json_encode($fresh, JSON_UNESCAPED_UNICODE));
        $fresh['fromCache'] = false;
        return $fresh;
    }

    if (file_exists($cacheFile)) {
        $cached = json_decode(file_get_contents($cacheFile), true);
        if ($cached) {
            $cached['fromCache'] = true;
            $cached['stale'] = true;
            return $cached;
        }
    }

    return getFallbackStations();
}

/**
 * Fallback Canadian radio stations (hardcoded for reliability)
 */
function getFallbackStations() {
    return [
        'updated' => date('c'),
        'source' => 'fallback',
        'count' => 20,
        'stations' => [
            ['id' => 'ca-cbc-radio-one', 'name' => 'CBC Radio One', 'country' => 'Canada', 'state' => 'Ontario', 'language' => 'English', 'genres' => ['News', 'Talk', 'Public Radio'], 'streams' => [['url' => 'https://cbcradiolive.akamaized.net/hls/live/2041169/ES_R1OTT/master.m3u8', 'format' => 'HLS', 'bitrate' => 128]], 'logo' => 'https://www.cbc.ca/radio/images/cbc-radio-one-logo.png', 'votes' => 1000, 'clickcount' => 5000],
            ['id' => 'ca-cbc-music', 'name' => 'CBC Music', 'country' => 'Canada', 'state' => 'Ontario', 'language' => 'English', 'genres' => ['Music', 'Variety'], 'streams' => [['url' => 'https://cbcradiolive.akamaized.net/hls/live/2041171/ES_R2TOR/master.m3u8', 'format' => 'HLS', 'bitrate' => 128]], 'logo' => 'https://www.cbc.ca/radio/images/cbc-music-logo.png', 'votes' => 900, 'clickcount' => 4000],
            ['id' => 'ca-ici-premiere', 'name' => 'ICI Radio-Canada Premiere', 'country' => 'Canada', 'state' => 'Quebec', 'language' => 'French', 'genres' => ['News', 'Talk', 'Public Radio'], 'streams' => [['url' => 'https://cbcradiolive.akamaized.net/hls/live/2041169/ES_R1MTL/master.m3u8', 'format' => 'HLS', 'bitrate' => 128]], 'logo' => null, 'votes' => 800, 'clickcount' => 3500],
            ['id' => 'ca-ici-musique', 'name' => 'ICI Musique', 'country' => 'Canada', 'state' => 'Quebec', 'language' => 'French', 'genres' => ['Music', 'Variety'], 'streams' => [['url' => 'https://cbcradiolive.akamaized.net/hls/live/2041171/ES_R2MTL/master.m3u8', 'format' => 'HLS', 'bitrate' => 128]], 'logo' => null, 'votes' => 700, 'clickcount' => 3000],
            ['id' => 'ca-chom', 'name' => 'CHOM 97.7', 'country' => 'Canada', 'state' => 'Quebec', 'language' => 'English', 'genres' => ['Rock', 'Classic Rock'], 'streams' => [['url' => 'https://playerservices.streamtheworld.com/api/livestream-redirect/CHOMFMAAC.aac', 'format' => 'AAC', 'bitrate' => 128]], 'logo' => null, 'votes' => 600, 'clickcount' => 2500],
            ['id' => 'ca-virgin-radio', 'name' => 'Virgin Radio 96', 'country' => 'Canada', 'state' => 'Quebec', 'language' => 'English', 'genres' => ['Pop', 'Top 40'], 'streams' => [['url' => 'https://playerservices.streamtheworld.com/api/livestream-redirect/CJFMFMAAC.aac', 'format' => 'AAC', 'bitrate' => 128]], 'logo' => null, 'votes' => 550, 'clickcount' => 2200],
            ['id' => 'ca-energie', 'name' => 'Energie Montreal 94.3', 'country' => 'Canada', 'state' => 'Quebec', 'language' => 'French', 'genres' => ['Pop', 'Dance', 'Top 40'], 'streams' => [['url' => 'https://playerservices.streamtheworld.com/api/livestream-redirect/CKMFFMAAC.aac', 'format' => 'AAC', 'bitrate' => 128]], 'logo' => null, 'votes' => 500, 'clickcount' => 2000],
            ['id' => 'ca-rouge-fm', 'name' => 'Rouge FM 107.3', 'country' => 'Canada', 'state' => 'Quebec', 'language' => 'French', 'genres' => ['Adult Contemporary', 'Pop'], 'streams' => [['url' => 'https://playerservices.streamtheworld.com/api/livestream-redirect/CITFFMAAC.aac', 'format' => 'AAC', 'bitrate' => 128]], 'logo' => null, 'votes' => 450, 'clickcount' => 1800],
            ['id' => 'ca-rythme', 'name' => 'Rythme FM 105.7', 'country' => 'Canada', 'state' => 'Quebec', 'language' => 'French', 'genres' => ['Adult Contemporary', 'Pop'], 'streams' => [['url' => 'https://cogecoradio.leanstream.co/CFGL-FM', 'format' => 'MP3', 'bitrate' => 128]], 'logo' => null, 'votes' => 400, 'clickcount' => 1600],
            ['id' => 'ca-cjad', 'name' => 'CJAD 800', 'country' => 'Canada', 'state' => 'Quebec', 'language' => 'English', 'genres' => ['News', 'Talk'], 'streams' => [['url' => 'https://playerservices.streamtheworld.com/api/livestream-redirect/CJADAMAAC.aac', 'format' => 'AAC', 'bitrate' => 128]], 'logo' => null, 'votes' => 350, 'clickcount' => 1400],
            ['id' => 'ca-98-5', 'name' => '98.5 FM Montreal', 'country' => 'Canada', 'state' => 'Quebec', 'language' => 'French', 'genres' => ['News', 'Talk', 'Sports'], 'streams' => [['url' => 'https://cogecoradio.leanstream.co/CHMP-FM', 'format' => 'MP3', 'bitrate' => 128]], 'logo' => null, 'votes' => 300, 'clickcount' => 1200],
            ['id' => 'ca-ckoi', 'name' => 'CKOI 96.9', 'country' => 'Canada', 'state' => 'Quebec', 'language' => 'French', 'genres' => ['Pop', 'Dance'], 'streams' => [['url' => 'https://cogecoradio.leanstream.co/CKOI-FM', 'format' => 'MP3', 'bitrate' => 128]], 'logo' => null, 'votes' => 280, 'clickcount' => 1100],
            ['id' => 'ca-boom', 'name' => 'Boom 104.1', 'country' => 'Canada', 'state' => 'Quebec', 'language' => 'French', 'genres' => ['Classic Hits', '80s', '90s'], 'streams' => [['url' => 'https://cogecoradio.leanstream.co/CIQC-FM', 'format' => 'MP3', 'bitrate' => 128]], 'logo' => null, 'votes' => 260, 'clickcount' => 1000],
            ['id' => 'ca-the-beat', 'name' => 'The Beat 92.5', 'country' => 'Canada', 'state' => 'Quebec', 'language' => 'English', 'genres' => ['Hip Hop', 'R&B'], 'streams' => [['url' => 'https://playerservices.streamtheworld.com/api/livestream-redirect/CKBEFMAAC.aac', 'format' => 'AAC', 'bitrate' => 128]], 'logo' => null, 'votes' => 240, 'clickcount' => 950],
            ['id' => 'ca-cbc-radio-3', 'name' => 'CBC Radio 3', 'country' => 'Canada', 'state' => 'National', 'language' => 'English', 'genres' => ['Indie', 'Alternative', 'Canadian Music'], 'streams' => [['url' => 'https://cbcradiolive.akamaized.net/hls/live/2041173/ES_R3TOR/master.m3u8', 'format' => 'HLS', 'bitrate' => 128]], 'logo' => null, 'votes' => 220, 'clickcount' => 900],
            ['id' => 'ca-classique', 'name' => 'ICI Musique Classique', 'country' => 'Canada', 'state' => 'National', 'language' => 'French', 'genres' => ['Classical'], 'streams' => [['url' => 'https://cbcradiolive.akamaized.net/hls/live/2041175/ES_CLEMTL/master.m3u8', 'format' => 'HLS', 'bitrate' => 128]], 'logo' => null, 'votes' => 200, 'clickcount' => 850],
            ['id' => 'ca-jazz-fm', 'name' => 'Jazz FM 91.1', 'country' => 'Canada', 'state' => 'Ontario', 'language' => 'English', 'genres' => ['Jazz'], 'streams' => [['url' => 'https://playerservices.streamtheworld.com/api/livestream-redirect/CJABORIG.mp3', 'format' => 'MP3', 'bitrate' => 128]], 'logo' => null, 'votes' => 180, 'clickcount' => 800],
            ['id' => 'ca-indie-88', 'name' => 'Indie 88', 'country' => 'Canada', 'state' => 'Ontario', 'language' => 'English', 'genres' => ['Indie', 'Alternative'], 'streams' => [['url' => 'https://playerservices.streamtheworld.com/api/livestream-redirect/INDIE88AAC.aac', 'format' => 'AAC', 'bitrate' => 128]], 'logo' => null, 'votes' => 160, 'clickcount' => 750],
            ['id' => 'ca-edge', 'name' => 'The Edge 102.1', 'country' => 'Canada', 'state' => 'Ontario', 'language' => 'English', 'genres' => ['Alternative', 'Rock'], 'streams' => [['url' => 'https://playerservices.streamtheworld.com/api/livestream-redirect/CFNYFMAAC.aac', 'format' => 'AAC', 'bitrate' => 128]], 'logo' => null, 'votes' => 140, 'clickcount' => 700],
            ['id' => 'ca-country-104', 'name' => 'Country 104', 'country' => 'Canada', 'state' => 'Ontario', 'language' => 'English', 'genres' => ['Country'], 'streams' => [['url' => 'https://playerservices.streamtheworld.com/api/livestream-redirect/CKDK_FM.mp3', 'format' => 'MP3', 'bitrate' => 128]], 'logo' => null, 'votes' => 120, 'clickcount' => 650]
        ]
    ];
}

/**
 * Search stations by name, genre or state
 */
function searchStations($stations, $query) {
    $query = strtolower(trim($query));
    if (empty($query)) {
        return $stations;
    }

    return array_values(array_filter($stations, function($station) use ($query) {
        $name = strtolower($station['name'] ?? '');
        $genres = array_map('strtolower', $station['genres'] ?? []);
        $language = strtolower($station['language'] ?? '');
        $state = strtolower($station['state'] ?? '');

        return strpos($name, $query) !== false ||
               in_array($query, $genres) ||
               strpos(implode(' ', $genres), $query) !== false ||
               strpos($language, $query) !== false ||
               strpos($state, $query) !== false;
    }));
}

/**
 * Get unique genres from stations
 */
function getGenres($stations) {
    $genres = [];
    foreach ($stations as $station) {
        foreach ($station['genres'] ?? [] as $genre) {
            $genre = trim($genre);
            if (!empty($genre) && strlen($genre) > 1) {
                $genres[$genre] = ($genres[$genre] ?? 0) + 1;
            }
        }
    }
    arsort($genres);
    return array_slice($genres, 0, 20, true);
}

/**
 * La liste de l'utilisateur, et rien d'autre : depuis l'idée #97 il n'y a
 * plus de catalogue public, chacun a sa propre liste. Chaque station est
 * décorée de son favori et de son dossier, favoris en tête.
 */
function ownStations(string $user): array {
    $out = [];
    if ($user !== '') {
        $state = RadioStations::getState($user);
        foreach (RadioStations::listCustom($user) as $s) {
            $sid = (string)($s['id'] ?? '');
            $flags = $state[$sid] ?? ['favorite' => false, 'hidden' => false, 'folder_id' => null];
            if (!empty($flags['hidden'])) continue;
            $s['favorite']  = !empty($flags['favorite']);
            $s['custom']    = true;
            $s['folder_id'] = $flags['folder_id'] ?? null;
            $out[] = $s;
        }
        usort($out, function($a, $b) {
            $fa = !empty($a['favorite']) ? 1 : 0;
            $fb = !empty($b['favorite']) ? 1 : 0;
            if ($fa !== $fb) return $fb - $fa;
            return strcasecmp((string)($a['name'] ?? ''), (string)($b['name'] ?? ''));
        });
    }
    return [
        'updated'  => date('c'),
        'source'   => 'user',
        'count'    => count($out),
        'stations' => $out,
    ];
}

/**
 * Charge le catalogue Radio Browser et le passe dans la liste de
 * l'utilisateur (voir RadioStations::transferCatalog).
 */
function importCatalogInto(string $user, string $cacheFile, int $cacheDuration, bool $initial): int {
    if ($user === '') return 0;
    $catalog  = getStations($cacheFile, $cacheDuration);
    $stations = $catalog['stations'] ?? [];
    // Catalogue injoignable : on ne marque rien, on réessaiera plus tard.
    if (!$stations) return 0;
    // La réservation est atomique : deux requêtes en même temps ne peuvent
    // pas transférer le catalogue deux fois.
    if ($initial && !RadioStations::claimCatalogImport($user)) return 0;
    return RadioStations::transferCatalog($user, $stations, $initial);
}

/**
 * Le transfert initial, tenté à la lecture de la liste. Une fois fait, on
 * s'arrête sur une lecture de clé primaire : lister ses stations ne doit pas
 * relire le catalogue de 1200 lignes à chaque fois.
 */
function transferCatalogOnce(string $user, string $cacheFile, int $cacheDuration): void {
    if ($user === '' || RadioStations::catalogImported($user)) return;
    try {
        importCatalogInto($user, $cacheFile, $cacheDuration, true);
    } catch (\Throwable $e) {
        error_log('web-radio: transfert du catalogue échoué: ' . $e->getMessage());
    }
}

function readJsonBody(): array {
    $raw = file_get_contents('php://input');
    $j = json_decode((string)$raw, true);
    return is_array($j) ? $j : [];
}

try {
    switch ($action) {
        case 'list':
            transferCatalogOnce($user, $cacheFile, $cacheDuration);
            $data = ownStations($user);
            echo json_encode(['success' => true, 'data' => $data], JSON_UNESCAPED_UNICODE);
            break;

        case 'search':
            transferCatalogOnce($user, $cacheFile, $cacheDuration);
            $query = $_GET['q'] ?? '';
            $data = ownStations($user);
            $data['stations'] = searchStations($data['stations'], $query);
            $data['count'] = count($data['stations']);
            echo json_encode(['success' => true, 'data' => $data], JSON_UNESCAPED_UNICODE);
            break;

        case 'refresh':
            if (file_exists($cacheFile)) {
                @unlink($cacheFile);
            }
            $fresh = fetchFromRadioBrowser();
            if ($fresh && !empty($fresh['stations'])) {
                @file_put_contents($cacheFile, json_encode($fresh, JSON_UNESCAPED_UNICODE));
                echo json_encode(['success' => true, 'message' => 'Cache refreshed', 'count' => $fresh['count']], JSON_UNESCAPED_UNICODE);
            } else {
                echo json_encode(['success' => false, 'message' => 'Failed to fetch from Radio Browser API']);
            }
            break;

        case 'genres':
            $data = ownStations($user);
            $genres = getGenres($data['stations']);
            echo json_encode(['success' => true, 'data' => $genres], JSON_UNESCAPED_UNICODE);
            break;

        // ─── User-managed actions (require a session) ───
        case 'add':
            if ($user === '') { http_response_code(401); echo json_encode(['success' => false, 'error' => 'unauthenticated']); break; }
            $payload = readJsonBody();
            if (!$payload) $payload = $_POST;
            $id = RadioStations::addCustom($user, $payload);
            if ($id === false) {
                echo json_encode(['success' => false, 'error' => 'Nom et URL valides requis']);
            } else {
                $row = RadioStations::getCustom($user, $id);
                echo json_encode(['success' => true, 'id' => 'custom:' . $id, 'station' => $row]);
            }
            break;

        case 'update':
            if ($user === '') { http_response_code(401); echo json_encode(['success' => false, 'error' => 'unauthenticated']); break; }
            $payload = readJsonBody();
            $sid = $payload['station_id'] ?? '';
            if (!str_starts_with((string)$sid, 'custom:')) {
                echo json_encode(['success' => false, 'error' => 'Seules les stations personnalisées sont modifiables']);
                break;
            }
            $ok = RadioStations::updateCustom($user, (int)substr($sid, 7), $payload);
            $row = RadioStations::getCustom($user, (int)substr($sid, 7));
            echo json_encode(['success' => $ok, 'station' => $row]);
            break;

        case 'get':
            if ($user === '') { http_response_code(401); echo json_encode(['success' => false, 'error' => 'unauthenticated']); break; }
            $sid = $_REQUEST['station_id'] ?? '';
            $row = str_starts_with((string)$sid, 'custom:')
                ? RadioStations::getCustom($user, (int)substr($sid, 7))
                : null;
            echo json_encode(['success' => (bool)$row, 'station' => $row]);
            break;

        case 'add_bulk':
            if ($user === '') { http_response_code(401); echo json_encode(['success' => false, 'error' => 'unauthenticated']); break; }
            $payload = readJsonBody();
            $items   = $payload['items'] ?? [];
            if (!is_array($items) || !$items) { echo json_encode(['success' => false, 'error' => 'items[] manquant']); break; }
            $added = 0; $failed = 0;
            foreach ($items as $it) {
                $id = RadioStations::addCustom($user, is_array($it) ? $it : []);
                if ($id === false) $failed++; else $added++;
            }
            echo json_encode(['success' => true, 'added' => $added, 'failed' => $failed]);
            break;

        case 'remove':
            if ($user === '') { http_response_code(401); echo json_encode(['success' => false, 'error' => 'unauthenticated']); break; }
            // Toutes les stations appartiennent à l'utilisateur : supprimer,
            // c'est supprimer pour de bon (idée #97).
            $sid = $_REQUEST['station_id'] ?? readJsonBody()['station_id'] ?? '';
            $ok = str_starts_with((string)$sid, 'custom:')
                && RadioStations::removeCustom($user, (int)substr($sid, 7));
            echo json_encode(['success' => $ok]);
            break;

        case 'remove_bulk':
            if ($user === '') { http_response_code(401); echo json_encode(['success' => false, 'error' => 'unauthenticated']); break; }
            $sids = readJsonBody()['station_ids'] ?? [];
            if (!is_array($sids)) { echo json_encode(['success' => false, 'error' => 'station_ids[] manquant']); break; }
            $customIds = [];
            foreach ($sids as $sid) {
                $sid = (string)$sid;
                if (str_starts_with($sid, 'custom:')) $customIds[] = (int)substr($sid, 7);
            }
            $deleted = RadioStations::removeCustomBulk($user, $customIds);
            echo json_encode(['success' => true, 'deleted' => $deleted]);
            break;

        // ── Le catalogue Radio Browser, comme source d'import ─────────
        case 'import_catalog':
            // Reprendre le catalogue dans sa liste, à la demande : ce qu'il a
            // déjà (même URL de flux) n'est pas dupliqué.
            if ($user === '') { http_response_code(401); echo json_encode(['success' => false, 'error' => 'unauthenticated']); break; }
            $n = importCatalogInto($user, $cacheFile, $cacheDuration, false);
            echo json_encode(['success' => true, 'imported' => $n]);
            break;

        case 'toggle_favorite':
            if ($user === '') { http_response_code(401); echo json_encode(['success' => false, 'error' => 'unauthenticated']); break; }
            $sid = $_REQUEST['station_id'] ?? readJsonBody()['station_id'] ?? '';
            if ($sid === '') { echo json_encode(['success' => false, 'error' => 'station_id requis']); break; }
            $res = RadioStations::toggleFlag($user, (string)$sid, 'is_favorite');
            echo json_encode(['success' => true, 'favorite' => $res['favorite']]);
            break;

        // ── Folders ──────────────────────────────────────────────────
        case 'folders_list':
            if ($user === '') { http_response_code(401); echo json_encode(['success' => false, 'error' => 'unauthenticated']); break; }
            echo json_encode(['success' => true, 'folders' => RadioStations::listFolders($user)]);
            break;

        case 'folders_create':
            if ($user === '') { http_response_code(401); echo json_encode(['success' => false, 'error' => 'unauthenticated']); break; }
            $payload = readJsonBody();
            $name  = trim((string)($payload['name'] ?? ''));
            $color = $payload['color'] ?? null;
            $id = RadioStations::createFolder($user, $name, $color);
            if ($id === false) {
                echo json_encode(['success' => false, 'error' => 'Nom requis']);
            } else {
                echo json_encode(['success' => true, 'id' => $id]);
            }
            break;

        case 'folders_rename':
            if ($user === '') { http_response_code(401); echo json_encode(['success' => false, 'error' => 'unauthenticated']); break; }
            $payload = readJsonBody();
            $id    = (int)($payload['id'] ?? 0);
            $name  = trim((string)($payload['name'] ?? ''));
            $color = $payload['color'] ?? null;
            $ok = RadioStations::renameFolder($user, $id, $name, $color);
            echo json_encode(['success' => $ok]);
            break;

        case 'folders_delete':
            if ($user === '') { http_response_code(401); echo json_encode(['success' => false, 'error' => 'unauthenticated']); break; }
            $id = (int)($_REQUEST['id'] ?? readJsonBody()['id'] ?? 0);
            $ok = RadioStations::deleteFolder($user, $id);
            echo json_encode(['success' => $ok]);
            break;

        case 'station_move':
            if ($user === '') { http_response_code(401); echo json_encode(['success' => false, 'error' => 'unauthenticated']); break; }
            $payload = readJsonBody();
            $sids = $payload['station_ids'] ?? [];
            if (!is_array($sids)) $sids = [];
            $folderId = isset($payload['folder_id']) && $payload['folder_id'] !== null
                ? (int)$payload['folder_id']
                : null;
            $n = RadioStations::moveStations($user, $sids, $folderId);
            echo json_encode(['success' => true, 'moved' => $n]);
            break;

        default:
            echo json_encode(['success' => false, 'error' => 'Unknown action']);
    }
} catch (Exception $e) {
    echo json_encode(['success' => false, 'error' => $e->getMessage()]);
}
