<?php
/**
 * Les maisons amies, côté serveur GulliFY d'une maison GulliOS (GulliOS 1.49, serveur 1.8.0).
 *
 * GulliOS écrit /var/lib/gullios/amies/amies.json (monté en lecture seule sur /amies, variable
 * AMIES_FICHIER) : {moi, cle_registre, voir, amies: [{nom, adresse, billet}]}. Le billet d'une amie
 * est signé par l'atelier (gullify.app, src/AmiesMaisons.php) :
 *   {"usage":"amie","de":<elle>,"chez":<nous>,"expire":…}
 * - billetValable() : la maison amie qui présente ce billet chez NOUS (ou null) ;
 * - amies() : nos amies et leurs billets, que l'app d'une personne connectée présente chez elles.
 * Chaque personne choisit de partager sa musique (users.partage_amies) ; rien n'est copié : l'amie
 * lit les fichiers ici, en continu. Sans fichier (gullify.app, maison sans GulliOS 1.47) : rien.
 */
declare(strict_types=1);

final class MaisonsAmies
{
    private static ?array $etat = null;

    private static function etat(): array
    {
        if (self::$etat !== null) {
            return self::$etat;
        }
        $fichier = getenv('AMIES_FICHIER') ?: '/amies/amies.json';
        $o = is_readable($fichier) ? json_decode((string)file_get_contents($fichier), true) : null;
        return self::$etat = is_array($o) ? $o : [];
    }

    public static function actif(): bool
    {
        return isset(self::etat()['moi']);
    }

    /** Le nom de la maison amie qui présente ce billet, s'il est bon pour nous ; sinon null. */
    public static function billetValable(?string $billet): ?string
    {
        $e = self::etat();
        $moi = $e['moi'] ?? null;
        $cle = base64_decode((string)($e['cle_registre'] ?? ''), true);
        if (!$moi || $cle === false || strlen($cle) !== SODIUM_CRYPTO_SIGN_PUBLICKEYBYTES
            || !is_string($billet) || strlen($billet) > 2048 || substr_count($billet, '.') !== 1) {
            return null;
        }
        $d = fn(string $s) => base64_decode(strtr($s, '-_', '+/') . str_repeat('=', (4 - strlen($s) % 4) % 4), true);
        [$c, $s] = explode('.', $billet);
        $contenu = $d($c);
        $signature = $d($s);
        if ($contenu === false || $signature === false || strlen($signature) !== SODIUM_CRYPTO_SIGN_BYTES
            || !sodium_crypto_sign_verify_detached($signature, $contenu, $cle)) {
            return null;
        }
        $o = json_decode($contenu, true);
        // « usage » et « chez » : un billet du bureau à distance (champ « cible ») ne passe pas ici.
        if (!is_array($o) || ($o['usage'] ?? '') !== 'amie' || ($o['chez'] ?? '') !== $moi
            || (int)($o['expire'] ?? 0) < time()) {
            return null;
        }
        $de = (string)($o['de'] ?? '');
        return preg_match('/^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/', $de) ? $de : null;
    }

    /** {voir, maisons: [{nom, adresse, billet}]} — pour l'app d'une personne connectée ici. */
    public static function amies(): array
    {
        $e = self::etat();
        $voir = ($e['voir'] ?? false) === true;
        $maisons = [];
        foreach ($voir ? ($e['amies'] ?? []) : [] as $a) {
            if (is_array($a) && isset($a['nom'], $a['adresse'], $a['billet'])
                && preg_match('/^[a-z0-9.-]{1,253}$/', (string)$a['adresse'])) {
                $maisons[] = ['nom' => (string)$a['nom'], 'adresse' => (string)$a['adresse'], 'billet' => (string)$a['billet']];
            }
        }
        return ['actif' => self::actif(), 'voir' => $voir, 'maisons' => $maisons];
    }
}
