<?php
/**
 * La sonie d'un morceau (EBU R128, ffmpeg loudnorm) et le gain qui l'amène à la cible.
 *
 * Choix (veille audio, 2026-10-25) : une cible de -14 LUFS, et une BAISSE seulement — un morceau trop fort
 * est baissé, un morceau faible n'est pas monté (comme YouTube et Tidal). Le gain ne dépasse jamais 0 dB.
 */
final class Loudness
{
    public const CIBLE_LUFS = -14.0;

    /** Mesure la sonie intégrée d'un fichier, en LUFS, ou null si ffmpeg n'y arrive pas. */
    public static function mesurer(string $fichier): ?float
    {
        if (!is_file($fichier)) {
            return null;
        }
        $commande = sprintf(
            'ffmpeg -hide_banner -nostdin -i %s -af loudnorm=I=%s:TP=-1.5:LRA=11:print_format=json -f null - 2>&1',
            escapeshellarg($fichier),
            self::CIBLE_LUFS
        );
        $sortie = (string)shell_exec($commande);
        return self::lireMesure($sortie);
    }

    /** Lit `input_i` dans la sortie JSON de loudnorm (la dernière accolade du texte). */
    public static function lireMesure(string $sortie): ?float
    {
        if (!preg_match_all('/\{[^{}]*"input_i"[^{}]*\}/s', $sortie, $blocs) || $blocs[0] === []) {
            return null;
        }
        $json = json_decode(end($blocs[0]), true);
        if (!is_array($json) || !isset($json['input_i'])) {
            return null;
        }
        $valeur = (float)$json['input_i'];
        return is_finite($valeur) && $valeur > -70 ? $valeur : null;
    }

    /** Le gain à appliquer (dB) : négatif pour un morceau trop fort, 0 sinon. Null si on ne sait pas mesurer. */
    public static function gain(?float $lufs): ?float
    {
        if ($lufs === null) {
            return null;
        }
        return min(0.0, round(self::CIBLE_LUFS - $lufs, 2));
    }
}
