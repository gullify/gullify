<?php
/**
 * Gullify API v2 — partage d'une chanson, d'un album ou d'un artiste par lien
 * éphémère.
 *
 *   POST ?action=create  {kind, id}   → session requise, rend le lien
 *   GET  ?action=info&token=…         → carte de visite + titres (public)
 *   GET  ?action=stream&token=…&song= → OCTETS audio (public, pas de JSON)
 *   GET  ?action=mine                 → session requise, mes liens en cours
 *   POST ?action=revoke  {token}      → session requise, coupe un lien
 *
 * Seules `create`, `mine` et `revoke` exigent un compte : `info` et `stream`
 * sont ouverts, sinon la personne à qui on envoie le lien ne pourrait rien en
 * faire. Ce que le jeton ouvre est étroit : ce qui a été partagé, pendant
 * 24 h. Il ne permet ni de parcourir la bibliothèque, ni de connaître le
 * chemin des fichiers — `stream` sert les octets et rien d'autre, et refuse
 * tout titre qui ne fait pas partie du partage.
 */
declare(strict_types=1);

require_once __DIR__ . '/_v2.php';
require_once __DIR__ . '/../../../src/AppConfig.php';
require_once __DIR__ . '/../../../src/SongShare.php';
require_once __DIR__ . '/../../../src/Storage/StorageInterface.php';
require_once __DIR__ . '/../../../src/Storage/LocalStorage.php';
require_once __DIR__ . '/../../../src/Storage/SFTPStorage.php';
require_once __DIR__ . '/../../../src/Storage/StorageFactory.php';

$action = $_GET['action'] ?? $_POST['action'] ?? 'info';
$body   = v2_body();

/** Valeur de requête, indifféremment en query string ou en corps JSON. */
function s_in(string $key, string $default = ''): string {
    global $body;
    $v = $_GET[$key] ?? $_POST[$key] ?? $body[$key] ?? $default;
    return is_scalar($v) ? trim((string)$v) : $default;
}

/**
 * Racine publique du site, pour fabriquer l'adresse du lien. Même logique que
 * pour les parties : la configuration d'abord, l'en-tête de la requête quand
 * elle n'est pas renseignée.
 */
function s_base_url(): string {
    $base = rtrim((string)AppConfig::get('app.url', ''), '/');
    if ($base === '' || str_contains($base, 'localhost')) {
        $https = ($_SERVER['HTTPS'] ?? '') !== ''
            || ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https';
        $base = ($https ? 'https' : 'http') . '://' . ($_SERVER['HTTP_HOST'] ?? 'localhost');
    }
    return $base;
}

/** Vue d'un lien, adresses rendues absolues pour l'app comme pour le web. */
function s_view(array $share): array {
    $base = s_base_url();
    $view = SongShare::publicView($share);
    if ($view['artworkUrl'] !== '') {
        $view['artworkUrl'] = $base . '/' . $view['artworkUrl'];
    }
    $view['url']       = SongShare::url($base, $view['token']);
    $view['streamUrl'] = $base . '/api/v2/share.php?action=stream&token=' . $view['token'];
    return $view;
}

try {
    switch ($action) {
        // ── Ouvrir un lien (seule action qui touche à la bibliothèque) ─────
        case 'create': {
            $ctx  = v2_auth();
            $kind = s_in('kind', 'song');
            // `songId` : la forme d'avant l'idée #89, quand on ne partageait
            // que des chansons. Les anciennes versions de l'app l'envoient
            // encore.
            $id = (int)s_in('id', s_in('songId', '0'));
            if ($id <= 0) v2_fail('invalid_request', 'Rien à partager', 400);
            try {
                $share = SongShare::create((string)$ctx['user']['username'], $kind, $id);
            } catch (RuntimeException $e) {
                [$msg, $http] = match ($e->getMessage()) {
                    'too_many_shares' =>
                        ['Trop de liens en cours — attends que certains expirent.', 429],
                    'invalid_kind' =>
                        ['Ce genre de partage n\'existe pas.', 400],
                    default => [
                        match ($kind) {
                            'album'  => "Cet album n'est plus dans ta bibliothèque.",
                            'artist' => "Cet artiste n'est plus dans ta bibliothèque.",
                            default  => "Cette chanson n'est plus dans ta bibliothèque.",
                        },
                        404,
                    ],
                };
                v2_fail($e->getMessage(), $msg, $http);
            }
            v2_ok(s_view($share));
        }

        // ── Carte de visite de la page publique ───────────────────────────
        case 'info': {
            $share = SongShare::byToken(s_in('token'));
            if (!$share) v2_fail('share_expired', "Ce lien n'est plus valable.", 404);
            $view = s_view($share);
            $view['tracks'] = share_track_views($share, $view['streamUrl']);
            v2_ok($view);
        }

        // ── Mes liens en cours ────────────────────────────────────────────
        case 'mine': {
            $ctx = v2_auth();
            $out = [];
            foreach (SongShare::listFor((string)$ctx['user']['username']) as $row) {
                $out[] = s_view($row);
            }
            v2_ok($out);
        }

        // ── Couper un lien avant l'heure ──────────────────────────────────
        case 'revoke': {
            $ctx = v2_auth();
            $ok = SongShare::revoke((string)$ctx['user']['username'], s_in('token'));
            if (!$ok) v2_fail('share_expired', "Ce lien n'existe plus.", 404);
            v2_ok(['revoked' => true]);
        }

        // ── Les octets d'un titre du partage ──────────────────────────────
        case 'stream': {
            $share = SongShare::byToken(s_in('token'));
            if (!$share) v2_fail('share_expired', "Ce lien n'est plus valable.", 404);
            $songId = (int)s_in('song', '0');
            share_stream($share, $songId > 0 ? $songId : null);
        }

        default:
            v2_fail('unknown_action', 'Action inconnue : ' . $action, 400);
    }
} catch (Throwable $e) {
    error_log('share.php error: ' . $e->getMessage());
    v2_fail('server_error', 'Erreur serveur', 500);
}

/**
 * Les titres du partage tels qu'on les montre : de quoi les afficher et les
 * écouter, rien de plus (surtout pas le chemin du fichier).
 */
function share_track_views(array $share, string $streamUrl): array {
    $out = [];
    foreach (SongShare::tracks($share) as $t) {
        $out[] = [
            'id'        => (int)$t['id'],
            'title'     => (string)$t['title'],
            'artist'    => (string)($t['artist_name'] ?? ''),
            'album'     => (string)($t['album_name'] ?? ''),
            'duration'  => (int)$t['duration'],
            'streamUrl' => $streamUrl . '&song=' . (int)$t['id'],
        ];
    }
    return $out;
}

/**
 * Sert un titre du partage.
 *
 * `$songId` désigne le titre voulu ; il doit appartenir au partage, sinon rien
 * ne sort. Sans précision, c'est le premier titre — la forme d'avant, quand un
 * lien ne portait qu'une chanson.
 *
 * Un mp3 déjà sur disque part tel quel (avec ses requêtes Range, que les
 * navigateurs exigent pour se déplacer dans le morceau) ; tout autre format
 * est transcodé une fois en mp3 et gardé jusqu'à l'échéance du lien — un flac
 * ou un wma ne se lit pas dans un navigateur, et rien n'oblige à renvoyer le
 * fichier d'origine. Le chemin réel ne sort jamais d'ici.
 */
function share_stream(array $share, ?int $songId): never {
    $track = SongShare::track($share, $songId);
    if (!$track || empty($track['file_path'])) {
        v2_fail('song_gone', "Cette chanson n'est plus disponible.", 404);
    }

    $begin = share_range_begin();
    // Une écoute = une ouverture de flux. Les requêtes Range suivantes, qui
    // reprennent le même morceau plus loin, ne comptent pas une deuxième fois.
    if ($begin === 0) SongShare::countPlay((int)$share['id']);

    $source = share_local_path((string)$share['owner_user'], (string)$track['file_path']);
    if ($source !== null && strtolower((string)pathinfo($source, PATHINFO_EXTENSION)) === 'mp3') {
        share_send($source);
    }

    $file = SongShare::cacheFile((int)$share['id'], (int)$track['id']);
    if (!is_file($file)) {
        // Un seul transcodage : les autres requêtes attendent puis relisent.
        $lock = fopen($file . '.lock', 'c');
        if ($lock) flock($lock, LOCK_EX);
        if (!is_file($file)) {
            share_transcode(
                $source ?? 'http://127.0.0.1/stream.php?path=' . rawurlencode((string)$track['file_path']),
                $file
            );
        }
        if ($lock) { flock($lock, LOCK_UN); fclose($lock); }
    }
    if (!is_file($file) || filesize($file) === 0) {
        v2_fail('stream_failed', "La chanson n'a pas pu être préparée.", 500);
    }
    share_send($file);
}

/** Premier octet demandé par le client (0 s'il ne demande rien de précis). */
function share_range_begin(): int {
    if (isset($_SERVER['HTTP_RANGE']) &&
        preg_match('/bytes=\h*(\d+)-/i', (string)$_SERVER['HTTP_RANGE'], $m)) {
        return (int)$m[1];
    }
    return 0;
}

/** Chemin réel du fichier quand le stockage est local, sinon null. */
function share_local_path(string $user, string $relativePath): ?string {
    $storage = StorageFactory::forUser($user);
    if ($storage->getType() !== 'local') return null;
    $realBase = realpath($storage->getPathBase());
    $realFile = realpath($storage->getPathBase() . '/' . $relativePath);
    if ($realBase === false || $realFile === false) return null;
    return str_starts_with($realFile, $realBase) ? $realFile : null;
}

/** Transcode la chanson entière en mp3 160 kbit/s. */
function share_transcode(string $input, string $dest): void {
    $tmp = $dest . '.tmp.mp3';
    $cmd = sprintf(
        'ffmpeg -nostdin -loglevel error -i %s -vn -ac 2 -ar 44100 -b:a 160k -f mp3 -y %s 2>&1',
        escapeshellarg($input),
        escapeshellarg($tmp)
    );
    @exec($cmd, $out, $rc);
    if ($rc === 0 && is_file($tmp) && filesize($tmp) > 0) {
        @rename($tmp, $dest);
    } else {
        @unlink($tmp);
        error_log('share ffmpeg failed (' . $rc . '): ' . implode(' ', array_slice($out ?? [], 0, 3)));
    }
}

/** Envoie le fichier audio, requêtes Range comprises (Safari les exige). */
function share_send(string $file, string $type = 'audio/mpeg'): never {
    $size = (int)filesize($file);
    $begin = 0;
    $end = $size - 1;
    if (isset($_SERVER['HTTP_RANGE']) &&
        preg_match('/bytes=\h*(\d+)-(\d*)/i', (string)$_SERVER['HTTP_RANGE'], $m)) {
        $begin = min((int)$m[1], max(0, $size - 1));
        if ($m[2] !== '') $end = min((int)$m[2], $size - 1);
    }
    $length = max(0, $end - $begin + 1);

    header('Content-Type: ' . $type);
    header('Accept-Ranges: bytes');
    header('Cache-Control: no-store');
    if (isset($_SERVER['HTTP_RANGE'])) {
        http_response_code(206);
        header("Content-Range: bytes $begin-$end/$size");
    }
    header('Content-Length: ' . $length);

    while (ob_get_level()) ob_end_clean();
    $h = fopen($file, 'rb');
    fseek($h, $begin);
    $sent = 0;
    while ($sent < $length && !feof($h)) {
        $chunk = (int)min(65536, $length - $sent);
        echo fread($h, $chunk);
        $sent += $chunk;
        flush();
    }
    fclose($h);
    exit;
}
