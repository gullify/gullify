<?php
/**
 * Gullify - Storage Settings API (per-user, no admin required)
 * Allows any authenticated user to configure their own storage backend.
 */
require_once __DIR__ . '/../../src/AppConfig.php';
require_once __DIR__ . '/../../src/auth_required.php';
require_once __DIR__ . '/../../src/Storage/StorageInterface.php';
require_once __DIR__ . '/../../src/Storage/LocalStorage.php';
require_once __DIR__ . '/../../src/Storage/SFTPStorage.php';
require_once __DIR__ . '/../../src/Storage/StorageFactory.php';

header('Content-Type: application/json');

$action   = $_GET['action'] ?? $_POST['action'] ?? '';
$userId   = (int)($_SESSION['user_id'] ?? 0);
$username = $_SESSION['username'] ?? '';

if (!$userId) {
    http_response_code(401);
    echo json_encode(['success' => false, 'error' => 'Non authentifié']);
    exit;
}

try {
    $db = AppConfig::getDB();

    switch ($action) {

        // ── Get current storage settings ──────────────────────────
        case 'get_storage':
            $stmt = $db->prepare(
                'SELECT storage_type, sftp_host, sftp_port, sftp_user, sftp_path, music_directory
                 FROM users WHERE id=?'
            );
            $stmt->execute([$userId]);
            $row = $stmt->fetch(PDO::FETCH_ASSOC);
            if (!$row) throw new Exception('Utilisateur introuvable');
            $row['sftp_password'] = ''; // never expose
            echo json_encode(['success' => true, 'data' => $row]);
            break;

        // ── Update storage settings ───────────────────────────────
        case 'update_storage':
            $storageType = trim($_POST['storage_type'] ?? 'local');
            $musicDir    = trim($_POST['music_directory'] ?? '');
            $sftpHost    = trim($_POST['sftp_host'] ?? '');
            $sftpPort    = (int)($_POST['sftp_port'] ?? 22);
            $sftpUser    = trim($_POST['sftp_user'] ?? '');
            $sftpPass    = $_POST['sftp_password'] ?? '';  // empty = keep existing
            $sftpPath    = trim($_POST['sftp_path'] ?? '');

            if ($storageType === 'local') {
                $stmt = $db->prepare(
                    'UPDATE users SET storage_type=?, music_directory=?,
                     sftp_host=NULL, sftp_port=22, sftp_user=NULL, sftp_password=NULL, sftp_path=NULL
                     WHERE id=?'
                );
                $stmt->execute(['local', $musicDir ?: null, $userId]);
            } else {
                // SFTP
                if ($sftpPass !== '') {
                    $encryptedPass = StorageFactory::encryptPassword($sftpPass);
                    $stmt = $db->prepare(
                        'UPDATE users SET storage_type=?, sftp_host=?, sftp_port=?, sftp_user=?, sftp_password=?, sftp_path=?
                         WHERE id=?'
                    );
                    $stmt->execute(['sftp', $sftpHost ?: null, $sftpPort ?: 22, $sftpUser ?: null,
                                    $encryptedPass, $sftpPath ?: null, $userId]);
                } else {
                    $stmt = $db->prepare(
                        'UPDATE users SET storage_type=?, sftp_host=?, sftp_port=?, sftp_user=?, sftp_path=?
                         WHERE id=?'
                    );
                    $stmt->execute(['sftp', $sftpHost ?: null, $sftpPort ?: 22, $sftpUser ?: null,
                                    $sftpPath ?: null, $userId]);
                }
            }

            echo json_encode(['success' => true, 'message' => 'Paramètres de stockage enregistrés']);
            break;

        // ── Test SFTP connection ──────────────────────────────────
        case 'test_sftp':
            $sftpHost = trim($_POST['sftp_host'] ?? '');
            $sftpPort = (int)($_POST['sftp_port'] ?? 22);
            $sftpUser = trim($_POST['sftp_user'] ?? '');
            $sftpPass = $_POST['sftp_password'] ?? '';
            $sftpPath = trim($_POST['sftp_path'] ?? '');

            if (empty($sftpHost) || empty($sftpUser) || empty($sftpPath)) {
                throw new Exception('Hôte, utilisateur et chemin SFTP requis');
            }

            // If no password supplied, try stored encrypted password
            if ($sftpPass === '') {
                $stmt = $db->prepare('SELECT sftp_password FROM users WHERE id=?');
                $stmt->execute([$userId]);
                $row = $stmt->fetch(PDO::FETCH_ASSOC);
                if ($row && !empty($row['sftp_password'])) {
                    $sftpPass = StorageFactory::decryptPassword($row['sftp_password']);
                }
            }

            if (empty($sftpPass)) {
                throw new Exception('Mot de passe SFTP requis pour tester la connexion');
            }

            try {
                $testStorage = new SFTPStorage($sftpHost, $sftpPort, $sftpUser, $sftpPass, $sftpPath);
                $accessible  = $testStorage->isDir($sftpPath);
                if ($accessible) {
                    echo json_encode(['success' => true, 'message' => 'Connexion SFTP réussie']);
                } else {
                    echo json_encode(['success' => false, 'error' => 'Chemin SFTP inaccessible ou inexistant: ' . $sftpPath]);
                }
            } catch (Exception $e) {
                echo json_encode(['success' => false, 'error' => 'Erreur SFTP: ' . $e->getMessage()]);
            }
            break;

        default:
            throw new Exception('Action inconnue: ' . htmlspecialchars($action));
    }

} catch (Exception $e) {
    echo json_encode(['success' => false, 'error' => $e->getMessage()]);
}
