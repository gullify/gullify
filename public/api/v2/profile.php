<?php
/**
 * Gullify API v2 - Profile
 *   POST /api/v2/profile.php?action=set_avatar     (Bearer, multipart 'avatar')
 *        → { avatarUrl }
 *   POST /api/v2/profile.php?action=remove_avatar  (Bearer) → { avatarUrl: null }
 */
require_once __DIR__ . '/_v2.php';
require_once __DIR__ . '/../../../src/Avatar.php';

$ctx    = v2_auth();
$userId = (int) $ctx['user']['id'];
$action = $_GET['action'] ?? $_POST['action'] ?? '';

try {
    switch ($action) {
        case 'set_avatar':
            if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
                v2_fail('method_not_allowed', 'POST required', 405);
            }
            if (empty($_FILES['avatar']) || $_FILES['avatar']['error'] !== UPLOAD_ERR_OK) {
                v2_fail('no_file', 'Aucune image reçue', 400);
            }
            $file    = $_FILES['avatar'];
            $allowed = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp'];
            if (!in_array($file['type'], $allowed, true)) {
                v2_fail('bad_format', 'Format non supporté (JPEG / PNG / WebP)', 400);
            }
            if ($file['size'] > 8 * 1024 * 1024) {
                v2_fail('too_large', 'Fichier trop volumineux (max 8 Mo)', 400);
            }
            Avatar::store($userId, $file['tmp_name'], $file['type']);
            v2_ok(['avatarUrl' => Avatar::url($userId)]);

        case 'remove_avatar':
            Avatar::remove($userId);
            v2_ok(['avatarUrl' => null]);

        default:
            v2_fail('unknown_action', 'Unknown profile action: ' . $action, 400);
    }
} catch (Throwable $e) {
    error_log('API v2 profile error: ' . $e->getMessage());
    v2_fail('server_error', 'Server error', 500);
}
