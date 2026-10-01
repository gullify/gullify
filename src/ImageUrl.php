<?php
/**
 * Gullify — Les adresses des images, datées.
 *
 * Une adresse qui ne change jamais est une image qui ne change jamais, pour
 * qui la garde en cache. L'app Android range les images sur le téléphone et
 * ne redemande pas une adresse qu'elle connaît : le 2026-10-01, 646 photos
 * d'artiste sont passées de 800 à 1600 px sur le serveur, et l'app a continué
 * d'afficher les anciennes — sans même une requête, les journaux le montrent.
 * Le serveur datait pourtant déjà ses adresses… mais seulement celles qu'il
 * rendait quand on changeait une photo DEPUIS l'app. Partout ailleurs, rien.
 *
 * La date est celle du fichier en cache : elle change exactement quand
 * l'image change, et pas une fois de plus. Pas de date si le fichier n'existe
 * pas encore — `serve_image.php` ira alors le chercher, et la prochaine liste
 * portera sa date.
 */

require_once __DIR__ . '/AppConfig.php';

final class ImageUrl
{
    public static function artiste(int|string|null $id): string
    {
        return self::adresse('artist_id', (int)$id, 'artist_');
    }

    public static function album(int|string|null $id): string
    {
        return self::adresse('album_id', (int)$id, 'album_');
    }

    private static function adresse(string $cle, int $id, string $prefixe): string
    {
        $v = self::dateDuFichier($prefixe . $id);
        return 'serve_image.php?' . $cle . '=' . $id . ($v ? '&v=' . $v : '');
    }

    /** La date du fichier en cache (0 s'il n'y en a pas). */
    private static function dateDuFichier(string $nom): int
    {
        static $dossier = null;
        if ($dossier === null) {
            $dossier = AppConfig::getDataPath() . '/cache/artwork';
        }
        return (int)@filemtime($dossier . '/' . $nom . '.jpg');
    }
}
