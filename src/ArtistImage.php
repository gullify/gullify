<?php
/**
 * Gullify — image d'artiste récupérée sur le web (idée #67)
 *
 * Un artiste qui vient d'entrer dans la bibliothèque n'a aucune image : ni
 * fichier dans son dossier, ni blob en base. `serve_image.php` servait alors
 * le logo Gullify, et la page de l'artiste restait sur ce logo tant que
 * personne n'avait lancé le grand rattrapage (batch_fetch_artist_images.php).
 * Ce fichier fait le même travail, mais pour UN artiste, au moment où on
 * ouvre sa page.
 *
 * Deux sources, dans cet ordre : YouTube Music (via python/ytmusic_search.py,
 * nettement meilleur sur le catalogue québécois et francophone) puis Deezer
 * (`picture_xl`, 1000×1000, gratuit et sans clé).
 *
 * Trois garde-fous, parce que la recherche coûte un processus python et des
 * appels réseau alors que serve_image.php répond sans session :
 *   - un artiste sans résultat est marqué (fichier `.miss`) et n'est pas
 *     retenté avant une semaine ;
 *   - un verrou global n'autorise qu'une recherche à la fois sur le serveur,
 *     les autres requêtes retombent immédiatement sur le placeholder ;
 *   - chaque appel externe est borné dans le temps (au total ~28 s au pire).
 */

require_once __DIR__ . '/AppConfig.php';

class ArtistImage
{
    /** Une semaine sans retenter un artiste que personne n'a. */
    private const MISS_TTL = 604800;

    /** Bornes de temps (secondes) des appels externes. */
    private const YT_TIMEOUT       = 12;
    private const SEARCH_TIMEOUT   = 6;
    private const DOWNLOAD_TIMEOUT = 10;

    public static function cacheDir(): string
    {
        return AppConfig::getDataPath() . '/cache/artwork';
    }

    public static function cacheFile(int $artistId): string
    {
        return self::cacheDir() . '/artist_' . $artistId . '.jpg';
    }

    /**
     * Image de l'artiste sur YouTube Music, en 1000 px si YouTube veut bien.
     */
    public static function ytMusicUrl(string $name): ?string
    {
        $script = AppConfig::getPythonPath() . '/ytmusic_search.py';
        if (!file_exists($script)) return null;
        $python = is_executable('/opt/ytdlp/bin/python3') ? '/opt/ytdlp/bin/python3' : 'python3';
        $cmd = sprintf(
            'timeout %d %s %s artist %s 2>/dev/null',
            self::YT_TIMEOUT,
            $python,
            escapeshellarg($script),
            escapeshellarg($name)
        );
        $out = @shell_exec($cmd);
        if (!$out) return null;
        $data = json_decode($out, true);
        $best = self::bestMatch($name, $data['results'] ?? [], 'name');
        $thumb = $best['thumbnail'] ?? '';
        if (!$thumb) return null;
        // Les vignettes YouTube reviennent parfois en petit format : on force
        // la taille dans l'URL.
        return preg_replace('/=w\d+-h\d+/', '=w1000-h1000', $thumb);
    }

    /** Image de l'artiste chez Deezer (picture_xl, 1000×1000). */
    public static function deezerUrl(string $name): ?string
    {
        $url = 'https://api.deezer.com/search/artist?limit=5&q=' . urlencode($name);
        $bin = self::curl($url, self::SEARCH_TIMEOUT);
        if ($bin === null) return null;
        $data = json_decode($bin, true);
        $best = self::bestMatch($name, $data['data'] ?? [], 'name');
        if (!$best) return null;
        return $best['picture_xl'] ?? $best['picture_big'] ?? null;
    }

    /**
     * Cherche puis télécharge. Renvoie ['data' => octets, 'source' => nom de
     * la source], ou null si personne n'a cet artiste.
     */
    /**
     * Noms fourre-tout des fichiers mal taggés : ce ne sont pas des artistes,
     * et YouTube comme Deezer ont pourtant quelqu'un à ce nom-là.
     */
    private const PLACEHOLDERS = [
        'unknown artist', 'unknown', 'various artists', 'various',
        'artiste inconnu', 'inconnu', 'va', 'compilation', 'compilations',
    ];

    public static function fetch(string $name): ?array
    {
        $name = trim($name);
        if ($name === '') return null;
        if (in_array(self::normalize($name), self::PLACEHOLDERS, true)) return null;

        // YouTube Music d'abord, Deezer en repli — et Deezer n'est interrogé
        // que si YouTube n'a rien donné.
        foreach (['ytmusic', 'deezer'] as $source) {
            $url = $source === 'ytmusic'
                ? self::ytMusicUrl($name)
                : self::deezerUrl($name);
            if (!$url) continue;
            $bin = self::curl($url, self::DOWNLOAD_TIMEOUT);
            if ($bin !== null && strlen($bin) > 200) {
                return ['data' => $bin, 'source' => $source];
            }
        }
        return null;
    }

    /**
     * Dernier recours de `serve_image.php` : va chercher l'image de l'artiste
     * et la met en cache. Renvoie les octets servis, ou null.
     *
     * Ne fait RIEN si une autre requête cherche déjà (verrou global) ou si cet
     * artiste a été cherché en vain récemment.
     */
    public static function ensure(int $artistId, string $name): ?string
    {
        $file = self::cacheFile($artistId);
        if (is_file($file)) {
            $bin = @file_get_contents($file);
            return $bin === false ? null : $bin;
        }

        $miss = $file . '.miss';
        if (is_file($miss) && (time() - (int)@filemtime($miss)) < self::MISS_TTL) {
            return null;
        }

        $lock = @fopen(sys_get_temp_dir() . '/gullify-artist-image.lock', 'c');
        if (!$lock) return null;
        if (!flock($lock, LOCK_EX | LOCK_NB)) {
            // Une recherche est déjà en cours : cette requête-ci ne fait pas
            // patienter le client pour rien.
            fclose($lock);
            return null;
        }

        try {
            $hit = self::fetch($name);
            if (!$hit) {
                @touch($miss);
                return null;
            }
            $dir = dirname($file);
            if (!is_dir($dir)) @mkdir($dir, 0775, true);
            if (@file_put_contents($file, $hit['data']) === false) return null;
            @chmod($file, 0644);
            @unlink($miss);
            return $hit['data'];
        } catch (\Throwable $e) {
            return null;
        } finally {
            flock($lock, LOCK_UN);
            fclose($lock);
        }
    }

    /**
     * Le résultat qui porte VRAIMENT ce nom, ou rien.
     *
     * YouTube et Deezer répondent toujours quelque chose, même à une requête
     * qui ne correspond à personne : se rabattre sur le premier résultat, c'est
     * coller le visage d'un autre sur la page d'un artiste. Mieux vaut pas
     * d'image du tout. La comparaison se fait sur un nom réduit ([normalize]),
     * pour ne pas rater « Eric Lapointe » contre « Éric Lapointe ».
     */
    private static function bestMatch(string $name, array $hits, string $field): ?array
    {
        $want = self::normalize($name);
        if ($want === '' || !$hits) return null;
        foreach ($hits as $hit) {
            if (self::normalize((string)($hit[$field] ?? '')) === $want) {
                return $hit;
            }
        }
        return null;
    }

    /**
     * Nom réduit à sa forme comparable : minuscules, sans accents, sans
     * ponctuation, sans article de tête (« The Doors » = « Doors »).
     */
    private static function normalize(string $s): string
    {
        $s = mb_strtolower(trim($s), 'UTF-8');
        $ascii = @iconv('UTF-8', 'ASCII//TRANSLIT', $s);
        if (is_string($ascii) && $ascii !== '') $s = strtolower($ascii);
        $s = preg_replace('/[^a-z0-9]+/', ' ', $s);
        $s = trim(preg_replace('/\s+/', ' ', $s));
        return preg_replace('/^(the|les|le|la|l) /', '', $s);
    }

    /** GET borné dans le temps. Renvoie le corps, ou null hors 200. */
    private static function curl(string $url, int $timeout): ?string
    {
        if (!function_exists('curl_init')) return null;
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => $timeout,
            CURLOPT_CONNECTTIMEOUT => 5,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_USERAGENT      => 'Gullify/1.0 (self-hosted music player)',
        ]);
        $body = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        return ($code === 200 && is_string($body) && $body !== '') ? $body : null;
    }
}
