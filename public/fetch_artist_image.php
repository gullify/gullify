<?php
/**
 * Gullify — Auto-fetch high-res artist image from Deezer (free, no API key).
 *
 *   GET ?artist_id=N
 *
 * Strategy:
 *   1. Look up the artist's name in the DB
 *   2. Search Deezer (api.deezer.com/search/artist) and pick the best match
 *   3. Download picture_xl (1000×1000 JPEG)
 *   4. Save to data/cache/artwork/artist_{id}.jpg, clear DB blob
 *
 * Returns { error, message, source: 'deezer', size, matched_name }
 */

ini_set('display_errors', 0);
header('Content-Type: application/json');

require_once __DIR__ . '/../src/AppConfig.php';
require_once __DIR__ . '/../src/auth_required.php';

function fail(string $msg, int $code = 400): never
{
    http_response_code($code);
    echo json_encode(['error' => true, 'message' => $msg]);
    exit;
}

try {
    $artistId = (int)($_GET['artist_id'] ?? 0);
    if ($artistId <= 0) fail('artist_id requis');

    $db = AppConfig::getDB();

    // Permission check: artist must belong to the current user
    $stmt = $db->prepare('SELECT id, name, user FROM artists WHERE id = ?');
    $stmt->execute([$artistId]);
    $artist = $stmt->fetch();
    if (!$artist) fail('Artiste introuvable', 404);
    $sessionUser = $_SESSION['username'] ?? '';
    if ($sessionUser !== '' && $artist['user'] !== $sessionUser && empty($_SESSION['is_admin'])) {
        fail('Accès refusé', 403);
    }

    if (!function_exists('curl_init')) {
        fail("L'extension curl PHP n'est pas disponible", 500);
    }

    $name = trim($artist['name']);
    if ($name === '') fail("L'artiste n'a pas de nom");

    // 1. Search Deezer for the artist
    $searchUrl = 'https://api.deezer.com/search/artist?limit=5&q=' . urlencode($name);
    $ch = curl_init($searchUrl);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 8,
        CURLOPT_USERAGENT      => 'Gullify/1.0 (self-hosted music player)',
        CURLOPT_HTTPHEADER     => ['Accept: application/json'],
    ]);
    $body   = curl_exec($ch);
    $status = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $err    = curl_error($ch);
    curl_close($ch);

    if ($status !== 200 || !$body) fail("Deezer search failed (HTTP $status): $err", 502);

    $payload = json_decode($body, true);
    $hits = $payload['data'] ?? [];
    if (!$hits) fail("Aucun résultat Deezer pour « $name »", 404);

    // Prefer an exact case-insensitive name match; otherwise take the first hit
    $best = null;
    foreach ($hits as $hit) {
        if (mb_strtolower($hit['name'] ?? '') === mb_strtolower($name)) {
            $best = $hit;
            break;
        }
    }
    $best ??= $hits[0];

    $imgUrl = $best['picture_xl'] ?? $best['picture_big'] ?? null;
    if (!$imgUrl) fail('Aucune image picture_xl chez Deezer pour cet artiste', 502);

    // 2. Download the image
    $ch = curl_init($imgUrl);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 12,
        CURLOPT_USERAGENT      => 'Gullify/1.0',
    ]);
    $imgData = curl_exec($ch);
    $imgCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($imgCode !== 200 || !$imgData || strlen($imgData) < 200) {
        fail("Téléchargement de l'image a échoué (HTTP $imgCode)", 502);
    }

    // 3. Save to cache file
    $cacheDir = AppConfig::getDataPath() . '/cache/artwork';
    if (!is_dir($cacheDir)) @mkdir($cacheDir, 0775, true);
    $cacheFile = $cacheDir . '/artist_' . $artistId . '.jpg';
    if (@file_put_contents($cacheFile, $imgData) === false) {
        fail("Impossible d'écrire $cacheFile", 500);
    }
    @chmod($cacheFile, 0644);

    // Clear the legacy DB blob so serve_image.php prefers the new file
    $stmt = $db->prepare('UPDATE artists SET image = NULL WHERE id = ?');
    $stmt->execute([$artistId]);

    echo json_encode([
        'error'        => false,
        'message'      => 'Image HD récupérée depuis Deezer',
        'source'       => 'deezer',
        'matched_name' => $best['name'] ?? null,
        'size'         => strlen($imgData),
        'cached'       => true,
    ]);
} catch (\Throwable $e) {
    http_response_code(500);
    echo json_encode(['error' => true, 'message' => $e->getMessage()]);
}
