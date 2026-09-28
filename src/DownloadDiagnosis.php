<?php
/**
 * Gullify — Pourquoi ce téléchargement a-t-il échoué ?
 *
 * « Échec du téléchargement (code: 1) » ne dit rien : yt-dlp sort en 1 aussi
 * bien pour un disque retiré de YouTube que pour un contrôle anti-robot, et
 * seul le second vaut la peine d'être réessayé tout de suite. Or c'est ce
 * code nu que l'app affichait, laissant chercher la cause dans un journal que
 * l'app ne montre pas.
 *
 * On relit donc la sortie de yt-dlp, du motif le plus parlant au plus
 * générique, et à défaut on rend la dernière ligne ERROR débarrassée de ce
 * que yt-dlp colle autour (préfixe d'extracteur, identifiant de vidéo, liens
 * d'aide). Les messages sont courts : la tuile de la file d'attente leur
 * donne deux lignes.
 */

class DownloadDiagnosis
{
    /** Longueur au-delà de laquelle une ligne ERROR brute est coupée. */
    private const MAX_RAW_LENGTH = 120;

    /**
     * @param string $logFile  Journal écrit par scripts/download-worker.php.
     * @param int    $exitCode Code de sortie de yt-dlp, gardé en dernier recours.
     */
    public static function describe(string $logFile, int $exitCode): string
    {
        $log = is_file($logFile) ? (string)file_get_contents($logFile) : '';

        $known = self::fromKnownPatterns($log);
        if ($known !== null) return $known;

        $raw = self::fromLastError($log);
        if ($raw !== null) return 'Échec : ' . $raw;

        return "Échec du téléchargement (code: $exitCode)";
    }

    /** Les échecs qu'on sait nommer, du plus précis au plus large. */
    private static function fromKnownPatterns(string $log): ?string
    {
        // L'apostrophe de « you're » est typographique dans la sortie de
        // YouTube : on cherche les deux bouts de la phrase, pas la phrase.
        if (stripos($log, 'Sign in to confirm') !== false && stripos($log, 'not a bot') !== false) {
            return "YouTube demande une vérification anti-robot : réessayez dans quelques minutes";
        }
        if (strpos($log, 'HTTP Error 429') !== false) {
            return "YouTube limite les requêtes du serveur : réessayez plus tard";
        }
        if (stripos($log, 'Music Premium') !== false || stripos($log, 'members-only') !== false) {
            return "Ce disque est réservé aux abonnés YouTube Premium";
        }
        if (stripos($log, 'Video unavailable') !== false || stripos($log, 'Private video') !== false) {
            return "Ces titres ne sont plus disponibles sur YouTube";
        }
        if (stripos($log, 'No space left on device') !== false) {
            return "Plus d'espace disque sur le serveur";
        }
        if (stripos($log, 'Unsupported URL') !== false) {
            return "Lien non reconnu par yt-dlp";
        }
        return null;
    }

    /** La dernière ligne ERROR, nettoyée ; null si le journal n'en a aucune. */
    private static function fromLastError(string $log): ?string
    {
        if (!preg_match_all('/^ERROR:\s*(.+)$/m', $log, $matches)) return null;

        $line = trim((string)end($matches[1]));
        $line = preg_replace('/^\[[^\]]+\]\s*/', '', $line);        // [youtube]
        $line = preg_replace('/^[\w-]{11}:\s*/', '', $line);        // AbCdEfGhIjK:
        $line = preg_split('/\.\s+(Use|See)\s/', $line)[0];         // « . Use --cookies… »
        $line = trim($line);

        return $line === '' ? null : mb_substr($line, 0, self::MAX_RAW_LENGTH);
    }
}
