<?php
/**
 * Les postes des maisons GulliOS (GulliOS 1.57) : les ordinateurs d'une maison qui ne sont pas son
 * serveur. Une maison = un serveur + autant de postes qu'on veut.
 *
 * Un poste a sa propre paire de clés ed25519 (comme une maison) et s'annonce lui-même, toutes les
 * heures, par un message signé {maison, poste, quand, cle, version, canal} : la première fois, il
 * arrive « en demande ». C'est la MAISON (son serveur, message signé par la clé de la maison) qui
 * l'accepte, le retire, et lui donne le canal dev — seulement si elle est Dev elle-même.
 * Un poste accepté envoie ses mesures (MesuresMaisons, sous le nom « maison~poste ») ; sa maison
 * en lit la liste (avec les dernières valeurs) et l'historique.
 *
 * Une demande dont la clé change est remplacée (le poste a été réinstallé avant d'être accepté) ;
 * un poste accepté ne change pas de clé : la maison doit d'abord le retirer.
 */
declare(strict_types=1);

require_once __DIR__ . '/AppConfig.php';
require_once __DIR__ . '/MesuresMaisons.php';

final class PostesMaisons
{
    private const FENETRE = 300;
    private const NOM = '/^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/';
    /** Les séries dont la liste rend la dernière valeur, et une petite courbe (la dernière heure). */
    private const SERIES = ['lat_internet', 'cpu', 'mem_utilisee', 'mem_total', 'disque_utilise:/', 'disque_total:/',
                            'net_recu'];

    private PDO $db;

    public function __construct(?PDO $db = null)
    {
        $this->db = $db ?? AppConfig::getDB();
        $this->db->exec(
            'CREATE TABLE IF NOT EXISTS gullios_postes (
                maison     VARCHAR(63) NOT NULL,
                poste      VARCHAR(63) NOT NULL,
                cle        VARCHAR(64) NOT NULL,
                etat       ENUM(\'demande\',\'accepte\') NOT NULL DEFAULT \'demande\',
                dev        TINYINT(1)  NOT NULL DEFAULT 0,
                version    VARCHAR(40) NULL,
                canal      ENUM(\'stable\',\'beta\',\'dev\') NOT NULL DEFAULT \'stable\',
                demande_le DATETIME    NOT NULL,
                vue_le     DATETIME    NULL,
                PRIMARY KEY (maison, poste)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'
        );
    }

    /** Le nom sous lequel les mesures d'un poste sont rangées (≤ 63 : les noms du registre font ≤ 30). */
    public static function cleMesures(string $maison, string $poste): string
    {
        return substr($maison . '~' . $poste, 0, 63);
    }

    private function ligne(string $maison, string $poste): ?array
    {
        $q = $this->db->prepare('SELECT * FROM gullios_postes WHERE maison = ? AND poste = ?');
        $q->execute([$maison, $poste]);
        return $q->fetch(PDO::FETCH_ASSOC) ?: null;
    }

    /**
     * Le message d'un poste, vérifié. La clé est celle qu'on connaît pour un poste accepté ; pour une
     * demande (ou un inconnu), celle que le message porte. Rend [message, ligne|null].
     */
    public function ouvrir(array $corps): array
    {
        $brut = (string)($corps['message'] ?? '');
        $signature = base64_decode((string)($corps['signature'] ?? ''), true);
        $m = json_decode($brut, true);
        if (!is_array($m) || $signature === false || strlen($signature) !== SODIUM_CRYPTO_SIGN_BYTES) {
            throw new DomainException('Message illisible.');
        }
        $maison = strtolower((string)($m['maison'] ?? ''));
        $poste = strtolower((string)($m['poste'] ?? ''));
        if (!preg_match(self::NOM, $maison) || !preg_match(self::NOM, $poste)) {
            throw new DomainException('Nom de maison ou de poste invalide.');
        }
        if (abs(time() - (int)($m['quand'] ?? 0)) > self::FENETRE) {
            throw new DomainException('L\'horloge du poste est décalée de plus de cinq minutes.');
        }
        $q = $this->db->prepare('SELECT 1 FROM gullios_maisons WHERE nom = ?');
        $q->execute([$maison]);
        if (!$q->fetchColumn()) {
            throw new DomainException('Maison inconnue du registre.');
        }
        $ligne = $this->ligne($maison, $poste);
        $connue = $ligne && $ligne['etat'] === 'accepte';
        $cle = base64_decode($connue ? $ligne['cle'] : (string)($m['cle'] ?? ''), true);
        if ($cle === false || strlen($cle) !== SODIUM_CRYPTO_SIGN_PUBLICKEYBYTES) {
            throw new DomainException('Clé invalide.');
        }
        if (!sodium_crypto_sign_verify_detached($signature, $brut, $cle)) {
            throw new DomainException($connue && ($m['cle'] ?? '') !== $ligne['cle']
                ? 'Ce nom de poste est déjà pris dans cette maison (par un autre ordinateur). La maison doit d\'abord le retirer.'
                : 'Signature refusée.');
        }
        $m['maison'] = $maison;
        $m['poste'] = $poste;
        return [$m, $ligne];
    }

    /** Le signe de vie d'un poste ; la première fois, sa demande. Rend {etat, dev}. */
    public function signe(array $m, ?array $ligne): array
    {
        $canal = in_array($m['canal'] ?? '', ['stable', 'beta', 'dev'], true) ? $m['canal'] : 'stable';
        $version = substr((string)($m['version'] ?? ''), 0, 40);
        if (!$ligne || $ligne['etat'] === 'demande') {
            $this->db->prepare(
                'INSERT INTO gullios_postes (maison, poste, cle, version, canal, demande_le, vue_le)
                 VALUES (?, ?, ?, ?, ?, NOW(), NOW())
                 ON DUPLICATE KEY UPDATE cle = VALUES(cle), version = VALUES(version), canal = VALUES(canal), vue_le = NOW()'
            )->execute([$m['maison'], $m['poste'], (string)$m['cle'], $version, $canal]);
        } else {
            $this->db->prepare('UPDATE gullios_postes SET version = ?, canal = ?, vue_le = NOW() WHERE maison = ? AND poste = ?')
                ->execute([$version, $canal, $m['maison'], $m['poste']]);
        }
        $etat = $this->etat($m['maison'], $m['poste']);
        // 1.64 : les maisons amies de la sienne — un poste accepté y laisse entrer leurs gens (session de visiteur)
        $etat['amies'] = [];
        if ($etat['etat'] === 'accepte') {
            try {
                $q = $this->db->prepare("SELECT IF(a = ?, b, a) FROM gullios_amies WHERE (a = ? OR b = ?) AND etat = 'amie'");
                $q->execute([$m['maison'], $m['maison'], $m['maison']]);
                $etat['amies'] = array_values(array_map('strval', $q->fetchAll(PDO::FETCH_COLUMN)));
            } catch (PDOException $e) {
                // pas encore d'annuaire des amies
            }
        }
        return $etat;
    }

    /** {etat: demande|accepte, dev} — le canal dev seulement si la maison est Dev elle aussi. */
    public function etat(string $maison, string $poste): array
    {
        $q = $this->db->prepare('SELECT p.etat, p.dev AND COALESCE(m.dev, 0) AS dev FROM gullios_postes p
                                 LEFT JOIN gullios_maisons m ON m.nom = p.maison WHERE p.maison = ? AND p.poste = ?');
        $q->execute([$maison, $poste]);
        $x = $q->fetch(PDO::FETCH_ASSOC);
        return ['etat' => $x['etat'] ?? 'demande', 'dev' => (bool)($x['dev'] ?? 0)];
    }

    public function mesures(array $m, ?array $ligne): int
    {
        if (!$ligne || $ligne['etat'] !== 'accepte') {
            throw new DomainException('Ce poste n\'est pas encore accepté par sa maison.');
        }
        if (!is_array($m['echantillons'] ?? null)) {
            throw new DomainException('Échantillons manquants.');
        }
        return (new MesuresMaisons($this->db))->recevoir(self::cleMesures($m['maison'], $m['poste']), $m['echantillons']);
    }

    // ── Vu de la maison ───────────────────────────────────────────────────

    /** Les postes d'une maison, demandes comprises, avec leurs dernières mesures (la dernière heure). */
    public function liste(string $maison): array
    {
        $q = $this->db->prepare('SELECT poste, etat, dev, version, canal, demande_le, vue_le FROM gullios_postes
                                 WHERE maison = ? ORDER BY etat = \'accepte\', poste');
        $q->execute([$maison]);
        new MesuresMaisons($this->db);  // ses tables, si aucune mesure n'est encore arrivée
        $mes = $this->db->prepare('SELECT serie, t, v FROM mesures_brutes WHERE maison = ? AND t >= ? AND serie IN ('
                                  . implode(',', array_fill(0, count(self::SERIES), '?')) . ') ORDER BY t');
        $rendu = [];
        foreach ($q->fetchAll(PDO::FETCH_ASSOC) as $x) {
            $courbes = [];
            if ($x['etat'] === 'accepte') {
                $mes->execute([self::cleMesures($maison, $x['poste']), time() - 3600, ...self::SERIES]);
                foreach ($mes->fetchAll(PDO::FETCH_ASSOC) as $p) {
                    $courbes[$p['serie']][] = (float)$p['v'];
                }
            }
            $rendu[] = ['nom' => $x['poste'], 'etat' => $x['etat'], 'dev' => (bool)$x['dev'], 'version' => $x['version'],
                        'canal' => $x['canal'], 'demande_le' => gmdate('c', strtotime((string)$x['demande_le'])),
                        'vue_il_y_a' => $x['vue_le'] ? max(0, time() - strtotime((string)$x['vue_le'])) : null,
                        'courbes' => $courbes];
        }
        return $rendu;
    }

    /** accepter | retirer | dev-oui | dev-non — par la maison. Rend la liste. */
    public function geste(string $maison, bool $maisonDev, string $geste, string $poste): array
    {
        $ligne = $this->ligne($maison, $poste);
        if (!$ligne) {
            throw new DomainException('Poste inconnu dans cette maison.');
        }
        switch ($geste) {
            case 'accepter':
                $this->db->prepare('UPDATE gullios_postes SET etat = \'accepte\' WHERE maison = ? AND poste = ?')
                    ->execute([$maison, $poste]);
                break;
            case 'retirer':
                $this->db->prepare('DELETE FROM gullios_postes WHERE maison = ? AND poste = ?')->execute([$maison, $poste]);
                break;
            case 'dev-oui':
            case 'dev-non':
                if ($geste === 'dev-oui' && !$maisonDev) {
                    throw new DomainException('Seule une maison Dev peut donner le canal dev à ses postes.');
                }
                if ($ligne['etat'] !== 'accepte') {
                    throw new DomainException('Accepte d\'abord ce poste.');
                }
                $this->db->prepare('UPDATE gullios_postes SET dev = ? WHERE maison = ? AND poste = ?')
                    ->execute([$geste === 'dev-oui' ? 1 : 0, $maison, $poste]);
                break;
            default:
                throw new DomainException('Geste inconnu.');
        }
        return $this->liste($maison);
    }

    public function historique(string $maison, string $poste, string $periode): array
    {
        $ligne = $this->ligne($maison, $poste);
        if (!$ligne || $ligne['etat'] !== 'accepte') {
            throw new DomainException('Poste inconnu dans cette maison.');
        }
        return (new MesuresMaisons($this->db))->historique(self::cleMesures($maison, $poste), $periode);
    }
}
