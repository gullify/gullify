<?php
/**
 * Pour toi — la lecture automatique sort de la bibliothèque (serveur 1.21.0).
 *
 * Quand la bibliothèque n'a plus rien de proche de ce qui joue, la suite
 * passe par les liens de « Tes artistes » (`artistes_similaires`, Last.fm ou
 * YouTube Music) : des artistes proches qu'on n'a pas, tirés au hasard selon
 * leur proximité, et un de leurs titres connus, écouté à la pièce comme dans
 * la recherche — YouTube Music d'abord, Bandcamp en repli.
 *
 * Ce qui est proche ET déjà dans la bibliothèque n'en sort pas : il est rendu
 * à GoutsRadio (`dedans`), qui le joue depuis les fichiers.
 */
require_once __DIR__ . '/Gouts.php';
require_once __DIR__ . '/GoutsSources.php';
require_once __DIR__ . '/Bandcamp.php';

class GoutsAilleurs
{
    /** Au plus ce nombre de titres d'ailleurs par appel (chacun coûte une recherche). */
    public const MAX = 5;

    /** Combien de temps garder les titres d'un artiste (secondes). */
    private const CACHE_TTL = 14 * 86400;
    private const CACHE_TTL_VIDE = 86400;

    /**
     * Les artistes proches de ces graines.
     *
     * @param string[] $noms noms des artistes qui jouent ou viennent de jouer (le plus récent en dernier)
     * @return array{dedans: array<int,float>, dehors: array<string, array{nom:string, w:float, racine:string}>}
     *   dedans : id d'artiste de la bibliothèque => proximité ; dehors : clé => artiste d'ailleurs
     */
    public static function proches(PDO $db, string $user, array $noms): array
    {
        $noms = array_values(array_unique(array_filter(array_map('trim', $noms),
            fn($n) => $n !== '' && !Gouts::artisteVide($n))));
        $noms = array_slice($noms, -3);
        $biblio = self::bibliotheque($db, $user);
        $rejetes = self::rejetes($db, $user);
        $choix = Gouts::choix($db, $user);
        $dedans = [];
        $dehors = [];
        $poids = [1.0, 0.55, 0.35];
        $decrits = 0;

        foreach (array_reverse($noms) as $i => $nom) {
            $w = $poids[$i] ?? 0.3;
            $cle = Gouts::cle($nom);
            $proches = self::similaires($db, $cle);
            // Jamais décrit (artiste entendu sur YouTube, pas encore chez soi) :
            // on le décrit maintenant, un seul par appel pour rester rapide.
            if ($proches === [] && $decrits < 1 && !self::dejaCherche($db, $cle)) {
                $decrits++;
                GoutsSources::enrichirUn($db, $nom);
                $proches = self::similaires($db, $cle);
            }
            $max = max(0.0001, ...array_map(fn($p) => (float)$p['score'], $proches ?: [['score' => 1]]));
            // La graine elle-même, si on ne l'a pas : d'autres titres d'elle.
            if (!isset($biblio[$cle])) {
                $dehors[$cle] = ['nom' => $nom, 'w' => max($dehors[$cle]['w'] ?? 0, 0.45 * $w), 'racine' => $nom];
            }
            foreach ($proches as $p) {
                $vc = (string)$p['voisin_cle'];
                $vn = (string)$p['voisin_nom'];
                if ($vc === '' || Gouts::artisteVide($vn)) continue;
                $s = $w * (0.35 + 0.65 * (float)$p['score'] / $max);
                // Un artiste aimé dans « Tes artistes » passe devant.
                if (isset($choix[$vc])) $s *= 1 + 0.4 * $choix[$vc]['niveau'];
                if (isset($biblio[$vc])) {
                    $id = $biblio[$vc];
                    if (isset($rejetes[$id])) continue;
                    $dedans[$id] = max($dedans[$id] ?? 0, min(1.0, $s));
                } elseif (!isset($dehors[$vc]) || $dehors[$vc]['w'] < $s) {
                    $dehors[$vc] = ['nom' => $vn, 'w' => $s, 'racine' => $nom];
                }
            }
        }

        // Rien de connu autour (graines jamais décrites, pas de réseau) : les
        // artistes aimés dans « Tes artistes » qu'on n'a pas encore.
        $graines = array_fill_keys(array_map([Gouts::class, 'cle'], $noms), true);
        if ($dedans === [] && array_diff_key($dehors, $graines) === [] && $noms !== []) {
            foreach ($choix as $cle => $c) {
                $cle = (string)$cle;
                if ($c['niveau'] <= 0 || isset($biblio[$cle]) || isset($dehors[$cle])) continue;
                $dehors[$cle] = ['nom' => $c['nom'], 'w' => 0.3 * $c['niveau'], 'racine' => ''];
            }
        }
        return ['dedans' => $dedans, 'dehors' => $dehors];
    }

    /**
     * Des titres d'artistes d'ailleurs, un par artiste, tirés selon la proximité.
     *
     * @param array<string, array{nom:string, w:float, racine:string}> $dehors
     * @param string[] $exclus déjà en file : `yt:<videoId>`, `bc:<id du titre>`
     * @return array<array<string,mixed>> fiches prêtes pour l'app (`externe` = youtube|bandcamp)
     */
    public static function titres(array $dehors, array $exclus, int $n, string $famille = 'auto'): array
    {
        $n = max(0, min(self::MAX, $n));
        if ($n === 0 || $dehors === []) return [];
        $exclus = array_fill_keys($exclus, true);

        // Tirage pondéré sans remise (Efraimidis–Spirakis), avec deux artistes
        // de réserve pour encaisser les recherches vides.
        $cles = [];
        foreach ($dehors as $cle => $a) {
            $u = max(1e-9, mt_rand() / mt_getrandmax());
            $cles[$cle] = log($u) / max(0.01, $a['w']);
        }
        arsort($cles);
        $tires = array_slice(array_keys($cles), 0, min(10, $n + 2));

        $parNom = [];
        foreach ($tires as $cle) $parNom[$dehors[$cle]['nom']] = $cle;
        $titres = self::titresConnus(array_keys($parNom));

        $out = [];
        foreach ($tires as $cle) {
            if (count($out) >= $n) break;
            $a = $dehors[$cle];
            $liste = array_values(array_filter($titres[$a['nom']] ?? [],
                fn($t) => !isset($exclus[$t['cleFile']])));
            if ($liste === []) continue;
            // Les plus connus d'abord, sans jouer toujours le même : on tire
            // parmi les cinq premiers, le premier plus souvent.
            $k = min(count($liste), 5);
            $i = (int)floor($k * (mt_rand() / mt_getrandmax()) ** 1.6);
            $t = $liste[min($i, $k - 1)];
            $exclus[$t['cleFile']] = true;
            $raison = $a['racine'] === ''
                ? 'Un artiste que tu aimes, pas encore chez toi'
                : (Gouts::cle($a['racine']) === $cle ? 'Encore ' . $a['nom'] . ', hors de ta bibliothèque'
                                                     : 'Proche de ' . $a['racine'] . ', hors de ta bibliothèque');
            unset($t['cleFile']);
            $out[] = $t + ['raison' => $raison, 'origin' => "$famille:ailleurs"];
        }
        return $out;
    }

    /**
     * Les titres connus de ces artistes : cache, puis YouTube Music (un seul
     * processus pour tous), puis Bandcamp pour ceux que YouTube ignore.
     *
     * @param string[] $noms
     * @return array<string, array<array<string,mixed>>>
     */
    public static function titresConnus(array $noms): array
    {
        $out = [];
        $manquants = [];
        foreach ($noms as $nom) {
            $c = self::lireCache($nom);
            if ($c !== null) $out[$nom] = $c; else $manquants[] = $nom;
        }
        if ($manquants !== []) {
            $yt = self::youtube($manquants);
            foreach ($manquants as $nom) {
                $liste = $yt[$nom] ?? [];
                if ($liste === []) $liste = self::bandcamp($nom);
                // YouTube muet pour tout le monde (anti-robot, réseau) : on ne
                // retient pas ce vide-là, il ne dit rien de l'artiste.
                if ($liste !== [] || $yt !== null) self::ecrireCache($nom, $liste);
                $out[$nom] = $liste;
            }
        }
        return $out;
    }

    /** @return array<string, array>|null null si YouTube Music n'a pas répondu du tout */
    private static function youtube(array $noms): ?array
    {
        $script = AppConfig::getPythonPath() . '/ytmusic_search.py';
        $python = file_exists('/opt/ytdlp/bin/python3') ? '/opt/ytdlp/bin/python3' : 'python3';
        $cmd = $python . ' ' . escapeshellarg($script) . ' top_songs '
             . escapeshellarg(json_encode(array_values($noms), JSON_UNESCAPED_UNICODE)) . ' 8 2>/dev/null';
        $sortie = shell_exec($cmd);
        $data = is_string($sortie) ? json_decode($sortie, true) : null;
        if (!is_array($data) || !is_array($data['artistes'] ?? null)) return null;
        $out = [];
        foreach ($data['artistes'] as $nom => $liste) {
            foreach ((array)$liste as $s) {
                $id = (string)($s['videoId'] ?? '');
                if ($id === '' || ($s['title'] ?? '') === '') continue;
                $duree = self::secondes((string)($s['duration'] ?? ''));
                if ($duree > 0 && ($duree < 60 || $duree > 900)) continue; // interludes, mixes d'une heure
                $out[$nom][] = [
                    'externe' => 'youtube', 'videoId' => $id, 'cleFile' => "yt:$id",
                    'title' => (string)$s['title'], 'artist' => (string)($s['artist'] ?? $nom),
                    'album' => (string)($s['album'] ?? ''), 'thumbnail' => (string)($s['thumbnail'] ?? ''),
                    'duration' => $duree, 'url' => "https://music.youtube.com/watch?v=$id",
                ];
            }
        }
        return $out;
    }

    private static function bandcamp(string $nom): array
    {
        try {
            $songs = Bandcamp::searchSongs($nom, 15);
        } catch (Throwable $e) {
            return [];
        }
        $voulu = Gouts::cle($nom);
        $out = [];
        foreach ($songs as $s) {
            if (Gouts::cle($s['artist']) !== $voulu || $s['itemId'] <= 0 || $s['bandId'] <= 0) continue;
            $out[] = [
                'externe' => 'bandcamp', 'trackId' => $s['itemId'], 'bandId' => $s['bandId'],
                'cleFile' => 'bc:' . $s['itemId'],
                'title' => $s['title'], 'artist' => $s['artist'], 'album' => $s['album'],
                'thumbnail' => $s['thumbnail'], 'duration' => 0, 'url' => $s['url'],
            ];
            if (count($out) >= 8) break;
        }
        return $out;
    }

    /** « 3:45 » ou « 1:02:03 » → secondes. */
    public static function secondes(string $d): int
    {
        if (!preg_match('/^\d+(:\d{1,2}){0,2}$/', trim($d))) return 0;
        $s = 0;
        foreach (explode(':', trim($d)) as $p) $s = $s * 60 + (int)$p;
        return $s;
    }

    // ── Cache des titres par artiste (fichiers, perdus au redémarrage : sans gravité) ──

    private static function fichierCache(string $nom): string
    {
        $dir = sys_get_temp_dir() . '/gullify-ailleurs';
        if (!is_dir($dir)) @mkdir($dir, 0775, true);
        return $dir . '/' . md5(Gouts::cle($nom)) . '.json';
    }

    private static function lireCache(string $nom): ?array
    {
        $f = self::fichierCache($nom);
        $brut = is_file($f) ? @file_get_contents($f) : false;
        if ($brut === false) return null;
        $c = json_decode($brut, true);
        if (!is_array($c) || !isset($c['t'], $c['titres'])) return null;
        $ttl = $c['titres'] === [] ? self::CACHE_TTL_VIDE : self::CACHE_TTL;
        return time() - (int)$c['t'] < $ttl ? $c['titres'] : null;
    }

    private static function ecrireCache(string $nom, array $titres): void
    {
        @file_put_contents(self::fichierCache($nom),
            json_encode(['t' => time(), 'titres' => $titres], JSON_UNESCAPED_UNICODE), LOCK_EX);
    }

    // ── Petites lectures ──

    /** clé => id d'artiste de la bibliothèque. */
    private static function bibliotheque(PDO $db, string $user): array
    {
        $q = $db->prepare('SELECT id, name FROM artists WHERE user = ?');
        $q->execute([$user]);
        $out = [];
        foreach ($q->fetchAll(PDO::FETCH_ASSOC) as $r) {
            if (Gouts::artisteVide((string)$r['name'])) continue;
            $out[Gouts::cle($r['name'])] ??= (int)$r['id'];
        }
        return $out;
    }

    private static function rejetes(PDO $db, string $user): array
    {
        $q = $db->prepare("SELECT cible_id FROM gouts_rejets WHERE user = ? AND type = 'artist'");
        $q->execute([$user]);
        return array_fill_keys(array_map('intval', $q->fetchAll(PDO::FETCH_COLUMN)), true);
    }

    private static function similaires(PDO $db, string $cle): array
    {
        $q = $db->prepare('SELECT voisin_cle, voisin_nom, score FROM artistes_similaires WHERE cle = ? ORDER BY score DESC LIMIT 30');
        $q->execute([$cle]);
        return $q->fetchAll(PDO::FETCH_ASSOC);
    }

    private static function dejaCherche(PDO $db, string $cle): bool
    {
        $q = $db->prepare('SELECT 1 FROM artistes_enrichis WHERE cle = ?');
        $q->execute([$cle]);
        return (bool)$q->fetchColumn();
    }
}
