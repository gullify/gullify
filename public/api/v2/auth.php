<?php
/**
 * Gullify API v2 - Auth
 *   POST /api/v2/auth.php?action=login    {username, password} → {token, user}
 *   POST /api/v2/auth.php?action=refresh  (Bearer) → {token, user}  (old token invalidated)
 *   GET  /api/v2/auth.php?action=me       (Bearer) → {user}
 *   POST /api/v2/auth.php?action=logout   (Bearer) → null
 */
require_once __DIR__ . '/_v2.php';

$action = $_GET['action'] ?? $_POST['action'] ?? '';

function v2_user_payload(array $user): array {
    return [
        'id'       => (int)$user['id'],
        'username' => $user['username'],
        'fullName' => $user['full_name'] ?? null,
        'isAdmin'  => (bool)($user['is_admin'] ?? false),
    ];
}

function v2_new_token(Auth $auth, int $userId): string {
    $token = bin2hex(random_bytes(32));
    $auth->createSession(
        $token,
        $userId,
        $_SERVER['REMOTE_ADDR'] ?? '',
        $_SERVER['HTTP_USER_AGENT'] ?? 'API v2 Client'
    );
    return $token;
}

try {
    switch ($action) {
        case 'login':
            if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
                v2_fail('method_not_allowed', 'POST required', 405);
            }
            $body     = v2_body();
            $username = trim((string)($body['username'] ?? ''));
            $password = (string)($body['password'] ?? '');
            if ($username === '' || $password === '') {
                v2_fail('missing_credentials', 'username and password required', 400);
            }
            $auth = new Auth();
            $user = $auth->verifyPassword($username, $password);
            if (!$user) {
                v2_fail('invalid_credentials', 'Invalid username or password', 401);
            }
            $token = v2_new_token($auth, (int)$user['id']);
            $auth->updateLastLogin((int)$user['id']);
            v2_ok(['token' => $token, 'user' => v2_user_payload($user)]);

        case 'refresh':
            $ctx  = v2_auth();
            $auth = $ctx['auth'];
            $new  = v2_new_token($auth, (int)$ctx['user']['id']);
            // Only invalidate the old token if it was a Bearer token —
            // never kill the browser's cookie session from here.
            if (v2_bearer() !== null) {
                $auth->deleteSession($ctx['token']);
            }
            v2_ok(['token' => $new, 'user' => v2_user_payload($ctx['user'])]);

        case 'me':
            $ctx = v2_auth();
            v2_ok(['user' => v2_user_payload($ctx['user'])]);

        case 'logout':
            $ctx = v2_auth();
            $ctx['auth']->deleteSession($ctx['token']);
            v2_ok(null);

        default:
            v2_fail('unknown_action', 'Unknown auth action: ' . $action, 400);
    }
} catch (Throwable $e) {
    error_log('API v2 auth error: ' . $e->getMessage());
    v2_fail('server_error', 'Server error', 500);
}
