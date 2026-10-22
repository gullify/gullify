<?php
/**
 * Les maisons amies (GulliOS 1.47) : deux maisons GulliOS qui se voient l'une l'autre ce qu'elles
 * partagent (pour commencer, les enregistrements télé de GulliTV). Rien ne passe par ici que
 * l'annuaire : qui est amie avec qui. Les fichiers se lisent DIRECTEMENT chez la maison qui partage.
 *
 * Une maison en invite une autre par son nom ; l'autre accepte (ou l'invite à son tour, ce qui
 * revient au même). Chaque fois qu'une maison demande sa liste, elle reçoit pour chaque amie un
 * billet signé par l'atelier (même clé que le bureau à distance, GULLIOS_REGISTRE_CLE) :
 *   {"usage":"amie","de":<moi>,"chez":<amie>,"expire":…,"nonce":…}
 * que la maison amie vérifie avec la clé publique livrée dans GulliOS. Jamais de champ « cible » :
 * un billet d'amie ne peut pas ouvrir le bureau à distance (qui exige cible = son nom).
 * Retirer une amie la coupe dès que son dernier billet expire (SECONDES_DU_BILLET).
 */
declare(strict_types=1);

require_once __DIR__ . '/AppConfig.php';

final class AmiesMaisons
{
    public const SECONDES_DU_BILLET = 6 * 3600;
    private const AMIES_MAX = 50;

    private PDO $db;
    private string $domaine;

    public function __construct(?PDO $db = null)
    {
        $this->db = $db ?? AppConfig::getDB();
        $this->domaine = strtolower(trim((string)AppConfig::get('registry.domain', 'gullify.app')));
        $this->db->exec(
            'CREATE TABLE IF NOT EXISTS gullios_amies (
                a       VARCHAR(63) NOT NULL,
                b       VARCHAR(63) NOT NULL,
                de      VARCHAR(63) NOT NULL,
                etat    ENUM(\'invitee\',\'amie\') NOT NULL DEFAULT \'invitee\',
                cree_le DATETIME NOT NULL,
                PRIMARY KEY (a, b), KEY (b)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'
        );
    }

    /** inviter | accepter | retirer (retirer sert aussi à refuser et à annuler une invitation). */
    public function geste(string $moi, string $geste, string $cible): array
    {
        if ($cible === $moi || !preg_match('/^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/', $cible)) {
            throw new DomainException('Maison invalide.');
        }
        [$a, $b] = $moi < $cible ? [$moi, $cible] : [$cible, $moi];
        $ligne = $this->ligne($a, $b);
        switch ($geste) {
            case 'inviter':
                $q = $this->db->prepare('SELECT 1 FROM gullios_maisons WHERE nom = ?');
                $q->execute([$cible]);
                if (!$q->fetchColumn()) {
                    throw new DomainException("Aucune maison GulliOS ne s'appelle « $cible ».");
                }
                if (!$ligne) {
                    if (count($this->liste($moi, false)) >= self::AMIES_MAX) {
                        throw new DomainException('Trop de maisons amies.');
                    }
                    $this->db->prepare('INSERT INTO gullios_amies (a, b, de, cree_le) VALUES (?, ?, ?, NOW())')
                        ->execute([$a, $b, $moi]);
                } elseif ($ligne['etat'] === 'invitee' && $ligne['de'] === $cible) {
                    $this->devenirAmies($a, $b);  // elle m'avait déjà invitée
                }
                break;
            case 'accepter':
                if (!$ligne || $ligne['etat'] !== 'invitee' || $ligne['de'] !== $cible) {
                    throw new DomainException('Pas d\'invitation de cette maison.');
                }
                $this->devenirAmies($a, $b);
                break;
            case 'retirer':
                $this->db->prepare('DELETE FROM gullios_amies WHERE a = ? AND b = ?')->execute([$a, $b]);
                break;
            default:
                throw new DomainException('Geste inconnu.');
        }
        return $this->liste($moi);
    }

    /**
     * [{nom, adresse, etat: amie|envoyee|recue, version, vue_il_y_a, billet?}] ; billet pour les amies
     * seulement (et seulement si $billets).
     */
    public function liste(string $moi, bool $billets = true): array
    {
        $q = $this->db->prepare(
            'SELECT IF(x.a = ?, x.b, x.a) AS nom, x.de, x.etat, m.version, m.vue_le
             FROM gullios_amies x LEFT JOIN gullios_maisons m ON m.nom = IF(x.a = ?, x.b, x.a)
             WHERE x.a = ? OR x.b = ? ORDER BY nom');
        $q->execute([$moi, $moi, $moi, $moi]);
        $secrete = null;
        $rendu = [];
        foreach ($q->fetchAll(PDO::FETCH_ASSOC) as $x) {
            $etat = $x['etat'] === 'amie' ? 'amie' : ($x['de'] === $moi ? 'envoyee' : 'recue');
            $r = ['nom' => $x['nom'], 'adresse' => "{$x['nom']}.{$this->domaine}", 'etat' => $etat,
                  'version' => $x['version'],
                  'vue_il_y_a' => $x['vue_le'] ? max(0, time() - strtotime((string)$x['vue_le'])) : null];
            if ($billets && $etat === 'amie') {
                $secrete ??= $this->cleSecrete();
                $r['billet'] = $this->billet($secrete, $moi, $x['nom']);
            }
            $rendu[] = $r;
        }
        return $rendu;
    }

    private function ligne(string $a, string $b): ?array
    {
        $q = $this->db->prepare('SELECT * FROM gullios_amies WHERE a = ? AND b = ?');
        $q->execute([$a, $b]);
        return $q->fetch(PDO::FETCH_ASSOC) ?: null;
    }

    private function devenirAmies(string $a, string $b): void
    {
        $this->db->prepare('UPDATE gullios_amies SET etat = \'amie\' WHERE a = ? AND b = ?')->execute([$a, $b]);
    }

    private function cleSecrete(): string
    {
        $secrete = base64_decode((string)AppConfig::get('registry.gullios_cle', ''), true);
        if ($secrete === false || strlen($secrete) !== SODIUM_CRYPTO_SIGN_SECRETKEYBYTES) {
            throw new RuntimeException('GULLIOS_REGISTRE_CLE absente ou invalide');
        }
        return $secrete;
    }

    /** Le billet qui laisse $de lire ce que $chez partage (base64url(contenu).base64url(signature)). */
    private function billet(string $secrete, string $de, string $chez): string
    {
        $contenu = json_encode(['usage' => 'amie', 'de' => $de, 'chez' => $chez,
                                'expire' => time() + self::SECONDES_DU_BILLET, 'nonce' => bin2hex(random_bytes(12))]);
        $b64 = fn(string $s) => rtrim(strtr(base64_encode($s), '+/', '-_'), '=');
        return $b64($contenu) . '.' . $b64(sodium_crypto_sign_detached($contenu, $secrete));
    }
}
