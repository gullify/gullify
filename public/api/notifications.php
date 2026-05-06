<?php
/**
 * Gullify — Notifications API
 *
 *   GET  ?action=list&limit=N&offset=M  → recent items + unread count
 *   GET  ?action=count                  → unread count only (cheap poll)
 *   POST ?action=mark_read&id=N         → mark one (id=0 → all)
 *   POST ?action=clear&id=N             → delete one (id=0 → all)
 */

header('Content-Type: application/json');

require_once __DIR__ . '/../../src/AppConfig.php';
require_once __DIR__ . '/../../src/auth_required.php';
require_once __DIR__ . '/../../src/Notifications.php';

$user   = $_SESSION['username'] ?? '';
$action = $_GET['action'] ?? 'list';

if ($user === '') {
    http_response_code(401);
    echo json_encode(['success' => false, 'error' => 'unauthenticated']);
    exit;
}

try {
    if ($action === 'list') {
        $limit  = (int)($_GET['limit']  ?? 30);
        $offset = (int)($_GET['offset'] ?? 0);
        echo json_encode([
            'success'   => true,
            'data'      => Notifications::list($user, $limit, $offset),
            'unread'    => Notifications::countUnread($user),
        ]);
    } elseif ($action === 'count') {
        echo json_encode([
            'success' => true,
            'unread'  => Notifications::countUnread($user),
        ]);
    } elseif ($action === 'mark_read') {
        Notifications::markRead($user, (int)($_GET['id'] ?? $_POST['id'] ?? 0));
        echo json_encode(['success' => true, 'unread' => Notifications::countUnread($user)]);
    } elseif ($action === 'clear') {
        Notifications::clear($user, (int)($_GET['id'] ?? $_POST['id'] ?? 0));
        echo json_encode(['success' => true, 'unread' => Notifications::countUnread($user)]);
    } else {
        echo json_encode(['success' => false, 'error' => 'unknown action']);
    }
} catch (\Throwable $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'error' => $e->getMessage()]);
}
