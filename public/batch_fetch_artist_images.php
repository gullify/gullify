<?php
/**
 * Gullify — Batch Deezer fetch for all artist images of the current user.
 *
 *   POST ?action=start  → kick off a background process; returns immediately
 *   GET  ?action=status → live progress (read-only)
 *   POST ?action=cancel → request cancellation (cooperative, checked on each tick)
 *
 * Progress is written to /tmp/gullify-artist-batch-{user}.json so multiple
 * users don't collide. The worker itself runs as the same PHP process via a
 * detached background command.
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
    $base = sys_get_temp_dir();
    return $base . '/gullify-artist-batch-' . preg_replace('/[^a-z0-9_]/i', '_', $user) . '.json';
}

function readProgress(string $user): array
{
    $f = progressFile($user);
    if (!file_exists($f)) return ['running' => false];
    $j = json_decode(@file_get_contents($f), true);
    return is_array($j) ? $j : ['running' => false];
}

function writeProgress(string $user, array $state): void
{
    @file_put_contents(progressFile($user), json_encode($state));
}

function deezerSearch(string $name, ?string &$matchedName = null): ?string
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
    $matchedName = $best['name'] ?? null;
    return $best['picture_xl'] ?? $best['picture_big'] ?? null;
}

function downloadImage(string $url): ?string
{
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 12,
        CURLOPT_USERAGENT      => 'Gullify/1.0',
    ]);
    $bin = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    if ($code !== 200 || !$bin || strlen($bin) < 200) return null;
    return $bin;
}

function runBatch(string $user, bool $onlyMissing): void
{
    $startState = readProgress($user);
    // Cancellation flag survives; running flag should be true here
    writeProgress($user, [
        'running'   => true,
        'started_at' => time(),
        'cancel'    => false,
        'phase'     => 'init',
        'total'     => 0,
        'processed' => 0,
        'updated'   => 0,
        'skipped'   => 0,
        'failed'    => 0,
        'current'   => null,
        'last_error'=> null,
    ]);

    try {
        $db = AppConfig::getDB();
        $stmt = $db->prepare('SELECT id, name FROM artists WHERE user = ? ORDER BY name ASC');
        $stmt->execute([$user]);
        $artists = $stmt->fetchAll(\PDO::FETCH_ASSOC);

        $cacheDir = AppConfig::getDataPath() . '/cache/artwork';
        if (!is_dir($cacheDir)) @mkdir($cacheDir, 0775, true);

        $total = count($artists);
        $state = readProgress($user);
        $state['total'] = $total;
        $state['phase'] = 'fetching';
        writeProgress($user, $state);

        $updated = 0; $skipped = 0; $failed = 0;
        foreach ($artists as $i => $a) {
            // Re-read state to honor cancel
            $cur = readProgress($user);
            if (!empty($cur['cancel'])) {
                $cur['phase'] = 'cancelled';
                $cur['running'] = false;
                writeProgress($user, $cur);
                return;
            }

            $cacheFile = $cacheDir . '/artist_' . $a['id'] . '.jpg';
            // "Only missing" mode: skip artists that already have a non-trivial cached file
            if ($onlyMissing && file_exists($cacheFile) && filesize($cacheFile) > 50000) {
                $skipped++;
            } else {
                $matched = null;
                $imgUrl  = deezerSearch($a['name'], $matched);
                if ($imgUrl) {
                    $bin = downloadImage($imgUrl);
                    if ($bin && @file_put_contents($cacheFile, $bin) !== false) {
                        @chmod($cacheFile, 0644);
                        // Clear legacy DB blob
                        $u = $db->prepare('UPDATE artists SET image = NULL WHERE id = ?');
                        $u->execute([$a['id']]);
                        $updated++;
                    } else {
                        $failed++;
                    }
                } else {
                    $failed++;
                }
                // Be polite to Deezer's free API: ~3 req/s
                usleep(350_000);
            }

            $cur = readProgress($user);
            $cur['processed'] = $i + 1;
            $cur['updated']   = $updated;
            $cur['skipped']   = $skipped;
            $cur['failed']    = $failed;
            $cur['current']   = $a['name'];
            writeProgress($user, $cur);
        }

        $cur = readProgress($user);
        $cur['phase']   = 'done';
        $cur['running'] = false;
        $cur['ended_at'] = time();
        writeProgress($user, $cur);

        // Push a notification with the summary
        try {
            Notifications::add($user, 'images_refresh',
                'Images artistes mises à jour',
                sprintf('%d mis à jour · %d ignorés · %d échec', $updated, $skipped, $failed),
                ['updated' => $updated, 'skipped' => $skipped, 'failed' => $failed]
            );
        } catch (\Throwable $e) { /* notifications are best-effort */ }
    } catch (\Throwable $e) {
        $cur = readProgress($user);
        $cur['phase']     = 'error';
        $cur['running']   = false;
        $cur['last_error']= $e->getMessage();
        writeProgress($user, $cur);
    }
}

if ($action === 'start') {
    if (!function_exists('curl_init')) {
        echo json_encode(['success' => false, 'error' => 'curl missing']);
        exit;
    }
    $existing = readProgress($user);
    if (!empty($existing['running'])) {
        echo json_encode(['success' => false, 'error' => 'already running', 'state' => $existing]);
        exit;
    }
    $onlyMissing = !empty($_REQUEST['only_missing']);

    // Detach: spawn a background PHP process so the request returns immediately
    $self = __FILE__;
    $cmd  = sprintf(
        '%s %s %s %s > /dev/null 2>&1 &',
        escapeshellcmd(PHP_BINARY),
        escapeshellarg($self),
        '--worker',
        ($onlyMissing ? '1' : '0')
    );
    // Pass the user via env (PHP_AUTH_USER won't survive)
    putenv('GULLIFY_BATCH_USER=' . $user);
    // Mark as running BEFORE spawn so quick polls see it
    writeProgress($user, ['running' => true, 'phase' => 'starting', 'cancel' => false]);
    if (function_exists('exec')) {
        exec("GULLIFY_BATCH_USER=" . escapeshellarg($user) . " " . $cmd);
    } else {
        // Fallback: run inline (will block the request)
        runBatch($user, $onlyMissing);
    }
    echo json_encode(['success' => true, 'started' => true]);
    exit;
}

if ($action === 'cancel') {
    $cur = readProgress($user);
    if (!empty($cur['running'])) {
        $cur['cancel'] = true;
        writeProgress($user, $cur);
    }
    echo json_encode(['success' => true]);
    exit;
}

if ($action === 'status') {
    echo json_encode(['success' => true, 'state' => readProgress($user)]);
    exit;
}

// CLI worker mode
if (PHP_SAPI === 'cli' && in_array('--worker', $argv ?? [], true)) {
    $cliUser = getenv('GULLIFY_BATCH_USER') ?: '';
    $only    = (($argv[2] ?? '0') === '1');
    if ($cliUser !== '') runBatch($cliUser, $only);
    exit;
}

echo json_encode(['success' => false, 'error' => 'unknown action']);
