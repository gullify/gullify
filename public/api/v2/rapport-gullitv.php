<?php
/**
 * Les rapports de plantage de GulliTV (0.29.1) : un texte brut (« GulliTV-plantage v1 … ») par POST, rangé
 * dans DATA_PATH/rapports-gullitv/AAAA-MM-JJ.txt. Rien n'est renvoyé, sauf le code. Pas de lecture publique.
 * Lire : docker exec gullify sh -c 'cat /app/data/rapports-gullitv/*.txt'
 */
const TAILLE_MAX = 65536;

header('Cache-Control: no-store');
header('Content-Type: application/json; charset=utf-8');

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    http_response_code(405);
    echo json_encode(['erreur' => 'POST seulement.']);
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
if (!str_starts_with($corps, 'GulliTV-plantage')) {
    http_response_code(422);
    echo json_encode(['erreur' => 'Ce n\'est pas un rapport GulliTV.']);
    exit;
}
$dossier = (getenv('DATA_PATH') ?: '/app/data') . '/rapports-gullitv';
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
