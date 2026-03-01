<?php
/**
 * Gullify - Local Filesystem Storage
 * Implements StorageInterface using PHP's native filesystem functions.
 */
require_once __DIR__ . '/StorageInterface.php';

class LocalStorage implements StorageInterface {
    private string $pathBase;
    private string $musicRoot;

    /**
     * @param string $pathBase   Global music base path (e.g. /music)
     * @param string $musicRoot  User's music root (e.g. /music/Musique)
     */
    public function __construct(string $pathBase, string $musicRoot) {
        $this->pathBase  = rtrim($pathBase, '/');
        $this->musicRoot = rtrim($musicRoot, '/');
    }

    public function getType(): string {
        return 'local';
    }

    public function getPathBase(): string {
        return $this->pathBase;
    }

    public function getMusicRoot(): string {
        return $this->musicRoot;
    }

    public function listDir(string $absPath): array {
        $items = @scandir($absPath);
        if (!$items) return [];
        $result = [];
        foreach ($items as $name) {
            if ($name === '.' || $name === '..') continue;
            $result[] = [
                'name'   => $name,
                'is_dir' => is_dir($absPath . '/' . $name),
            ];
        }
        return $result;
    }

    public function isDir(string $absPath): bool {
        return is_dir($absPath);
    }

    public function isFile(string $absPath): bool {
        return is_file($absPath);
    }

    public function fileExists(string $absPath): bool {
        return file_exists($absPath);
    }

    public function stat(string $absPath): array {
        return [
            'size'  => (int) @filesize($absPath),
            'mtime' => (int) @filemtime($absPath),
        ];
    }

    public function readFile(string $absPath): string {
        $data = @file_get_contents($absPath);
        return $data !== false ? $data : '';
    }

    public function readRange(string $absPath, int $offset, int $length): string {
        $handle = @fopen($absPath, 'rb');
        if (!$handle) return '';
        fseek($handle, $offset);
        $data = fread($handle, $length);
        fclose($handle);
        return $data !== false ? $data : '';
    }

    public function writeFile(string $absRemotePath, string $localTmpPath): bool {
        $dir = dirname($absRemotePath);
        if (!is_dir($dir)) {
            mkdir($dir, 0755, true);
        }
        return copy($localTmpPath, $absRemotePath);
    }

    public function rename(string $oldPath, string $newPath): bool {
        return @rename($oldPath, $newPath);
    }

    public function makeDir(string $absPath): bool {
        if (is_dir($absPath)) return true;
        return mkdir($absPath, 0755, true);
    }

    public function deleteFile(string $absPath): bool {
        return @unlink($absPath);
    }

    public function deleteDir(string $absPath): bool {
        return @rmdir($absPath);
    }
}
