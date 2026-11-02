<?php
/**
 * Pour toi — ce que le monde sait des artistes (Gouts).
 *
 * Une maison ne peut pas faire de filtrage collaboratif seule : elle emprunte
 * celui des autres. Last.fm (clé LASTFM_API_KEY) donne les artistes similaires
 * calculés sur des millions d'auditeurs et les étiquettes de sa communauté.
 * Sans clé, YouTube Music (artistes liés, par ytmusicapi) et MusicBrainz
 * (étiquettes) font le même travail, plus lentement.
 *
 * Le modèle de langue (IA_URL, IA_CLE, IA_MODELE, compatible OpenAI) est un
 * plus : il nomme les mix et écrit le portrait. Tout marche sans lui.
 */
require_once __DIR__ . '/AppConfig.php';
require_once __DIR__ . '/Gouts.php';
require_once __DIR__ . '/MusicBrainz.php';

class GoutsSources
{
    /** Refaire un artiste après ce délai (jours). */
    public const FRAICHEUR = 90;

    /** Étiquettes qui parlent de l'auditeur, pas de la musique. */
    private const TAGS_VIDES = [
        'seen live', 'favorites', 'favourite', 'favourites', 'favorite', 'my favorite', 'love', 'awesome',
        'beautiful', 'albums i own', 'cool', 'good', 'amazing', 'best', 'great', 'spotify', 'under 2000 listeners',
        'all', 'music', 'other', 'unknown', 'misc', 'check out', 'to listen', 'fip', 'epic', 'genius',
        'favorite artists', 'favourite artists', 'i love', 'loved', 'heard on pandora', 'vinyl',
    ];

    /** Deux noms pour la même chose : un seul garde la place. */
    private const SYNONYMES = [
        'quebec' => 'quebecois', 'quebecoise' => 'quebecois', 'quebec music' => 'quebecois',
        'musique quebecoise' => 'quebecois', 'french canadian' => 'quebecois',
        'hiphop' => 'hip hop', 'hip hop rap' => 'hip hop', 'rap' => 'hip hop',
        'electronica' => 'electronic', 'electro' => 'electronic',
        'french' => 'francophone', 'francais' => 'francophone', 'chanson' => 'chanson francaise',
        'pop punk' => 'pop punk', 'poppunk' => 'pop punk', 'punkrock' => 'punk rock',
        'soundtracks' => 'soundtrack', 'ost' => 'soundtrack', 'humour' => 'comedy', 'humor' => 'comedy',
    ];

    /** Image « étoile » que Last.fm sert à la place des photos d'artistes. */
    private const IMAGE_VIDE = '2a96cbd8b46e442fc41c2b86b821562f';

    public static function source(): string
    {
        return trim((string)AppConfig::get('lastfm.api_key')) !== '' ? 'lastfm' : 'youtube';
    }

    /**
     * Enrichit au plus $max artistes des bibliothèques : ceux qu'on écoute
     * d'abord, puis les autres, puis les périmés.
     *
     * @return array{faits:int, trouves:int, source:string}
     */
    public static function enrichir(PDO $db, int $max, ?callable $journal = null): array
    {
        Gouts::assurerTables($db);
        $source = self::source();
        // Les noms de toutes les bibliothèques, les plus écoutés en tête.
        $rows = $db->query("
            SELECT a.name, COALESCE(MAX(gp.score), -2) prio
              FROM artists a
              LEFT JOIN gouts_profil gp ON gp.user = a.user AND gp.type = 'artist' AND gp.cle = a.id
             WHERE a.name NOT IN ('', 'Various Artists', 'Artistes divers', 'Unknown Artist')
             GROUP BY a.name
             ORDER BY prio DESC")->fetchAll(PDO::FETCH_ASSOC);
        $deja = [];
        foreach ($db->query("SELECT cle, UNIX_TIMESTAMP(maj) m FROM artistes_enrichis") as $r) {
            $deja[$r['cle']] = (int)$r['m'];
        }
        $limite = time() - self::FRAICHEUR * 86400;
        $file = [];
        $vus = [];
        foreach ($rows as $r) {
            $cle = Gouts::cle($r['name']);
            if (isset($vus[$cle])) continue;
            $vus[$cle] = true;
            if (!isset($deja[$cle])) $file[] = $r['name'];
        }
        foreach ($rows as $r) {
            $cle = Gouts::cle($r['name']);
            if (isset($deja[$cle]) && $deja[$cle] < $limite) $file[] = $r['name'];
        }

        $faits = 0;
        $trouves = 0;
        foreach (array_slice($file, 0, $max) as $nom) {
            try {
                $ok = $source === 'lastfm' ? self::depuisLastfm($db, $nom) : self::depuisYoutube($db, $nom);
            } catch (Throwable $e) {
                $ok = false;
                if ($journal) $journal("  $nom : " . $e->getMessage());
            }
            $faits++;
            if ($ok) $trouves++;
            if ($journal && $faits % 50 === 0) $journal("  $faits artistes enrichis ($trouves trouvés)");
        }
        return ['faits' => $faits, 'trouves' => $trouves, 'source' => $source];
    }

    private static function marquer(PDO $db, string $nom, string $source, bool $trouve): void
    {
        $db->prepare('INSERT INTO artistes_enrichis (cle, nom, source, trouve, maj) VALUES (?, ?, ?, ?, NOW())
                      ON DUPLICATE KEY UPDATE nom = VALUES(nom), source = VALUES(source), trouve = VALUES(trouve), maj = NOW()')
           ->execute([Gouts::cle($nom), $nom, $source, $trouve ? 1 : 0]);
    }

    /** @param array<array{nom:string, score:float, image:?string}> $voisins */
    private static function ecrireVoisins(PDO $db, string $nom, array $voisins): void
    {
        $cle = Gouts::cle($nom);
        $db->prepare('DELETE FROM artistes_similaires WHERE cle = ?')->execute([$cle]);
        $ins = $db->prepare('INSERT IGNORE INTO artistes_similaires (cle, voisin_cle, voisin_nom, score, image)
                             VALUES (?, ?, ?, ?, ?)');
        foreach ($voisins as $v) {
            $vc = Gouts::cle($v['nom']);
            if ($vc === $cle) continue;
            $ins->execute([$cle, $vc, mb_substr($v['nom'], 0, 255), round($v['score'], 4), $v['image']]);
        }
    }

    /** @param array<string, float> $tags étiquette => poids (0 à 1) */
    private static function ecrireTags(PDO $db, string $nom, array $tags): void
    {
        $cle = Gouts::cle($nom);
        $db->prepare('DELETE FROM artistes_tags WHERE cle = ?')->execute([$cle]);
        $ins = $db->prepare('INSERT IGNORE INTO artistes_tags (cle, tag, poids) VALUES (?, ?, ?)');
        foreach ($tags as $t => $p) $ins->execute([$cle, $t, round($p, 3)]);
    }

    /** « Hip-Hop » = « hip hop » ; rien pour les étiquettes vides de sens. */
    public static function tagPropre(string $t): ?string
    {
        // Sans accents : la base (utf8mb4, insensible aux accents) tient
        // « québec » et « quebec » pour la même clé. GoutsRayons::joli les rend.
        $t = Gouts::sansAccents(mb_strtolower(trim($t), 'UTF-8'));
        $t = preg_replace('/[-_]+/', ' ', $t);
        $t = preg_replace('/\s+/', ' ', $t);
        $t = self::SYNONYMES[$t] ?? $t;
        if ($t === '' || mb_strlen($t) > 40 || in_array($t, self::TAGS_VIDES, true)) return null;
        if (preg_match('/^\d+ ?(stars?|of \d+)$/', $t)) return null;
        return mb_substr($t, 0, 100);
    }

    /** @param array<array{name:string, count:int}> $liste */
    private static function tagsPeses(array $liste, int $max = 12): array
    {
        $out = [];
        $top = 0;
        foreach ($liste as $e) $top = max($top, (int)$e['count']);
        $top = max(1, $top);
        foreach ($liste as $e) {
            $t = self::tagPropre((string)$e['name']);
            if ($t === null) continue;
            $p = (int)$e['count'] / $top;
            if ($p < 0.08) continue;
            $out[$t] = max($out[$t] ?? 0, $p);
            if (count($out) >= $max) break;
        }
        return $out;
    }

    // ── Last.fm ──────────────────────────────────────────────────────────

    private static function lastfm(string $methode, array $params): ?array
    {
        $url = 'https://ws.audioscrobbler.com/2.0/?' . http_build_query($params + [
            'method' => $methode, 'api_key' => AppConfig::get('lastfm.api_key'),
            'format' => 'json', 'autocorrect' => 1,
        ]);
        $ctx = stream_context_create(['http' => ['timeout' => 12, 'ignore_errors' => true,
            'header' => "User-Agent: GulliFY/1.0 (+https://gullify.app)\r\n"]]);
        usleep(220000); // Last.fm demande moins de cinq appels par seconde
        $raw = @file_get_contents($url, false, $ctx);
        $j = $raw ? json_decode($raw, true) : null;
        if (!is_array($j)) return null;
        if (isset($j['error'])) {
            // 6 = artiste inconnu : une réponse, pas une panne.
            if ((int)$j['error'] === 6) return [];
            throw new RuntimeException('Last.fm : ' . ($j['message'] ?? $j['error']));
        }
        return $j;
    }

    private static function depuisLastfm(PDO $db, string $nom): bool
    {
        $sim = self::lastfm('artist.getsimilar', ['artist' => $nom, 'limit' => 60]);
        $tags = self::lastfm('artist.gettoptags', ['artist' => $nom]);
        if ($sim === null || $tags === null) return false; // réseau : on réessaiera
        $voisins = [];
        foreach ($sim['similarartists']['artist'] ?? [] as $a) {
            $image = null;
            foreach ($a['image'] ?? [] as $im) {
                if (($im['size'] ?? '') === 'extralarge' && !empty($im['#text'])
                    && !str_contains($im['#text'], self::IMAGE_VIDE)) $image = $im['#text'];
            }
            $voisins[] = ['nom' => (string)$a['name'], 'score' => (float)($a['match'] ?? 0), 'image' => $image];
        }
        $liste = array_map(fn($t) => ['name' => $t['name'] ?? '', 'count' => (int)($t['count'] ?? 0)],
            $tags['toptags']['tag'] ?? []);
        $peses = self::tagsPeses($liste);
        self::ecrireVoisins($db, $nom, $voisins);
        self::ecrireTags($db, $nom, $peses);
        $trouve = $voisins !== [] || $peses !== [];
        self::marquer($db, $nom, 'lastfm', $trouve);
        return $trouve;
    }

    // ── YouTube Music + MusicBrainz (sans clé) ──────────────────────────

    private static function depuisYoutube(PDO $db, string $nom): bool
    {
        $py = file_exists('/opt/ytdlp/bin/python3') ? '/opt/ytdlp/bin/python3' : 'python3';
        $script = AppConfig::getPythonPath() . '/ytmusic_search.py';
        $out = shell_exec('timeout 40 ' . $py . ' ' . escapeshellarg($script) . ' related ' . escapeshellarg($nom) . ' 2>/dev/null');
        $j = $out ? json_decode($out, true) : null;
        $liste = is_array($j) ? ($j['results'] ?? $j) : [];
        $voisins = [];
        $n = count($liste);
        foreach (array_values($liste) as $i => $a) {
            if (!is_array($a) || empty($a['name'])) continue;
            // YouTube ne chiffre pas la ressemblance : le rang en tient lieu.
            $voisins[] = ['nom' => (string)$a['name'], 'score' => 1 - 0.6 * $i / max(1, $n),
                          'image' => ($a['thumbnail'] ?? '') ?: null];
        }
        $peses = [];
        try {
            $peses = self::tagsPeses(MusicBrainz::tags($nom, 10, 2));
            usleep(1100000); // MusicBrainz : un appel par seconde
        } catch (Throwable $e) {
            // les étiquettes manqueront, les voisins suffisent
        }
        if ($out === null && $peses === []) return false;
        self::ecrireVoisins($db, $nom, $voisins);
        self::ecrireTags($db, $nom, $peses);
        $trouve = $voisins !== [] || $peses !== [];
        self::marquer($db, $nom, 'youtube', $trouve);
        return $trouve;
    }

    /** Décrit un artiste précis maintenant (rayon « Ailleurs ») ; vrai s'il est trouvé. */
    public static function enrichirUn(PDO $db, string $nom): bool
    {
        try {
            return self::source() === 'lastfm' ? self::depuisLastfm($db, $nom) : self::depuisYoutube($db, $nom);
        } catch (Throwable $e) {
            return false;
        }
    }

    /**
     * Cherche des artistes dans le monde (« Tes artistes » : on peut aimer un
     * artiste qu'on n'a pas). Last.fm s'il y a une clé, sinon YouTube Music.
     *
     * @return array<array{nom:string, image:?string}>
     */
    public static function chercherArtistes(string $q, int $n = 8): array
    {
        $out = [];
        try {
            if (self::source() === 'lastfm') {
                $j = self::lastfm('artist.search', ['artist' => $q, 'limit' => $n]);
                foreach ($j['results']['artistmatches']['artist'] ?? [] as $a) {
                    if (!empty($a['name'])) $out[] = ['nom' => (string)$a['name'], 'image' => null];
                }
            } else {
                $py = file_exists('/opt/ytdlp/bin/python3') ? '/opt/ytdlp/bin/python3' : 'python3';
                $script = AppConfig::getPythonPath() . '/ytmusic_search.py';
                $raw = shell_exec('timeout 20 ' . $py . ' ' . escapeshellarg($script) . ' artist ' . escapeshellarg($q) . ' ' . (int)$n . ' 2>/dev/null');
                $j = $raw ? json_decode($raw, true) : null;
                foreach (($j['results'] ?? []) as $a) {
                    if (is_array($a) && !empty($a['name'])) {
                        $out[] = ['nom' => (string)$a['name'], 'image' => ($a['thumbnail'] ?? '') ?: null];
                    }
                }
            }
        } catch (Throwable $e) {
            // Rien du monde : la bibliothèque répond seule.
        }
        return array_slice($out, 0, $n);
    }

    /** Photo d'un artiste hors bibliothèque, par YouTube Music (rayon « Ailleurs »). */
    public static function imageArtiste(string $nom): ?string
    {
        $py = file_exists('/opt/ytdlp/bin/python3') ? '/opt/ytdlp/bin/python3' : 'python3';
        $script = AppConfig::getPythonPath() . '/ytmusic_search.py';
        $out = shell_exec('timeout 30 ' . $py . ' ' . escapeshellarg($script) . ' artist ' . escapeshellarg($nom) . ' 1 2>/dev/null');
        $j = $out ? json_decode($out, true) : null;
        $liste = is_array($j) ? ($j['results'] ?? $j) : [];
        foreach ($liste as $a) {
            if (is_array($a) && !empty($a['thumbnail'])) return (string)$a['thumbnail'];
        }
        return null;
    }

    // ── Modèle de langue (facultatif) ───────────────────────────────────

    public static function iaActive(): bool
    {
        return trim((string)AppConfig::get('ia.url')) !== '' && trim((string)AppConfig::get('ia.modele')) !== '';
    }

    /**
     * Demande un objet JSON au modèle. Rien (null) si pas configuré, injoignable
     * ou réponse illisible : l'appelant garde alors ses textes à lui.
     */
    public static function iaJson(string $consigne, string $donnees): ?array
    {
        if (!self::iaActive()) return null;
        $url = rtrim((string)AppConfig::get('ia.url'), '/');
        if (!str_ends_with($url, '/chat/completions')) $url .= '/chat/completions';
        $corps = json_encode([
            'model' => AppConfig::get('ia.modele'),
            'temperature' => 0.7,
            'max_tokens' => 1200,
            'messages' => [
                ['role' => 'system', 'content' => $consigne . "\nRéponds uniquement par un objet JSON valide, sans texte autour."],
                ['role' => 'user', 'content' => $donnees],
            ],
        ], JSON_UNESCAPED_UNICODE);
        $entetes = "Content-Type: application/json\r\n";
        $cle = trim((string)AppConfig::get('ia.cle'));
        if ($cle !== '') $entetes .= "Authorization: Bearer $cle\r\n";
        $ctx = stream_context_create(['http' => ['method' => 'POST', 'header' => $entetes, 'content' => $corps,
            'timeout' => 60, 'ignore_errors' => true]]);
        $raw = @file_get_contents($url, false, $ctx);
        $j = $raw ? json_decode($raw, true) : null;
        $texte = $j['choices'][0]['message']['content'] ?? null;
        if (!is_string($texte)) return null;
        if (preg_match('/\{.*\}/s', $texte, $m)) $texte = $m[0];
        $o = json_decode($texte, true);
        return is_array($o) ? $o : null;
    }
}
