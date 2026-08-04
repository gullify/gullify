<?php
/**
 * Gullify API v2 — Parties multijoueur des jeux.
 *
 *   POST ?action=create   {game,audioMode,name,source} → session requise
 *   GET  ?action=info&code=…                      → carte de visite du salon
 *   POST ?action=join     {code,name}             → jeton invité
 *   GET  ?action=state&code=…&token=…             → état complet
 *   POST ?action=start    {code,token}            → hôte seulement
 *   POST ?action=answer   {code,token,answer}
 *   POST ?action=skip     {code,token}            → Chrono, passer son tour
 *   POST ?action=leave    {code,token}
 *   POST ?action=close    {code,token}            → hôte seulement
 *   GET  ?action=snippet&code=…&token=…&round=N   → OCTETS mp3 (pas de JSON)
 *   POST ?action=voice    {code,token,audio,mime,ms} → message vocal (base64)
 *   GET  ?action=voiceclip&code=…&token=…&id=N    → OCTETS audio (pas de JSON)
 *
 * Une seule action exige un compte : `create`. Tout le reste s'authentifie
 * avec le jeton remis en rejoignant le salon — c'est ce qui permet à des
 * invités sans compte de jouer depuis un simple lien. Le jeton ne vaut que
 * pour ce salon-là, et meurt avec lui.
 *
 * `snippet` est le seul accès audio ouvert aux invités : il ne rend pas un
 * fichier de la bibliothèque mais un extrait mp3 transcodé, borné à la manche
 * en cours. Impossible d'y demander autre chose que le morceau du moment.
 *
 * Le talkie-walkie (`voice` / `voiceclip`) est du même bois : un message part
 * en entier, le salon le récupère au sondage suivant. Il n'y a pas de flux
 * permanent — sans serveur de relais temps réel, un canal ouvert en continu ne
 * tiendrait pas ; un message poussé, lui, arrive toujours.
 */
declare(strict_types=1);

require_once __DIR__ . '/_v2.php';
require_once __DIR__ . '/../../../src/AppConfig.php';
require_once __DIR__ . '/../../../src/GameSource.php';
require_once __DIR__ . '/../../../src/Party.php';
require_once __DIR__ . '/../../../src/Storage/StorageInterface.php';
require_once __DIR__ . '/../../../src/Storage/LocalStorage.php';
require_once __DIR__ . '/../../../src/Storage/SFTPStorage.php';
require_once __DIR__ . '/../../../src/Storage/StorageFactory.php';

$action = $_GET['action'] ?? $_POST['action'] ?? 'state';
$body   = v2_body();

/** Valeur de requête, indifféremment en query string ou en corps JSON. */
function p_in(string $key, string $default = ''): string {
    global $body;
    $v = $_GET[$key] ?? $_POST[$key] ?? $body[$key] ?? $default;
    return is_scalar($v) ? trim((string)$v) : $default;
}

/** Messages d'erreur du domaine, en français, pour l'app comme pour le web. */
function p_message(string $code): string {
    return [
        'party_not_found'  => "Cette partie n'existe plus.",
        'player_not_found' => "Tu n'es plus dans cette partie.",
        'party_started'    => 'La partie a déjà commencé.',
        'party_full'       => 'Le salon est complet.',
        'name_taken'       => 'Ce prénom est déjà pris dans le salon.',
        'name_required'    => 'Il faut un prénom.',
        'need_two_players' => "Il faut être au moins deux pour lancer la partie.",
        'already_started'  => 'La partie est déjà lancée.',
        'library_too_small'=> "Pas assez de titres pour ce jeu : élargis la source (tout, un autre genre, une autre playlist).",
        'not_host'         => "Seul l'hôte peut faire ça.",
        'not_accepting'    => "Ce n'est plus le moment de répondre.",
        'not_your_turn'    => "Ce n'est pas ton tour.",
        'too_late'         => 'Temps écoulé.',
        'no_round'         => 'Manche introuvable.',
        'voice_format'     => "Ce format de message vocal n'est pas accepté.",
        'voice_empty'      => 'Message vocal vide.',
        'voice_too_big'    => 'Message vocal trop long.',
        'voice_too_fast'   => 'Laisse une seconde entre deux messages.',
        'voice_failed'     => "Le message vocal n'a pas pu être enregistré.",
        'voice_not_found'  => 'Ce message vocal a expiré.',
    ][$code] ?? $code;
}

/**
 * Authentifie par jeton de partie et renvoie [party, player].
 * Le tick est appliqué au passage : c'est lui qui fait vivre la partie.
 */
function p_auth(bool $tick = true): array {
    try {
        $ctx = Party::auth(p_in('code'), p_in('token'));
    } catch (RuntimeException $e) {
        v2_fail($e->getMessage(), p_message($e->getMessage()), 404);
    }
    if ($tick) $ctx['party'] = Party::tick($ctx['party']);
    return $ctx;
}

function p_state(array $party, array $player): never {
    v2_ok(Party::publicState($party, $player));
}

try {
    switch ($action) {

        // ── Créer un salon (seule action qui exige un compte) ──────────────
        case 'create': {
            $ctx  = v2_auth();
            $user = $ctx['user'];
            $game = p_in('game', 'blind');
            $mode = p_in('audioMode', 'host');
            $default = trim((string)($user['full_name'] ?? '')) ?: (string)($user['username'] ?? 'Hôte');
            $name = p_in('name', $default);

            try {
                $made = Party::create(
                    (string)$user['username'],
                    $game,
                    $mode,
                    Party::cleanName($name),
                    GameSource::fromRequest($body)
                );
            } catch (InvalidArgumentException|RuntimeException $e) {
                v2_fail('invalid_request', p_message($e->getMessage()), 400);
            }
            $base = rtrim((string)AppConfig::get('app.url', ''), '/');
            if ($base === '' || str_contains($base, 'localhost')) {
                $scheme = (($_SERVER['HTTPS'] ?? '') !== '' || ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https') ? 'https' : 'http';
                $base = $scheme . '://' . ($_SERVER['HTTP_HOST'] ?? 'localhost');
            }
            v2_ok([
                'code'  => $made['party']['code'],
                'token' => $made['player']['token'],
                'url'   => $base . '/j/' . $made['party']['code'],
                'state' => Party::publicState($made['party'], $made['player']),
            ]);
        }

        // ── Carte de visite : ce qu'on montre avant de donner son prénom ───
        case 'info': {
            $party = Party::byCode(p_in('code'));
            if (!$party) v2_fail('party_not_found', p_message('party_not_found'), 404);
            $players = Party::players((int)$party['id']);
            $host = null;
            foreach ($players as $p) if ((int)$p['is_host'] === 1) $host = $p['name'];
            v2_ok([
                'code'       => $party['code'],
                'game'       => $party['game'],
                'status'     => $party['status'],
                'audioMode'  => $party['audio_mode'],
                'hostName'   => $host,
                'players'    => array_map(static fn($p) => $p['name'], $players),
                'maxPlayers' => Party::MAX_PLAYERS,
            ]);
        }

        case 'join': {
            try {
                $made = Party::join(p_in('code'), p_in('name'));
            } catch (RuntimeException $e) {
                v2_fail($e->getMessage(), p_message($e->getMessage()), 400);
            }
            v2_ok([
                'token' => $made['player']['token'],
                'state' => Party::publicState($made['party'], $made['player']),
            ]);
        }

        case 'state': {
            $ctx = p_auth();
            p_state($ctx['party'], $ctx['player']);
        }

        case 'start': {
            $ctx = p_auth();
            if ((int)$ctx['player']['is_host'] !== 1) v2_fail('not_host', p_message('not_host'), 403);
            try {
                $party = Party::start($ctx['party']);
            } catch (RuntimeException $e) {
                v2_fail($e->getMessage(), p_message($e->getMessage()), 400);
            }
            p_state($party, $ctx['player']);
        }

        case 'answer': {
            $ctx = p_auth();
            try {
                $party = Party::answer($ctx['party'], $ctx['player'], p_in('answer'));
            } catch (RuntimeException $e) {
                // Répondre trop tard n'est pas une panne : on rend l'état, le
                // client affichera simplement la manche révélée.
                $party = Party::tick(Party::byId((int)$ctx['party']['id']) ?? $ctx['party']);
            }
            p_state($party, $ctx['player']);
        }

        case 'skip': {
            $ctx = p_auth();
            try {
                $party = Party::skip($ctx['party'], $ctx['player']);
            } catch (RuntimeException $e) {
                $party = Party::tick(Party::byId((int)$ctx['party']['id']) ?? $ctx['party']);
            }
            p_state($party, $ctx['player']);
        }

        case 'leave': {
            $ctx = p_auth(false);
            Party::leave($ctx['party'], $ctx['player']);
            v2_ok(null);
        }

        case 'close': {
            $ctx = p_auth(false);
            if ((int)$ctx['player']['is_host'] !== 1) v2_fail('not_host', p_message('not_host'), 403);
            Party::close((int)$ctx['party']['id']);
            party_clear_cache((int)$ctx['party']['id']);
            v2_ok(null);
        }

        // ── Extrait audio d'une manche, pour les invités ───────────────────
        case 'snippet': {
            $ctx    = p_auth();
            $party  = $ctx['party'];
            $round  = (int)p_in('round', '-1');
            party_snippet($party, $round);
        }

        // ── Talkie-walkie : envoyer la voix, puis l'écouter ────────────────
        case 'voice': {
            // Pas de tick ici : parler ne doit pas faire avancer une manche.
            $ctx = p_auth(false);
            $bytes = base64_decode(p_in('audio'), true);
            if ($bytes === false) v2_fail('voice_format', p_message('voice_format'), 400);
            try {
                $id = Party::sendVoice(
                    $ctx['party'],
                    $ctx['player'],
                    $bytes,
                    p_in('mime'),
                    (int)p_in('ms', '0')
                );
            } catch (RuntimeException $e) {
                v2_fail($e->getMessage(), p_message($e->getMessage()), 400);
            }
            v2_ok(['id' => $id]);
        }

        case 'voiceclip': {
            $ctx  = p_auth(false);
            $clip = Party::voiceClip((int)$ctx['party']['id'], (int)p_in('id', '0'));
            if (!$clip) v2_fail('voice_not_found', p_message('voice_not_found'), 404);
            $file = Party::voicePath(
                (int)$ctx['party']['id'],
                (int)$clip['id'],
                (string)$clip['mime']
            );
            if (!is_file($file)) v2_fail('voice_not_found', p_message('voice_not_found'), 404);
            party_send_audio($file, (string)$clip['mime']);
        }

        default:
            v2_fail('invalid_request', 'Action inconnue', 400);
    }
} catch (Throwable $e) {
    error_log('party.php: ' . $e->getMessage());
    v2_fail('server_error', 'Erreur serveur', 500);
}

// ─────────────────────────────────────────────────────────────── extraits ──

function party_cache_dir(): string {
    $dir = AppConfig::getDataPath() . '/cache/party';
    if (!is_dir($dir)) @mkdir($dir, 0775, true);
    return $dir;
}

/** Efface les extraits d'une partie (appelé à sa fermeture). */
function party_clear_cache(int $partyId): void {
    foreach (glob(party_cache_dir() . "/p{$partyId}_*.mp3") ?: [] as $f) @unlink($f);
    foreach (glob(party_cache_dir() . "/p{$partyId}_*.lock") ?: [] as $f) @unlink($f);
    // Les messages vocaux sont effacés par Party::close(), mais un fichier
    // orphelin (fiche perdue) ne doit pas rester là non plus.
    foreach (glob(party_cache_dir() . "/v{$partyId}_*") ?: [] as $f) @unlink($f);
}

/**
 * Sert l'extrait de la manche demandée, en mp3.
 *
 * Trois verrous : la manche demandée doit être celle en cours, le jeu doit en
 * avoir un (blind test et Chrono), et le mode d'écoute doit être « chacun sur
 * son appareil ». Le fichier d'origine ne sort jamais du serveur : ffmpeg n'en
 * extrait que la fenêtre jouée, et le résultat est mis en cache pour que douze
 * invités ne déclenchent pas douze transcodages.
 */
function party_snippet(array $party, int $round): never {
    if ($party['audio_mode'] !== 'guests') {
        v2_fail('audio_host_only', "L'audio ne sort que sur l'appareil de l'hôte", 403);
    }
    if ($party['status'] !== 'playing' || $round !== (int)$party['round_index']) {
        v2_fail('not_current_round', 'Manche terminée', 409);
    }
    $rounds = Party::rounds($party);
    $r = $rounds[$round] ?? null;
    if (!$r || empty($r['filePath'])) v2_fail('no_snippet', 'Pas d\'extrait pour cette manche', 404);

    $seconds = (int)ceil(Party::roundMs($party) / 1000) + 10;
    $file = party_cache_dir() . '/p' . (int)$party['id'] . '_' . $round . '.mp3';

    if (!is_file($file)) {
        // Un seul transcodage : les autres requêtes attendent puis relisent.
        $lock = fopen($file . '.lock', 'c');
        if ($lock) flock($lock, LOCK_EX);
        if (!is_file($file)) {
            party_transcode((string)$party['host_user'], (string)$r['filePath'], (int)$r['startSec'], $seconds, $file);
        }
        if ($lock) { flock($lock, LOCK_UN); fclose($lock); }
    }
    if (!is_file($file) || filesize($file) === 0) {
        v2_fail('snippet_failed', "L'extrait n'a pas pu être préparé", 500);
    }
    party_send_audio($file);
}

/** Extrait `[$start, $start+$seconds]` du morceau, en mp3 96 kbit/s. */
function party_transcode(string $user, string $relativePath, int $start, int $seconds, string $dest): void {
    $storage = StorageFactory::forUser($user);
    $input = null;

    if ($storage->getType() === 'local') {
        $path = $storage->getPathBase() . '/' . $relativePath;
        $realBase = realpath($storage->getPathBase());
        $realFile = realpath($path);
        if ($realBase !== false && $realFile !== false && str_starts_with($realFile, $realBase)) {
            $input = $realFile;
        }
    }
    if ($input === null) {
        // Stockage distant : ffmpeg relit le morceau par le point de streaming
        // local, qui sait honorer les requêtes Range (donc pas de lecture
        // complète du fichier pour en extraire trente secondes).
        $input = 'http://127.0.0.1/stream.php?path=' . rawurlencode($relativePath);
    }

    $tmp = $dest . '.tmp.mp3';
    $cmd = sprintf(
        'ffmpeg -nostdin -loglevel error -ss %d -t %d -i %s -vn -ac 2 -ar 44100 -b:a 96k -f mp3 -y %s 2>&1',
        max(0, $start),
        max(5, $seconds),
        escapeshellarg($input),
        escapeshellarg($tmp)
    );
    @exec($cmd, $out, $rc);
    if ($rc === 0 && is_file($tmp) && filesize($tmp) > 0) {
        @rename($tmp, $dest);
    } else {
        @unlink($tmp);
        error_log('party snippet ffmpeg failed (' . $rc . '): ' . implode(' ', array_slice($out ?? [], 0, 3)));
    }
}

/** Envoie le fichier audio, requêtes Range comprises (Safari les exige). */
function party_send_audio(string $file, string $type = 'audio/mpeg'): never {
    $size = (int)filesize($file);
    $begin = 0;
    $end = $size - 1;
    if (isset($_SERVER['HTTP_RANGE']) &&
        preg_match('/bytes=\h*(\d+)-(\d*)/i', $_SERVER['HTTP_RANGE'], $m)) {
        $begin = (int)$m[1];
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
