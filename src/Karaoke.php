<?php
/**
 * Gullify - Versions karaoké (idée #63)
 *
 * Il n'existe pas d'API publique qui rende l'instrumental d'un titre, et une
 * vraie séparation de sources (Demucs et compagnie) demande un modèle de
 * plusieurs gigaoctets et bien plus de temps que la lecture ne peut en
 * attendre. Ce que le serveur sait faire, lui, en quelques secondes et sans
 * autre dépendance que ffmpeg : annuler le centre du mixage stéréo, là où la
 * voix lead se trouve presque toujours. Ce n'est pas un instrumental de
 * studio — la voix est atténuée, pas retirée, et ce qui est centré part avec
 * elle — mais c'est de quoi chanter dessus.
 *
 * Le rendu est fait une fois par titre, en tâche de fond, et gardé sur le
 * volume persistant (data/karaoke). `stream.php?...&karaoke=1` sert le fichier
 * rendu s'il existe, et l'original sinon : la lecture ne casse jamais parce
 * qu'une version karaoké manque.
 *
 * Un mixage trop centré (mono, ou stéréo « faux ») n'a rien à annuler : le
 * titre est alors marqué indisponible plutôt que de rendre une bouillie.
 */

require_once __DIR__ . '/AppConfig.php';
require_once __DIR__ . '/Storage/StorageInterface.php';
require_once __DIR__ . '/Storage/LocalStorage.php';
require_once __DIR__ . '/Storage/SFTPStorage.php';
require_once __DIR__ . '/Storage/StorageFactory.php';

class Karaoke
{
    /** Taille maximale du cache : au-delà, les plus vieux rendus s'effacent. */
    private const CACHE_MAX_BYTES = 600 * 1024 * 1024;

    /** Un rendu bloqué depuis plus longtemps que ça est considéré mort. */
    private const WORK_TTL = 600;

    /** Rendus simultanés autorisés (ffmpeg tourne ~90× le temps réel). */
    private const MAX_CONCURRENT = 2;

    /**
     * Combien de décibels le côté (L−R, ce qui reste après annulation du
     * centre) peut être sous le milieu avant qu'on déclare le titre trop
     * centré pour un karaoké.
     */
    private const MIN_SIDE_DB = -20.0;

    /** Secondes analysées pour juger du mixage (assez pour un refrain). */
    private const PROBE_SECONDS = 90;

    public static function dir(): string
    {
        return AppConfig::getDataPath() . '/karaoke';
    }

    /**
     * Chemin absolu et local du fichier d'origine, ou null si le titre est
     * inconnu ou stocké ailleurs (SFTP : ffmpeg n'y a pas accès).
     */
    public static function sourceFile(string $relativePath): ?string
    {
        if ($relativePath === '') {
            return null;
        }

        try {
            $db   = AppConfig::getDB();
            $stmt = $db->prepare(
                'SELECT ar.user
                 FROM songs s
                 JOIN albums al ON s.album_id = al.id
                 JOIN artists ar ON al.artist_id = ar.id
                 WHERE s.file_path = ?
                 LIMIT 1'
            );
            $stmt->execute([$relativePath]);
            $row = $stmt->fetch(PDO::FETCH_ASSOC);
        } catch (Exception $e) {
            return null;
        }

        // Titre absent de la base : on ne rend rien (personne ne doit pouvoir
        // faire tourner ffmpeg sur un chemin qui n'est pas de la musique).
        if (!$row) {
            return null;
        }

        $storage = StorageFactory::forUser((string)$row['user']);
        if ($storage->getType() !== 'local') {
            return null;
        }

        $base = realpath($storage->getPathBase());
        $file = realpath($storage->getPathBase() . '/' . $relativePath);
        if ($base === false || $file === false || strpos($file, $base) !== 0) {
            return null;
        }

        return is_file($file) ? $file : null;
    }

    /**
     * Clé de cache : le chemin, sa taille et sa date. Un fichier retagué ou
     * remplacé repart donc sur un rendu neuf.
     */
    public static function key(string $relativePath, string $sourceFile): string
    {
        return md5(implode('|', [
            $relativePath,
            (string)(@filesize($sourceFile) ?: 0),
            (string)(@filemtime($sourceFile) ?: 0),
        ]));
    }

    public static function renderedFile(string $key): string
    {
        return self::dir() . '/' . $key . '.mp3';
    }

    private static function workFile(string $key): string
    {
        return self::dir() . '/' . $key . '.work';
    }

    private static function refusedFile(string $key): string
    {
        return self::dir() . '/' . $key . '.none';
    }

    /**
     * Version karaoké prête pour ce titre, ou null. Utilisé par stream.php :
     * il ne déclenche aucun rendu, il ne fait que servir ce qui existe.
     */
    public static function readyFor(string $relativePath, string $sourceFile): ?string
    {
        $file = self::renderedFile(self::key($relativePath, $sourceFile));
        if (!is_file($file) || filesize($file) === 0) {
            return null;
        }
        // Date de dernier usage : le ménage efface les rendus les plus vieux.
        @touch($file);
        return $file;
    }

    /**
     * État du karaoké d'un titre, et lancement du rendu si besoin.
     *
     * Renvoie ['status' => ready|rendering|unavailable, 'reason' => ?string].
     * `unavailable` est définitif (titre inconnu, stockage distant, mixage
     * trop centré) ; `rendering` demande simplement de redemander plus tard.
     */
    public static function prepare(string $relativePath): array
    {
        $source = self::sourceFile($relativePath);
        if ($source === null) {
            return ['status' => 'unavailable', 'reason' => 'source'];
        }

        $key = self::key($relativePath, $source);
        if (is_file(self::renderedFile($key))) {
            return ['status' => 'ready', 'reason' => null];
        }
        if (is_file(self::refusedFile($key))) {
            return [
                'status' => 'unavailable',
                'reason' => trim((string)@file_get_contents(self::refusedFile($key))) ?: 'mono',
            ];
        }

        $work = self::workFile($key);
        if (is_file($work)) {
            if (time() - (int)@filemtime($work) < self::WORK_TTL) {
                return ['status' => 'rendering', 'reason' => null];
            }
            @unlink($work); // rendu mort : on repart
        }

        if (self::runningCount() >= self::MAX_CONCURRENT) {
            return ['status' => 'rendering', 'reason' => 'queued'];
        }

        self::spawn($relativePath);
        return ['status' => 'rendering', 'reason' => null];
    }

    private static function runningCount(): int
    {
        $running = 0;
        foreach (glob(self::dir() . '/*.work') ?: [] as $work) {
            if (time() - (int)@filemtime($work) < self::WORK_TTL) {
                $running++;
            }
        }
        return $running;
    }

    /** Lance le rendu en tâche de fond (la requête HTTP n'attend pas). */
    private static function spawn(string $relativePath): void
    {
        $script = dirname(__DIR__) . '/scripts/render-karaoke.php';
        $cmd = 'nohup php ' . escapeshellarg($script) . ' ' . escapeshellarg($relativePath)
             . ' > /dev/null 2>&1 &';
        @exec($cmd);
    }

    // ── Rendu (appelé par scripts/render-karaoke.php) ────────────────────────

    /**
     * Rend la version karaoké du titre. Bloquant : c'est le travail du script
     * de fond. Renvoie le même triplet d'état que prepare().
     */
    public static function render(string $relativePath): array
    {
        $source = self::sourceFile($relativePath);
        if ($source === null) {
            return ['status' => 'unavailable', 'reason' => 'source'];
        }

        $dir = self::dir();
        if (!is_dir($dir) && !@mkdir($dir, 0775, true) && !is_dir($dir)) {
            return ['status' => 'unavailable', 'reason' => 'cache'];
        }

        $key      = self::key($relativePath, $source);
        $rendered = self::renderedFile($key);
        if (is_file($rendered)) {
            return ['status' => 'ready', 'reason' => null];
        }

        $work = self::workFile($key);
        @file_put_contents($work, (string)getmypid());

        try {
            // 1. Le mixage se prête-t-il à l'exercice ? Sans énergie latérale
            //    (mono, ou stéréo factice), annuler le centre ne laisse rien.
            $side = self::meanVolume($source, 'c0-c1');
            $mid  = self::meanVolume($source, '0.5*c0+0.5*c1');
            if ($side === null || $mid === null) {
                return ['status' => 'unavailable', 'reason' => 'probe'];
            }
            if ($side - $mid < self::MIN_SIDE_DB) {
                @file_put_contents(self::refusedFile($key), 'mono');
                return ['status' => 'unavailable', 'reason' => 'mono'];
            }

            // 2. Rendu. Le fichier n'apparaît sous son nom définitif qu'une
            //    fois complet : stream.php ne peut pas servir un demi-rendu.
            $part = $rendered . '.part';
            $cmd  = 'ffmpeg -nostdin -y -i ' . escapeshellarg($source)
                  . ' -filter_complex ' . escapeshellarg(self::FILTER)
                  . ' -map ' . escapeshellarg('[out]')
                  // -f mp3 : le fichier s'appelle « .part » le temps du rendu,
                  // ffmpeg ne peut pas deviner le format d'après son nom.
                  . ' -c:a libmp3lame -b:a 192k -ac 2 -f mp3'
                  . ' ' . escapeshellarg($part) . ' 2>&1';
            @exec($cmd, $out, $code);

            if ($code !== 0 || !is_file($part) || filesize($part) === 0) {
                @unlink($part);
                return ['status' => 'unavailable', 'reason' => 'ffmpeg'];
            }
            if (!@rename($part, $rendered)) {
                @unlink($part);
                return ['status' => 'unavailable', 'reason' => 'cache'];
            }
        } finally {
            @unlink($work);
        }

        self::prune();
        return ['status' => 'ready', 'reason' => null];
    }

    /**
     * Annulation du centre, basses conservées : le côté (L−R) porte tout ce
     * qui n'est pas au milieu, mais emporterait aussi la grosse caisse et la
     * basse — on remet donc le grave du mixage d'origine par-dessus.
     */
    private const FILTER =
        '[0:a]asplit=2[a][b];'
        . '[a]pan=stereo|c0=c0-0.95*c1|c1=c1-0.95*c0[voix];'
        . '[b]pan=stereo|c0=0.5*c0+0.5*c1|c1=0.5*c0+0.5*c1,lowpass=f=180[grave];'
        . '[voix][grave]amix=inputs=2:duration=first:normalize=0,'
        . 'alimiter=limit=0.95[out]';

    /**
     * Volume moyen (dBFS) d'une combinaison de canaux, sur le début du titre.
     * Null si ffmpeg n'a rien su dire du fichier.
     */
    private static function meanVolume(string $source, string $mix): ?float
    {
        $cmd = 'ffmpeg -nostdin -t ' . self::PROBE_SECONDS . ' -i ' . escapeshellarg($source)
             . ' -af ' . escapeshellarg('pan=mono|c0=' . $mix . ',volumedetect')
             . ' -f null - 2>&1';
        @exec($cmd, $out, $code);
        foreach ($out as $line) {
            if (preg_match('/mean_volume:\s*(-?[\d.]+) dB/', $line, $m)) {
                return (float)$m[1];
            }
        }
        return null;
    }

    /** Garde le cache sous sa limite en effaçant les rendus les plus vieux. */
    public static function prune(): void
    {
        $files = [];
        $total = 0;
        foreach (glob(self::dir() . '/*.mp3') ?: [] as $file) {
            $size    = (int)@filesize($file);
            $total  += $size;
            $files[] = ['file' => $file, 'time' => (int)@filemtime($file), 'size' => $size];
        }
        if ($total <= self::CACHE_MAX_BYTES) {
            return;
        }

        usort($files, static fn($a, $b) => $a['time'] <=> $b['time']);
        foreach ($files as $entry) {
            if ($total <= self::CACHE_MAX_BYTES) {
                break;
            }
            if (@unlink($entry['file'])) {
                $total -= $entry['size'];
            }
        }
    }
}
