<?php
/**
 * Gullify - Login Page
 * Apple Liquid Glass style authentication.
 */
require_once __DIR__ . '/../src/AppConfig.php';
require_once __DIR__ . '/../src/Auth.php';

// Start session with 30-day cookie
$cookieLifetime = 2592000;
$secure = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off');
session_set_cookie_params([
    'lifetime' => $cookieLifetime,
    'path'     => '/',
    'domain'   => '',
    'secure'   => $secure,
    'httponly'  => true,
    'samesite'  => 'Lax',
]);
session_name('gullify_session');
session_start();

// Already logged in? Redirect to app
if (!empty($_SESSION['user_id'])) {
    try {
        $auth = new Auth();
        $dbSession = $auth->getSession(session_id());
        if ($dbSession && $dbSession['user_id'] == $_SESSION['user_id']) {
            header('Location: index.php');
            exit;
        }
    } catch (Exception $e) {
        // Fall through to login form
    }
}

$error = '';

// Handle POST login
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = trim($_POST['username'] ?? '');
    $password = $_POST['password'] ?? '';

    if ($username === '' || $password === '') {
        $error = 'Veuillez remplir tous les champs.';
    } else {
        try {
            $auth = new Auth();
            $user = $auth->verifyPassword($username, $password);

            if ($user) {
                // Regenerate session ID for security
                session_regenerate_id(true);

                // Store in session
                $_SESSION['user_id']  = $user['id'];
                $_SESSION['username'] = $user['username'];
                $_SESSION['is_admin'] = (bool)$user['is_admin'];

                // Create DB session
                $auth->createSession(
                    session_id(),
                    $user['id'],
                    $_SERVER['REMOTE_ADDR'] ?? '',
                    $_SERVER['HTTP_USER_AGENT'] ?? ''
                );

                // Update last login
                $auth->updateLastLogin($user['id']);

                header('Location: index.php');
                exit;
            } else {
                $error = 'Identifiants incorrects.';
            }
        } catch (Exception $e) {
            error_log('Login error: ' . $e->getMessage());
            $error = 'Erreur de connexion. Veuillez réessayer.';
        }
    }
}

$hasError = !empty($error);
?>
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Connexion - Gullify</title>
    <link rel="icon" type="image/x-icon" href="favicon.ico">
    <link rel="apple-touch-icon" href="apple-touch-icon.png">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Shadows+Into+Light&display=swap" rel="stylesheet">
    <style>
        *, *::before, *::after {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }

        :root {
            --glass-bg: rgba(255, 255, 255, 0.12);
            --glass-border: rgba(255, 255, 255, 0.18);
            --glass-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
            --input-bg: rgba(255, 255, 255, 0.08);
            --input-border: rgba(255, 255, 255, 0.15);
            --input-focus: rgba(255, 255, 255, 0.25);
            --text-primary: #ffffff;
            --text-secondary: rgba(255, 255, 255, 0.6);
            --accent: #6C5CE7;
            --accent-hover: #7C6CF7;
            --error: #ff6b6b;
        }

        @media (prefers-color-scheme: light) {
            :root {
                --glass-bg: rgba(255, 255, 255, 0.65);
                --glass-border: rgba(255, 255, 255, 0.5);
                --glass-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
                --input-bg: rgba(0, 0, 0, 0.04);
                --input-border: rgba(0, 0, 0, 0.1);
                --input-focus: rgba(0, 0, 0, 0.15);
                --text-primary: #1a1a2e;
                --text-secondary: rgba(0, 0, 0, 0.5);
                --accent: #6C5CE7;
                --accent-hover: #5A4BD6;
            }
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Segoe UI', Roboto, sans-serif;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            background: linear-gradient(135deg, #0f0c29 0%, #302b63 50%, #24243e 100%);
            overflow: hidden;
            padding: 20px;
        }

        @media (prefers-color-scheme: light) {
            body {
                background: linear-gradient(135deg, #667eea 0%, #764ba2 50%, #f093fb 100%);
            }
        }

        /* Animated background orbs */
        .bg-orb {
            position: fixed;
            border-radius: 50%;
            filter: blur(80px);
            opacity: 0.3;
            animation: float 20s ease-in-out infinite;
        }

        .bg-orb:nth-child(1) {
            width: 400px;
            height: 400px;
            background: #6C5CE7;
            top: -100px;
            left: -100px;
            animation-delay: 0s;
        }

        .bg-orb:nth-child(2) {
            width: 300px;
            height: 300px;
            background: #a29bfe;
            bottom: -80px;
            right: -80px;
            animation-delay: -7s;
        }

        .bg-orb:nth-child(3) {
            width: 250px;
            height: 250px;
            background: #fd79a8;
            top: 50%;
            left: 50%;
            animation-delay: -14s;
        }

        @keyframes float {
            0%, 100% { transform: translate(0, 0) scale(1); }
            25% { transform: translate(30px, -30px) scale(1.05); }
            50% { transform: translate(-20px, 20px) scale(0.95); }
            75% { transform: translate(20px, 10px) scale(1.02); }
        }

        /* Glass card */
        .login-card {
            position: relative;
            width: 100%;
            max-width: 400px;
            padding: 48px 40px;
            background: var(--glass-bg);
            backdrop-filter: blur(40px) saturate(180%);
            -webkit-backdrop-filter: blur(40px) saturate(180%);
            border: 1px solid var(--glass-border);
            border-radius: 24px;
            box-shadow: var(--glass-shadow);
            z-index: 1;
        }

        .login-header {
            text-align: center;
            margin-bottom: 36px;
        }

        .login-logo {
            max-width: 220px;
            height: auto;
            margin-bottom: 16px;
        }

        .login-title {
            font-family: "Shadows Into Light", cursive;
            font-weight: 400;
            font-size: 36px;
            color: var(--text-primary);
            letter-spacing: 1px;
        }

        .login-subtitle {
            font-size: 14px;
            color: var(--text-secondary);
            margin-top: 6px;
        }

        /* Form */
        .form-group {
            margin-bottom: 20px;
        }

        .form-group label {
            display: block;
            font-size: 13px;
            font-weight: 500;
            color: var(--text-secondary);
            margin-bottom: 8px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .form-group input {
            width: 100%;
            padding: 14px 16px;
            background: var(--input-bg);
            border: 1px solid var(--input-border);
            border-radius: 12px;
            color: var(--text-primary);
            font-size: 16px;
            font-family: inherit;
            transition: all 0.2s ease;
            outline: none;
        }

        .form-group input::placeholder {
            color: var(--text-secondary);
        }

        .form-group input:focus {
            border-color: var(--accent);
            background: var(--input-focus);
            box-shadow: 0 0 0 3px rgba(108, 92, 231, 0.15);
        }

        .submit-btn {
            width: 100%;
            padding: 14px;
            background: linear-gradient(135deg, var(--accent), #a29bfe);
            border: none;
            border-radius: 12px;
            color: #fff;
            font-size: 16px;
            font-weight: 600;
            font-family: inherit;
            cursor: pointer;
            transition: all 0.2s ease;
            margin-top: 8px;
        }

        .submit-btn:hover {
            background: linear-gradient(135deg, var(--accent-hover), #b8b0ff);
            transform: translateY(-1px);
            box-shadow: 0 4px 16px rgba(108, 92, 231, 0.4);
        }

        .submit-btn:active {
            transform: translateY(0);
        }

        /* Error */
        .error-message {
            background: rgba(255, 107, 107, 0.15);
            border: 1px solid rgba(255, 107, 107, 0.3);
            border-radius: 10px;
            padding: 12px 16px;
            margin-bottom: 20px;
            color: var(--error);
            font-size: 14px;
            text-align: center;
        }

        /* Shake animation */
        @keyframes shake {
            0%, 100% { transform: translateX(0); }
            10%, 30%, 50%, 70%, 90% { transform: translateX(-4px); }
            20%, 40%, 60%, 80% { transform: translateX(4px); }
        }

        .shake {
            animation: shake 0.5s ease-in-out;
        }

        /* Responsive */
        @media (max-width: 480px) {
            .login-card {
                padding: 36px 24px;
            }
            .login-logo {
                max-width: 160px;
            }
        }
    </style>
</head>
<body>
    <div class="bg-orb"></div>
    <div class="bg-orb"></div>
    <div class="bg-orb"></div>

    <div class="login-card<?= $hasError ? ' shake' : '' ?>" id="loginCard">
        <div class="login-header">
            <img src="logo_gullify_wh.png" alt="Gullify" class="login-logo">
            <div class="login-subtitle">Connectez-vous pour continuer</div>
        </div>

        <?php if ($hasError): ?>
            <div class="error-message"><?= htmlspecialchars($error) ?></div>
        <?php endif; ?>

        <form method="POST" action="" id="loginForm">
            <div class="form-group">
                <label for="username">Nom d'utilisateur</label>
                <input type="text" id="username" name="username" placeholder="Entrez votre nom d'utilisateur"
                       value="<?= htmlspecialchars($_POST['username'] ?? '') ?>"
                       autocomplete="username" autofocus required>
            </div>

            <div class="form-group">
                <label for="password">Mot de passe</label>
                <input type="password" id="password" name="password" placeholder="Entrez votre mot de passe"
                       autocomplete="current-password" required>
            </div>

            <button type="submit" class="submit-btn">Se connecter</button>
        </form>
    </div>

    <script>
        // Remove shake class after animation so it can re-trigger
        const card = document.getElementById('loginCard');
        card.addEventListener('animationend', () => card.classList.remove('shake'));

        // Focus first empty field
        const usernameField = document.getElementById('username');
        const passwordField = document.getElementById('password');
        if (usernameField.value) {
            passwordField.focus();
        }
    </script>
</body>
</html>
