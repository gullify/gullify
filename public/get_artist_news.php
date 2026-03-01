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

$result = ['success' => true, 'artist' => $artistName];

if ($section === 'all' || $section === 'bio') {
    $result['bio'] = fetchLastFmBio($artistName);
}

if ($section === 'all' || $section === 'news') {
    $result['news'] = fetchGoogleNews($artistName);
}

echo json_encode($result, JSON_UNESCAPED_UNICODE);

// ─── Last.fm ──────────────────────────────────────────────────────────────────

function fetchLastFmBio(string $artist): array {
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
        return ['available' => false, 'reason' => 'fetch_failed'];
    }

    $json = json_decode($data, true);
    if (!isset($json['artist'])) {
        return ['available' => false, 'reason' => 'not_found'];
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

function fetchGoogleNews(string $artist): array {
    $articles = [];
    $seenUrls = [];

    $queries = [
        ['q' => '"' . $artist . '" music OR album OR concert OR tour', 'hl' => 'en', 'gl' => 'US', 'ceid' => 'US:en'],
        ['q' => '"' . $artist . '" musique OR album OR concert OR tournée', 'hl' => 'fr', 'gl' => 'FR', 'ceid' => 'FR:fr'],
    ];

    foreach ($queries as $params) {
        $url = 'https://news.google.com/rss/search?' . http_build_query($params);
        $xml = httpGet($url, 5);
        if (!$xml) continue;

        $feed = @simplexml_load_string($xml);
        if (!$feed) continue;

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

    // Sort by date descending, keep top 6
    usort($articles, fn($a, $b) => strtotime($b['date']) - strtotime($a['date']));
    $articles = array_slice($articles, 0, 6);

    return [
        'available' => !empty($articles),
        'articles'  => $articles,
    ];
}

// ─── HTTP helper ──────────────────────────────────────────────────────────────

function httpGet(string $url, int $timeout = 8): string|false {
    $ctx = stream_context_create(['http' => [
        'timeout'          => $timeout,
        'user_agent'       => 'Gullify/1.0',
        'follow_location'  => true,
        'ignore_errors'    => true,
    ]]);
    return @file_get_contents($url, false, $ctx);
}
