<?php
/**
 * Gullify - Language file endpoint
 * Serves translation JSON for a given ?lang= parameter.
 */
$allowed = ['fr', 'en'];
$lang = $_GET['lang'] ?? 'fr';
if (!in_array($lang, $allowed, true)) {
    $lang = 'fr';
}

$file = __DIR__ . '/lang/' . $lang . '.json';
if (!file_exists($file)) {
    $file = __DIR__ . '/lang/fr.json';
}

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: public, max-age=3600');
readfile($file);
