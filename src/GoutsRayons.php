<?php
/**
 * Pour toi — les rayons de l'accueil, bâtis la nuit (scripts/analyser-gouts.php).
 *
 *  - mix       Les « Daily Mix » : les artistes aimés regroupés par affinité
 *              (propagation d'étiquettes sur le graphe des voisins), un mix par
 *              groupe : surtout du connu et aimé, un tiers à redécouvrir.
 *  - decouvertes  « Découvertes de la semaine » : jamais écoutés, chez des
 *              artistes proches de ce qu'on aime — refaites chaque lundi.
 *  - boucle    « En boucle » : ce qui tourne le plus depuis 30 jours.
 *  - oubliees  « Perles oubliées » : aimés, puis plus entendus depuis 30 jours.
 *  - moment    « Ton mix du matin / de l'après-midi / du soir / de la nuit » :
 *              ce qu'on écoute à cette heure-là (la daylist de Spotify).
 *  - ailleurs  Des artistes ABSENTS de la bibliothèque, que le monde associe à
 *              ce qu'on aime : à écouter sur YouTube, à télécharger.
 */
require_once __DIR__ . '/Gouts.php';
require_once __DIR__ . '/GoutsRadio.php';
require_once __DIR__ . '/GoutsSources.php';
require_once __DIR__ . '/TrackArtist.php';
require_once __DIR__ . '/ImageUrl.php';

class GoutsRayons
{
    public const MOMENTS = [
        'matin' => [5, 11, 'Ton mix du matin'],
        'apres_midi' => [11, 17, 'Ton mix de l\'après-midi'],
        'soir' => [17, 22, 'Ton mix du soir'],
        'nuit' => [22, 5, 'Ton mix de la nuit'],
    ];

    /** Étiquettes trop larges pour nommer un mix. */
    public const TAGS_LARGES = ['rock', 'pop', 'alternative', 'indie', 'canadian', 'american', 'british',
        'french', 'male vocalists', 'female vocalists', 'usa', 'canada', 'english', 'swedish', 'german',
        'australian', 'californian', 'singer songwriter', 'favorite songs'];

    /**
     * @param bool $reseau false : sans appel au dehors (photos d'artistes,
     *                     modèle de langue) — l'analyse faite à la volée par l'API.
     * @return array<string, int> nombre de rayons par type
     */
    public static function construire(PDO $db, string $user, bool $reseau = true): array
    {
        Gouts::assurerTables($db);
        $affArt = Gouts::affinitesArtistes($db, $user);
        $affTit = Gouts::affinitesTitres($db, $user);
        $voisins = Gouts::voisins($db, $user);
        $rejets = Gouts::rejets($db, $user);
        $noms = self::nomsArtistes($db, $user);
        $rayons = [];

        foreach (self::mixes($db, $user, $affArt, $affTit, $voisins, $rejets, $noms) as $i => $m) {
            $rayons[] = ['type' => 'mix', 'rang' => $i] + $m;
        }
        // Les découvertes ne changent qu'une fois par semaine (le lundi), ou
        // quand on a tout écouté.
        $q = $db->prepare("SELECT contenu, UNIX_TIMESTAMP(cree_le) t, titre, sous_titre FROM gouts_rayons WHERE user = ? AND type = 'decouvertes'");
        $q->execute([$user]);
        $ancien = $q->fetch(PDO::FETCH_ASSOC);
        $lundi = strtotime('monday this week');
        $garder = $ancien && (int)$ancien['t'] >= $lundi;
        if ($garder) {
            $c = json_decode($ancien['contenu'], true) ?: [];
            $restants = array_filter($c['titres'] ?? [], fn($t) => !isset($affTit[$t['id']]));
            if (count($restants) < 5) $garder = false;
        }
        if ($garder) {
            $rayons[] = ['type' => 'decouvertes', 'rang' => 0, 'titre' => $ancien['titre'], 'sous_titre' => $ancien['sous_titre'],
                         'contenu' => json_decode($ancien['contenu'], true)];
        } elseif ($d = self::decouvertes($db, $user, $affArt, $affTit, $voisins, $rejets, $noms)) {
            $rayons[] = ['type' => 'decouvertes', 'rang' => 0] + $d;
        }
        if ($b = self::enBoucle($db, $user)) $rayons[] = ['type' => 'boucle', 'rang' => 0] + $b;
        if ($o = self::oubliees($affTit, $rejets)) $rayons[] = ['type' => 'oubliees', 'rang' => 0] + $o;
        foreach (self::MOMENTS as $cle => $m) {
            if ($r = self::moment($db, $user, $cle, $affTit, $voisins, $rejets, $noms)) {
                $rayons[] = ['type' => 'moment', 'rang' => 0, 'titre' => $m[2]] + $r + ['moment' => $cle];
            }
        }
        if ($a = self::ailleurs($db, $user, $affArt, $noms, $reseau)) $rayons[] = ['type' => 'ailleurs', 'rang' => 0] + $a;

        if ($reseau) {
            self::nommerParIa($rayons, $db, $user, $noms, $affArt);
        } else {
            // Sans le modèle, on garde les noms qu'il avait donnés la nuit.
            self::garderNomsIa($rayons, $db, $user);
        }

        $db->beginTransaction();
        try {
            $db->prepare('DELETE FROM gouts_rayons WHERE user = ?')->execute([$user]);
            $ins = $db->prepare('INSERT INTO gouts_rayons (user, type, rang, titre, sous_titre, contenu) VALUES (?, ?, ?, ?, ?, ?)');
            $compte = [];
            foreach ($rayons as $r) {
                $contenu = $r['contenu'];
                if (isset($r['moment'])) $contenu['moment'] = $r['moment'];
                $ins->execute([$user, $r['type'], $r['rang'], mb_substr($r['titre'], 0, 120),
                    $r['sous_titre'] !== null ? mb_substr($r['sous_titre'], 0, 255) : null,
                    json_encode($contenu, JSON_UNESCAPED_UNICODE)]);
                $compte[$r['type']] = ($compte[$r['type']] ?? 0) + 1;
            }
            $db->commit();
        } catch (Throwable $e) {
            $db->rollBack();
            throw $e;
        }
        return $compte;
    }

    private static function nomsArtistes(PDO $db, string $user): array
    {
        $q = $db->prepare('SELECT id, name FROM artists WHERE user = ?');
        $q->execute([$user]);
        $out = [];
        foreach ($q->fetchAll(PDO::FETCH_ASSOC) as $r) {
            if (!Gouts::artisteVide((string)$r['name'])) $out[(int)$r['id']] = $r['name'];
        }
        return $out;
    }

    // ── Les mix quotidiens ──────────────────────────────────────────────

    private static function mixes(PDO $db, string $user, array $affArt, array $affTit, array $voisins, array $rejets, array $noms): array
    {
        $aimes = array_filter($affArt, fn($s, $a) => $s > 0.08 && !isset($rejets['artist'][$a]) && isset($noms[$a]),
            ARRAY_FILTER_USE_BOTH);
        arsort($aimes);
        $aimes = array_slice($aimes, 0, 90, true);
        if (count($aimes) < 3) return [];

        // Propagation d'étiquettes : chaque artiste prend le groupe que ses
        // voisins aimés tirent le plus fort.
        $label = [];
        foreach ($aimes as $a => $_) $label[$a] = $a;
        $ordre = array_keys($aimes);
        for ($tour = 0; $tour < 12; $tour++) {
            shuffle($ordre);
            $change = false;
            foreach ($ordre as $a) {
                $votes = [$label[$a] => 0.35 * $aimes[$a]];
                foreach ($voisins[$a] ?? [] as $v => $s) {
                    if (!isset($aimes[$v])) continue;
                    $votes[$label[$v]] = ($votes[$label[$v]] ?? 0) + $s * (0.5 + $aimes[$v]);
                }
                arsort($votes);
                $nouveau = array_key_first($votes);
                if ($nouveau !== $label[$a]) { $label[$a] = $nouveau; $change = true; }
            }
            if (!$change) break;
        }
        $groupes = [];
        foreach ($label as $a => $l) $groupes[$l][] = $a;
        // Les isolés rejoignent le groupe de leur meilleur voisin, sinon un
        // groupe « par genre » de la bibliothèque.
        $poidsGroupe = fn(array $g) => array_sum(array_map(fn($a) => $aimes[$a], $g));
        uasort($groupes, fn($x, $y) => $poidsGroupe($y) <=> $poidsGroupe($x));
        $gros = array_filter($groupes, fn($g) => count($g) >= 3);
        if ($gros === []) $gros = [array_key_first($groupes) => array_merge(...array_values($groupes))];
        foreach ($groupes as $l => $g) {
            if (isset($gros[$l])) continue;
            foreach ($g as $a) {
                $mieux = null;
                $s = 0;
                foreach ($gros as $gl => $membres) {
                    foreach ($membres as $m) {
                        $v = $voisins[$a][$m] ?? 0;
                        if ($v > $s) { $s = $v; $mieux = $gl; }
                    }
                }
                if ($mieux !== null) $gros[$mieux][] = $a;
            }
        }
        uasort($gros, fn($x, $y) => $poidsGroupe($y) <=> $poidsGroupe($x));
        $gros = array_slice($gros, 0, 6, true);

        $cles = [];
        foreach ($noms as $id => $nom) $cles[$id] = Gouts::cle($nom);
        $tags = Gouts::tagsDe($db, array_values($cles));
        $dejaNommes = [];
        $mixes = [];
        foreach ($gros as $membres) {
            usort($membres, fn($x, $y) => $aimes[$y] <=> $aimes[$x]);
            $titres = self::remplirMix($db, $user, $membres, $affTit, $voisins, $rejets, 45);
            if (count($titres) < 12) continue;
            $tag = self::tagDuGroupe($membres, $aimes, $cles, $tags, $dejaNommes);
            $dejaNommes[] = $tag;
            $mixes[] = [
                'titre' => $tag !== null ? 'Mix ' . self::joli($tag) : 'Mix ' . $noms[$membres[0]],
                'sous_titre' => self::listeNoms(array_map(fn($a) => $noms[$a], array_slice($membres, 0, 3)), count($membres) > 3),
                'contenu' => ['titres' => $titres, 'artistes' => array_slice($membres, 0, 8), 'tag' => $tag],
            ];
        }
        // Un nom en double (deux groupes de la même étiquette) : on numérote.
        foreach ($mixes as $i => $m) $mixes[$i]['contenu']['numero'] = $i + 1;
        return $mixes;
    }

    /**
     * Les titres d'un mix : ~65 % de titres aimés de ses artistes, le reste à
     * redécouvrir chez eux ou chez leurs voisins, ordonnés sans deux fois le
     * même artiste de suite.
     */
    private static function remplirMix(PDO $db, string $user, array $membres, array $affTit, array $voisins,
                                       array $rejets, int $n): array
    {
        $titres = GoutsRadio::titresDe($db, $user, $membres);
        $proches = [];
        foreach ($membres as $a) foreach ($voisins[$a] ?? [] as $v => $s) {
            if (!in_array($v, $membres, true)) $proches[$v] = max($proches[$v] ?? 0, $s);
        }
        arsort($proches);
        $proches = array_slice($proches, 0, 12, true);
        $titresProches = GoutsRadio::titresDe($db, $user, array_keys($proches));
        $recent = time() - 2 * 86400;

        $connus = [];
        $neufs = [];
        foreach ([[$titres, 1.0], [$titresProches, 0.6]] as [$liste, $facteur]) {
            foreach ($liste as $t) {
                $id = $t['id'];
                if (isset($rejets['song'][$id]) || isset($rejets['artist'][$t['artiste']])) continue;
                if ($t['duree'] > 0 && $t['duree'] < 60) continue;
                $at = $affTit[$id] ?? null;
                if ($at && $at['sauts'] > $at['finis']) continue;
                $bruit = mt_rand() / mt_getrandmax() * 0.35;
                if ($at && $at['score'] > 0.15) {
                    if ($at['dernier'] > $recent) $bruit -= 0.3; // entendu avant-hier : plus loin dans la liste
                    $connus[] = $t + ['s' => $at['score'] * $facteur + $bruit];
                } elseif (!$at) {
                    $neufs[] = $t + ['s' => $facteur * (($proches[$t['artiste']] ?? 1)) + $bruit];
                }
            }
        }
        usort($connus, fn($x, $y) => $y['s'] <=> $x['s']);
        usort($neufs, fn($x, $y) => $y['s'] <=> $x['s']);
        $nConnus = min(count($connus), (int)round($n * 0.65));
        $choix = array_merge(array_slice($connus, 0, $nConnus), array_slice($neufs, 0, $n - $nConnus));
        if (count($choix) < $n) $choix = array_merge($choix, array_slice($connus, $nConnus, $n - count($choix)));
        return self::sansRepetition($choix, 3);
    }

    /**
     * Mélange en évitant le même artiste à moins de $ecart titres, et pas plus
     * de 3 titres par album. Rend [{id, raison?}].
     */
    private static function sansRepetition(array $choix, int $ecart): array
    {
        shuffle($choix);
        $out = [];
        $parAlbum = [];
        while ($choix !== []) {
            $pris = null;
            foreach ($choix as $i => $t) {
                $recents = array_column(array_slice($out, -$ecart), 'a');
                if (in_array($t['artiste'], $recents, true)) continue;
                if (($parAlbum[$t['album']] ?? 0) >= 3) continue;
                $pris = $i;
                break;
            }
            if ($pris === null) {
                // Plus rien de présentable sans répétition : on s'arrête là
                // plutôt que d'aligner cinq titres du même artiste.
                if (count($out) >= 15) break;
                $pris = array_key_first($choix);
            }
            $t = $choix[$pris];
            unset($choix[$pris]);
            $parAlbum[$t['album']] = ($parAlbum[$t['album']] ?? 0) + 1;
            $out[] = ['id' => $t['id'], 'a' => $t['artiste']] + (isset($t['raison']) ? ['raison' => $t['raison']] : []);
        }
        return array_map(fn($t) => array_diff_key($t, ['a' => 1]), $out);
    }

    private static function tagDuGroupe(array $membres, array $aimes, array $cles, array $tags, array $deja): ?string
    {
        $score = [];
        foreach ($membres as $a) {
            foreach ($tags[$cles[$a] ?? ''] ?? [] as $t => $p) $score[$t] = ($score[$t] ?? 0) + $p * (0.3 + $aimes[$a]);
        }
        arsort($score);
        foreach ($score as $t => $_) {
            if (in_array($t, self::TAGS_LARGES, true) || in_array($t, $deja, true)) continue;
            if (preg_match('/^\d{2,4}s$/', $t)) continue; // « 90s » : une époque, pas un style
            return $t;
        }
        return null;
    }

    /** « punk rock » → « Punk rock », « quebecois » → « Québécois ». */
    public static function joli(string $tag): string
    {
        $fr = ['quebecois' => 'québécois', 'quebec' => 'Québec', 'francophone' => 'francophone', 'chanson francaise' => 'chanson française',
               'francais' => 'français', 'acadien' => 'acadien', 'quebecois rock' => 'rock québécois', 'rock quebecois' => 'rock québécois',
               'humour quebecois' => 'humour québécois', 'musique quebecoise' => 'musique québécoise', 'emo' => 'emo',
               'electronique' => 'électro', 'metal' => 'métal', 'hardcore' => 'hardcore', 'reggae' => 'reggae',
               'french rock' => 'rock français', 'french pop' => 'pop française', 'acadian' => 'acadien', 'hip hop' => 'hip-hop',
               'electronic' => 'électro', 'punk rock' => 'punk rock', 'singer songwriter' => 'auteurs-compositeurs',
               'post punk' => 'post-punk', 'pop punk' => 'pop-punk', 'skate punk' => 'skate punk', 'melodic hardcore' => 'hardcore mélodique',
               'classic rock' => 'rock classique', 'heavy metal' => 'heavy metal', 'soundtrack' => 'trames sonores',
               'comedy' => 'humour', 'celtic' => 'celtique', 'folk rock' => 'folk rock', 'chill' => 'détente'];
        $t = $fr[$tag] ?? $tag;
        return mb_strtoupper(mb_substr($t, 0, 1)) . mb_substr($t, 1);
    }

    private static function listeNoms(array $noms, bool $etPlus): string
    {
        if ($etPlus) return implode(', ', $noms) . ' et d\'autres';
        if (count($noms) <= 1) return implode('', $noms);
        return implode(', ', array_slice($noms, 0, -1)) . ' et ' . end($noms);
    }

    // ── Découvertes de la semaine ───────────────────────────────────────

    /** Proximité de chaque artiste avec le goût d'ensemble, et qui l'y amène. */
    private static function voisinageDuGout(array $affArt, array $voisins, array $rejets): array
    {
        $prox = [];
        $par = [];
        foreach ($affArt as $a => $s) {
            if ($s <= 0.05) continue;
            foreach ($voisins[$a] ?? [] as $v => $sim) {
                if (isset($rejets['artist'][$v])) continue;
                $c = $s * $sim;
                $prox[$v] = ($prox[$v] ?? 0) + $c;
                if ($c > ($par[$v][1] ?? 0)) $par[$v] = [$a, $c];
            }
        }
        return [$prox, $par];
    }

    private static function decouvertes(PDO $db, string $user, array $affArt, array $affTit, array $voisins, array $rejets, array $noms): ?array
    {
        [$prox, $par] = self::voisinageDuGout($affArt, $voisins, $rejets);
        // Un artiste jamais écouté vaut plus qu'un connu dont on n'a pas tout
        // entendu : c'est bien une découverte qu'on promet.
        foreach ($prox as $a => $p) {
            $connu = ($affArt[$a] ?? null) !== null;
            if ($connu && $affArt[$a] < -0.2) { unset($prox[$a]); continue; }
            $prox[$a] = $p * ($connu ? 0.55 : 1.0) * (0.85 + mt_rand() / mt_getrandmax() * 0.3);
        }
        arsort($prox);
        $prox = array_slice($prox, 0, 40, true);
        if (count($prox) < 3) return null;
        $titres = GoutsRadio::titresDe($db, $user, array_keys($prox));
        $parArtiste = [];
        foreach ($titres as $t) {
            if (isset($affTit[$t['id']]) || isset($rejets['song'][$t['id']])) continue;
            if ($t['duree'] > 0 && ($t['duree'] < 90 || $t['duree'] > 600)) continue;
            $parArtiste[$t['artiste']][] = $t;
        }
        $choix = [];
        foreach ($prox as $a => $p) {
            if (empty($parArtiste[$a])) continue;
            shuffle($parArtiste[$a]);
            $source = $noms[$par[$a][0]] ?? null;
            foreach (array_slice($parArtiste[$a], 0, 2) as $t) {
                $choix[] = $t + ['raison' => $source ? "Parce que tu écoutes $source" : 'Proche de tes goûts'];
            }
            if (count($choix) >= 30) break;
        }
        if (count($choix) < 8) return null;
        $sources = [];
        foreach ($choix as $c) if (preg_match('/tu écoutes (.+)$/u', $c['raison'], $m)) $sources[$m[1]] = true;
        return [
            'titre' => 'Découvertes de la semaine',
            'sous_titre' => 'Jamais écoutés, proches de ' . self::listeNoms(array_slice(array_keys($sources), 0, 2), count($sources) > 2),
            'contenu' => ['titres' => self::sansRepetition($choix, 2)],
        ];
    }

    // ── En boucle, perles oubliées ──────────────────────────────────────

    private static function enBoucle(PDO $db, string $user): ?array
    {
        $q = $db->prepare("
            SELECT ph.song_id, SUM(ph.completed) n
              FROM play_history ph JOIN songs s ON s.id = ph.song_id
             WHERE ph.user = ? AND ph.played_at > NOW() - INTERVAL 30 DAY
             GROUP BY ph.song_id HAVING n >= 2 ORDER BY n DESC, MAX(ph.played_at) DESC LIMIT 30");
        $q->execute([$user]);
        $ids = array_map('intval', $q->fetchAll(PDO::FETCH_COLUMN));
        if (count($ids) < 8) return null;
        return ['titre' => 'En boucle', 'sous_titre' => 'Ce qui tourne le plus depuis un mois',
                'contenu' => ['titres' => array_map(fn($id) => ['id' => $id], $ids)]];
    }

    private static function oubliees(array $affTit, array $rejets): ?array
    {
        $limite = time() - 30 * 86400;
        $ids = [];
        foreach ($affTit as $id => $t) {
            if ($t['finis'] >= 3 && $t['score'] > 0.3 && $t['dernier'] && $t['dernier'] < $limite && !isset($rejets['song'][$id])) {
                $ids[$id] = $t['score'] + mt_rand() / mt_getrandmax() * 0.3;
            }
        }
        if (count($ids) < 8) return null;
        arsort($ids);
        return ['titre' => 'Perles oubliées', 'sous_titre' => 'Tu les aimais, tu ne les entends plus',
                'contenu' => ['titres' => array_map(fn($id) => ['id' => $id], array_slice(array_keys($ids), 0, 30))]];
    }

    // ── Le mix du moment ────────────────────────────────────────────────

    private static function moment(PDO $db, string $user, string $cle, array $affTit, array $voisins, array $rejets, array $noms): ?array
    {
        [$de, $a] = self::MOMENTS[$cle];
        $local = 'HOUR(ph.played_at + INTERVAL ' . Gouts::decalage($db, $user) . ' MINUTE)';
        $heure = $de < $a ? "$local >= $de AND $local < $a" : "($local >= $de OR $local < $a)";
        $q = $db->prepare("
            SELECT " . Gouts::SQL_INTERPRETE . " AS artiste, SUM(ph.completed) - 0.7 * SUM(ph.completed = 0 AND ph.play_duration < 30) s
              FROM play_history ph JOIN songs s ON s.id = ph.song_id
              JOIN albums al ON al.id = s.album_id JOIN artists a ON a.id = al.artist_id
             WHERE ph.user = ? AND a.user = ? AND ph.played_at > NOW() - INTERVAL 120 DAY AND $heure
             GROUP BY artiste HAVING artiste IS NOT NULL ORDER BY s DESC LIMIT 12");
        $q->execute([$user, $user]);
        $rows = $q->fetchAll(PDO::FETCH_ASSOC);
        $total = array_sum(array_map(fn($r) => max(0, (float)$r['s']), $rows));
        if ($total < 20 || count($rows) < 3) return null; // pas assez d'écoutes à cette heure-là
        $membres = array_map(fn($r) => (int)$r['artiste'], array_filter($rows, fn($r) => (float)$r['s'] > 0));
        $titres = self::remplirMix($db, $user, $membres, $affTit, $voisins, $rejets, 40);
        if (count($titres) < 12) return null;
        return ['sous_titre' => self::listeNoms(array_map(fn($a) => $noms[$a] ?? '', array_slice($membres, 0, 3)), count($membres) > 3),
                'contenu' => ['titres' => $titres]];
    }

    // ── Ailleurs : hors de la bibliothèque ──────────────────────────────

    private static function ailleurs(PDO $db, string $user, array $affArt, array $noms, bool $reseau = true): ?array
    {
        $cleVersId = [];
        foreach ($noms as $id => $nom) $cleVersId[Gouts::cle($nom)] = $id;
        // Les sources : les artistes aimés de la bibliothèque, et ceux choisis
        // dans « Tes artistes » hors bibliothèque (déjà connus de la personne :
        // on ne les lui propose pas, on part d'eux).
        $sources = []; // clé => [poids, nom]
        foreach ($affArt as $a => $s) {
            if ($s > 0.1 && isset($noms[$a])) $sources[Gouts::cle($noms[$a])] = [$s, $noms[$a]];
        }
        $choix = Gouts::choix($db, $user);
        foreach ($choix as $cle => $c) {
            if (!isset($cleVersId[$cle])) $sources[$cle] = [$c['niveau'] >= 2 ? 0.9 : 0.6, $c['nom']];
        }
        if ($sources === []) return null;
        $in = implode(',', array_fill(0, count($sources), '?'));
        $q = $db->prepare("SELECT cle, voisin_cle, voisin_nom, score, image FROM artistes_similaires WHERE cle IN ($in)");
        $q->execute(array_keys($sources));
        $cands = [];
        while ($r = $q->fetch(PDO::FETCH_ASSOC)) {
            if (isset($cleVersId[$r['voisin_cle']])) continue; // déjà dans la bibliothèque
            if (isset($choix[$r['voisin_cle']])) continue;     // déjà choisi
            [$poids, $nomSource] = $sources[$r['cle']];
            $c = &$cands[$r['voisin_cle']];
            $c ??= ['nom' => $r['voisin_nom'], 'score' => 0.0, 'parce' => [], 'image' => null];
            $contrib = $poids * (float)$r['score'];
            $c['score'] += $contrib;
            $c['parce'][$nomSource] = $contrib;
            $c['image'] ??= $r['image'];
            unset($c);
        }
        // Recommandé par plusieurs artistes aimés > très proche d'un seul.
        foreach ($cands as $k => $c) $cands[$k]['score'] *= 1 + 0.25 * min(4, count($c['parce']) - 1);
        uasort($cands, fn($x, $y) => $y['score'] <=> $x['score']);
        $cands = array_slice($cands, 0, 15, true);
        if (count($cands) < 3) return null;

        // Images et étiquettes des retenus : connues si déjà enrichis, sinon
        // demandées maintenant (quinze appels au plus).
        if ($reseau) {
            $connus = Gouts::tagsDe($db, array_keys($cands));
            foreach ($cands as $cle => $c) if (!isset($connus[$cle])) GoutsSources::enrichirUn($db, $c['nom']);
        }
        $tags = Gouts::tagsDe($db, array_keys($cands));
        $artistes = [];
        foreach ($cands as $cle => $c) {
            arsort($c['parce']);
            $image = $c['image'] ?? self::imageEnCache($db, $cle) ?? ($reseau ? GoutsSources::imageArtiste($c['nom']) : null);
            if ($image) self::memoriserImage($db, $cle, $image);
            $t = array_keys($tags[$cle] ?? []);
            $artistes[] = [
                'nom' => $c['nom'],
                'image' => $image,
                'parce' => array_slice(array_keys($c['parce']), 0, 2),
                'tags' => array_map([self::class, 'joli'], array_slice(array_values(array_filter($t,
                    fn($x) => !in_array($x, self::TAGS_LARGES, true) && Gouts::cle($x) !== $cle)), 0, 3)),
                'score' => round($c['score'], 3),
            ];
        }
        return ['titre' => 'À découvrir ailleurs', 'sous_titre' => 'Pas encore dans ta bibliothèque',
                'contenu' => ['artistes' => $artistes]];
    }

    private static function imageEnCache(PDO $db, string $cle): ?string
    {
        $q = $db->prepare("SELECT image FROM artistes_similaires WHERE voisin_cle = ? AND image IS NOT NULL LIMIT 1");
        $q->execute([$cle]);
        $v = $q->fetchColumn();
        return $v ?: null;
    }

    private static function memoriserImage(PDO $db, string $cle, string $image): void
    {
        $db->prepare('UPDATE artistes_similaires SET image = ? WHERE voisin_cle = ? AND image IS NULL')->execute([$image, $cle]);
    }

    // ── Le modèle de langue, s'il y en a un ─────────────────────────────

    /** Reprend les noms de mix et phrases donnés par le modèle au dernier passage. */
    private static function garderNomsIa(array &$rayons, PDO $db, string $user): void
    {
        $q = $db->prepare("SELECT type, titre, contenu FROM gouts_rayons WHERE user = ? AND type IN ('mix', 'ailleurs')");
        $q->execute([$user]);
        $noms = [];
        $phrases = [];
        foreach ($q->fetchAll(PDO::FETCH_ASSOC) as $r) {
            $c = json_decode($r['contenu'], true) ?: [];
            if ($r['type'] === 'mix' && isset($c['nom_auto'])) $noms[$c['nom_auto']] = $r['titre'];
            foreach ($c['artistes'] ?? [] as $a) if (is_array($a) && isset($a['phrase'])) $phrases[$a['nom']] = $a['phrase'];
        }
        foreach ($rayons as $i => $r) {
            if ($r['type'] === 'mix' && isset($noms[$r['titre']])) {
                $rayons[$i]['contenu']['nom_auto'] = $r['titre'];
                $rayons[$i]['titre'] = $noms[$r['titre']];
            }
            if ($r['type'] === 'ailleurs') {
                foreach ($r['contenu']['artistes'] as $j => $a) {
                    if (isset($phrases[$a['nom']])) $rayons[$i]['contenu']['artistes'][$j]['phrase'] = $phrases[$a['nom']];
                }
            }
        }
    }

    /**
     * Donne aux mix un nom qui sonne (« Punk de sous-sol »), une phrase aux
     * artistes d'ailleurs, et le portrait. Échec ou pas configuré : on garde
     * les noms faits maison.
     */
    private static function nommerParIa(array &$rayons, PDO $db, string $user, array $noms, array $affArt): void
    {
        if (!GoutsSources::iaActive()) return;
        $mix = [];
        $ailleurs = [];
        foreach ($rayons as $i => $r) {
            if ($r['type'] === 'mix') {
                $mix[] = ['i' => $i, 'artistes' => array_map(fn($a) => $noms[$a] ?? '', $r['contenu']['artistes']),
                          'etiquette' => $r['contenu']['tag'] ?? null];
            }
            if ($r['type'] === 'ailleurs') {
                foreach ($r['contenu']['artistes'] as $j => $a) $ailleurs[] = ['j' => $j, 'nom' => $a['nom'], 'parce' => $a['parce'], 'tags' => $a['tags']];
            }
        }
        arsort($affArt);
        $top = array_map(fn($a) => $noms[$a] ?? '', array_slice(array_keys($affArt), 0, 15));
        $tags = $db->prepare("SELECT cle FROM gouts_profil WHERE user = ? AND type = 'tag' AND score > 0 ORDER BY score DESC LIMIT 12");
        $tags->execute([$user]);
        $r = GoutsSources::iaJson(
            "Tu es le programmateur musical d'une app d'écoute québécoise. Tu écris en français du Québec, court, chaleureux, sans cliché marketing.",
            json_encode([
                'demande' => "1) Pour chaque mix, un nom de 2 à 4 mots qui évoque son ambiance (pas le mot « mix »). " .
                             "2) Pour chaque artiste d'ailleurs, une phrase de 12 mots au plus qui dit pourquoi il plaira, à partir de « parce » et « tags ». " .
                             "3) Un portrait de l'auditeur en 2 phrases, au tutoiement. " .
                             "Format : {\"mix\":[{\"i\":0,\"nom\":\"…\"}],\"ailleurs\":[{\"j\":0,\"phrase\":\"…\"}],\"portrait\":\"…\"}",
                'mix' => $mix, 'ailleurs' => $ailleurs, 'artistes_preferes' => $top,
                'etiquettes_preferees' => $tags->fetchAll(PDO::FETCH_COLUMN),
            ], JSON_UNESCAPED_UNICODE)
        );
        if (!$r) return;
        foreach ($r['mix'] ?? [] as $m) {
            $i = (int)($m['i'] ?? -1);
            $nom = trim((string)($m['nom'] ?? ''));
            if (isset($rayons[$i]) && $rayons[$i]['type'] === 'mix' && $nom !== '' && mb_strlen($nom) <= 40) {
                $rayons[$i]['contenu']['nom_auto'] = $rayons[$i]['titre'];
                $rayons[$i]['titre'] = $nom;
            }
        }
        foreach ($rayons as $i => $ray) {
            if ($ray['type'] !== 'ailleurs') continue;
            foreach ($r['ailleurs'] ?? [] as $a) {
                $j = (int)($a['j'] ?? -1);
                $phrase = trim((string)($a['phrase'] ?? ''));
                if (isset($ray['contenu']['artistes'][$j]) && $phrase !== '') $rayons[$i]['contenu']['artistes'][$j]['phrase'] = mb_substr($phrase, 0, 140);
            }
        }
        $portrait = trim((string)($r['portrait'] ?? ''));
        if ($portrait !== '') {
            $db->prepare('INSERT INTO gouts_reglages (user, portrait) VALUES (?, ?) ON DUPLICATE KEY UPDATE portrait = VALUES(portrait)')
               ->execute([$user, mb_substr($portrait, 0, 600)]);
        }
    }

    // ── Lecture des rayons (API) ────────────────────────────────────────

    /**
     * Les titres prêts pour l'app, dans l'ordre demandé (les disparus sautés).
     *
     * @param array<array{id:int, raison?:string}> $liste
     */
    public static function hydrater(PDO $db, string $user, array $liste, ?string $origin = null): array
    {
        $ids = array_values(array_unique(array_map(fn($t) => (int)$t['id'], $liste)));
        if ($ids === []) return [];
        $in = implode(',', array_fill(0, count($ids), '?'));
        $q = $db->prepare("
            SELECT s.id, s.title, s.track_number, s.duration, s.file_path, s.album_id, al.name AS album_name,
                   " . TRACK_ARTIST_ID . " AS artist_id, " . TRACK_ARTIST_NAME . " AS artist_name
              FROM songs s JOIN albums al ON al.id = s.album_id JOIN artists a ON a.id = al.artist_id
              " . TRACK_ARTIST_JOIN . "
             WHERE s.id IN ($in) AND a.user = ?");
        $q->execute(array_merge($ids, [$user]));
        $rows = [];
        foreach ($q->fetchAll(PDO::FETCH_ASSOC) as $r) $rows[(int)$r['id']] = $r;
        $out = [];
        foreach ($liste as $t) {
            $r = $rows[(int)$t['id']] ?? null;
            if (!$r) continue;
            $out[] = [
                'id' => (int)$r['id'],
                'title' => $r['title'],
                'trackNumber' => (int)$r['track_number'],
                'duration' => (int)$r['duration'],
                'filePath' => $r['file_path'],
                'albumId' => (int)$r['album_id'],
                'albumName' => $r['album_name'],
                'artworkUrl' => ImageUrl::album((int)$r['album_id']),
                'artistId' => $r['artist_id'] !== null ? (int)$r['artist_id'] : null,
                'artistName' => $r['artist_name'],
                'raison' => $t['raison'] ?? null,
                'origin' => $t['origin'] ?? $origin,
            ];
        }
        return $out;
    }
}
