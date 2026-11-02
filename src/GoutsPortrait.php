<?php
/**
 * Pour toi — « Tes goûts » : ce que GulliFY a compris de la personne, montré
 * en clair (Spotify le cache, Deezer commence à l'ouvrir avec son Flow Tuner :
 * un algorithme qu'on voit, on lui fait confiance et on le corrige).
 */
require_once __DIR__ . '/Gouts.php';
require_once __DIR__ . '/GoutsRayons.php';
require_once __DIR__ . '/GoutsSources.php';
require_once __DIR__ . '/ImageUrl.php';

class GoutsPortrait
{
    private const BRAS_NOMS = [
        'artiste' => 'Le même artiste', 'voisins' => 'Les artistes proches', 'sequence' => 'Tes enchaînements',
        'favoris' => 'Tes préférés', 'decouverte' => 'L\'inconnu',
    ];

    public static function pour(PDO $db, string $user): array
    {
        // Étiquettes : la part de chacune parmi les positives.
        $q = $db->prepare("SELECT type, cle, score, ecoutes FROM gouts_profil WHERE user = ? AND score > 0 ORDER BY score DESC");
        $q->execute([$user]);
        $tags = [];
        $genres = [];
        $artistesIds = [];
        foreach ($q->fetchAll(PDO::FETCH_ASSOC) as $r) {
            if ($r['type'] === 'tag') $tags[$r['cle']] = (float)$r['score'];
            if ($r['type'] === 'genre') $genres[$r['cle']] = (float)$r['score'];
            if ($r['type'] === 'artist') $artistesIds[(int)$r['cle']] = ['score' => (float)$r['score'], 'ecoutes' => (int)$r['ecoutes']];
        }
        // L'ADN : des styles, pas des pays ni des étiquettes fourre-tout.
        $tags = array_filter($tags, fn($t) => !in_array($t, GoutsRayons::TAGS_LARGES, true), ARRAY_FILTER_USE_KEY);
        $tags = array_slice($tags, 0, 10, true);
        $somme = array_sum($tags) ?: 1;
        $etiquettes = [];
        foreach ($tags as $t => $s) $etiquettes[] = ['nom' => GoutsRayons::joli($t), 'cle' => $t, 'part' => round($s / $somme, 3)];
        $genresOut = [];
        foreach (array_slice($genres, 0, 6, true) as $g => $s) $genresOut[] = ['nom' => mb_convert_case($g, MB_CASE_TITLE), 'score' => round($s, 3)];

        $top = array_slice($artistesIds, 0, 10, true);
        $artistes = [];
        if ($top) {
            $in = implode(',', array_fill(0, count($top), '?'));
            $q = $db->prepare("SELECT id, name FROM artists WHERE id IN ($in) AND user = ?");
            $q->execute(array_merge(array_keys($top), [$user]));
            $noms = $q->fetchAll(PDO::FETCH_KEY_PAIR);
            foreach ($top as $id => $x) {
                if (!isset($noms[$id])) continue;
                $artistes[] = ['id' => $id, 'nom' => $noms[$id], 'imageUrl' => ImageUrl::artiste($id),
                               'score' => round($x['score'], 3), 'ecoutes' => $x['ecoutes']];
            }
        }

        // Habitudes des 30 derniers jours.
        $q = $db->prepare("
            SELECT COUNT(*) n, COALESCE(SUM(completed), 0) finis, COALESCE(SUM(play_duration), 0) secondes,
                   COALESCE(SUM(completed = 0 AND play_duration < 30), 0) sautes
              FROM play_history WHERE user = ? AND played_at > NOW() - INTERVAL 30 DAY");
        $q->execute([$user]);
        $h = $q->fetch(PDO::FETCH_ASSOC);
        $q = $db->prepare("SELECT COUNT(*) FROM gouts_sauts WHERE user = ? AND saute_le > NOW() - INTERVAL 30 DAY");
        $q->execute([$user]);
        $sautsNets = (int)$q->fetchColumn();
        $n = (int)$h['n'] + $sautsNets;

        $decalage = Gouts::decalage($db, $user);
        $q = $db->prepare("SELECT HOUR(played_at + INTERVAL $decalage MINUTE) h, COUNT(*) n FROM play_history
                            WHERE user = ? AND played_at > NOW() - INTERVAL 90 DAY GROUP BY h");
        $q->execute([$user]);
        $heures = array_fill(0, 24, 0);
        foreach ($q->fetchAll(PDO::FETCH_ASSOC) as $r) $heures[(int)$r['h']] = (int)$r['n'];

        // Diversité : combien d'artistes différents pour cent écoutes.
        $q = $db->prepare("
            SELECT " . Gouts::SQL_INTERPRETE . " AS artiste, COUNT(*) n
              FROM play_history ph JOIN songs s ON s.id = ph.song_id
              JOIN albums al ON al.id = s.album_id JOIN artists a ON a.id = al.artist_id
             WHERE ph.user = ? AND ph.played_at > NOW() - INTERVAL 90 DAY GROUP BY artiste");
        $q->execute([$user]);
        $parts = array_map('intval', $q->fetchAll(PDO::FETCH_KEY_PAIR));
        $total = array_sum($parts) ?: 1;
        $entropie = 0.0;
        foreach ($parts as $c) { $p = $c / $total; $entropie -= $p * log($p); }
        $effectifs = (int)round(exp($entropie)); // « nombre effectif » d'artistes
        $profil = $effectifs >= 60 ? 'Explorateur' : ($effectifs >= 20 ? 'Curieux' : 'Fidèle');

        $q = $db->prepare("
            SELECT COUNT(*) FROM (
              SELECT " . Gouts::SQL_INTERPRETE . " AS artiste, MIN(ph.played_at) premier
                FROM play_history ph JOIN songs s ON s.id = ph.song_id
                JOIN albums al ON al.id = s.album_id JOIN artists a ON a.id = al.artist_id
               WHERE ph.user = ? GROUP BY artiste) x
             WHERE premier > NOW() - INTERVAL 30 DAY");
        $q->execute([$user]);
        $nouveaux = (int)$q->fetchColumn();
        // « Nouveaux ce mois-ci » n'a de sens qu'avec un historique plus long
        // qu'un mois : sinon tous les artistes le seraient.
        $q = $db->prepare('SELECT MIN(played_at) < NOW() - INTERVAL 45 DAY FROM play_history WHERE user = ?');
        $q->execute([$user]);
        if (!(int)$q->fetchColumn()) $nouveaux = null;

        // Réussite des recommandations, par famille d'origine (90 jours).
        $q = $db->prepare("
            SELECT SUBSTRING_INDEX(origin, ':', 1) f, COUNT(*) n, SUM(completed) finis
              FROM play_history WHERE user = ? AND origin IS NOT NULL AND played_at > NOW() - INTERVAL 90 DAY
             GROUP BY f");
        $q->execute([$user]);
        $reussite = [];
        $libelles = ['auto' => 'Lecture automatique', 'radio' => 'Radios de titres', 'mix' => 'Tes mix',
                     'decouvertes' => 'Découvertes de la semaine', 'moment' => 'Mix du moment',
                     'boucle' => 'En boucle', 'oubliees' => 'Perles oubliées'];
        foreach ($q->fetchAll(PDO::FETCH_ASSOC) as $r) {
            if (!isset($libelles[$r['f']]) || (int)$r['n'] < 3) continue;
            $reussite[] = ['famille' => $r['f'], 'nom' => $libelles[$r['f']], 'ecoutes' => (int)$r['n'],
                           'taux' => round((int)$r['finis'] / (int)$r['n'], 3)];
        }

        // Ce que la lecture automatique a appris.
        $q = $db->prepare('SELECT bras, succes, echecs FROM gouts_bandits WHERE user = ?');
        $q->execute([$user]);
        $appris = [];
        foreach ($q->fetchAll(PDO::FETCH_ASSOC) as $r) {
            if (!isset(self::BRAS_NOMS[$r['bras']])) continue;
            $essais = (float)$r['succes'] + (float)$r['echecs'] - 2;
            if ($essais < 3) continue;
            $appris[] = ['bras' => $r['bras'], 'nom' => self::BRAS_NOMS[$r['bras']], 'essais' => (int)round($essais),
                         'taux' => round((float)$r['succes'] / ((float)$r['succes'] + (float)$r['echecs']), 3)];
        }
        usort($appris, fn($a, $b) => $b['taux'] <=> $a['taux']);

        // Réglages, rejets, état de l'analyse.
        $q = $db->prepare('SELECT aventure, portrait, analyse_le FROM gouts_reglages WHERE user = ?');
        $q->execute([$user]);
        $reg = $q->fetch(PDO::FETCH_ASSOC) ?: ['aventure' => 0.35, 'portrait' => null, 'analyse_le' => null];
        $q = $db->prepare("
            SELECT r.type, r.cible_id, COALESCE(ar.name, s.title) nom, sa.name artiste
              FROM gouts_rejets r
              LEFT JOIN artists ar ON r.type = 'artist' AND ar.id = r.cible_id
              LEFT JOIN songs s ON r.type = 'song' AND s.id = r.cible_id
              LEFT JOIN albums sal ON sal.id = s.album_id
              LEFT JOIN artists sa ON sa.id = sal.artist_id
             WHERE r.user = ? ORDER BY r.cree_le DESC");
        $q->execute([$user]);
        $rejets = [];
        foreach ($q->fetchAll(PDO::FETCH_ASSOC) as $r) {
            if ($r['nom'] === null) continue;
            $rejets[] = ['type' => $r['type'], 'id' => (int)$r['cible_id'], 'nom' => $r['nom'], 'artiste' => $r['artiste']];
        }
        $q = $db->prepare("SELECT COUNT(DISTINCT a.name), COUNT(DISTINCT e.cle) FROM artists a
                             LEFT JOIN artistes_enrichis e ON e.nom = a.name AND e.trouve = 1 WHERE a.user = ?");
        $q->execute([$user]);
        [$nArtistes, $nEnrichis] = array_map('intval', $q->fetch(PDO::FETCH_NUM));

        $portrait = $reg['portrait'] ?: self::portraitMaison($etiquettes, $artistes, $profil, $nouveaux);

        return [
            'portrait' => $portrait,
            'profil' => $profil,
            'etiquettes' => $etiquettes,
            'genres' => $genresOut,
            'artistes' => $artistes,
            'habitudes' => [
                'ecoutes' => (int)$h['n'],
                'minutes' => (int)round((int)$h['secondes'] / 60),
                'tauxFini' => $n ? round((int)$h['finis'] / $n, 3) : null,
                'tauxSaute' => $n ? round(((int)$h['sautes'] + $sautsNets) / $n, 3) : null,
                'artistesEffectifs' => $effectifs,
                'nouveauxArtistes' => $nouveaux,  // null : historique trop court pour le dire
                'heures' => $heures,
            ],
            'reussite' => $reussite,
            'appris' => $appris,
            'aventure' => round((float)$reg['aventure'], 2),
            'rejets' => $rejets,
            'sources' => [
                'monde' => GoutsSources::source(),
                'enrichis' => $nEnrichis,
                'artistes' => $nArtistes,
                'ia' => GoutsSources::iaActive(),
            ],
            'analyseLe' => $reg['analyse_le'],
        ];
    }

    private static function portraitMaison(array $etiquettes, array $artistes, string $profil, ?int $nouveaux): string
    {
        if ($etiquettes === [] && $artistes === []) {
            return 'Écoute quelques albums : GulliFY apprend tes goûts à chaque titre fini ou sauté.';
        }
        $phrases = [];
        // Trois styles qui ne se répètent pas (« punk rock » couvre « punk »).
        $t = [];
        foreach ($etiquettes as $e) {
            $n = mb_strtolower($e['nom']);
            foreach ($t as $deja) if (str_contains($deja, $n) || str_contains($n, $deja)) continue 2;
            $t[] = $n;
            if (count($t) === 3) break;
        }
        if (count($t) >= 2) {
            $phrases[] = 'Ton cœur penche vers ' . implode(', ', array_slice($t, 0, -1)) . ' et ' . end($t) . '.';
        }
        if ($artistes) {
            $phrases[] = $artistes[0]['nom'] . ' reste ton repère'
                . (isset($artistes[1]) ? ', avec ' . $artistes[1]['nom'] . ' pas loin derrière' : '') . '.';
        }
        $phrases[] = match ($profil) {
            'Explorateur' => $nouveaux ? "Tu papillonnes : $nouveaux nouveaux artistes ce mois-ci." : 'Tu papillonnes d\'un artiste à l\'autre.',
            'Curieux' => $nouveaux ? "Fidèle à tes classiques, tu t'ouvres quand même : $nouveaux nouveaux artistes ce mois-ci." : 'Fidèle à tes classiques, mais curieux.',
            default => 'Tu sais ce que tu aimes, et tu y reviens.',
        };
        return implode(' ', $phrases);
    }
}
