<?php
/**
 * Gullify — jaquette d'album choisie à la main (idée #93)
 *
 * `serve_image.php` sert la jaquette qu'il trouve : fichier de cache, blob en
 * base, `folder.jpg` du dossier, pochette embarquée dans les tags. Quand la
 * source est laide, minuscule ou tout simplement fausse (album mal taggé,
 * pochette d'une réédition, téléchargement dont la miniature est un visage
 * YouTube), il n'y avait aucun moyen d'imposer la bonne — sinon éditer les
 * fichiers sur le disque. C'est ce que ce fichier répare : on choisit une
 * jaquette parmi les propositions de YouTube Music et de Deezer, un lien
 * collé, ou une image du téléphone, et elle est rangée dans le CACHE, que
 * `serve_image.php` regarde en tout premier. Le choix tient donc jusqu'à ce
 * qu'on le défasse ([forget]), sans jamais toucher aux fichiers de musique.
 *
 * Même esprit que [ArtistImage] pour les photos d'artiste (idée #78), avec
 * qui il partage sa plomberie ([RemoteImage]) : la recherche ne filtre RIEN
 * sur le nom, parce que c'est justement quand la reconnaissance automatique
 * se trompe qu'on vient choisir soi-même.
 */

require_once __DIR__ . '/AppConfig.php';
require_once __DIR__ . '/RemoteImage.php';

class AlbumCover
{
    /** Borne de temps (secondes) de la recherche YouTube Music. */
    private const YT_TIMEOUT = 12;

    /** Poids maximal d'une image acceptée (collée, téléversée ou trouvée). */
    public const MAX_BYTES = RemoteImage::MAX_BYTES;

    public static function cacheDir(): string
    {
        return AppConfig::getDataPath() . '/cache/artwork';
    }

    public static function cacheFile(int $albumId): string
    {
        return self::cacheDir() . '/album_' . $albumId . '.jpg';
    }

    /**
     * Les jaquettes que YouTube Music et Deezer proposent pour cette
     * recherche (« artiste titre », ou ce que l'on tape soi-même).
     *
     * Chaque proposition porte le titre ET l'artiste que le service lui
     * donne : deux albums du même nom ne se distinguent qu'à ça, et une
     * compilation qui a avalé le titre cherché se repère de la même façon.
     *
     * @return array<int, array{title: string, artist: string, thumbnail: string, source: string}>
     */
    public static function candidates(string $query, int $limit = 12): array
    {
        $query = trim($query);
        if ($query === '') return [];

        $out  = [];
        $seen = [];
        foreach (['ytmusic', 'deezer'] as $source) {
            $hits = $source === 'ytmusic'
                ? self::ytMusicResults($query, 8)
                : self::deezerResults($query, 8);
            foreach ($hits as $hit) {
                $title  = trim((string)($hit['title'] ?? ''));
                $artist = $source === 'ytmusic'
                    ? trim((string)($hit['artist'] ?? ''))
                    : trim((string)($hit['artist']['name'] ?? ''));
                $thumb = $source === 'ytmusic'
                    ? RemoteImage::ytFullSize((string)($hit['thumbnail'] ?? ''))
                    : (string)($hit['cover_xl'] ?? $hit['cover_big'] ?? '');
                if ($title === '' || $thumb === '') continue;
                if (isset($seen[$thumb])) continue;
                $seen[$thumb] = true;
                $out[] = [
                    'title'     => $title,
                    'artist'    => $artist,
                    'thumbnail' => $thumb,
                    'source'    => $source,
                ];
                if (count($out) >= $limit) return $out;
            }
        }
        return $out;
    }

    /** Ce que YouTube Music répond pour cette recherche d'album. */
    private static function ytMusicResults(string $query, int $limit = 8): array
    {
        $yt = RemoteImage::ytMusicScript();
        if ($yt === null) return [];
        [$python, $script] = $yt;
        $cmd = sprintf(
            'timeout %d %s %s album %s %d 2>/dev/null',
            self::YT_TIMEOUT,
            $python,
            escapeshellarg($script),
            escapeshellarg($query),
            $limit
        );
        $out = @shell_exec($cmd);
        if (!$out) return [];
        $data = json_decode($out, true);
        return is_array($data['results'] ?? null) ? $data['results'] : [];
    }

    /** Ce que Deezer répond pour cette recherche d'album. */
    private static function deezerResults(string $query, int $limit = 8): array
    {
        $url = 'https://api.deezer.com/search/album?limit=' . $limit
             . '&q=' . urlencode($query);
        $bin = RemoteImage::get($url, RemoteImage::SEARCH_TIMEOUT);
        if ($bin === null) return [];
        $data = json_decode($bin, true);
        return is_array($data['data'] ?? null) ? $data['data'] : [];
    }

    /**
     * Télécharge une image dont on a l'adresse (lien collé, ou proposition
     * choisie dans la liste).
     */
    public static function download(string $url): ?string
    {
        return RemoteImage::download($url);
    }

    /**
     * Range une jaquette choisie à la main : elle prend la place du fichier
     * de cache, servi avant le dossier et avant les tags.
     *
     * Renvoie false si ce n'était pas une image.
     */
    public static function store(int $albumId, string $bin): bool
    {
        if (!RemoteImage::store(self::cacheFile($albumId), $bin)) return false;
        self::dropDerived($albumId);
        return true;
    }

    /**
     * Oublie la jaquette rangée pour cet album : le `folder.jpg` du dossier,
     * ou la pochette des tags, reprend la main à la prochaine requête.
     */
    public static function forget(int $albumId): void
    {
        @unlink(self::cacheFile($albumId));
        self::dropDerived($albumId);
    }

    /**
     * Efface ce qui découlait de l'ancienne jaquette : les versions carrées
     * servies à Android Auto et à la notification système, qui montreraient
     * sinon la pochette d'avant.
     */
    private static function dropDerived(int $albumId): void
    {
        foreach (glob(self::cacheDir() . '/album_' . $albumId . '_sq*.jpg') ?: [] as $sq) {
            @unlink($sq);
        }
    }
}
