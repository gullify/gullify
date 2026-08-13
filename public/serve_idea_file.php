<?php
/**
 * Gullify — Sert une pièce jointe du carnet d'idées (idée #84).
 *
 * GET /serve_idea_file.php?id=N
 *   Auth : en-tête `Authorization: Bearer …` (app), cookie de session (web)
 *   ou `?token=…` (pour ouvrir/partager un fichier hors de l'app, où l'on ne
 *   peut pas poser d'en-tête). Le fichier n'est servi qu'à son propriétaire.
 *
 * Les images partent en ligne ; tout le reste part en téléchargement générique,
 * pour qu'un fichier téléversé ne puisse jamais s'exécuter dans le domaine.
 */
require_once __DIR__ . '/../src/AppConfig.php';
require_once __DIR__ . '/../src/Auth.php';
require_once __DIR__ . '/../src/IdeaAttachments.php';

$id = isset($_GET['id']) ? (int)$_GET['id'] : 0;
if ($id <= 0) {
    http_response_code(400);
    exit;
}

$header = $_SERVER['HTTP_AUTHORIZATION']
    ?? (function_exists('apache_request_headers') ? (apache_request_headers()['Authorization'] ?? '') : '');
$token = preg_match('/^Bearer\s+(\S+)$/i', trim((string)$header), $m)
    ? $m[1]
    : (string)($_GET['token'] ?? $_COOKIE['gullify_session'] ?? '');

if ($token === '') {
    http_response_code(401);
    exit;
}

try {
    $auth    = new Auth();
    $session = $auth->getSession($token);
    $account = $session ? $auth->getUserById((int)$session['user_id']) : false;
    if (!$account) {
        http_response_code(401);
        exit;
    }

    $db  = AppConfig::getDB();
    $row = IdeaAttachments::get($db, $id, (string)$account['username']);
    $path = $row ? IdeaAttachments::path($row) : '';
    if (!$row || $path === '' || !is_file($path)) {
        http_response_code(404);
        exit;
    }
} catch (Throwable $e) {
    error_log('serve_idea_file: ' . $e->getMessage());
    http_response_code(500);
    exit;
}

$mime   = (string)$row['mime'];
$inline = IdeaAttachments::isImage($mime);

header('Content-Type: ' . ($inline ? $mime : 'application/octet-stream'));
header('Content-Length: ' . filesize($path));
header('Cache-Control: private, max-age=86400');
header('X-Content-Type-Options: nosniff');
header(sprintf(
    'Content-Disposition: %s; filename="%s"',
    $inline ? 'inline' : 'attachment',
    str_replace('"', '', (string)$row['name'])
));
readfile($path);
