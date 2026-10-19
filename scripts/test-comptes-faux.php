<?php
/**
 * Un FAUX service Comptes (CONTRAT-COMPTES.md, §1) pour scripts/test-comptes.php :
 * routeur de `php -S`, état dans le fichier JSON désigné par FAUX_COMPTES_ETAT.
 * Jamais en production.
 */
if (PHP_SAPI !== 'cli-server') { http_response_code(404); exit; }

$fichier = getenv('FAUX_COMPTES_ETAT');
$etat = json_decode((string)@file_get_contents($fichier), true) ?: [];

function rep(int $statut, $corps = null, string $type = 'application/json'): never
{
    http_response_code($statut);
    header("Content-Type: $type");
    echo is_string($corps) ? $corps : json_encode($corps, JSON_UNESCAPED_UNICODE);
    exit;
}

if (($_SERVER['HTTP_AUTHORIZATION'] ?? '') !== 'Bearer ' . getenv('FAUX_COMPTES_JETON')) {
    rep(401, ['code' => 'jeton']);
}

$chemin = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$corps = json_decode((string)file_get_contents('php://input'), true) ?: [];

if ($_SERVER['REQUEST_METHOD'] === 'POST' && $chemin === '/verifier') {
    $courriel = strtolower(trim((string)($corps['courriel'] ?? '')));
    $etat['dernier_ip'] = $corps['ip'] ?? null;
    file_put_contents($fichier, json_encode($etat));
    foreach ($etat['comptes'] as $c) {
        if ($c['courriel'] !== $courriel) continue;
        if (($c['etat'] ?? '') === 'bloque') rep(429, ['code' => 'bloque', 'jusqua' => gmdate('Y-m-d\TH:i:s\Z', time() + 120)]);
        if ($c['mdp'] !== ($corps['mot_de_passe'] ?? null)) break;
        if (($c['etat'] ?? '') === 'desactive') rep(403, ['code' => 'desactive']);
        if (($c['etat'] ?? '') === 'sans_acces') rep(403, ['code' => 'sans_acces']);
        rep(200, ['id' => $c['id'], 'nom' => $c['nom'], 'courriel' => $c['courriel'],
                  'doit_changer' => $c['doit_changer'], 'photo' => $c['photo']]);
    }
    rep(401, ['code' => 'identifiants']);
}

if ($_SERVER['REQUEST_METHOD'] === 'POST' && $chemin === '/changer') {
    foreach ($etat['comptes'] as $i => $c) {
        if ($c['id'] !== ($corps['id'] ?? null)) continue;
        if ($c['mdp'] !== ($corps['ancien'] ?? null)) rep(401, ['code' => 'identifiants']);
        $n = (string)($corps['nouveau'] ?? '');
        if (mb_strlen($n) < 10 || $n === $c['mdp']) rep(422, ['code' => 'faible']);
        $etat['comptes'][$i]['mdp'] = $n;
        $etat['comptes'][$i]['doit_changer'] = false;
        file_put_contents($fichier, json_encode($etat));
        rep(200, ['ok' => true]);
    }
    rep(404, ['code' => 'introuvable']);
}

if ($_SERVER['REQUEST_METHOD'] === 'GET' && preg_match('#^/personnes/([^/]+)/photo$#', $chemin, $m)) {
    foreach ($etat['comptes'] as $c) {
        if ($c['id'] === rawurldecode($m[1]) && $c['photo']) {
            $im = imagecreatetruecolor(256, 256);
            imagefill($im, 0, 0, imagecolorallocate($im, 61, 146, 190));
            ob_start();
            imagejpeg($im);
            rep(200, ob_get_clean(), 'image/jpeg');
        }
    }
    rep(404, ['code' => 'introuvable']);
}

rep(404, ['code' => 'route']);
