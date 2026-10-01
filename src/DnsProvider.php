<?php
/**
 * Le DNS, vu par le service d'inscription.
 *
 * Une interface pour une seule raison : pouvoir tout essayer sans toucher au
 * vrai domaine. Le pilote factice écrit dans un fichier, le vrai parle à
 * IONOS ; le reste du code ne sait pas lequel il a en main.
 */
declare(strict_types=1);

interface DnsProvider
{
    /**
     * Pose ou met à jour l'enregistrement A d'un sous-domaine.
     *
     * @param string $fqdn Le nom entier, par exemple « papa.gullify.app ».
     * @param string $ip   L'adresse IPv4 vers laquelle il pointe.
     * @return string Un identifiant d'enregistrement, à conserver pour pouvoir
     *                le modifier ou le retirer ensuite.
     */
    public function upsertA(string $fqdn, string $ip): string;

    /** Retire l'enregistrement. Ne lève rien s'il a déjà disparu. */
    public function deleteA(string $fqdn): void;

    /** L'adresse actuellement publiée, ou null si le nom n'existe pas. */
    public function lookupA(string $fqdn): ?string;
}

/**
 * Le pilote d'essai : un fichier JSON en guise de zone.
 *
 * Il sert à tout : les essais automatisés, et la mise au point avant que la
 * clé IONOS existe. Il se comporte comme le vrai, y compris quand on lui
 * demande de retirer un nom absent.
 */
final class FakeDns implements DnsProvider
{
    private string $fichier;

    public function __construct(?string $fichier = null)
    {
        $this->fichier = $fichier ?? sys_get_temp_dir() . '/gullify-dns-fictif.json';
    }

    public function upsertA(string $fqdn, string $ip): string
    {
        $zone = $this->zone();
        $zone[$fqdn] = ['ip' => $ip, 'id' => $zone[$fqdn]['id'] ?? bin2hex(random_bytes(8))];
        $this->ecrire($zone);
        return $zone[$fqdn]['id'];
    }

    public function deleteA(string $fqdn): void
    {
        $zone = $this->zone();
        unset($zone[$fqdn]);
        $this->ecrire($zone);
    }

    public function lookupA(string $fqdn): ?string
    {
        return $this->zone()[$fqdn]['ip'] ?? null;
    }

    /** @return array<string, array{ip: string, id: string}> */
    private function zone(): array
    {
        if (!is_file($this->fichier)) {
            return [];
        }
        $j = json_decode((string)file_get_contents($this->fichier), true);
        return is_array($j) ? $j : [];
    }

    private function ecrire(array $zone): void
    {
        file_put_contents($this->fichier, json_encode($zone, JSON_PRETTY_PRINT));
    }
}
