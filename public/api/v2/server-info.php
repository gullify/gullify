<?php
/**
 * Gullify API v2 - Infos du serveur
 *   GET /api/v2/server-info.php → {disks, music, data, library, database, system}
 *
 * Lecture seule : espace disque disponible, poids de la musique et des
 * données, taille de la base, versions. Affiché dans l'app
 * (Paramètres → Infos du serveur).
 */
declare(strict_types=1);

require_once __DIR__ . '/_v2.php';

v2_auth();

/** Espace du système de fichiers qui porte $path (null si introuvable). */
function si_disk(string $label, string $path): ?array {
    if (!is_dir($path)) return null;
    $total = @disk_total_space($path);
    $free  = @disk_free_space($path);
    if (!$total || $free === false) return null;
    return [
        'label' => $label,
        'path'  => $path,
        'total' => (int)$total,
        'free'  => (int)$free,
        'used'  => (int)$total - (int)$free,
    ];
}

/**
 * Taille cumulée d'un dossier, avec un budget de temps : la musique = des
 * dizaines de milliers de fichiers, mieux vaut rendre null (« — » dans
 * l'app) qu'une requête qui traîne. Ne suit pas les liens symboliques.
 */
function si_dir_size(string $path, float $budget): ?int {
    if (!is_dir($path)) return null;
    $deadline = microtime(true) + $budget;
    $total = 0;
    $n = 0;
    try {
        $it = new RecursiveIteratorIterator(
            new RecursiveDirectoryIterator($path, FilesystemIterator::SKIP_DOTS),
            RecursiveIteratorIterator::LEAVES_ONLY,
            RecursiveIteratorIterator::CATCH_GET_CHILD
        );
        foreach ($it as $file) {
            if ($file->isFile()) $total += $file->getSize();
            if ((++$n % 512) === 0 && microtime(true) > $deadline) return null;
        }
    } catch (Throwable $e) {
        return null;
    }
    return $total;
}

/**
 * Taille d'un dossier mise en cache sur disque : le calcul ne repart que
 * lorsque le cache a expiré. Rend ['bytes' => int|null, 'at' => int|null].
 */
function si_cached_dir_size(string $key, string $path, int $ttl, float $budget): array {
    $dir  = AppConfig::getDataPath() . '/cache';
    $file = $dir . '/server_info_' . $key . '.json';

    if (is_file($file)) {
        $age = time() - (int)@filemtime($file);
        $j   = json_decode((string)@file_get_contents($file), true);
        if ($age < $ttl && is_array($j) && isset($j['bytes'], $j['at'])) {
            return ['bytes' => (int)$j['bytes'], 'at' => (int)$j['at']];
        }
    }

    $bytes = si_dir_size($path, $budget);
    if ($bytes === null) {
        // Budget dépassé : on garde la dernière valeur connue, même périmée.
        $j = is_file($file) ? json_decode((string)@file_get_contents($file), true) : null;
        if (is_array($j) && isset($j['bytes'], $j['at'])) {
            return ['bytes' => (int)$j['bytes'], 'at' => (int)$j['at']];
        }
        return ['bytes' => null, 'at' => null];
    }

    $result = ['bytes' => $bytes, 'at' => time()];
    if (!is_dir($dir)) @mkdir($dir, 0775, true);
    @file_put_contents($file, json_encode($result));
    return $result;
}

/** Première valeur d'un fichier /proc, ou null hors Linux. */
function si_proc(string $file): ?string {
    if (!is_readable($file)) return null;
    $raw = @file_get_contents($file);
    return $raw === false ? null : $raw;
}

try {
    $musicPath = AppConfig::getMusicBasePath();
    $dataPath  = AppConfig::getDataPath();

    // ── Disques ───────────────────────────────────────────────────────
    // Musique et données sont souvent sur le même volume : on ne l'affiche
    // alors qu'une fois.
    $disks = [];
    foreach ([['Musique', $musicPath], ['Données', $dataPath]] as [$label, $path]) {
        $d = si_disk($label, $path);
        if ($d === null) continue;
        $same = null;
        foreach ($disks as $i => $existing) {
            if ($existing['total'] === $d['total'] && $existing['free'] === $d['free']) {
                $same = $i;
                break;
            }
        }
        if ($same === null) {
            $disks[] = $d;
        } else {
            $disks[$same]['label'] .= ' et ' . lcfirst($d['label']);
        }
    }
    $disks = array_values($disks);

    // ── Poids de la musique et des données (mis en cache) ─────────────
    $music = si_cached_dir_size('music', $musicPath, 21600, 8.0);
    $data  = si_cached_dir_size('data', $dataPath, 3600, 5.0);

    // ── Bibliothèque ──────────────────────────────────────────────────
    $db  = AppConfig::getDB();
    $lib = $db->query(
        'SELECT (SELECT COUNT(*) FROM songs)    AS songs,
                (SELECT COUNT(*) FROM albums)   AS albums,
                (SELECT COUNT(*) FROM artists)  AS artists,
                (SELECT COUNT(*) FROM genres)   AS genres,
                (SELECT COUNT(*) FROM playlists) AS playlists,
                (SELECT COUNT(*) FROM users)    AS users,
                (SELECT COALESCE(SUM(duration), 0) FROM songs) AS duration'
    )->fetch(PDO::FETCH_ASSOC) ?: [];

    $lastScan = null;
    try {
        $ts = $db->query('SELECT last_update FROM library_status ORDER BY id DESC LIMIT 1')
                 ->fetchColumn();
        if ($ts) $lastScan = (int)$ts;
    } catch (Throwable $e) {
        // table absente : pas de dernier scan à afficher
    }

    $dbSize = (int)$db->query(
        'SELECT COALESCE(SUM(data_length + index_length), 0)
         FROM information_schema.TABLES WHERE table_schema = DATABASE()'
    )->fetchColumn();

    // ── Système ───────────────────────────────────────────────────────
    $os = php_uname('s');
    $release = si_proc('/etc/os-release');
    if ($release !== null && preg_match('/^PRETTY_NAME="?([^"\n]+)"?/m', $release, $m)) {
        $os = $m[1];
    }

    $uptime = null;
    $raw = si_proc('/proc/uptime');
    if ($raw !== null) $uptime = (int)(float)strtok($raw, ' ');

    $memTotal = $memAvailable = null;
    $raw = si_proc('/proc/meminfo');
    if ($raw !== null) {
        if (preg_match('/^MemTotal:\s+(\d+) kB/m', $raw, $m))     $memTotal     = (int)$m[1] * 1024;
        if (preg_match('/^MemAvailable:\s+(\d+) kB/m', $raw, $m)) $memAvailable = (int)$m[1] * 1024;
    }

    $cpus = null;
    $raw = si_proc('/proc/cpuinfo');
    if ($raw !== null) $cpus = substr_count($raw, "\nprocessor") + (str_starts_with($raw, 'processor') ? 1 : 0);

    $load = function_exists('sys_getloadavg') ? (sys_getloadavg() ?: null) : null;

    v2_ok([
        'disks'   => $disks,
        'music'   => ['bytes' => $music['bytes'], 'computedAt' => $music['at'], 'path' => $musicPath],
        'data'    => ['bytes' => $data['bytes'],  'computedAt' => $data['at'],  'path' => $dataPath],
        'library' => [
            'songs'     => (int)($lib['songs'] ?? 0),
            'albums'    => (int)($lib['albums'] ?? 0),
            'artists'   => (int)($lib['artists'] ?? 0),
            'genres'    => (int)($lib['genres'] ?? 0),
            'playlists' => (int)($lib['playlists'] ?? 0),
            'users'     => (int)($lib['users'] ?? 0),
            'duration'  => (int)($lib['duration'] ?? 0),
            'lastScan'  => $lastScan,
        ],
        'database' => ['bytes' => $dbSize, 'name' => (string)AppConfig::get('mysql.database', '')],
        'system'   => [
            'php'        => PHP_VERSION,
            'server'     => (string)($_SERVER['SERVER_SOFTWARE'] ?? ''),
            'os'         => $os,
            'kernel'     => php_uname('r'),
            'cpus'       => $cpus ?: null,
            'load'       => $load ? array_map(static fn($v) => round((float)$v, 2), $load) : null,
            'memTotal'   => $memTotal,
            'memFree'    => $memAvailable,
            'uptime'     => $uptime,
            // Déjà formatée dans le fuseau du serveur : l'app l'affiche telle
            // quelle (la reconvertir côté client donnerait l'heure locale).
            'time'       => date('d/m H:i'),
            'timezone'   => date_default_timezone_get(),
            'apiVersion' => 'v2',
        ],
    ]);
} catch (Throwable $e) {
    v2_fail('server_info', 'Infos du serveur indisponibles : ' . $e->getMessage(), 500);
}
