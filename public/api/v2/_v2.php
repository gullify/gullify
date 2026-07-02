<?php
/**
 * Gullify API v2 - Bootstrap
 *
 * Normalized JSON envelope for every response:
 *   { "success": bool, "data": T|null, "error": {"code": string, "message": string}|null }
 *
 * Auth: Bearer token (Authorization header) or gullify_session cookie.
 * Failures return JSON 401 (never a redirect), so mobile/web clients can
 * intercept and refresh tokens.
 */
declare(strict_types=1);

error_reporting(E_ALL);
ini_set('display_errors', '0');

require_once __DIR__ . '/../../../src/AppConfig.php';
require_once __DIR__ . '/../../../src/Auth.php';

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Authorization, Content-Type');

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(204);
    exit;
}

function v2_ok(mixed $data = null, int $http = 200): never {
    http_response_code($http);
    echo json_encode(['success' => true, 'data' => $data, 'error' => null], JSON_UNESCAPED_UNICODE);
    exit;
}

function v2_fail(string $code, string $message, int $http = 400): never {
    http_response_code($http);
    echo json_encode([
        'success' => false,
        'data'    => null,
        'error'   => ['code' => $code, 'message' => $message],
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

function v2_body(): array {
    $raw = file_get_contents('php://input');
    if ($raw === '' || $raw === false) return [];
    $j = json_decode($raw, true);
    return is_array($j) ? $j : [];
}

function v2_bearer(): ?string {
    $h = $_SERVER['HTTP_AUTHORIZATION']
        ?? (function_exists('apache_request_headers') ? (apache_request_headers()['Authorization'] ?? '') : '');
    return preg_match('/^Bearer\s+(\S+)$/i', trim((string)$h), $m) ? $m[1] : null;
}

/**
 * Authenticate the request. Returns ['user' => row, 'token' => string, 'auth' => Auth].
 * Emits a 401 JSON envelope and exits on failure.
 */
function v2_auth(): array {
    static $cached = null;
    if ($cached !== null) return $cached;

    try {
        $auth  = new Auth();
        $token = v2_bearer() ?? ($_COOKIE['gullify_session'] ?? null);
        if ($token) {
            $sess = $auth->getSession($token);
            if ($sess) {
                $user = $auth->getUserById((int)$sess['user_id']);
                if ($user) {
                    $auth->updateSessionActivity($token);
                    return $cached = ['user' => $user, 'token' => $token, 'auth' => $auth];
                }
            }
        }
    } catch (Throwable $e) {
        error_log('API v2 auth error: ' . $e->getMessage());
        v2_fail('server_error', 'Authentication check failed', 500);
    }
    v2_fail('unauthenticated', 'Valid Bearer token or session required', 401);
}

/**
 * Run a legacy endpoint, capture its output and re-emit it in the v2 envelope.
 * Handles legacy scripts that exit() early via a shutdown fallback, and
 * converts auth redirects (Location header) into JSON 401.
 */
function v2_proxy(string $legacyFile): void {
    $ctx = v2_auth();
    // Legacy endpoints trust ?user= — always force the authenticated user.
    $_GET['user'] = $_POST['user'] = $_REQUEST['user'] = $ctx['user']['username'];

    $GLOBALS['__v2_done'] = false;
    ob_start();
    register_shutdown_function(function (): void {
        if (!empty($GLOBALS['__v2_done'])) return;
        $GLOBALS['__v2_done'] = true;
        v2_emit((string)(ob_get_clean() ?: ''));
    });

    require $legacyFile;

    $GLOBALS['__v2_done'] = true;
    v2_emit((string)(ob_get_clean() ?: ''));
}

/** Normalize a captured legacy response body into the v2 envelope. */
function v2_emit(string $raw): void {
    $code = http_response_code();
    if (!headers_sent()) {
        header('Content-Type: application/json; charset=utf-8');
        if (is_int($code) && $code >= 300 && $code < 400) {
            // Legacy auth_required redirect → JSON 401
            header_remove('Location');
            http_response_code(401);
            echo json_encode([
                'success' => false, 'data' => null,
                'error' => ['code' => 'unauthenticated', 'message' => 'Session expired'],
            ]);
            return;
        }
    }

    $j = json_decode($raw, true);
    if (!is_array($j)) {
        if (!headers_sent()) http_response_code(502);
        echo json_encode([
            'success' => false, 'data' => null,
            'error' => ['code' => 'bad_legacy_response', 'message' => mb_substr(strip_tags($raw), 0, 300)],
        ], JSON_UNESCAPED_UNICODE);
        return;
    }

    // Style A: {success: bool, ...}
    if (array_key_exists('success', $j)) {
        if ($j['success']) {
            // Unwrap {success, data} but keep sibling keys (e.g. {success, data, unread})
            $extras = array_diff_key($j, ['success' => 1]);
            if (array_key_exists('data', $j) && count($extras) === 1) {
                $data = $j['data'];
            } else {
                $data = $extras === [] ? null : $extras;
            }
            echo json_encode(['success' => true, 'data' => $data, 'error' => null], JSON_UNESCAPED_UNICODE);
        } else {
            $msg = is_string($j['error'] ?? null) ? $j['error'] : (string)($j['message'] ?? 'Unknown error');
            echo json_encode([
                'success' => false, 'data' => null,
                'error' => ['code' => 'legacy_error', 'message' => $msg],
            ], JSON_UNESCAPED_UNICODE);
        }
        return;
    }

    // Style B: {error: bool|string, message?, data?}
    if (array_key_exists('error', $j)) {
        $isErr = is_string($j['error']) ? true : (bool)$j['error'];
        if ($isErr) {
            $msg = is_string($j['error']) ? $j['error'] : (string)($j['message'] ?? 'Unknown error');
            echo json_encode([
                'success' => false, 'data' => null,
                'error' => ['code' => 'legacy_error', 'message' => $msg],
            ], JSON_UNESCAPED_UNICODE);
        } else {
            $extras = array_diff_key($j, ['error' => 1, 'message' => 1]);
            if (array_key_exists('data', $j) && count($extras) === 1) {
                $data = $j['data'];
            } else {
                $data = $extras === [] ? null : $extras;
            }
            echo json_encode(['success' => true, 'data' => $data, 'error' => null], JSON_UNESCAPED_UNICODE);
        }
        return;
    }

    // Style C: bare payload
    echo json_encode(['success' => true, 'data' => $j, 'error' => null], JSON_UNESCAPED_UNICODE);
}
