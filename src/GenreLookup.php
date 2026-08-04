<?php
/**
 * Gullify — Le genre d'un artiste, demandé à plusieurs sources.
 *
 * MusicBrainz est la source de référence, mais elle ne connaît qu'une partie
 * du monde : sur une bibliothèque d'ici, l'artiste n'y figure souvent pas, ou
 * n'y porte aucune étiquette — et le rangement à la main restait sans
 * suggestion une fois sur deux (idée #54). On demande donc, À DÉFAUT, à deux
 * catalogues qui connaissent bien la musique québécoise :
 *
 *   1. MusicBrainz — les tags votés de la communauté, riches quand ils sont là ;
 *   2. Deezer — le genre de chaque album de l'artiste, compté (aucune clé) ;
 *   3. Apple Music (iTunes Search) — un genre principal par artiste (aucune clé).
 *
 * Les sources suivantes ne sont interrogées que tant que rien n'est sorti : un
 * artiste bien connu de MusicBrainz ne coûte pas un aller-retour de plus
 * qu'avant, et l'ordre garde à MusicBrainz le dernier mot quand il en a un.
 *
 * Comme dans MusicBrainz.php, rien ici ne DÉCIDE d'un genre : chaque source
 * rend des étiquettes pesées, et c'est GenreTaxonomy qui tranche.
 */

require_once __DIR__ . '/GenreTaxonomy.php';
require_once __DIR__ . '/MusicBrainz.php';

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

    /**
     * Le genre d'un artiste, la source qui l'a donné, et les étiquettes qui y
     * ont mené.
     *
     * @param int $timeout  Secondes accordées à chaque appel réseau.
     * @param int $attempts Essais par appel MusicBrainz (voir MusicBrainz::tags).
     * @return array{genre: string|null, tags: array<string>, source: string|null}
     */
    public static function suggest(string $artistName, int $timeout = 5, int $attempts = 2): array
    {
        $names = self::candidates($artistName);
        $seen  = [];

        $sources = [
            'musicbrainz' => static fn(): array => MusicBrainz::tags($artistName, $timeout, $attempts),
            'deezer'      => static fn(): array => self::firstOf($names, static fn(string $n): array => self::deezerTags($n, $timeout)),
            'itunes'      => static fn(): array => self::firstOf($names, static fn(string $n): array => self::itunesTags($n, $timeout)),
        ];

        foreach ($sources as $source => $fetch) {
            $tags = self::sorted($fetch());
            foreach ($tags as $tag) {
                $key = mb_strtolower($tag['name'], 'UTF-8');
                $seen[$key] ??= $tag['name'];
            }

            $genre = GenreTaxonomy::pickFromTags($tags);
            if ($genre !== null) {
                return [
                    'genre'  => $genre,
                    'tags'   => array_slice(array_values($seen), 0, self::MAX_TAGS),
                    'source' => $source,
                ];
            }
        }

        // Rien de net nulle part : on rend quand même ce qu'on a lu, le
        // dialogue le montre pour que le choix reste éclairé.
        return [
            'genre'  => null,
            'tags'   => array_slice(array_values($seen), 0, self::MAX_TAGS),
            'source' => null,
        ];
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
        curl_close($ch);

        if ($status !== 200 || !$body) return null;

        return json_decode((string)$body, true) ?: null;
    }
}
