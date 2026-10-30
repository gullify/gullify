<?php
/**
 * Les ordres de l'atelier aux maisons GulliOS (1.107) : une file au registre, que chaque maison relève chaque minute
 * par un message signé (gullios-ordres, root). La liste des gestes est FERMÉE — jamais une commande libre :
 *
 *   maj-app <app>   tirer l'image du canal de la maison et relancer l'app (comptes, gullieats, gulliscan, gullitv,
 *                   gullify : pour GulliFY, la demande « maj » à son compagnon)
 *   maj-gullios     lancer la mise à jour de GulliOS (gullios-maj.service)
 *
 * Seul l'atelier ordonne : la page Apps de l'app Atelier, par `docker exec gullify php` ; aucune route web ne crée
 * d'ordre. En relevant, la maison envoie aussi l'empreinte (digest) de l'image de chacune de ses apps : l'atelier, qui
 * connaît les tags du registre, en tire les versions installées. Un ordre non relevé en 24 h est oublié.
 */
declare(strict_types=1);

require_once __DIR__ . '/AppConfig.php';

final class OrdresMaisons
{
    public const GESTES = ['maj-app', 'maj-gullios'];
    public const APPS = ['comptes', 'gullieats', 'gulliscan', 'gullitv', 'gullify'];
    private const HEURES_DE_VIE = 24;

    private PDO $db;

    public function __construct()
    {
        $this->db = AppConfig::getDB();
        $this->creerTables();
    }

    /** Un ordre pour une maison (celui déjà en attente s'il existe, pour ne pas l'empiler). Rend son id. */
    public function ordonner(string $maison, string $geste, ?string $app = null): int
    {
        if (!preg_match('/^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/', $maison)) {
            throw new DomainException('Maison invalide.');
        }
        if (!in_array($geste, self::GESTES, true)) {
            throw new DomainException('Geste inconnu.');
        }
        $app = $geste === 'maj-app' ? (string)$app : null;
        if ($geste === 'maj-app' && !in_array($app, self::APPS, true)) {
            throw new DomainException('App inconnue.');
        }
        $q = $this->db->prepare('SELECT id FROM gullios_ordres WHERE maison = ? AND geste = ? AND app <=> ?
                                 AND etat IN (\'attente\', \'pris\') AND cree_le > NOW() - INTERVAL ' . self::HEURES_DE_VIE . ' HOUR');
        $q->execute([$maison, $geste, $app]);
        $deja = $q->fetchColumn();
        if ($deja) {
            return (int)$deja;
        }
        $this->db->prepare('INSERT INTO gullios_ordres (maison, geste, app, etat, cree_le) VALUES (?, ?, ?, \'attente\', NOW())')
            ->execute([$maison, $geste, $app]);
        return (int)$this->db->lastInsertId();
    }

    /**
     * La maison relève ses ordres (ils passent « pris ») et dépose l'image de ses apps : {image: [digest, …]}.
     * Rend [{id, geste, app}].
     */
    public function relever(string $maison, array $images): array
    {
        $propres = [];
        foreach (array_slice($images, 0, 30, true) as $image => $digests) {
            if (!is_string($image) || !preg_match('/^[a-z0-9][a-z0-9._-]{0,60}$/', $image) || !is_array($digests)) {
                continue;
            }
            $propres[$image] = array_values(array_filter(array_slice($digests, 0, 5),
                fn($d) => is_string($d) && preg_match('/^sha256:[0-9a-f]{64}$/', $d)));
        }
        $this->db->prepare('INSERT INTO gullios_maisons_apps (maison, images, vue_le) VALUES (?, ?, NOW())
                            ON DUPLICATE KEY UPDATE images = VALUES(images), vue_le = NOW()')
            ->execute([$maison, json_encode($propres, JSON_UNESCAPED_SLASHES)]);
        $q = $this->db->prepare('SELECT id, geste, app FROM gullios_ordres WHERE maison = ? AND etat = \'attente\'
                                 AND cree_le > NOW() - INTERVAL ' . self::HEURES_DE_VIE . ' HOUR ORDER BY id');
        $q->execute([$maison]);
        $ordres = $q->fetchAll(PDO::FETCH_ASSOC);
        if ($ordres) {
            $ids = array_column($ordres, 'id');
            $this->db->prepare('UPDATE gullios_ordres SET etat = \'pris\', pris_le = NOW() WHERE id IN ('
                               . implode(',', array_fill(0, count($ids), '?')) . ')')->execute($ids);
        }
        return array_map(fn($o) => ['id' => (int)$o['id'], 'geste' => $o['geste'], 'app' => $o['app']], $ordres);
    }

    /** La maison rend le résultat d'un ordre qu'elle a pris. */
    public function rendre(string $maison, int $id, bool $ok, string $sortie): array
    {
        $q = $this->db->prepare('UPDATE gullios_ordres SET etat = ?, sortie = ?, fini_le = NOW()
                                 WHERE id = ? AND maison = ? AND etat = \'pris\'');
        $q->execute([$ok ? 'ok' : 'echec', mb_substr($sortie, 0, 2000), $id, $maison]);
        return ['rendu' => $q->rowCount() === 1];
    }

    /** Pour l'atelier : l'image des apps de chaque maison et les ordres des 7 derniers jours. */
    public function etat(): array
    {
        $apps = [];
        foreach ($this->db->query('SELECT maison, images, UNIX_TIMESTAMP(vue_le) AS vue_le FROM gullios_maisons_apps') as $l) {
            $apps[$l['maison']] = ['images' => json_decode((string)$l['images'], true) ?: [], 'vue_le' => (int)$l['vue_le']];
        }
        $ordres = $this->db->query('SELECT id, maison, geste, app, etat, sortie, UNIX_TIMESTAMP(cree_le) AS cree_le,
                                    UNIX_TIMESTAMP(fini_le) AS fini_le FROM gullios_ordres
                                    WHERE cree_le > NOW() - INTERVAL 7 DAY ORDER BY id DESC LIMIT 200')->fetchAll(PDO::FETCH_ASSOC);
        return ['apps' => $apps, 'ordres' => $ordres];
    }

    private function creerTables(): void
    {
        $this->db->exec(
            'CREATE TABLE IF NOT EXISTS gullios_ordres (
                id       INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                maison   VARCHAR(63) NOT NULL,
                geste    VARCHAR(20) NOT NULL,
                app      VARCHAR(20) NULL,
                etat     ENUM(\'attente\',\'pris\',\'ok\',\'echec\') NOT NULL DEFAULT \'attente\',
                sortie   TEXT NULL,
                cree_le  DATETIME NOT NULL,
                pris_le  DATETIME NULL,
                fini_le  DATETIME NULL,
                KEY maison_etat (maison, etat)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'
        );
        $this->db->exec(
            'CREATE TABLE IF NOT EXISTS gullios_maisons_apps (
                maison   VARCHAR(63) NOT NULL PRIMARY KEY,
                images   TEXT NOT NULL,
                vue_le   DATETIME NOT NULL
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'
        );
    }
}
