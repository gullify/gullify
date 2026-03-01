<?php
/**
 * Gullify - Storage Interface
 * Abstraction layer for local filesystem and SFTP backends.
 */
interface StorageInterface {
    /**
     * Returns 'local' or 'sftp'
     */
    public function getType(): string;

    /**
     * The base prefix stripped from absolute paths to produce DB-stored relative paths.
     * Local: /music  → file_path = music_dir/Artist/Album/song.mp3
     * SFTP:  /remote/path → file_path = Artist/Album/song.mp3
     */
    public function getPathBase(): string;

    /**
     * The user's music root (absolute path on this backend).
     * Local: /music/Musique
     * SFTP:  /home/user/music
     */
    public function getMusicRoot(): string;

    /**
     * List directory contents.
     * @return array of ['name' => string, 'is_dir' => bool]
     */
    public function listDir(string $absPath): array;

    public function isDir(string $absPath): bool;

    public function isFile(string $absPath): bool;

    public function fileExists(string $absPath): bool;

    /**
     * @return array ['size' => int, 'mtime' => int]
     */
    public function stat(string $absPath): array;

    /**
     * Read full file contents into memory.
     */
    public function readFile(string $absPath): string;

    /**
     * Read a byte range from a file (for HTTP range streaming).
     */
    public function readRange(string $absPath, int $offset, int $length): string;

    /**
     * Upload a local file to the backend path.
     * @param string $absRemotePath  Absolute destination path on this backend
     * @param string $localTmpPath   Local file to upload from
     */
    public function writeFile(string $absRemotePath, string $localTmpPath): bool;

    /**
     * Rename a file or directory.
     */
    public function rename(string $oldPath, string $newPath): bool;

    /**
     * Create directory (recursive).
     */
    public function makeDir(string $absPath): bool;

    /**
     * Delete a single file.
     */
    public function deleteFile(string $absPath): bool;

    /**
     * Delete an empty directory.
     */
    public function deleteDir(string $absPath): bool;
}
