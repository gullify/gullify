<?php
/**
 * Gullify — Remet d'aplomb les jaquettes d'album qui ne sont pas carrées.
 *
 * Analyse : une pochette est carrée. Les vignettes trouvées sur le web, elles,
 * arrivent souvent en 16:9 — la pochette au milieu, des bandes de couleur
 * peintes de chaque côté (mesuré : la bande de gauche d'une 800×450 a un
 * écart-type de 0,005, c'est un aplat). Rangées telles quelles, elles sont
 * recadrées à l'affichage par l'app et par le web, mais PAS par ce qui reçoit
 * l'image brute : Android Auto, la notification du téléphone, l'écran
 * verrouillé, et tout autre lecteur ouvrant le folder.jpg du dossier.
 *
 * On recadre donc au centre, là où est la pochette. Jamais d'agrandissement :
 * une 800×450 devient une 450×450, pas une 800×800 étirée.
 *
 * Sûr : n'écrit que dans le cache (régénérable), ne touche jamais aux fichiers
 * de musique ; --dossiers étend la réparation aux folder.jpg que Gullify a
 * lui-même écrits, et seulement à ceux-là (même taille que le cache).
 *
 * Usage (dans le conteneur) :
 *   php scripts/square_album_covers.php               # dry-run (analyse seule)
 *   php scripts/square_album_covers.php --apply       # recadre le cache
 *   php scripts/square_album_covers.php --apply --dossiers
 *   Options : --limit=N  --id=N  --tolerance=0.01
 */

ini_set('display_errors', '1');
error_reporting(E_ALL & ~E_DEPRECATED);

require_once __DIR__ . '/../src/AppConfig.php';

$opts = getopt('', ['apply', 'dossiers', 'limit::', 'id::', 'tolerance::']);
$apply     = isset($opts['apply']);
$dossiers  = isset($opts['dossiers']);
$limit     = (int)($opts['limit'] ?? 0);
$onlyId    = (int)($opts['id'] ?? 0);
// Une pochette scannée peut être carrée à un pixel près ; la retoucher pour
// si peu ne ferait que lui coûter une génération de JPEG.
$tolerance = (float)($opts['tolerance'] ?? 0.01);

if (!function_exists('imagecreatefromstring')) {
    fwrite(STDERR, "GD PHP requis\n");
    exit(1);
}

$cacheDir = AppConfig::getDataPath() . '/cache/artwork';
if (!is_dir($cacheDir)) {
    fwrite(STDERR, "Aucun cache de jaquettes : $cacheDir\n");
    exit(1);
}

echo "Mode : " . ($apply ? "APPLY (recadrage réel)" : "DRY-RUN (analyse seule)") . "\n";
echo "Cache : $cacheDir\n\n";

$fichiers = glob($cacheDir . '/album_*.jpg') ?: [];
$vus = 0; $carrees = 0; $recadrees = 0; $echecs = 0; $lignes = [];
$pires = [];

foreach ($fichiers as $fichier) {
    // Les variantes déjà carrées (album_12_sq256.jpg) sont des copies
    // dérivées : elles se régénèrent, et elles sont carrées par construction.
    if (preg_match('/_sq\d+\.jpg$/', $fichier)) continue;
    if (!preg_match('/album_(\d+)\.jpg$/', basename($fichier), $m)) continue;
    $id = (int)$m[1];
    if ($onlyId > 0 && $id !== $onlyId) continue;

    $taille = @getimagesize($fichier);
    if (!$taille) { $echecs++; continue; }
    [$w, $h] = $taille;
    if ($w < 1 || $h < 1) { $echecs++; continue; }
    $vus++;

    if (abs($w - $h) / max($w, $h) <= $tolerance) { $carrees++; continue; }

    $cote = min($w, $h);
    $perte = round(100 * (1 - ($cote * $cote) / ($w * $h)));
    $lignes[] = sprintf("  album %-6d %4d×%-4d → %d×%d  (%d%% de l'image était du décor)",
        $id, $w, $h, $cote, $cote, $perte);
    $pires[$id] = $perte;

    if (!$apply) { $recadrees++; continue; }

    if (recadreCarre($fichier)) {
        $recadrees++;
        // Les variantes de taille viennent de l'ancienne image : qu'elles se
        // refassent à la prochaine demande, depuis la pochette corrigée.
        foreach (glob($cacheDir . '/album_' . $id . '_sq*.jpg') ?: [] as $vieille) {
            @unlink($vieille);
        }
        if ($dossiers) repareDossier($id, $w, $h);
    } else {
        $echecs++;
    }

    if ($limit > 0 && $recadrees >= $limit) break;
}

sort($lignes);
echo implode("\n", $lignes) . (count($lignes) ? "\n\n" : "");
echo "───────────────────────────────────────────────\n";
echo "Jaquettes en cache      : $vus\n";
echo "  Déjà carrées          : $carrees\n";
echo "  " . ($apply ? "Recadrées             " : "À recadrer (dry-run)  ") . ": $recadrees\n";
if ($echecs) echo "  Illisibles / échecs   : $echecs\n";
if (!$apply && $recadrees > 0) echo "\nRelance avec --apply pour recadrer.\n";

// ─────────────── helpers ───────────────

/** Recadre un fichier en son plus grand carré centré. Écriture atomique :
 *  un JPEG tronqué par une panne vaut moins qu'une pochette non carrée. */
function recadreCarre(string $fichier): bool
{
    $bin = @file_get_contents($fichier);
    if ($bin === false) return false;
    $src = @imagecreatefromstring($bin);
    if (!$src) return false;

    $w = imagesx($src); $h = imagesy($src);
    $cote = min($w, $h);
    $dst = imagecreatetruecolor($cote, $cote);
    imagecopy($dst, $src, 0, 0, intdiv($w - $cote, 2), intdiv($h - $cote, 2), $cote, $cote);

    // imagecopy, pas imagecopyresampled : à taille égale, rien à rééchantillonner
    // — le centre sort pixel pour pixel, seul le JPEG se regénère.
    $tmp = $fichier . '.tmp';
    $ok = imagejpeg($dst, $tmp, 92);
    imagedestroy($src); imagedestroy($dst);
    if (!$ok) { @unlink($tmp); return false; }
    return @rename($tmp, $fichier);
}

/** Répare le folder.jpg du dossier de l'album, mais seulement si c'est celui
 *  que Gullify y a écrit — mêmes dimensions que la jaquette en cache. Une
 *  image que son propriétaire a rangée là lui appartient. */
function repareDossier(int $albumId, int $w, int $h): void
{
    static $db = null;
    if ($db === null) {
        $db = AppConfig::getDB();
        require_once __DIR__ . '/../src/Storage/StorageFactory.php';
    }

    $stmt = $db->prepare("
        SELECT ar.user, s.file_path
        FROM songs s
        JOIN albums al ON s.album_id = al.id
        JOIN artists ar ON al.artist_id = ar.id
        WHERE al.id = ? LIMIT 1
    ");
    $stmt->execute([$albumId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$row) return;

    $storage = StorageFactory::forUser($row['user']);
    if ($storage->getType() !== 'local') return; // à distance : hors de portée ici
    $folder = dirname($storage->getPathBase() . '/' . ltrim($row['file_path'], '/')) . '/folder.jpg';
    if (!is_file($folder) || !is_writable($folder)) return;

    $taille = @getimagesize($folder);
    if (!$taille || (int)$taille[0] !== $w || (int)$taille[1] !== $h) return;

    if (recadreCarre($folder)) {
        echo "  folder.jpg recadré : $folder\n";
    }
}
