<?php
/**
 * Pour toi — la suite d'un morceau : lecture automatique et radio d'un titre.
 *
 * Comme la radio de Spotify ou le Flow de Deezer, en trois temps :
 *
 *  1. Des CANDIDATS venus de cinq sources (« bras ») : le même artiste, les
 *     artistes voisins, ce que la personne écoute d'habitude juste après,
 *     ses favoris proches, et des titres jamais écoutés proches (découverte).
 *  2. Un CLASSEMENT : proximité avec ce qui joue, affinité pour le titre et
 *     l'artiste, nouveauté dosée par le niveau d'aventure, et la SÉANCE en
 *     cours — un artiste sauté tout à l'heure recule tout de suite, sans
 *     attendre l'analyse de nuit.
 *  3. Un DOSAGE appris : chaque bras a sa loi Beta (succès = titre écouté,
 *     échec = sauté avant 30 s, voir Gouts::apprendre) ; on tire au sort
 *     (Thompson) la part de chaque bras à chaque appel. Ce qui marche pour
 *     cette personne prend de la place, sans jamais fermer la porte au reste
 *     (exploration). Puis la diversité : jamais deux fois le même artiste de
 *     suite, pas trois fois le même album.
 */
require_once __DIR__ . '/Gouts.php';

class GoutsRadio
{
    /** Part de départ de chaque bras, avant ce que le bandit a appris. */
    private const PART = ['artiste' => 0.18, 'voisins' => 0.34, 'sequence' => 0.14, 'favoris' => 0.22, 'decouverte' => 0.12];

    private const RAISONS = [
        'artiste'    => 'Du même artiste',
        'sequence'   => 'Tu l\'écoutes souvent juste après',
        'favoris'    => 'Un de tes préférés',
    ];

    /**
     * @param int[] $graines titres qui jouent ou viennent de jouer (le plus récent en dernier)
     * @param int[] $exclus  titres déjà dans la file
     * @return array<array{id:int, bras:string, raison:string}>
     */
    public static function suite(PDO $db, string $user, array $graines, array $exclus, int $n = 10,
                                 ?float $aventure = null, string $famille = 'auto'): array
    {
        Gouts::assurerTables($db);
        $n = max(1, min(50, $n));
        $aventure ??= Gouts::aventure($db, $user);
        $affArt = Gouts::affinitesArtistes($db, $user);
        $affTit = Gouts::affinitesTitres($db, $user);
        $voisins = Gouts::voisins($db, $user);
        $rejets = Gouts::rejets($db, $user);
        $exclus = array_fill_keys(array_map('intval', $exclus), true);
        foreach ($graines as $g) $exclus[(int)$g] = true;

        // ── La séance : 3 dernières heures ──────────────────────────────────
        $seance = self::seance($db, $user);
        foreach ($seance['recents'] as $id => $_) $exclus[$id] = true;
        if ($graines === []) $graines = $seance['finis'];

        // ── Les graines et leur voisinage ───────────────────────────────────
        $infos = self::infosTitres($db, $user, array_slice($graines, -4));
        $ctx = []; // artiste => proximité 0..1
        $poids = [1.0, 0.55, 0.35, 0.25];
        $racines = [];
        foreach (array_reverse(array_slice($graines, -4)) as $i => $g) {
            $a = $infos[(int)$g]['artiste'] ?? null;
            if ($a === null) continue;
            $w = $poids[$i] ?? 0.2;
            $racines[$a] = max($racines[$a] ?? 0, $w);
            $ctx[$a] = max($ctx[$a] ?? 0, $w);
            foreach ($voisins[$a] ?? [] as $v => $s) $ctx[$v] = max($ctx[$v] ?? 0, $w * $s);
        }
        // Graine sans voisins connus (bibliothèque pas encore enrichie) : le
        // même genre, puis les artistes qu'on aime, pour ne jamais rester muet.
        if (count($ctx) < 4) {
            foreach (self::memeGenre($db, $user, array_keys($racines)) as $a) $ctx[$a] ??= 0.3;
        }
        if (count($ctx) < 4) {
            arsort($affArt);
            foreach (array_slice($affArt, 0, 20, true) as $a => $s) if ($s > 0) $ctx[$a] ??= 0.25 * $s;
        }
        foreach ($rejets['artist'] as $a => $_) unset($ctx[$a]);
        if ($ctx === []) return [];
        arsort($ctx);
        $ctx = array_slice($ctx, 0, 45, true);

        // ── Candidats ───────────────────────────────────────────────────────
        $sequence = self::sequence($db, $user, array_slice($graines, -2));
        $titres = self::titresDe($db, $user, array_keys($ctx), array_keys($sequence));
        $maintenant = time();
        $cands = []; // bras => [id => [score, raison, artiste, album]]
        foreach ($titres as $t) {
            $id = $t['id'];
            if (isset($exclus[$id]) || isset($rejets['song'][$id])) continue;
            if ($t['duree'] > 0 && $t['duree'] < 45) continue; // interludes, jingles
            $a = $t['artiste'];
            $sim = $ctx[$a] ?? 0;
            $at = $affTit[$id] ?? null;
            $art = $affArt[$a] ?? 0;
            if ($at && $at['sauts'] >= 2 && $at['finis'] === 0) continue; // refusé plusieurs fois
            // Deux sauts du même artiste (ou album) dans la séance : on le met
            // de côté pour ce soir, comme le Flow de Deezer.
            if (($seance['sautsArtiste'][$a] ?? 0) >= 2 || ($seance['sautsAlbum'][$t['album']] ?? 0) >= 2) continue;

            $score = 0.45 * $sim + 0.30 * ($at['score'] ?? 0) + 0.20 * $art;
            $score += $at ? (1 - $aventure) * 0.15 * max(0, $at['score']) : $aventure * 0.30;
            if ($at && $at['dernier'] > $maintenant - 3 * 86400) $score -= 0.25; // entendu ces jours-ci
            $score -= 0.4 * ($seance['sautsArtiste'][$a] ?? 0);
            $score -= 0.2 * ($seance['sautsAlbum'][$t['album']] ?? 0);
            $score += 0.10 * ($seance['finisArtiste'][$a] ?? 0);
            $score += 0.07 * self::gumbel(); // jamais deux fois la même suite

            $c = ['score' => $score, 'artiste' => $a, 'album' => $t['album']];
            if (isset($sequence[$id])) {
                $cands['sequence'][$id] = $c + ['raison' => self::RAISONS['sequence'], 'score' => $score + 0.3 * $sequence[$id]];
            }
            if (isset($racines[$a])) {
                $cands['artiste'][$id] = $c + ['raison' => self::RAISONS['artiste']];
            } elseif ($at === null) {
                $cands['decouverte'][$id] = $c + ['raison' => 'Jamais écouté, proche de ' . self::nomRacine($a, $racines, $voisins, $infos)];
            } elseif ($at['score'] >= 0.45) {
                $cands['favoris'][$id] = $c + ['raison' => self::RAISONS['favoris']];
            } else {
                $cands['voisins'][$id] = $c + ['raison' => 'Proche de ' . self::nomRacine($a, $racines, $voisins, $infos)];
            }
            // Un favori de l'artiste de la graine compte aussi comme favori.
            if (isset($racines[$a]) && $at && $at['score'] >= 0.45) {
                $cands['favoris'][$id] = $c + ['raison' => self::RAISONS['favoris']];
            }
        }
        foreach ($cands as &$liste) uasort($liste, fn($x, $y) => $y['score'] <=> $x['score']);
        unset($liste);

        // ── Dosage (Thompson) ───────────────────────────────────────────────
        $parts = self::parts($db, $user, $aventure);

        // ── Sélection avec diversité ────────────────────────────────────────
        $choisis = [];
        $derniersArtistes = [];
        foreach (array_slice($graines, -2) as $g) {
            if (isset($infos[(int)$g]['artiste'])) $derniersArtistes[] = $infos[(int)$g]['artiste'];
        }
        $parArtiste = [];
        $parAlbum = [];
        $pris = [];
        // Le premier candidat présentable d'un bras : $souplesse 0 = pas d'artiste
        // des deux derniers titres et deux titres par artiste au plus ;
        // 1 = seulement pas le même artiste deux fois de suite, trois au plus.
        $premier = function (string $bras, int $souplesse) use (&$cands, &$pris, &$derniersArtistes, &$parArtiste, &$parAlbum): ?int {
            foreach ($cands[$bras] ?? [] as $id => $c) {
                if (isset($pris[$id])) continue;
                $a = $c['artiste'];
                if (!$souplesse && in_array($a, array_slice($derniersArtistes, -2), true)) continue;
                if ($souplesse && end($derniersArtistes) === $a) continue;
                if (($parArtiste[$a] ?? 0) >= ($souplesse ? 3 : 2)) continue;
                if (($parAlbum[$c['album']] ?? 0) >= 2) continue;
                return $id;
            }
            return null;
        };
        for ($k = 0; $k < $n; $k++) {
            $dispo = array_filter($parts, fn($p, $b) => !empty($cands[$b]), ARRAY_FILTER_USE_BOTH);
            if ($dispo === []) break;
            $bras = self::tirer($dispo);
            // Le bras tiré, sinon les autres (du plus dosé au moins dosé), tous
            // avec la règle stricte ; on ne l'assouplit qu'en dernier recours.
            $ordre = $dispo;
            unset($ordre[$bras]);
            arsort($ordre);
            $trouve = null;
            foreach ([0, 1] as $souplesse) {
                foreach (array_merge([$bras], array_keys($ordre)) as $b) {
                    $trouve = $premier($b, $souplesse);
                    if ($trouve !== null) { $bras = $b; break 2; }
                }
            }
            if ($trouve === null) break; // plus rien de présentable nulle part
            $c = $cands[$bras][$trouve];
            $pris[$trouve] = true;
            $parArtiste[$c['artiste']] = ($parArtiste[$c['artiste']] ?? 0) + 1;
            $parAlbum[$c['album']] = ($parAlbum[$c['album']] ?? 0) + 1;
            $derniersArtistes[] = $c['artiste'];
            foreach ($cands as $b => $_) unset($cands[$b][$trouve]);
            $choisis[] = ['id' => $trouve, 'bras' => $bras, 'raison' => $c['raison'], 'origin' => "$famille:$bras"];
        }
        return $choisis;
    }

    /** Parts de chaque bras pour cet appel : part de départ × tirage Beta. */
    public static function parts(PDO $db, string $user, float $aventure): array
    {
        $base = self::PART;
        $base['decouverte'] = 0.06 + 0.40 * $aventure;
        $base['favoris'] = 0.10 + 0.25 * (1 - $aventure);
        $q = $db->prepare('SELECT bras, succes, echecs FROM gouts_bandits WHERE user = ?');
        $q->execute([$user]);
        $beta = [];
        while ($r = $q->fetch(PDO::FETCH_ASSOC)) $beta[$r['bras']] = [(float)$r['succes'], (float)$r['echecs']];
        $out = [];
        foreach ($base as $b => $p) {
            [$s, $e] = $beta[$b] ?? [1.0, 1.0];
            // Moyenne a priori 0,5 : un bras jamais essayé garde sa part.
            $out[$b] = $p * 2 * self::beta($s, $e);
        }
        return $out;
    }

    /** Ce qui s'est passé ces trois dernières heures. */
    public static function seance(PDO $db, string $user): array
    {
        $q = $db->prepare("
            SELECT ph.song_id, ph.completed, ph.skipped, ph.play_duration, s.album_id, " . Gouts::SQL_INTERPRETE . " AS artiste
              FROM play_history ph JOIN songs s ON s.id = ph.song_id
              JOIN albums al ON al.id = s.album_id JOIN artists a ON a.id = al.artist_id
             WHERE ph.user = ? AND ph.played_at > NOW() - INTERVAL 3 HOUR
            UNION ALL
            SELECT g.song_id, 0, 1, g.duree, s.album_id, " . Gouts::SQL_INTERPRETE . "
              FROM gouts_sauts g JOIN songs s ON s.id = g.song_id
              JOIN albums al ON al.id = s.album_id JOIN artists a ON a.id = al.artist_id
             WHERE g.user = ? AND g.saute_le > NOW() - INTERVAL 3 HOUR");
        $q->execute([$user, $user]);
        $out = ['recents' => [], 'finis' => [], 'sautsArtiste' => [], 'sautsAlbum' => [], 'finisArtiste' => []];
        foreach ($q->fetchAll(PDO::FETCH_ASSOC) as $r) {
            $id = (int)$r['song_id'];
            $a = $r['artiste'] !== null ? (int)$r['artiste'] : 0;
            $out['recents'][$id] = true;
            $saute = (int)$r['play_duration'] < 30 && !$r['completed'] && $r['skipped'] !== '0';
            if ($saute) {
                $out['sautsArtiste'][$a] = min(2, ($out['sautsArtiste'][$a] ?? 0) + 1);
                $out['sautsAlbum'][(int)$r['album_id']] = min(2, ($out['sautsAlbum'][(int)$r['album_id']] ?? 0) + 1);
            } elseif ($r['completed']) {
                $out['finis'][] = $id;
                $out['finisArtiste'][$a] = min(2, ($out['finisArtiste'][$a] ?? 0) + 1);
            }
        }
        $out['finis'] = array_slice($out['finis'], -3);
        return $out;
    }

    /** Ce qu'on écoute d'habitude après ces titres (fini, moins de 20 min plus tard). */
    private static function sequence(PDO $db, string $user, array $graines): array
    {
        if ($graines === []) return [];
        $in = implode(',', array_fill(0, count($graines), '?'));
        $q = $db->prepare("
            SELECT nx.song_id, COUNT(*) n
              FROM play_history ph
              JOIN play_history nx ON nx.user = ph.user AND nx.played_at > ph.played_at
                   AND nx.played_at < ph.played_at + INTERVAL 20 MINUTE AND nx.completed = 1
             WHERE ph.user = ? AND ph.song_id IN ($in) AND nx.song_id NOT IN ($in)
             GROUP BY nx.song_id ORDER BY n DESC LIMIT 40");
        $q->execute(array_merge([$user], array_map('intval', $graines), array_map('intval', $graines)));
        $out = [];
        $max = 0;
        foreach ($q->fetchAll(PDO::FETCH_ASSOC) as $r) {
            $out[(int)$r['song_id']] = (int)$r['n'];
            $max = max($max, (int)$r['n']);
        }
        foreach ($out as $k => $v) $out[$k] = $v / max(1, $max);
        return $out;
    }

    /** @return array<int, array{artiste:?int, album:int, nom:string}> */
    public static function infosTitres(PDO $db, string $user, array $ids): array
    {
        $ids = array_values(array_filter(array_map('intval', $ids)));
        if ($ids === []) return [];
        $in = implode(',', array_fill(0, count($ids), '?'));
        $q = $db->prepare("
            SELECT s.id, s.album_id, " . Gouts::SQL_INTERPRETE . " AS artiste,
                   COALESCE(NULLIF(ta.name, ''), NULLIF(s.track_artist, ''), a.name) AS nom
              FROM songs s JOIN albums al ON al.id = s.album_id JOIN artists a ON a.id = al.artist_id
              LEFT JOIN artists ta ON ta.id = s.artist_id
             WHERE s.id IN ($in) AND a.user = ?");
        $q->execute(array_merge($ids, [$user]));
        $out = [];
        foreach ($q->fetchAll(PDO::FETCH_ASSOC) as $r) {
            $out[(int)$r['id']] = ['artiste' => $r['artiste'] !== null ? (int)$r['artiste'] : null,
                                   'album' => (int)$r['album_id'], 'nom' => $r['nom']];
        }
        return $out;
    }

    /** Titres des artistes donnés (interprète réel). */
    public static function titresDe(PDO $db, string $user, array $artistes, array $enPlus = []): array
    {
        $artistes = array_values(array_unique(array_map('intval', $artistes)));
        if ($artistes === []) return [];
        $out = [];
        // Les titres « écoutés juste après », quel que soit leur artiste.
        if ($enPlus !== []) {
            $ids = array_values(array_map('intval', $enPlus));
            $inIds = implode(',', array_fill(0, count($ids), '?'));
            $q = $db->prepare("
                SELECT s.id, s.album_id, s.duration, " . Gouts::SQL_INTERPRETE . " AS artiste
                  FROM songs s JOIN albums al ON al.id = s.album_id JOIN artists a ON a.id = al.artist_id
                 WHERE s.id IN ($inIds) AND a.user = ?");
            $q->execute(array_merge($ids, [$user]));
            foreach ($q->fetchAll(PDO::FETCH_ASSOC) as $r) {
                if ($r['artiste'] === null) continue;
                $out[(int)$r['id']] = ['id' => (int)$r['id'], 'album' => (int)$r['album_id'],
                                       'duree' => (int)$r['duration'], 'artiste' => (int)$r['artiste']];
            }
        }
        $in = implode(',', array_fill(0, count($artistes), '?'));
        // Deux requêtes plutôt qu'un OR : chacune garde son index.
        $q = $db->prepare("
            SELECT s.id, s.album_id, s.duration, al.artist_id AS artiste
              FROM songs s JOIN albums al ON al.id = s.album_id JOIN artists a ON a.id = al.artist_id
             WHERE al.artist_id IN ($in) AND a.user = ?
               AND LOWER(a.name) NOT IN ('" . implode("', '", array_filter(Gouts::ARTISTES_VIDES)) . "')
               AND (s.artist_id IS NULL OR s.artist_id = al.artist_id)
               AND (NULLIF(s.track_artist, '') IS NULL OR s.track_artist = a.name)
            UNION ALL
            SELECT s.id, s.album_id, s.duration, s.artist_id
              FROM songs s JOIN albums al ON al.id = s.album_id JOIN artists a ON a.id = al.artist_id
             WHERE s.artist_id IN ($in) AND a.user = ? AND s.artist_id <> al.artist_id");
        $q->execute(array_merge($artistes, [$user], $artistes, [$user]));
        foreach ($q->fetchAll(PDO::FETCH_ASSOC) as $r) {
            $out[(int)$r['id']] = ['id' => (int)$r['id'], 'album' => (int)$r['album_id'],
                                   'duree' => (int)$r['duration'], 'artiste' => (int)$r['artiste']];
        }
        return array_values($out);
    }

    /** Artistes du même genre de bibliothèque (repli sans voisins). */
    private static function memeGenre(PDO $db, string $user, array $artistes): array
    {
        if ($artistes === []) return [];
        $in = implode(',', array_fill(0, count($artistes), '?'));
        $q = $db->prepare("
            SELECT DISTINCT b.id FROM artists a JOIN artists b ON b.user = a.user AND b.genre = a.genre AND b.id <> a.id
             WHERE a.id IN ($in) AND a.user = ? AND a.genre NOT IN ('', 'Music', 'Other', 'Miscellaneous')
             ORDER BY RAND() LIMIT 30");
        $q->execute(array_merge($artistes, [$user]));
        return array_map('intval', $q->fetchAll(PDO::FETCH_COLUMN));
    }

    /** Le nom de la graine la plus proche de cet artiste, pour expliquer. */
    private static function nomRacine(int $a, array $racines, array $voisins, array $infos): string
    {
        $meilleur = null;
        $s = -1;
        foreach ($racines as $r => $w) {
            $v = ($voisins[$r][$a] ?? 0) * $w;
            if ($v > $s) { $s = $v; $meilleur = $r; }
        }
        foreach ($infos as $i) if ($i['artiste'] === $meilleur) return $i['nom'];
        return 'ce que tu écoutes';
    }

    private static function tirer(array $poids): string
    {
        $total = array_sum($poids);
        $x = mt_rand() / mt_getrandmax() * $total;
        foreach ($poids as $k => $p) {
            $x -= $p;
            if ($x <= 0) return (string)$k;
        }
        return (string)array_key_last($poids);
    }

    private static function gumbel(): float
    {
        $u = max(1e-9, mt_rand() / mt_getrandmax());
        return -log(-log($u)) / 3;
    }

    /** Tirage Beta(a, b) par deux tirages Gamma (Marsaglia–Tsang). */
    public static function beta(float $a, float $b): float
    {
        $x = self::gamma($a);
        $y = self::gamma($b);
        return $x + $y > 0 ? $x / ($x + $y) : 0.5;
    }

    private static function gamma(float $k): float
    {
        if ($k < 1) return self::gamma($k + 1) * (mt_rand() / mt_getrandmax()) ** (1 / $k);
        $d = $k - 1 / 3;
        $c = 1 / sqrt(9 * $d);
        while (true) {
            do {
                $u1 = max(1e-12, mt_rand() / mt_getrandmax());
                $u2 = mt_rand() / mt_getrandmax();
                $z = sqrt(-2 * log($u1)) * cos(2 * M_PI * $u2);
                $v = (1 + $c * $z) ** 3;
            } while ($v <= 0);
            $u = mt_rand() / mt_getrandmax();
            if (log(max(1e-12, $u)) < 0.5 * $z * $z + $d - $d * $v + $d * log($v)) return $d * $v;
        }
    }
}
