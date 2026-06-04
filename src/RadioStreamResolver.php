<?php
/**
 * Gullify — Resolve a user-supplied radio URL into a directly-playable stream.
 *
 * Supported inputs:
 *   - Direct HTTP/HTTPS streams (MP3, AAC, OGG/Vorbis, OPUS) — Icecast and
 *     Shoutcast both serve these natively; we just verify content-type.
 *   - HLS playlists (.m3u8 with #EXT-X-STREAM-INF or .ts segments) — passed
 *     through; Safari plays them natively, the future Android client uses
 *     ExoPlayer which handles HLS.
 *   - M3U/M3U8 playlists with #EXTINF entries pointing at audio streams —
 *     the first valid URL is extracted.
 *   - PLS playlists ([playlist] + FileN=URL) — File1 is extracted.
 *   - Shoutcast/Icecast directory pages that return a "Tune in" .pls — fetched
 *     and the inner URL is used.
 *
 * Returns:
 *   [
 *     'url'         => '…', // the URL Gullify should send to the audio element
 *     'format'      => 'mp3'|'aac'|'ogg'|'opus'|'hls'|'unknown',
 *     'is_playlist' => bool, // whether we followed a playlist
 *     'note'        => ?string, // human-readable detection note
 *   ]
 */

class RadioStreamResolver
{
    public static function resolve(string $url): array
    {
        $url = trim($url);
        if ($url === '' || !filter_var($url, FILTER_VALIDATE_URL)) {
            return ['url' => $url, 'format' => 'unknown', 'is_playlist' => false, 'note' => 'URL invalide'];
        }

        $lc = strtolower($url);
        $isHls = preg_match('/\.m3u8(\?|$)/i', $url) === 1;

        // Quick HEAD check to get content-type. Some Icecast/Shoutcast servers
        // dislike HEAD — fall back to a small GET if HEAD doesn't help.
        $ct = self::peekContentType($url);

        // HLS — Safari/iOS/Android native, plus optional hls.js on Chrome
        if ($isHls || $ct === 'application/vnd.apple.mpegurl' || $ct === 'application/x-mpegurl') {
            // Could still be a regular M3U playlist of streams; sample the body
            $sample = self::sampleBody($url, 2048);
            if ($sample && preg_match('/#EXT-X-STREAM-INF|#EXT-X-TARGETDURATION|#EXT-X-VERSION/', $sample)) {
                return [
                    'url' => $url,
                    'format' => 'hls',
                    'is_playlist' => false,
                    'note' => 'HLS (Apple/Android natif)',
                ];
            }
            // Treat as M3U playlist of streams
            if ($sample) {
                $extracted = self::extractFromM3U($sample, $url);
                if ($extracted !== null) return self::detectStream($extracted, true, 'M3U → flux extrait');
            }
            return ['url' => $url, 'format' => 'hls', 'is_playlist' => false, 'note' => 'HLS supposé'];
        }

        // PLS
        if ($ct === 'audio/x-scpls' || preg_match('/\.pls(\?|$)/i', $url)) {
            $sample = self::sampleBody($url, 4096);
            if ($sample) {
                $extracted = self::extractFromPLS($sample);
                if ($extracted) return self::detectStream($extracted, true, 'PLS → flux extrait');
            }
        }

        // Plain text / playlist content-type
        if ($ct === 'text/plain' || $ct === 'audio/x-mpegurl' || $ct === 'audio/mpegurl' || preg_match('/\.m3u(\?|$)/i', $url)) {
            $sample = self::sampleBody($url, 4096);
            if ($sample) {
                if (str_starts_with(ltrim($sample), '[playlist]')) {
                    $extracted = self::extractFromPLS($sample);
                    if ($extracted) return self::detectStream($extracted, true, 'PLS → flux extrait');
                }
                if (str_contains($sample, '#EXTM3U') || preg_match('/^https?:\/\//m', $sample)) {
                    $extracted = self::extractFromM3U($sample, $url);
                    if ($extracted) return self::detectStream($extracted, true, 'M3U → flux extrait');
                }
            }
        }

        // Direct stream — content-type tells us the codec when available
        return self::detectStream($url, false, null, $ct);
    }

    private static function detectStream(string $url, bool $fromPlaylist, ?string $note = null, ?string $ct = null): array
    {
        if (!$ct) $ct = self::peekContentType($url);
        $format = 'unknown';
        if ($ct) {
            $ct = strtolower($ct);
            if (str_contains($ct, 'mpeg') && !str_contains($ct, 'mpegurl'))  $format = 'mp3';
            elseif (str_contains($ct, 'aac') || str_contains($ct, 'aacp'))   $format = 'aac';
            elseif (str_contains($ct, 'ogg'))                                $format = 'ogg';
            elseif (str_contains($ct, 'opus'))                               $format = 'opus';
            elseif (str_contains($ct, 'mp4') || str_contains($ct, 'm4a'))    $format = 'mp4';
            elseif (str_contains($ct, 'flac'))                               $format = 'flac';
            elseif (str_contains($ct, 'wav'))                                $format = 'wav';
        }
        if ($format === 'unknown') {
            // Last-resort: look at URL extension
            if      (preg_match('/\.mp3(\?|$)/i', $url))                    $format = 'mp3';
            elseif (preg_match('/\.aac(\?|$)/i', $url))                     $format = 'aac';
            elseif (preg_match('/\.(ogg|oga)(\?|$)/i', $url))              $format = 'ogg';
            elseif (preg_match('/\.opus(\?|$)/i', $url))                    $format = 'opus';
            elseif (preg_match('/\.m4a(\?|$)/i', $url))                     $format = 'mp4';
            elseif (preg_match('/\.flac(\?|$)/i', $url))                    $format = 'flac';
        }
        return [
            'url'         => $url,
            'format'      => $format,
            'is_playlist' => $fromPlaylist,
            'note'        => $note,
        ];
    }

    private static function peekContentType(string $url): ?string
    {
        if (!function_exists('curl_init')) return null;
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_NOBODY         => true,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_TIMEOUT        => 5,
            CURLOPT_CONNECTTIMEOUT => 3,
            CURLOPT_USERAGENT      => 'Gullify/1.0',
        ]);
        curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $ct   = curl_getinfo($ch, CURLINFO_CONTENT_TYPE);
        curl_close($ch);
        if ($code >= 400 || !$ct) return null;
        // Strip parameters (charset, etc.)
        if (str_contains($ct, ';')) $ct = trim(substr($ct, 0, strpos($ct, ';')));
        return strtolower($ct);
    }

    private static function sampleBody(string $url, int $bytes = 4096): ?string
    {
        if (!function_exists('curl_init')) return null;
        $ch = curl_init($url);
        $buf = '';
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_TIMEOUT        => 6,
            CURLOPT_CONNECTTIMEOUT => 3,
            CURLOPT_USERAGENT      => 'Gullify/1.0',
            CURLOPT_WRITEFUNCTION  => function ($_, $chunk) use (&$buf, $bytes) {
                $buf .= $chunk;
                if (strlen($buf) >= $bytes) return -1;
                return strlen($chunk);
            },
        ]);
        @curl_exec($ch);
        curl_close($ch);
        return $buf !== '' ? $buf : null;
    }

    private static function extractFromM3U(string $body, string $baseUrl): ?string
    {
        $base = parse_url($baseUrl);
        $lines = preg_split('/\r?\n/', $body);
        foreach ($lines as $line) {
            $line = trim($line);
            if ($line === '' || str_starts_with($line, '#')) continue;
            // Bare URL ?
            if (preg_match('~^https?://~i', $line)) return $line;
            // Relative URL ? resolve against base
            if ($base && isset($base['scheme'], $base['host'])) {
                $abs = $base['scheme'] . '://' . $base['host'];
                if (!empty($base['port'])) $abs .= ':' . $base['port'];
                if ($line[0] !== '/') {
                    $abs .= rtrim(dirname($base['path'] ?? '/'), '/') . '/';
                }
                $abs .= ltrim($line, '/');
                return $abs;
            }
        }
        return null;
    }

    private static function extractFromPLS(string $body): ?string
    {
        if (preg_match_all('/^File\d+\s*=\s*(\S+)/mi', $body, $m)) {
            foreach ($m[1] as $u) {
                $u = trim($u);
                if (preg_match('~^https?://~i', $u)) return $u;
            }
        }
        return null;
    }
}
