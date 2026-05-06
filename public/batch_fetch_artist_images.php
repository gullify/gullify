<?php
/**
 * Gullify — Chunked HD artist images fetcher.
 *
 *   POST ?action=start[&only_missing=1]   → initialise state, return first status
 *   POST ?action=process[&chunk=N]        → process next N artists (default 1), return state
 *   POST ?action=cancel                   → stop after current chunk
 *   POST ?action=reset                    → wipe state (use to recover from stuck "already running")
 *   GET  ?action=status                   → current state, no work
 *
 * Each artist tries:
 *   1) YouTube Music (best for francophone / niche; via python/ytmusic_search.py)
 *   2) Deezer (fallback when YT has nothing)
 *
 * State lives in /tmp/gullify-artist-batch-{user}.json.
 *
 * No detached worker, no exec, no cron. The frontend pings this endpoint
 * every couple of seconds and each call does ~1 chunk of synchronous work.
 */

ini_set('display_errors', 0);
header('Content-Type: application/json');

require_once __DIR__ . '/../src/AppConfig.php';
require_once __DIR__ . '/../src/auth_required.php';
require_once __DIR__ . '/../src/Notifications.php';

$user   = $_SESSION['username'] ?? '';
$action = $_GET['action'] ?? 'status';

if ($user === '') {
    http_response_code(401);
    echo json_encode(['success' => false, 'error' => 'unauthenticated']);
    exit;
}

function progressFile(string $user): string
{
    return sys_get_temp_dir() . '/gullify-artist-batch-' . preg_replace('/[^a-z0-9_]/i', '_', $user) . '.json';
}

function readProgress(string $user): array
{
    $f = progressFile($user);
    if (!file_exists($f)) return ['running' => false, 'phase' => 'idle'];
    $j = json_decode(@file_get_contents($f), true);
    return is_array($j) ? $j : ['running' => false, 'phase' => 'idle'];
}

function writeProgress(string $user, array $state): void
{
    @file_put_contents(progressFile($user), json_encode($state));
}

function ytMusicArtistImage(string $name): ?string
{
    $script = AppConfig::getPythonPath() . '/ytmusic_search.py';
    if (!file_exists($script)) return null;
    $python = is_executable('/opt/ytdlp/bin/python3') ? '/opt/ytdlp/bin/python3' : 'python3';
    $cmd    = sprintf('%s %s artist %s 2>/dev/null',
        $python,
        escapeshellarg($script),
        escapeshellarg($name)
    );
    $out = @shell_exec($cmd);
    if (!$out) return null;
    $data = json_decode($out, true);
    $hits = $data['results'] ?? [];
    if (!$hits) return null;

    // Prefer an exact case-insensitive match
    $exact = null;
    foreach ($hits as $h) {
        if (mb_strtolower($h['name'] ?? '') === mb_strtolower($name)) { $exact = $h; break; }
    }
    $best = $exact ?? $hits[0];
    $thumb = $best['thumbnail'] ?? '';
    if (!$thumb) return null;
    // YT thumbnails come back at the smallest size in some setups —
    // upgrade common width tokens to a 1000px version.
    $thumb = preg_replace('/=w\d+-h\d+/', '=w1000-h1000', $thumb);
    return $thumb;
}

function deezerArtistImage(string $name): ?string
{
    $url = 'https://api.deezer.com/search/artist?limit=5&q=' . urlencode($name);
    $ch  = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 8,
        CURLOPT_USERAGENT      => 'Gullify/1.0',
    ]);
    $body = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    if ($code !== 200 || !$body) return null;
    $data = json_decode($body, true);
    $hits = $data['data'] ?? [];
    if (!$hits) return null;
    $best = null;
    foreach ($hits as $h) {
        if (mb_strtolower($h['name'] ?? '') === mb_strtolower($name)) { $best = $h; break; }
    }
    $best ??= $hits[0];
    return $best['picture_xl'] ?? $best['picture_big'] ?? null;
}

function downloadImage(string $url): ?string
{
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 12,
        CURLOPT_USERAGENT      => 'Gullify/1.0',
        CURLOPT_FOLLOWLOCATION => true,
    ]);
    $bin  = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    if ($code !== 200 || !$bin || strlen($bin) < 200) return null;
    return $bin;
}

function fetchOneArtist(string $name): ?array
{
    // YouTube Music first (better for francophone / niche)
    $url = ytMusicArtistImage($name);
    $src = 'ytmusic';
    if (!$url) {
        $url = deezerArtistImage($name);
        $src = 'deezer';
    }
    if (!$url) return null;

    $bin = downloadImage($url);
    if (!$bin) return null;
    return ['data' => $bin, 'source' => $src];
}

function startBatch(string $user, bool $onlyMissing): array
{
    $db = AppConfig::getDB();
    $stmt = $db->prepare('SELECT id, name FROM artists WHERE user = ? ORDER BY name ASC');
    $stmt->execute([$user]);
    $rows = $stmt->fetchAll(\PDO::FETCH_ASSOC);

    $cacheDir = AppConfig::getDataPath() . '/cache/artwork';
    if (!is_dir($cacheDir)) @mkdir($cacheDir, 0775, true);

    $pending = [];
    $skipped = 0;
    foreach ($rows as $a) {
        $cacheFile = $cacheDir . '/artist_' . $a['id'] . '.jpg';
        if ($onlyMissing && file_exists($cacheFile) && filesize($cacheFile) > 50000) {
            $skipped++;
            continue;
        }
        $pending[] = ['id' => (int)$a['id'], 'name' => $a['name']];
    }

    $state = [
        'running'    => count($pending) > 0,
        'phase'      => count($pending) > 0 ? 'fetching' : 'done',
        'started_at' => time(),
        'cancel'     => false,
        'pending'    => $pending,
        'total'      => count($rows),
        'processed'  => 0,
        'updated'    => 0,
        'skipped'    => $skipped,
        'failed'     => 0,
        'current'    => null,
        'last_error' => null,
        'last_source'=> null,
        'only_missing' => $onlyMissing,
    ];
    writeProgress($user, $state);
    return $state;
}

function processChunk(string $user, int $chunkSize): array
{
    $state = readProgress($user);
    if (empty($state['running'])) return $state;
    if (!empty($state['cancel'])) {
        $state['running'] = false;
        $state['phase']   = 'cancelled';
        writeProgress($user, $state);
        return $state;
    }

    $cacheDir = AppConfig::getDataPath() . '/cache/artwork';
    if (!is_dir($cacheDir)) @mkdir($cacheDir, 0775, true);
    $db = AppConfig::getDB();

    $chunkSize = max(1, min(5, $chunkSize));
    for ($i = 0; $i < $chunkSize && !empty($state['pending']); $i++) {
        $artist = array_shift($state['pending']);
        $state['current'] = $artist['name'];
        try {
            $res = fetchOneArtist($artist['name']);
            if ($res !== null) {
                $cacheFile = $cacheDir . '/artist_' . $artist['id'] . '.jpg';
                if (@file_put_contents($cacheFile, $res['data']) !== false) {
                    @chmod($cacheFile, 0644);
                    $upd = $db->prepare('UPDATE artists SET image = NULL WHERE id = ?');
                    $upd->execute([$artist['id']]);
                    $state['updated']++;
                    $state['last_source'] = $res['source'];
                } else {
                    $state['failed']++;
                }
            } else {
                $state['failed']++;
            }
        } catch (\Throwable $e) {
            $state['failed']++;
            $state['last_error'] = $e->getMessage();
        }
        $state['processed']++;
    }

    if (empty($state['pending'])) {
        $state['running']  = false;
        $state['phase']    = 'done';
        $state['ended_at'] = time();
        try {
            Notifications::add(
                $user,
                'images_refresh',
                'Images artistes mises à jour',
                sprintf('%d mis à jour · %d ignorés · %d échec',
                    $state['updated'], $state['skipped'], $state['failed']),
                ['updated' => $state['updated'], 'skipped' => $state['skipped'], 'failed' => $state['failed']]
            );
        } catch (\Throwable $e) { /* best-effort */ }
    }

    writeProgress($user, $state);
    return $state;
}

try {
    if ($action === 'start') {
        if (!function_exists('curl_init')) {
            echo json_encode(['success' => false, 'error' => 'curl missing']);
            exit;
        }
        $existing = readProgress($user);
        // Self-heal: if "running" but stale > 60 s without progress, allow restart
        $stale = !empty($existing['running']) &&
                 (time() - (int)($existing['started_at'] ?? 0) > 60) &&
                 ($existing['processed'] ?? 0) === 0;
        if (!empty($existing['running']) && !$stale) {
            echo json_encode(['success' => false, 'error' => 'already_running', 'state' => $existing]);
            exit;
        }
        $state = startBatch($user, !empty($_REQUEST['only_missing']));
        echo json_encode(['success' => true, 'state' => $state]);
    } elseif ($action === 'process') {
        $chunk = (int)($_REQUEST['chunk'] ?? 1);
        $state = processChunk($user, $chunk);
        echo json_encode(['success' => true, 'state' => $state]);
    } elseif ($action === 'cancel') {
        $state = readProgress($user);
        $state['cancel'] = true;
        writeProgress($user, $state);
        echo json_encode(['success' => true, 'state' => $state]);
    } elseif ($action === 'reset') {
        @unlink(progressFile($user));
        echo json_encode(['success' => true, 'state' => ['running' => false, 'phase' => 'idle']]);
    } elseif ($action === 'status') {
        echo json_encode(['success' => true, 'state' => readProgress($user)]);
    } else {
        echo json_encode(['success' => false, 'error' => 'unknown action']);
    }
} catch (\Throwable $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'error' => $e->getMessage()]);
}
