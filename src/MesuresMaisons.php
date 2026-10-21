<?php
/**
 * L'historique des maisons GulliOS (GulliOS 1.44), à la Cacti : chaque maison envoie toutes les
 * 5 minutes ses échantillons d'une minute (message signé, voir api/v2/gullios.php action « mesures ») ;
 * ici on les range sans connaître les séries à l'avance :
 *   mesures_brutes  (maison, serie, t, v)                 la minute, 2 jours
 *   mesures_heures  (maison, serie, t, n, somme, mini, maxi) l'heure, 90 jours
 *   mesures_jours   (même forme)                          le jour, 2 ans
 *   mesures_etat    (maison, quand, smart, sauvegarde)    le dernier état connu
 * Les heures et les jours se tiennent à la réception (pas de tâche planifiée) ; un échantillon reçu
 * deux fois (réponse perdue, la maison renvoie) ne compte qu'une fois.
 * Lecture réservée aux maisons Dev : historique(maison, période).
 */
declare(strict_types=1);

require_once __DIR__ . '/AppConfig.php';

final class MesuresMaisons
{
    public const PAR_ENVOI = 500;
    private const SERIES_MAX = 80;
    private const GARDE_BRUTES = 2 * 86400;
    private const GARDE_HEURES = 90 * 86400;
    private const GARDE_JOURS = 2 * 366 * 86400;

    /** période → [table, pas (s), durée (s)] */
    private const PERIODES = [
        '6h' => ['brutes', 60, 6 * 3600],
        '24h' => ['brutes', 300, 86400],
        '7j' => ['heures', 3600, 7 * 86400],
        '30j' => ['heures', 3 * 3600, 30 * 86400],
        '1an' => ['jours', 86400, 365 * 86400],
    ];

    private PDO $db;

    public function __construct(?PDO $db = null)
    {
        $this->db = $db ?? AppConfig::getDB();
        $this->creerTables();
    }

    // ── Recevoir ──────────────────────────────────────────────────────────

    /** Rend le nombre d'échantillons nouveaux. */
    public function recevoir(string $maison, array $echantillons): int
    {
        if (count($echantillons) > self::PAR_ENVOI) {
            throw new DomainException('Trop d\'échantillons dans un envoi.');
        }
        $maintenant = time();
        $brute = $this->db->prepare('INSERT IGNORE INTO mesures_brutes (maison, serie, t, v) VALUES (?, ?, ?, ?)');
        $agreger = [];
        foreach (['heures' => 3600, 'jours' => 86400] as $table => $pas) {
            $agreger[$pas] = $this->db->prepare(
                "INSERT INTO mesures_$table (maison, serie, t, n, somme, mini, maxi) VALUES (?, ?, ?, 1, ?, ?, ?)
                 ON DUPLICATE KEY UPDATE n = n + 1, somme = somme + VALUES(somme),
                                         mini = LEAST(mini, VALUES(mini)), maxi = GREATEST(maxi, VALUES(maxi))");
        }
        $nouveaux = 0;
        $dernier = null;
        $this->db->beginTransaction();
        try {
            foreach ($echantillons as $e) {
                $t = (int)($e['t'] ?? 0);
                $v = $e['v'] ?? null;
                if ($t < $maintenant - self::GARDE_BRUTES || $t > $maintenant + 300 || !is_array($v)
                    || count($v) > self::SERIES_MAX) {
                    continue;  // trop vieux pour la minute (les heures l'auraient compté de travers), ou mal formé
                }
                $compte = false;
                foreach ($v as $serie => $valeur) {
                    if (!is_string($serie) || !preg_match('/^[a-z_]{1,24}(:[A-Za-z0-9_\/.-]{1,40})?$/', $serie)
                        || !is_numeric($valeur) || !is_finite((float)$valeur)) {
                        continue;
                    }
                    $x = (float)$valeur;
                    $brute->execute([$maison, $serie, $t, $x]);
                    if ($brute->rowCount() !== 1) {
                        continue;  // déjà reçu
                    }
                    $compte = true;
                    foreach ($agreger as $pas => $q) {
                        $q->execute([$maison, $serie, intdiv($t, $pas) * $pas, $x, $x, $x]);
                    }
                }
                $nouveaux += $compte ? 1 : 0;
                if ($compte && (!$dernier || $t >= $dernier['t'])) {  // un lot renvoyé ne remplace rien
                    $dernier = $e;
                }
                if (isset($e['smart']) && is_array($e['smart'])) {
                    $this->db->prepare('INSERT INTO mesures_etat (maison, quand, smart) VALUES (?, FROM_UNIXTIME(?), ?)
                                        ON DUPLICATE KEY UPDATE smart = VALUES(smart)')
                        ->execute([$maison, $t, mb_substr(json_encode(array_slice($e['smart'], 0, 16), JSON_UNESCAPED_UNICODE), 0, 16000)]);
                }
            }
            if ($dernier) {
                $sauvegarde = is_string($dernier['sauvegarde'] ?? null) && preg_match('/^\d{4}-\d{2}-\d{2}-\d{4}$/', $dernier['sauvegarde'])
                    ? $dernier['sauvegarde'] : null;
                $this->db->prepare('INSERT INTO mesures_etat (maison, quand, sauvegarde) VALUES (?, FROM_UNIXTIME(?), ?)
                                    ON DUPLICATE KEY UPDATE sauvegarde = IF(VALUES(quand) >= quand, VALUES(sauvegarde), sauvegarde),
                                                            quand = GREATEST(quand, VALUES(quand))')
                    ->execute([$maison, (int)$dernier['t'], $sauvegarde]);
            }
            $this->db->commit();
        } catch (Throwable $e) {
            $this->db->rollBack();
            throw $e;
        }
        if (random_int(1, 50) === 1) {
            $this->menage();
        }
        return $nouveaux;
    }

    public function menage(): void
    {
        $t = time();
        $this->db->prepare('DELETE FROM mesures_brutes WHERE t < ?')->execute([$t - self::GARDE_BRUTES - 3600]);
        $this->db->prepare('DELETE FROM mesures_heures WHERE t < ?')->execute([$t - self::GARDE_HEURES]);
        $this->db->prepare('DELETE FROM mesures_jours WHERE t < ?')->execute([$t - self::GARDE_JOURS]);
    }

    // ── Lire ──────────────────────────────────────────────────────────────

    /**
     * {periode, debut, fin, pas, series: {serie: [[t, moyenne, max], …]}, presence: [[t, part 0-1], …],
     *  etat: {quand, smart, sauvegarde}}. presence = part des minutes où la maison a envoyé quelque chose.
     */
    public function historique(string $maison, string $periode): array
    {
        if (!isset(self::PERIODES[$periode])) {
            throw new DomainException('Période inconnue.');
        }
        [$table, $pas, $duree] = self::PERIODES[$periode];
        $fin = time();
        $debut = intdiv($fin - $duree, $pas) * $pas;
        if ($table === 'brutes') {
            $q = $this->db->prepare("SELECT serie, FLOOR(t / $pas) * $pas AS b, AVG(v) AS moy, MAX(v) AS maxi, COUNT(*) AS n
                                     FROM mesures_brutes WHERE maison = ? AND t >= ? GROUP BY serie, b ORDER BY b");
        } else {
            $q = $this->db->prepare("SELECT serie, FLOOR(t / $pas) * $pas AS b, SUM(somme) / SUM(n) AS moy, MAX(maxi) AS maxi,
                                     SUM(n) AS n FROM mesures_$table WHERE maison = ? AND t >= ? GROUP BY serie, b ORDER BY b");
        }
        $q->execute([$maison, $debut]);
        $series = [];
        $presence = [];
        foreach ($q->fetchAll(PDO::FETCH_ASSOC) as $l) {
            $b = (int)$l['b'];
            $series[$l['serie']][] = [$b, round((float)$l['moy'], 3), round((float)$l['maxi'], 3)];
            if ($l['serie'] === 'up') {
                $presence[] = [$b, min(1.0, round((int)$l['n'] * 60 / $pas, 3))];
            }
        }
        $e = $this->db->prepare('SELECT UNIX_TIMESTAMP(quand) AS quand, smart, sauvegarde FROM mesures_etat WHERE maison = ?');
        $e->execute([$maison]);
        $etat = $e->fetch(PDO::FETCH_ASSOC) ?: null;
        if ($etat) {
            $etat['quand'] = (int)$etat['quand'];
            $etat['smart'] = $etat['smart'] ? json_decode($etat['smart'], true) : null;
        }
        return ['periode' => $periode, 'debut' => $debut, 'fin' => $fin, 'pas' => $pas,
                'series' => $series, 'presence' => $presence, 'etat' => $etat];
    }

    // ── Interne ───────────────────────────────────────────────────────────

    private function creerTables(): void
    {
        $this->db->exec('CREATE TABLE IF NOT EXISTS mesures_brutes (
            maison VARCHAR(63) NOT NULL, serie VARCHAR(66) NOT NULL, t INT UNSIGNED NOT NULL, v DOUBLE NOT NULL,
            PRIMARY KEY (maison, serie, t), KEY (t)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4');
        foreach (['heures', 'jours'] as $table) {
            $this->db->exec("CREATE TABLE IF NOT EXISTS mesures_$table (
                maison VARCHAR(63) NOT NULL, serie VARCHAR(66) NOT NULL, t INT UNSIGNED NOT NULL,
                n INT UNSIGNED NOT NULL, somme DOUBLE NOT NULL, mini DOUBLE NOT NULL, maxi DOUBLE NOT NULL,
                PRIMARY KEY (maison, serie, t), KEY (t)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
        }
        $this->db->exec('CREATE TABLE IF NOT EXISTS mesures_etat (
            maison VARCHAR(63) NOT NULL PRIMARY KEY, quand DATETIME NOT NULL, smart TEXT NULL, sauvegarde VARCHAR(20) NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4');
    }
}
