<?php
/**
 * Télécharger un album (ou un titre) Bandcamp sans yt-dlp.
 *
 * Depuis novembre 2026, Bandcamp sert un défi anti-robot à yt-dlp, même
 * quand il imite Chrome. Sa propre page d'album, lue sous l'identité de son
 * app (Bandcamp::AGENT), donne pourtant chaque titre et son MP3 — les mêmes
 * fichiers que yt-dlp récupérait. download-worker.php lance ce script à la
 * place de yt-dlp pour une adresse Bandcamp ; il écrit les mêmes lignes de
 * progression (« [download] Downloading item i of n »), les mêmes noms de
 * fichiers (« 01 - Titre.mp3 ») et les mêmes tags (titre, artiste, album,
 * artiste de l'album, piste, année, pochette intégrée). Pas de genre : celui
 * de Bandcamp est une liste de mots-clés de vente (voir download-worker.php).
 *
 *   php bandcamp-download.php <url> <dossier> <album> <artiste de l'album>
 *
 * Code de sortie : 0 tout est là, 1 rien, 2 une partie seulement.
 */
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
require_once __DIR__ . '/../src/AppConfig.php';
require_once __DIR__ . '/../src/Bandcamp.php';

[, $url, $dossier, $album, $artisteAlbum] = $argv + [null, '', '', '', ''];
if ($url === '' || $dossier === '') {
    fwrite(STDERR, "Usage : php bandcamp-download.php <url> <dossier> <album> <artiste>\n");
    exit(1);
}

$info = Bandcamp::albumTracks($url);
if ($info === null) {
    echo "ERROR: [Bandcamp] page illisible : $url\n";
    exit(1);
}
if (!$info['tracks']) {
    echo "ERROR: [Bandcamp] aucun titre écoutable sur cette page (réservé aux acheteurs ?)\n";
    exit(1);
}
if (!is_dir($dossier)) mkdir($dossier, 0755, true);

$album = $album !== '' ? $album : $info['album'];
$artisteAlbum = $artisteAlbum !== '' ? $artisteAlbum : $info['artist'];
$pochette = '';
if ($info['cover'] !== '') {
    $p = $dossier . '/.pochette-bandcamp.jpg';
    if (Bandcamp::saveTo($info['cover'], $p)) $pochette = $p;
}

$n = count($info['tracks']);
$faits = 0;
foreach ($info['tracks'] as $i => $t) {
    echo '[download] Downloading item ' . ($i + 1) . " of $n\n";
    $nom = sprintf('%02d - %s.mp3', $t['num'], str_replace(['/', "\0"], ['-', ''], $t['title']));
    $brut = $dossier . '/.brut-' . $i . '.mp3';
    if (!Bandcamp::saveTo($t['url'], $brut)) {
        echo "ERROR: [Bandcamp] « {$t['title']} » : téléchargement refusé\n";
        continue;
    }
    $args = ['ffmpeg', '-y', '-loglevel', 'error', '-i', $brut];
    if ($pochette !== '') array_push($args, '-i', $pochette, '-map', '0:a', '-map', '1:v',
        '-metadata:s:v', 'title=Album cover', '-metadata:s:v', 'comment=Cover (front)');
    array_push($args, '-c', 'copy', '-id3v2_version', '3', '-map_metadata', '-1',
        '-metadata', 'title=' . $t['title'],
        '-metadata', 'artist=' . $t['artist'],
        '-metadata', 'album=' . $album,
        '-metadata', 'album_artist=' . $artisteAlbum,
        '-metadata', 'track=' . $t['num'] . '/' . $n);
    if ($info['year'] !== '') array_push($args, '-metadata', 'date=' . $info['year']);
    $args[] = $dossier . '/' . $nom;
    $cmd = implode(' ', array_map('escapeshellarg', $args)) . ' 2>&1';
    exec($cmd, $sortie, $code);
    @unlink($brut);
    if ($code !== 0) {
        echo "ERROR: [Bandcamp] « {$t['title']} » : ffmpeg ($code) " . implode(' ', $sortie) . "\n";
        @unlink($dossier . '/' . $nom);
        continue;
    }
    echo "[ExtractAudio] Destination: $dossier/$nom\n";
    $faits++;
}
if ($pochette !== '') @unlink($pochette);
echo "[Bandcamp] $faits titre(s) sur $n\n";
exit($faits === $n ? 0 : ($faits === 0 ? 1 : 2));
