<?php
/**
 * « Écouter sur… » (serveur 1.23.0) : le téléphone fait jouer sa file par un autre appareil
 * du Wi-Fi où il se trouve — une télé GulliFY, un poste ou un serveur GulliOS, chez soi ou
 * chez d'autres. Cet appareil n'a pas de compte ici : il reçoit, pour chaque titre, une
 * adresse de stream.php signée.
 *
 * Le billet ouvre UN fichier, au nom d'UNE personne, jusqu'à une heure donnée (12 h). Il ne
 * se stocke nulle part : HMAC-SHA-256 sur « v1|expire|personne|chemin », avec une clé tirée
 * du secret de l'app (séparée de ses autres usages). Le jeton de session du téléphone ne
 * quitte jamais le téléphone.
 *
 * À la lecture, la personne doit encore être active : désactiver un compte coupe ses billets.
 */
declare(strict_types=1);

require_once __DIR__ . '/AppConfig.php';

final class BilletEcoute {
    public const DUREE = 12 * 3600;

    private static function cle(): string {
        return hash_hmac('sha256', 'gullify-ecoute-v1', AppConfig::getSecret(), true);
    }

    private static function signature(int $expire, string $personne, string $chemin): string {
        $sig = hash_hmac('sha256', "v1|$expire|$personne|$chemin", self::cle(), true);
        return rtrim(strtr(base64_encode($sig), '+/', '-_'), '=');
    }

    /** Le billet d'un fichier : « expire.personne(base64url).signature ». */
    public static function creer(string $personne, string $chemin, ?int $maintenant = null): string {
        $expire = ($maintenant ?? time()) + self::DUREE;
        $p = rtrim(strtr(base64_encode($personne), '+/', '-_'), '=');
        return $expire . '.' . $p . '.' . self::signature($expire, $personne, $chemin);
    }

    /** La personne au nom de qui le billet ouvre ce chemin, ou null. */
    public static function verifier(mixed $billet, string $chemin, ?int $maintenant = null): ?string {
        if (!is_string($billet) || !preg_match('/^(\d{9,11})\.([A-Za-z0-9_-]{1,200})\.([A-Za-z0-9_-]{43})$/', $billet, $m)) {
            return null;
        }
        $expire = (int)$m[1];
        if ($expire < ($maintenant ?? time())) return null;
        $personne = base64_decode(strtr($m[2], '-_', '+/'), true);
        if (!is_string($personne) || $personne === '') return null;
        return hash_equals(self::signature($expire, $personne, $chemin), $m[3]) ? $personne : null;
    }
}
