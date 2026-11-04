<?php
/**
 * Pour toi — « Tes artistes » : les bulles à la Spotify.
 *
 * On touche une bulle une fois pour aimer, deux fois pour adorer, trois fois
 * pour retirer. Aimer une bulle en fait éclore d'autres à côté (ses artistes
 * proches) : c'est comme ça qu'on part de trois noms pour décrire un goût. On
 * peut aussi chercher un artiste, dans sa bibliothèque ou hors d'elle — un
 * artiste qu'on n'a pas compte quand même : ses voisins dans la bibliothèque
 * en profitent (Gouts::analyserProfil), et les « artistes d'ailleurs » partent
 * de lui (GoutsRayons::ailleurs).
 */
require_once __DIR__ . '/Gouts.php';
require_once __DIR__ . '/GoutsSources.php';
require_once __DIR__ . '/ImageUrl.php';

class GoutsBulles
{
    /** Les artistes de la bibliothèque : clé => [id, nom]. */
    private static function bibliotheque(PDO $db, string $user): array
    {
        static $cache = [];
        if (isset($cache[$user])) return $cache[$user];
        $q = $db->prepare('SELECT id, name FROM artists WHERE user = ?');
        $q->execute([$user]);
        $out = [];
        foreach ($q->fetchAll(PDO::FETCH_ASSOC) as $r) {
            if (Gouts::artisteVide((string)$r['name'])) continue;
            $out[Gouts::cle($r['name'])] ??= ['id' => (int)$r['id'], 'nom' => $r['name']];
        }
        return $cache[$user] = $out;
    }

    /** Une bulle telle que l'app la dessine. */
    private static function bulle(string $cle, string $nom, ?string $image, array $biblio, array $choix): array
    {
        $b = $biblio[$cle] ?? null;
        return [
            'cle' => $cle,
            'nom' => $b['nom'] ?? $nom,
            'image' => $b ? ImageUrl::artiste($b['id']) : $image,
            'artistId' => $b['id'] ?? null,
            'niveau' => $choix[$cle]['niveau'] ?? 0,
        ];
    }

    /**
     * Les bulles de départ : ce qu'on a déjà choisi, chacune suivie de ses
     * artistes proches (on revient modifier : le réseau a déjà poussé), puis
     * les artistes qu'on écoute le plus et des artistes d'ailleurs, mêlés.
     * Chaque bulle porte ses `liens` : les bulles à l'écran qui lui sont
     * proches, les fils du réseau que l'app dessine.
     */
    public static function depart(PDO $db, string $user, int $n = 36): array
    {
        $biblio = self::bibliotheque($db, $user);
        $choix = Gouts::choix($db, $user);
        $rejetes = self::rejetes($db, $user);
        $vus = $choix === [] ? [] : array_fill_keys(array_map('strval', array_keys($choix)), true);
        $out = [];

        // Des choisies jamais décrites (choisies avant qu'on décrive tout de
        // suite, ou la source était muette) : deux par ouverture, pas plus.
        $voisins = self::voisinsDe($db, array_keys($choix));
        $aDecrire = 2;
        foreach ($choix as $cle => $c) {
            if ($aDecrire <= 0) break;
            if (isset($voisins[$cle]) || self::dejaCherche($db, (string)$cle)) continue;
            $aDecrire--;
            if (GoutsSources::enrichirUn($db, $c['nom'])) $voisins[$cle] = self::similaires($db, (string)$cle);
        }

        // Chaque choisie, puis ses proches : deux tiers dans la bibliothèque.
        // Trois chacune au plus, et une trentaine en tout.
        $parChoix = $choix === [] ? 0 : max(1, min(3, (int)ceil(30 / count($choix))));
        $proposes = 0;
        foreach ($choix as $cle => $c) {
            $cle = (string)$cle;
            $out[] = self::bulle($cle, $c['nom'], $c['image'], $biblio, $choix);
            if ($proposes >= 30) continue;
            $dedans = [];
            $dehors = [];
            foreach ($voisins[$cle] ?? [] as $p) {
                $vc = $p['voisin_cle'];
                if (isset($vus[$vc]) || Gouts::artisteVide((string)$p['voisin_nom'])) continue;
                $b = self::bulle($vc, $p['voisin_nom'], $p['image'], $biblio, $choix);
                if ($b['artistId'] !== null && isset($rejetes[$b['artistId']])) continue;
                if ($b['artistId'] !== null) $dedans[] = $b; else $dehors[] = $b;
            }
            foreach (self::melanger($dedans, $dehors, min($parChoix, 30 - $proposes)) as $b) {
                $vus[$b['cle']] = true;
                $out[] = $b;
                $proposes++;
            }
        }

        // Les écoutés (affinité), à défaut les plus fournis de la bibliothèque.
        $q = $db->prepare("SELECT a.id, a.name FROM gouts_profil gp JOIN artists a ON a.id = gp.cle
                            WHERE gp.user = ? AND gp.type = 'artist' AND gp.score > 0 AND a.user = ?
                            ORDER BY gp.score DESC LIMIT 40");
        $q->execute([$user, $user]);
        $locaux = $q->fetchAll(PDO::FETCH_ASSOC);
        if (count($locaux) < 20) {
            $q = $db->prepare('SELECT id, name FROM artists WHERE user = ? ORDER BY song_count DESC LIMIT 40');
            $q->execute([$user]);
            $locaux = array_merge($locaux, $q->fetchAll(PDO::FETCH_ASSOC));
        }
        $l = [];
        foreach ($locaux as $r) {
            $cle = Gouts::cle($r['name']);
            if (isset($vus[$cle]) || isset($rejetes[(int)$r['id']]) || Gouts::artisteVide((string)$r['name'])) continue;
            $vus[$cle] = true;
            $l[] = self::bulle($cle, $r['name'], null, $biblio, $choix);
        }

        // Les artistes d'ailleurs du dernier calcul.
        $q = $db->prepare("SELECT contenu FROM gouts_rayons WHERE user = ? AND type = 'ailleurs' LIMIT 1");
        $q->execute([$user]);
        $e = [];
        foreach ((json_decode((string)$q->fetchColumn(), true)['artistes'] ?? []) as $a) {
            $cle = Gouts::cle($a['nom']);
            if (isset($vus[$cle])) continue;
            $vus[$cle] = true;
            $e[] = self::bulle($cle, $a['nom'], $a['image'] ?? null, $biblio, $choix);
        }

        // Mêlés : trois de la bibliothèque, un d'ailleurs.
        $reste = max(0, $n - count($out));
        $i = 0;
        while ($reste > 0 && ($l !== [] || $e !== [])) {
            $pris = ($i++ % 4 === 3 && $e !== []) || $l === [] ? array_shift($e) : array_shift($l);
            $out[] = $pris;
            $reste--;
        }
        return self::relier($db, $out);
    }

    /** Les artistes écartés (« Pas pour moi ») : id => true. */
    private static function rejetes(PDO $db, string $user): array
    {
        $q = $db->prepare("SELECT cible_id FROM gouts_rejets WHERE user = ? AND type = 'artist'");
        $q->execute([$user]);
        return array_fill_keys(array_map('intval', $q->fetchAll(PDO::FETCH_COLUMN)), true);
    }

    /** Les proches de plusieurs artistes d'un coup : clé => [proches, du plus proche au moins]. */
    private static function voisinsDe(PDO $db, array $cles): array
    {
        $out = [];
        foreach (array_chunk(array_map('strval', $cles), 200) as $lot) {
            $in = implode(',', array_fill(0, count($lot), '?'));
            $q = $db->prepare("SELECT cle, voisin_cle, voisin_nom, image FROM artistes_similaires
                                WHERE cle IN ($in) ORDER BY score DESC");
            $q->execute($lot);
            while ($r = $q->fetch(PDO::FETCH_ASSOC)) {
                $r['voisin_cle'] = (string)$r['voisin_cle'];
                $out[(string)$r['cle']][] = $r;
            }
        }
        return $out;
    }

    private static function dejaCherche(PDO $db, string $cle): bool
    {
        $q = $db->prepare('SELECT 1 FROM artistes_enrichis WHERE cle = ?');
        $q->execute([$cle]);
        return (bool)$q->fetchColumn();
    }

    /** Deux tiers de la bibliothèque, un tiers d'ailleurs, quand on peut. */
    private static function melanger(array $dedans, array $dehors, int $n): array
    {
        if ($n <= 0) return [];
        $nDedans = min(count($dedans), max($n - count($dehors), (int)ceil($n * 2 / 3)));
        return array_slice(array_merge(array_slice($dedans, 0, $nDedans), $dehors, array_slice($dedans, $nDedans)), 0, $n);
    }

    /** Les fils du réseau : pour chaque bulle, les bulles à l'écran qui lui sont proches. */
    private static function relier(PDO $db, array $bulles): array
    {
        $ecran = array_fill_keys(array_column($bulles, 'cle'), true);
        $voisins = self::voisinsDe($db, array_keys($ecran));
        foreach ($bulles as &$b) {
            $liens = [];
            foreach ($voisins[$b['cle']] ?? [] as $p) {
                if ($p['voisin_cle'] !== $b['cle'] && isset($ecran[$p['voisin_cle']])) $liens[] = $p['voisin_cle'];
            }
            $b['liens'] = array_values(array_unique($liens));
        }
        unset($b);
        return $bulles;
    }

    /**
     * Ce qui éclot à côté d'une bulle qu'on vient d'aimer : ses artistes
     * proches, dans la bibliothèque d'abord, puis hors d'elle.
     *
     * @param string[] $deja clés déjà à l'écran
     */
    public static function autour(PDO $db, string $user, string $cle, string $nom, array $deja, int $n = 6): array
    {
        $proches = self::similaires($db, $cle);
        if ($proches === [] && $nom !== '') {
            // Jamais décrit (artiste tout juste cherché) : on le décrit maintenant.
            GoutsSources::enrichirUn($db, $nom);
            $proches = self::similaires($db, $cle);
        }
        $biblio = self::bibliotheque($db, $user);
        $choix = Gouts::choix($db, $user);
        $deja = array_fill_keys($deja, true);
        $dedans = [];
        $dehors = [];
        foreach ($proches as $p) {
            if (isset($deja[$p['voisin_cle']]) || isset($choix[$p['voisin_cle']])) continue;
            $b = self::bulle($p['voisin_cle'], $p['voisin_nom'], $p['image'], $biblio, $choix);
            if ($b['artistId'] !== null) $dedans[] = $b; else $dehors[] = $b;
        }
        return self::melanger($dedans, $dehors, $n);
    }

    private static function similaires(PDO $db, string $cle): array
    {
        $q = $db->prepare('SELECT voisin_cle, voisin_nom, image FROM artistes_similaires WHERE cle = ? ORDER BY score DESC LIMIT 40');
        $q->execute([$cle]);
        return $q->fetchAll(PDO::FETCH_ASSOC);
    }

    /** Chercher un artiste : la bibliothèque d'abord, le monde ensuite. */
    public static function chercher(PDO $db, string $user, string $texte): array
    {
        $texte = trim($texte);
        if (mb_strlen($texte) < 2) return [];
        $biblio = self::bibliotheque($db, $user);
        $choix = Gouts::choix($db, $user);
        $out = [];
        $vus = [];
        $q = $db->prepare('SELECT name FROM artists WHERE user = ? AND name LIKE ? ORDER BY song_count DESC LIMIT 8');
        $q->execute([$user, '%' . $texte . '%']);
        foreach ($q->fetchAll(PDO::FETCH_COLUMN) as $nom) {
            $cle = Gouts::cle($nom);
            if (isset($vus[$cle]) || Gouts::artisteVide((string)$nom)) continue;
            $vus[$cle] = true;
            $out[] = self::bulle($cle, $nom, null, $biblio, $choix);
        }
        foreach (GoutsSources::chercherArtistes($texte, 8) as $a) {
            $cle = Gouts::cle($a['nom']);
            if (isset($vus[$cle])) continue;
            $vus[$cle] = true;
            $out[] = self::bulle($cle, $a['nom'], $a['image'], $biblio, $choix);
        }
        return $out;
    }

    /**
     * Aimer (1), adorer (2) ou retirer (0) un artiste. Un artiste hors
     * bibliothèque jamais décrit l'est tout de suite : sans ses voisins, il ne
     * servirait à rien.
     */
    public static function choisir(PDO $db, string $user, string $nom, int $niveau, ?string $image): array
    {
        $nom = trim($nom);
        if ($nom === '' || mb_strlen($nom) > 255) throw new InvalidArgumentException('Nom d\'artiste invalide');
        $cle = Gouts::cle($nom);
        $niveau = max(0, min(2, $niveau));
        if ($niveau === 0) {
            $db->prepare('DELETE FROM gouts_choix WHERE user = ? AND cle = ?')->execute([$user, $cle]);
        } else {
            if ($image !== null && !preg_match('#^https?://#', $image)) $image = null; // les photos locales se recalculent
            $db->prepare('INSERT INTO gouts_choix (user, cle, nom, niveau, image) VALUES (?, ?, ?, ?, ?)
                          ON DUPLICATE KEY UPDATE niveau = VALUES(niveau), nom = VALUES(nom), image = COALESCE(VALUES(image), image)')
               ->execute([$user, $cle, $nom, $niveau, $image !== null ? mb_substr($image, 0, 500) : null]);
            if (self::similaires($db, $cle) === []) GoutsSources::enrichirUn($db, $nom);
        }
        return ['cle' => $cle, 'niveau' => $niveau];
    }
}
