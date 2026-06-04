<?php
/**
 * Gullify — Radio station logo upload
 *
 * Accepts an image file (JPEG / PNG / WebP), resizes to 256×256 max,
 * stores it under data/cache/radio_logos/ and returns a stable URL the
 * client can paste into the station's logo field.
 *
 * POST multipart/form-data
 *   logo: file (image/*)
 *
 * Response:
 *   { error: bool, message: string, url: '/serve_radio_logo.php?id=…' }
 */

ini_set('display_errors', 0);
header('Content-Type: application/json');

require_once __DIR__ . '/../src/AppConfig.php';
require_once __DIR__ . '/../src/auth_required.php';

$user = $_SESSION['username'] ?? '';
if ($user === '') {
    http_response_code(401);
    echo json_encode(['error' => true, 'message' => 'unauthenticated']);
    exit;
}

function fetchExternalImage(string $url): array {
    if (!filter_var($url, FILTER_VALIDATE_URL) || !preg_match('~^https?://~i', $url)) {
        throw new Exception('URL invalide');
    }
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_FOLLOWLOCATION => true,
        CURLOPT_TIMEOUT        => 10,
        CURLOPT_CONNECTTIMEOUT => 5,
        CURLOPT_USERAGENT      => 'Mozilla/5.0 Gullify/1.0',
        CURLOPT_HTTPHEADER     => ['Accept: image/*'],
    ]);
    $bin  = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $ct   = (string)curl_getinfo($ch, CURLINFO_CONTENT_TYPE);
    curl_close($ch);
    if ($code >= 400 || !$bin) {
        throw new Exception("Téléchargement échoué (HTTP $code)");
    }
    if (strlen($bin) > 8 * 1024 * 1024) {
        throw new Exception('Image distante trop volumineuse');
    }
    $mime = strtolower(strtok($ct, ';') ?: '');
    if (!str_starts_with($mime, 'image/')) {
        // Some servers omit a useful Content-Type — sniff from magic bytes
        $magic = substr($bin, 0, 12);
        if      (str_starts_with($magic, "\xFF\xD8\xFF"))                  $mime = 'image/jpeg';
        elseif (str_starts_with($magic, "\x89PNG\r\n\x1A\n"))             $mime = 'image/png';
        elseif (str_starts_with($magic, "RIFF") && substr($magic, 8, 4) === 'WEBP') $mime = 'image/webp';
        else throw new Exception("Le serveur n'a pas retourné une image (Content-Type: $ct)");
    }
    return ['data' => $bin, 'mime' => $mime];
}

try {
    $useUrl = !empty($_REQUEST['url']);
    $allowed = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp'];

    if ($useUrl) {
        // Server-side fetch — avoids CORS / hotlinking / mixed-content issues
        $fetched = fetchExternalImage((string)$_REQUEST['url']);
        $bin  = $fetched['data'];
        $mime = $fetched['mime'];
        $tmpFile = tempnam(sys_get_temp_dir(), 'gullify_radio_');
        @file_put_contents($tmpFile, $bin);
        $tmpPath = $tmpFile;
    } else {
        if (empty($_FILES['logo']) || $_FILES['logo']['error'] !== UPLOAD_ERR_OK) {
            throw new Exception('Aucun fichier reçu');
        }
        $file = $_FILES['logo'];
        if (!in_array($file['type'], $allowed, true)) {
            throw new Exception('Format non supporté (JPEG / PNG / WebP uniquement)');
        }
        if ($file['size'] > 4 * 1024 * 1024) {
            throw new Exception('Fichier trop volumineux (max 4 MB)');
        }
        $mime    = $file['type'];
        $tmpPath = $file['tmp_name'];
    }

    $im = null;
    switch ($mime) {
        case 'image/jpeg':
        case 'image/jpg':
            $im = imagecreatefromjpeg($tmpPath);
            break;
        case 'image/png':
            $im = imagecreatefrompng($tmpPath);
            break;
        case 'image/webp':
            $im = imagecreatefromwebp($tmpPath);
            break;
        default:
            throw new Exception("Format non supporté: $mime");
    }
    if (!$im) throw new Exception("Impossible de décoder l'image");

    // Cap at 256×256 — generous for the 96px card on retina, doesn't bloat
    $w = imagesx($im);
    $h = imagesy($im);
    $max = 256;
    if ($w > $max || $h > $max) {
        $ratio = min($max / $w, $max / $h);
        $nw    = max(1, (int)($w * $ratio));
        $nh    = max(1, (int)($h * $ratio));
        $rs    = imagecreatetruecolor($nw, $nh);
        // Preserve transparency for PNG/WebP
        imagealphablending($rs, false);
        imagesavealpha($rs, true);
        imagefilledrectangle($rs, 0, 0, $nw, $nh, imagecolorallocatealpha($rs, 0, 0, 0, 127));
        imagecopyresampled($rs, $im, 0, 0, 0, 0, $nw, $nh, $w, $h);
        imagedestroy($im);
        $im = $rs;
    }

    // PNG to keep transparency for the typical favicon shape; small payload
    ob_start();
    imagepng($im, null, 6);
    $bin = ob_get_clean();
    imagedestroy($im);

    $dir = AppConfig::getDataPath() . '/cache/radio_logos';
    if (!is_dir($dir)) @mkdir($dir, 0775, true);

    // File name: {user}_{shorthash}.png — stable enough that re-uploading
    // the same image overwrites instead of accumulating duplicates.
    $hash = substr(sha1($bin), 0, 10);
    $safeUser = preg_replace('/[^a-z0-9_]/i', '_', $user);
    $fname = $safeUser . '_' . $hash . '_' . time() . '.png';
    $path  = $dir . '/' . $fname;
    if (@file_put_contents($path, $bin) === false) {
        throw new Exception("Impossible d'écrire l'image");
    }
    @chmod($path, 0644);

    // Served via the existing serve_radio_logo.php which checks ownership
    $base = rtrim(dirname($_SERVER['SCRIPT_NAME'] ?? ''), '/');
    $url  = $base . '/serve_radio_logo.php?f=' . urlencode($fname);

    // Clean up the temp file used for URL-mode
    if (!empty($tmpFile) && file_exists($tmpFile)) @unlink($tmpFile);

    echo json_encode([
        'error'   => false,
        'message' => $useUrl ? 'Image récupérée depuis l\'URL' : 'Logo téléversé',
        'url'     => $url,
        'size'    => strlen($bin),
    ]);
} catch (\Throwable $e) {
    if (!empty($tmpFile) && file_exists($tmpFile)) @unlink($tmpFile);
    http_response_code(400);
    echo json_encode(['error' => true, 'message' => $e->getMessage()]);
}
