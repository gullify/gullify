<?php
/**
 * Gullify - Profile avatars
 *
 * Small helper around the per-user profile picture, stored as a single
 * square JPEG under data/avatars/<user_id>.jpg (a persistent Docker volume,
 * so it survives image rebuilds). Served publicly by serve_avatar.php.
 */

require_once __DIR__ . '/AppConfig.php';

class Avatar
{
    /** Directory holding the avatar files. */
    public static function dir(): string
    {
        return AppConfig::getDataPath() . '/avatars';
    }

    /** Absolute path of a user's avatar file (may not exist). */
    public static function path(int $userId): string
    {
        return self::dir() . '/' . $userId . '.jpg';
    }

    public static function exists(int $userId): bool
    {
        return is_file(self::path($userId));
    }

    /**
     * Public, cache-busting URL for a user's avatar, or null if none.
     * Relative to the server root — the app makes it absolute.
     */
    public static function url(int $userId): ?string
    {
        if (!self::exists($userId)) {
            return null;
        }
        $v = @filemtime(self::path($userId)) ?: 0;
        return 'serve_avatar.php?user_id=' . $userId . '&v=' . $v;
    }

    /**
     * Decode an uploaded image, crop it to a centered square, resize to
     * 256×256 and store it as the user's avatar (JPEG). Throws on failure.
     */
    public static function store(int $userId, string $tmpPath, string $mime): void
    {
        $im = match ($mime) {
            'image/jpeg', 'image/jpg' => @imagecreatefromjpeg($tmpPath),
            'image/png'               => @imagecreatefrompng($tmpPath),
            'image/webp'              => @imagecreatefromwebp($tmpPath),
            default                   => throw new RuntimeException("Format non supporté: $mime"),
        };
        if (!$im) {
            throw new RuntimeException("Impossible de décoder l'image");
        }

        $w = imagesx($im);
        $h = imagesy($im);
        $side = min($w, $h);
        $sx = (int) (($w - $side) / 2);
        $sy = (int) (($h - $side) / 2);

        $size = 256;
        $dst = imagecreatetruecolor($size, $size);
        imagecopyresampled($dst, $im, 0, 0, $sx, $sy, $size, $size, $side, $side);
        imagedestroy($im);

        $dir = self::dir();
        if (!is_dir($dir)) {
            @mkdir($dir, 0775, true);
        }

        ob_start();
        imagejpeg($dst, null, 88);
        $bin = ob_get_clean();
        imagedestroy($dst);

        if ($bin === false || @file_put_contents(self::path($userId), $bin) === false) {
            throw new RuntimeException("Impossible d'écrire l'image");
        }
        @chmod(self::path($userId), 0644);
    }

    public static function remove(int $userId): void
    {
        $p = self::path($userId);
        if (is_file($p)) {
            @unlink($p);
        }
    }
}
