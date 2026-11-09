<?php
/**
 * Gullify — Le genre d'un artiste, demandé à plusieurs sources.
 *
 * Last.fm d'abord (quand le serveur a une clé, LASTFM_API_KEY) : ses
 * étiquettes sont votées par des millions d'auditeurs et connaissent bien la
 * scène d'ici, là où MusicBrainz ne connaît souvent pas l'artiste ou ne lui
 * met aucune étiquette. Puis, À DÉFAUT :
 *
 *   1. Last.fm — les étiquettes pesées (« folk », « rock », « quebec »…) ;
 *   2. MusicBrainz — les tags votés de la communauté, riches quand ils sont là ;
 *   3. Deezer — le genre de chaque album de l'artiste, compté (aucune clé) ;
 *   4. Apple Music (iTunes Search) — un genre principal par artiste (aucune clé).
 *
 * Les sources suivantes ne sont interrogées que tant que rien n'est sorti.
 *
 * Un artiste a jusqu'à trois genres (le principal en tête), et une ORIGINE à
 * part (Québec, France…, voir Origine.php) : tirée des mêmes étiquettes
 * Last.fm, ou de la région que MusicBrainz lui connaît.
 *
 * Comme dans MusicBrainz.php, rien ici ne DÉCIDE d'un genre : chaque source
 * rend des étiquettes pesées, et c'est GenreTaxonomy qui tranche.
 */

require_once __DIR__ . '/GenreTaxonomy.php';
require_once __DIR__ . '/MusicBrainz.php';
require_once __DIR__ . '/Origine.php';

class GenreLookup
{
    /**
     * Les genres Deezer, par identifiant. Les albums ne portent que le
     * numéro ; la liste, elle, ne bouge pas (relevée sur api.deezer.com/genre,
     * en français). Un identifiant inconnu est ignoré : pas d'étiquette vaut
     * mieux qu'une étiquette devinée.
     */
    private const DEEZER_GENRES = [
        132 => 'Pop',
        116 => 'Rap/Hip Hop',
        152 => 'Rock',
        113 => 'Dance',
        165 => 'R&B',
        85  => 'Alternative',
        106 => 'Electro',
        466 => 'Folk',
        144 => 'Reggae',
        129 => 'Jazz',
        84  => 'Country',
        98  => 'Classique',
        173 => 'Films/Jeux vidéo',
        464 => 'Metal',
        169 => 'Soul & Funk',
        153 => 'Blues',
        95  => 'Jeunesse',
        197 => 'Latino',
        2   => 'Musique africaine',
        459 => 'Musique allemande',
        16  => 'Musique asiatique',
        75  => 'Musique brésilienne',
        81  => 'Musique indienne',
        52  => 'Chanson française',
        128 => 'Rap français',
        133 => 'Pop indé/Folk',
        96  => 'Comptines/Chansons',
        97  => 'Histoires',
        457 => 'Livres audio',
    ];

    /** Étiquettes rapportées à l'app : de quoi montrer d'où vient la suggestion. */
    private const MAX_TAGS = 6;

    /** Genres retenus par artiste, principal compris. */
    public const MAX_GENRES = 3;

    /**
     * Le genre d'un artiste (et ses genres, son origine), la source qui l'a
     * donné, et les étiquettes qui y ont mené.
     *
     * @param int  $timeout  Secondes accordées à chaque appel réseau.
     * @param int  $attempts Essais par appel MusicBrainz (voir MusicBrainz::tags).
     * @param bool $origine  Chercher aussi l'origine chez MusicBrainz quand
     *   Last.fm n'en dit rien (un appel de plus, cadencé à 1 par seconde).
     * @return array{genre: string|null, genres: array<string>, tags: array<string>,
     *   source: string|null, origine: string|null, origine_source: string|null}
     */
    public static function suggest(string $artistName, int $timeout = 5, int $attempts = 2, bool $origine = true): array
    {
        $names = self::candidates($artistName);
        $seen  = [];
        $lastfmTags = null;

        $sources = [];
        if (self::lastfmKey() !== '') {
            $sources['lastfm'] = static function () use ($names, $timeout, &$lastfmTags): array {
                return $lastfmTags = self::firstOf($names, static fn(string $n): array => self::lastfmTags($n, $timeout));
            };
        }
        $sources['musicbrainz'] = static fn(): array => MusicBrainz::tags($artistName, $timeout, $attempts);
        $sources['deezer']      = static fn(): array => self::firstOf($names, static fn(string $n): array => self::deezerTags($n, $timeout));
        $sources['itunes']      = static fn(): array => self::firstOf($names, static fn(string $n): array => self::itunesTags($n, $timeout));

        $result = ['genre' => null, 'genres' => [], 'tags' => [], 'source' => null,
                   'origine' => null, 'origine_source' => null];

        foreach ($sources as $source => $fetch) {
            $tags = self::sorted($fetch());
            foreach ($tags as $tag) {
                $key = mb_strtolower($tag['name'], 'UTF-8');
                $seen[$key] ??= $tag['name'];
            }

            $genres = GenreTaxonomy::pickManyFromTags($tags, self::MAX_GENRES);
            if ($genres) {
                $result['genre']  = $genres[0];
                $result['genres'] = $genres;
                $result['source'] = $source;
                break;
            }
        }

        // L'origine : les étiquettes Last.fm d'abord (déjà lues), la région
        // MusicBrainz à défaut.
        if ($lastfmTags) {
            $result['origine'] = Origine::depuisTags($lastfmTags);
            if ($result['origine'] !== null) $result['origine_source'] = 'lastfm';
        }
        if ($result['origine'] === null && $origine) {
            $result['origine'] = MusicBrainz::origine($artistName, $timeout, $attempts);
            if ($result['origine'] !== null) $result['origine_source'] = 'musicbrainz';
        } elseif ($origine && in_array($result['origine'], [Origine::CANADA, Origine::FRANCE], true)) {
            // Deux étiquettes ambiguës : « canadian » se dit aussi des
            // artistes d'ici (Céline Dion), et « french » de qui chante en
            // français (Les Denis Drolet). MusicBrainz, qui connaît le pays et
            // la ville natale, tranche quand il sait.
            $precise = MusicBrainz::origine($artistName, $timeout, $attempts);
            $corrige = $result['origine'] === Origine::CANADA
                ? in_array($precise, [Origine::QUEBEC, Origine::ACADIE], true)
                : $precise !== null && $precise !== Origine::FRANCE;
            if ($corrige) {
                $result['origine'] = $precise;
                $result['origine_source'] = 'musicbrainz';
            }
        }

        // Rien de net nulle part : on rend quand même ce qu'on a lu, le
        // dialogue le montre pour que le choix reste éclairé.
        $result['tags'] = array_slice(array_values($seen), 0, self::MAX_TAGS);

        return $result;
    }

    /**
     * Ce que Last.fm sait d'un artiste : ses étiquettes les plus votées, le
     * compte ramené de 0 à 100 par Last.fm lui-même. `autocorrect` rattrape
     * les fautes courantes (« Cowboys Fringants » → « Les Cowboys Fringants »).
     *
     * @return array<array{name: string, count: int}>
     */
    public static function lastfmTags(string $artistName, int $timeout = 5): array
    {
        $key = self::lastfmKey();
        if ($key === '') return [];

        // Last.fm demande moins de cinq appels par seconde.
        static $dernier = 0.0;
        $attente = 0.22 - (microtime(true) - $dernier);
        if ($attente > 0) usleep((int)($attente * 1_000_000));
        $dernier = microtime(true);

        $data = self::json('https://ws.audioscrobbler.com/2.0/?' . http_build_query([
            'method'      => 'artist.gettoptags',
            'artist'      => $artistName,
            'api_key'     => $key,
            'format'      => 'json',
            'autocorrect' => 1,
        ]), $timeout);

        $tags = [];
        foreach ($data['toptags']['tag'] ?? [] as $t) {
            $name = trim((string)($t['name'] ?? ''));
            if ($name === '') continue;
            $tags[] = ['name' => $name, 'count' => (int)($t['count'] ?? 0)];
        }

        return $tags;
    }

    /** La clé Last.fm du serveur, ou '' (la source est alors sautée). */
    private static function lastfmKey(): string
    {
        if (!class_exists('AppConfig')) return '';

        return trim((string)AppConfig::get('lastfm.api_key'));
    }

    /**
     * Ce que Deezer sait d'un artiste : le genre de chacun de ses albums,
     * compté. Un artiste dont neuf albums sur dix sont rangés en « Rock » l'est
     * bien plus sûrement que par une étiquette isolée.
     *
     * @return array<array{name: string, count: int}>
     */
    public static function deezerTags(string $artistName, int $timeout = 5): array
    {
        $search = self::json('https://api.deezer.com/search/artist?' . http_build_query([
            'q'     => $artistName,
            'limit' => 5,
        ]), $timeout);

        $artistId = 0;
        foreach ($search['data'] ?? [] as $found) {
            if (MusicBrainz::sameArtist($artistName, (string)($found['name'] ?? ''))) {
                $artistId = (int)($found['id'] ?? 0);
                break;
            }
        }
        if ($artistId <= 0) return [];

        $albums = self::json("https://api.deezer.com/artist/{$artistId}/albums?limit=50", $timeout);

        $counts = [];
        foreach ($albums['data'] ?? [] as $album) {
            $name = self::DEEZER_GENRES[(int)($album['genre_id'] ?? 0)] ?? null;
            if ($name === null) continue;
            $counts[$name] = ($counts[$name] ?? 0) + 1;
        }

        $tags = [];
        foreach ($counts as $name => $count) {
            $tags[] = ['name' => $name, 'count' => $count];
        }

        return $tags;
    }

    /**
     * Ce qu'Apple Music sait d'un artiste : un seul genre, mais posé par le
     * catalogue plutôt que voté — et il connaît les artistes d'ici. Catalogue
     * canadien : « Les Cowboys Fringants » n'existe pas dans tous les pays.
     *
     * @return array<array{name: string, count: int}>
     */
    public static function itunesTags(string $artistName, int $timeout = 5): array
    {
        $data = self::json('https://itunes.apple.com/search?' . http_build_query([
            'term'    => $artistName,
            'entity'  => 'musicArtist',
            'limit'   => 5,
            'country' => 'CA',
        ]), $timeout);

        foreach ($data['results'] ?? [] as $found) {
            if (!MusicBrainz::sameArtist($artistName, (string)($found['artistName'] ?? ''))) continue;
            $genre = trim((string)($found['primaryGenreName'] ?? ''));
            if ($genre === '') continue;

            return [['name' => $genre, 'count' => 1]];
        }

        return [];
    }

    // ── Interne ─────────────────────────────────────────────────────────────

    /**
     * Les noms sous lesquels chercher un artiste : le sien, et le même sans le
     * titre du film ou de la compilation dont il traîne le nom
     * (« (50 First Dates) Bob Marley ») — tel quel, aucun catalogue ne le
     * trouve.
     *
     * @return array<string>
     */
    private static function candidates(string $artistName): array
    {
        $names    = [trim($artistName)];
        $stripped = trim((string)preg_replace('/^\s*\([^)]*\)\s*/', '', $artistName));
        if ($stripped !== '' && $stripped !== $names[0]) $names[] = $stripped;

        return array_filter($names, static fn(string $n): bool => $n !== '');
    }

    /**
     * Le premier essai qui rapporte quelque chose. Un nom qui ne donne rien ne
     * coûte qu'un appel de plus, et seulement quand il y a un second nom.
     *
     * @param array<string> $names
     * @return array<array{name: string, count: int}>
     */
    private static function firstOf(array $names, callable $fetch): array
    {
        foreach ($names as $name) {
            $tags = $fetch($name);
            if ($tags) return $tags;
        }

        return [];
    }

    /**
     * Les étiquettes les plus pesées d'abord : elles disent d'où vient la
     * suggestion, et aident à trancher quand la taxonomie ne trouve rien.
     *
     * @param array<array{name: string, count: int}> $tags
     * @return array<array{name: string, count: int}>
     */
    private static function sorted(array $tags): array
    {
        usort($tags, static fn(array $a, array $b): int => ($b['count'] ?? 0) <=> ($a['count'] ?? 0));

        return $tags;
    }

    /**
     * Un GET, JSON décodé ou null. Ni cadence ni reprise : ces catalogues n'en
     * demandent pas, et quelqu'un attend devant son téléphone.
     */
    private static function json(string $url, int $timeout): ?array
    {
        if (!function_exists('curl_init')) return null;

        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => $timeout,
            CURLOPT_USERAGENT      => 'Gullify/1.0 (self-hosted; https://github.com/gullify)',
            // Deezer traduit ses genres selon la langue demandée : sans ça, un
            // serveur hors Québec range en « Französische Chansons ».
            CURLOPT_HTTPHEADER     => ['Accept: application/json', 'Accept-Language: fr'],
            CURLOPT_FOLLOWLOCATION => true,
        ]);
        $body   = curl_exec($ch);
        $status = curl_getinfo($ch, CURLINFO_HTTP_CODE);

        if ($status !== 200 || !$body) return null;

        return json_decode((string)$body, true) ?: null;
    }
}
