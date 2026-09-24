<?php
/**
 * Gullify — Podcasts (idée #112) : découvrir, s'abonner, écouter.
 *
 * Un podcast n'est rien d'autre qu'un flux RSS ; tout le reste (chercher,
 * classer, illustrer) vient de l'annuaire public d'Apple, qui répond sans clé
 * ni session — le même que celui déjà utilisé pour les pochettes :
 *
 *   - `itunes.apple.com/search?media=podcast` : la recherche ;
 *   - `itunes.apple.com/<pays>/rss/toppodcasts/…/genre=<id>` : les palmarès,
 *     par catégorie, pour la liste « à découvrir » ;
 *   - `itunes.apple.com/lookup?id=…` : l'adresse du flux et la grande
 *     pochette, que le palmarès ne donne pas (un seul appel pour toute la
 *     page).
 *
 * Ce qui appartient à l'utilisateur vit ici, en base :
 *
 *   podcast_subscriptions — ses abonnements (un flux, sa fiche au moment de
 *                           l'abonnement, pour l'afficher sans réseau)
 *   podcast_progress      — où il en est dans chaque épisode
 *
 * Les épisodes ne sont jamais recopiés en base : ils sont lus dans le flux à
 * la demande, avec un cache court sur le disque (les flux publient parfois
 * plusieurs fois par jour, mais rarement plus d'une fois l'heure).
 *
 * Comme Bandcamp, toutes les méthodes rendent des structures vides plutôt que
 * de lever : un annuaire muet ne doit pas casser l'écran.
 */

require_once __DIR__ . '/AppConfig.php';

class Podcasts
{
    /** Boutique Apple interrogée (pochettes, palmarès et recherche). */
    private const STORE = 'ca';

    private const SEARCH_URL = 'https://itunes.apple.com/search';
    private const LOOKUP_URL = 'https://itunes.apple.com/lookup';

    /** Les palmarès bougent au jour le jour : six heures de cache suffisent. */
    private const CHART_TTL = 6 * 3600;

    /** Un flux peut publier plusieurs fois par jour, rarement plus souvent. */
    private const FEED_TTL = 1800;

    /** Un flux de podcast dépasse rarement 5 Mo ; au-delà, c'est autre chose. */
    private const FEED_MAX_BYTES = 8 * 1024 * 1024;

    /**
     * Les catégories du palmarès d'Apple, dans sa taxonomie de 2019 (des
     * identifiants plus anciens existent encore mais renvoient le palmarès
     * général — donc inutilisables).
     */
    private const GENRES = [
        1488 => 'Crimes réels',
        1489 => 'Actualités',
        1324 => 'Société et culture',
        1303 => 'Humour',
        1310 => 'Musique',
        1321 => 'Affaires',
        1533 => 'Sciences',
        1318 => 'Technologies',
        1512 => 'Santé et forme',
        1487 => 'Histoire',
        1301 => 'Arts',
        1304 => 'Éducation',
        1309 => 'Télé et cinéma',
        1545 => 'Sports',
        1305 => 'Enfants et famille',
        1502 => 'Loisirs',
        1483 => 'Fiction',
        1314 => 'Spiritualité',
        1511 => 'Gouvernement',
    ];

    // ── Ce qu'on montre ────────────────────────────────────────────────────

    /** Les catégories proposées à la découverte. */
    public static function genres(): array
    {
        $out = [];
        foreach (self::GENRES as $id => $name) {
            $out[] = ['id' => $id, 'name' => $name];
        }
        return $out;
    }

    /** Vrai si [$id] est une catégorie connue. */
    public static function isGenre(int $id): bool
    {
        return isset(self::GENRES[$id]);
    }

    /**
     * Les podcasts trouvés pour [$query].
     *
     * @return array<array<string,mixed>>
     */
    public static function search(string $query, int $limit = 25): array
    {
        $query = trim($query);
        if ($query === '') return [];
        $url = self::SEARCH_URL . '?' . http_build_query([
            'media'   => 'podcast',
            'entity'  => 'podcast',
            'term'    => $query,
            'limit'   => max(1, min(50, $limit)),
            'country' => strtoupper(self::STORE),
        ]);
        $data = self::getJson($url, 'recherche');
        $shows = [];
        foreach (is_array($data['results'] ?? null) ? $data['results'] : [] as $r) {
            $show = self::showFromLookup(is_array($r) ? $r : []);
            if ($show !== null) $shows[] = $show;
        }
        return $shows;
    }

    /**
     * Le palmarès d'une catégorie. Le palmarès ne donne ni adresse de flux ni
     * grande pochette : un seul `lookup` groupé les complète.
     *
     * @return array<array<string,mixed>>
     */
    public static function top(int $genreId, int $limit = 30): array
    {
        if (!self::isGenre($genreId)) return [];
        $limit = max(1, min(50, $limit));

        $cache = self::cacheFile('charts', "$genreId-$limit");
        $cached = self::readCache($cache, self::CHART_TTL);
        if ($cached !== null) return $cached;

        $url = sprintf(
            'https://itunes.apple.com/%s/rss/toppodcasts/limit=%d/genre=%d/json',
            self::STORE,
            $limit,
            $genreId
        );
        $data = self::getJson($url, 'palmarès');
        $entries = $data['feed']['entry'] ?? null;
        // Un palmarès d'un seul podcast n'est pas une liste de listes.
        if (is_array($entries) && isset($entries['id'])) $entries = [$entries];
        if (!is_array($entries)) {
            // Rendre le dernier palmarès connu plutôt que rien : Apple répond
            // parfois à côté, et une page vide serait pire que six heures de
            // retard.
            return self::readCache($cache, PHP_INT_MAX) ?? [];
        }

        $ids = [];
        foreach ($entries as $e) {
            $id = (int) ($e['id']['attributes']['im:id'] ?? 0);
            if ($id > 0) $ids[] = $id;
        }
        $shows = self::lookup($ids);
        if ($shows === []) return self::readCache($cache, PHP_INT_MAX) ?? [];

        self::writeCache($cache, $shows);
        return $shows;
    }

    /**
     * Les fiches de podcasts d'Apple, par identifiant, dans l'ordre demandé.
     * Un seul appel : `lookup` accepte jusqu'à 200 identifiants.
     *
     * @param array<int> $ids
     * @return array<array<string,mixed>>
     */
    public static function lookup(array $ids): array
    {
        $ids = array_values(array_unique(array_filter(array_map('intval', $ids), fn($i) => $i > 0)));
        if ($ids === []) return [];
        $url = self::LOOKUP_URL . '?' . http_build_query([
            'id'      => implode(',', array_slice($ids, 0, 200)),
            'entity'  => 'podcast',
            'country' => strtoupper(self::STORE),
        ]);
        $data = self::getJson($url, 'fiches');

        $byId = [];
        foreach (is_array($data['results'] ?? null) ? $data['results'] : [] as $r) {
            if (!is_array($r)) continue;
            $show = self::showFromLookup($r);
            if ($show !== null) $byId[(int) $show['itunesId']] = $show;
        }
        // L'ordre du palmarès est l'information : `lookup` le perd.
        $out = [];
        foreach ($ids as $id) {
            if (isset($byId[$id])) $out[] = $byId[$id];
        }
        return $out;
    }

    /**
     * Une fiche de podcast telle que l'app l'attend, ou null si l'entrée n'a
     * pas de flux (sans flux, rien à écouter).
     */
    private static function showFromLookup(array $r): ?array
    {
        $feed = trim((string) ($r['feedUrl'] ?? ''));
        if ($feed === '' || !self::isHttpUrl($feed)) return null;
        $art = (string) ($r['artworkUrl600'] ?? $r['artworkUrl100'] ?? $r['artworkUrl60'] ?? '');
        return [
            'feedUrl'      => $feed,
            'title'        => (string) ($r['collectionName'] ?? $r['trackName'] ?? ''),
            'author'       => (string) ($r['artistName'] ?? ''),
            'image'        => $art,
            'genre'        => (string) ($r['primaryGenreName'] ?? ''),
            'itunesId'     => (int) ($r['collectionId'] ?? $r['trackId'] ?? 0),
            'episodeCount' => (int) ($r['trackCount'] ?? 0),
            'description'  => '',
        ];
    }

    // ── Les abonnements ────────────────────────────────────────────────────

    public static function ensureTables(): void
    {
        static $bootstrapped = false;
        if ($bootstrapped) return;
        $bootstrapped = true;
        try {
            $db = AppConfig::getDB();
            // `feed_key` (md5 de l'adresse) plutôt que l'adresse elle-même
            // dans les clés : une URL de flux passe allègrement la longueur
            // maximale d'un index, et la collation du serveur ignore casse et
            // accents — ce qui n'a aucun sens pour une adresse.
            $db->exec("
                CREATE TABLE IF NOT EXISTS podcast_subscriptions (
                    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    user VARCHAR(100) NOT NULL,
                    feed_key CHAR(32) NOT NULL,
                    feed_url TEXT NOT NULL,
                    title VARCHAR(255) NOT NULL,
                    author VARCHAR(255) NULL,
                    image TEXT NULL,
                    description TEXT NULL,
                    genre VARCHAR(120) NULL,
                    itunes_id BIGINT NULL,
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE KEY uniq_pod_user_feed (user, feed_key),
                    INDEX idx_pod_user (user)
                )
            ");
            $db->exec("
                CREATE TABLE IF NOT EXISTS podcast_progress (
                    user VARCHAR(100) NOT NULL,
                    feed_key CHAR(32) NOT NULL,
                    episode_key CHAR(32) NOT NULL,
                    position INT UNSIGNED NOT NULL DEFAULT 0,
                    duration INT UNSIGNED NOT NULL DEFAULT 0,
                    completed TINYINT(1) NOT NULL DEFAULT 0,
                    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                        ON UPDATE CURRENT_TIMESTAMP,
                    PRIMARY KEY (user, feed_key, episode_key),
                    INDEX idx_pod_prog_feed (user, feed_key)
                )
            ");
        } catch (\Throwable $e) {
            error_log('Podcasts::ensureTables failed: ' . $e->getMessage());
        }
    }

    /** La clé d'un flux (et d'un épisode) : son empreinte, pas son adresse. */
    public static function key(string $value): string
    {
        return md5(trim($value));
    }

    /**
     * Les abonnements de [$user], du plus récent au plus ancien.
     *
     * @return array<array<string,mixed>>
     */
    public static function subscriptions(string $user): array
    {
        self::ensureTables();
        try {
            $stmt = AppConfig::getDB()->prepare('
                SELECT feed_url, title, author, image, description, genre,
                       itunes_id, created_at
                FROM podcast_subscriptions
                WHERE user = ?
                ORDER BY created_at DESC, id DESC
            ');
            $stmt->execute([$user]);
            $rows = $stmt->fetchAll(\PDO::FETCH_ASSOC);
        } catch (\Throwable $e) {
            error_log('Podcasts::subscriptions failed: ' . $e->getMessage());
            return [];
        }

        $out = [];
        foreach ($rows as $r) {
            $out[] = [
                'feedUrl'      => (string) $r['feed_url'],
                'title'        => (string) $r['title'],
                'author'       => (string) ($r['author'] ?? ''),
                'image'        => (string) ($r['image'] ?? ''),
                'description'  => (string) ($r['description'] ?? ''),
                'genre'        => (string) ($r['genre'] ?? ''),
                'itunesId'     => (int) ($r['itunes_id'] ?? 0),
                'episodeCount' => 0,
                'subscribed'   => true,
                'since'        => (string) ($r['created_at'] ?? ''),
            ];
        }
        return $out;
    }

    /** Vrai si [$user] est abonné à ce flux. */
    public static function isSubscribed(string $user, string $feedUrl): bool
    {
        self::ensureTables();
        try {
            $stmt = AppConfig::getDB()->prepare(
                'SELECT 1 FROM podcast_subscriptions WHERE user = ? AND feed_key = ?'
            );
            $stmt->execute([$user, self::key($feedUrl)]);
            return (bool) $stmt->fetchColumn();
        } catch (\Throwable $e) {
            return false;
        }
    }

    /**
     * Abonne [$user] à un podcast. Se réabonner n'ajoute rien : la fiche est
     * simplement rafraîchie.
     */
    public static function subscribe(string $user, array $show): bool
    {
        self::ensureTables();
        $feed = trim((string) ($show['feedUrl'] ?? ''));
        if ($feed === '' || !self::isHttpUrl($feed)) return false;
        try {
            $stmt = AppConfig::getDB()->prepare('
                INSERT INTO podcast_subscriptions
                    (user, feed_key, feed_url, title, author, image, description,
                     genre, itunes_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE
                    title = VALUES(title), author = VALUES(author),
                    image = VALUES(image), description = VALUES(description),
                    genre = VALUES(genre), itunes_id = VALUES(itunes_id)
            ');
            $stmt->execute([
                $user,
                self::key($feed),
                $feed,
                mb_substr(trim((string) ($show['title'] ?? '')) ?: $feed, 0, 255),
                mb_substr(trim((string) ($show['author'] ?? '')), 0, 255),
                trim((string) ($show['image'] ?? '')),
                trim((string) ($show['description'] ?? '')),
                mb_substr(trim((string) ($show['genre'] ?? '')), 0, 120),
                (int) ($show['itunesId'] ?? 0),
            ]);
            return true;
        } catch (\Throwable $e) {
            error_log('Podcasts::subscribe failed: ' . $e->getMessage());
            return false;
        }
    }

    /** Désabonne [$user]. Ce qu'il a écouté reste : se réabonner le retrouve. */
    public static function unsubscribe(string $user, string $feedUrl): bool
    {
        self::ensureTables();
        try {
            $stmt = AppConfig::getDB()->prepare(
                'DELETE FROM podcast_subscriptions WHERE user = ? AND feed_key = ?'
            );
            $stmt->execute([$user, self::key($feedUrl)]);
            return true;
        } catch (\Throwable $e) {
            error_log('Podcasts::unsubscribe failed: ' . $e->getMessage());
            return false;
        }
    }

    // ── Où l'on en est ─────────────────────────────────────────────────────

    /**
     * L'avancement de [$user] dans les épisodes d'un flux, par empreinte
     * d'épisode.
     *
     * @return array<string, array{position:int,duration:int,completed:bool}>
     */
    public static function progress(string $user, string $feedUrl): array
    {
        self::ensureTables();
        try {
            $stmt = AppConfig::getDB()->prepare('
                SELECT episode_key, position, duration, completed
                FROM podcast_progress
                WHERE user = ? AND feed_key = ?
            ');
            $stmt->execute([$user, self::key($feedUrl)]);
            $rows = $stmt->fetchAll(\PDO::FETCH_ASSOC);
        } catch (\Throwable $e) {
            return [];
        }
        $out = [];
        foreach ($rows as $r) {
            $out[(string) $r['episode_key']] = [
                'position'  => (int) $r['position'],
                'duration'  => (int) $r['duration'],
                'completed' => (bool) $r['completed'],
            ];
        }
        return $out;
    }

    /**
     * Retient où [$user] en est dans un épisode. Un épisode marqué écouté le
     * reste tant qu'on ne le relance pas depuis le début.
     */
    public static function saveProgress(
        string $user,
        string $feedUrl,
        string $guid,
        int $position,
        int $duration,
        bool $completed
    ): bool {
        self::ensureTables();
        if (trim($guid) === '' || trim($feedUrl) === '') return false;
        try {
            $stmt = AppConfig::getDB()->prepare('
                INSERT INTO podcast_progress
                    (user, feed_key, episode_key, position, duration, completed)
                VALUES (?, ?, ?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE
                    position = VALUES(position),
                    duration = GREATEST(duration, VALUES(duration)),
                    completed = VALUES(completed)
            ');
            $stmt->execute([
                $user,
                self::key($feedUrl),
                self::key($guid),
                max(0, $position),
                max(0, $duration),
                $completed ? 1 : 0,
            ]);
            return true;
        } catch (\Throwable $e) {
            error_log('Podcasts::saveProgress failed: ' . $e->getMessage());
            return false;
        }
    }

    // ── Le flux lui-même ───────────────────────────────────────────────────

    /**
     * La fiche et les épisodes d'un flux. `null` si le flux n'a pas pu être lu
     * (et qu'aucune copie n'en traîne dans le cache).
     *
     * @return array{show:array<string,mixed>,episodes:array<array<string,mixed>>}|null
     */
    public static function feed(string $feedUrl, int $limit = 100, bool $refresh = false): ?array
    {
        $feedUrl = trim($feedUrl);
        if (!self::isHttpUrl($feedUrl)) return null;

        $cache = self::cacheFile('feeds', self::key($feedUrl));
        if (!$refresh) {
            $cached = self::readCache($cache, self::FEED_TTL);
            if ($cached !== null) return self::sliceFeed($cached, $limit);
        }

        $xml = self::fetch($feedUrl);
        if ($xml === null) {
            // Le flux ne répond pas : mieux vaut une liste d'hier que rien.
            $stale = self::readCache($cache, PHP_INT_MAX);
            return $stale === null ? null : self::sliceFeed($stale, $limit);
        }

        $parsed = self::parse($xml, $feedUrl);
        if ($parsed === null) {
            $stale = self::readCache($cache, PHP_INT_MAX);
            return $stale === null ? null : self::sliceFeed($stale, $limit);
        }

        self::writeCache($cache, $parsed);
        return self::sliceFeed($parsed, $limit);
    }

    /** Les [$limit] premiers épisodes d'un flux déjà lu. */
    private static function sliceFeed(array $parsed, int $limit): array
    {
        $episodes = is_array($parsed['episodes'] ?? null) ? $parsed['episodes'] : [];
        return [
            'show'     => is_array($parsed['show'] ?? null) ? $parsed['show'] : [],
            'episodes' => array_slice($episodes, 0, max(1, min(300, $limit))),
        ];
    }

    /**
     * Lit un flux RSS de podcast. Public pour les tests : c'est la forme des
     * flux (et leurs approximations) qu'on veut pouvoir vérifier hors ligne.
     *
     * @return array{show:array<string,mixed>,episodes:array<array<string,mixed>>}|null
     */
    public static function parse(string $xml, string $feedUrl = ''): ?array
    {
        // Les flux sont écrits par tout et n'importe quoi : un caractère
        // illégal ne doit pas remplir le journal d'erreurs. LIBXML_NOENT n'y
        // est PAS : on ne résout aucune entité externe d'un fichier distant.
        $previous = libxml_use_internal_errors(true);
        $root = simplexml_load_string($xml, 'SimpleXMLElement', LIBXML_NOCDATA);
        libxml_clear_errors();
        libxml_use_internal_errors($previous);
        if ($root === false || !isset($root->channel)) return null;

        $channel = $root->channel;
        $ns = $root->getNamespaces(true);
        $itunesNs = $ns['itunes'] ?? 'http://www.itunes.com/dtds/podcast-1.0.dtd';
        $chanItunes = $channel->children($itunesNs);

        $show = [
            'feedUrl'     => $feedUrl,
            'title'       => self::text($channel->title),
            'author'      => self::text($chanItunes->author) ?: self::text($channel->{'managingEditor'}),
            'description' => self::plain(self::text($channel->description) ?: self::text($chanItunes->summary)),
            'image'       => self::channelImage($channel, $chanItunes),
            'link'        => self::text($channel->link),
            'genre'       => self::attr($chanItunes->category, 'text'),
        ];

        $episodes = [];
        foreach ($channel->item as $item) {
            $episode = self::episode($item, $itunesNs, $show['image']);
            if ($episode !== null) $episodes[] = $episode;
        }
        // Les flux sont presque toujours du plus récent au plus ancien, mais
        // « presque » n'est pas « toujours » : on range nous-mêmes.
        usort($episodes, fn($a, $b) => $b['publishedAt'] <=> $a['publishedAt']);

        return ['show' => $show, 'episodes' => $episodes];
    }

    /** Un épisode, ou null s'il n'a pas de son à jouer. */
    private static function episode(\SimpleXMLElement $item, string $itunesNs, string $showImage): ?array
    {
        $itunes = $item->children($itunesNs);

        $audio = '';
        foreach ($item->enclosure as $enclosure) {
            $url = self::attr($enclosure, 'url');
            $type = strtolower(self::attr($enclosure, 'type'));
            if ($url === '' || !self::isHttpUrl($url)) continue;
            // Une vidéo dans un flux de podcast existe ; on ne la joue pas.
            if ($type !== '' && !str_starts_with($type, 'audio')) continue;
            $audio = $url;
            break;
        }
        if ($audio === '') return null;

        $title = self::text($item->title) ?: self::text($itunes->title);
        $guid = self::text($item->guid);
        if ($guid === '') $guid = $audio;

        $image = self::attr($itunes->image, 'href');

        return [
            'guid'        => $guid,
            'title'       => $title !== '' ? $title : 'Épisode',
            'audioUrl'    => $audio,
            'description' => self::plain(
                self::text($item->description) ?: self::text($itunes->summary)
            ),
            'duration'    => self::seconds(self::text($itunes->duration)),
            'publishedAt' => self::timestamp(self::text($item->pubDate)),
            'image'       => $image !== '' ? $image : $showImage,
            'episode'     => (int) self::text($itunes->episode),
            'season'      => (int) self::text($itunes->season),
        ];
    }

    /** La pochette de la série : celle d'iTunes, sinon celle du RSS. */
    private static function channelImage(\SimpleXMLElement $channel, \SimpleXMLElement $itunes): string
    {
        $href = self::attr($itunes->image, 'href');
        if ($href !== '') return $href;
        return isset($channel->image->url) ? self::text($channel->image->url) : '';
    }

    /**
     * Une durée iTunes : secondes (« 1832 »), « mm:ss » ou « hh:mm:ss ».
     * 0 quand le flux n'en donne pas — l'app lira alors celle du fichier.
     */
    public static function seconds(string $raw): int
    {
        $raw = trim($raw);
        if ($raw === '') return 0;
        if (ctype_digit($raw)) return (int) $raw;
        $parts = array_reverse(explode(':', $raw));
        $total = 0;
        foreach ($parts as $i => $part) {
            if ($i > 2) break;
            $total += (int) round((float) $part) * (60 ** $i);
        }
        return max(0, $total);
    }

    /** Une date RSS en horodatage, 0 si illisible. */
    private static function timestamp(string $raw): int
    {
        $raw = trim($raw);
        if ($raw === '') return 0;
        $ts = strtotime($raw);
        return $ts === false ? 0 : $ts;
    }

    /** Le texte d'un nœud, vide s'il est absent. */
    private static function text($node): string
    {
        return $node === null ? '' : trim((string) $node);
    }

    /**
     * Un attribut d'un nœud, vide si le nœud ou l'attribut manque. Un flux
     * mal fichu n'a pas à faire lever un avertissement.
     */
    private static function attr($node, string $name): string
    {
        if (!$node instanceof \SimpleXMLElement) return '';
        $attributes = $node->attributes();
        if ($attributes === null || !isset($attributes[$name])) return '';
        return trim((string) $attributes[$name]);
    }

    /** Une description de flux, débarrassée de son HTML. */
    private static function plain(string $html): string
    {
        if ($html === '') return '';
        $text = preg_replace('#<br\s*/?>|</p>#i', "\n", $html) ?? $html;
        $text = html_entity_decode(strip_tags($text), ENT_QUOTES | ENT_HTML5, 'UTF-8');
        $text = preg_replace("/[ \t]+/", ' ', $text) ?? $text;
        $text = preg_replace("/\n{3,}/", "\n\n", $text) ?? $text;
        return trim($text);
    }

    // ── Rouages ────────────────────────────────────────────────────────────

    /**
     * Une adresse que le serveur accepte d'aller chercher.
     *
     * C'est le client qui fournit l'adresse d'un flux : sans ce garde-fou, il
     * pourrait faire sonner ce que le serveur voit et lui seul (la base, les
     * services voisins du réseau docker, les métadonnées de l'hébergeur).
     * D'où : http(s) seulement, un vrai nom d'hôte, et jamais une adresse
     * privée ou réservée.
     */
    public static function isHttpUrl(string $url): bool
    {
        $url = trim($url);
        if ($url === '' || strlen($url) > 2000) return false;
        $parts = parse_url($url);
        if (!is_array($parts)) return false;
        $scheme = strtolower((string) ($parts['scheme'] ?? ''));
        $host = (string) ($parts['host'] ?? '');
        if (($scheme !== 'http' && $scheme !== 'https') || $host === '') return false;
        return self::isPublicHost($host);
    }

    /** Vrai si [$host] désigne une machine publique (et pas le réseau local). */
    private static function isPublicHost(string $host): bool
    {
        $host = trim($host, '[]');
        $ips = filter_var($host, FILTER_VALIDATE_IP) ? [$host] : self::resolve($host);
        if ($ips === []) return false;
        foreach ($ips as $ip) {
            $public = filter_var(
                $ip,
                FILTER_VALIDATE_IP,
                FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE
            );
            if ($public === false) return false;
        }
        return true;
    }

    /** Les adresses IP d'un nom d'hôte (v4 et v6), ou [] s'il ne résout pas. */
    private static function resolve(string $host): array
    {
        $ips = [];
        $v4 = @gethostbynamel($host);
        if (is_array($v4)) $ips = $v4;
        $aaaa = @dns_get_record($host, DNS_AAAA);
        foreach (is_array($aaaa) ? $aaaa : [] as $record) {
            if (!empty($record['ipv6'])) $ips[] = (string) $record['ipv6'];
        }
        return $ips;
    }

    /** Un GET JSON, décodé, ou [] — l'annuaire d'Apple n'est pas vital. */
    private static function getJson(string $url, string $what): array
    {
        $raw = self::fetch($url, ['Accept: application/json']);
        if ($raw === null) {
            error_log("Podcasts: $what indisponible ($url)");
            return [];
        }
        $data = json_decode($raw, true);
        return is_array($data) ? $data : [];
    }

    /**
     * Une requête HTTP, corps brut ou null. Les redirections sont suivies,
     * mais l'adresse d'arrivée est revérifiée : une redirection vers le réseau
     * local contournerait sinon le garde-fou d'entrée.
     */
    private static function fetch(string $url, array $headers = []): ?string
    {
        if (!self::isHttpUrl($url)) return null;

        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => 20,
            CURLOPT_CONNECTTIMEOUT => 8,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_MAXREDIRS      => 5,
            CURLOPT_PROTOCOLS      => CURLPROTO_HTTP | CURLPROTO_HTTPS,
            CURLOPT_REDIR_PROTOCOLS => CURLPROTO_HTTP | CURLPROTO_HTTPS,
            CURLOPT_ACCEPT_ENCODING => '',
            CURLOPT_USERAGENT      => 'Gullify/1.0 (+https://gullify.app)',
            CURLOPT_HTTPHEADER     => $headers,
            // Un flux qui déborde est coupé net plutôt que de remplir la
            // mémoire du serveur.
            CURLOPT_BUFFERSIZE     => 65536,
            CURLOPT_NOPROGRESS     => false,
            CURLOPT_PROGRESSFUNCTION => fn($ch, $dlTotal, $dlNow) =>
                $dlNow > self::FEED_MAX_BYTES ? 1 : 0,
        ]);
        $raw    = curl_exec($ch);
        $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $final  = (string) curl_getinfo($ch, CURLINFO_EFFECTIVE_URL);
        $error  = curl_error($ch);
        curl_close($ch);

        if ($final !== '' && $final !== $url && !self::isHttpUrl($final)) {
            error_log("Podcasts: redirection refusée vers $final");
            return null;
        }
        if ($status < 200 || $status >= 300 || !is_string($raw) || $raw === '') {
            error_log("Podcasts: $url → HTTP $status" . ($error ? " ($error)" : ''));
            return null;
        }
        return $raw;
    }

    /** Où garder une réponse entre deux lectures. */
    private static function cacheFile(string $kind, string $name): string
    {
        $base = class_exists('AppConfig') ? AppConfig::getDataPath() . '/cache' : sys_get_temp_dir();
        $dir = "$base/podcasts/$kind";
        if (!is_dir($dir)) @mkdir($dir, 0775, true);
        return "$dir/" . preg_replace('/[^A-Za-z0-9_-]/', '', $name) . '.json';
    }

    /** Le contenu du cache s'il est assez frais, sinon null. */
    private static function readCache(string $path, int $ttl): ?array
    {
        if (!is_file($path)) return null;
        if ($ttl !== PHP_INT_MAX && filemtime($path) < time() - $ttl) return null;
        $data = json_decode((string) @file_get_contents($path), true);
        return is_array($data) ? $data : null;
    }

    private static function writeCache(string $path, array $data): void
    {
        @file_put_contents($path, json_encode($data, JSON_UNESCAPED_UNICODE));
    }
}
