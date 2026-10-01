<?php
/**
 * Le DNS de gullify.app, chez IONOS.
 *
 * API v1 : https://api.hosting.ionos.com/dns/v1
 * Authentification par en-tête `X-API-Key: <prefixe>.<secret>` — la clé se
 * crée dans l'espace client IONOS (Domaines & SSL → API DNS). Elle ne vit que
 * dans le .env du serveur central, jamais dans l'installateur.
 *
 * ATTENTION : écrit d'après la documentation publique, mais jamais exécuté
 * contre le vrai service — la clé n'existait pas encore. Le script
 * `scripts/verifier-ionos.php` vérifie chaque appel contre la vraie zone ; il
 * doit être passé avant de croire cette classe sur parole.
 */
declare(strict_types=1);

require_once __DIR__ . '/DnsProvider.php';

final class IonosDns implements DnsProvider
{
    private const BASE = 'https://api.hosting.ionos.com/dns/v1';

    /** La durée de vie des enregistrements : courte, puisque l'IP bouge. */
    private const TTL = 60;

    private string $cle;
    private string $zoneNom;
    private ?string $zoneId = null;

    public function __construct(string $cle, string $zoneNom)
    {
        $this->cle = $cle;
        $this->zoneNom = strtolower($zoneNom);
    }

    public function upsertA(string $fqdn, string $ip): string
    {
        $existant = $this->trouver($fqdn);
        $corps = [
            'disabled' => false,
            'content'  => $ip,
            'ttl'      => self::TTL,
            'prio'     => 0,
        ];

        if ($existant !== null) {
            $this->appel('PUT', "/zones/{$this->zone()}/records/{$existant['id']}", $corps);
            return (string)$existant['id'];
        }

        // La création prend un tableau : l'API accepte plusieurs enregistrements
        // d'un coup, on n'en pose qu'un.
        $this->appel('POST', "/zones/{$this->zone()}/records", [[
            'name'     => $fqdn,
            'type'     => 'A',
            'content'  => $ip,
            'ttl'      => self::TTL,
            'prio'     => 0,
            'disabled' => false,
        ]]);

        $pose = $this->trouver($fqdn);
        if ($pose === null) {
            throw new RuntimeException("IONOS a accepté la création de $fqdn mais ne le retrouve pas");
        }
        return (string)$pose['id'];
    }

    public function deleteA(string $fqdn): void
    {
        $existant = $this->trouver($fqdn);
        if ($existant === null) {
            return; // déjà parti : rien à faire, et ce n'est pas une erreur
        }
        $this->appel('DELETE', "/zones/{$this->zone()}/records/{$existant['id']}");
    }

    public function lookupA(string $fqdn): ?string
    {
        $r = $this->trouver($fqdn);
        return $r === null ? null : (string)$r['content'];
    }

    /** L'identifiant de la zone, cherché une fois puis gardé. */
    private function zone(): string
    {
        if ($this->zoneId !== null) {
            return $this->zoneId;
        }
        foreach ($this->appel('GET', '/zones') as $zone) {
            if (strtolower((string)($zone['name'] ?? '')) === $this->zoneNom) {
                return $this->zoneId = (string)$zone['id'];
            }
        }
        throw new RuntimeException("La zone {$this->zoneNom} est introuvable sur ce compte IONOS");
    }

    /** @return array{id: string, content: string}|null */
    private function trouver(string $fqdn): ?array
    {
        $zone = $this->appel('GET', "/zones/{$this->zone()}?recordType=A&recordName=" . rawurlencode($fqdn));
        foreach ($zone['records'] ?? [] as $r) {
            if (strtolower((string)($r['name'] ?? '')) === strtolower($fqdn) && ($r['type'] ?? '') === 'A') {
                return ['id' => (string)$r['id'], 'content' => (string)$r['content']];
            }
        }
        return null;
    }

    private function appel(string $methode, string $chemin, ?array $corps = null): array
    {
        $ch = curl_init(self::BASE . $chemin);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_CUSTOMREQUEST  => $methode,
            CURLOPT_TIMEOUT        => 20,
            CURLOPT_HTTPHEADER     => [
                'X-API-Key: ' . $this->cle,
                'Content-Type: application/json',
                'Accept: application/json',
            ],
        ]);
        if ($corps !== null) {
            curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($corps));
        }

        $reponse = curl_exec($ch);
        $code = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        $erreur = curl_error($ch);
        curl_close($ch);

        if ($reponse === false) {
            throw new RuntimeException("IONOS injoignable ($methode $chemin) : $erreur");
        }
        if ($code >= 400) {
            // Le corps d'erreur d'IONOS contient le motif ; on le garde, tronqué,
            // parce que c'est lui qui dit si la clé est mauvaise ou le nom invalide.
            throw new RuntimeException("IONOS a refusé $methode $chemin ($code) : " . substr((string)$reponse, 0, 300));
        }

        $j = json_decode((string)$reponse, true);
        return is_array($j) ? $j : [];
    }
}
