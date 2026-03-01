<?php
/**
 * Gullify - Genre Taxonomy API
 * Manages the genres table (hierarchy) and album genre assignment.
 */
require_once __DIR__ . '/../src/AppConfig.php';
require_once __DIR__ . '/../src/TagEditor.php';
require_once __DIR__ . '/../src/auth_required.php';

header('Content-Type: application/json');

$action = $_GET['action'] ?? $_POST['action'] ?? '';

try {
    $db = AppConfig::getDB();

    switch ($action) {

        case 'get_genres':
            // Fetch taxonomy genres (parent + subgenres)
            $stmt = $db->query("SELECT id, name, parent_id FROM genres ORDER BY parent_id IS NOT NULL, name ASC");
            $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

            $parents = [];
            $children = [];
            foreach ($rows as $row) {
                if ($row['parent_id'] === null) {
                    $parents[$row['id']] = ['id' => $row['id'], 'name' => $row['name'], 'subgenres' => []];
                } else {
                    $children[] = $row;
                }
            }
            foreach ($children as $child) {
                if (isset($parents[$child['parent_id']])) {
                    $parents[$child['parent_id']]['subgenres'][] = ['id' => $child['id'], 'name' => $child['name']];
                }
            }

            // If taxonomy is empty, fall back to distinct genres already in albums
            if (empty($parents)) {
                $stmt = $db->query("SELECT DISTINCT genre FROM albums WHERE genre IS NOT NULL AND genre != '' ORDER BY genre ASC");
                $albumGenres = $stmt->fetchAll(PDO::FETCH_COLUMN);
                foreach ($albumGenres as $i => $name) {
                    $parents[$i] = ['id' => null, 'name' => $name, 'subgenres' => []];
                }
            }

            echo json_encode(['success' => true, 'data' => ['genres' => array_values($parents)]]);
            break;

        case 'add_genre':
            $name     = trim($_POST['name'] ?? '');
            $parentId = !empty($_POST['parent_id']) ? intval($_POST['parent_id']) : null;

            if ($name === '') {
                echo json_encode(['success' => false, 'error' => 'Nom requis']);
                break;
            }

            $stmt = $db->prepare("INSERT INTO genres (name, parent_id) VALUES (?, ?)");
            $stmt->execute([$name, $parentId]);
            echo json_encode(['success' => true, 'id' => $db->lastInsertId()]);
            break;

        case 'rename_genre':
            $id   = intval($_POST['id'] ?? 0);
            $name = trim($_POST['name'] ?? '');

            if (!$id || $name === '') {
                echo json_encode(['success' => false, 'error' => 'ID et nom requis']);
                break;
            }

            $stmt = $db->prepare("UPDATE genres SET name = ? WHERE id = ?");
            $stmt->execute([$name, $id]);
            echo json_encode(['success' => true]);
            break;

        case 'delete_genre':
            $id = intval($_POST['id'] ?? 0);
            if (!$id) {
                echo json_encode(['success' => false, 'error' => 'ID requis']);
                break;
            }

            // Subgenres are deleted via ON DELETE SET NULL; clean them up explicitly
            $db->prepare("DELETE FROM genres WHERE parent_id = ?")->execute([$id]);
            $db->prepare("DELETE FROM genres WHERE id = ?")->execute([$id]);
            echo json_encode(['success' => true]);
            break;

        case 'set_album_genre':
            $albumId = intval($_GET['album_id'] ?? 0);
            $genre   = trim($_GET['genre'] ?? '');

            if (!$albumId) {
                echo json_encode(['success' => false, 'error' => 'Album ID requis']);
                break;
            }

            // Update DB
            $stmt = $db->prepare("UPDATE albums SET genre = ? WHERE id = ?");
            $stmt->execute([$genre ?: null, $albumId]);

            // Write genre to ID3 tags of all songs in the album
            $editor = new TagEditor();
            $stmt = $db->prepare("SELECT id FROM songs WHERE album_id = ?");
            $stmt->execute([$albumId]);
            $songIds = $stmt->fetchAll(PDO::FETCH_COLUMN);

            foreach ($songIds as $songId) {
                $editor->updateSongTags((int)$songId, ['genre' => $genre], true);
            }

            echo json_encode(['success' => true, 'updated_files' => count($songIds)]);
            break;

        default:
            echo json_encode(['success' => false, 'error' => 'Action inconnue: ' . $action]);
    }

} catch (Exception $e) {
    echo json_encode(['success' => false, 'error' => $e->getMessage()]);
}
