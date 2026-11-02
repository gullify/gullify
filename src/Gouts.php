<?php
/**
 * Pour toi — le profil de goûts d'une personne.
 *
 * Ce que font les grands (Spotify, Deezer Flow, YouTube Music), ramené à une
 * maison qui n'a qu'une poignée d'auditeurs, chacun avec SA bibliothèque :
 *
 *  - Signaux implicites pesés : un titre fini compte, un « suivant » pressé
 *    dans les trente premières secondes est un refus (le seuil d'une « écoute »
 *    chez Spotify), un saut de moins de cinq secondes encore plus (gouts_sauts).
 *    Signaux explicites : favoris (titre, album, artiste), listes, « Pas pour
 *    moi » (gouts_rejets, comme le bannissement de Deezer).
 *  - Amortissement : une écoute perd la moitié de son poids en 60 jours. Les
 *    goûts bougent, le profil suit.
 *  - Le filtrage collaboratif, qu'une maison ne peut pas faire seule, vient du
 *    monde : les artistes similaires et les étiquettes de Last.fm (des millions
 *    d'auditeurs), à défaut YouTube Music et MusicBrainz (GoutsSources).
 *    S'y ajoutent les enchaînements que la personne fait elle-même.
 *
 * Calculé la nuit par scripts/analyser-gouts.php ; la lecture automatique
 * (GoutsRadio) y ajoute à la volée ce qui se passe dans la séance.
 */
require_once __DIR__ . '/AppConfig.php';

class Gouts
{
    /** Demi-vie d'une écoute, en jours. */
    public const DEMI_VIE = 60;

    /** Faux artistes des compilations : ni goût, ni voisin, ni suggestion. */
    public const ARTISTES_VIDES = ['various artists', 'various', 'artistes divers', 'artistes variés', 'va', 'unknown artist', 'artiste inconnu', ''];

    public static function artisteVide(string $nom): bool
    {
        return in_array(mb_strtolower(trim($nom), 'UTF-8'), self::ARTISTES_VIDES, true);
    }

    /** Les sources de la lecture automatique, que le bandit apprend à doser. */
    public const BRAS = ['artiste', 'voisins', 'sequence', 'favoris', 'decouverte'];

    /** Mêmes CREATE que setup/schema.sql, pour les bases déjà installées. */
    private const TABLES = [
        "CREATE TABLE IF NOT EXISTS artistes_enrichis (
            cle VARCHAR(191) PRIMARY KEY, nom VARCHAR(255) NOT NULL, source VARCHAR(20) NULL,
            trouve TINYINT(1) NOT NULL DEFAULT 0, maj DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
        "CREATE TABLE IF NOT EXISTS artistes_similaires (
            cle VARCHAR(191) NOT NULL, voisin_cle VARCHAR(191) NOT NULL, voisin_nom VARCHAR(255) NOT NULL,
            score FLOAT NOT NULL, image VARCHAR(500) NULL,
            PRIMARY KEY (cle, voisin_cle), INDEX idx_artsim_voisin (voisin_cle)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
        "CREATE TABLE IF NOT EXISTS artistes_tags (
            cle VARCHAR(191) NOT NULL, tag VARCHAR(100) NOT NULL, poids FLOAT NOT NULL,
            PRIMARY KEY (cle, tag), INDEX idx_arttag_tag (tag)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
        "CREATE TABLE IF NOT EXISTS gouts_profil (
            user VARCHAR(50) NOT NULL, type VARCHAR(10) NOT NULL, cle VARCHAR(191) NOT NULL,
            score FLOAT NOT NULL, ecoutes INT NOT NULL DEFAULT 0, sauts INT NOT NULL DEFAULT 0,
            PRIMARY KEY (user, type, cle)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
        "CREATE TABLE IF NOT EXISTS gouts_titres (
            user VARCHAR(50) NOT NULL, song_id INT NOT NULL, score FLOAT NOT NULL,
            finis INT NOT NULL DEFAULT 0, sauts INT NOT NULL DEFAULT 0, dernier DATETIME NULL,
            PRIMARY KEY (user, song_id), INDEX idx_gtitres_song (song_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
        "CREATE TABLE IF NOT EXISTS gouts_voisins (
            user VARCHAR(50) NOT NULL, artist_id INT NOT NULL, voisin_id INT NOT NULL, score FLOAT NOT NULL,
            PRIMARY KEY (user, artist_id, voisin_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
        "CREATE TABLE IF NOT EXISTS gouts_rayons (
            id INT AUTO_INCREMENT PRIMARY KEY, user VARCHAR(50) NOT NULL, type VARCHAR(20) NOT NULL,
            rang INT NOT NULL DEFAULT 0, titre VARCHAR(120) NOT NULL, sous_titre VARCHAR(255) NULL,
            contenu JSON NOT NULL, cree_le DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_grayons_user (user, type, rang)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
        "CREATE TABLE IF NOT EXISTS gouts_rejets (
            user VARCHAR(50) NOT NULL, type VARCHAR(10) NOT NULL, cible_id INT NOT NULL,
            cree_le DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (user, type, cible_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
        "CREATE TABLE IF NOT EXISTS gouts_choix (
            user VARCHAR(50) NOT NULL, cle VARCHAR(191) NOT NULL, nom VARCHAR(255) NOT NULL,
            niveau TINYINT NOT NULL DEFAULT 1, image VARCHAR(500) NULL,
            cree_le DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (user, cle)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
        "CREATE TABLE IF NOT EXISTS gouts_bandits (
            user VARCHAR(50) NOT NULL, bras VARCHAR(20) NOT NULL,
            succes FLOAT NOT NULL DEFAULT 1, echecs FLOAT NOT NULL DEFAULT 1, PRIMARY KEY (user, bras)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
        "CREATE TABLE IF NOT EXISTS gouts_sauts (
            id BIGINT AUTO_INCREMENT PRIMARY KEY, user VARCHAR(50) NOT NULL, song_id INT NOT NULL,
            duree INT NOT NULL DEFAULT 0, origin VARCHAR(40) NULL,
            saute_le DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, INDEX idx_gsauts_user (user, saute_le)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
        "CREATE TABLE IF NOT EXISTS gouts_reglages (
            user VARCHAR(50) PRIMARY KEY, aventure FLOAT NOT NULL DEFAULT 0.35,
            portrait TEXT NULL, decalage SMALLINT NULL, analyse_le DATETIME NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
    ];

    /** Les tables de goûts propres à une personne (suppression de compte). */
    public const TABLES_PERSONNE = [
        'gouts_profil', 'gouts_titres', 'gouts_voisins', 'gouts_rayons',
        'gouts_rejets', 'gouts_bandits', 'gouts_sauts', 'gouts_reglages', 'gouts_choix',
    ];

    private static bool $tablesOk = false;

    public static function assurerTables(PDO $db): void
    {
        if (self::$tablesOk) return;
        foreach (self::TABLES as $sql) $db->exec($sql);
        self::$tablesOk = true;
    }

    /**
     * Clé d'un nom d'artiste : sans accents, casse, ponctuation ni « The »,
     * pour que « Les Cowboys Fringants » de la bibliothèque retrouve celui de
     * Last.fm.
     */
    public static function cle(string $nom): string
    {
        $s = mb_strtolower(trim($nom), 'UTF-8');
        $t = @iconv('UTF-8', 'ASCII//TRANSLIT//IGNORE', $s);
        if (is_string($t) && $t !== '') $s = $t;
        $s = str_replace('&', ' and ', $s);
        $s = preg_replace('/^the\s+/', '', $s);
        $s = preg_replace('/[^a-z0-9]+/', '', $s);
        return substr($s !== '' ? $s : md5($nom), 0, 191);
    }

    /** Une origine lisible ou rien : `mix:2`, `auto:voisins`, `decouvertes`… */
    public static function origineValide(mixed $o): ?string
    {
        if (!is_string($o)) return null;
        $o = strtolower(trim($o));
        return preg_match('/^[a-z_]{2,20}(:[a-z0-9_]{1,18})?$/', $o) ? $o : null;
    }

    /**
     * Poids d'une écoute, de −1,2 (sauté net) à +1 (écouté jusqu'au bout).
     *
     * @param ?int $skipped 1 « suivant » pressé, 0 interrompu autrement (nouvelle
     *                      file, fermeture), null client d'avant qui ne le dit pas.
     */
    public static function poidsEcoute(int $joue, int $duree, bool $fini, ?int $skipped): float
    {
        if ($fini) return 1.0;
        $f = $duree > 0 ? min(1.0, $joue / $duree) : 0.5;
        if ($skipped === 1) {
            if ($joue < 10) return -1.0;
            if ($joue < 30) return -0.8;
            return $f < 0.5 ? -0.35 : 0.2;
        }
        if ($skipped === 0) {
            // Changer de file n'est pas un jugement sur le titre.
            return $f >= 0.5 ? 0.6 : 0.0;
        }
        if ($joue < 30) return -0.5;
        return $f < 0.5 ? -0.15 : 0.5;
    }

    /** Amortissement d'une écoute vieille de $jours. */
    public static function amorti(float $jours): float
    {
        return 0.5 ** (max(0.0, $jours) / self::DEMI_VIE);
    }

    /**
     * Ce que la lecture automatique apprend d'une écoute : le bras qui a
     * proposé le titre gagne (fini, ou écouté une minute sans sauter) ou perd
     * (sauté avant trente secondes). Ne lève jamais : une écoute se compte
     * même si l'apprentissage échoue.
     */
    public static function apprendre(PDO $db, string $user, ?string $origin, bool $fini, bool $saute, int $joue): void
    {
        if ($user === '' || $origin === null || !str_contains($origin, ':')) return;
        [$famille, $bras] = explode(':', $origin, 2);
        if (!in_array($famille, ['auto', 'radio'], true) || !in_array($bras, self::BRAS, true)) return;
        $succes = $fini || ($joue >= 60 && !$saute);
        $echec  = $saute && $joue < 30;
        if (!$succes && !$echec) return;
        try {
            self::assurerTables($db);
            $db->prepare(
                'INSERT INTO gouts_bandits (user, bras, succes, echecs) VALUES (?, ?, ?, ?)
                 ON DUPLICATE KEY UPDATE succes = succes + VALUES(succes) - 1, echecs = echecs + VALUES(echecs) - 1'
            )->execute([$user, $bras, $succes ? 2 : 1, $echec ? 2 : 1]);
            // Mémoire bornée : au-delà de 150 essais, on ramène à l'échelle,
            // pour que le bandit suive un goût qui change.
            $db->prepare(
                'UPDATE gouts_bandits SET succes = succes * 0.5 + 0.5, echecs = echecs * 0.5 + 0.5
                 WHERE user = ? AND bras = ? AND succes + echecs > 150'
            )->execute([$user, $bras]);
        } catch (Throwable $e) {
            error_log('Gouts::apprendre : ' . $e->getMessage());
        }
    }

    // ───────────────────────────────────────────── analyse de nuit ──

    /**
     * Interprète d'une piste (ids d'artistes de la personne), même règle que
     * TRACK_ARTIST_ID : l'artiste lié, sinon celui de l'album quand la piste
     * n'en nomme pas d'autre.
     */
    public const SQL_INTERPRETE = "COALESCE(s.artist_id, CASE
        WHEN NULLIF(s.track_artist, '') IS NULL OR s.track_artist = a.name THEN a.id END)";

    /**
     * Recalcule le profil d'une personne : titres, artistes, étiquettes,
     * genres, puis les voisins entre ses artistes.
     *
     * @return array{ecoutes:int, titres:int, artistes:int, tags:int, voisins:int}
     */
    public static function analyserProfil(PDO $db, string $user): array
    {
        self::assurerTables($db);
        $maintenant = time();

        // ── 1. Les écoutes de l'année, pesées et amorties ─────────────────
        $req = $db->prepare("
            SELECT ph.song_id, UNIX_TIMESTAMP(ph.played_at) t, ph.play_duration, ph.completed, ph.skipped,
                   s.duration, " . self::SQL_INTERPRETE . " AS artiste
              FROM play_history ph
              JOIN songs s ON s.id = ph.song_id
              JOIN albums al ON al.id = s.album_id
              JOIN artists a ON a.id = al.artist_id
             WHERE ph.user = ? AND a.user = ? AND ph.played_at > NOW() - INTERVAL 365 DAY");
        $req->execute([$user, $user]);
        $titres = [];   // song_id => [score, finis, sauts, dernier, artiste]
        $n = 0;
        $ajouter = function (int $id, ?int $artiste, float $w, bool $fini, bool $saut, int $t) use (&$titres) {
            $x = &$titres[$id];
            $x ??= ['score' => 0.0, 'finis' => 0, 'sauts' => 0, 'dernier' => 0, 'artiste' => $artiste];
            $x['score'] += $w;
            if ($fini) $x['finis']++;
            if ($saut) $x['sauts']++;
            $x['dernier'] = max($x['dernier'], $t);
        };
        while ($r = $req->fetch(PDO::FETCH_ASSOC)) {
            $n++;
            $skipped = $r['skipped'] === null ? null : (int)$r['skipped'];
            $w = self::poidsEcoute((int)$r['play_duration'], (int)$r['duration'], (bool)$r['completed'], $skipped);
            $w *= self::amorti(($maintenant - (int)$r['t']) / 86400);
            $ajouter((int)$r['song_id'], $r['artiste'] !== null ? (int)$r['artiste'] : null, $w,
                (bool)$r['completed'], $w < -0.3, (int)$r['t']);
        }
        // Les sauts nets (< 5 s), hors historique.
        $req = $db->prepare("
            SELECT g.song_id, UNIX_TIMESTAMP(g.saute_le) t, " . self::SQL_INTERPRETE . " AS artiste
              FROM gouts_sauts g
              JOIN songs s ON s.id = g.song_id
              JOIN albums al ON al.id = s.album_id
              JOIN artists a ON a.id = al.artist_id
             WHERE g.user = ? AND a.user = ? AND g.saute_le > NOW() - INTERVAL 365 DAY");
        $req->execute([$user, $user]);
        while ($r = $req->fetch(PDO::FETCH_ASSOC)) {
            $n++;
            $w = -1.2 * self::amorti(($maintenant - (int)$r['t']) / 86400);
            $ajouter((int)$r['song_id'], $r['artiste'] !== null ? (int)$r['artiste'] : null, $w, false, true, (int)$r['t']);
        }

        // ── 2. Les gestes explicites ────────────────────────────────────────
        $explicite = function (string $sql, float $w) use ($db, $user, $ajouter) {
            $q = $db->prepare($sql);
            $q->execute([$user, $user]);
            while ($r = $q->fetch(PDO::FETCH_ASSOC)) {
                $ajouter((int)$r['id'], $r['artiste'] !== null ? (int)$r['artiste'] : null, $w, false, false, 0);
            }
        };
        $base = "FROM songs s JOIN albums al ON al.id = s.album_id JOIN artists a ON a.id = al.artist_id";
        $interp = self::SQL_INTERPRETE;
        $explicite("SELECT s.id, $interp artiste $base JOIN favorites f ON f.song_id = s.id
                     WHERE f.user = ? AND a.user = ?", 2.5);
        $explicite("SELECT s.id, $interp artiste $base JOIN favorite_albums fa ON fa.album_id = al.id
                     WHERE fa.user = ? AND a.user = ?", 0.8);
        $explicite("SELECT DISTINCT s.id, $interp artiste $base
                      JOIN playlist_songs ps ON ps.song_id = s.id JOIN playlists p ON p.id = ps.playlist_id
                     WHERE p.user = ? AND a.user = ?", 0.8);

        // ── 3. Artistes : la somme de leurs titres, aplatie ─────────────────
        $artistes = []; // id => [raw, ecoutes, sauts]
        foreach ($titres as $t) {
            if ($t['artiste'] === null) continue;
            $x = &$artistes[$t['artiste']];
            $x ??= ['raw' => 0.0, 'ecoutes' => 0, 'sauts' => 0];
            $x['raw'] += $t['score'];
            $x['ecoutes'] += $t['finis'];
            $x['sauts'] += $t['sauts'];
            unset($x);
        }
        $q = $db->prepare('SELECT artist_id FROM favorite_artists WHERE user = ?');
        $q->execute([$user]);
        foreach ($q->fetchAll(PDO::FETCH_COLUMN) as $id) {
            $artistes[(int)$id] ??= ['raw' => 0.0, 'ecoutes' => 0, 'sauts' => 0];
            $artistes[(int)$id]['raw'] += 4.0;
        }
        $q = $db->prepare("SELECT cible_id FROM gouts_rejets WHERE user = ? AND type = 'artist'");
        $q->execute([$user]);
        foreach ($q->fetchAll(PDO::FETCH_COLUMN) as $id) {
            $artistes[(int)$id] ??= ['raw' => 0.0, 'ecoutes' => 0, 'sauts' => 0];
            $artistes[(int)$id]['raw'] -= 8.0;
        }

        // Noms, genres et clés des artistes de la bibliothèque.
        $q = $db->prepare("SELECT a.id, a.name, a.genre FROM artists a WHERE a.user = ?");
        $q->execute([$user]);
        $infos = [];
        foreach ($q->fetchAll(PDO::FETCH_ASSOC) as $r) {
            if (self::artisteVide((string)$r['name'])) {
                unset($artistes[(int)$r['id']]);
                continue;
            }
            $infos[(int)$r['id']] = ['nom' => $r['name'], 'cle' => self::cle($r['name']),
                                      'genre' => self::genreCle((string)$r['genre'])];
        }
        // « Tes artistes » (les bulles) : aimer pèse comme un favori, adorer
        // deux fois plus. Un artiste hors de la bibliothèque passe son goût à
        // ses voisins qui, eux, y sont.
        $parCle = [];
        foreach ($infos as $id => $i) $parCle[$i['cle']] = $id;
        $choix = self::choix($db, $user);
        $exterieurs = [];
        foreach ($choix as $cle => $c) {
            $poids = $c['niveau'] >= 2 ? 9.0 : 4.5;
            if (isset($parCle[$cle])) {
                $id = $parCle[$cle];
                $artistes[$id] ??= ['raw' => 0.0, 'ecoutes' => 0, 'sauts' => 0];
                $artistes[$id]['raw'] += $poids;
            } else {
                $exterieurs[$cle] = $c['niveau'] >= 2 ? 0.9 : 0.6;
            }
        }
        if ($exterieurs !== []) {
            $in = implode(',', array_fill(0, count($exterieurs), '?'));
            $q = $db->prepare("SELECT cle, voisin_cle, score FROM artistes_similaires WHERE cle IN ($in)");
            $q->execute(array_keys($exterieurs));
            while ($r = $q->fetch(PDO::FETCH_ASSOC)) {
                $id = $parCle[$r['voisin_cle']] ?? null;
                if ($id === null) continue;
                $artistes[$id] ??= ['raw' => 0.0, 'ecoutes' => 0, 'sauts' => 0];
                $artistes[$id]['raw'] += 6.0 * $exterieurs[$r['cle']] * (float)$r['score'];
            }
        }

        // Un artiste sans fiche (supprimé depuis) n'a plus rien à dire.
        $artistes = array_intersect_key($artistes, $infos);

        // Étiquettes connues (Last.fm, MusicBrainz) par clé d'artiste.
        $tagsParCle = self::tagsDe($db, array_column($infos, 'cle'));
        $tagsExterieurs = self::tagsDe($db, array_keys($exterieurs));

        // ── 4. Étiquettes et genres : les affinités des artistes, réparties ─
        $tags = [];
        $genres = [];
        foreach ($artistes as $id => $x) {
            $aff = tanh($x['raw'] / 6);
            $artistes[$id]['aff'] = $aff;
            $info = $infos[$id] ?? null;
            if (!$info) continue;
            foreach ($tagsParCle[$info['cle']] ?? [] as $tag => $p) {
                $tags[$tag] = ($tags[$tag] ?? 0) + $aff * $p;
            }
            if ($info['genre'] !== '') $genres[$info['genre']] = ($genres[$info['genre']] ?? 0) + $aff;
        }
        foreach ($exterieurs as $cle => $aff) {
            foreach ($tagsExterieurs[$cle] ?? [] as $tag => $p) $tags[$tag] = ($tags[$tag] ?? 0) + $aff * $p;
        }

        // ── 5. Écriture (remplacement complet, en une transaction) ──────────
        $db->beginTransaction();
        try {
            $db->prepare('DELETE FROM gouts_titres WHERE user = ?')->execute([$user]);
            $db->prepare('DELETE FROM gouts_profil WHERE user = ?')->execute([$user]);
            $ins = $db->prepare('INSERT INTO gouts_titres (user, song_id, score, finis, sauts, dernier)
                                 VALUES (?, ?, ?, ?, ?, ?)');
            foreach ($titres as $id => $t) {
                $ins->execute([$user, $id, round(tanh($t['score'] / 3), 4), $t['finis'], $t['sauts'],
                    $t['dernier'] ? date('Y-m-d H:i:s', $t['dernier']) : null]);
            }
            $ins = $db->prepare('INSERT INTO gouts_profil (user, type, cle, score, ecoutes, sauts)
                                 VALUES (?, ?, ?, ?, ?, ?)');
            foreach ($artistes as $id => $x) {
                $ins->execute([$user, 'artist', (string)$id, round($x['aff'], 4), $x['ecoutes'], $x['sauts']]);
            }
            foreach (self::normaliser($tags, 60) as $tag => $s) $ins->execute([$user, 'tag', $tag, $s, 0, 0]);
            foreach (self::normaliser($genres, 30) as $g => $s) $ins->execute([$user, 'genre', $g, $s, 0, 0]);
            $db->commit();
        } catch (Throwable $e) {
            $db->rollBack();
            throw $e;
        }

        $voisins = self::calculerVoisins($db, $user, $infos, $tagsParCle);

        return ['ecoutes' => $n, 'titres' => count($titres), 'artistes' => count($artistes),
                'tags' => count($tags), 'voisins' => $voisins];
    }

    /** Ramène des scores à [−1, 1] (le plus fort vaut 1) et garde les $n plus nets. */
    private static function normaliser(array $scores, int $n): array
    {
        if ($scores === []) return [];
        $max = max(array_map('abs', $scores)) ?: 1;
        $out = [];
        foreach ($scores as $k => $v) $out[$k] = round($v / $max, 4);
        uasort($out, fn($a, $b) => abs($b) <=> abs($a));
        return array_slice($out, 0, $n, true);
    }

    /** « québécois » → « quebecois » (les clés de la base ignorent les accents). */
    public static function sansAccents(string $s): string
    {
        $t = @iconv('UTF-8', 'ASCII//TRANSLIT//IGNORE', $s);
        return is_string($t) && $t !== '' ? $t : $s;
    }

    /** Un genre de la bibliothèque comme clé (« Punk Rock » = « punk rock »). */
    public static function genreCle(string $g): string
    {
        $g = self::sansAccents(mb_strtolower(trim($g), 'UTF-8'));
        return in_array($g, ['', 'music', 'other', 'miscellaneous', 'unknown', 'divers', 'autre'], true) ? '' : $g;
    }

    /**
     * Étiquettes pesées (0 à 1) par clé d'artiste. Les étiquettes qui ne
     * décrivent pas la musique (« seen live », « favorites »…) sont écartées
     * à l'enrichissement (GoutsSources).
     *
     * @param string[] $cles
     * @return array<string, array<string, float>>
     */
    public static function tagsDe(PDO $db, array $cles): array
    {
        $out = [];
        foreach (array_chunk(array_values(array_unique($cles)), 500) as $lot) {
            $in = implode(',', array_fill(0, count($lot), '?'));
            $q = $db->prepare("SELECT cle, tag, poids FROM artistes_tags WHERE cle IN ($in)");
            $q->execute($lot);
            while ($r = $q->fetch(PDO::FETCH_ASSOC)) $out[$r['cle']][$r['tag']] = (float)$r['poids'];
        }
        return $out;
    }

    /**
     * Les voisins de chaque artiste de la bibliothèque, par un « ou » bruité de
     * quatre indices : similarité du monde (Last.fm / YouTube Music),
     * étiquettes partagées (cosinus TF-IDF : « rock » rapproche moins que
     * « chiac »), même genre, et les enchaînements que la personne fait.
     *
     * @return int le nombre de liens écrits
     */
    public static function calculerVoisins(PDO $db, string $user, array $infos, array $tagsParCle): int
    {
        $parCle = [];
        foreach ($infos as $id => $info) $parCle[$info['cle']][] = $id;
        $ids = array_keys($infos);
        $liens = []; // "a:b" => [ext, tag, genre, co]

        // 1. Le monde.
        foreach (array_chunk(array_keys($parCle), 500) as $lot) {
            $in = implode(',', array_fill(0, count($lot), '?'));
            $q = $db->prepare("SELECT cle, voisin_cle, score FROM artistes_similaires WHERE cle IN ($in)");
            $q->execute($lot);
            while ($r = $q->fetch(PDO::FETCH_ASSOC)) {
                foreach ($parCle[$r['cle']] ?? [] as $a) {
                    foreach ($parCle[$r['voisin_cle']] ?? [] as $b) {
                        if ($a === $b) continue;
                        $s = (float)$r['score'];
                        foreach (["$a:$b", "$b:$a"] as $k) $liens[$k][0] = max($liens[$k][0] ?? 0, $s);
                    }
                }
            }
        }

        // 2. Étiquettes : TF-IDF puis cosinus, par index inversé.
        $nArt = max(1, count($ids));
        $df = [];
        $vec = [];
        foreach ($ids as $id) {
            foreach ($tagsParCle[$infos[$id]['cle']] ?? [] as $tag => $p) $df[$tag] = ($df[$tag] ?? 0) + 1;
        }
        $index = [];
        foreach ($ids as $id) {
            $v = [];
            foreach ($tagsParCle[$infos[$id]['cle']] ?? [] as $tag => $p) {
                if ($df[$tag] < 2) continue; // personne d'autre ne la porte
                $v[$tag] = $p * log(1 + $nArt / $df[$tag]);
            }
            $norme = sqrt(array_sum(array_map(fn($x) => $x * $x, $v)));
            if ($norme <= 0) continue;
            foreach ($v as $tag => $x) {
                $vec[$id][$tag] = $x / $norme;
                $index[$tag][] = $id;
            }
        }
        $dots = [];
        foreach ($index as $tag => $porteurs) {
            if (count($porteurs) > 400) continue; // trop commun pour départager
            foreach ($porteurs as $a) {
                $va = $vec[$a][$tag];
                foreach ($porteurs as $b) {
                    if ($a < $b) $dots["$a:$b"] = ($dots["$a:$b"] ?? 0) + $va * $vec[$b][$tag];
                }
            }
        }
        foreach ($dots as $k => $c) {
            if ($c < 0.15) continue;
            [$a, $b] = explode(':', $k);
            $liens["$a:$b"][1] = $c;
            $liens["$b:$a"][1] = $c;
        }

        // 3. Même genre de bibliothèque (faible : les genres sont larges).
        $parGenre = [];
        foreach ($ids as $id) if ($infos[$id]['genre'] !== '') $parGenre[$infos[$id]['genre']][] = $id;
        foreach ($parGenre as $membres) {
            if (count($membres) > 300 || count($membres) < 2) continue;
            foreach ($membres as $a) foreach ($membres as $b) {
                if ($a !== $b && isset($liens["$a:$b"])) $liens["$a:$b"][2] = 1;
            }
            // Sans autre indice, un genre partagé seul ne fait un voisin que
            // dans un petit genre (≤ 40 artistes) : « Acadien » oui, « Rock » non.
            if (count($membres) <= 40) {
                foreach ($membres as $a) foreach ($membres as $b) if ($a !== $b) $liens["$a:$b"][2] = 1;
            }
        }

        // 4. Ses enchaînements : deux titres finis à moins de 20 min d'écart.
        //    En lecture aléatoire, deux titres se suivent par hasard : un
        //    enchaînement ne compte qu'à partir de la deuxième fois.
        $q = $db->prepare("
            SELECT " . self::SQL_INTERPRETE . " AS artiste, UNIX_TIMESTAMP(ph.played_at) t, ph.completed
              FROM play_history ph JOIN songs s ON s.id = ph.song_id
              JOIN albums al ON al.id = s.album_id JOIN artists a ON a.id = al.artist_id
             WHERE ph.user = ? AND a.user = ? AND ph.played_at > NOW() - INTERVAL 365 DAY
             ORDER BY ph.played_at");
        $q->execute([$user, $user]);
        $prec = null;
        $co = [];
        while ($r = $q->fetch(PDO::FETCH_ASSOC)) {
            if ($r['artiste'] === null || !$r['completed']) { $prec = null; continue; }
            $cur = ['a' => (int)$r['artiste'], 't' => (int)$r['t']];
            if ($prec && $prec['a'] !== $cur['a'] && $cur['t'] - $prec['t'] < 1200) {
                $co["{$prec['a']}:{$cur['a']}"] = ($co["{$prec['a']}:{$cur['a']}"] ?? 0) + 1;
                $co["{$cur['a']}:{$prec['a']}"] = ($co["{$cur['a']}:{$prec['a']}"] ?? 0) + 1;
            }
            $prec = $cur;
        }
        foreach ($co as $k => $c) if ($c >= 2) $liens[$k][3] = min(1.0, ($c - 1) / 3);

        // Fusion et tri : 25 voisins au plus par artiste.
        $parArtiste = [];
        foreach ($liens as $k => $l) {
            $s = 1 - (1 - 0.9 * ($l[0] ?? 0)) * (1 - 0.8 * ($l[1] ?? 0))
                   * (1 - 0.3 * ($l[2] ?? 0)) * (1 - 0.6 * ($l[3] ?? 0));
            if ($s < 0.12) continue;
            [$a, $b] = explode(':', $k);
            $parArtiste[(int)$a][(int)$b] = $s;
        }
        $db->beginTransaction();
        try {
            $db->prepare('DELETE FROM gouts_voisins WHERE user = ?')->execute([$user]);
            $ins = $db->prepare('INSERT INTO gouts_voisins (user, artist_id, voisin_id, score) VALUES (?, ?, ?, ?)');
            $n = 0;
            foreach ($parArtiste as $a => $vs) {
                arsort($vs);
                foreach (array_slice($vs, 0, 25, true) as $b => $s) {
                    $ins->execute([$user, $a, $b, round($s, 4)]);
                    $n++;
                }
            }
            $db->commit();
        } catch (Throwable $e) {
            $db->rollBack();
            throw $e;
        }
        return $n;
    }

    // ───────────────────────────────────────────── lecture rapide ──

    /** Affinités d'artistes de la personne : id => score (−1 à 1). */
    public static function affinitesArtistes(PDO $db, string $user): array
    {
        $q = $db->prepare("SELECT cle, score FROM gouts_profil WHERE user = ? AND type = 'artist'");
        $q->execute([$user]);
        $out = [];
        while ($r = $q->fetch(PDO::FETCH_ASSOC)) $out[(int)$r['cle']] = (float)$r['score'];
        return $out;
    }

    /** Affinités de titres : song_id => [score, finis, sauts, dernier (timestamp)]. */
    public static function affinitesTitres(PDO $db, string $user): array
    {
        $q = $db->prepare('SELECT song_id, score, finis, sauts, UNIX_TIMESTAMP(dernier) d FROM gouts_titres WHERE user = ?');
        $q->execute([$user]);
        $out = [];
        while ($r = $q->fetch(PDO::FETCH_ASSOC)) {
            $out[(int)$r['song_id']] = ['score' => (float)$r['score'], 'finis' => (int)$r['finis'],
                                         'sauts' => (int)$r['sauts'], 'dernier' => (int)$r['d']];
        }
        return $out;
    }

    /** Voisins : artist_id => [voisin_id => score]. */
    public static function voisins(PDO $db, string $user): array
    {
        $q = $db->prepare('SELECT artist_id, voisin_id, score FROM gouts_voisins WHERE user = ?');
        $q->execute([$user]);
        $out = [];
        while ($r = $q->fetch(PDO::FETCH_ASSOC)) $out[(int)$r['artist_id']][(int)$r['voisin_id']] = (float)$r['score'];
        return $out;
    }

    /** Rejets : ['song' => [id => true], 'artist' => [id => true]]. */
    public static function rejets(PDO $db, string $user): array
    {
        $q = $db->prepare('SELECT type, cible_id FROM gouts_rejets WHERE user = ?');
        $q->execute([$user]);
        $out = ['song' => [], 'artist' => []];
        while ($r = $q->fetch(PDO::FETCH_ASSOC)) $out[$r['type']][(int)$r['cible_id']] = true;
        return $out;
    }

    /**
     * Le fuseau de la personne (minutes à ajouter à l'UTC), tel que l'app l'a
     * dit : le serveur et la base vivent en UTC, l'auditeur non.
     */
    public static function decalage(PDO $db, string $user): int
    {
        $q = $db->prepare('SELECT decalage FROM gouts_reglages WHERE user = ?');
        $q->execute([$user]);
        $v = $q->fetchColumn();
        return $v === false || $v === null ? 0 : max(-840, min(840, (int)$v));
    }

    /** « Tes artistes » : clé => [nom, niveau (1 aime, 2 adore), image]. */
    public static function choix(PDO $db, string $user): array
    {
        $q = $db->prepare('SELECT cle, nom, niveau, image FROM gouts_choix WHERE user = ? ORDER BY niveau DESC, cree_le DESC');
        $q->execute([$user]);
        $out = [];
        while ($r = $q->fetch(PDO::FETCH_ASSOC)) {
            $out[$r['cle']] = ['nom' => $r['nom'], 'niveau' => (int)$r['niveau'], 'image' => $r['image']];
        }
        return $out;
    }

    public static function aventure(PDO $db, string $user): float
    {
        $q = $db->prepare('SELECT aventure FROM gouts_reglages WHERE user = ?');
        $q->execute([$user]);
        $v = $q->fetchColumn();
        return $v === false ? 0.35 : max(0.0, min(1.0, (float)$v));
    }
}
