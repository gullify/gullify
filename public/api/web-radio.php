<?php
/**
 * Gullify - Web Radio API
 * Uses Radio Browser API - Fetches and caches Canadian radio stations
 * Migrated from web_radio_api.php
 */

require_once __DIR__ . '/../../src/AppConfig.php';

header('Content-Type: application/json');
header('Cache-Control: no-cache');

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

try {
    switch ($action) {
        case 'list':
            $data = getStations($cacheFile, $cacheDuration);
            echo json_encode(['success' => true, 'data' => $data], JSON_UNESCAPED_UNICODE);
            break;

        case 'search':
            $query = $_GET['q'] ?? '';
            $data = getStations($cacheFile, $cacheDuration);
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
            $data = getStations($cacheFile, $cacheDuration);
            $genres = getGenres($data['stations']);
            echo json_encode(['success' => true, 'data' => $genres], JSON_UNESCAPED_UNICODE);
            break;

        default:
            echo json_encode(['success' => false, 'error' => 'Unknown action']);
    }
} catch (Exception $e) {
    echo json_encode(['success' => false, 'error' => $e->getMessage()]);
}
