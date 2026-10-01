<?php
/**
 * Gullify — Va rechercher les images d'artiste trop petites.
 *
 * Analyse : l'en-tête d'une fiche d'artiste occupe tout l'écran du téléphone
 * — 440 points de haut, soit ~1300 pixels réels sur un écran ordinaire. Les
 * images en cache étaient plafonnées à 800 px par le code qui les rangeait :
 * elles y étaient donc agrandies de moitié, et cela se voyait. Les sources en
 * ont de plus grandes (YouTube Music sert jusqu'à 1600, Deezer 1000) ; ce
 * script va les chercher.
 *
 * Sûr : n'écrit que dans le cache (régénérable), ne touche à aucun fichier de
 * musique, et ne remplace une image que par une PLUS GRANDE — jamais par une
 * plus petite, même si la recherche trouve autre chose.
 *
 * Usage (dans le conteneur) :
 *   php scripts/refresh_artist_images.php              # dry-run
 *   php scripts/refresh_artist_images.php --apply
 *   Options : --min-width=1200  --limit=N  --id=N  --sleep-ms=400
 */

ini_set('display_errors', '1');
error_reporting(E_ALL & ~E_DEPRECATED);
set_time_limit(0);

require_once __DIR__ . '/../src/AppConfig.php';
require_once __DIR__ . '/../src/RemoteImage.php';
require_once __DIR__ . '/../src/ArtistImage.php';

$opts = getopt('', ['apply', 'min-width::', 'limit::', 'id::', 'sleep-ms::']);
$apply    = isset($opts['apply']);
$minWidth = max(100, (int)($opts['min-width'] ?? 1200));
$limit    = (int)($opts['limit'] ?? 0);
$onlyId   = (int)($opts['id'] ?? 0);
$sleepMs  = (int)($opts['sleep-ms'] ?? 400);

$cacheDir = AppConfig::getDataPath() . '/cache/artwork';
if (!is_dir($cacheDir)) @mkdir($cacheDir, 0775, true);

$db  = AppConfig::getDB();
$sql = 'SELECT id, name FROM artists';
if ($onlyId > 0) $sql .= ' WHERE id = ' . $onlyId;
$sql .= ' ORDER BY id';
$artistes = $db->query($sql)->fetchAll(PDO::FETCH_ASSOC);

echo 'Mode : ' . ($apply ? 'APPLY (téléchargement réel)' : 'DRY-RUN (analyse seule)') . "\n";
echo 'Artistes : ' . count($artistes) . " | seuil : {$minWidth}px\n\n";

$assez = 0; $candidats = 0; $ameliores = 0; $sansMieux = 0; $sansImage = 0; $lignes = [];

foreach ($artistes as $a) {
    $id      = (int)$a['id'];
    $fichier = $cacheDir . '/artist_' . $id . '.jpg';
    $actuel  = 0;
    if (is_file($fichier)) {
        $t = @getimagesize($fichier);
        if ($t) $actuel = (int)$t[0];
    }

    // Sans image du tout, ce n'est pas le travail de ce script : serve_image
    // va la chercher tout seul la première fois qu'on regarde l'artiste.
    if ($actuel === 0) { $sansImage++; continue; }
    if ($actuel >= $minWidth) { $assez++; continue; }

    $candidats++;
    if (!$apply) {
        $lignes[] = sprintf('  artiste %-5d %-32s %4d px', $id, tronque($a['name']), $actuel);
        if ($limit > 0 && $candidats >= $limit) break;
        continue;
    }

    $trouve = ArtistImage::fetch((string)$a['name']);
    if ($sleepMs > 0) usleep($sleepMs * 1000);

    if (!$trouve) {
        $sansMieux++;
        $lignes[] = sprintf('  artiste %-5d %-32s %4d px → rien trouvé', $id, tronque($a['name']), $actuel);
        continue;
    }

    $t = @getimagesizefromstring($trouve['data']);
    $neuf = $t ? (int)$t[0] : 0;

    // Plus grande, ou rien : une recherche qui retombe sur une vignette
    // abîmerait ce qui est déjà là.
    if ($neuf <= $actuel) {
        $sansMieux++;
        $lignes[] = sprintf('  artiste %-5d %-32s %4d px → %s pas mieux (%d px)',
            $id, tronque($a['name']), $actuel, $trouve['source'], $neuf);
        continue;
    }

    $tmp = $fichier . '.tmp';
    if (@file_put_contents($tmp, $trouve['data']) === false || !@rename($tmp, $fichier)) {
        @unlink($tmp);
        $sansMieux++;
        $lignes[] = sprintf('  artiste %-5d %-32s écriture impossible', $id, tronque($a['name']));
        continue;
    }
    @chmod($fichier, 0644);
    // Les versions carrées déjà servies viennent de l'ancienne image.
    foreach (glob($cacheDir . '/artist_' . $id . '_sq*.jpg') ?: [] as $vieille) {
        @unlink($vieille);
    }

    $ameliores++;
    $lignes[] = sprintf('  artiste %-5d %-32s %4d px → %4d px (%s)',
        $id, tronque($a['name']), $actuel, $neuf, $trouve['source']);

    if ($limit > 0 && $ameliores >= $limit) break;
}

echo implode("\n", $lignes) . (count($lignes) ? "\n\n" : '');
echo "───────────────────────────────────────────────\n";
echo "Déjà assez grandes (≥{$minWidth}px) : $assez\n";
echo "Sans image en cache                : $sansImage\n";
echo '  ' . ($apply ? 'Agrandies                        ' : 'À reprendre (dry-run)            ') . ": " .
     ($apply ? $ameliores : $candidats) . "\n";
if ($apply) echo "  Rien de mieux trouvé             : $sansMieux\n";
if (!$apply && $candidats > 0) echo "\nRelance avec --apply pour télécharger.\n";

function tronque(string $nom): string
{
    return mb_strlen($nom) > 32 ? mb_substr($nom, 0, 31) . '…' : $nom;
}
