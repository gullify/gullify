<?php
/**
 * L'envoi de courriel du service d'inscription.
 *
 * Un seul courriel part aujourd'hui : le lien qui confirme qu'une adresse
 * existe avant d'accorder un sous-domaine. C'est peu, mais il doit arriver —
 * sinon l'installation s'arrête là.
 *
 * Deux pilotes :
 *   - `journal` (défaut) : rien ne part, tout est écrit dans un fichier. C'est
 *     ce qui permet de construire et d'essayer sans compte d'envoi.
 *   - `http` : un service d'envoi qui parle JSON (Brevo, Resend…). Pas de SMTP :
 *     les adresses IP de VPS sont massivement classées indésirables, un service
 *     d'envoi est le seul moyen d'arriver dans la boîte de réception.
 *
 * Réglages (.env) :
 *   MAIL_DRIVER=journal|http
 *   MAIL_FROM="GulliFY <bonjour@gullify.app>"
 *   MAIL_HTTP_URL=https://api.resend.com/emails
 *   MAIL_HTTP_TOKEN=…
 */
declare(strict_types=1);

final class Mailer
{
    private string $pilote;
    private string $expediteur;
    private ?string $url;
    private ?string $jeton;
    private string $journal;

    public function __construct(
        string $pilote,
        string $expediteur,
        ?string $url = null,
        ?string $jeton = null,
        ?string $journal = null
    ) {
        $this->pilote = $pilote;
        $this->expediteur = $expediteur;
        $this->url = $url;
        $this->jeton = $jeton;
        $this->journal = $journal ?? (sys_get_temp_dir() . '/gullify-courriels.log');
    }

    public static function fromConfig(): self
    {
        return new self(
            (string)AppConfig::get('mail.driver', 'journal'),
            (string)AppConfig::get('mail.from', 'GulliFY <bonjour@gullify.app>'),
            AppConfig::get('mail.http_url') ?: null,
            AppConfig::get('mail.http_token') ?: null,
            AppConfig::get('mail.log') ?: null,
        );
    }

    /** Vrai si un courriel partirait vraiment — l'installateur le dit à l'écran. */
    public function envoiReel(): bool
    {
        return $this->pilote === 'http' && $this->url && $this->jeton;
    }

    /**
     * @throws RuntimeException si l'envoi échoue — l'appelant doit le dire à
     *         l'utilisateur plutôt que de prétendre que le courriel est parti.
     */
    public function envoyer(string $destinataire, string $sujet, string $texte, string $html): void
    {
        if (!$this->envoiReel()) {
            $trace = sprintf(
                "[%s] à %s\nSujet : %s\n%s\n%s\n",
                date('c'),
                $destinataire,
                $sujet,
                str_repeat('-', 60),
                $texte
            );
            file_put_contents($this->journal, $trace, FILE_APPEND);
            return;
        }

        $ch = curl_init($this->url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_POST           => true,
            CURLOPT_TIMEOUT        => 20,
            CURLOPT_HTTPHEADER     => [
                'Authorization: Bearer ' . $this->jeton,
                'Content-Type: application/json',
            ],
            CURLOPT_POSTFIELDS => json_encode([
                'from'    => $this->expediteur,
                'to'      => [$destinataire],
                'subject' => $sujet,
                'text'    => $texte,
                'html'    => $html,
            ]),
        ]);
        $reponse = curl_exec($ch);
        $code = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        curl_close($ch);

        if ($reponse === false || $code >= 300) {
            throw new RuntimeException("Le service d'envoi a refusé le courriel ($code)");
        }
    }
}
