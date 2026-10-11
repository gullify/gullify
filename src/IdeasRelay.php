<?php
/**
 * Gullify — Le facteur des idées.
 *
 * Une idée écrite sur un GulliFY quelconque est destinée au développeur, pas
 * au serveur où elle est née : celui-ci n'a personne pour la lire. Elle part
 * donc vers la boîte (`ideas.relay`), en gardant une copie chez elle pour que
 * son auteur la retrouve.
 *
 * Deux choses ne partent jamais : les idées du propriétaire de la boîte
 * lui-même (il écrit déjà chez lui), et celles d'un serveur où le relais a
 * été vidé dans le `.env` — quelqu'un peut vouloir garder ses idées pour lui.
 *
 * L'envoi ne fait jamais attendre : deux secondes au plus, et un échec se
 * rattrape au prochain affichage de la liste. Une idée perdue serait pire
 * qu'une idée en retard, mais un carnet qui gèle à l'écriture serait pire
 * que les deux.
 */

require_once __DIR__ . '/AppConfig.php';

final class IdeasRelay
{
    private const DELAI = 2;        // secondes
    private const RETARD_MIN = 300; // on ne relance pas plus d'une fois par 5 min
    private const PAR_RELANCE = 10;

    /** Ce serveur envoie-t-il les idées de [$user] à quelqu'un ? */
    public static function actif(string $user): bool
    {
        if (self::adresse() === '') return false;
        // Le propriétaire de la boîte écrit déjà dans la boîte.
        $proprietaire = trim((string)AppConfig::get('ideas.inbox_owner', ''));
        return $proprietaire === '' || $user !== $proprietaire;
    }

    public static function adresse(): string
    {
        return rtrim(trim((string)AppConfig::get('ideas.relay', '')), '/');
    }

    public static function creerColonnes(PDO $db): void
    {
        // Ajoutées après coup : les carnets existants n'en ont pas.
        foreach ([
            "ALTER TABLE dev_ideas ADD COLUMN relayed TINYINT(1) NOT NULL DEFAULT 0",
            "ALTER TABLE dev_ideas ADD COLUMN relay_tried_at TIMESTAMP NULL DEFAULT NULL",
        ] as $sql) {
            try { $db->exec($sql); } catch (Throwable $e) { /* déjà là */ }
        }
    }

    /** Envoie une idée, et dit si elle est arrivée. */
    public static function envoyer(PDO $db, int $id, string $user, string $texte): bool
    {
        $arrivee = self::poster($user, $texte);
        $db->prepare("UPDATE dev_ideas SET relayed = ?, relay_tried_at = NOW() WHERE id = ?")
           ->execute([$arrivee ? 1 : 0, $id]);
        return $arrivee;
    }

    /**
     * Rattrape les idées restées en chemin. Appelée à l'affichage de la
     * liste : pas de tâche planifiée à installer, et la relance arrive
     * exactement quand quelqu'un regarde.
     */
    public static function rattraper(PDO $db, string $user): void
    {
        if (!self::actif($user)) return;
        $stmt = $db->prepare("
            SELECT id, text FROM dev_ideas
            WHERE user = ? AND relayed = 0
              AND (relay_tried_at IS NULL OR relay_tried_at < (NOW() - INTERVAL " . self::RETARD_MIN . " SECOND))
            ORDER BY id LIMIT " . self::PAR_RELANCE);
        $stmt->execute([$user]);
        foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
            self::envoyer($db, (int)$row['id'], $user, (string)$row['text']);
        }
    }

    private static function poster(string $user, string $texte): bool
    {
        $url = self::adresse();
        if ($url === '' || !function_exists('curl_init')) return false;

        $ch = curl_init($url . '/api/v2/ideas-inbox.php');
        curl_setopt_array($ch, [
            CURLOPT_POST           => true,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => self::DELAI,
            CURLOPT_CONNECTTIMEOUT => self::DELAI,
            CURLOPT_USERAGENT      => 'Gullify/serveur',
            CURLOPT_HTTPHEADER     => ['Content-Type: application/json'],
            CURLOPT_POSTFIELDS     => json_encode([
                'serveur'     => (string)AppConfig::get('app.url', ''),
                'utilisateur' => $user,
                'texte'       => $texte,
            ], JSON_UNESCAPED_UNICODE),
        ]);
        $corps = curl_exec($ch);
        $code  = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        return $code === 200
            && is_string($corps)
            && (json_decode($corps, true)['success'] ?? false) === true;
    }
}
