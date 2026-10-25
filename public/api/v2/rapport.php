<?php
/**
 * Les rapports de plantage des apps de la maison et de GulliFY (1.0) : un texte brut par POST, rangé dans
 * DATA_PATH/rapports/<app>/AAAA-MM-JJ.txt. Pas de lecture publique : on lit sur l'atelier.
 *   POST /api/v2/rapport.php?app=gullitv|gulliscan|gullieats|gullify   (text/plain, première ligne « <App>-plantage v1 »)
 * Lire : docker exec gullify sh -c 'cat /app/data/rapports/<app>/*.txt'
 */
const TAILLE_MAX = 65536;
const APPS = ['gullitv', 'gulliscan', 'gullieats', 'gullify'];

header('Cache-Control: no-store');
header('Content-Type: application/json; charset=utf-8');

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    http_response_code(405);
    echo json_encode(['erreur' => 'POST seulement.']);
    exit;
}
$app = strtolower((string)($_GET['app'] ?? ''));
if (!in_array($app, APPS, true)) {
    http_response_code(404);
    echo json_encode(['erreur' => 'Application inconnue.']);
    exit;
}
$corps = file_get_contents('php://input', false, null, 0, TAILLE_MAX + 1);
if ($corps === false || $corps === '') {
    http_response_code(422);
    echo json_encode(['erreur' => 'Rapport vide.']);
    exit;
}
if (strlen($corps) > TAILLE_MAX) {
    http_response_code(413);
    echo json_encode(['erreur' => 'Rapport trop grand.']);
    exit;
}
$premiere = strtok($corps, "\n");
if ($premiere === false || !preg_match('/^[A-Za-z]+-plantage v1$/', trim($premiere))) {
    http_response_code(422);
    echo json_encode(['erreur' => 'Ce n\'est pas un rapport de plantage.']);
    exit;
}
$dossier = (getenv('DATA_PATH') ?: '/app/data') . '/rapports/' . $app;
if (!is_dir($dossier) && !mkdir($dossier, 0775, true)) {
    http_response_code(500);
    echo json_encode(['erreur' => 'Dossier indisponible.']);
    exit;
}
$fichier = $dossier . '/' . date('Y-m-d') . '.txt';
$ligne = "\n========== " . date('c') . " ==========\n" . $corps . "\n";
if (file_put_contents($fichier, $ligne, FILE_APPEND | LOCK_EX) === false) {
    http_response_code(500);
    echo json_encode(['erreur' => 'Écriture impossible.']);
    exit;
}
echo json_encode(['ok' => true]);
