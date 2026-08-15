<?php
/**
 * Gullify — la plomberie commune aux images qu'on va chercher ailleurs
 * (photo d'artiste, jaquette d'album).
 *
 * Télécharger une adresse et ranger l'image dans le cache se fait exactement
 * pareil qu'il s'agisse d'un artiste ou d'un album : seule change la façon de
 * CHERCHER, et le nom du fichier de cache. Ce qui est identique vit ici, et
 * [ArtistImage] comme [AlbumCover] s'appuient dessus.
 */

require_once __DIR__ . '/AppConfig.php';

class RemoteImage
{
    /** Poids maximal d'une image acceptée (collée, téléversée ou trouvée). */
    public const MAX_BYTES = 8388608; // 8 Mo

    /** Côté maximal de l'image rangée dans le cache. */
    public const MAX_SIDE = 1000;

    /** Bornes de temps (secondes) des appels externes. */
    public const SEARCH_TIMEOUT   = 6;
    public const DOWNLOAD_TIMEOUT = 10;

    /**
     * Télécharge une image dont on a l'adresse (lien collé, ou proposition
     * choisie dans la liste). Renvoie les octets, ou null si l'adresse ne
     * donne rien d'exploitable.
     */
    public static function download(string $url): ?string
    {
        $url = trim($url);
        if (!filter_var($url, FILTER_VALIDATE_URL) || !preg_match('~^https?://~i', $url)) {
            return null;
        }
        $bin = self::get($url, self::DOWNLOAD_TIMEOUT, self::MAX_BYTES);
        if ($bin === null || strlen($bin) < 200 || strlen($bin) > self::MAX_BYTES) {
            return null;
        }
        return $bin;
    }

    /**
     * Range une image choisie à la main dans le fichier de cache donné, que
     * `serve_image.php` sert avant tout le reste — l'image du dossier comme
     * celle du web passent après.
     *
     * L'image est re-encodée en JPEG (le cache s'appelle `.jpg` et est servi
     * comme tel : y déposer un PNG donnerait un type MIME menteur) et ramenée
     * à 1000 px de côté au plus. Renvoie false si ce n'était pas une image.
     */
    public static function store(string $file, string $bin): bool
    {
        if (!function_exists('imagecreatefromstring')) return false;
        $src = @imagecreatefromstring($bin);
        if (!$src) return false;

        try {
            $w = imagesx($src);
            $h = imagesy($src);
            if ($w < 1 || $h < 1) return false;

            $ratio = min(1, self::MAX_SIDE / max($w, $h));
            $nw = max(1, (int)round($w * $ratio));
            $nh = max(1, (int)round($h * $ratio));

            // Fond blanc : un PNG transparent aplati en JPEG virerait au noir.
            $dst = imagecreatetruecolor($nw, $nh);
            imagefilledrectangle($dst, 0, 0, $nw, $nh, imagecolorallocate($dst, 255, 255, 255));
            imagecopyresampled($dst, $src, 0, 0, 0, 0, $nw, $nh, $w, $h);
            ob_start();
            imagejpeg($dst, null, 90);
            $jpeg = ob_get_clean();
            imagedestroy($dst);
            if ($jpeg === false || $jpeg === '') return false;

            $dir = dirname($file);
            if (!is_dir($dir)) @mkdir($dir, 0775, true);
            // Écriture en deux temps : une requête qui sert l'image pendant ce
            // temps-là voit l'ancienne ou la nouvelle, jamais une moitié.
            $tmp = $file . '.tmp' . getmypid();
            if (@file_put_contents($tmp, $jpeg) === false) return false;
            @chmod($tmp, 0644);
            if (!@rename($tmp, $file)) {
                @unlink($tmp);
                return false;
            }
            return true;
        } finally {
            imagedestroy($src);
        }
    }

    /**
     * Les vignettes YouTube reviennent parfois en petit format : on force la
     * taille dans l'URL.
     */
    public static function ytFullSize(string $thumb): string
    {
        return $thumb === ''
            ? ''
            : (string)preg_replace('/=w\d+-h\d+/', '=w1000-h1000', $thumb);
    }

    /**
     * L'interpréteur python qui sait parler à YouTube Music, et le script de
     * recherche — null si le script n'est pas là (dépôt sans `python/`).
     *
     * @return array{0: string, 1: string}|null [binaire python, script]
     */
    public static function ytMusicScript(): ?array
    {
        $script = AppConfig::getPythonPath() . '/ytmusic_search.py';
        if (!is_file($script)) return null;
        $python = is_executable('/opt/ytdlp/bin/python3') ? '/opt/ytdlp/bin/python3' : 'python3';
        return [$python, $script];
    }

    /**
     * GET borné dans le temps (et, si demandé, en taille). Renvoie le corps,
     * ou null hors 200.
     */
    public static function get(string $url, int $timeout, int $maxBytes = 0): ?string
    {
        if (!function_exists('curl_init')) return null;
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => $timeout,
            CURLOPT_CONNECTTIMEOUT => 5,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_USERAGENT      => 'Gullify/1.0 (self-hosted music player)',
            // Une adresse collée à la main peut rebondir n'importe où : la
            // redirection reste cantonnée au web.
            CURLOPT_PROTOCOLS       => CURLPROTO_HTTP | CURLPROTO_HTTPS,
            CURLOPT_REDIR_PROTOCOLS => CURLPROTO_HTTP | CURLPROTO_HTTPS,
        ]);
        if ($maxBytes > 0) curl_setopt($ch, CURLOPT_MAXFILESIZE, $maxBytes);
        $body = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        return ($code === 200 && is_string($body) && $body !== '') ? $body : null;
    }
}
