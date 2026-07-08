<?php
/**
 * Gullify — Backfill des jaquettes d'album trop petites ou manquantes.
 *
 * Analyse : la qualité d'une jaquette servie par serve_image.php dépend
 * entièrement de sa SOURCE (fichier folder.jpg, pochette embarquée ID3,
 * miniature du téléchargement). Certains albums n'ont qu'une pochette
 * embarquée minuscule (≈170–300 px) ou aucune image → dans Android Auto la
 * jaquette est floue/pixellisée. Ce script trouve ces albums et télécharge
 * une jaquette HD (1000×1000) depuis Deezer (gratuit, sans clé — même source
 * que fetch_artist_image.php), écrite dans le cache que serve_image lit en
 * premier (data/cache/artwork/album_<id>.jpg).
 *
 * Sûr : n'écrit que dans le cache (régénérable), ne touche jamais aux
 * fichiers source ; n'accepte une jaquette Deezer que si son artiste ET son
 * titre correspondent, et seulement si elle est plus grande que l'existante.
 *
 * Usage (dans le conteneur) :
 *   php scripts/backfill_album_covers.php            # dry-run (analyse seule)
 *   php scripts/backfill_album_covers.php --apply    # télécharge et applique
 *   Options : --min-width=500  --limit=N  --id=N  --sleep-ms=300
 */

ini_set('display_errors', '1');
error_reporting(E_ALL & ~E_DEPRECATED);

require_once __DIR__ . '/../src/AppConfig.php';

// ─────────────── options ───────────────
$opts = getopt('', ['apply', 'min-width::', 'limit::', 'id::', 'sleep-ms::']);
$apply    = isset($opts['apply']);
$minWidth = max(100, (int)($opts['min-width'] ?? 500));
$limit    = (int)($opts['limit'] ?? 0);
$onlyId   = (int)($opts['id'] ?? 0);
$sleepMs  = (int)($opts['sleep-ms'] ?? 300);

if (!function_exists('curl_init')) {
    fwrite(STDERR, "curl PHP requis\n");
    exit(1);
}

$cacheDir = AppConfig::getDataPath() . '/cache/artwork';
if (!is_dir($cacheDir)) @mkdir($cacheDir, 0775, true);

$db = AppConfig::getDB();

// ─────────────── sélection des albums vivants ───────────────
$sql = 'SELECT al.id, al.name AS title, ar.name AS artist
        FROM albums al JOIN artists ar ON al.artist_id = ar.id';
if ($onlyId > 0) {
    $sql .= ' WHERE al.id = ' . $onlyId;
}
$sql .= ' ORDER BY al.id';
$albums = $db->query($sql)->fetchAll(PDO::FETCH_ASSOC);

echo "Mode : " . ($apply ? "APPLY (téléchargement réel)" : "DRY-RUN (analyse seule)") . "\n";
echo "Albums vivants : " . count($albums) . " | seuil : {$minWidth}px\n\n";

$scanned = 0; $ok = 0; $improved = 0; $noMatch = 0; $tooSmall = 0; $skipGood = 0;
$actions = [];

foreach ($albums as $a) {
    $id     = (int)$a['id'];
    $title  = trim($a['title']);
    $artist = trim($a['artist']);
    $cacheFile = $cacheDir . '/album_' . $id . '.jpg';

    // 1. Largeur actuelle réellement servie (résout aussi l'art local à la
    //    volée via serve_image, qui met en cache si une source existe).
    $curWidth = currentCoverWidth($id, $cacheFile);
    if ($curWidth >= $minWidth) { $skipGood++; continue; }

    // 2. Candidat : jaquette absente ou trop petite → on cherche mieux.
    $scanned++;
    if ($limit > 0 && $scanned > $limit) { $scanned--; break; }

    $cover = resolveAlbumCover($artist, $title, $minWidth);
    if ($cover === null) {
        $noMatch++;
        $actions[] = sprintf("  ✗ %-5d %-24s — %-30s  (aucune corresp., actuel=%s)",
            $id, cut($artist, 24), cut($title, 30), $curWidth ? "{$curWidth}px" : "aucune");
        continue;
    }
    if ($cover['w'] <= $curWidth) {
        $tooSmall++;
        continue; // Deezer pas meilleur que l'existant.
    }

    $line = sprintf("  ✓ %-5d %-24s — %-30s  %s → %dpx (%s: %s)",
        $id, cut($artist, 24), cut($title, 30),
        $curWidth ? "{$curWidth}px" : "aucune", $cover['w'], $cover['source'], cut($cover['matched'], 30));

    if ($apply) {
        if (@file_put_contents($cacheFile, $cover['data']) !== false) {
            @chmod($cacheFile, 0644);
            $improved++;
            $actions[] = $line;
        } else {
            $actions[] = "  ! ÉCHEC écriture $cacheFile";
        }
    } else {
        $improved++;
        $actions[] = $line;
    }
    $ok++;

    if ($sleepMs > 0) usleep($sleepMs * 1000);
}

echo implode("\n", $actions) . "\n\n";
echo "───────────────────────────────────────────────\n";
echo "Déjà correctes (≥{$minWidth}px) : $skipGood\n";
echo "Candidates analysées          : $scanned\n";
echo "  " . ($apply ? "Améliorées (téléchargées)" : "Améliorables (dry-run)") . "   : $improved\n";
echo "  Sans correspondance Deezer   : $noMatch\n";
echo "  Deezer pas plus grand        : $tooSmall\n";
if (!$apply) echo "\nRelance avec --apply pour télécharger et appliquer.\n";

// ─────────────── helpers ───────────────

/** Largeur de la jaquette actuellement servie (0 si aucune). */
function currentCoverWidth(int $id, string $cacheFile): int
{
    if (is_file($cacheFile)) {
        $s = @getimagesize($cacheFile);
        if ($s) return (int)$s[0];
    }
    // Pas encore en cache : demande à serve_image de résoudre l'art local
    // (folder.jpg / pochette embarquée). Il met en cache si une source existe.
    $bin = httpGet('http://127.0.0.1/serve_image.php?album_id=' . $id . '&fallback=404', 15);
    if ($bin !== null && strlen($bin) > 200) {
        $s = @getimagesizefromstring($bin);
        if ($s) return (int)$s[0];
    }
    return 0;
}

/** Cherche une jaquette HD : Deezer d'abord, puis YouTube Music en repli
 *  (bien mieux fourni pour le catalogue québécois/francophone). */
function resolveAlbumCover(string $artist, string $title, int $minWidth): ?array
{
    if ($title === '') return null;
    return deezerAlbumCover($artist, $title, $minWidth)
        ?? ytmusicAlbumCover($artist, $title, $minWidth);
}

/** Cherche une jaquette HD sur Deezer, artiste+titre vérifiés. */
function deezerAlbumCover(string $artist, string $title, int $minWidth): ?array
{
    // Requête avancée précise, puis repli en texte libre.
    $queries = [
        'artist:"' . $artist . '" album:"' . $title . '"',
        trim($artist . ' ' . $title),
    ];
    foreach ($queries as $q) {
        $body = httpGet('https://api.deezer.com/search/album?limit=8&q=' . urlencode($q), 8);
        if ($body === null) continue;
        $data = json_decode($body, true);
        foreach ($data['data'] ?? [] as $hit) {
            $ht = $hit['title'] ?? '';
            $ha = $hit['artist']['name'] ?? '';
            if (!titleMatches($title, $ht) || !textMatches($artist, $ha)) continue;
            $url = $hit['cover_xl'] ?? $hit['cover_big'] ?? null;
            if (!$url) continue;
            $img = downloadCover($url, $minWidth);
            if ($img === null) continue;
            return $img + ['matched' => $ht . ' — ' . $ha, 'source' => 'Deezer'];
        }
    }
    return null;
}

/** Cherche une jaquette HD sur YouTube Music (via ytmusic_search.py). */
function ytmusicAlbumCover(string $artist, string $title, int $minWidth): ?array
{
    $script = AppConfig::getPythonPath() . '/ytmusic_search.py';
    if (!is_file($script)) return null;
    $bin = is_file('/opt/ytdlp/bin/python3') ? '/opt/ytdlp/bin/python3' : 'python3';
    $cmd = $bin . ' ' . escapeshellarg($script) . ' album '
         . escapeshellarg(trim($artist . ' ' . $title)) . ' 8 2>/dev/null';
    $out = shell_exec($cmd);
    if (!$out) return null;
    $data = json_decode($out, true);
    foreach ($data['results'] ?? [] as $hit) {
        $ht = $hit['title'] ?? '';
        $ha = $hit['artist'] ?? '';
        if (!titleMatches($title, $ht) || !textMatches($artist, $ha)) continue;
        $url = $hit['thumbnail'] ?? '';
        if ($url === '') continue;
        // Les miniatures Google acceptent une taille demandée plus grande.
        $hd = preg_replace('/=w\d+-h\d+/', '=w1000-h1000', $url);
        $img = downloadCover($hd, $minWidth) ?? downloadCover($url, $minWidth);
        if ($img === null) continue;
        return $img + ['matched' => $ht . ' — ' . $ha, 'source' => 'YT Music'];
    }
    return null;
}

/** Télécharge et valide une image (assez grande et carrée-ish). */
function downloadCover(string $url, int $minWidth): ?array
{
    $img = httpGet($url, 12);
    if ($img === null || strlen($img) < 500) return null;
    $s = @getimagesizefromstring($img);
    if (!$s || $s[0] < $minWidth) return null;
    // Refuse un format trop peu carré (une vraie jaquette est ~1:1).
    if ($s[1] > 0) {
        $ratio = $s[0] / $s[1];
        if ($ratio < 0.85 || $ratio > 1.18) return null;
    }
    return ['data' => $img, 'w' => (int)$s[0]];
}

/** Correspondance de TITRE, stricte : égalité, ou le titre trouvé COMMENCE
 *  par le titre local (ou l'inverse). Le préfixe garde « Machina » ↔
 *  « Machina / The Machines Of God » mais rejette un titre court avalé au
 *  milieu d'une compilation (« Sur mon canapé » ↔ « Enfin réunis … »). */
function titleMatches(string $a, string $b): bool
{
    $na = normalizeText($a);
    $nb = normalizeText($b);
    if ($na === '' || $nb === '') return false;
    if ($na === $nb) return true;
    $short = strlen($na) <= strlen($nb) ? $na : $nb;
    $long  = strlen($na) <= strlen($nb) ? $nb : $na;
    if (strlen($short) < 4) return false;            // fragment trop court
    return str_starts_with($long, $short);           // préfixe significatif
}

/** Correspondance d'ARTISTE, tolérante : égalité ou sous-chaîne (≥4 car.).
 *  Évite « FD » ↔ « FD2 » tout en acceptant « Beatles » ↔ « The Beatles ». */
function textMatches(string $a, string $b): bool
{
    $na = normalizeText($a);
    $nb = normalizeText($b);
    if ($na === '' || $nb === '') return false;
    if ($na === $nb) return true;
    $short = strlen($na) <= strlen($nb) ? $na : $nb;
    $long  = strlen($na) <= strlen($nb) ? $nb : $na;
    if (strlen($short) < 4) return false;
    return str_contains($long, $short);
}

function normalizeText(string $s): string
{
    $s = mb_strtolower($s);
    // enlève accents courants
    $s = strtr($s, [
        'à'=>'a','â'=>'a','ä'=>'a','é'=>'e','è'=>'e','ê'=>'e','ë'=>'e',
        'î'=>'i','ï'=>'i','ô'=>'o','ö'=>'o','ù'=>'u','û'=>'u','ü'=>'u','ç'=>'c',
    ]);
    return preg_replace('/[^a-z0-9]+/', '', $s) ?? '';
}

function cut(string $s, int $n): string
{
    return mb_strlen($s) > $n ? mb_substr($s, 0, $n - 1) . '…' : $s;
}

/** GET simple, renvoie le corps ou null. */
function httpGet(string $url, int $timeout): ?string
{
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => $timeout,
        CURLOPT_FOLLOWLOCATION => true,
        CURLOPT_USERAGENT      => 'Gullify/1.0 (self-hosted music player)',
    ]);
    $body = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    if ($body === false || $code >= 400) return null;
    return $body;
}
