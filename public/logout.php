<?php
/**
 * Gullify - Logout
 * Destroys session, clears cookie, redirects to login.
 */
require_once __DIR__ . '/../src/AppConfig.php';
require_once __DIR__ . '/../src/Auth.php';

$secure = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off');
session_set_cookie_params([
    'lifetime' => 0,
    'path'     => '/',
    'domain'   => '',
    'secure'   => $secure,
    'httponly'  => true,
    'samesite'  => 'Lax',
]);
session_name('gullify_session');
session_start();

// Delete DB session
if (!empty($_SESSION['user_id'])) {
    try {
        $auth = new Auth();
        $auth->deleteSession(session_id());
    } catch (Exception $e) {
        error_log('Logout session cleanup failed: ' . $e->getMessage());
    }
}

// Destroy PHP session
$_SESSION = [];
if (ini_get('session.use_cookies')) {
    $params = session_get_cookie_params();
    setcookie(session_name(), '', time() - 42000,
        $params['path'], $params['domain'],
        $params['secure'], $params['httponly']
    );
}
session_destroy();

header('Location: login.php');
exit;
