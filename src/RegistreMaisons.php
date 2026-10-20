<?php
/**
 * Le registre des maisons GulliOS (GulliOS 1.31) : qui existe, qui est Dev, et les billets
 * du bureau à distance.
 *
 * Une maison prouve qui elle est comme Let's Encrypt le fait d'un domaine : elle crée sa paire
 * de clés ed25519, publie sa clé publique sur https://<nom>.gullify.app/.well-known/gullios/identite,
 * et le registre va l'y lire avant de l'inscrire. Ensuite, chaque demande est un message JSON
 * signé par la maison ({"message": "…", "signature": "…"}), daté à cinq minutes près.
 *
 * Le rôle Dev n'appartient qu'au registre : une maison Dev en désigne une autre (un code à usage
 * unique, sept jours), l'administrateur de celle-ci l'entre chez lui, et c'est ici que le rôle
 * est accordé. Les billets du bureau à distance sont signés par la clé de l'atelier
 * (GULLIOS_REGISTRE_CLE, dans le .env, jamais dans git) ; chaque maison les vérifie avec la clé
 * publique livrée dans le paquet GulliOS.
 *
 * Comme Registry, ne tourne que sur le serveur central (actif() faux ailleurs).
 */
declare(strict_types=1);

require_once __DIR__ . '/AppConfig.php';

final class RegistreMaisons
{
    private const FENETRE = 300;           // secondes de décalage d'horloge tolérées
    private const JOURS_DU_CODE = 7;
    private const ESSAIS_DU_CODE = 5;
    private const SECONDES_DU_BILLET = 120;
    private const ALPHABET = 'ACDEFGHJKMNPQRTUVWXY34679';  // sans 0/O, 1/I/L, 2/Z, 5/S, 8/B

    private PDO $db;
    private string $domaine;
    /** @var callable(string): ?string  lit l'identité publiée par une maison (remplaçable en essai) */
    private $lireIdentite;

    public function __construct(?callable $lireIdentite = null)
    {
        $this->db = AppConfig::getDB();
        $this->domaine = strtolower(trim((string)AppConfig::get('registry.domain', '')));
        $this->lireIdentite = $lireIdentite ?? [$this, 'identitePubliee'];
        $this->creerTables();
    }

    public static function actif(): bool
    {
        return trim((string)AppConfig::get('registry.domain', '')) !== '';
    }

    // ── Les messages signés ───────────────────────────────────────────────

    /**
     * Le message d'une maison, vérifié : sa signature, sa date, et (sauf à l'inscription) la
     * maison connue qui l'a signé. Rend [message, maison|null].
     */
    public function ouvrir(array $corps, bool $inscription = false): array
    {
        $brut = (string)($corps['message'] ?? '');
        $signature = base64_decode((string)($corps['signature'] ?? ''), true);
        $m = json_decode($brut, true);
        if (!is_array($m) || $signature === false || strlen($signature) !== SODIUM_CRYPTO_SIGN_BYTES) {
            throw new DomainException('Message illisible.');
        }
        $nom = strtolower((string)($m['nom'] ?? ''));
        if (!preg_match('/^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/', $nom)) {
            throw new DomainException('Nom de maison invalide.');
        }
        if (abs(time() - (int)($m['quand'] ?? 0)) > self::FENETRE) {
            throw new DomainException('L\'horloge de la maison est décalée de plus de cinq minutes.');
        }
        $maison = $this->maison($nom);
        $cle = $inscription ? base64_decode((string)($m['cle'] ?? ''), true) :
            ($maison ? base64_decode($maison['cle'], true) : false);
        if ($cle === false || strlen($cle) !== SODIUM_CRYPTO_SIGN_PUBLICKEYBYTES) {
            throw new DomainException($inscription ? 'Clé invalide.' : 'Maison inconnue : elle doit d\'abord s\'inscrire.');
        }
        if (!sodium_crypto_sign_verify_detached($signature, $brut, $cle)) {
            throw new DomainException('Signature refusée.');
        }
        $m['nom'] = $nom;
        return [$m, $maison];
    }

    private function maison(string $nom): ?array
    {
        $q = $this->db->prepare('SELECT * FROM gullios_maisons WHERE nom = ?');
        $q->execute([$nom]);
        return $q->fetch(PDO::FETCH_ASSOC) ?: null;
    }

    private function exigerDev(?array $maison): void
    {
        if (!$maison || !(int)$maison['dev']) {
            throw new DomainException('Réservé aux maisons Dev.');
        }
    }

    // ── Inscription et signe de vie ───────────────────────────────────────

    /** L'identité publiée par la maison sur sa propre adresse (null si rien de lisible). */
    private function identitePubliee(string $nom): ?string
    {
        $contexte = stream_context_create(['http' => ['timeout' => 10, 'ignore_errors' => false,
                                                      'header' => "User-Agent: GulliOS-Registre\r\n"]]);
        $texte = @file_get_contents("https://{$nom}.{$this->domaine}/.well-known/gullios/identite", false, $contexte);
        return $texte === false ? null : trim(substr($texte, 0, 200));
    }

    public function inscrire(array $m): array
    {
        $cle = (string)$m['cle'];
        if (($this->lireIdentite)($m['nom']) !== $cle) {
            throw new DomainException("https://{$m['nom']}.{$this->domaine}/.well-known/gullios/identite ne montre pas cette clé.");
        }
        $this->db->prepare(
            'INSERT INTO gullios_maisons (nom, cle, inscrite_le, vue_le) VALUES (?, ?, NOW(), NOW())
             ON DUPLICATE KEY UPDATE cle = VALUES(cle), vue_le = NOW()'
        )->execute([$m['nom'], $cle]);
        return $this->signeDeVie($m);
    }

    public function signeDeVie(array $m): array
    {
        $canal = in_array($m['canal'] ?? '', ['stable', 'beta', 'dev'], true) ? $m['canal'] : 'stable';
        $this->db->prepare(
            'UPDATE gullios_maisons SET version = ?, canal = ?, aide = ?, vue_le = NOW() WHERE nom = ?'
        )->execute([substr((string)($m['version'] ?? ''), 0, 40), $canal, !empty($m['aide']) ? 1 : 0, $m['nom']]);
        return $this->etat($m['nom']);
    }

    /** Ce que la maison doit savoir d'elle-même : Dev ? désignée ? */
    public function etat(string $nom): array
    {
        $x = $this->maison($nom);
        return ['dev' => (bool)($x['dev'] ?? 0),
                'designee' => $x && $x['code_hash'] && strtotime((string)$x['code_expire']) > time()];
    }

    // ── Les maisons Dev ───────────────────────────────────────────────────

    public function liste(): array
    {
        $q = $this->db->query('SELECT nom, version, canal, aide, dev, vue_le, code_hash, code_expire
                               FROM gullios_maisons ORDER BY nom');
        $rendu = [];
        foreach ($q->fetchAll(PDO::FETCH_ASSOC) as $x) {
            $designee = $x['code_hash'] && strtotime((string)$x['code_expire']) > time();
            $rendu[] = ['nom' => $x['nom'], 'adresse' => "{$x['nom']}.{$this->domaine}", 'version' => $x['version'],
                        'canal' => $x['canal'], 'aide' => (bool)$x['aide'], 'dev' => (bool)$x['dev'],
                        'vue_il_y_a' => $x['vue_le'] ? max(0, time() - strtotime((string)$x['vue_le'])) : null,
                        'designee_jusqua' => $designee ? gmdate('c', strtotime((string)$x['code_expire'])) : null];
        }
        return $rendu;
    }

    public function designer(string $cible): array
    {
        $x = $this->maison($cible);
        if (!$x) {
            throw new DomainException('Maison inconnue.');
        }
        if ((int)$x['dev']) {
            throw new DomainException('Cette maison est déjà Dev.');
        }
        $code = '';
        for ($i = 0; $i < 6; $i++) {
            $code .= self::ALPHABET[random_int(0, strlen(self::ALPHABET) - 1)];
        }
        $this->db->prepare('UPDATE gullios_maisons SET code_hash = ?, code_expire = ?, code_essais = 0 WHERE nom = ?')
            ->execute([hash('sha256', $code), date('Y-m-d H:i:s', time() + self::JOURS_DU_CODE * 86400), $cible]);
        return ['code' => substr($code, 0, 3) . '-' . substr($code, 3), 'jours' => self::JOURS_DU_CODE];
    }

    public function annuler(string $cible): void
    {
        $this->db->prepare('UPDATE gullios_maisons SET code_hash = NULL, code_expire = NULL WHERE nom = ?')
            ->execute([$cible]);
    }

    /** L'administrateur de la maison désignée entre son code. */
    public function devenirDev(array $m, array $maison): array
    {
        $code = strtoupper(preg_replace('/[^A-Za-z0-9]/', '', (string)($m['code'] ?? '')));
        $valide = $maison['code_hash'] && strtotime((string)$maison['code_expire']) > time();
        if (!$valide) {
            throw new DomainException('Cette maison n\'est pas désignée Dev (ou le code a expiré).');
        }
        if (!hash_equals($maison['code_hash'], hash('sha256', $code))) {
            $essais = (int)$maison['code_essais'] + 1;
            $this->db->prepare($essais >= self::ESSAIS_DU_CODE
                ? 'UPDATE gullios_maisons SET code_hash = NULL, code_expire = NULL, code_essais = 0 WHERE nom = ?'
                : 'UPDATE gullios_maisons SET code_essais = code_essais + 1 WHERE nom = ?')->execute([$maison['nom']]);
            throw new DomainException($essais >= self::ESSAIS_DU_CODE
                ? 'Trop d\'essais : le code est annulé. Demande-en un nouveau.' : 'Ce code ne marche pas.');
        }
        $this->db->prepare('UPDATE gullios_maisons SET dev = 1, code_hash = NULL, code_expire = NULL, code_essais = 0
                            WHERE nom = ?')->execute([$maison['nom']]);
        return $this->etat($maison['nom']);
    }

    /** Pour l'atelier (scripts/registre-dev.php) : accorder ou retirer le rôle à la main. */
    public function fixerDev(string $nom, bool $dev): bool
    {
        $q = $this->db->prepare('UPDATE gullios_maisons SET dev = ? WHERE nom = ?');
        $q->execute([$dev ? 1 : 0, $nom]);
        return $q->rowCount() > 0 || $this->maison($nom) !== null;
    }

    /** Un billet pour le bureau à distance de UNE maison, signé par l'atelier, deux minutes. */
    public function billet(array $m, string $cible): array
    {
        $x = $this->maison($cible);
        if (!$x) {
            throw new DomainException('Maison inconnue.');
        }
        if (!(int)$x['aide']) {
            throw new DomainException('L\'aide à distance est coupée sur cette maison.');
        }
        $secrete = base64_decode((string)AppConfig::get('registry.gullios_cle', ''), true);
        if ($secrete === false || strlen($secrete) !== SODIUM_CRYPTO_SIGN_SECRETKEYBYTES) {
            throw new RuntimeException('GULLIOS_REGISTRE_CLE absente ou invalide');
        }
        $contenu = json_encode(['cible' => $cible, 'de' => $m['nom'],
                                'personne' => mb_substr((string)($m['personne'] ?? ''), 0, 60),
                                'expire' => time() + self::SECONDES_DU_BILLET, 'nonce' => bin2hex(random_bytes(12))],
                               JSON_UNESCAPED_UNICODE);
        $signature = sodium_crypto_sign_detached($contenu, $secrete);
        $b64 = fn(string $s) => rtrim(strtr(base64_encode($s), '+/', '-_'), '=');
        return ['billet' => $b64($contenu) . '.' . $b64($signature),
                'adresse' => "https://{$cible}.{$this->domaine}/bureau/"];
    }

    private function creerTables(): void
    {
        $this->db->exec(
            'CREATE TABLE IF NOT EXISTS gullios_maisons (
                nom          VARCHAR(63)  NOT NULL PRIMARY KEY,
                cle          VARCHAR(64)  NOT NULL,
                version      VARCHAR(40)  NULL,
                canal        ENUM(\'stable\',\'beta\',\'dev\') NOT NULL DEFAULT \'stable\',
                aide         TINYINT(1)   NOT NULL DEFAULT 0,
                dev          TINYINT(1)   NOT NULL DEFAULT 0,
                code_hash    CHAR(64)     NULL,
                code_expire  DATETIME     NULL,
                code_essais  TINYINT      NOT NULL DEFAULT 0,
                inscrite_le  DATETIME     NOT NULL,
                vue_le       DATETIME     NULL
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'
        );
    }
}
