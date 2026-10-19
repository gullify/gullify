<?php
/**
 * Gullify API v2 - Auth
 *   POST /api/v2/auth.php?action=login    {username, password} → {token, user}
 *   POST /api/v2/auth.php?action=refresh  (Bearer) → {token, user}  (old token invalidated)
 *   GET  /api/v2/auth.php?action=me       (Bearer) → {user}
 *   POST /api/v2/auth.php?action=logout   (Bearer) → null
 *   POST /api/v2/auth.php?action=change_password (Bearer) {old_password, new_password} → {user}
 *
 *   GET  /api/v2/auth.php?action=subsonic        (Bearer) → {actif, identifiant}
 *   POST /api/v2/auth.php?action=subsonic_generer (Bearer) → {motDePasse, identifiant} (montré UNE fois)
 *   POST /api/v2/auth.php?action=subsonic_revoquer (Bearer) → {actif: false}
 *
 * Comptes de la maison (COMPTES_URL posé, voir src/Comptes.php) : login prend
 * {courriel, password} (un nom d'utilisateur est refusé), change_password
 * passe par Comptes (10 caractères au moins), et les clients Subsonic utilisent
 * un « mot de passe d'application » généré ici (subsonic_*), jamais celui de la maison.
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
        'courriel'  => $user['email'] ?? null,
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
            $auth = new Auth();
            if (Comptes::actif()) {
                // Courriel + mot de passe de la maison, vérifiés par Comptes.
                $courriel = trim((string)($body['courriel'] ?? $body['email'] ?? $username));
                if ($courriel === '' || $password === '') {
                    v2_fail('missing_credentials', 'Courriel et mot de passe requis.', 400);
                }
                if (!str_contains($courriel, '@')) {
                    v2_fail('courriel_requis', 'Connecte-toi avec ton courriel et le mot de passe de la maison.', 400);
                }
                try {
                    $user = Comptes::connecter($courriel, $password, Comptes::ipClient());
                } catch (ComptesErreur $e) {
                    v2_fail($e->code_api, $e->getMessage(), $e->http);
                }
            } else {
                if ($username === '' || $password === '') {
                    v2_fail('missing_credentials', 'username and password required', 400);
                }
                $user = $auth->verifyPassword($username, $password);
            }
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
            if (Comptes::actif()) {
                if (mb_strlen($new) < 10) {
                    v2_fail('weak_password', 'Le nouveau mot de passe doit faire au moins 10 caractères.', 400);
                }
                if ($new === $old) {
                    v2_fail('same_password', 'Le nouveau mot de passe doit être différent de l\'ancien.', 400);
                }
                try {
                    Comptes::changer($ctx['user'], $old, $new, $ctx['token']);
                } catch (ComptesErreur $e) {
                    v2_fail($e->code_api, $e->getMessage(), $e->http);
                }
                $user = $ctx['auth']->getUserById((int)$ctx['user']['id']);
                v2_ok(['user' => v2_user_payload($user ?: $ctx['user'])]);
            }
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

        // Mot de passe d'application Subsonic (comptes de la maison seulement :
        // sans eux, Subsonic accepte le mot de passe GulliFY, comme avant).
        case 'subsonic':
        case 'subsonic_generer':
        case 'subsonic_revoquer':
            $ctx = v2_auth();
            if (!Comptes::actif()) {
                v2_fail('comptes_inactif', 'Les clients Subsonic utilisent ton mot de passe GulliFY.', 400);
            }
            $uid = (int)$ctx['user']['id'];
            $db  = AppConfig::getDB();
            if ($action === 'subsonic') {
                $st = $db->prepare('SELECT subsonic_password IS NOT NULL AND subsonic_password <> \'\' FROM users WHERE id = ?');
                $st->execute([$uid]);
                v2_ok(['actif' => (bool)$st->fetchColumn(), 'identifiant' => $ctx['user']['username']]);
            }
            if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
                v2_fail('method_not_allowed', 'POST required', 405);
            }
            if ($action === 'subsonic_revoquer') {
                $db->prepare('UPDATE users SET subsonic_password = NULL WHERE id = ?')->execute([$uid]);
                v2_ok(['actif' => false, 'identifiant' => $ctx['user']['username']]);
            }
            // Un nouveau remplace l'ancien : les clients déjà configurés devront le recevoir.
            $mdp = Comptes::nouveauMotDePasseSubsonic();
            $db->prepare('UPDATE users SET subsonic_password = ? WHERE id = ?')->execute([$mdp, $uid]);
            v2_ok(['actif' => true, 'identifiant' => $ctx['user']['username'], 'motDePasse' => $mdp]);

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
