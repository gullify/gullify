<?php
/**
 * Gullify - Authentication Middleware
 * Include at the top of every protected page.
 * Validates session, redirects to login if unauthenticated.
 */
require_once __DIR__ . '/AppConfig.php';
require_once __DIR__ . '/Auth.php';

// Configure session with 30-day cookie
$cookieLifetime = 2592000; // 30 days
$secure = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off');

// Extend PHP's server-side session lifetime to match the cookie (default is only 24 min)
ini_set('session.gc_maxlifetime', $cookieLifetime);

session_set_cookie_params([
    'lifetime' => $cookieLifetime,
    'path'     => '/',
    'domain'   => '',
    'secure'   => $secure,
    'httponly'  => true,
    'samesite'  => 'Lax',
]);
session_name('gullify_session');
session_start();

$authenticated = false;

// Extract Bearer token from Authorization header (used by API clients, e.g. Android app)
$bearerToken = null;
$authHeader  = $_SERVER['HTTP_AUTHORIZATION']
    ?? (function_exists('apache_request_headers') ? (apache_request_headers()['Authorization'] ?? '') : '');
if (preg_match('/^Bearer\s+(\S+)$/i', trim($authHeader), $m)) {
    $bearerToken = $m[1];
}

try {
    $auth = new Auth();

    if ($bearerToken !== null) {
        // ── API token auth (Android / external clients) ──────────────────────
        $dbSession = $auth->getSession($bearerToken);
        if ($dbSession) {
            $_SESSION['user_id'] = $dbSession['user_id'];
            $auth->updateSessionActivity($bearerToken);
            $authenticated = true;
        }
    } else {
        // ── Web session auth (browser cookie) ────────────────────────────────
        // Always look up in the DB so auth works even if the PHP session file
        // was garbage-collected (default gc_maxlifetime is only 24 min).
        $sessionId = session_id();
        $dbSession = $auth->getSession($sessionId);
        if ($dbSession) {
            if (empty($_SESSION['user_id'])) {
                $_SESSION['user_id'] = $dbSession['user_id'];
            }
            if ((int)$dbSession['user_id'] === (int)$_SESSION['user_id']) {
                $auth->updateSessionActivity($sessionId);
                $authenticated = true;
            }
        }
    }

    // Restore session fields if missing (e.g. after PHP session file GC)
    if ($authenticated && (empty($_SESSION['username']) || !isset($_SESSION['is_admin']))) {
        $user = $auth->getUserById((int)$_SESSION['user_id']);
        if ($user) {
            $_SESSION['username'] = $user['username'];
            $_SESSION['is_admin'] = (bool)$user['is_admin'];
        }
    }

    // 1% chance: clean up expired sessions (>30 days)
    if ($authenticated && mt_rand(1, 100) === 1) {
        $auth->cleanOldSessions($cookieLifetime);
    }

} catch (Exception $e) {
    error_log('Auth check failed: ' . $e->getMessage());
}

if (!$authenticated) {
    // Clear any stale session data
    $_SESSION = [];
    if (ini_get('session.use_cookies')) {
        $params = session_get_cookie_params();
        setcookie(session_name(), '', time() - 42000,
            $params['path'], $params['domain'],
            $params['secure'], $params['httponly']
        );
    }
    session_destroy();

    // Redirect to login
    $loginUrl = dirname($_SERVER['SCRIPT_NAME']) . '/login.php';
    // Normalize double slashes
    $loginUrl = preg_replace('#/+#', '/', $loginUrl);
    header('Location: ' . $loginUrl);
    exit;
}
