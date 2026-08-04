<?php
/**
 * Gullify — MusicBrainz, la source de genres « fiable ».
 *
 * Extrait du scanner de genres (scripts/scan-genres.php) pour que le choix
 * manuel du genre d'un artiste puisse consulter la même base que la détection
 * automatique : ce qui range la bibliothèque toute seule doit être ce qui est
 * proposé quand on range à la main.
 *
 * Rien ici ne décide d'un genre : la classe rend des ÉTIQUETTES pesées, et
 * c'est GenreTaxonomy qui tranche (voir pickFromTags) — un « top tag » est un
 * mauvais signal, souvent hors sujet (« seen live », « canadian ») ou trop
 * large à côté d'une étiquette bien plus parlante plus bas dans la liste.
 *
 * Cadence : 1 requête/seconde, la politique de MusicBrainz.
 */

require_once __DIR__ . '/GenreTaxonomy.php';

class MusicBrainz
{
    /** Horodatage du dernier appel, pour tenir la cadence (partagé au process). */
    private static float $lastCall = 0.0;

    /**
     * Les étiquettes pesées d'un artiste (genres vérifiés + tags de la
     * communauté, fusionnés par nom, meilleur compte gardé).
     *
     * @param int $timeout  Secondes accordées à chaque appel réseau.
     * @param int $attempts Essais par appel. Un scan de fond peut insister
     *   (503 de passage) ; une suggestion demandée depuis l'app, non — c'est
     *   quelqu'un qui attend devant son téléphone.
     * @return array<array{name: string, count: int}>
     */
    public static function tags(string $artistName, int $timeout = 10, int $attempts = 3): array
    {
        // ── 1. Trouver l'artiste ────────────────────────────────────────────
        // Beaucoup de noms traînent le titre du film ou de la compilation dont
        // ils viennent : « (50 First Dates) Bob Marley ». Tel quel, rien ne
        // sort ; sans le préfixe, l'artiste se trouve du premier coup.
        $mbid     = null;
        $stripped = trim(preg_replace('/^\s*\([^)]*\)\s*/', '', $artistName));
        foreach ([$artistName, $stripped] as $candidate) {
            if ($candidate === '' || ($candidate !== $artistName && $candidate === trim($artistName))) {
                continue;
            }
            $mbid = self::findArtistId($candidate, $timeout, $attempts);
            if ($mbid) break;
        }

        if (!$mbid) return [];

        // ── 2. Ses tags et ses genres vérifiés ──────────────────────────────
        $detail = self::get(
            "https://musicbrainz.org/ws/2/artist/{$mbid}?inc=tags+genres&fmt=json",
            $timeout,
            $attempts
        );
        if (!$detail) return [];

        // Les genres vérifiés d'abord : mêmes noms que les tags, mais relus.
        // Un nom vu des deux côtés garde son meilleur compte.
        $merged = [];
        foreach ([$detail['genres'] ?? [], $detail['tags'] ?? []] as $list) {
            foreach ($list as $entry) {
                $name = trim($entry['name'] ?? '');
                if ($name === '') continue;
                $count = max(0, (int)($entry['count'] ?? 0));
                $key   = mb_strtolower($name, 'UTF-8');
                if (!isset($merged[$key]) || $count > $merged[$key]['count']) {
                    $merged[$key] = ['name' => $name, 'count' => $count];
                }
            }
        }

        return array_values($merged);
    }

    /**
     * L'identifiant MusicBrainz d'un artiste, ou null.
     *
     * Essaie la recherche exacte (entre guillemets) d'abord, puis une
     * recherche libre pour les noms qui ne collent pas caractère pour
     * caractère (ponctuation, « UB-40 » contre « UB40 »).
     */
    public static function findArtistId(string $name, int $timeout = 10, int $attempts = 3): ?string
    {
        $nameLower = strtolower(trim($name));

        foreach (['quoted', 'loose'] as $mode) {
            $term = $mode === 'quoted'
                ? '"' . self::luceneEscape($name) . '"'
                : self::luceneStrip($name);
            if (trim($term, '" ') === '') continue;

            $searchUrl = 'https://musicbrainz.org/ws/2/artist/?' . http_build_query([
                'query' => 'artist:' . $term,
                'fmt'   => 'json',
                'limit' => '5',
            ]);

            $data = self::get($searchUrl, $timeout, $attempts);
            if (empty($data['artists'])) continue;

            // Le nom exact d'abord ; sinon le premier résultat qui ressemble
            // encore à l'artiste demandé.
            $best = null;
            foreach ($data['artists'] as $a) {
                if (strtolower($a['name'] ?? '') === $nameLower) { $best = $a; break; }
            }
            if (!$best) {
                foreach ($data['artists'] as $a) {
                    if (self::nameMatches($name, (string)($a['name'] ?? ''), (int)($a['score'] ?? 0))) {
                        $best = $a;
                        break;
                    }
                }
            }

            if ($best && !empty($best['id'])) return (string)$best['id'];
        }

        return null;
    }

    /**
     * Un GET MusicBrainz, JSON décodé ou null. Tient la cadence d'1 req/s.
     *
     * Sur une longue série, MusicBrainz refuse ponctuellement une requête (503)
     * même en respectant la cadence : sans reprise, l'artiste repartait sans
     * genre pour une simple contrariété de passage. On repasse donc jusqu'à
     * $attempts fois, en laissant le serveur souffler entre deux.
     */
    private static function get(string $url, int $timeout = 10, int $attempts = 3): ?array
    {
        for ($attempt = 0; $attempt < max(1, $attempts); $attempt++) {
            $elapsed = microtime(true) - self::$lastCall;
            $wait    = 1.05 + ($attempt * 2.0);   // 1 s, puis 3 s, puis 5 s
            if ($elapsed < $wait) usleep((int)(($wait - $elapsed) * 1_000_000));
            self::$lastCall = microtime(true);

            $ch = curl_init($url);
            curl_setopt_array($ch, [
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_TIMEOUT        => $timeout,
                CURLOPT_USERAGENT      => 'Gullify/1.0 (self-hosted; https://github.com/gullify)',
                CURLOPT_HTTPHEADER     => ['Accept: application/json'],
                CURLOPT_FOLLOWLOCATION => true,
            ]);
            $body   = curl_exec($ch);
            $status = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            curl_close($ch);

            if ($status === 200 && $body) return json_decode($body, true) ?: null;
            // 503 = cadence refusée, 0 = réseau : ça vaut la peine de réessayer.
            if ($status !== 503 && $status !== 0) return null;
        }

        return null;
    }

    /**
     * Garde-fou contre une recherche libre qui ramène quelqu'un d'autre : le
     * nom trouvé doit ressembler à celui demandé, ou MusicBrainz doit être
     * lui-même très sûr de sa correspondance. Pas de genre vaut mieux qu'un
     * mauvais genre.
     */
    private static function nameMatches(string $wanted, string $found, int $score): bool
    {
        $a = GenreTaxonomy::normalize($wanted);
        $b = GenreTaxonomy::normalize($found);
        if ($a === '' || $b === '') return false;
        if ($a === $b) return true;
        if (str_contains($a, $b) || str_contains($b, $a)) return true;

        return $score >= 90;
    }

    /**
     * Échappe une chaîne destinée à une phrase Lucene entre guillemets :
     * seuls \ et " y sont spéciaux.
     */
    private static function luceneEscape(string $s): string
    {
        return str_replace(['\\', '"'], ['\\\\', '\\"'], $s);
    }

    /**
     * Retire les opérateurs Lucene pour la recherche libre. Laissé tel quel,
     * un nom comme « (50 First Dates) UB-40 » se lit comme une expression
     * groupée et ramène un artiste sans rapport.
     */
    private static function luceneStrip(string $s): string
    {
        $s = str_replace(
            ['+', '-', '&&', '||', '!', '(', ')', '{', '}', '[', ']', '^', '"', '~', '*', '?', ':', '\\', '/'],
            ' ',
            $s
        );
        return trim(preg_replace('/\s+/', ' ', $s));
    }
}
