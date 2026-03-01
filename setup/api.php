<?php
/**
 * Gullify Setup Wizard - Backend API
 *
 * Handles all AJAX requests from the setup wizard frontend.
 * Each action returns a JSON response with success/error status.
 */

header('Content-Type: application/json');
header('Cache-Control: no-store, no-cache, must-revalidate');

// Error handling
set_error_handler(function ($severity, $message, $file, $line) {
    throw new ErrorException($message, 0, $severity, $file, $line);
});

require_once __DIR__ . '/../src/AppConfig.php';

$action = $_GET['action'] ?? $_POST['action'] ?? '';

try {
    switch ($action) {
        case 'check_requirements':
            handleCheckRequirements();
            break;
        case 'test_database':
            handleTestDatabase();
            break;
        case 'create_tables':
            handleCreateTables();
            break;
        case 'check_music_dir':
            handleCheckMusicDir();
            break;
        case 'create_admin':
            handleCreateAdmin();
            break;
        case 'add_user':
            handleAddUser();
            break;
        case 'start_scan':
            handleStartScan();
            break;
        case 'scan_status':
            handleScanStatus();
            break;
        case 'finish_setup':
            handleFinishSetup();
            break;
        default:
            jsonResponse(false, 'Action inconnue: ' . $action);
    }
} catch (Throwable $e) {
    jsonResponse(false, $e->getMessage());
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

function jsonResponse(bool $success, string $message = '', array $data = []): void {
    echo json_encode(array_merge([
        'success' => $success,
        'message' => $message,
    ], $data), JSON_UNESCAPED_UNICODE);
    exit;
}

function getPostData(): array {
    $raw = file_get_contents('php://input');
    $data = json_decode($raw, true);
    if (!is_array($data)) {
        $data = $_POST;
    }
    return $data;
}

function getDBConnection(array $params): PDO {
    $dsn = sprintf(
        'mysql:host=%s;port=%s;dbname=%s;charset=utf8mb4',
        $params['host'] ?? 'localhost',
        $params['port'] ?? '3306',
        $params['database'] ?? 'gullify'
    );
    return new PDO($dsn, $params['user'] ?? '', $params['password'] ?? '', [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
    ]);
}

// ─── Action Handlers ─────────────────────────────────────────────────────────

function handleCheckRequirements(): void {
    $requirements = [];

    // PHP version
    $phpOk = version_compare(PHP_VERSION, '8.0.0', '>=');
    $requirements[] = [
        'name' => 'PHP >= 8.0',
        'status' => $phpOk,
        'current' => PHP_VERSION,
    ];

    // Required extensions
    $extensions = ['PDO', 'pdo_mysql', 'fileinfo', 'gd', 'curl', 'mbstring'];
    foreach ($extensions as $ext) {
        $loaded = extension_loaded($ext);
        $requirements[] = [
            'name' => "Extension: $ext",
            'status' => $loaded,
            'current' => $loaded ? 'Chargee' : 'Manquante',
        ];
    }

    // Data directory writable
    $dataPath = AppConfig::getDataPath();
    $dataWritable = is_dir($dataPath) && is_writable($dataPath);
    if (!$dataWritable && !is_dir($dataPath)) {
        @mkdir($dataPath, 0775, true);
        $dataWritable = is_dir($dataPath) && is_writable($dataPath);
    }
    $requirements[] = [
        'name' => 'Dossier data accessible en ecriture',
        'status' => $dataWritable,
        'current' => $dataPath,
    ];

    // getID3 library
    $getid3Path = AppConfig::getVendorPath() . '/getid3/getid3.php';
    $getid3Exists = file_exists($getid3Path);
    $requirements[] = [
        'name' => 'Bibliotheque getID3',
        'status' => $getid3Exists,
        'current' => $getid3Exists ? 'Trouvee' : 'Non trouvee (' . $getid3Path . ')',
    ];

    $allPassed = true;
    foreach ($requirements as $req) {
        if (!$req['status']) {
            $allPassed = false;
            break;
        }
    }

    jsonResponse(true, '', [
        'requirements' => $requirements,
        'all_passed' => $allPassed,
    ]);
}

function handleTestDatabase(): void {
    $data = getPostData();

    $required = ['host', 'port', 'database', 'user', 'password'];
    foreach ($required as $field) {
        if (empty($data[$field]) && $field !== 'password') {
            jsonResponse(false, "Le champ '$field' est requis.");
        }
    }

    try {
        $db = getDBConnection($data);
        $version = $db->query('SELECT VERSION()')->fetchColumn();

        // Save credentials to .env
        AppConfig::updateEnv('MYSQL_HOST', $data['host']);
        AppConfig::updateEnv('MYSQL_PORT', $data['port']);
        AppConfig::updateEnv('MYSQL_DATABASE', $data['database']);
        AppConfig::updateEnv('MYSQL_USER', $data['user']);
        AppConfig::updateEnv('MYSQL_PASSWORD', $data['password']);

        jsonResponse(true, "Connexion reussie. MySQL $version", [
            'version' => $version,
        ]);
    } catch (PDOException $e) {
        $msg = $e->getMessage();
        if (str_contains($msg, 'Access denied')) {
            jsonResponse(false, "Acces refuse. Verifiez le nom d'utilisateur et le mot de passe.");
        } elseif (str_contains($msg, 'Unknown database')) {
            jsonResponse(false, "La base de donnees '{$data['database']}' n'existe pas. Creez-la d'abord.");
        } elseif (str_contains($msg, 'Connection refused') || str_contains($msg, 'No such file')) {
            jsonResponse(false, "Impossible de se connecter a MySQL sur {$data['host']}:{$data['port']}.");
        } else {
            jsonResponse(false, "Erreur de connexion: $msg");
        }
    }
}

function handleCreateTables(): void {
    $data = getPostData();

    try {
        $db = getDBConnection($data);
    } catch (PDOException $e) {
        jsonResponse(false, 'Connexion echouee: ' . $e->getMessage());
    }

    $schemaFile = __DIR__ . '/schema.sql';
    if (!file_exists($schemaFile)) {
        jsonResponse(false, 'Fichier schema.sql introuvable.');
    }

    $sql = file_get_contents($schemaFile);

    // Split on semicolons that are at end of statement (not inside strings)
    $statements = [];
    $current = '';
    foreach (explode("\n", $sql) as $line) {
        $trimmed = trim($line);
        // Skip pure comment lines
        if (str_starts_with($trimmed, '--')) {
            continue;
        }
        $current .= $line . "\n";
        if (str_ends_with($trimmed, ';')) {
            $stmt = trim($current);
            if ($stmt !== '' && $stmt !== ';') {
                $statements[] = $stmt;
            }
            $current = '';
        }
    }
    // Catch any trailing statement without semicolon
    $trailing = trim($current);
    if ($trailing !== '' && $trailing !== ';') {
        $statements[] = $trailing;
    }

    $created = 0;
    $skipped = 0;
    $errors = [];

    foreach ($statements as $stmt) {
        if (empty(trim($stmt))) continue;
        try {
            $db->exec($stmt);
            $created++;
        } catch (PDOException $e) {
            $msg = $e->getMessage();
            if (str_contains($msg, 'already exists')) {
                $skipped++;
            } else {
                $errors[] = $msg;
            }
        }
    }

    if (!empty($errors)) {
        jsonResponse(false, 'Certaines tables ont echoue: ' . implode('; ', array_slice($errors, 0, 3)), [
            'created' => $created,
            'skipped' => $skipped,
            'errors' => $errors,
        ]);
    }

    // Migration: add SFTP columns to users table if they don't exist yet.
    // Uses INFORMATION_SCHEMA check for MySQL compatibility (MySQL does not
    // support ADD COLUMN IF NOT EXISTS unlike MariaDB).
    try {
        $stmt = $db->prepare(
            "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
             WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users'"
        );
        $stmt->execute();
        $existingCols = array_column($stmt->fetchAll(PDO::FETCH_ASSOC), 'COLUMN_NAME');

        $sftpMigrations = [
            'storage_type'  => "ALTER TABLE users ADD COLUMN storage_type ENUM('local','sftp') NOT NULL DEFAULT 'local' AFTER music_directory",
            'sftp_host'     => "ALTER TABLE users ADD COLUMN sftp_host VARCHAR(255) NULL AFTER storage_type",
            'sftp_port'     => "ALTER TABLE users ADD COLUMN sftp_port SMALLINT UNSIGNED NOT NULL DEFAULT 22 AFTER sftp_host",
            'sftp_user'     => "ALTER TABLE users ADD COLUMN sftp_user VARCHAR(100) NULL AFTER sftp_port",
            'sftp_password' => "ALTER TABLE users ADD COLUMN sftp_password VARCHAR(512) NULL AFTER sftp_user",
            'sftp_path'     => "ALTER TABLE users ADD COLUMN sftp_path VARCHAR(255) NULL AFTER sftp_password",
        ];
        foreach ($sftpMigrations as $col => $sql) {
            if (!in_array($col, $existingCols)) {
                try { $db->exec($sql); } catch (PDOException $e) { /* ignore */ }
            }
        }
    } catch (PDOException $e) { /* users table not yet created — skip */ }

    jsonResponse(true, "$created instructions executees, $skipped deja existantes.", [
        'created' => $created,
        'skipped' => $skipped,
    ]);
}

function handleCheckMusicDir(): void {
    $data = getPostData();
    $path = $data['path'] ?? '';

    if (empty($path)) {
        jsonResponse(false, 'Le chemin est requis.');
    }

    $path = rtrim($path, '/');

    if (!is_dir($path)) {
        jsonResponse(false, "Le dossier '$path' n'existe pas.");
    }

    if (!is_readable($path)) {
        jsonResponse(false, "Le dossier '$path' n'est pas accessible en lecture.");
    }

    // List subdirectories
    $subdirs = [];
    $items = @scandir($path);
    if ($items) {
        foreach ($items as $item) {
            if ($item === '.' || $item === '..') continue;
            if (is_dir($path . '/' . $item)) {
                // Count audio files recursively (quick estimate)
                $subdirs[] = [
                    'name' => $item,
                    'path' => $item,
                ];
            }
        }
    }

    jsonResponse(true, 'Dossier valide. ' . count($subdirs) . ' sous-dossier(s) trouve(s).', [
        'path' => $path,
        'subdirectories' => $subdirs,
    ]);
}

function handleCreateAdmin(): void {
    $data = getPostData();

    $username = trim($data['username'] ?? '');
    $password = $data['password'] ?? '';
    $fullName = trim($data['full_name'] ?? '');
    $musicDir = trim($data['music_directory'] ?? '');

    if (empty($username)) {
        jsonResponse(false, "Le nom d'utilisateur est requis.");
    }
    if (strlen($username) < 3 || strlen($username) > 50) {
        jsonResponse(false, "Le nom d'utilisateur doit contenir entre 3 et 50 caracteres.");
    }
    if (!preg_match('/^[a-zA-Z0-9_-]+$/', $username)) {
        jsonResponse(false, "Le nom d'utilisateur ne peut contenir que des lettres, chiffres, tirets et underscores.");
    }
    if (empty($password)) {
        jsonResponse(false, 'Le mot de passe est requis.');
    }
    if (strlen($password) < 6) {
        jsonResponse(false, 'Le mot de passe doit contenir au moins 6 caracteres.');
    }

    try {
        $db = AppConfig::getDB();

        // Check if admin already exists
        $stmt = $db->query('SELECT COUNT(*) FROM users WHERE is_admin = 1');
        $adminCount = $stmt->fetchColumn();
        if ($adminCount > 0) {
            jsonResponse(false, 'Un compte administrateur existe deja.');
        }

        $hash = password_hash($password, PASSWORD_BCRYPT, ['cost' => 12]);

        $stmt = $db->prepare('
            INSERT INTO users (username, password_hash, full_name, is_active, is_admin, music_directory, created_at)
            VALUES (?, ?, ?, 1, 1, ?, NOW())
        ');
        $stmt->execute([$username, $hash, $fullName, $musicDir ?: null]);

        jsonResponse(true, "Compte administrateur '$username' cree avec succes.", [
            'user_id' => (int) $db->lastInsertId(),
            'username' => $username,
        ]);
    } catch (PDOException $e) {
        if (str_contains($e->getMessage(), 'Duplicate entry')) {
            jsonResponse(false, "Le nom d'utilisateur '$username' est deja utilise.");
        }
        jsonResponse(false, 'Erreur base de donnees: ' . $e->getMessage());
    }
}

function handleAddUser(): void {
    $data = getPostData();

    $username = trim($data['username'] ?? '');
    $password = $data['password'] ?? '';
    $fullName = trim($data['full_name'] ?? '');
    $musicDir = trim($data['music_directory'] ?? '');

    if (empty($username)) {
        jsonResponse(false, "Le nom d'utilisateur est requis.");
    }
    if (strlen($username) < 3 || strlen($username) > 50) {
        jsonResponse(false, "Le nom d'utilisateur doit contenir entre 3 et 50 caracteres.");
    }
    if (!preg_match('/^[a-zA-Z0-9_-]+$/', $username)) {
        jsonResponse(false, "Le nom d'utilisateur ne peut contenir que des lettres, chiffres, tirets et underscores.");
    }
    if (empty($password)) {
        jsonResponse(false, 'Le mot de passe est requis.');
    }
    if (strlen($password) < 6) {
        jsonResponse(false, 'Le mot de passe doit contenir au moins 6 caracteres.');
    }

    try {
        $db = AppConfig::getDB();
        $hash = password_hash($password, PASSWORD_BCRYPT, ['cost' => 12]);

        $stmt = $db->prepare('
            INSERT INTO users (username, password_hash, full_name, is_active, is_admin, music_directory, created_at)
            VALUES (?, ?, ?, 1, 0, ?, NOW())
        ');
        $stmt->execute([$username, $hash, $fullName, $musicDir]);

        jsonResponse(true, "Utilisateur '$username' cree avec succes.", [
            'user_id' => (int) $db->lastInsertId(),
            'username' => $username,
        ]);
    } catch (PDOException $e) {
        if (str_contains($e->getMessage(), 'Duplicate entry')) {
            jsonResponse(false, "Le nom d'utilisateur '$username' est deja utilise.");
        }
        jsonResponse(false, 'Erreur base de donnees: ' . $e->getMessage());
    }
}

function handleStartScan(): void {
    $data = getPostData();
    $user = trim($data['user'] ?? '');

    $lockFile = '/tmp/gullify-scan.lock';
    $progressFile = '/tmp/gullify-scan-progress.json';

    // Check if already running
    if (file_exists($lockFile)) {
        $lockAge = time() - filemtime($lockFile);
        if ($lockAge < 1800) {
            jsonResponse(false, 'Un scan est deja en cours.');
        }
        @unlink($lockFile);
    }

    // Write initial progress
    file_put_contents($progressFile, json_encode([
        'status' => 'starting',
        'user' => $user,
        'started_at' => time(),
        'message' => 'Demarrage du scan...',
    ]));

    // Build the scan command
    $scanScript = AppConfig::getAppRoot() . '/scripts/run-scan.php';
    $srcDir = AppConfig::getSrcPath();

    // Create a temporary scan runner if it doesn't exist
    if (!file_exists($scanScript)) {
        $scanScript = '/tmp/gullify-scan-runner.php';
        $appRoot = AppConfig::getAppRoot();
        $runnerCode = <<<'PHPCODE'
<?php
// Gullify background scan runner
error_reporting(E_ALL);
ini_set('display_errors', 0);
ini_set('memory_limit', '1024M');
ini_set('max_execution_time', 3600);

$lockFile = '/tmp/gullify-scan.lock';
$progressFile = '/tmp/gullify-scan-progress.json';

file_put_contents($lockFile, getmypid());

function updateProgress(string $status, string $message, array $extra = []): void {
    global $progressFile;
    file_put_contents($progressFile, json_encode(array_merge([
        'status' => $status,
        'message' => $message,
        'updated_at' => time(),
    ], $extra)));
}

try {
    $appRoot = $argv[1] ?? '';
    $targetUser = $argv[2] ?? '';

    require_once $appRoot . '/src/AppConfig.php';
    require_once $appRoot . '/src/Scanner.php';

    updateProgress('scanning', 'Initialisation du scanner...');

    $scanner = new Scanner(false);
    $users = $targetUser ? [$targetUser] : $scanner->getAllUsers();

    if (empty($users)) {
        updateProgress('error', 'Aucun utilisateur avec un dossier musique trouve.');
        @unlink($lockFile);
        exit(1);
    }

    $totalUsers = count($users);
    $currentUser = 0;

    foreach ($users as $u) {
        $currentUser++;
        updateProgress('scanning', "Scan de l'utilisateur $u ($currentUser/$totalUsers)...", [
            'current_user' => $u,
            'progress' => round(($currentUser - 1) / $totalUsers * 100),
        ]);

        try {
            $scanner->scanUserIncremental($u);
        } catch (Exception $e) {
            updateProgress('scanning', "Erreur pour $u: " . $e->getMessage());
        }
    }

    // Get final stats
    $db = AppConfig::getDB();
    $stats = [
        'artists' => (int) $db->query('SELECT COUNT(*) FROM artists')->fetchColumn(),
        'albums' => (int) $db->query('SELECT COUNT(*) FROM albums')->fetchColumn(),
        'songs' => (int) $db->query('SELECT COUNT(*) FROM songs')->fetchColumn(),
    ];

    updateProgress('complete', 'Scan termine avec succes !', [
        'progress' => 100,
        'stats' => $stats,
    ]);

} catch (Throwable $e) {
    updateProgress('error', 'Erreur: ' . $e->getMessage());
}

@unlink($lockFile);
PHPCODE;
        file_put_contents($scanScript, $runnerCode);
    }

    $appRoot = escapeshellarg(AppConfig::getAppRoot());
    $userArg = escapeshellarg($user);

    // Launch in background
    $cmd = sprintf(
        'php %s %s %s > /tmp/gullify-scan.log 2>&1 &',
        escapeshellarg($scanScript),
        $appRoot,
        $userArg
    );
    exec($cmd);

    jsonResponse(true, 'Scan demarre en arriere-plan.', [
        'user' => $user,
    ]);
}

function handleScanStatus(): void {
    $progressFile = '/tmp/gullify-scan-progress.json';
    $lockFile = '/tmp/gullify-scan.lock';

    if (!file_exists($progressFile)) {
        jsonResponse(true, '', [
            'status' => 'idle',
            'running' => false,
            'message' => 'Aucun scan en cours.',
        ]);
    }

    $progress = json_decode(file_get_contents($progressFile), true);
    if (!$progress) {
        jsonResponse(true, '', [
            'status' => 'idle',
            'running' => false,
            'message' => 'Aucun scan en cours.',
        ]);
    }

    $running = file_exists($lockFile);
    $progress['running'] = $running;

    // If lock file gone but status not updated, mark complete
    if (!$running && ($progress['status'] ?? '') === 'scanning') {
        $progress['status'] = 'complete';
        $progress['message'] = 'Scan termine.';

        // Try to get stats
        try {
            $db = AppConfig::getDB();
            $progress['stats'] = [
                'artists' => (int) $db->query('SELECT COUNT(*) FROM artists')->fetchColumn(),
                'albums' => (int) $db->query('SELECT COUNT(*) FROM albums')->fetchColumn(),
                'songs' => (int) $db->query('SELECT COUNT(*) FROM songs')->fetchColumn(),
            ];
        } catch (Throwable $e) {
            // ignore
        }
    }

    jsonResponse(true, $progress['message'] ?? '', $progress);
}

function handleFinishSetup(): void {
    // Mark setup as done
    $result = AppConfig::updateEnv('GULLIFY_SETUP_DONE', 'true');
    if (!$result) {
        jsonResponse(false, "Impossible d'ecrire dans le fichier .env.");
    }

    // Get stats
    $stats = [
        'artists' => 0,
        'albums' => 0,
        'songs' => 0,
        'users' => 0,
    ];

    try {
        $db = AppConfig::getDB();
        $stats['artists'] = (int) $db->query('SELECT COUNT(*) FROM artists')->fetchColumn();
        $stats['albums'] = (int) $db->query('SELECT COUNT(*) FROM albums')->fetchColumn();
        $stats['songs'] = (int) $db->query('SELECT COUNT(*) FROM songs')->fetchColumn();
        $stats['users'] = (int) $db->query('SELECT COUNT(*) FROM users')->fetchColumn();
    } catch (Throwable $e) {
        // Stats unavailable, that's ok
    }

    jsonResponse(true, 'Configuration terminee !', [
        'stats' => $stats,
    ]);
}
