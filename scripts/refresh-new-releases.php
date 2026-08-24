<?php
/**
 * Gullify — Nouveautés des artistes que l'on écoute.
 *
 * Pourquoi ce script existe. « Nouveautés » se servait jusqu'ici de la page
 * `FEmusic_new_releases_albums` de YouTube Music. Interrogée sans compte, cette
 * page renvoie un fourre-tout mondial non trié — le même en CA, US, FR ou JP —
 * fait pour l'essentiel de sorties confidentielles allemandes et russes, et qui
 * ne bouge quasiment pas d'un jour à l'autre. Elle n'a rien à voir avec la page
 * « Nouveautés » de l'app YouTube Music, qui est régionale et personnalisée.
 * D'où l'impression, juste, que la liste est figée depuis des jours.
 *
 * Ce que ce script fait à la place : il demande à YouTube Music la
 * discographie des artistes que l'utilisateur a DÉJÀ dans sa bibliothèque, et
 * garde les albums récents qu'il ne possède pas encore. C'est une liste qui se
 * renouvelle vraiment — dès qu'un artiste suivi sort quelque chose — et qui est
 * directement actionnable : un clic pour le télécharger.
 *
 * Pourquoi par tranches. 1200 artistes × ~1,5 s d'appel, c'est une demi-heure :
 * bien trop pour une requête web. On avance donc d'une tranche par passage
 * (cron horaire), en gardant un curseur ; la bibliothèque entière est balayée
 * en une journée environ, et le résultat vit dans un fichier que l'API lit.
 *
 * Usage (dans le conteneur) :
 *   php scripts/refresh-new-releases.php               # une tranche
 *   php scripts/refresh-new-releases.php --slice=200   # tranche plus large
 *   php scripts/refresh-new-releases.php --user=maxime --full   # tout, un user
 *   Options : --slice=N --user=NOM --full --months=N --verbose
 */

ini_set('display_errors', '1');
error_reporting(E_ALL & ~E_DEPRECATED);

require_once __DIR__ . '/../src/AppConfig.php';

$opts    = getopt('', ['slice::', 'user::', 'full', 'months::', 'verbose']);
$slice   = max(1, (int) ($opts['slice'] ?? 60));
$onlyUser = $opts['user'] ?? null;
$full    = isset($opts['full']);
$verbose = isset($opts['verbose']);

/** Fenêtre de « nouveauté », en mois. Un album sorti il y a plus longtemps
 *  n'est plus une nouvelle sortie, c'est un trou dans la discothèque. */
$months  = max(1, (int) ($opts['months'] ?? 18));

$cacheDir  = AppConfig::getDataPath() . '/cache';
$outFile   = $cacheDir . '/personal_new_releases.json';
$stateFile = $cacheDir . '/personal_new_releases_state.json';
$lockFile  = $cacheDir . '/personal_new_releases.lock';

if (!is_dir($cacheDir)) @mkdir($cacheDir, 0775, true);

// Un seul passage à la fois : le cron est à l'heure, mais un balayage complet
// lancé à la main peut déborder sur le suivant.
$lock = @fopen($lockFile, 'c');
if ($lock === false || !flock($lock, LOCK_EX | LOCK_NB)) {
    fwrite(STDERR, "Un autre passage est déjà en cours.\n");
    exit(0);
}

function say($msg) {
    global $verbose;
    if ($verbose) echo $msg . "\n";
}

/**
 * Comparaison de noms tolérante : casse, accents, ponctuation et articles de
 * tête écartés. Même normalisation que download.php, recopiée ici parce que
 * celle-là vit dans un fichier web qu'un script CLI n'a pas à charger.
 */
function nrNormalize($name) {
    $name = mb_strtolower(trim((string) $name), 'UTF-8');
    $name = str_replace(
        ['á','à','â','ä','ã','å','é','è','ê','ë','í','ì','î','ï','ó','ò','ô',
         'ö','õ','ú','ù','û','ü','ç','ñ','ø','æ','œ'],
        ['a','a','a','a','a','a','e','e','e','e','i','i','i','i','o','o','o',
         'o','o','u','u','u','u','c','n','o','ae','oe'],
        $name
    );
    $name = preg_replace('/^(the|le|la|les|los|las)\s+/u', '', $name);
    $name = preg_replace('/[^a-z0-9]+/u', '', $name);
    return $name ?? '';
}

/**
 * Les albums d'un artiste selon YouTube Music. Une seule requête : la
 * recherche « albums » porte déjà l'année et le browseId, ce qui suffit —
 * ouvrir la page de l'artiste coûterait un aller-retour de plus par nom.
 */
function ytAlbumsFor($artistName) {
    $script = AppConfig::getPythonPath() . '/ytmusic_search.py';
    $bin    = file_exists('/opt/ytdlp/bin/python3') ? '/opt/ytdlp/bin/python3' : 'python3';
    $out    = shell_exec(
        $bin . ' ' . escapeshellarg($script) . ' album '
        . escapeshellarg($artistName) . ' 20 2>/dev/null'
    );
    $data = $out ? json_decode($out, true) : null;
    return is_array($data['results'] ?? null) ? $data['results'] : [];
}

/**
 * Écrit la liste et l'état du balayage. Les plus récents d'abord, puis les
 * dernières trouvailles : c'est l'ordre dans lequel l'API les sert, elle ne
 * fait que trancher.
 */
function nrSave(array $found, array $state, $outFile, $stateFile) {
    uasort($found, function ($a, $b) {
        $y = (int) ($b['year'] ?? 0) <=> (int) ($a['year'] ?? 0);
        return $y !== 0 ? $y : ((int) ($b['seenAt'] ?? 0) <=> (int) ($a['seenAt'] ?? 0));
    });
    @file_put_contents($outFile, json_encode($found, JSON_UNESCAPED_UNICODE));
    @file_put_contents($stateFile, json_encode($state, JSON_UNESCAPED_UNICODE));
    @chmod($outFile, 0664);
    @chmod($stateFile, 0664);
}

$db = AppConfig::getDB();

// ─────────────── état : où en est le balayage, pour chaque utilisateur ───────
$state = [];
if (is_readable($stateFile)) {
    $state = json_decode((string) @file_get_contents($stateFile), true) ?: [];
}

$found = [];
if (is_readable($outFile)) {
    $found = json_decode((string) @file_get_contents($outFile), true) ?: [];
}

$users = $db->query('SELECT DISTINCT user FROM artists ORDER BY user')
            ->fetchAll(PDO::FETCH_COLUMN);
if ($onlyUser !== null) {
    $users = array_values(array_filter($users, fn($u) => $u === $onlyUser));
}

$now      = time();
$cutoff   = (int) date('Y', strtotime("-$months months"));
$examined = 0;
$added    = 0;

foreach ($users as $user) {
    // La bibliothèque de cet utilisateur : ce qu'il a déjà, pour ne pas lui
    // proposer de retélécharger, et pour reconnaître ses artistes.
    $owned = [];
    $stmt = $db->prepare('
        SELECT ar.name AS artist, al.name AS album, COUNT(s.id) AS tracks
        FROM albums al
        JOIN artists ar ON ar.id = al.artist_id
        LEFT JOIN songs s ON s.album_id = al.id
        WHERE ar.user = ?
        GROUP BY al.id
    ');
    $stmt->execute([$user]);
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        if ((int) $row['tracks'] === 0) continue; // album fantôme
        $owned[nrNormalize($row['artist']) . '|' . nrNormalize($row['album'])] = true;
    }

    // Les artistes à interroger, du plus écouté au moins écouté : si le
    // balayage est interrompu, ce sont les plus utiles qui sont déjà faits.
    $stmt = $db->prepare('
        SELECT ar.id, ar.name, COALESCE(SUM(st.play_count), 0) AS plays
        FROM artists ar
        LEFT JOIN songs s ON s.artist_id = ar.id
        LEFT JOIN song_stats st ON st.song_id = s.id
        WHERE ar.user = ?
        GROUP BY ar.id
        ORDER BY plays DESC, ar.id ASC
    ');
    $stmt->execute([$user]);
    $artists = $stmt->fetchAll(PDO::FETCH_ASSOC);
    if (!$artists) continue;

    $cursor = (int) ($state[$user]['cursor'] ?? 0);
    if ($cursor >= count($artists)) $cursor = 0;
    $take = $full ? count($artists) : min($slice, count($artists));

    say("── $user : " . count($artists) . " artistes, tranche $take à partir de $cursor");

    for ($i = 0; $i < $take; $i++) {
        $artist = $artists[($cursor + $i) % count($artists)];
        $name   = trim((string) $artist['name']);
        if ($name === '' || nrNormalize($name) === '') continue;
        // « Various Artists » n'est pas un artiste : c'est ce que le scan écrit
        // sur les compilations. Le chercher sur YouTube Music ramène des
        // dizaines de compilations de techno qui n'intéressent personne.
        if (in_array(nrNormalize($name), [
            'variousartists', 'various', 'va', 'artistesvaries', 'artistesdivers',
            'divers', 'compilation', 'unknownartist', 'artisteinconnu', 'unknown',
            'soundtrack', 'bandeoriginale', 'ost',
        ], true)) continue;

        $examined++;
        $key = nrNormalize($name);
        foreach (ytAlbumsFor($name) as $album) {
            $title = trim((string) ($album['title'] ?? ''));
            $bid   = trim((string) ($album['browseId'] ?? ''));
            $year  = (int) ($album['year'] ?? 0);
            if ($title === '' || $bid === '' || $year < $cutoff) continue;

            // La recherche ratisse large : « Rancid » remonte aussi des
            // hommages et des compilations d'autres artistes. On ne garde que
            // ce qui est bien crédité à l'artiste de la bibliothèque.
            $credited = false;
            foreach (preg_split('/\s*(?:,|&|feat\.?|ft\.?|;|\/)\s*/iu',
                                (string) ($album['artist'] ?? '')) as $part) {
                if (nrNormalize($part) === $key) { $credited = true; break; }
            }
            if (!$credited) continue;

            if (isset($owned[$key . '|' . nrNormalize($title)])) continue;

            // Clé par titre, pas par browseId : un même album existe souvent en
            // plusieurs éditions sur YouTube Music, et les proposer toutes
            // remplit la liste de doublons.
            $slot = $user . '|' . $key . '|' . nrNormalize($title);
            if (!isset($found[$slot])) $added++;
            $found[$slot] = [
                'user'      => $user,
                'title'     => $title,
                'artist'    => $album['artist'] ?? $name,
                'year'      => (string) $year,
                'thumbnail' => $album['thumbnail'] ?? '',
                'browseId'  => $bid,
                // Pour qui c'est proposé : l'app peut le dire, et cela sert à
                // reclasser quand deux artistes sortent la même semaine.
                'becauseOf' => $name,
                'seenAt'    => $now,
            ];
            say("   + $name — $title ($year)");
        }
    }

    $state[$user] = [
        'cursor'  => $full ? 0 : ($cursor + $take) % count($artists),
        'lastRun' => $now,
        'artists' => count($artists),
    ];

    // Élagage : ce que l'utilisateur a fini par télécharger sort de la liste,
    // et ce qui a vieilli au-delà de la fenêtre aussi.
    foreach ($found as $slot => $entry) {
        if (($entry['user'] ?? '') !== $user) continue;
        $stale = (int) ($entry['year'] ?? 0) < $cutoff;
        $has   = isset($owned[nrNormalize($entry['becauseOf'] ?? $entry['artist'] ?? '')
                             . '|' . nrNormalize($entry['title'] ?? '')]);
        if ($stale || $has) unset($found[$slot]);
    }

    // Enregistré utilisateur par utilisateur : un balayage complet dure une
    // vingtaine de minutes, et tout perdre parce qu'il s'est interrompu à la
    // fin serait bête.
    nrSave($found, $state, $outFile, $stateFile);
}

nrSave($found, $state, $outFile, $stateFile);

printf(
    "%d artistes interrogés, %d nouvelles sorties ajoutées, %d en liste.\n",
    $examined, $added, count($found)
);

flock($lock, LOCK_UN);
fclose($lock);
