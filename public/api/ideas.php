<?php
/**
 * Carnet d'idées de développement (par utilisateur), stocké en base.
 * Actions : list | add | set_status | update | delete
 * Utilisé par l'app mobile et lu par Claude côté serveur.
 */
require_once __DIR__ . '/../../src/AppConfig.php';
require_once __DIR__ . '/../../src/auth_required.php';

header('Content-Type: application/json');
header('Cache-Control: no-cache');

$user = $_SESSION['username'] ?? ($_REQUEST['user'] ?? '');
if ($user === '') {
    http_response_code(401);
    echo json_encode(['success' => false, 'error' => 'unauthenticated']);
    return;
}

$db = AppConfig::getDB();
$db->exec("
    CREATE TABLE IF NOT EXISTS dev_ideas (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user VARCHAR(255) NOT NULL,
        text TEXT NOT NULL,
        status VARCHAR(20) NOT NULL DEFAULT 'todo',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX (user)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
");

$readBody = function (): array {
    $j = json_decode((string)file_get_contents('php://input'), true);
    return is_array($j) ? $j : [];
};

$action = $_REQUEST['action'] ?? 'list';

switch ($action) {
    case 'list':
        $stmt = $db->prepare("
            SELECT id, text, status, created_at
            FROM dev_ideas WHERE user = ?
            ORDER BY (status = 'done') ASC, created_at DESC
        ");
        $stmt->execute([$user]);
        $ideas = array_map(fn($r) => [
            'id'        => (int)$r['id'],
            'text'      => $r['text'],
            'status'    => $r['status'],
            'createdAt' => $r['created_at'],
        ], $stmt->fetchAll(PDO::FETCH_ASSOC));
        echo json_encode(['success' => true, 'ideas' => $ideas]);
        break;

    case 'add':
        $body = $readBody();
        $text = trim((string)($body['text'] ?? $_POST['text'] ?? ''));
        if ($text === '') {
            echo json_encode(['success' => false, 'error' => 'text required']);
            break;
        }
        $stmt = $db->prepare("INSERT INTO dev_ideas (user, text) VALUES (?, ?)");
        $stmt->execute([$user, mb_substr($text, 0, 2000)]);
        echo json_encode(['success' => true, 'id' => (int)$db->lastInsertId()]);
        break;

    case 'set_status':
        $body   = $readBody();
        $id     = (int)($body['id'] ?? 0);
        $status = ($body['status'] ?? 'todo') === 'done' ? 'done' : 'todo';
        $db->prepare("UPDATE dev_ideas SET status = ? WHERE id = ? AND user = ?")
           ->execute([$status, $id, $user]);
        echo json_encode(['success' => true]);
        break;

    case 'request':
        // Confie l'idée à Claude (traitée par le cron process-ideas.sh).
        $body = $readBody();
        $id   = (int)($body['id'] ?? 0);
        $db->prepare("UPDATE dev_ideas SET status = 'requested' WHERE id = ? AND user = ?")
           ->execute([$id, $user]);
        echo json_encode(['success' => true]);
        break;

    case 'update':
        $body = $readBody();
        $id   = (int)($body['id'] ?? 0);
        $text = trim((string)($body['text'] ?? ''));
        if ($text === '') {
            echo json_encode(['success' => false, 'error' => 'text required']);
            break;
        }
        $db->prepare("UPDATE dev_ideas SET text = ? WHERE id = ? AND user = ?")
           ->execute([mb_substr($text, 0, 2000), $id, $user]);
        echo json_encode(['success' => true]);
        break;

    case 'delete':
        $body = $readBody();
        $id   = (int)($body['id'] ?? $_REQUEST['id'] ?? 0);
        $db->prepare("DELETE FROM dev_ideas WHERE id = ? AND user = ?")
           ->execute([$id, $user]);
        echo json_encode(['success' => true]);
        break;

    default:
        echo json_encode(['success' => false, 'error' => 'unknown action']);
}
