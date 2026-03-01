<?php
/**
 * Gullify - Centralized Configuration
 *
 * Loads .env file and provides access to all configuration values.
 * Replaces all hardcoded paths and credentials throughout the application.
 */
class AppConfig {
    private static ?AppConfig $instance = null;
    private array $config = [];
    private string $envPath;

    private function __construct() {
        $this->envPath = dirname(__DIR__) . '/.env';
        $this->loadDefaults();
        $this->loadEnv();
        $this->loadEnvironmentVariables();
    }

    public static function getInstance(): self {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    /**
     * Get a config value using dot notation: AppConfig::get('mysql.host')
     */
    public static function get(string $key, mixed $default = null): mixed {
        $instance = self::getInstance();
        return $instance->config[$key] ?? $default;
    }

    /**
     * Check if setup wizard has been completed
     */
    public static function isSetupDone(): bool {
        return filter_var(self::get('setup_done', false), FILTER_VALIDATE_BOOLEAN);
    }

    /**
     * Get PDO connection to MySQL
     */
    public static function getDB(): PDO {
        static $db = null;
        if ($db === null) {
            $dsn = sprintf(
                'mysql:host=%s;port=%s;dbname=%s;charset=utf8mb4',
                self::get('mysql.host'),
                self::get('mysql.port'),
                self::get('mysql.database')
            );
            $db = new PDO($dsn, self::get('mysql.user'), self::get('mysql.password'), [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES => false,
            ]);
            self::runMigrations($db);
        }
        return $db;
    }

    /**
     * Run schema migrations automatically on first connection.
     * Checks INFORMATION_SCHEMA before each ALTER to stay compatible with MySQL
     * (MySQL does not support ADD COLUMN IF NOT EXISTS unlike MariaDB).
     */
    private static function runMigrations(PDO $db): void {
        $dbName = self::get('mysql.database');

        // Fetch existing columns for the users table
        try {
            $stmt = $db->prepare(
                "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
                 WHERE TABLE_SCHEMA = ? AND TABLE_NAME = 'users'"
            );
            $stmt->execute([$dbName]);
            $existing = array_column($stmt->fetchAll(PDO::FETCH_ASSOC), 'COLUMN_NAME');
        } catch (PDOException $e) {
            return; // users table does not exist yet (fresh setup wizard)
        }

        // Column name => ALTER TABLE statement to add it
        $columns = [
            'storage_type'  => "ALTER TABLE users ADD COLUMN storage_type ENUM('local','sftp') NOT NULL DEFAULT 'local' AFTER music_directory",
            'sftp_host'     => "ALTER TABLE users ADD COLUMN sftp_host VARCHAR(255) NULL AFTER storage_type",
            'sftp_port'     => "ALTER TABLE users ADD COLUMN sftp_port SMALLINT UNSIGNED NOT NULL DEFAULT 22 AFTER sftp_host",
            'sftp_user'     => "ALTER TABLE users ADD COLUMN sftp_user VARCHAR(100) NULL AFTER sftp_port",
            'sftp_password' => "ALTER TABLE users ADD COLUMN sftp_password VARCHAR(512) NULL AFTER sftp_user",
            'sftp_path'     => "ALTER TABLE users ADD COLUMN sftp_path VARCHAR(255) NULL AFTER sftp_password",
        ];

        foreach ($columns as $col => $sql) {
            if (!in_array($col, $existing)) {
                try {
                    $db->exec($sql);
                } catch (PDOException $e) {
                    // ignore — e.g. race condition on concurrent boot
                }
            }
        }
    }

    /**
     * Get the base path where music files are stored
     */
    public static function getMusicBasePath(): string {
        return rtrim(self::get('music.base_path', '/music'), '/');
    }

    /**
     * Get the data directory path (cache, logs, downloads)
     */
    public static function getDataPath(): string {
        return rtrim(self::get('data.path', dirname(__DIR__) . '/data'), '/');
    }

    /**
     * Get path to the vendor directory
     */
    public static function getVendorPath(): string {
        return dirname(__DIR__) . '/vendor';
    }

    /**
     * Get path to the python scripts directory
     */
    public static function getPythonPath(): string {
        return dirname(__DIR__) . '/python';
    }

    /**
     * Get path to the src directory
     */
    public static function getSrcPath(): string {
        return dirname(__DIR__) . '/src';
    }

    /**
     * Get the app root directory
     */
    public static function getAppRoot(): string {
        return dirname(__DIR__);
    }

    /**
     * Get the public directory
     */
    public static function getPublicPath(): string {
        return dirname(__DIR__) . '/public';
    }

    /**
     * Update a key in the .env file
     */
    public static function updateEnv(string $key, string $value): bool {
        $instance = self::getInstance();
        $envFile = $instance->envPath;

        if (!file_exists($envFile)) {
            // Create from example
            $examplePath = dirname(__DIR__) . '/.env.example';
            if (file_exists($examplePath)) {
                copy($examplePath, $envFile);
            } else {
                file_put_contents($envFile, '');
            }
        }

        $content = file_get_contents($envFile);
        $pattern = '/^' . preg_quote($key, '/') . '=.*/m';

        if (preg_match($pattern, $content)) {
            $content = preg_replace($pattern, $key . '=' . $value, $content);
        } else {
            $content .= "\n" . $key . '=' . $value;
        }

        $result = file_put_contents($envFile, $content);

        // Reload config
        if ($result !== false) {
            self::$instance = null; // Force reload
        }

        return $result !== false;
    }

    /**
     * Get the application secret used for encrypting sensitive data (e.g. SFTP passwords).
     * Reads APP_SECRET from config/env. Falls back to a derived constant if not set.
     */
    public static function getSecret(): string {
        $secret = self::get('app.secret', '');
        if (!empty($secret)) {
            return $secret;
        }
        // Fallback: derive from DB credentials (not ideal, but ensures a usable key)
        return hash('sha256', self::get('mysql.password', 'gullify') . self::get('mysql.database', 'gullify'));
    }

    private function loadDefaults(): void {
        $this->config = [
            'setup_done' => 'false',
            'mysql.host' => 'localhost',
            'mysql.port' => '3306',
            'mysql.database' => 'gullify',
            'mysql.user' => 'gullify',
            'mysql.password' => 'changeme',
            'music.base_path' => '/music',
            'data.path' => dirname(__DIR__) . '/data',
            'app.url' => 'http://localhost:8080',
            'app.debug' => 'false',
            'app.secret' => '',
            'lastfm.api_key' => '',
        ];
    }

    private function loadEnv(): void {
        if (!file_exists($this->envPath)) {
            return;
        }

        $lines = file($this->envPath, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
        foreach ($lines as $line) {
            $line = trim($line);
            if ($line === '' || str_starts_with($line, '#')) {
                continue;
            }

            $eqPos = strpos($line, '=');
            if ($eqPos === false) {
                continue;
            }

            $key = trim(substr($line, 0, $eqPos));
            $value = trim(substr($line, $eqPos + 1));

            // Remove surrounding quotes
            if ((str_starts_with($value, '"') && str_ends_with($value, '"')) ||
                (str_starts_with($value, "'") && str_ends_with($value, "'"))) {
                $value = substr($value, 1, -1);
            }

            $this->mapEnvToConfig($key, $value);
        }
    }

    /**
     * Also load from actual environment variables (Docker sets these)
     */
    private function loadEnvironmentVariables(): void {
        $envMap = [
            'GULLIFY_SETUP_DONE' => 'setup_done',
            'MYSQL_HOST' => 'mysql.host',
            'MYSQL_PORT' => 'mysql.port',
            'MYSQL_DATABASE' => 'mysql.database',
            'MYSQL_USER' => 'mysql.user',
            'MYSQL_PASSWORD' => 'mysql.password',
            'MUSIC_BASE_PATH' => 'music.base_path',
            'DATA_PATH' => 'data.path',
            'APP_URL' => 'app.url',
            'APP_DEBUG' => 'app.debug',
            'APP_SECRET' => 'app.secret',
            'LASTFM_API_KEY' => 'lastfm.api_key',
        ];

        foreach ($envMap as $envKey => $configKey) {
            $value = getenv($envKey);
            if ($value !== false) {
                $this->config[$configKey] = $value;
            }
        }
    }

    private function mapEnvToConfig(string $key, string $value): void {
        $map = [
            'GULLIFY_SETUP_DONE' => 'setup_done',
            'MYSQL_HOST' => 'mysql.host',
            'MYSQL_PORT' => 'mysql.port',
            'MYSQL_DATABASE' => 'mysql.database',
            'MYSQL_USER' => 'mysql.user',
            'MYSQL_PASSWORD' => 'mysql.password',
            'MUSIC_BASE_PATH' => 'music.base_path',
            'DATA_PATH' => 'data.path',
            'APP_URL' => 'app.url',
            'APP_DEBUG' => 'app.debug',
            'APP_SECRET' => 'app.secret',
            'LASTFM_API_KEY' => 'lastfm.api_key',
        ];

        if (isset($map[$key])) {
            $this->config[$map[$key]] = $value;
        }
    }
}
