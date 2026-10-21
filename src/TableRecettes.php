<?php
/**
 * La table commune des recettes (GulliEATS 0.5, GulliOS 1.42) : chaque maison qui partage y
 * dépose ses recettes au fil de l'eau, et chaque maison qui regarde y reprend celles des autres
 * dans sa propre base. Ce qui est déposé reste même si la maison disparaît du réseau : seul
 * « arrêter de partager » le retire (des pierres tombales, que les autres maisons suivent).
 *
 * Accès : un jeton par maison et par app, délivré par le registre sur un message signé de la
 * maison (RegistreMaisons::jetonTable). Ici on ne garde que son empreinte.
 *
 * Fichiers (photo du plat, pages d'origine) : rangés par leur empreinte SHA-256 sous
 * DATA_PATH/table/, déposés une fois, servis aux maisons.
 */
declare(strict_types=1);

require_once __DIR__ . '/AppConfig.php';

final class TableRecettes
{
    public const PAR_ENVOI = 200;
    public const PAR_LECTURE = 300;
    private const CONTENU_MAX = 512 * 1024;
    private const FICHIER_MAX = 20 * 1024 * 1024;

    private PDO $db;
    private string $dossier;

    public function __construct(?PDO $db = null, ?string $dossier = null)
    {
        $this->db = $db ?? AppConfig::getDB();
        $this->dossier = rtrim($dossier ?? (rtrim((string)(getenv('DATA_PATH') ?: '/app/data'), '/') . '/table'), '/');
        $this->creerTables();
    }

    // ── Les jetons ────────────────────────────────────────────────────────

    /** Un jeton neuf pour (maison, app) ; l'ancien ne vaut plus rien. Rendu en clair une seule fois. */
    public function nouveauJeton(string $maison, string $app): string
    {
        $jeton = bin2hex(random_bytes(32));
        $this->db->prepare('REPLACE INTO table_jetons (maison, app, empreinte, cree_le) VALUES (?, ?, ?, NOW())')
            ->execute([$maison, $app, hash('sha256', $jeton)]);
        return $jeton;
    }

    /** La maison derrière un jeton, ou null. */
    public function maisonDuJeton(string $jeton): ?string
    {
        if (!preg_match('/^[0-9a-f]{64}$/', $jeton)) {
            return null;
        }
        $q = $this->db->prepare('SELECT maison FROM table_jetons WHERE empreinte = ?');
        $q->execute([hash('sha256', $jeton)]);
        $m = $q->fetchColumn();
        return $m === false ? null : (string)$m;
    }

    // ── Déposer ───────────────────────────────────────────────────────────

    /**
     * [{uid, lien, contenu}] → les empreintes de fichiers citées que la table n'a pas encore
     * (la maison les envoie ensuite).
     */
    public function deposer(string $maison, array $recettes): array
    {
        if (count($recettes) > self::PAR_ENVOI) {
            throw new DomainException('Trop de recettes dans un envoi.');
        }
        $manquants = [];
        $ins = $this->db->prepare(
            'INSERT INTO table_recettes (maison, uid, lien, contenu, supprimee, seq, maj)
             VALUES (?, ?, ?, ?, 0, ?, NOW())
             ON DUPLICATE KEY UPDATE lien = VALUES(lien), contenu = VALUES(contenu), supprimee = 0,
                                     seq = VALUES(seq), maj = NOW()'
        );
        foreach ($recettes as $r) {
            $uid = (string)($r['uid'] ?? '');
            $contenu = $r['contenu'] ?? null;
            if (!preg_match('/^[A-Za-z0-9_.:-]{1,64}$/', $uid) || !is_array($contenu)) {
                throw new DomainException('Recette mal formée.');
            }
            $json = json_encode($contenu, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
            if ($json === false || strlen($json) > self::CONTENU_MAX) {
                throw new DomainException('Recette trop grosse.');
            }
            $lien = isset($r['lien']) && is_string($r['lien']) && $r['lien'] !== '' ? mb_substr($r['lien'], 0, 512) : null;
            $ins->execute([$maison, $uid, $lien, $json, $this->seq(), ]);
            foreach (self::fichiersCites($contenu) as $h) {
                if (!$this->aFichier($h)) {
                    $manquants[$h] = true;
                }
            }
        }
        return array_keys($manquants);
    }

    /** Retire des recettes (ou toutes, $uids = null) : elles deviennent des pierres tombales. */
    public function retirer(string $maison, ?array $uids): int
    {
        $n = 0;
        $maj = $this->db->prepare('UPDATE table_recettes SET supprimee = 1, contenu = NULL, lien = NULL, seq = ?, maj = NOW()
                                   WHERE maison = ? AND uid = ? AND supprimee = 0');
        if ($uids === null) {
            $q = $this->db->prepare('SELECT uid FROM table_recettes WHERE maison = ? AND supprimee = 0');
            $q->execute([$maison]);
            $uids = $q->fetchAll(PDO::FETCH_COLUMN);
        }
        foreach ($uids as $uid) {
            $maj->execute([$this->seq(), $maison, (string)$uid]);
            $n += $maj->rowCount();
        }
        return $n;
    }

    // ── Lire ──────────────────────────────────────────────────────────────

    /** Les changements des AUTRES maisons après $depuis, dans l'ordre. */
    public function changements(string $maison, int $depuis, int $n = self::PAR_LECTURE): array
    {
        $n = max(1, min($n, self::PAR_LECTURE));
        $q = $this->db->prepare("SELECT seq, maison, uid, lien, contenu, supprimee FROM table_recettes
                                 WHERE seq > ? AND maison <> ? ORDER BY seq LIMIT $n");
        $q->execute([$depuis, $maison]);
        $lignes = [];
        foreach ($q->fetchAll() as $l) {
            $lignes[] = ['seq' => (int)$l['seq'], 'maison' => $l['maison'], 'uid' => $l['uid'], 'lien' => $l['lien'],
                         'supprimee' => (bool)$l['supprimee'],
                         'contenu' => $l['contenu'] === null ? null : json_decode($l['contenu'], true)];
        }
        // Rien de plus récent : le curseur saute au dernier numéro (nos propres envois compris).
        $fin = $lignes ? end($lignes)['seq'] : max($depuis, (int)$this->db->query('SELECT COALESCE(MAX(seq), 0) FROM table_recettes')->fetchColumn());
        return ['recettes' => $lignes, 'fin' => $fin, 'encore' => count($lignes) === $n];
    }

    /** Les maisons qui partagent : nom, nombre de recettes, dernier dépôt. */
    public function maisons(): array
    {
        return array_map(fn($l) => ['nom' => $l['maison'], 'recettes' => (int)$l['n'], 'maj' => $l['maj']],
            $this->db->query('SELECT maison, COUNT(*) n, MAX(maj) maj FROM table_recettes WHERE supprimee = 0
                              GROUP BY maison ORDER BY maison')->fetchAll());
    }

    // ── Fichiers ──────────────────────────────────────────────────────────

    public function aFichier(string $h): bool
    {
        return preg_match('/^[0-9a-f]{64}$/', $h) === 1 && is_file($this->chemin($h));
    }

    public function poserFichier(string $h, string $octets): void
    {
        if (preg_match('/^[0-9a-f]{64}$/', $h) !== 1 || hash('sha256', $octets) !== $h) {
            throw new DomainException('Empreinte du fichier fausse.');
        }
        if (strlen($octets) > self::FICHIER_MAX) {
            throw new DomainException('Fichier trop gros.');
        }
        $info = @getimagesizefromstring($octets);
        if ($info === false || !in_array($info[2], [IMAGETYPE_JPEG, IMAGETYPE_PNG, IMAGETYPE_WEBP, IMAGETYPE_GIF], true)) {
            throw new DomainException('Seules les images sont acceptées.');
        }
        $chemin = $this->chemin($h);
        if (!is_dir(dirname($chemin))) {
            mkdir(dirname($chemin), 0755, true);
        }
        $tmp = $chemin . '.' . bin2hex(random_bytes(4));
        file_put_contents($tmp, $octets);
        rename($tmp, $chemin);
    }

    public function chemin(string $h): string
    {
        return $this->dossier . '/' . substr($h, 0, 2) . '/' . $h;
    }

    /** @return array<int, string> */
    public static function fichiersCites(array $contenu): array
    {
        $h = [];
        if (is_string($contenu['image'] ?? null)) {
            $h[] = $contenu['image'];
        }
        foreach ((array)($contenu['pages'] ?? []) as $p) {
            if (is_string($p)) {
                $h[] = $p;
            }
        }
        return array_values(array_filter(array_unique($h), fn($x) => preg_match('/^[0-9a-f]{64}$/', $x) === 1));
    }

    // ── Interne ───────────────────────────────────────────────────────────

    /** Un numéro de changement croissant, partagé par toutes les maisons. */
    private function seq(): int
    {
        $this->db->exec('INSERT INTO table_compteur () VALUES ()');
        return (int)$this->db->lastInsertId();
    }

    private function creerTables(): void
    {
        $this->db->exec('CREATE TABLE IF NOT EXISTS table_jetons (
            maison VARCHAR(63) NOT NULL, app VARCHAR(20) NOT NULL, empreinte CHAR(64) NOT NULL,
            cree_le DATETIME NOT NULL, PRIMARY KEY (maison, app), UNIQUE KEY (empreinte)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4');
        $this->db->exec('CREATE TABLE IF NOT EXISTS table_compteur (
            seq BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY
        ) ENGINE=InnoDB');
        $this->db->exec('CREATE TABLE IF NOT EXISTS table_recettes (
            maison VARCHAR(63) NOT NULL, uid VARCHAR(64) NOT NULL, lien VARCHAR(512) NULL,
            contenu MEDIUMTEXT NULL, supprimee TINYINT(1) NOT NULL DEFAULT 0,
            seq BIGINT UNSIGNED NOT NULL, maj DATETIME NOT NULL,
            PRIMARY KEY (maison, uid), KEY (seq)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4');
    }
}
