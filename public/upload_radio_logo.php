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

try {
    if (empty($_FILES['logo']) || $_FILES['logo']['error'] !== UPLOAD_ERR_OK) {
        throw new Exception('Aucun fichier reçu');
    }

    $file = $_FILES['logo'];
    $allowed = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp'];
    if (!in_array($file['type'], $allowed, true)) {
        throw new Exception('Format non supporté (JPEG / PNG / WebP uniquement)');
    }
    if ($file['size'] > 4 * 1024 * 1024) {
        throw new Exception('Fichier trop volumineux (max 4 MB)');
    }

    $im = null;
    switch ($file['type']) {
        case 'image/jpeg':
        case 'image/jpg':
            $im = imagecreatefromjpeg($file['tmp_name']);
            break;
        case 'image/png':
            $im = imagecreatefrompng($file['tmp_name']);
            break;
        case 'image/webp':
            $im = imagecreatefromwebp($file['tmp_name']);
            break;
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

    echo json_encode([
        'error'   => false,
        'message' => 'Logo téléversé',
        'url'     => $url,
        'size'    => strlen($bin),
    ]);
} catch (\Throwable $e) {
    http_response_code(400);
    echo json_encode(['error' => true, 'message' => $e->getMessage()]);
}
