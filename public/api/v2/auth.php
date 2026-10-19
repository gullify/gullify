<?php
/**
 * Gullify API v2 - Auth
 *   POST /api/v2/auth.php?action=login    {username, password} → {token, user}
 *   POST /api/v2/auth.php?action=refresh  (Bearer) → {token, user}  (old token invalidated)
 *   GET  /api/v2/auth.php?action=me       (Bearer) → {user}
 *   POST /api/v2/auth.php?action=logout   (Bearer) → null
 *   POST /api/v2/auth.php?action=change_password (Bearer) {old_password, new_password} → {user}
 *
 * Mot de passe temporaire (posé par « Ma maison ») : la connexion réussit mais
 * porte "doit_changer": true, et toute autre route répond 403
 * « changement_requis » jusqu'au change_password — seuls me et logout passent.
 */
require_once __DIR__ . '/_v2.php';
require_once __DIR__ . '/../../../src/Avatar.php';

$action = $_GET['action'] ?? $_POST['action'] ?? '';
$GLOBALS['v2_changement_permis'] = in_array($action, ['me', 'logout', 'change_password'], true);

function v2_user_payload(array $user): array {
    return [
        'id'        => (int)$user['id'],
        'username'  => $user['username'],
        'fullName'  => $user['full_name'] ?? null,
        'isAdmin'   => (bool)($user['is_admin'] ?? false),
        'avatarUrl' => Avatar::url((int)$user['id']),
        'doitChanger' => Auth::mustChangePassword($user),
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
                if ($auth->isDisabledAccount($username, $password)) {
                    v2_fail('account_disabled', 'Ce compte est désactivé. Demande à la personne qui gère la maison de le réactiver.', 403);
                }
                v2_fail('invalid_credentials', 'Invalid username or password', 401);
            }
            $token = v2_new_token($auth, (int)$user['id']);
            $auth->updateLastLogin((int)$user['id']);
            v2_ok([
                'token'        => $token,
                'user'         => v2_user_payload($user),
                'doit_changer' => Auth::mustChangePassword($user),
            ]);

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

        case 'change_password':
            if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
                v2_fail('method_not_allowed', 'POST required', 405);
            }
            $ctx  = v2_auth();
            $body = v2_body();
            $old  = (string)($body['old_password'] ?? '');
            $new  = (string)($body['new_password'] ?? '');
            if (!password_verify($old, (string)$ctx['user']['password_hash'])) {
                v2_fail('wrong_password', 'Le mot de passe actuel est incorrect.', 400);
            }
            if (mb_strlen($new) < 8) {
                v2_fail('weak_password', 'Le nouveau mot de passe doit faire au moins 8 caractères.', 400);
            }
            if ($new === $old) {
                v2_fail('same_password', 'Le nouveau mot de passe doit être différent de l\'ancien.', 400);
            }
            // Le jeton courant reste valable ; toutes les autres sessions tombent.
            $ctx['auth']->changeOwnPassword((int)$ctx['user']['id'], $new, $ctx['token']);
            $user = $ctx['auth']->getUserById((int)$ctx['user']['id']);
            v2_ok(['user' => v2_user_payload($user ?: $ctx['user'])]);

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
