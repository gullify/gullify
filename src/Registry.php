<?php
/**
 * Le service d'inscription : qui a droit à quel « nom.gullify.app ».
 *
 * Il ne tourne que sur le serveur central. Partout ailleurs — c'est-à-dire sur
 * les milliers de serveurs installés chez les gens, avec le même code —
 * `actif()` répond faux et les points d'entrée se taisent (404). C'est
 * volontaire : un serveur de salon n'a aucune raison de distribuer des noms.
 *
 * Le parcours, du côté de celui qui installe :
 *   1. il choisit un nom          → `disponible()`
 *   2. il laisse son adresse      → `reserver()` envoie un courriel
 *   3. il clique dans le courriel → `confirmer()` crée l'enregistrement DNS
 *   4. l'installateur vient prendre le jeton → `etatReservation()`
 *   5. toutes les cinq minutes    → `majIp()` suit son adresse qui change
 *
 * Le jeton est le seul secret : il tient lieu de mot de passe pour dire « cette
 * IP est la mienne ». Il n'est stocké qu'en empreinte, sauf pendant les quelques
 * minutes où l'installateur doit venir le chercher.
 */
declare(strict_types=1);

require_once __DIR__ . '/AppConfig.php';
require_once __DIR__ . '/DnsProvider.php';
require_once __DIR__ . '/IonosDns.php';
require_once __DIR__ . '/Mailer.php';

final class Registry
{
    /** Longueur d'un nom : assez court pour se dicter au téléphone. */
    private const NOM_MIN = 3;
    private const NOM_MAX = 30;

    /** Au-delà, un nom qui ne donne plus signe de vie est rendu à tout le monde. */
    private const JOURS_AVANT_EXPIRATION = 90;
    private const JOURS_AVANT_AVERTISSEMENT = 75;

    /** Combien de noms une même adresse IP peut réserver par jour. */
    private const RESERVATIONS_PAR_JOUR = 3;

    /** Le lien de confirmation ne vaut que quelques heures. */
    private const HEURES_DE_CONFIRMATION = 48;

    /**
     * Les noms qu'on ne donne pas : ce qui est déjà pris, ce qui sert à
     * l'infrastructure, et ce qui pourrait servir à se faire passer pour nous.
     */
    private const RESERVES = [
        'www', 'api', 'app', 'apps', 'admin', 'administrateur', 'root', 'mail',
        'smtp', 'imap', 'pop', 'ns', 'ns1', 'ns2', 'dns', 'ftp', 'cdn', 'static',
        'download', 'downloads', 'telechargement', 'tv', 'vr', 'fy', 'gulli',
        'gullify', 'gullitv', 'gullivr', 'compte', 'comptes', 'account', 'login',
        'connexion', 'securite', 'security', 'support', 'aide', 'help', 'blog',
        'docs', 'status', 'statut', 'test', 'demo', 'exemple', 'example',
        'serveur', 'server', 'registry', 'inscription', 'paiement', 'payment',
    ];

    private PDO $db;
    private DnsProvider $dns;
    private Mailer $courriel;
    private string $domaine;

    public function __construct(?DnsProvider $dns = null, ?Mailer $courriel = null)
    {
        $this->db = AppConfig::getDB();
        $this->domaine = strtolower(trim((string)AppConfig::get('registry.domain', '')));
        $this->dns = $dns ?? self::dnsDeConfig();
        $this->courriel = $courriel ?? Mailer::fromConfig();
        $this->creerTables();
    }

    /** Vrai seulement là où un domaine à distribuer est configuré. */
    public static function actif(): bool
    {
        return trim((string)AppConfig::get('registry.domain', '')) !== '';
    }

    public function domaine(): string
    {
        return $this->domaine;
    }

    /** Le pilote DNS choisi par le .env : « ionos » en production, sinon le factice. */
    private static function dnsDeConfig(): DnsProvider
    {
        $choix = strtolower((string)AppConfig::get('registry.dns', 'fictif'));
        if ($choix === 'ionos') {
            $cle = (string)AppConfig::get('registry.ionos_key', '');
            if ($cle === '') {
                throw new RuntimeException('REGISTRY_DNS=ionos mais IONOS_API_KEY est vide');
            }
            return new IonosDns($cle, (string)AppConfig::get('registry.domain', ''));
        }
        return new FakeDns((string)AppConfig::get('data.path') . '/dns-fictif.json');
    }

    // ── Les noms ──────────────────────────────────────────────────────────

    /**
     * Pourquoi ce nom ne peut pas être accordé, ou null s'il convient.
     *
     * Les messages sont ceux que l'installateur montre : ils s'adressent à
     * quelqu'un qui n'a rien demandé à personne, pas à un développeur.
     */
    public function refusDuNom(string $nom): ?string
    {
        $nom = strtolower(trim($nom));

        if (strlen($nom) < self::NOM_MIN) {
            return 'Il faut au moins ' . self::NOM_MIN . ' lettres.';
        }
        if (strlen($nom) > self::NOM_MAX) {
            return 'Il faut au plus ' . self::NOM_MAX . ' lettres.';
        }
        if (!preg_match('/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/', $nom)) {
            return 'Des lettres, des chiffres et des traits d\'union seulement, et pas de trait d\'union au début ni à la fin.';
        }
        if (str_contains($nom, '--')) {
            // Réservé par la norme IDN (xn--) : on écarte la famille entière.
            return 'Deux traits d\'union à la suite, ce n\'est pas permis.';
        }
        if (in_array($nom, self::RESERVES, true)) {
            return 'Ce nom est réservé.';
        }
        if ($this->nomPris($nom)) {
            return 'Ce nom est déjà pris.';
        }
        return null;
    }

    /**
     * Un nom est pris s'il est en service, en cours de confirmation, ou s'il a
     * été coupé.
     *
     * Le cas « coupé » compte : un sous-domaine qu'on révoque l'est pour un
     * motif, et le rendre à la minute suivante — au même ou à un autre —
     * annulerait la décision. Seuls les noms ABANDONNÉS (plus de signe de vie
     * pendant trois mois) retournent au pot commun ; c'est là toute la
     * différence entre « expiré » et « révoqué ».
     */
    /**
     * Vrai si ce nom est en service — donc repris par qui l'a réservé.
     *
     * Un nom révoqué n'est pas reprenable : il a été coupé pour un motif. Un
     * nom libre non plus, évidemment : il se réserve.
     */
    public function reprenable(string $nom): bool
    {
        $q = $this->db->prepare("SELECT 1 FROM registry_servers WHERE name = ? AND state = 'active' LIMIT 1");
        $q->execute([strtolower(trim($nom))]);
        return (bool)$q->fetchColumn();
    }

    private function nomPris(string $nom): bool
    {
        $q = $this->db->prepare(
            "SELECT 1 FROM registry_servers
              WHERE name = ?
                AND (state IN ('active', 'revoked')
                     OR (state = 'pending' AND created_at > ?))
              LIMIT 1"
        );
        $q->execute([$nom, $this->ilYA(self::HEURES_DE_CONFIRMATION * 3600)]);
        return (bool)$q->fetchColumn();
    }

    // ── Réserver, confirmer ───────────────────────────────────────────────

    /**
     * Réserve un nom et envoie le courriel de confirmation.
     *
     * @return string L'identifiant de réservation, que l'installateur
     *                interrogera jusqu'à ce que l'adresse soit confirmée.
     * @throws RuntimeException avec un message destiné à être lu tel quel.
     */
    public function reserver(string $nom, string $adresse, string $ipDemandeur): string
    {
        $nom = strtolower(trim($nom));
        $adresse = trim($adresse);

        if (!filter_var($adresse, FILTER_VALIDATE_EMAIL)) {
            throw new RuntimeException('Cette adresse de courriel n\'a pas l\'air valide.');
        }

        // Reprendre un nom qu'on possède déjà.
        //
        // Un serveur se réinstalle : nouvelle machine, disque changé, dossier
        // effacé. Le nom, lui, est resté — et son jeton est perdu avec
        // l'ancienne installation. Sans ce chemin, la seule issue serait de
        // choisir un autre nom, c'est-à-dire de prévenir toute la famille.
        //
        // La preuve de propriété est la même qu'à la première fois : le
        // courriel. Même adresse, même personne ; une autre adresse, et le nom
        // reste pris, comme il se doit.
        if ($reprise = $this->proprietaire($nom, $adresse)) {
            return $this->prepareLaReprise($reprise, $adresse, $ipDemandeur);
        }

        if ($refus = $this->refusDuNom($nom)) {
            throw new RuntimeException($refus);
        }
        if ($this->tropDeReservations($ipDemandeur)) {
            throw new RuntimeException(
                'Trop de noms réservés depuis cette connexion aujourd\'hui. Réessaie demain.'
            );
        }

        $reservation = bin2hex(random_bytes(16));
        $confirmation = bin2hex(random_bytes(16));

        $q = $this->db->prepare(
            'INSERT INTO registry_servers
                (name, email, state, claim_id, confirm_code, claim_ip, created_at)
             VALUES (?, ?, \'pending\', ?, ?, ?, NOW())'
        );
        $q->execute([$nom, $adresse, $reservation, $confirmation, $ipDemandeur]);

        $this->envoyerLaConfirmation($nom, $adresse, $confirmation);
        return $reservation;
    }

    /**
     * La ligne de ce nom si elle appartient DÉJÀ à cette adresse de courriel.
     *
     * Un nom révoqué ne se reprend pas : il a été coupé pour un motif, et le
     * rendre à son propriétaire annulerait la décision.
     */
    private function proprietaire(string $nom, string $adresse): ?array
    {
        $q = $this->db->prepare(
            "SELECT * FROM registry_servers
              WHERE name = ? AND state = 'active' AND LOWER(email) = LOWER(?)
              LIMIT 1"
        );
        $q->execute([$nom, $adresse]);
        $ligne = $q->fetch(PDO::FETCH_ASSOC);
        return $ligne ?: null;
    }

    /**
     * Prépare la reprise : un nouveau code de confirmation sur la ligne
     * existante, et un courriel qui dit clairement ce qui va se passer.
     *
     * Le jeton actuel reste valable jusqu'à la confirmation : si la personne
     * ne confirme pas, son serveur d'origine continue de fonctionner comme
     * avant. Rien n'est cassé par une reprise entamée puis abandonnée.
     */
    private function prepareLaReprise(array $ligne, string $adresse, string $ipDemandeur): string
    {
        $reservation = bin2hex(random_bytes(16));
        $confirmation = bin2hex(random_bytes(16));

        $q = $this->db->prepare(
            'UPDATE registry_servers
                SET claim_id = ?, confirm_code = ?, claim_ip = ?
              WHERE id = ?'
        );
        $q->execute([$reservation, $confirmation, $ipDemandeur, $ligne['id']]);

        $this->envoyerLaConfirmation((string)$ligne['name'], $adresse, $confirmation, true);
        $this->noter('reprise-demandee', (string)$ligne['name'], null, $ipDemandeur);

        return $reservation;
    }

    private function tropDeReservations(string $ip): bool
    {
        $q = $this->db->prepare(
            'SELECT COUNT(*) FROM registry_servers WHERE claim_ip = ? AND created_at > ?'
        );
        $q->execute([$ip, $this->ilYA(86400)]);
        return (int)$q->fetchColumn() >= self::RESERVATIONS_PAR_JOUR;
    }

    private function envoyerLaConfirmation(string $nom, string $adresse, string $code, bool $reprise = false): void
    {
        $lien = rtrim((string)AppConfig::get('app.url'), '/') . '/confirmer-serveur.php?code=' . $code;
        $complet = $nom . '.' . $this->domaine;

        $quoi = $reprise
            ? "Quelqu'un vient de demander à REPRENDRE « $complet » sur une autre\n"
                . "machine. Ton serveur actuel continuera de fonctionner tant que ce lien\n"
                . "n'est pas ouvert."
            : "Quelqu'un vient de réserver « $complet » pour son serveur de musique\n"
                . "GulliFY, avec cette adresse de courriel.";

        $texte = <<<TEXTE
            Bonjour,

            $quoi

            Si c'est toi, confirme en ouvrant ce lien :
            $lien

            Le lien vaut 48 heures. Si ce n'est pas toi, ignore ce message : sans
            confirmation, le nom est rendu à tout le monde.

            — GulliFY
            TEXTE;

        $html = '<p>Bonjour,</p><p>' . ($reprise
                ? 'Quelqu\'un vient de demander à <strong>reprendre</strong> '
                    . htmlspecialchars($complet, ENT_QUOTES, 'UTF-8')
                    . ' sur une autre machine. Ton serveur actuel continuera de fonctionner '
                    . 'tant que ce lien n\'est pas ouvert.'
                : 'Quelqu\'un vient de réserver <strong>'
                    . htmlspecialchars($complet, ENT_QUOTES, 'UTF-8')
                    . '</strong> pour son serveur de musique GulliFY, avec cette adresse de courriel.')
            . '</p>'
            . '<p>Si c\'est toi : <a href="' . htmlspecialchars($lien, ENT_QUOTES, 'UTF-8') . '">confirme ici</a>.</p>'
            . '<p>Le lien vaut 48 heures. Si ce n\'est pas toi, ignore ce message : sans confirmation, '
            . 'le nom est rendu à tout le monde.</p><p>— GulliFY</p>';

        $this->courriel->envoyer(
            $adresse,
            $reprise ? "Reprendre $complet sur une autre machine" : "Confirme ton serveur $complet",
            $texte,
            $html
        );
    }

    /**
     * Le clic dans le courriel : le nom devient actif et son enregistrement DNS
     * est posé sur l'adresse d'où la réservation est partie.
     *
     * @return string Le nom entier, pour l'afficher sur la page de confirmation.
     */
    public function confirmer(string $code): string
    {
        // Une réservation neuve, ou la reprise d'un nom déjà en service : les
        // deux portent un code de confirmation, et aboutissent au même endroit
        // — un nouveau jeton, remis une seule fois.
        $q = $this->db->prepare(
            "SELECT * FROM registry_servers
              WHERE confirm_code = ? AND state IN ('pending', 'active')"
        );
        $q->execute([$code]);
        $ligne = $q->fetch(PDO::FETCH_ASSOC);

        if (!$ligne) {
            throw new RuntimeException(
                'Ce lien n\'est plus valable. Relance l\'installateur pour réserver ton nom à nouveau.'
            );
        }

        $reprise = ((string)$ligne['state']) === 'active';

        // Une réservation neuve expire ; une reprise, elle, porte sur un nom
        // qu'on possède déjà et peut attendre.
        if (!$reprise && strtotime((string)$ligne['created_at']) < time() - self::HEURES_DE_CONFIRMATION * 3600) {
            throw new RuntimeException(
                'Ce lien a expiré. Relance l\'installateur pour réserver ton nom à nouveau.'
            );
        }

        // Entre-temps, quelqu'un a pu confirmer le même nom : le premier arrivé
        // l'emporte, et on le dit clairement au second.
        if (!$reprise && $this->estActif((string)$ligne['name'])) {
            throw new RuntimeException('Ce nom a été pris entre-temps. Relance l\'installateur et choisis-en un autre.');
        }

        $jeton = bin2hex(random_bytes(24));
        $fqdn = $ligne['name'] . '.' . $this->domaine;
        $id = $this->dns->upsertA($fqdn, (string)$ligne['claim_ip']);

        $maj = $this->db->prepare(
            "UPDATE registry_servers
                SET state = 'active', confirmed_at = NOW(), confirm_code = NULL,
                    token_hash = ?, token_pickup = ?, ip = claim_ip,
                    dns_record_id = ?, last_seen = NOW()
              WHERE id = ?"
        );
        $maj->execute([hash('sha256', $jeton), $jeton, $id, $ligne['id']]);

        $this->noter($reprise ? 'reprise-confirmee' : 'confirme', $ligne['name'], null, (string)$ligne['claim_ip']);
        return $fqdn;
    }

    private function estActif(string $nom): bool
    {
        $q = $this->db->prepare("SELECT 1 FROM registry_servers WHERE name = ? AND state = 'active' LIMIT 1");
        $q->execute([$nom]);
        return (bool)$q->fetchColumn();
    }

    /**
     * Ce que l'installateur demande en boucle pendant que l'utilisateur va voir
     * ses courriels.
     *
     * Le jeton n'est remis qu'une fois : dès qu'il est pris, la copie en clair
     * disparaît de la base et il ne reste que son empreinte.
     *
     * @return array{state: string, name: string, fqdn: string, token: ?string}
     */
    public function etatReservation(string $reservation): array
    {
        $q = $this->db->prepare('SELECT * FROM registry_servers WHERE claim_id = ?');
        $q->execute([$reservation]);
        $ligne = $q->fetch(PDO::FETCH_ASSOC);

        if (!$ligne) {
            throw new RuntimeException('Cette réservation n\'existe pas.');
        }

        $jeton = $ligne['token_pickup'] ?: null;
        if ($jeton !== null) {
            $this->db->prepare('UPDATE registry_servers SET token_pickup = NULL WHERE id = ?')
                ->execute([$ligne['id']]);
        }

        return [
            'state' => (string)$ligne['state'],
            'name'  => (string)$ligne['name'],
            'fqdn'  => $ligne['name'] . '.' . $this->domaine,
            'token' => $jeton,
        ];
    }

    // ── Suivre l'adresse IP ───────────────────────────────────────────────

    /**
     * Le serveur de salon dit « me voici ». On ne touche au DNS que si son
     * adresse a changé : la plupart des appels ne font qu'écrire une date.
     *
     * @return array{fqdn: string, ip: string, changed: bool}
     */
    public function majIp(string $jeton, string $ip): array
    {
        // Publique, et rien d'autre. Une adresse de réseau local publiée dans le
        // DNS enverrait tout le monde chez lui-même ; un serveur injoignable est
        // moins grave qu'un nom qui pointe n'importe où.
        if (!filter_var(
            $ip,
            FILTER_VALIDATE_IP,
            FILTER_FLAG_IPV4 | FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE
        )) {
            throw new RuntimeException('Adresse IPv4 publique attendue, reçu « ' . $ip . ' ».');
        }

        $q = $this->db->prepare("SELECT * FROM registry_servers WHERE token_hash = ? AND state = 'active'");
        $q->execute([hash('sha256', $jeton)]);
        $ligne = $q->fetch(PDO::FETCH_ASSOC);

        if (!$ligne) {
            throw new RuntimeException('Jeton inconnu ou serveur révoqué.');
        }

        $fqdn = $ligne['name'] . '.' . $this->domaine;
        $change = ((string)$ligne['ip']) !== $ip;

        if ($change) {
            $id = $this->dns->upsertA($fqdn, $ip);
            $this->db->prepare('UPDATE registry_servers SET ip = ?, dns_record_id = ?, last_seen = NOW() WHERE id = ?')
                ->execute([$ip, $id, $ligne['id']]);
        } else {
            $this->db->prepare('UPDATE registry_servers SET last_seen = NOW() WHERE id = ?')
                ->execute([$ligne['id']]);
        }

        return ['fqdn' => $fqdn, 'ip' => $ip, 'changed' => $change];
    }

    // ── Ce qui se passe mal ───────────────────────────────────────────────

    /**
     * Garde une trace de ce qui empêche les gens d'installer : routeur fermé,
     * réseau d'opérateur, Docker refusé. C'est ce qui dira, chiffres en main,
     * s'il faut construire le tunnel.
     */
    public function noter(string $genre, ?string $nom, ?string $detail, string $ip): void
    {
        $q = $this->db->prepare(
            'INSERT INTO registry_events (name, kind, detail, ip, created_at) VALUES (?, ?, ?, ?, NOW())'
        );
        $q->execute([$nom, substr($genre, 0, 40), $detail === null ? null : substr($detail, 0, 255), $ip]);
    }

    /** @return array<string, int> Les genres d'échec des trente derniers jours. */
    public function comptageDesEchecs(): array
    {
        $q = $this->db->query(
            'SELECT kind, COUNT(*) AS n FROM registry_events
              WHERE created_at > DATE_SUB(NOW(), INTERVAL 30 DAY)
              GROUP BY kind ORDER BY n DESC'
        );
        $total = [];
        foreach ($q->fetchAll(PDO::FETCH_ASSOC) as $l) {
            $total[(string)$l['kind']] = (int)$l['n'];
        }
        return $total;
    }

    // ── Entretien ─────────────────────────────────────────────────────────

    /**
     * Rend à tout le monde les noms qui ne donnent plus signe de vie, et
     * prévient ceux qui s'en approchent. À passer une fois par jour.
     *
     * @return array{avertis: int, liberes: int}
     */
    public function entretien(): array
    {
        $avertis = 0;
        $liberes = 0;

        $q = $this->db->prepare(
            "SELECT * FROM registry_servers
              WHERE state = 'active' AND last_seen < ?"
        );
        $q->execute([$this->ilYA(self::JOURS_AVANT_AVERTISSEMENT * 86400)]);

        foreach ($q->fetchAll(PDO::FETCH_ASSOC) as $ligne) {
            $silence = (time() - strtotime((string)$ligne['last_seen'])) / 86400;
            $fqdn = $ligne['name'] . '.' . $this->domaine;

            if ($silence >= self::JOURS_AVANT_EXPIRATION) {
                $this->dns->deleteA($fqdn);
                $this->db->prepare("UPDATE registry_servers SET state = 'expired' WHERE id = ?")
                    ->execute([$ligne['id']]);
                $this->noter('expire', (string)$ligne['name'], (int)$silence . ' jours de silence', '');
                $liberes++;
                continue;
            }

            if (empty($ligne['warned_at'])) {
                $reste = (int)ceil(self::JOURS_AVANT_EXPIRATION - $silence);
                $this->courriel->envoyer(
                    (string)$ligne['email'],
                    "Ton serveur $fqdn va perdre son nom",
                    "Ton serveur n'a plus donné signe de vie depuis " . (int)$silence . " jours.\n"
                    . "Sans nouvelles d'ici $reste jours, le nom « $fqdn » sera rendu à tout le monde.\n\n"
                    . "Il suffit de rallumer ton serveur pour que tout rentre dans l'ordre.\n\n— GulliFY",
                    "<p>Ton serveur n'a plus donné signe de vie depuis " . (int)$silence . " jours.</p>"
                    . "<p>Sans nouvelles d'ici $reste jours, le nom <strong>$fqdn</strong> sera rendu à tout le monde.</p>"
                    . "<p>Il suffit de rallumer ton serveur pour que tout rentre dans l'ordre.</p><p>— GulliFY</p>"
                );
                $this->db->prepare('UPDATE registry_servers SET warned_at = NOW() WHERE id = ?')
                    ->execute([$ligne['id']]);
                $avertis++;
            }
        }

        return ['avertis' => $avertis, 'liberes' => $liberes];
    }

    /** Coupe un sous-domaine : le DNS disparaît, le nom reste bloqué. */
    public function revoquer(string $nom, string $motif): void
    {
        $this->dns->deleteA($nom . '.' . $this->domaine);
        $this->db->prepare("UPDATE registry_servers SET state = 'revoked' WHERE name = ?")->execute([$nom]);
        $this->noter('revoque', $nom, $motif, '');
    }

    // ── Plomberie ─────────────────────────────────────────────────────────

    private function ilYA(int $secondes): string
    {
        return date('Y-m-d H:i:s', time() - $secondes);
    }

    /**
     * Les tables n'existent que là où le service tourne. Elles sont créées à la
     * demande plutôt que par le schéma général : les serveurs installés chez les
     * gens n'ont pas à porter des tables qu'ils n'utiliseront jamais.
     */
    private function creerTables(): void
    {
        $this->db->exec(
            'CREATE TABLE IF NOT EXISTS registry_servers (
                id            INT AUTO_INCREMENT PRIMARY KEY,
                name          VARCHAR(63)  NOT NULL,
                email         VARCHAR(190) NOT NULL,
                state         ENUM(\'pending\',\'active\',\'expired\',\'revoked\') NOT NULL DEFAULT \'pending\',
                claim_id      CHAR(32)     NOT NULL,
                confirm_code  CHAR(32)     NULL,
                token_hash    CHAR(64)     NULL,
                token_pickup  VARCHAR(64)  NULL,
                ip            VARCHAR(45)  NULL,
                claim_ip      VARCHAR(45)  NOT NULL,
                dns_record_id VARCHAR(64)  NULL,
                created_at    DATETIME     NOT NULL,
                confirmed_at  DATETIME     NULL,
                last_seen     DATETIME     NULL,
                warned_at     DATETIME     NULL,
                UNIQUE KEY uniq_claim (claim_id),
                KEY idx_name (name),
                KEY idx_state (state),
                KEY idx_seen (last_seen),
                KEY idx_token (token_hash)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'
        );

        $this->db->exec(
            'CREATE TABLE IF NOT EXISTS registry_events (
                id         INT AUTO_INCREMENT PRIMARY KEY,
                name       VARCHAR(63)  NULL,
                kind       VARCHAR(40)  NOT NULL,
                detail     VARCHAR(255) NULL,
                ip         VARCHAR(45)  NULL,
                created_at DATETIME     NOT NULL,
                KEY idx_kind (kind),
                KEY idx_date (created_at)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'
        );
    }
}
