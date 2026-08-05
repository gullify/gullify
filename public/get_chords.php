<?php
/**
 * Gullify - Chords Endpoint
 *
 * Grille d'accords guitare d'un titre (bouton « Accords » du lecteur), sur le
 * modèle de get_lyrics.php :
 *   1. Cache DB (table song_chords, positif 30 j / négatif 3 j)
 *   2. Ultimate-Guitar : recherche publique puis page d'onglet. Les deux pages
 *      embarquent leur état dans <div class="js-store" data-content="…"> —
 *      aucune clé d'API n'existe pour ce service, c'est la seule source
 *      gratuite qui donne à la fois la grille et le doigté des accords.
 *
 * GET params :
 *   path    — chemin relatif du fichier (résout artiste/titre en base)
 *   artist  — artiste (si pas de path)
 *   title   — titre (si pas de path)
 *   refresh — 1 pour ignorer le cache
 */
header('Content-Type: application/json; charset=utf-8');

require_once __DIR__ . '/../src/AppConfig.php';

const CHORDS_TTL_HIT  = 30 * 86400; // une grille ne bouge quasiment jamais
const CHORDS_TTL_MISS = 3 * 86400;  // mais un titre absent peut arriver plus tard

$relativePath = trim($_GET['path'] ?? '');
$artist       = trim($_GET['artist'] ?? '');
$title        = trim($_GET['title'] ?? '');

try {
    $db = AppConfig::getDB();

    if ($relativePath && (!$artist || !$title)) {
        $stmt = $db->prepare('
            SELECT a.name AS artist_name, s.title
            FROM songs s
            JOIN albums al ON s.album_id = al.id
            JOIN artists a  ON al.artist_id = a.id
            WHERE s.file_path = ?
            LIMIT 1
        ');
        $stmt->execute([$relativePath]);
        if ($row = $stmt->fetch()) {
            $artist = $artist ?: (string)$row['artist_name'];
            $title  = $title  ?: (string)$row['title'];
        }
    }

    if (!$artist || !$title) {
        echo json_encode(['success' => false, 'error' => 'Missing artist/title']);
        exit;
    }

    $cleanTitle = chords_clean_title($title);
    $searchUrl  = 'https://www.ultimate-guitar.com/search.php?' . http_build_query([
        'search_type' => 'title',
        'value'       => $artist . ' ' . $cleanTitle,
    ]);

    chords_ensure_table($db);
    $key = md5(chords_normalize($artist) . '|' . chords_normalize($cleanTitle));

    if (empty($_GET['refresh'])) {
        $stmt = $db->prepare('SELECT payload, UNIX_TIMESTAMP(fetched_at) AS ts FROM song_chords WHERE cache_key = ?');
        $stmt->execute([$key]);
        if ($cached = $stmt->fetch()) {
            $age = time() - (int)$cached['ts'];
            $hit = $cached['payload'] !== null;
            if ($age < ($hit ? CHORDS_TTL_HIT : CHORDS_TTL_MISS)) {
                echo json_encode([
                    'success'   => true,
                    'chords'    => $hit ? json_decode((string)$cached['payload'], true) : null,
                    'searchUrl' => $searchUrl,
                    'cached'    => true,
                ], JSON_UNESCAPED_UNICODE);
                exit;
            }
        }
    }

    $chords = chords_fetch_ultimate_guitar($artist, $cleanTitle);

    $stmt = $db->prepare('
        INSERT INTO song_chords (cache_key, artist, title, payload, fetched_at)
        VALUES (?, ?, ?, ?, NOW())
        ON DUPLICATE KEY UPDATE payload = VALUES(payload), fetched_at = NOW()
    ');
    $stmt->execute([
        $key,
        mb_substr($artist, 0, 255),
        mb_substr($title, 0, 255),
        $chords ? json_encode($chords, JSON_UNESCAPED_UNICODE) : null,
    ]);

    echo json_encode([
        'success'   => true,
        'chords'    => $chords,
        'searchUrl' => $searchUrl,
    ], JSON_UNESCAPED_UNICODE);

} catch (Throwable $e) {
    error_log('get_chords error: ' . $e->getMessage());
    echo json_encode(['success' => false, 'error' => $e->getMessage()]);
}

// ─── Cache ───────────────────────────────────────────────────────────────────

function chords_ensure_table(PDO $db): void {
    $db->exec("
        CREATE TABLE IF NOT EXISTS song_chords (
            id INT AUTO_INCREMENT PRIMARY KEY,
            cache_key CHAR(32) NOT NULL UNIQUE,
            artist VARCHAR(255) NOT NULL,
            title VARCHAR(255) NOT NULL,
            payload MEDIUMTEXT NULL,
            fetched_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ");
}

// ─── Ultimate-Guitar ─────────────────────────────────────────────────────────

/**
 * Cherche la meilleure grille d'accords et la met en forme pour l'app.
 * Renvoie null si rien d'exploitable (l'appelant met alors un cache négatif).
 */
function chords_fetch_ultimate_guitar(string $artist, string $title): ?array {
    $html = chords_http_get('https://www.ultimate-guitar.com/search.php?' . http_build_query([
        'search_type' => 'title',
        'value'       => $artist . ' ' . $title,
    ]));
    if (!$html) return null;

    $store   = chords_js_store($html);
    $results = $store['store']['page']['data']['results'] ?? null;
    if (!is_array($results)) return null;

    $best      = null;
    $bestScore = -1.0;
    foreach ($results as $r) {
        if (($r['type'] ?? '') !== 'Chords') continue;
        $url = (string)($r['tab_url'] ?? '');
        // Les entrées « Pro » renvoient vers l'appli payante : pas de grille.
        if (!str_contains($url, 'tabs.ultimate-guitar.com/tab/')) continue;

        $score = chords_score($r, $artist, $title);
        if ($score > $bestScore) {
            $bestScore = $score;
            $best      = $r;
        }
    }
    if (!$best) return null;

    $tabHtml = chords_http_get((string)$best['tab_url']);
    if (!$tabHtml) return null;

    $data    = chords_js_store($tabHtml)['store']['page']['data'] ?? [];
    $view    = $data['tab_view'] ?? [];
    $content = $view['wiki_tab']['content'] ?? '';
    if (!is_string($content) || trim($content) === '') return null;

    $meta = is_array($view['meta'] ?? null) ? $view['meta'] : [];
    $tab  = is_array($data['tab'] ?? null) ? $data['tab'] : [];

    return [
        'artist'   => (string)($tab['artist_name'] ?? $best['artist_name'] ?? $artist),
        'title'    => (string)($tab['song_name'] ?? $best['song_name'] ?? $title),
        'content'  => chords_clean_content($content),
        'capo'     => isset($meta['capo']) && (int)$meta['capo'] > 0 ? (int)$meta['capo'] : null,
        'tonality' => chords_string_or_null($meta['tonality'] ?? ($tab['tonality_name'] ?? null)),
        'tuning'   => chords_string_or_null($meta['tuning']['value'] ?? null),
        'version'  => isset($tab['version']) ? (int)$tab['version'] : null,
        'rating'   => isset($tab['rating']) ? round((float)$tab['rating'], 2) : null,
        'votes'    => isset($tab['votes']) ? (int)$tab['votes'] : null,
        'url'      => (string)($tab['tab_url'] ?? $best['tab_url']),
        'source'   => 'ultimate-guitar',
        'shapes'   => chords_shapes($view['applicature'] ?? null),
    ];
}

/** Note un résultat de recherche : popularité pondérée par la ressemblance. */
function chords_score(array $result, string $artist, string $title): float {
    $rating = (float)($result['rating'] ?? 0);
    $votes  = (int)($result['votes'] ?? 0);
    $score  = $rating * log10($votes + 10);

    $wantedArtist = chords_normalize($artist);
    $foundArtist  = chords_normalize((string)($result['artist_name'] ?? ''));
    if ($wantedArtist !== '' && $foundArtist !== '') {
        if ($wantedArtist === $foundArtist) {
            $score += 6;
        } elseif (str_contains($foundArtist, $wantedArtist) || str_contains($wantedArtist, $foundArtist)) {
            $score += 3;
        } else {
            $score -= 4;
        }
    }

    $wantedTitle = chords_normalize($title);
    $foundTitle  = chords_normalize((string)($result['song_name'] ?? ''));
    if ($wantedTitle !== '' && $foundTitle !== '') {
        if ($wantedTitle === $foundTitle) {
            $score += 4;
        } elseif (str_contains($foundTitle, $wantedTitle) || str_contains($wantedTitle, $foundTitle)) {
            $score += 2;
        } else {
            $score -= 3;
        }
    }

    return $score;
}

/**
 * Doigtés fournis par la page : une position par accord (la première, qui est
 * celle affichée par défaut sur Ultimate-Guitar). frets/fingers vont de la
 * corde aiguë (mi) à la corde grave, -1 = corde étouffée.
 */
function chords_shapes(mixed $applicature): array {
    if (!is_array($applicature)) return [];
    $shapes = [];
    foreach ($applicature as $name => $variants) {
        if (!is_array($variants) || !isset($variants[0]['frets'])) continue;
        $v = $variants[0];
        $shapes[(string)$name] = [
            'frets'    => array_map('intval', (array)$v['frets']),
            'fingers'  => array_map('intval', (array)($v['fingers'] ?? [])),
            'baseFret' => (int)($v['fret'] ?? 0),
        ];
        if (count($shapes) >= 40) break; // grille pathologique : on borne
    }
    return $shapes;
}

/**
 * Nettoie la grille : les marqueurs [tab]…[/tab] servent seulement à figer la
 * chasse côté web, l'app affiche déjà tout en monospace. Les [ch]…[/ch] sont
 * conservés : c'est ce qui permet de colorer les accords.
 */
function chords_clean_content(string $content): string {
    $text = str_replace(["\r\n", "\r"], "\n", $content);
    $text = str_ireplace(['[tab]', '[/tab]'], '', $text);
    $text = preg_replace("/\n{3,}/", "\n\n", $text);
    return trim((string)$text);
}

/** Titre de bibliothèque → titre cherchable (sans « feat. », « Remastered »…). */
function chords_clean_title(string $title): string {
    $t = preg_replace('/\s*[\(\[][^\)\]]*(feat\.?|ft\.?|with|remaster|remasteris|version|edit|live|mix|mono|stereo|bonus)[^\)\]]*[\)\]]/iu', '', $title);
    $t = preg_replace('/\s*-\s*(remaster|remasteris|live|single|radio|album)\b.*$/iu', '', (string)$t);
    $t = trim((string)$t);
    return $t !== '' ? $t : $title;
}

/** Minuscules sans accents ni ponctuation, pour comparer des noms. */
function chords_normalize(string $s): string {
    $s = mb_strtolower(trim($s));
    if (function_exists('iconv')) {
        $ascii = @iconv('UTF-8', 'ASCII//TRANSLIT', $s);
        if ($ascii !== false) $s = strtolower($ascii);
    }
    $s = preg_replace('/[^a-z0-9]+/', ' ', $s);
    return trim(preg_replace('/\s+/', ' ', (string)$s));
}

function chords_string_or_null(mixed $v): ?string {
    $s = is_string($v) ? trim($v) : '';
    return $s !== '' ? $s : null;
}

/** Extrait l'état JSON embarqué dans <div class="js-store" data-content="…">. */
function chords_js_store(string $html): array {
    if (!preg_match('/class="js-store"\s+data-content="(.*?)"\s*>/s', $html, $m)) return [];
    $json = html_entity_decode($m[1], ENT_QUOTES | ENT_HTML5, 'UTF-8');
    $data = json_decode($json, true);
    return is_array($data) ? $data : [];
}

function chords_http_get(string $url, int $timeout = 12): ?string {
    if (!function_exists('curl_init')) return null;
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_FOLLOWLOCATION => true,
        CURLOPT_MAXREDIRS      => 3,
        CURLOPT_TIMEOUT        => $timeout,
        CURLOPT_ENCODING       => '',
        CURLOPT_USERAGENT      => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        CURLOPT_HTTPHEADER     => ['Accept: text/html,application/xhtml+xml', 'Accept-Language: en-US,en;q=0.9'],
    ]);
    $body   = curl_exec($ch);
    $status = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    return ($status === 200 && is_string($body) && $body !== '') ? $body : null;
}
