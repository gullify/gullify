<?php
/**
 * L'envoi de courriel du service d'inscription.
 *
 * Un seul courriel part aujourd'hui : le lien qui confirme qu'une adresse
 * existe avant d'accorder un sous-domaine. C'est peu, mais il doit arriver —
 * sinon l'installation s'arrête là.
 *
 * Trois pilotes :
 *   - `journal` (défaut) : rien ne part, tout est écrit dans un fichier. C'est
 *     ce qui permet de construire et d'essayer sans compte d'envoi.
 *   - `smtp` : la boîte du domaine, chez IONOS. C'est le chemin retenu —
 *     l'enregistrement SPF de gullify.app autorise déjà les serveurs d'IONOS,
 *     donc le courriel part d'une adresse que le domaine reconnaît. Envoyer
 *     directement depuis le VPS, en revanche, finirait en indésirable : son
 *     adresse IP n'est pas dans le SPF, et les IP de VPS sont mal notées.
 *   - `http` : un service d'envoi qui parle JSON (Brevo, Resend…), si un jour
 *     le volume dépasse ce qu'une boîte IONOS accepte.
 *
 * Réglages (.env) :
 *   MAIL_DRIVER=journal|smtp|http
 *   MAIL_FROM="GulliFY <info@gullify.app>"
 *   MAIL_SMTP_HOST=smtp.ionos.com      MAIL_SMTP_PORT=587
 *   MAIL_SMTP_USER=info@gullify.app    MAIL_SMTP_PASSWORD=…
 *   MAIL_HTTP_URL=…                    MAIL_HTTP_TOKEN=…
 */
declare(strict_types=1);

final class Mailer
{
    private string $pilote;
    private string $expediteur;
    private ?string $url;
    private ?string $jeton;
    private string $journal;
    private array $smtp;

    public function __construct(
        string $pilote,
        string $expediteur,
        ?string $url = null,
        ?string $jeton = null,
        ?string $journal = null,
        array $smtp = []
    ) {
        $this->pilote = $pilote;
        $this->expediteur = $expediteur;
        $this->url = $url;
        $this->jeton = $jeton;
        $this->journal = $journal ?? (sys_get_temp_dir() . '/gullify-courriels.log');
        $this->smtp = $smtp;
    }

    public static function fromConfig(): self
    {
        return new self(
            (string)AppConfig::get('mail.driver', 'journal'),
            (string)AppConfig::get('mail.from', 'GulliFY <bonjour@gullify.app>'),
            AppConfig::get('mail.http_url') ?: null,
            AppConfig::get('mail.http_token') ?: null,
            AppConfig::get('mail.log') ?: null,
            [
                'hote'  => (string)AppConfig::get('mail.smtp_host', 'smtp.ionos.com'),
                'port'  => (int)AppConfig::get('mail.smtp_port', 587),
                'nom'   => (string)AppConfig::get('mail.smtp_user', ''),
                'mdp'   => (string)AppConfig::get('mail.smtp_password', ''),
            ],
        );
    }

    /** Vrai si un courriel partirait vraiment — l'installateur le dit à l'écran. */
    public function envoiReel(): bool
    {
        if ($this->pilote === 'http') {
            return (bool)($this->url && $this->jeton);
        }
        if ($this->pilote === 'smtp') {
            return ($this->smtp['nom'] ?? '') !== '' && ($this->smtp['mdp'] ?? '') !== '';
        }
        return false;
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

        if ($this->pilote === 'smtp') {
            $this->parSmtp($destinataire, $sujet, $texte, $html);
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

    // ── SMTP ──────────────────────────────────────────────────────────────

    /**
     * Un client SMTP minimal : connexion, STARTTLS, authentification, envoi.
     *
     * Écrit à la main plutôt qu'avec une bibliothèque parce que le serveur n'a
     * pas de gestionnaire de dépendances PHP, et qu'un seul courriel part d'ici.
     * Chaque réponse du serveur est vérifiée : un envoi qui échoue doit le dire,
     * sans quoi quelqu'un attendrait indéfiniment un courriel qui n'arrive pas.
     */
    private function parSmtp(string $destinataire, string $sujet, string $texte, string $html): void
    {
        $hote = (string)($this->smtp['hote'] ?? 'smtp.ionos.com');
        $port = (int)($this->smtp['port'] ?? 587);

        $flux = @stream_socket_client("tcp://$hote:$port", $errno, $errstr, 15);
        if ($flux === false) {
            throw new RuntimeException("SMTP injoignable ($hote:$port) : $errstr");
        }
        stream_set_timeout($flux, 15);

        try {
            $this->attendre($flux, 220);
            $this->dire($flux, 'EHLO gullify.app', 250);

            // STARTTLS : le mot de passe ne doit jamais traverser en clair.
            $this->dire($flux, 'STARTTLS', 220);
            if (!stream_socket_enable_crypto($flux, true, STREAM_CRYPTO_METHOD_TLS_CLIENT)) {
                throw new RuntimeException('SMTP : le chiffrement TLS a échoué');
            }
            $this->dire($flux, 'EHLO gullify.app', 250);

            $this->dire($flux, 'AUTH LOGIN', 334);
            $this->dire($flux, base64_encode((string)$this->smtp['nom']), 334);
            $this->dire($flux, base64_encode((string)$this->smtp['mdp']), 235);

            $this->dire($flux, 'MAIL FROM:<' . $this->adresseSeule($this->expediteur) . '>', 250);
            $this->dire($flux, 'RCPT TO:<' . $destinataire . '>', 250);
            $this->dire($flux, 'DATA', 354);

            fwrite($flux, $this->message($destinataire, $sujet, $texte, $html));
            $this->attendre($flux, 250);
            $this->dire($flux, 'QUIT', 221);
        } finally {
            fclose($flux);
        }
    }

    /** Envoie une commande et vérifie le code de réponse. */
    private function dire($flux, string $commande, int $attendu): void
    {
        fwrite($flux, $commande . "\r\n");
        $this->attendre($flux, $attendu);
    }

    /**
     * Lit une réponse, en suivant les lignes de continuation (« 250-… »), et
     * vérifie son code.
     */
    private function attendre($flux, int $attendu): string
    {
        $tout = '';
        while (($ligne = fgets($flux, 1024)) !== false) {
            $tout .= $ligne;
            // Une réponse se termine par « 250 texte » ; « 250-texte » annonce
            // qu'il en reste.
            if (strlen($ligne) >= 4 && $ligne[3] === ' ') {
                break;
            }
        }
        $code = (int)substr(ltrim($tout), 0, 3);
        if ($code !== $attendu) {
            throw new RuntimeException("SMTP a répondu « " . trim($tout) . " » là où $attendu était attendu");
        }
        return $tout;
    }

    /** « GulliFY <info@gullify.app> » → « info@gullify.app ». */
    private function adresseSeule(string $expediteur): string
    {
        return preg_match('/<([^>]+)>/', $expediteur, $m) ? $m[1] : trim($expediteur);
    }

    /**
     * Le message lui-même : deux versions, texte et HTML, pour que chacun
     * l'affiche à sa façon.
     *
     * Les deux sont encodées en base64, ce qui règle d'un coup trois ennuis :
     * les accents, les lignes trop longues, et le point seul en début de ligne
     * qui couperait le message en deux (l'alphabet base64 ne contient pas de
     * point, donc le cas ne peut pas se produire).
     */
    private function message(string $destinataire, string $sujet, string $texte, string $html): string
    {
        $limite = 'gullify-' . bin2hex(random_bytes(8));
        $entetes = [
            'From: ' . $this->expediteur,
            'To: ' . $destinataire,
            'Subject: =?UTF-8?B?' . base64_encode($sujet) . '?=',
            'Date: ' . date('r'),
            'Message-ID: <' . bin2hex(random_bytes(12)) . '@gullify.app>',
            'MIME-Version: 1.0',
            'Content-Type: multipart/alternative; boundary="' . $limite . '"',
        ];

        $corps = "--$limite\r\n"
            . "Content-Type: text/plain; charset=UTF-8\r\n"
            . "Content-Transfer-Encoding: base64\r\n\r\n"
            . chunk_split(base64_encode($texte)) . "\r\n"
            . "--$limite\r\n"
            . "Content-Type: text/html; charset=UTF-8\r\n"
            . "Content-Transfer-Encoding: base64\r\n\r\n"
            . chunk_split(base64_encode($html)) . "\r\n"
            . "--$limite--\r\n";

        return implode("\r\n", $entetes) . "\r\n\r\n" . $corps . "\r\n.\r\n";
    }
}
