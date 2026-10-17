<?php
/**
 * Le compagnon, vu depuis le serveur.
 *
 * Un conteneur ne peut ni se remplacer, ni se remonter sur un autre dossier,
 * ni même regarder ce qu'il y a sur la machine : il ne voit que ce qu'on lui
 * a monté. Le compagnon, lui, tourne dehors. On lui parle par fichiers, dans
 * le volume de données : une DEMANDE qu'il ramasse, un JOURNAL qu'il écrit,
 * une RÉPONSE pour ce qui attend un retour.
 *
 * Voir compagnon/gullify-compagnon.sh — les deux moitiés du même mécanisme.
 */

require_once __DIR__ . '/AppConfig.php';

class Compagnon
{
    /** Au-delà, le service d'à côté est considéré comme absent ou mort. */
    public const SIGNE_DE_VIE = 120;

    /** Ce qu'on attend d'une réponse avant d'abandonner (il dort 10 s au pire). */
    private const ATTENTE_MAX = 12.0;

    public static function dossier(): string
    {
        return AppConfig::getDataPath() . '/maj';
    }

    /** Il donne signe de vie en touchant un fichier. Un fichier qui date prouve
     *  qu'il a existé, pas qu'il tourne : on exige du frais. */
    public static function present(): bool
    {
        $vie = self::dossier() . '/present';
        return is_file($vie) && (time() - (int)@filemtime($vie)) < self::SIGNE_DE_VIE;
    }

    /** Dépose une demande. Rend false si le disque n'en veut pas. */
    public static function demande(string $demande): bool
    {
        $dossier = self::dossier();
        if (!is_dir($dossier)) @mkdir($dossier, 0775, true);
        return @file_put_contents($dossier . '/demande', $demande) !== false;
    }

    /**
     * Demande quelque chose qui se répond, et attend la réponse.
     *
     * La réponse précédente est jetée AVANT de demander : sans ça, on prendrait
     * la réponse d'hier pour celle d'aujourd'hui — et on afficherait le contenu
     * d'un autre dossier que celui qu'on vient d'ouvrir.
     *
     * @return array|null le JSON du compagnon, ou null s'il n'a rien dit
     */
    public static function interroge(string $demande): ?array
    {
        $reponse = self::dossier() . '/reponse';
        @unlink($reponse);
        if (!self::demande($demande)) return null;

        $fin = microtime(true) + self::ATTENTE_MAX;
        while (microtime(true) < $fin) {
            usleep(100000); // 100 ms : assez fin pour ne pas se voir, assez gros
            if (!is_file($reponse)) continue;
            $brut = (string)@file_get_contents($reponse);
            if (trim($brut) === '') continue;  // il écrit peut-être encore
            $decode = json_decode($brut, true);
            if (!is_array($decode)) continue;
            @unlink($reponse);
            return $decode;
        }
        return null;
    }

    /** @return string[] les dernières lignes de ce qu'il raconte */
    public static function journal(): array
    {
        $fichier = self::dossier() . '/journal';
        if (!is_file($fichier)) return [];
        $lignes = preg_split('/\R/', trim((string)@file_get_contents($fichier))) ?: [];
        $lignes = array_values(array_filter($lignes, static fn($l) => trim($l) !== ''));
        return array_slice($lignes, -40);
    }

    /**
     * Un travail est en cours tant que le journal n'a pas dit « fini » — à
     * moins qu'il ne dise plus rien depuis longtemps : un compagnon tué en
     * plein travail laisserait son journal inachevé, et l'app tournerait pour
     * toujours sur une opération que personne ne mène plus.
     */
    public static function travaille(int $abandon = 900): bool
    {
        $lignes = self::journal();
        if (!$lignes) return false;
        if (str_starts_with(end($lignes), 'fini')) return false;
        $fichier = self::dossier() . '/journal';
        return (time() - (int)@filemtime($fichier)) < $abandon;
    }
}
