<?php
/**
 * Gullify API v2 - Vidéos (natif)
 *
 *   GET  ?action=search&q=…&limit=20  → [{id,title,channel,duration,thumbnail,live}]
 *   GET  ?action=library              → [{id,title,channel,duration,thumbnail,
 *                                         status,progress,size,addedAt}]
 *   GET  ?action=stream&id=…          → OCTETS vidéo (pas d'enveloppe JSON) :
 *                                       fichier local si la vidéo a été
 *                                       téléchargée, sinon relais du flux
 *                                       YouTube. Les requêtes Range sont
 *                                       honorées (avance/recul du lecteur).
 *   POST ?action=download {id,title,channel,duration,thumbnail} → null
 *   POST ?action=delete   {id}        → null
 *
 * Pourquoi relayer le flux plutôt que renvoyer l'URL à l'app : les URL
 * googlevideo sont liées à l'IP qui les a résolues (paramètre `ip=`), donc
 * inutilisables depuis le téléphone. Le relais ne peut servir qu'un format
 * « progressif » (audio+vidéo dans un seul fichier, 360p la plupart du temps);
 * pour la HD il faut télécharger la vidéo (yt-dlp fusionne alors les pistes).
 */
declare(strict_types=1);

require_once __DIR__ . '/_v2.php';
require_once __DIR__ . '/../../../src/AppConfig.php';

$ctx    = v2_auth();
$action = $_GET['action'] ?? $_POST['action'] ?? 'search';
$body   = v2_body();

/** Répertoire des vidéos téléchargées (volume persistant `data/`). */
function vid_dir(): string {
    $dir = AppConfig::getDataPath() . '/videos';
    if (!is_dir($dir)) @mkdir($dir, 0775, true);
    return $dir;
}

/** Répertoire de cache (recherches et URL résolues). */
function vid_cache_dir(string $kind): string {
    $dir = AppConfig::getDataPath() . '/cache/videos/' . $kind;
    if (!is_dir($dir)) @mkdir($dir, 0775, true);
    return $dir;
}

/**
 * Un identifiant YouTube et rien d'autre : ces valeurs finissent dans une
 * ligne de commande yt-dlp et dans des noms de fichiers.
 */
function vid_id(string $raw): string {
    $id = trim($raw);
    if (!preg_match('/^[A-Za-z0-9_-]{11}$/', $id)) {
        v2_fail('invalid_request', 'Identifiant de vidéo invalide');
    }
    return $id;
}

function vid_meta_path(string $id): string { return vid_dir() . "/$id.json"; }
function vid_file_path(string $id): string { return vid_dir() . "/$id.mp4"; }
function vid_log_path(string $id): string  { return vid_dir() . "/$id.log"; }

function vid_read_meta(string $id): ?array {
    $p = vid_meta_path($id);
    if (!is_file($p)) return null;
    $j = json_decode((string)@file_get_contents($p), true);
    return is_array($j) ? $j : null;
}

function vid_write_meta(string $id, array $meta): void {
    @file_put_contents(
        vid_meta_path($id),
        json_encode($meta, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE)
    );
}

/**
 * Avancement d'un téléchargement en cours, lu dans la sortie de yt-dlp
 * (dernier « [download]  42.3% » du journal).
 */
function vid_progress(string $id): int {
    $log = vid_log_path($id);
    if (!is_file($log)) return 0;
    $size = filesize($log) ?: 0;
    $fh   = @fopen($log, 'r');
    if (!$fh) return 0;
    // Le journal grossit à coups de retours chariot : la fin suffit.
    if ($size > 8192) fseek($fh, -8192, SEEK_END);
    $tail = (string)stream_get_contents($fh);
    fclose($fh);
    if (preg_match_all('/(\d{1,3}(?:\.\d)?)%/', $tail, $m) === 0) return 0;
    // yt-dlp télécharge la vidéo puis le son (deux fois 0→100 %) avant de
    // fusionner : on ne montre 100 % qu'une fois le fichier réellement prêt.
    return min(99, (int)round((float)end($m[1])));
}

/**
 * Le processus yt-dlp de cette vidéo tourne-t-il encore ?
 *
 * `[y]t-dlp` et pas `yt-dlp` : sans ça le motif se trouve lui-même dans la
 * ligne de commande du shell lancé par PHP, et tout téléchargement paraissait
 * éternellement en cours.
 */
function vid_running(string $id): bool {
    $out = (string)@shell_exec('pgrep -f ' . escapeshellarg("[y]t-dlp.*$id") . ' 2>/dev/null');
    return trim($out) !== '';
}

/** Miniature YouTube : URL publique et stable, pas besoin de la relayer. */
function vid_thumb(string $id): string {
    return "https://i.ytimg.com/vi/$id/hqdefault.jpg";
}

/** Chemin du binaire yt-dlp (installé dans l'image docker). */
function vid_ytdlp(): string {
    return is_file('/usr/local/bin/yt-dlp') ? '/usr/local/bin/yt-dlp' : 'yt-dlp';
}

/**
 * Sert un fichier local en honorant l'en-tête Range (indispensable : sans ça
 * le lecteur ne peut pas se déplacer dans la vidéo).
 */
function vid_serve_file(string $path): never {
    $size  = (int)filesize($path);
    $start = 0;
    $end   = $size - 1;
    $range = $_SERVER['HTTP_RANGE'] ?? '';
    $partial = false;

    if ($range !== '' && preg_match('/bytes=(\d*)-(\d*)/', $range, $m)) {
        if ($m[1] !== '') $start = (int)$m[1];
        if ($m[2] !== '') $end   = min((int)$m[2], $size - 1);
        if ($start > $end || $start >= $size) {
            header('Content-Range: bytes */' . $size);
            http_response_code(416);
            exit;
        }
        $partial = true;
    }

    while (ob_get_level() > 0) ob_end_clean();
    header_remove('Content-Type');
    header('Content-Type: video/mp4');
    header('Accept-Ranges: bytes');
    header('Content-Length: ' . ($end - $start + 1));
    if ($partial) {
        http_response_code(206);
        header("Content-Range: bytes $start-$end/$size");
    }

    $fh = fopen($path, 'rb');
    if (!$fh) { http_response_code(500); exit; }
    fseek($fh, $start);
    $remaining = $end - $start + 1;
    while ($remaining > 0 && !feof($fh) && !connection_aborted()) {
        $chunk = fread($fh, (int)min(262144, $remaining));
        if ($chunk === false || $chunk === '') break;
        echo $chunk;
        flush();
        $remaining -= strlen($chunk);
    }
    fclose($fh);
    exit;
}

/**
 * Résout (et met en cache) l'URL d'un format progressif. Le cache expire un
 * peu avant l'URL elle-même (paramètre `expire=`), qui ne vaut que quelques
 * heures.
 */
function vid_resolve_url(string $id): ?string {
    $cachePath = vid_cache_dir('urls') . "/$id.json";
    if (is_file($cachePath)) {
        $c = json_decode((string)@file_get_contents($cachePath), true);
        if (is_array($c) && ($c['expiresAt'] ?? 0) > time() && !empty($c['url'])) {
            return (string)$c['url'];
        }
    }

    $cmd = vid_ytdlp()
        . ' --no-warnings --no-playlist --socket-timeout 20'
        . ' -f ' . escapeshellarg('b[ext=mp4][acodec!=none][vcodec!=none]/b[acodec!=none][vcodec!=none]')
        . ' --print urls '
        . escapeshellarg("https://www.youtube.com/watch?v=$id")
        . ' 2>/dev/null';
    $url = trim((string)@shell_exec($cmd));
    if ($url === '' || !str_starts_with($url, 'http')) return null;
    // Une seule ligne attendue (format progressif); on ignore le reste.
    $url = strtok($url, "\n") ?: $url;

    $expire = 0;
    if (preg_match('/[?&]expire=(\d+)/', $url, $m)) $expire = (int)$m[1];
    $expiresAt = $expire > 0 ? $expire - 300 : time() + 1800;
    @file_put_contents($cachePath, json_encode(['url' => $url, 'expiresAt' => $expiresAt]));
    return $url;
}

/** Relaie un flux distant en réémettant statut, Range et longueur. */
function vid_proxy(string $url): never {
    while (ob_get_level() > 0) ob_end_clean();
    header_remove('Content-Type');
    set_time_limit(0);

    $headers = ['User-Agent: Mozilla/5.0 (Android) Gullify'];
    if (!empty($_SERVER['HTTP_RANGE'])) $headers[] = 'Range: ' . $_SERVER['HTTP_RANGE'];

    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_HTTPHEADER     => $headers,
        CURLOPT_FOLLOWLOCATION => true,
        CURLOPT_CONNECTTIMEOUT => 15,
        CURLOPT_TIMEOUT        => 0,
        CURLOPT_HEADERFUNCTION => function ($ch, string $line): int {
            $len = strlen($line);
            if (preg_match('#^HTTP/[\d.]+\s+(\d{3})#', $line, $m)) {
                http_response_code((int)$m[1]);
                return $len;
            }
            $parts = explode(':', $line, 2);
            if (count($parts) === 2) {
                $name = strtolower(trim($parts[0]));
                if (in_array($name, ['content-type', 'content-length', 'content-range', 'accept-ranges'], true)) {
                    header(trim($parts[0]) . ': ' . trim($parts[1]));
                }
            }
            return $len;
        },
        CURLOPT_WRITEFUNCTION => function ($ch, string $data): int {
            if (connection_aborted()) return -1;
            echo $data;
            flush();
            return strlen($data);
        },
    ]);
    curl_exec($ch);
    curl_close($ch);
    exit;
}

try {
    switch ($action) {
        // ───────────────────────── Recherche ─────────────────────────
        case 'search': {
            $q     = trim((string)($_GET['q'] ?? ''));
            $limit = max(1, min(30, (int)($_GET['limit'] ?? 20)));
            if ($q === '') v2_ok([]);

            $cachePath = vid_cache_dir('search') . '/' . md5("$q|$limit") . '.json';
            if (is_file($cachePath) && filemtime($cachePath) > time() - 1800) {
                $cached = json_decode((string)@file_get_contents($cachePath), true);
                if (is_array($cached)) v2_ok($cached);
            }

            $cmd = vid_ytdlp()
                . ' --flat-playlist -J --no-warnings --socket-timeout 20 '
                . escapeshellarg("ytsearch$limit:$q") . ' 2>/dev/null';
            $raw = (string)@shell_exec($cmd);
            $json = json_decode($raw, true);
            if (!is_array($json) || !isset($json['entries'])) {
                v2_fail('upstream_error', 'Recherche YouTube indisponible', 502);
            }

            $out = [];
            foreach ($json['entries'] as $e) {
                $id = (string)($e['id'] ?? '');
                if (!preg_match('/^[A-Za-z0-9_-]{11}$/', $id)) continue;
                $live = ($e['live_status'] ?? '') === 'is_live';
                $out[] = [
                    'id'        => $id,
                    'title'     => (string)($e['title'] ?? ''),
                    'channel'   => (string)($e['channel'] ?? $e['uploader'] ?? ''),
                    'duration'  => (int)round((float)($e['duration'] ?? 0)),
                    'thumbnail' => vid_thumb($id),
                    'live'      => $live,
                ];
            }
            @file_put_contents($cachePath, json_encode($out, JSON_UNESCAPED_UNICODE));
            v2_ok($out);
        }

        // ──────────────── Vidéothèque locale (serveur) ────────────────
        case 'library': {
            $out = [];
            foreach (glob(vid_dir() . '/*.json') ?: [] as $metaFile) {
                $meta = json_decode((string)@file_get_contents($metaFile), true);
                if (!is_array($meta) || empty($meta['id'])) continue;
                $id     = (string)$meta['id'];
                $file   = vid_file_path($id);
                $ready  = is_file($file) && filesize($file) > 0;
                $status = (string)($meta['status'] ?? 'downloading');

                if ($status === 'downloading') {
                    if ($ready && !vid_running($id)) {
                        $status = 'ready';
                        $meta['status'] = 'ready';
                        vid_write_meta($id, $meta);
                        @unlink(vid_log_path($id));
                    } elseif (!$ready && !vid_running($id)) {
                        // Processus terminé sans fichier : échec.
                        $status = 'error';
                        $meta['status'] = 'error';
                        vid_write_meta($id, $meta);
                    }
                }

                $out[] = [
                    'id'        => $id,
                    'title'     => (string)($meta['title'] ?? $id),
                    'channel'   => (string)($meta['channel'] ?? ''),
                    'duration'  => (int)($meta['duration'] ?? 0),
                    'thumbnail' => (string)($meta['thumbnail'] ?? vid_thumb($id)),
                    'status'    => $status,
                    'progress'  => $status === 'downloading' ? vid_progress($id) : 100,
                    'size'      => $ready ? (int)filesize($file) : 0,
                    'addedAt'   => (int)($meta['addedAt'] ?? 0),
                ];
            }
            usort($out, fn($a, $b) => $b['addedAt'] <=> $a['addedAt']);
            v2_ok($out);
        }

        // ─────────────────── Lecture (octets bruts) ───────────────────
        case 'stream': {
            $id   = vid_id((string)($_GET['id'] ?? ''));
            $file = vid_file_path($id);
            // La copie locale prime : meilleure qualité et aucun aléa YouTube.
            if (is_file($file) && filesize($file) > 0 && !vid_running($id)) {
                vid_serve_file($file);
            }
            $url = vid_resolve_url($id);
            if ($url === null) v2_fail('upstream_error', 'Flux vidéo introuvable', 502);
            vid_proxy($url);
        }

        // ───────────────────── Téléchargement ─────────────────────
        case 'download': {
            $id = vid_id((string)($body['id'] ?? $_POST['id'] ?? ''));
            $existing = vid_read_meta($id);
            if ($existing !== null && ($existing['status'] ?? '') !== 'error') {
                v2_ok(); // déjà téléchargée ou en cours
            }

            vid_write_meta($id, [
                'id'        => $id,
                'title'     => trim((string)($body['title'] ?? $id)),
                'channel'   => trim((string)($body['channel'] ?? '')),
                'duration'  => (int)($body['duration'] ?? 0),
                'thumbnail' => vid_thumb($id),
                'status'    => 'downloading',
                'addedAt'   => time(),
                'user'      => $ctx['user']['username'],
            ]);
            @unlink(vid_log_path($id));

            // Meilleure vidéo ≤1080p + meilleur son, fusionnés en mp4 (ffmpeg
            // est présent dans l'image). `--no-part` évite un .part orphelin.
            $cmd = vid_ytdlp()
                . ' --no-warnings --no-playlist --no-part --newline'
                . ' -f ' . escapeshellarg('bv*[height<=1080]+ba/b[height<=1080]/b')
                . ' --merge-output-format mp4'
                . ' -o ' . escapeshellarg(vid_dir() . "/$id.%(ext)s") . ' '
                . escapeshellarg("https://www.youtube.com/watch?v=$id")
                . ' > ' . escapeshellarg(vid_log_path($id)) . ' 2>&1 &';
            @exec($cmd);
            v2_ok();
        }

        case 'delete': {
            $id = vid_id((string)($body['id'] ?? $_POST['id'] ?? ''));
            @shell_exec('pkill -f ' . escapeshellarg("[y]t-dlp.*$id") . ' 2>/dev/null');
            foreach (glob(vid_dir() . "/$id.*") ?: [] as $f) @unlink($f);
            v2_ok();
        }

        default:
            v2_fail('invalid_request', "Action inconnue : $action", 404);
    }
} catch (Throwable $e) {
    error_log('API v2 videos error: ' . $e->getMessage());
    v2_fail('server_error', 'Erreur serveur', 500);
}
