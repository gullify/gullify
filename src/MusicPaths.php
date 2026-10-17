<?php
/**
 * Les chemins de musique, côté machine et côté conteneur.
 *
 * Dans Docker, la musique est montée : ce que le serveur lit sous « /music »
 * vit en réalité ailleurs sur la machine (MUSIC_HOST_PATH). On garde le chemin
 * interne pour lire les fichiers, et on montre — et on accepte — le vrai.
 */

require_once __DIR__ . '/AppConfig.php';

/**
 * Le dossier d'un compte qui lit TOUT le dossier de musique. Une bibliothèque
 * à un seul occupant n'a pas de sous-dossier à son nom : sa musique est à la
 * racine. Une chaîne vide, elle, veut dire « aucun dossier » — le compte ne
 * lit rien —, d'où ce point.
 */
const GULLIFY_RACINE = '.';

/**
 * Les dossiers proposables, en chemins relatifs à la racine, sur [$depth]
 * niveaux. Un dossier qui en contient d'autres reste proposable lui-même :
 * une bibliothèque peut être le parent comme l'enfant.
 *
 * Un seul niveau par défaut : en dessous, ce sont les artistes, et une liste
 * de mille entrées n'aide personne. On s'arrête de toute façon à [$max] —
 * passé ce nombre, c'est la saisie libre qui sert, pas le menu.
 *
 * @return string[] triés, sans les dossiers cachés
 */
function gullify_music_dirs(
    string $basePath,
    int $depth = 1,
    string $prefix = '',
    int $max = 300
): array {
    if ($depth <= 0 || !is_dir($basePath)) return [];
    $entries = @scandir($basePath);
    if ($entries === false) return [];

    $dirs = [];
    foreach ($entries as $entry) {
        if ($entry === '.' || $entry === '..') continue;
        if ($entry[0] === '.') continue; // dossiers cachés : ce n'est pas de la musique
        $full = $basePath . '/' . $entry;
        if (!is_dir($full)) continue;
        $relative = $prefix === '' ? $entry : $prefix . '/' . $entry;
        $dirs[] = $relative;
        foreach (gullify_music_dirs($full, $depth - 1, $relative, $max) as $child) {
            $dirs[] = $child;
        }
        if (count($dirs) >= $max) break;
    }
    sort($dirs, SORT_NATURAL | SORT_FLAG_CASE);
    return array_slice($dirs, 0, $max);
}

/**
 * Ramène au relatif ce qu'on a bien voulu saisir : un nom (« Maxime »), un
 * sous-dossier (« Maxime/Flac »), le chemin interne (« /music/Maxime ») ou le
 * vrai chemin de la machine (« /media/music/Maxime »). La racine elle-même —
 * « . », ou l'un des deux chemins complets — rend GULLIFY_RACINE : le compte
 * lit alors tout le dossier.
 *
 * Rend null quand le chemin sort du dossier de musique — là, c'est le montage
 * qu'il faut changer, pas le réglage d'un compte.
 */
function gullify_relative_music_dir(
    string $input,
    ?string $basePath = null,
    ?string $hostPath = null
): ?string {
    $base = rtrim($basePath ?? AppConfig::getMusicBasePath(), '/');
    $host = rtrim($hostPath ?? AppConfig::getMusicHostPath(), '/');

    $path = trim(str_replace('\\', '/', $input));
    while (strpos($path, '//') !== false) $path = str_replace('//', '/', $path);
    $path = rtrim($path, '/');
    if ($path === '') return null;
    if ($path === GULLIFY_RACINE) return GULLIFY_RACINE;

    // Le vrai chemin d'abord : c'est celui qu'on affiche, donc celui qu'on
    // recopie. Les deux racines peuvent être la même (hors Docker).
    foreach ([$host, $base] as $root) {
        if ($root === '' || $root === '/') continue;
        if ($path === $root) return GULLIFY_RACINE;   // tout le dossier
        if (strpos($path, $root . '/') === 0) {
            $path = substr($path, strlen($root) + 1);
            break;
        }
    }

    // Un chemin absolu qui n'est sous aucune des deux racines ne mène nulle
    // part dans le conteneur : mieux vaut le dire que de l'enregistrer.
    if ($path === '' || $path[0] === '/') return null;

    // Ni remontée, ni dossier courant : le réglage d'un compte ne doit pas
    // pouvoir pointer hors de la racine.
    foreach (explode('/', $path) as $part) {
        if ($part === '' || $part === '.' || $part === '..') return null;
    }
    return $path;
}

/**
 * Le chemin complet d'un dossier tel qu'on le montre : celui de la machine.
 */
function gullify_display_music_path(string $relative, ?string $hostPath = null): string {
    $host = rtrim($hostPath ?? AppConfig::getMusicHostPath(), '/');
    $relative = trim($relative, '/');
    return ($relative === '' || $relative === GULLIFY_RACINE) ? $host : $host . '/' . $relative;
}
