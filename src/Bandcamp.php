<?php
/**
 * Gullify — Bandcamp, deuxième source de téléchargement à côté de YouTube
 * Music (idée #110).
 *
 * Bandcamp n'a pas d'API publique documentée, mais deux points d'entrée que
 * son propre site et son application mobile utilisent, et qui répondent sans
 * clé ni session :
 *
 *   - `autocomplete_elastic` : la recherche du site (albums `a`, artistes
 *     `b`, titres `t`) ;
 *   - `mobile/24/band_details` et `mobile/24/tralbum_details` : la
 *     discographie d'un artiste et le détail d'un album ou d'un titre.
 *
 * On ne télécharge rien ici : les URLs rendues (`https://<artiste>.bandcamp.com/album/…`)
 * partent dans la même file que YouTube, yt-dlp sachant lire Bandcamp.
 *
 * Toutes les méthodes rendent des structures vides plutôt que de lever : une
 * recherche qui échoue doit laisser l'autre source répondre, pas casser
 * l'écran.
 */

class Bandcamp
{
    private const SEARCH_URL = 'https://bandcamp.com/api/bcsearch_public_api/1/autocomplete_elastic';
    private const MOBILE_API = 'https://bandcamp.com/api/mobile/24/';

    /** Pochettes : `a<art_id>_<taille>.jpg`, 2 = 350 px (assez pour l'app). */
    private const ART_SIZE = '_2';

    /** Vrai si [$url] est un lien Bandcamp (domaine officiel ou sous-domaine d'artiste). */
    public static function isUrl(string $url): bool
    {
        $host = strtolower((string) parse_url(trim($url), PHP_URL_HOST));
        return $host === 'bandcamp.com' || str_ends_with($host, '.bandcamp.com');
    }

    /**
     * Albums trouvés pour [$query].
     *
     * @return array<array{title:string,artist:string,year:string,thumbnail:string,url:string,itemId:int,bandId:int,itemType:string}>
     */
    public static function searchAlbums(string $query, int $limit = 10): array
    {
        $albums = [];
        foreach (self::search($query, 'a', $limit) as $r) {
            $albums[] = [
                'title'     => (string) ($r['name'] ?? ''),
                'artist'    => (string) ($r['band_name'] ?? ''),
                'year'      => '',            // absent de la recherche, résolu au tap
                'thumbnail' => self::artwork($r['art_id'] ?? null, $r['img'] ?? ''),
                'url'       => (string) ($r['item_url_path'] ?? ''),
                'itemId'    => (int) ($r['id'] ?? 0),
                'bandId'    => (int) ($r['band_id'] ?? 0),
                'itemType'  => 'a',
            ];
        }
        return array_values(array_filter($albums, fn($a) => $a['title'] !== '' && $a['url'] !== ''));
    }

    /**
     * Artistes (et labels) trouvés pour [$query].
     *
     * @return array<array{name:string,bandId:int,thumbnail:string,location:string,isLabel:bool}>
     */
    public static function searchArtists(string $query, int $limit = 10): array
    {
        $artists = [];
        foreach (self::search($query, 'b', $limit) as $r) {
            $artists[] = [
                'name'      => (string) ($r['name'] ?? ''),
                'bandId'    => (int) ($r['id'] ?? 0),
                // Photo d'artiste : espace de noms différent des pochettes,
                // on garde l'URL telle que Bandcamp la donne.
                'thumbnail' => (string) ($r['img'] ?? ''),
                'location'  => (string) ($r['location'] ?? ''),
                'isLabel'   => !empty($r['is_label']),
            ];
        }
        return array_values(array_filter($artists, fn($a) => $a['name'] !== '' && $a['bandId'] > 0));
    }

    /**
     * Titres seuls trouvés pour [$query].
     *
     * @return array<array{title:string,artist:string,album:string,thumbnail:string,url:string,itemId:int,bandId:int,itemType:string}>
     */
    public static function searchSongs(string $query, int $limit = 10): array
    {
        $songs = [];
        foreach (self::search($query, 't', $limit) as $r) {
            $songs[] = [
                'title'     => (string) ($r['name'] ?? ''),
                'artist'    => (string) ($r['band_name'] ?? ''),
                'album'     => (string) ($r['album_name'] ?? ''),
                'thumbnail' => self::artwork($r['art_id'] ?? null, $r['img'] ?? ''),
                'url'       => (string) ($r['item_url_path'] ?? ''),
                'itemId'    => (int) ($r['id'] ?? 0),
                'bandId'    => (int) ($r['band_id'] ?? 0),
                'itemType'  => 't',
            ];
        }
        return array_values(array_filter($songs, fn($s) => $s['title'] !== '' && $s['url'] !== ''));
    }

    /**
     * Discographie d'un artiste : ses albums et ses titres isolés, du plus
     * récent au plus ancien.
     *
     * Bandcamp ne donne pas l'URL des sorties dans cette réponse : l'app
     * renvoie `bandId` + `itemId` + `itemType` à [resolve] au moment du tap,
     * qui va chercher l'URL (et le nombre de pistes) au coup par coup.
     *
     * @return array<array{title:string,artist:string,year:string,thumbnail:string,url:string,itemId:int,bandId:int,itemType:string}>
     */
    public static function artistAlbums(int $bandId, int $limit = 50): array
    {
        if ($bandId <= 0) return [];
        $data = self::get(self::MOBILE_API . 'band_details?band_id=' . $bandId);
        if (!is_array($data) || empty($data['discography'])) return [];

        $bandName = (string) ($data['name'] ?? '');
        $albums = [];
        foreach ($data['discography'] as $item) {
            if (!is_array($item)) continue;
            $type = ($item['item_type'] ?? 'album') === 'track' ? 't' : 'a';
            $albums[] = [
                'title'     => (string) ($item['title'] ?? ''),
                'artist'    => (string) ($item['artist_name'] ?: ($item['band_name'] ?? $bandName)),
                'year'      => self::yearOf($item['release_date'] ?? null),
                'thumbnail' => self::artwork($item['art_id'] ?? null, ''),
                'url'       => '',
                'itemId'    => (int) ($item['item_id'] ?? 0),
                'bandId'    => (int) ($item['band_id'] ?? $bandId),
                'itemType'  => $type,
            ];
        }
        $albums = array_values(array_filter($albums, fn($a) => $a['title'] !== '' && $a['itemId'] > 0));
        return array_slice($albums, 0, max(1, $limit));
    }

    /**
     * Métadonnées d'un album ou d'un titre, prêtes pour la fenêtre de
     * confirmation et pour la file de téléchargement.
     *
     * Deux entrées possibles : les identifiants rendus par la recherche
     * (`bandId` + `itemId` + `itemType`, la voie normale), ou une URL seule —
     * un lien collé, qu'il faut alors lire sur la page elle-même.
     *
     * @return array{url:string,artist:string,title:string,album:string,year:string,track_count:int,thumbnail:string,is_track:bool}|null
     */
    public static function resolve(int $bandId, int $itemId, string $itemType = 'a'): ?array
    {
        if ($bandId <= 0 || $itemId <= 0) return null;
        $type = $itemType === 't' ? 't' : 'a';
        $data = self::get(self::MOBILE_API . 'tralbum_details?' . http_build_query([
            'band_id'      => $bandId,
            'tralbum_id'   => $itemId,
            'tralbum_type' => $type,
        ]));
        if (!is_array($data) || empty($data['bandcamp_url'])) return null;

        $tracks  = is_array($data['tracks'] ?? null) ? $data['tracks'] : [];
        $isTrack = $type === 't';
        $artist  = (string) ($data['tralbum_artist'] ?? '');
        if ($artist === '' && isset($data['band']['name'])) {
            $artist = (string) $data['band']['name'];
        }

        return [
            'url'         => (string) $data['bandcamp_url'],
            'artist'      => $artist,
            'title'       => (string) ($data['title'] ?? ''),
            // Un titre isolé n'a pas toujours d'album : l'appelant range
            // alors dans « Singles », comme pour YouTube.
            'album'       => $isTrack ? (string) ($data['album_title'] ?? '') : (string) ($data['title'] ?? ''),
            'year'        => self::yearOf($data['release_date'] ?? null),
            'track_count' => $isTrack ? 1 : count($tracks),
            'thumbnail'   => self::artwork($data['art_id'] ?? null, ''),
            'is_track'    => $isTrack,
        ];
    }

    /**
     * Idem à partir d'une URL seule (lien collé) : la page d'un album ou d'un
     * titre porte son propre descriptif JSON dans l'attribut `data-tralbum`.
     *
     * @return array{url:string,artist:string,title:string,album:string,year:string,track_count:int,thumbnail:string,is_track:bool}|null
     */
    public static function resolveUrl(string $url): ?array
    {
        $url = trim($url);
        if (!self::isUrl($url)) return null;

        $html = self::fetch($url, ['Accept: text/html']);
        if ($html === null) return null;

        if (!preg_match('/data-tralbum="([^"]*)"/', $html, $m)) return null;
        $tralbum = json_decode(html_entity_decode($m[1], ENT_QUOTES, 'UTF-8'), true);
        if (!is_array($tralbum)) return null;

        $current = is_array($tralbum['current'] ?? null) ? $tralbum['current'] : [];
        $tracks  = is_array($tralbum['trackinfo'] ?? null) ? $tralbum['trackinfo'] : [];
        $isTrack = ($current['type'] ?? '') === 'track';

        $title = (string) ($current['title'] ?? '');
        if ($title === '') return null;

        return [
            'url'         => (string) ($tralbum['url'] ?? $url),
            'artist'      => (string) ($current['artist'] ?? ($tralbum['artist'] ?? '')),
            'title'       => $title,
            // La page d'un titre ne nomme pas son album (elle n'en donne que
            // le lien) : l'appelant rangera dans « Singles », comme YouTube.
            'album'       => $isTrack ? '' : $title,
            // Un titre porte la date de son album, pas la sienne.
            'year'        => self::yearOf(
                $current['release_date'] ?? ($tralbum['album_release_date'] ?? ($current['publish_date'] ?? null))
            ),
            'track_count' => $isTrack ? 1 : count($tracks),
            'thumbnail'   => self::artwork($tralbum['art_id'] ?? ($current['art_id'] ?? null), ''),
            'is_track'    => $isTrack,
        ];
    }

    /**
     * URL de flux d'un titre (pré-écoute). Bandcamp la signe et la fait
     * expirer : elle se redemande à chaque écoute et ne sort jamais du
     * serveur — public/api/download.php la proxifie comme celles de YouTube.
     */
    public static function streamUrl(int $bandId, int $trackId): ?string
    {
        if ($bandId <= 0 || $trackId <= 0) return null;
        $data = self::get(self::MOBILE_API . 'tralbum_details?' . http_build_query([
            'band_id'      => $bandId,
            'tralbum_id'   => $trackId,
            'tralbum_type' => 't',
        ]));
        $track = $data['tracks'][0] ?? null;
        if (!is_array($track)) return null;
        $streams = is_array($track['streaming_url'] ?? null) ? $track['streaming_url'] : [];
        $url = (string) ($streams['mp3-128'] ?? reset($streams) ?: '');
        return $url !== '' && str_starts_with($url, 'http') ? $url : null;
    }

    // ── Rouages ────────────────────────────────────────────────────────────

    /**
     * Un appel à la recherche du site. [$filter] : `a` album, `b` artiste,
     * `t` titre.
     *
     * @return array<array<string,mixed>>
     */
    private static function search(string $query, string $filter, int $limit): array
    {
        $query = trim($query);
        if ($query === '') return [];

        $body = json_encode([
            'search_text'   => $query,
            'search_filter' => $filter,
            'full_page'     => false,
            'fan_id'        => null,
        ], JSON_UNESCAPED_UNICODE);

        $raw = self::fetch(self::SEARCH_URL, ['Content-Type: application/json'], $body);
        if ($raw === null) return [];
        $data = json_decode($raw, true);
        $results = $data['auto']['results'] ?? [];
        if (!is_array($results)) return [];

        return array_slice(
            array_values(array_filter($results, 'is_array')),
            0,
            max(1, $limit)
        );
    }

    /** Un GET JSON, décodé, ou null. */
    private static function get(string $url): ?array
    {
        $raw = self::fetch($url, ['Accept: application/json']);
        if ($raw === null) return null;
        $data = json_decode($raw, true);
        // Bandcamp répond 200 avec {"error":true} sur une requête refusée.
        if (!is_array($data) || !empty($data['error'])) return null;
        return $data;
    }

    /**
     * Une requête HTTP, corps brut ou null. [$body] non nul = POST.
     *
     * Bandcamp sert du HTML de navigateur : sans User-Agent crédible, la page
     * d'un album revient vide de son `data-tralbum`.
     */
    private static function fetch(string $url, array $headers = [], ?string $body = null): ?string
    {
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => 15,
            CURLOPT_CONNECTTIMEOUT => 8,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_USERAGENT      => 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
                                    . '(KHTML, like Gecko) Chrome/124.0 Safari/537.36',
            CURLOPT_HTTPHEADER     => $headers,
        ]);
        if ($body !== null) {
            curl_setopt($ch, CURLOPT_POST, true);
            curl_setopt($ch, CURLOPT_POSTFIELDS, $body);
        }
        $raw    = curl_exec($ch);
        $status = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $error  = curl_error($ch);
        curl_close($ch);

        if ($status !== 200 || !is_string($raw) || $raw === '') {
            error_log("Bandcamp: $url → HTTP $status" . ($error ? " ($error)" : ''));
            return null;
        }
        return $raw;
    }

    /**
     * URL de la pochette. Bandcamp donne dans ses recherches une vignette de
     * 100 px ; le même dessin existe en 350 px sous `a<art_id>_2.jpg`, seule
     * taille qui vaille pour une fiche d'album.
     */
    private static function artwork($artId, string $fallback): string
    {
        $artId = (int) $artId;
        if ($artId > 0) {
            return 'https://f4.bcbits.com/img/a' . $artId . self::ART_SIZE . '.jpg';
        }
        return $fallback;
    }

    /**
     * L'année d'une date de sortie, qu'elle vienne de l'API mobile (timestamp)
     * ou d'une page (« 29 Mar 1999 00:00:00 GMT »). Chaîne vide si inconnue.
     */
    private static function yearOf($date): string
    {
        if (is_numeric($date)) {
            $ts = (int) $date;
            return $ts > 0 ? date('Y', $ts) : '';
        }
        if (is_string($date) && $date !== '') {
            $ts = strtotime($date);
            return $ts ? date('Y', $ts) : '';
        }
        return '';
    }
}
