<?php
/**
 * Artist info: biography (Last.fm) + recent news (Google News RSS)
 *
 * GET params:
 *   artist  — artist name (required)
 *   section — 'all' | 'bio' | 'news' (default: 'all')
 */
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: public, max-age=3600'); // cache 1h

require_once __DIR__ . '/../src/AppConfig.php';

$artistName = trim($_GET['artist'] ?? '');
$section    = $_GET['section'] ?? 'all';

if (!$artistName) {
    echo json_encode(['success' => false, 'error' => 'Artist name required']);
    exit;
}

$debug  = !empty($_GET['debug']);
$result = ['success' => true, 'artist' => $artistName];

if ($section === 'all' || $section === 'bio') {
    $result['bio'] = fetchLastFmBio($artistName, $debug);
}

if ($section === 'all' || $section === 'news') {
    $result['news'] = fetchGoogleNews($artistName, $debug);
}

echo json_encode($result, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);

// ─── Last.fm ──────────────────────────────────────────────────────────────────

function fetchLastFmBio(string $artist, bool $debug = false): array {
    $apiKey = AppConfig::get('lastfm.api_key');

    if (empty($apiKey)) {
        return ['available' => false, 'reason' => 'no_api_key'];
    }

    $url = 'https://ws.audioscrobbler.com/2.0/?' . http_build_query([
        'method'      => 'artist.getinfo',
        'artist'      => $artist,
        'api_key'     => $apiKey,
        'format'      => 'json',
        'autocorrect' => 1,
        'lang'        => 'fr',
    ]);

    $data = httpGet($url);
    if (!$data) {
        return ['available' => false, 'reason' => 'fetch_failed', 'debug' => $debug ? 'curl returned empty' : null];
    }

    $json = json_decode($data, true);
    if (!isset($json['artist'])) {
        return ['available' => false, 'reason' => 'not_found', 'debug' => $debug ? substr($data, 0, 300) : null];
    }

    $a = $json['artist'];

    // Clean Last.fm bio (remove "Read more on Last.fm" link at the end)
    $bioText = $a['bio']['content'] ?? '';
    $bioText = preg_replace('/<a href="https?:\/\/www\.last\.fm\/[^"]*">[^<]*<\/a>\.?/i', '', $bioText);
    $bioText = trim(strip_tags($bioText));

    $bioSummary = $a['bio']['summary'] ?? '';
    $bioSummary = preg_replace('/<a href="https?:\/\/www\.last\.fm\/[^"]*">[^<]*<\/a>\.?/i', '', $bioSummary);
    $bioSummary = trim(strip_tags($bioSummary));

    return [
        'available'      => true,
        'name'           => $a['name'] ?? $artist,
        'listeners'      => (int) ($a['stats']['listeners'] ?? 0),
        'playcount'      => (int) ($a['stats']['playcount'] ?? 0),
        'bio_summary'    => $bioSummary,
        'bio_full'       => $bioText,
        'tags'           => array_column($a['tags']['tag'] ?? [], 'name'),
        'similar'        => array_map(fn($s) => [
            'name'  => $s['name'],
            'image' => lastFmImage($s['image'] ?? []),
        ], array_slice($a['similar']['artist'] ?? [], 0, 5)),
        'url'            => $a['url'] ?? null,
    ];
}

function lastFmImage(array $images): ?string {
    foreach (array_reverse($images) as $img) {
        if (!empty($img['#text'])) return $img['#text'];
    }
    return null;
}

// ─── Google News RSS ──────────────────────────────────────────────────────────

function fetchGoogleNews(string $artist, bool $debug = false): array {
    $articles = [];
    $seenUrls = [];
    $debugInfo = [];

    $queries = [
        ['q' => '"' . $artist . '" music OR album OR concert OR tour', 'hl' => 'en-US', 'gl' => 'US', 'ceid' => 'US:en'],
        ['q' => '"' . $artist . '" musique OR album OR concert', 'hl' => 'fr-FR', 'gl' => 'FR', 'ceid' => 'FR:fr'],
    ];

    foreach ($queries as $params) {
        $url = 'https://news.google.com/rss/search?' . http_build_query($params);
        $xml = httpGet($url, 8);

        if (!$xml) {
            if ($debug) $debugInfo[] = ['url' => $url, 'error' => 'empty response'];
            continue;
        }

        libxml_use_internal_errors(true);
        $feed = simplexml_load_string($xml);
        if (!$feed) {
            if ($debug) $debugInfo[] = ['url' => $url, 'error' => 'xml parse failed', 'raw' => substr($xml, 0, 500)];
            continue;
        }

        if ($debug) $debugInfo[] = ['url' => $url, 'items_found' => count($feed->channel->item ?? [])];

        $items = $feed->channel->item ?? [];
        $count = 0;
        foreach ($items as $item) {
            if ($count >= 4) break;
            $link = (string) $item->link;
            if (in_array($link, $seenUrls)) continue;
            $seenUrls[] = $link;

            $articles[] = [
                'title'  => (string) $item->title,
                'url'    => $link,
                'source' => (string) ($item->source ?? ''),
                'date'   => (string) $item->pubDate,
            ];
            $count++;
        }
    }

    usort($articles, fn($a, $b) => strtotime($b['date']) - strtotime($a['date']));
    $articles = array_slice($articles, 0, 6);

    $result = [
        'available' => !empty($articles),
        'articles'  => $articles,
    ];
    if ($debug) $result['debug'] = $debugInfo;
    return $result;
}

// ─── HTTP helper ──────────────────────────────────────────────────────────────

function httpGet(string $url, int $timeout = 8): string|false {
    if (function_exists('curl_init')) {
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => $timeout,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_SSL_VERIFYPEER => true,
            CURLOPT_USERAGENT      => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            CURLOPT_HTTPHEADER     => ['Accept: application/rss+xml, application/xml, text/xml, */*'],
        ]);
        $result = curl_exec($ch);
        curl_close($ch);
        return $result ?: false;
    }

    // Fallback
    $ctx = stream_context_create(['http' => [
        'timeout'        => $timeout,
        'user_agent'     => 'Mozilla/5.0 (compatible; Gullify/1.0)',
        'follow_location' => true,
    ]]);
    return @file_get_contents($url, false, $ctx);
}
