<?php
/**
 * Gullify - Points de transition des titres (idée #79)
 *
 * Le fondu enchaîné de l'app (idée #76) croise deux titres sur une durée fixe,
 * réglée à la main. C'est trop pour un morceau qui s'éteint déjà tout seul en
 * huit secondes, et pas assez pour celui qui s'arrête net. Le serveur mesure
 * donc ce que fait le son AUX BORDS de chaque titre, et l'app taille son
 * croisement dessus.
 *
 * Mesure : ffmpeg rend le niveau RMS du morceau, fenêtre par fenêtre d'une
 * demi-seconde (mono, rééchantillonné à 8 kHz — un niveau moyen n'a pas besoin
 * de mieux). Un titre de quatre minutes s'analyse en moins d'une seconde. De
 * cette courbe on tire trois durées :
 *
 *   - `tail`  : le silence de fin (blanc de fichier). Croiser dessus revient à
 *               croiser sur rien : l'app démarre le suivant AVANT.
 *   - `decay` : la descente naturelle de fin — le temps que le titre passe
 *               sous son plein régime avant de se taire. Long = le morceau
 *               fait déjà son fondu tout seul ; nul = il s'arrête franc, et
 *               c'est là qu'un croisement doit être généreux.
 *   - `lead`  : l'entrée en matière du titre suivant, avant qu'il n'arrive à
 *               plein régime. C'est ce qu'il faut lui donner d'avance pour que
 *               sa première vraie note tombe pile à la fin de la précédente.
 *
 * De la même courbe sortent trois niveaux, en décibels :
 *
 *   - `level` : le niveau de référence du morceau entier (idée #101), celui
 *               auquel il est gravé.
 *   - `end`   : le niveau de sa dernière ligne droite — ce qu'il joue vraiment
 *               pendant qu'on lui passe dessus.
 *   - `start` : le niveau de son entrée, une fois l'intro passée — ce que le
 *               titre entrant fait entendre pendant le croisement.
 *
 * `end` et `start`, et pas `level` des deux côtés : un morceau finit presque
 * toujours plus bas qu'il n'a joué (idée #102).
 *
 * Le résultat est gardé en base (`song_transitions`), la clé portant taille et
 * date du fichier : un titre retagué ou remplacé se réanalyse tout seul.
 *
 * Rien n'est analysé d'office : l'app demande le profil du titre en cours et
 * du suivant, deux par piste, et se rabat sur le fondu réglé à la main quand
 * le serveur ne sait rien dire (fichier sur un stockage distant, ffmpeg en
 * échec, titre trop court).
 */

require_once __DIR__ . '/AppConfig.php';
require_once __DIR__ . '/Storage/StorageInterface.php';
require_once __DIR__ . '/Storage/LocalStorage.php';
require_once __DIR__ . '/Storage/SFTPStorage.php';
require_once __DIR__ . '/Storage/StorageFactory.php';

class TransitionAnalysis
{
    /** Fenêtre d'analyse, en millisecondes (4000 échantillons à 8 kHz). */
    private const WINDOW_MS = 500;

    /** Sous ce niveau absolu, il n'y a plus de musique — que du blanc. */
    private const SILENCE_DB = -45.0;

    /** Un titre discret n'a pas de « silence » à −45 dB : on le juge aussi
     *  relativement à son propre niveau. Le plus strict des deux gagne. */
    private const QUIET_MARGIN_DB = 30.0;

    /** À moins de ça sous son niveau de référence, un titre est à plein
     *  régime. Six décibels, c'est la moitié de l'amplitude : en dessous, on
     *  entend clairement que ça a baissé. */
    private const FULL_MARGIN_DB = 6.0;

    /** Aucune des trois durées rendues ne dépasse ça : au-delà on ne parle
     *  plus de bord de morceau mais de structure. */
    private const MAX_MS = 12000;

    /** Titres plus courts : rien à mesurer, les bords sont tout le morceau. */
    private const MIN_TRACK_MS = 20000;

    /** Sur quelle longueur se mesurent les niveaux de bord (`end`, `start`) :
     *  la part du morceau qu'un croisement recouvre. Le réglage de l'app va
     *  d'une demi-seconde à huit secondes (le double en croisement
     *  intelligent) ; six secondes est le milieu honnête de cet éventail. */
    private const EDGE_MS = 6000;

    /** Avance maximale qu'un titre entrant peut recevoir pour son intro — la
     *  même que `kSmartLeadMax` côté app. Au-delà, l'app ne recule plus le
     *  départ : le croisement tombe donc encore dans l'intro, et c'est là
     *  qu'il faut mesurer `start`. */
    private const LEAD_CAP_MS = 3000;

    /**
     * Les profils de plusieurs titres d'un coup, indexés par id. Un titre
     * inconnu, distant ou impossible à analyser est simplement absent du
     * tableau — l'app sait s'en passer.
     *
     * @param int[] $ids
     * @return array<int, array{tailMs:int, decayMs:int, leadMs:int, levelDb:float, endDb:float, startDb:float}>
     */
    public static function forSongs(PDO $db, string $user, array $ids): array
    {
        $ids = array_values(array_unique(array_filter(
            array_map('intval', $ids),
            static fn(int $id): bool => $id > 0
        )));
        if (!$ids) {
            return [];
        }

        self::ensureTable($db);

        $placeholders = implode(',', array_fill(0, count($ids), '?'));
        $stmt = $db->prepare(
            "SELECT s.id, s.file_path
             FROM songs s
             JOIN albums al ON s.album_id = al.id
             JOIN artists ar ON al.artist_id = ar.id
             WHERE s.id IN ($placeholders) AND ar.user = ?"
        );
        $stmt->execute(array_merge($ids, [$user]));
        $songs = $stmt->fetchAll(PDO::FETCH_ASSOC) ?: [];
        if (!$songs) {
            return [];
        }

        $base = self::userBase($user);
        $out  = [];
        foreach ($songs as $song) {
            $id   = (int)$song['id'];
            $file = self::localFile($base, (string)$song['file_path']);
            if ($file === null) {
                continue; // stockage distant, ou fichier disparu
            }
            $key     = self::fileKey($file);
            $profile = self::cached($db, $id, $key);
            if ($profile === null) {
                $profile = self::measure($file);
                if ($profile === null) {
                    continue;
                }
                self::remember($db, $id, $key, $profile);
            }
            $out[$id] = $profile;
        }

        return $out;
    }

    /**
     * Le profil d'un fichier, mesuré par ffmpeg. Null quand ffmpeg ne rend
     * rien d'exploitable (format illisible, morceau trop court).
     *
     * @return array{tailMs:int, decayMs:int, leadMs:int, levelDb:float, endDb:float, startDb:float}|null
     */
    public static function measure(string $file): ?array
    {
        $levels = self::rmsWindows($file);
        // Il faut de quoi voir un bord : moins de quarante fenêtres (vingt
        // secondes), c'est un jingle, pas un morceau.
        if (count($levels) < self::MIN_TRACK_MS / self::WINDOW_MS) {
            return null;
        }

        // Niveau de référence : le troisième quartile, pas la moyenne. Un
        // morceau qui commence et finit doucement tirerait la moyenne vers le
        // bas, et tout paraîtrait « à plein régime ».
        $sorted = $levels;
        sort($sorted);
        $ref = $sorted[(int)floor(0.75 * (count($sorted) - 1))];

        $floor = max(self::SILENCE_DB, $ref - self::QUIET_MARGIN_DB);
        $full  = $ref - self::FULL_MARGIN_DB;

        $n = count($levels);

        // Silence de fin : les dernières fenêtres sous le plancher.
        $tail = 0;
        while ($tail < $n && $levels[$n - 1 - $tail] <= $floor) {
            $tail++;
        }
        // Un morceau entièrement sous le plancher n'existe pas : on renonce
        // plutôt que de rendre n'importe quoi.
        if ($tail >= $n) {
            return null;
        }

        // Descente de fin : à partir de la dernière fenêtre qui sonne, le
        // temps passé sous le plein régime.
        $decay = 0;
        $i = $n - 1 - $tail;
        while ($i >= 0 && $levels[$i] < $full) {
            $decay++;
            $i--;
        }

        // Entrée en matière : le temps que met le début à atteindre le plein
        // régime (blanc de fichier, montée en puissance, décompte).
        $lead = 0;
        while ($lead < $n && $levels[$lead] < $full) {
            $lead++;
        }

        // Les niveaux de bord (idée #102). Le croisement ne fait pas jouer les
        // morceaux à leur niveau de référence : il fait jouer la FIN de l'un
        // et le DÉBUT de l'autre. Un morceau finit presque toujours plus bas
        // qu'il n'a joué — sur cette bibliothèque, cinq décibels de moins en
        // médiane —, si bien que se comparer aux niveaux de référence fait
        // arriver l'entrant plus fort que ce que le sortant joue à cet
        // instant. C'est exactement là que se mesurent les deux niveaux.
        $edge  = (int)(self::EDGE_MS / self::WINDOW_MS);
        $music = $n - $tail; // première fenêtre du blanc de fin

        // Fin : les dernières fenêtres qui sonnent encore, blanc non compris.
        $endDb = self::energyMean(
            array_slice($levels, max(0, $music - $edge), min($edge, $music))
        );

        // Début : ce qui suit l'intro, dans la limite de l'avance que l'app
        // sait donner. Une intro plus longue que ça et le croisement tombe
        // dedans : autant la mesurer telle qu'elle sera entendue.
        $from    = min($lead, (int)(self::LEAD_CAP_MS / self::WINDOW_MS));
        $startDb = self::energyMean(
            array_slice($levels, $from, max(0, min($edge, $music - $from)))
        );

        return [
            'tailMs'  => self::clampMs($tail * self::WINDOW_MS),
            'decayMs' => self::clampMs($decay * self::WINDOW_MS),
            'leadMs'  => self::clampMs($lead * self::WINDOW_MS),
            'levelDb' => round($ref, 1),
            // Un bord impossible à mesurer (morceau plus court que sa propre
            // intro) retombe sur le niveau de référence : le croisement se
            // comporte alors comme avant l'idée #102.
            'endDb'   => round($endDb ?? $ref, 1),
            'startDb' => round($startDb ?? $ref, 1),
        ];
    }

    /**
     * La moyenne d'une poignée de niveaux en décibels — moyenne des énergies,
     * pas des décibels : c'est ce que veut dire « le niveau de ce passage »,
     * et ça donne le poids qu'il faut aux fenêtres les plus fortes.
     *
     * @param float[] $levels
     */
    private static function energyMean(array $levels): ?float
    {
        if (!$levels) {
            return null;
        }
        $sum = 0.0;
        foreach ($levels as $db) {
            $sum += pow(10, $db / 10);
        }
        $mean = $sum / count($levels);
        // Du silence numérique de bout en bout : on rend le plancher plutôt
        // que le −inf de log10(0).
        return $mean > 0 ? 10 * log10($mean) : -120.0;
    }

    /**
     * Le niveau RMS du fichier, une valeur par fenêtre, en décibels. Le
     * silence numérique (`-inf`) est ramené à −120 dB pour rester comparable.
     *
     * @return float[]
     */
    private static function rmsWindows(string $file): array
    {
        $samples = (int)(8000 * self::WINDOW_MS / 1000);
        $filter  = 'aresample=8000,aformat=channel_layouts=mono'
                 . ',asetnsamples=' . $samples
                 . ',astats=metadata=1:reset=1'
                 . ',ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-';
        $cmd = 'ffmpeg -nostdin -hide_banner -nostats -i ' . escapeshellarg($file)
             . ' -af ' . escapeshellarg($filter)
             . ' -f null - 2>/dev/null';

        $out  = [];
        $code = 0;
        @exec($cmd, $out, $code);
        if ($code !== 0) {
            return [];
        }

        $levels = [];
        foreach ($out as $line) {
            if (strpos($line, 'RMS_level=') === false) {
                continue;
            }
            $value = substr($line, strpos($line, '=') + 1);
            $levels[] = is_numeric($value) ? (float)$value : -120.0;
        }
        return $levels;
    }

    /** Racine locale des fichiers de l'utilisateur, ou null si distante. */
    private static function userBase(string $user): ?string
    {
        try {
            $storage = StorageFactory::forUser($user);
        } catch (Throwable $e) {
            return null;
        }
        // ffmpeg ne sait pas lire un stockage SFTP : ces titres restent sans
        // profil, et l'app garde le fondu réglé à la main.
        if ($storage->getType() !== 'local') {
            return null;
        }
        $base = realpath($storage->getPathBase());
        return $base === false ? null : $base;
    }

    /** Chemin absolu d'un titre, à condition qu'il reste sous sa racine. */
    private static function localFile(?string $base, string $relative): ?string
    {
        if ($base === null || $relative === '') {
            return null;
        }
        $file = realpath($base . '/' . $relative);
        if ($file === false || strpos($file, $base) !== 0) {
            return null;
        }
        return is_file($file) ? $file : null;
    }

    /** Clé du fichier : un titre remplacé ou retagué se réanalyse. */
    private static function fileKey(string $file): string
    {
        return md5(implode('|', [
            $file,
            (string)(@filesize($file) ?: 0),
            (string)(@filemtime($file) ?: 0),
        ]));
    }

    private static function clampMs(int $ms): int
    {
        return max(0, min(self::MAX_MS, $ms));
    }

    private static function ensureTable(PDO $db): void
    {
        static $ready = false;
        if ($ready) {
            return;
        }
        $ready = true;
        $db->exec("
            CREATE TABLE IF NOT EXISTS song_transitions (
                song_id INT NOT NULL PRIMARY KEY,
                file_key CHAR(32) NOT NULL,
                tail_ms INT NOT NULL DEFAULT 0,
                decay_ms INT NOT NULL DEFAULT 0,
                lead_ms INT NOT NULL DEFAULT 0,
                level_db FLOAT NOT NULL DEFAULT 0,
                end_db FLOAT NOT NULL DEFAULT 0,
                start_db FLOAT NOT NULL DEFAULT 0,
                analyzed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ");
        // Les niveaux de bord sont arrivés après (idée #102) : une table déjà
        // là les reçoit ici. MySQL ne connaît pas ADD COLUMN IF NOT EXISTS, on
        // laisse donc l'erreur « colonne déjà présente » passer sans bruit.
        foreach (['end_db', 'start_db'] as $col) {
            try {
                $db->exec(
                    "ALTER TABLE song_transitions
                     ADD COLUMN $col FLOAT NOT NULL DEFAULT 0 AFTER level_db"
                );
            } catch (Throwable $e) {
                // déjà en place
            }
        }
    }

    /**
     * @return array{tailMs:int, decayMs:int, leadMs:int, levelDb:float, endDb:float, startDb:float}|null
     */
    private static function cached(PDO $db, int $songId, string $key): ?array
    {
        $stmt = $db->prepare(
            'SELECT tail_ms, decay_ms, lead_ms, level_db, end_db, start_db
             FROM song_transitions WHERE song_id = ? AND file_key = ?'
        );
        $stmt->execute([$songId, $key]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$row) {
            return null;
        }
        // Un niveau RMS est toujours négatif : zéro, c'est un profil mesuré
        // avant l'idée #102, qui ne connaissait pas les niveaux de bord. On le
        // remesure plutôt que de croiser sur une valeur qu'on n'a pas — ça ne
        // coûte qu'un passage de ffmpeg, une seule fois par titre.
        if ((float)$row['end_db'] >= 0 || (float)$row['start_db'] >= 0) {
            return null;
        }
        return [
            'tailMs'  => (int)$row['tail_ms'],
            'decayMs' => (int)$row['decay_ms'],
            'leadMs'  => (int)$row['lead_ms'],
            'levelDb' => (float)$row['level_db'],
            'endDb'   => (float)$row['end_db'],
            'startDb' => (float)$row['start_db'],
        ];
    }

    /** @param array{tailMs:int, decayMs:int, leadMs:int, levelDb:float, endDb:float, startDb:float} $p */
    private static function remember(PDO $db, int $songId, string $key, array $p): void
    {
        try {
            $stmt = $db->prepare(
                'INSERT INTO song_transitions
                    (song_id, file_key, tail_ms, decay_ms, lead_ms, level_db,
                     end_db, start_db, analyzed_at)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, NOW())
                 ON DUPLICATE KEY UPDATE
                    file_key = VALUES(file_key), tail_ms = VALUES(tail_ms),
                    decay_ms = VALUES(decay_ms), lead_ms = VALUES(lead_ms),
                    level_db = VALUES(level_db), end_db = VALUES(end_db),
                    start_db = VALUES(start_db), analyzed_at = NOW()'
            );
            $stmt->execute([
                $songId, $key, $p['tailMs'], $p['decayMs'], $p['leadMs'],
                $p['levelDb'], $p['endDb'], $p['startDb'],
            ]);
        } catch (Throwable $e) {
            // Une mise en cache qui rate ne doit jamais empêcher de répondre :
            // le titre sera simplement réanalysé la prochaine fois.
            error_log('TransitionAnalysis: cache impossible (' . $e->getMessage() . ')');
        }
    }
}
