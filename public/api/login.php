<?php
/**
 * Gullify - API Login
 * POST /api/login.php
 * Body: {"username": "xxx", "password": "xxx"}
 * Returns: {"token": "xxx", "username": "xxx", "user_id": 1}
 *
 * The returned token is used as a Bearer token in subsequent requests:
 *   Authorization: Bearer <token>
 */
header('Content-Type: application/json');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'POST required']);
    exit;
}

require_once __DIR__ . '/../../src/AppConfig.php';
require_once __DIR__ . '/../../src/Auth.php';

try {
    $body     = json_decode(file_get_contents('php://input'), true) ?? [];
    $username = trim($body['username'] ?? '');
    $password = $body['password'] ?? '';

    if ($username === '' || $password === '') {
        http_response_code(400);
        echo json_encode(['error' => 'username and password required']);
        exit;
    }

    $auth = new Auth();
    $user = $auth->verifyPassword($username, $password);

    if (!$user) {
        http_response_code(401);
        echo json_encode(['error' => 'Invalid credentials']);
        exit;
    }

    // Generate a secure random token (64-char hex, stored as a session record)
    $token = bin2hex(random_bytes(32));
    $ip    = $_SERVER['REMOTE_ADDR'] ?? '';
    $ua    = $_SERVER['HTTP_USER_AGENT'] ?? 'API Client';

    $auth->createSession($token, (int)$user['id'], $ip, $ua);
    $auth->updateLastLogin((int)$user['id']);

    echo json_encode([
        'token'    => $token,
        'username' => $user['username'],
        'user_id'  => (int)$user['id'],
    ]);

} catch (Exception $e) {
    error_log('API login error: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['error' => 'Server error']);
}
