<?php
/**
 * Upload artist image endpoint
 * Receives an image, resizes to 500x500, stores as base64 in DB.
 */

ini_set('display_errors', 0);
error_reporting(E_ALL);

header('Content-Type: application/json');

require_once __DIR__ . '/../src/AppConfig.php';

try {
    if (!isset($_FILES['image']) || $_FILES['image']['error'] !== UPLOAD_ERR_OK) {
        throw new Exception('Aucun fichier uploadé ou erreur lors de l\'upload');
    }

    $artistId = $_POST['artist_id'] ?? null;
    if (!$artistId) {
        throw new Exception('ID de l\'artiste requis');
    }

    $allowedTypes = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp'];
    $fileType = $_FILES['image']['type'];

    if (!in_array($fileType, $allowedTypes)) {
        throw new Exception('Type de fichier non supporté. Utilisez JPG, PNG ou WebP.');
    }

    $maxSize = 5 * 1024 * 1024;
    if ($_FILES['image']['size'] > $maxSize) {
        throw new Exception('Le fichier est trop volumineux. Taille maximale: 5MB');
    }

    // Load image with GD
    $image = null;
    switch ($fileType) {
        case 'image/jpeg':
        case 'image/jpg':
            $image = imagecreatefromjpeg($_FILES['image']['tmp_name']);
            break;
        case 'image/png':
            $image = imagecreatefrompng($_FILES['image']['tmp_name']);
            break;
        case 'image/webp':
            $image = imagecreatefromwebp($_FILES['image']['tmp_name']);
            break;
    }

    if (!$image) {
        throw new Exception('Impossible de lire l\'image');
    }

    // Resize only if larger than 1000px (cap at 1000, preserve smaller).
    // Higher cap than the legacy 500 because the audiophile hero displays
    // artists at 240–320px CSS = up to 640px on retina, and a JPEG q=92 at
    // 1000×1000 looks crisp at that size.
    $originalWidth  = imagesx($image);
    $originalHeight = imagesy($image);
    $maxDimension   = 1000;

    if ($originalWidth > $maxDimension || $originalHeight > $maxDimension) {
        $ratio     = min($maxDimension / $originalWidth, $maxDimension / $originalHeight);
        $newWidth  = (int)($originalWidth  * $ratio);
        $newHeight = (int)($originalHeight * $ratio);
        $resized   = imagecreatetruecolor($newWidth, $newHeight);
        imagecopyresampled($resized, $image, 0, 0, 0, 0, $newWidth, $newHeight, $originalWidth, $originalHeight);
        imagedestroy($image);
        $image = $resized;
    }

    ob_start();
    imagejpeg($image, null, 92);
    $jpegData = ob_get_clean();
    imagedestroy($image);

    // Persist as a file in data/cache/artwork (mirrors how albums are stored).
    // Drop the legacy base64 column to avoid storing two copies.
    $cacheDir = AppConfig::getDataPath() . '/cache/artwork';
    if (!is_dir($cacheDir)) @mkdir($cacheDir, 0775, true);
    $cacheFile = $cacheDir . '/artist_' . (int)$artistId . '.jpg';
    if (@file_put_contents($cacheFile, $jpegData) === false) {
        throw new Exception("Impossible d'écrire l'image dans $cacheFile");
    }
    @chmod($cacheFile, 0644);

    $db = AppConfig::getDB();
    $stmt = $db->prepare('UPDATE artists SET image = NULL WHERE id = ?');
    $stmt->execute([$artistId]);

    echo json_encode([
        'error'   => false,
        'message' => 'Image uploadée avec succès',
        'size'    => strlen($jpegData),
        'cached'  => true,
    ]);

} catch (Exception $e) {
    http_response_code(400);
    echo json_encode([
        'error' => true,
        'message' => $e->getMessage()
    ]);
}
