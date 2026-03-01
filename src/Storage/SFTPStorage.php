<?php
/**
 * Gullify - SFTP Storage Backend
 * Uses phpseclib3 for SFTP operations (pure PHP, no ssh2 extension required).
 */
require_once __DIR__ . '/StorageInterface.php';

// Load composer autoload for phpseclib3
$vendorAutoload = dirname(__DIR__, 2) . '/vendor/autoload.php';
if (file_exists($vendorAutoload)) {
    require_once $vendorAutoload;
}

use phpseclib3\Net\SFTP;

class SFTPStorage implements StorageInterface {
    private string $host;
    private int    $port;
    private string $username;
    private string $password;
    private string $sftpPath;   // Remote base path = user's music root

    private ?SFTP $sftp = null;

    public function __construct(
        string $host,
        int    $port,
        string $username,
        string $password,
        string $sftpPath
    ) {
        $this->host     = $host;
        $this->port     = $port;
        $this->username = $username;
        $this->password = $password;
        $this->sftpPath = rtrim($sftpPath, '/');
    }

    public function getType(): string {
        return 'sftp';
    }

    public function getPathBase(): string {
        // For SFTP users file_path in DB is relative to sftp_path
        return $this->sftpPath;
    }

    public function getMusicRoot(): string {
        return $this->sftpPath;
    }

    // -------------------------------------------------------------------------
    // Connection (lazy)
    // -------------------------------------------------------------------------

    private function connect(): SFTP {
        if ($this->sftp === null) {
            $sftp = new SFTP($this->host, $this->port, 30);
            if (!$sftp->login($this->username, $this->password)) {
                throw new RuntimeException(
                    "SFTP login failed for {$this->username}@{$this->host}:{$this->port}"
                );
            }
            $this->sftp = $sftp;
        }
        return $this->sftp;
    }

    // -------------------------------------------------------------------------
    // Interface implementation
    // -------------------------------------------------------------------------

    public function listDir(string $absPath): array {
        $sftp  = $this->connect();
        $raw   = $sftp->rawlist($absPath);
        if ($raw === false) return [];

        $result = [];
        foreach ($raw as $name => $attrs) {
            if ($name === '.' || $name === '..') continue;
            $result[] = [
                'name'   => $name,
                'is_dir' => isset($attrs['type']) && $attrs['type'] === NET_SFTP_TYPE_DIRECTORY,
            ];
        }
        return $result;
    }

    public function isDir(string $absPath): bool {
        $sftp = $this->connect();
        $stat = $sftp->stat($absPath);
        if (!$stat) return false;
        return isset($stat['type']) && $stat['type'] === NET_SFTP_TYPE_DIRECTORY;
    }

    public function isFile(string $absPath): bool {
        $sftp = $this->connect();
        $stat = $sftp->stat($absPath);
        if (!$stat) return false;
        return isset($stat['type']) && $stat['type'] === NET_SFTP_TYPE_REGULAR;
    }

    public function fileExists(string $absPath): bool {
        $sftp = $this->connect();
        return $sftp->stat($absPath) !== false;
    }

    public function stat(string $absPath): array {
        $sftp = $this->connect();
        $s    = $sftp->stat($absPath);
        return [
            'size'  => isset($s['size'])  ? (int) $s['size']  : 0,
            'mtime' => isset($s['mtime']) ? (int) $s['mtime'] : 0,
        ];
    }

    public function readFile(string $absPath): string {
        $sftp = $this->connect();
        $data = $sftp->get($absPath);
        return $data !== false ? $data : '';
    }

    public function readRange(string $absPath, int $offset, int $length): string {
        $sftp = $this->connect();
        // phpseclib3: get($remote, false, $offset, $length) returns string
        $data = $sftp->get($absPath, false, $offset, $length);
        return $data !== false ? $data : '';
    }

    public function writeFile(string $absRemotePath, string $localTmpPath): bool {
        $sftp = $this->connect();
        // Ensure remote directory exists
        $remoteDir = dirname($absRemotePath);
        if (!$this->isDir($remoteDir)) {
            $sftp->mkdir($remoteDir, -1, true);
        }
        return $sftp->put($absRemotePath, $localTmpPath, SFTP::SOURCE_LOCAL_FILE);
    }

    public function rename(string $oldPath, string $newPath): bool {
        $sftp = $this->connect();
        return $sftp->rename($oldPath, $newPath);
    }

    public function makeDir(string $absPath): bool {
        $sftp = $this->connect();
        if ($this->isDir($absPath)) return true;
        return $sftp->mkdir($absPath, -1, true) !== false;
    }

    public function deleteFile(string $absPath): bool {
        $sftp = $this->connect();
        return $sftp->delete($absPath, false);
    }

    public function deleteDir(string $absPath): bool {
        $sftp = $this->connect();
        return $sftp->rmdir($absPath);
    }
}
