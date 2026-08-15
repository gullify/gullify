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
require_once __DIR__ . '/RemoteImage.php';

class ArtistImage
{
    /** Une semaine sans retenter un artiste que personne n'a. */
    private const MISS_TTL = 604800;

    /** Borne de temps (secondes) de la recherche YouTube Music. */
    private const YT_TIMEOUT = 12;

    /** Poids maximal d'une image acceptée (collée, téléversée ou trouvée). */
    public const MAX_BYTES = RemoteImage::MAX_BYTES;

    public static function cacheDir(): string
    {
        return AppConfig::getDataPath() . '/cache/artwork';
    }

    public static function cacheFile(int $artistId): string
    {
        return self::cacheDir() . '/artist_' . $artistId . '.jpg';
    }

    /** Ce que YouTube Music répond pour ce nom d'artiste (nom + vignette). */
    private static function ytMusicResults(string $name, int $limit = 5): array
    {
        $yt = RemoteImage::ytMusicScript();
        if ($yt === null) return [];
        [$python, $script] = $yt;
        $cmd = sprintf(
            'timeout %d %s %s artist %s %d 2>/dev/null',
            self::YT_TIMEOUT,
            $python,
            escapeshellarg($script),
            escapeshellarg($name),
            $limit
        );
        $out = @shell_exec($cmd);
        if (!$out) return [];
        $data = json_decode($out, true);
        return is_array($data['results'] ?? null) ? $data['results'] : [];
    }

    /** Ce que Deezer répond pour ce nom d'artiste. */
    private static function deezerResults(string $name, int $limit = 5): array
    {
        $url = 'https://api.deezer.com/search/artist?limit=' . $limit
             . '&q=' . urlencode($name);
        $bin = RemoteImage::get($url, RemoteImage::SEARCH_TIMEOUT);
        if ($bin === null) return [];
        $data = json_decode($bin, true);
        return is_array($data['data'] ?? null) ? $data['data'] : [];
    }

    /**
     * Image de l'artiste sur YouTube Music, en 1000 px si YouTube veut bien.
     */
    public static function ytMusicUrl(string $name): ?string
    {
        $best = self::bestMatch($name, self::ytMusicResults($name), 'name');
        $thumb = (string)($best['thumbnail'] ?? '');
        return $thumb === '' ? null : self::ytFullSize($thumb);
    }

    /** Image de l'artiste chez Deezer (picture_xl, 1000×1000). */
    public static function deezerUrl(string $name): ?string
    {
        $best = self::bestMatch($name, self::deezerResults($name), 'name');
        if (!$best) return null;
        return $best['picture_xl'] ?? $best['picture_big'] ?? null;
    }

    /**
     * Les artistes que YouTube Music et Deezer proposent sous ce nom, avec
     * leur photo (idée #78).
     *
     * Contrairement à [fetch], AUCUN filtrage sur le nom : c'est précisément
     * quand la reconnaissance automatique s'est trompée d'homonyme qu'on vient
     * choisir à la main, et le nom cherché n'est alors pas celui du dossier.
     * Chaque proposition porte donc le nom que le service lui donne, à lire
     * avant de choisir.
     *
     * @return array<int, array{name: string, thumbnail: string, source: string}>
     */
    public static function candidates(string $name, int $limit = 12): array
    {
        $name = trim($name);
        if ($name === '') return [];

        $out  = [];
        $seen = [];
        foreach (['ytmusic', 'deezer'] as $source) {
            $hits = $source === 'ytmusic'
                ? self::ytMusicResults($name, 8)
                : self::deezerResults($name, 8);
            foreach ($hits as $hit) {
                $label = trim((string)($hit['name'] ?? ''));
                $thumb = $source === 'ytmusic'
                    ? self::ytFullSize((string)($hit['thumbnail'] ?? ''))
                    : (string)($hit['picture_xl'] ?? $hit['picture_big'] ?? '');
                if ($label === '' || $thumb === '') continue;
                if (isset($seen[$thumb])) continue;
                $seen[$thumb] = true;
                $out[] = ['name' => $label, 'thumbnail' => $thumb, 'source' => $source];
                if (count($out) >= $limit) return $out;
            }
        }
        return $out;
    }

    /**
     * Les vignettes YouTube reviennent parfois en petit format : on force la
     * taille dans l'URL.
     */
    private static function ytFullSize(string $thumb): string
    {
        return RemoteImage::ytFullSize($thumb);
    }

    /**
     * Télécharge une image dont on a l'adresse (lien collé, ou proposition
     * choisie dans la liste). Renvoie les octets, ou null si l'adresse ne
     * donne rien d'exploitable.
     */
    public static function download(string $url): ?string
    {
        return RemoteImage::download($url);
    }

    /**
     * Range une image choisie à la main comme photo de l'artiste : elle prend
     * la place du fichier de cache, que `serve_image.php` sert avant tout le
     * reste — l'image du dossier comme celle du web passent après.
     *
     * Renvoie false si ce n'était pas une image.
     */
    public static function store(int $artistId, string $bin): bool
    {
        if (!RemoteImage::store(self::cacheFile($artistId), $bin)) return false;
        self::dropDerived($artistId);
        return true;
    }

    /**
     * Oublie la photo rangée pour cet artiste : la prochaine requête la
     * cherchera de nouveau (dossier de l'artiste, puis web).
     */
    public static function forget(int $artistId): void
    {
        @unlink(self::cacheFile($artistId));
        self::dropDerived($artistId);
    }

    /**
     * Efface ce qui découlait de l'ancienne image : les versions carrées
     * (Android Auto, notification) et le marqueur « personne n'a cet
     * artiste », qui n'a plus lieu d'être une fois qu'on en a une.
     */
    private static function dropDerived(int $artistId): void
    {
        @unlink(self::cacheFile($artistId) . '.miss');
        foreach (glob(self::cacheDir() . '/artist_' . $artistId . '_sq*.jpg') ?: [] as $sq) {
            @unlink($sq);
        }
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
            $bin = RemoteImage::get($url, RemoteImage::DOWNLOAD_TIMEOUT);
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
}
