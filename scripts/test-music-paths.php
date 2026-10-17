<?php
/**
 * Vérifie les chemins de musique (src/MusicPaths.php).
 *
 * Deux racines cohabitent : celle du conteneur (« /music ») et la vraie,
 * celle de la machine (« /media/musique »). On affiche la seconde, donc on
 * doit aussi savoir la relire — et refuser ce qui sort du dossier monté.
 *
 *   php scripts/test-music-paths.php
 */

require_once __DIR__ . '/../src/MusicPaths.php';

$failures = 0;
$checks   = 0;

function check(string $label, mixed $got, mixed $want): void
{
    global $failures, $checks;
    $checks++;
    if ($got === $want) return;
    $failures++;
    printf(
        "  ✗ %s\n      attendu : %s\n      obtenu  : %s\n",
        $label,
        var_export($want, true),
        var_export($got, true)
    );
}

const BASE = '/music';
const HOST = '/media/musique';

function rel(string $input): ?string
{
    return gullify_relative_music_dir($input, BASE, HOST);
}

echo "── Ce qu'on accepte ─────────────────────────────────────────\n";
check('un nom de dossier', rel('Maxime'), 'Maxime');
check('un sous-dossier', rel('Maxime/Flac'), 'Maxime/Flac');
check('le vrai chemin de la machine', rel('/media/musique/Maxime'), 'Maxime');
check('le vrai chemin, en profondeur',
    rel('/media/musique/Maxime/Flac'), 'Maxime/Flac');
check('le chemin du conteneur', rel('/music/Maxime'), 'Maxime');
check('une barre oblique de trop', rel('/media/musique//Maxime/'), 'Maxime');
check('des espaces autour', rel('  Maxime  '), 'Maxime');
check('un nom avec espace', rel('Vieux disques'), 'Vieux disques');
check('« . » : tout le dossier', rel('.'), '.');
check('la racine de la machine : tout le dossier', rel('/media/musique'), '.');
check('la racine de la machine, barre finale', rel('/media/musique/'), '.');
check('la racine du conteneur : tout le dossier', rel('/music'), '.');

echo "── Ce qu'on refuse ──────────────────────────────────────────\n";
check('un chemin hors du dossier monté', rel('/home/maxime/Musique'), null);
check('un point déguisé', rel('./Maxime'), null);
check('une remontée', rel('../etc'), null);
check('une remontée déguisée', rel('Maxime/../../etc'), null);
check('le vide', rel('   '), null);
check('la racine absolue', rel('/'), null);

echo "── Hors Docker, les deux racines sont la même ────────────────\n";
check('chemin complet sans montage',
    gullify_relative_music_dir('/srv/musique/Jeanne', '/srv/musique', '/srv/musique'),
    'Jeanne');

echo "── Ce qu'on affiche ─────────────────────────────────────────\n";
check('le chemin montré est celui de la machine',
    gullify_display_music_path('Maxime', HOST), '/media/musique/Maxime');
check('sans dossier, c\'est la racine',
    gullify_display_music_path('', HOST), '/media/musique');
check('« . » se montre comme la racine',
    gullify_display_music_path('.', HOST), '/media/musique');

echo "── Les dossiers proposés ────────────────────────────────────\n";
$tmp = sys_get_temp_dir() . '/gullify-chemins-' . getmypid();
@mkdir($tmp . '/Maxime/Flac', 0777, true);
@mkdir($tmp . '/Maxime/MP3', 0777, true);
@mkdir($tmp . '/Jeanne', 0777, true);
@mkdir($tmp . '/.cache', 0777, true);
touch($tmp . '/une-chanson.mp3');

check('un seul niveau par défaut, dossiers cachés exclus',
    gullify_music_dirs($tmp), ['Jeanne', 'Maxime']);
check('deux niveaux sur demande',
    gullify_music_dirs($tmp, 2),
    ['Jeanne', 'Maxime', 'Maxime/Flac', 'Maxime/MP3']);
check('la liste est plafonnée',
    gullify_music_dirs($tmp, 2, '', 2), ['Jeanne', 'Maxime']);
check('un dossier introuvable ne casse rien',
    gullify_music_dirs($tmp . '/nulle-part', 2), []);

array_map('rmdir', [
    $tmp . '/Maxime/Flac', $tmp . '/Maxime/MP3', $tmp . '/Maxime',
    $tmp . '/Jeanne', $tmp . '/.cache',
]);
@unlink($tmp . '/une-chanson.mp3');
@rmdir($tmp);

echo "\n";
if ($failures === 0) {
    echo "✓ {$checks} vérifications, aucune erreur.\n";
    exit(0);
}
echo "✗ {$failures} erreur(s) sur {$checks} vérifications.\n";
exit(1);
