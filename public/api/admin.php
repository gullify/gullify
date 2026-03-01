<?php
/**
 * Gullify - Admin API
 * User management and directory management. Requires is_admin session.
 */
require_once __DIR__ . '/../../src/AppConfig.php';
require_once __DIR__ . '/../../src/auth_required.php';
require_once __DIR__ . '/../../src/Auth.php';
require_once __DIR__ . '/../../src/Storage/StorageInterface.php';
require_once __DIR__ . '/../../src/Storage/LocalStorage.php';
require_once __DIR__ . '/../../src/Storage/SFTPStorage.php';
require_once __DIR__ . '/../../src/Storage/StorageFactory.php';

header('Content-Type: application/json');

// Admin only
if (empty($_SESSION['is_admin'])) {
    http_response_code(403);
    echo json_encode(['success' => false, 'error' => 'Accès refusé']);
    exit;
}

$action = $_GET['action'] ?? $_POST['action'] ?? '';

try {
    $auth = new Auth();

    switch ($action) {

        // ── User list ──────────────────────────────────────────────
        case 'list_users':
            $users = $auth->getAllUsers();
            // Never expose password_hash or raw sftp_password
            foreach ($users as &$u) {
                unset($u['password_hash']);
                // Return empty string for sftp_password — never send encrypted value to client
                if (isset($u['sftp_password'])) $u['sftp_password'] = '';
            }
            unset($u);
            echo json_encode(['success' => true, 'data' => $users]);
            break;

        // ── Create user ────────────────────────────────────────────
        case 'create_user':
            $username    = trim($_POST['username'] ?? '');
            $password    = $_POST['password'] ?? '';
            $fullName    = trim($_POST['full_name'] ?? '');
            $isAdmin     = !empty($_POST['is_admin']) ? 1 : 0;
            $musicDir    = trim($_POST['music_directory'] ?? '');
            $storageType = trim($_POST['storage_type'] ?? 'local');
            $sftpHost    = trim($_POST['sftp_host'] ?? '');
            $sftpPort    = (int) ($_POST['sftp_port'] ?? 22);
            $sftpUser    = trim($_POST['sftp_user'] ?? '');
            $sftpPass    = $_POST['sftp_password'] ?? '';
            $sftpPath    = trim($_POST['sftp_path'] ?? '');

            if (empty($username) || empty($password)) {
                throw new Exception('Nom d\'utilisateur et mot de passe requis');
            }
            if (strlen($password) < 6) {
                throw new Exception('Le mot de passe doit faire au moins 6 caractères');
            }
            if (!preg_match('/^[a-zA-Z0-9_\-\.]+$/', $username)) {
                throw new Exception('Nom d\'utilisateur invalide (lettres, chiffres, _ - . uniquement)');
            }

            $userId = $auth->createUser($username, $password, $fullName, (bool)$isAdmin, $musicDir ?: null);

            // Save SFTP settings if provided
            if ($storageType === 'sftp') {
                $encryptedPass = $sftpPass !== '' ? StorageFactory::encryptPassword($sftpPass) : '';
                $db = AppConfig::getDB();
                $stmt = $db->prepare(
                    'UPDATE users SET storage_type=?, sftp_host=?, sftp_port=?, sftp_user=?, sftp_password=?, sftp_path=?
                     WHERE id=?'
                );
                $stmt->execute(['sftp', $sftpHost ?: null, $sftpPort ?: 22, $sftpUser ?: null,
                                $encryptedPass ?: null, $sftpPath ?: null, $userId]);
            }

            echo json_encode(['success' => true, 'user_id' => $userId]);
            break;

        // ── Delete user ────────────────────────────────────────────
        case 'delete_user':
            $userId = intval($_POST['user_id'] ?? 0);
            if (!$userId) throw new Exception('user_id requis');

            // Cannot delete yourself
            if ($userId === (int)$_SESSION['user_id']) {
                throw new Exception('Vous ne pouvez pas supprimer votre propre compte');
            }

            $auth->deleteUser($userId);
            echo json_encode(['success' => true]);
            break;

        // ── Toggle active ──────────────────────────────────────────
        case 'toggle_active':
            $userId = intval($_POST['user_id'] ?? 0);
            if (!$userId) throw new Exception('user_id requis');
            if ($userId === (int)$_SESSION['user_id']) {
                throw new Exception('Vous ne pouvez pas désactiver votre propre compte');
            }

            $auth->toggleUserActive($userId);
            echo json_encode(['success' => true]);
            break;

        // ── Update password ────────────────────────────────────────
        case 'update_password':
            $userId   = intval($_POST['user_id'] ?? 0);
            $password = $_POST['password'] ?? '';
            if (!$userId) throw new Exception('user_id requis');
            if (strlen($password) < 6) throw new Exception('Le mot de passe doit faire au moins 6 caractères');

            $auth->updatePassword($userId, $password);
            echo json_encode(['success' => true]);
            break;

        // ── Update music directory ─────────────────────────────────
        case 'update_directory':
            $userId   = intval($_POST['user_id'] ?? 0);
            $musicDir = trim($_POST['music_directory'] ?? '');
            if (!$userId) throw new Exception('user_id requis');

            // Validate that directory exists
            $basePath = AppConfig::getMusicBasePath();
            if (!empty($musicDir)) {
                $fullPath = $basePath . '/' . $musicDir;
                if (!is_dir($fullPath)) {
                    throw new Exception("Répertoire introuvable: $musicDir");
                }
            }

            $auth->updateMusicDirectory($userId, $musicDir ?: null);
            echo json_encode(['success' => true]);
            break;

        // ── List available directories ─────────────────────────────
        case 'list_directories':
            $basePath = AppConfig::getMusicBasePath();
            $dirs = [];
            if (is_dir($basePath)) {
                foreach (scandir($basePath) as $entry) {
                    if ($entry === '.' || $entry === '..') continue;
                    if (is_dir($basePath . '/' . $entry)) {
                        $dirs[] = $entry;
                    }
                }
            }
            echo json_encode(['success' => true, 'data' => $dirs, 'base_path' => $basePath]);
            break;

        // ── Update SFTP settings ───────────────────────────────────
        case 'update_sftp':
            $userId      = intval($_POST['user_id'] ?? 0);
            $storageType = trim($_POST['storage_type'] ?? 'local');
            $sftpHost    = trim($_POST['sftp_host'] ?? '');
            $sftpPort    = (int) ($_POST['sftp_port'] ?? 22);
            $sftpUser    = trim($_POST['sftp_user'] ?? '');
            $sftpPass    = $_POST['sftp_password'] ?? '';  // empty = keep existing
            $sftpPath    = trim($_POST['sftp_path'] ?? '');

            if (!$userId) throw new Exception('user_id requis');

            $db = AppConfig::getDB();

            if ($storageType !== 'sftp') {
                // Switch back to local
                $stmt = $db->prepare('UPDATE users SET storage_type=? WHERE id=?');
                $stmt->execute(['local', $userId]);
            } else {
                // Update SFTP fields; only update password if a new one was supplied
                if ($sftpPass !== '') {
                    $encryptedPass = StorageFactory::encryptPassword($sftpPass);
                    $stmt = $db->prepare(
                        'UPDATE users SET storage_type=?, sftp_host=?, sftp_port=?, sftp_user=?, sftp_password=?, sftp_path=?
                         WHERE id=?'
                    );
                    $stmt->execute(['sftp', $sftpHost ?: null, $sftpPort ?: 22, $sftpUser ?: null,
                                    $encryptedPass, $sftpPath ?: null, $userId]);
                } else {
                    // Keep existing encrypted password
                    $stmt = $db->prepare(
                        'UPDATE users SET storage_type=?, sftp_host=?, sftp_port=?, sftp_user=?, sftp_path=?
                         WHERE id=?'
                    );
                    $stmt->execute(['sftp', $sftpHost ?: null, $sftpPort ?: 22, $sftpUser ?: null,
                                    $sftpPath ?: null, $userId]);
                }
            }

            echo json_encode(['success' => true]);
            break;

        // ── Test SFTP connection ────────────────────────────────────
        case 'test_sftp_connection':
            $sftpHost = trim($_POST['sftp_host'] ?? '');
            $sftpPort = (int) ($_POST['sftp_port'] ?? 22);
            $sftpUser = trim($_POST['sftp_user'] ?? '');
            $sftpPass = $_POST['sftp_password'] ?? '';
            $sftpPath = trim($_POST['sftp_path'] ?? '');
            $userId   = intval($_POST['user_id'] ?? 0);

            if (empty($sftpHost) || empty($sftpUser) || empty($sftpPath)) {
                throw new Exception('Hôte, utilisateur et chemin SFTP requis');
            }

            // If no password supplied and user_id given, decrypt stored password
            if ($sftpPass === '' && $userId > 0) {
                $db   = AppConfig::getDB();
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

        // ── Toggle admin ───────────────────────────────────────────
        case 'toggle_admin':
            $userId = intval($_POST['user_id'] ?? 0);
            if (!$userId) throw new Exception('user_id requis');
            if ($userId === (int)$_SESSION['user_id']) {
                throw new Exception('Vous ne pouvez pas modifier votre propre rôle');
            }

            $db = AppConfig::getDB();
            $stmt = $db->prepare('UPDATE users SET is_admin = 1 - is_admin WHERE id = ?');
            $stmt->execute([$userId]);
            echo json_encode(['success' => true]);
            break;

        default:
            throw new Exception('Action inconnue');
    }

} catch (Exception $e) {
    http_response_code(400);
    echo json_encode(['success' => false, 'error' => $e->getMessage()]);
}
