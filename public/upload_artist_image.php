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

    // Resize (max 500x500, maintain aspect ratio)
    $originalWidth = imagesx($image);
    $originalHeight = imagesy($image);
    $maxDimension = 500;
    $ratio = min($maxDimension / $originalWidth, $maxDimension / $originalHeight);
    $newWidth = (int)($originalWidth * $ratio);
    $newHeight = (int)($originalHeight * $ratio);

    $resizedImage = imagecreatetruecolor($newWidth, $newHeight);

    if ($fileType === 'image/png') {
        imagealphablending($resizedImage, false);
        imagesavealpha($resizedImage, true);
        $transparent = imagecolorallocatealpha($resizedImage, 255, 255, 255, 127);
        imagefilledrectangle($resizedImage, 0, 0, $newWidth, $newHeight, $transparent);
    }

    imagecopyresampled(
        $resizedImage, $image,
        0, 0, 0, 0,
        $newWidth, $newHeight,
        $originalWidth, $originalHeight
    );

    // Convert to JPEG base64
    ob_start();
    imagejpeg($resizedImage, null, 85);
    $optimizedImageData = ob_get_clean();
    $base64Image = base64_encode($optimizedImageData);

    imagedestroy($image);
    imagedestroy($resizedImage);

    // Save to database
    $db = AppConfig::getDB();
    $stmt = $db->prepare('UPDATE artists SET image = ? WHERE id = ?');
    $stmt->execute([$base64Image, $artistId]);
    $updated = $stmt->rowCount();

    if ($updated === 0) {
        echo json_encode([
            'error' => false,
            'message' => 'Artiste ignoré (scan en cours ou déjà à jour)',
            'skipped' => true
        ]);
        exit;
    }

    echo json_encode([
        'error' => false,
        'message' => 'Image uploadée avec succès',
        'image' => $base64Image
    ]);

} catch (Exception $e) {
    http_response_code(400);
    echo json_encode([
        'error' => true,
        'message' => $e->getMessage()
    ]);
}
