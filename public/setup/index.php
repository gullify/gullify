<?php
require_once __DIR__ . '/../../src/AppConfig.php';
header('Content-Type: text/html; charset=UTF-8');
// If already set up, go to main app
/** Échappement court : la page affiche des valeurs venues de la configuration. */
function e(?string $v): string {
    return htmlspecialchars((string)$v, ENT_QUOTES, 'UTF-8');
}

if (AppConfig::isSetupDone()) {
    header('Location: /');
    exit;
}

// Language detection (cookie → default fr)
$_allowedLangs = ['fr', 'en'];
$setupLang = $_COOKIE['gullify_lang'] ?? 'fr';
if (!in_array($setupLang, $_allowedLangs, true)) $setupLang = 'fr';
$_langFile = __DIR__ . '/../lang/' . $setupLang . '.json';
$_langData = file_exists($_langFile) ? file_get_contents($_langFile) : '{}';
?>
<!DOCTYPE html>
<html lang="<?= htmlspecialchars($setupLang) ?>">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Gullify - Configuration</title>
    <link rel="icon" href="/favicon.ico">
    <style>
        /* L'assistant porte l'habillage de la maison : les mêmes couleurs et la
           même matière que l'app qui s'ouvrira juste après, et que la page
           d'accueil de gullify.app. C'est le premier écran qu'on voit de
           GulliFY — il ne doit pas avoir l'air d'un formulaire d'administration
           tombé d'un autre logiciel.

           Rien n'est téléchargé : ni police, ni bibliothèque. Un serveur qu'on
           installe n'a pas toujours une connexion aimable. */
        :root {
            color-scheme: dark;

            --fond: #07080e;
            --fond-carte: #121622;
            --fond-carte-haut: #161b2a;
            --fond-champ: #1a2030;

            --bordure: #262c3d;
            --bordure-vive: #39415c;

            --texte: #c3cbdd;
            --texte-vif: #f2f5fc;
            --texte-attenue: #99a1b7;

            --fy: #2C6774;
            --accent: #3A93AC;
            --accent-clair: #6FC6DB;
            --succes: #5ad79b;
            --danger: #ff8080;

            --rayon: 14px;
            --rayon-l: 20px;

            /* La pile système : c'est la police du logotype de la gamme. */
            --police: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto,
                'Helvetica Neue', Arial, sans-serif;
        }

        * { margin: 0; padding: 0; box-sizing: border-box; }

        body {
            font-family: var(--police);
            background:
                radial-gradient(900px 500px at 15% -10%, rgba(58, 147, 172, .16), transparent 60%),
                var(--fond);
            color: var(--texte);
            line-height: 1.6;
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: flex-start;
            padding: 40px 20px 80px;
        }

        .wizard { max-width: 620px; width: 100%; }

        /* ── Le logo ─────────────────────────────────────────────────────── */

        .logo { text-align: center; margin-bottom: 28px; }

        .logo .marque {
            display: inline-flex;
            align-items: center;
            gap: .55rem;
            font-weight: 800;
            font-size: 2.1rem;
            letter-spacing: -.03em;
            color: var(--texte-vif);
            line-height: 1;
        }

        /* Le signe fait 1,74 fois la taille du nom : les proportions de la
           gamme, les mêmes que sur le site et dans l'app. */
        .logo .marque img { width: 42px; height: 60px; object-fit: contain; }
        .logo .fy { color: var(--fy); }
        .logo p { color: var(--texte-attenue); margin-top: 10px; font-size: .95rem; }

        /* ── Les pastilles d'étapes ──────────────────────────────────────── */

        .steps {
            display: flex;
            justify-content: center;
            gap: 10px;
            margin-bottom: 26px;
        }

        .steps .step-dot {
            width: 9px;
            height: 9px;
            border-radius: 50%;
            background: var(--bordure-vive);
            transition: background-color .25s ease, transform .25s ease;
        }

        .steps .step-dot.active { background: var(--accent-clair); transform: scale(1.35); }
        .steps .step-dot.done { background: var(--fy); }

        /* ── Les cartes ──────────────────────────────────────────────────── */

        .card {
            background: linear-gradient(180deg, var(--fond-carte-haut), var(--fond-carte));
            border: 1px solid var(--bordure);
            border-radius: var(--rayon-l);
            padding: 28px;
            box-shadow: 0 18px 44px rgba(0, 0, 0, .45);
        }

        .card h2 {
            font-size: 1.45rem;
            font-weight: 700;
            letter-spacing: -.02em;
            color: var(--texte-vif);
            margin-bottom: 6px;
        }

        .card .subtitle {
            color: var(--texte-attenue);
            font-size: .95rem;
            margin-bottom: 22px;
        }

        /* Les écrans se cachent par la classe « hidden », que goStep() pose et
           retire — pas par une classe « active » : le premier écran n'en a
           aucune au chargement. */
        .hidden { display: none !important; }

        /* ── Les champs ──────────────────────────────────────────────────── */

        .form-group { margin-bottom: 16px; }

        .form-group label {
            display: block;
            font-size: .88rem;
            color: var(--texte-vif);
            margin-bottom: 6px;
        }

        .form-group input {
            width: 100%;
            padding: .75em .9em;
            border-radius: var(--rayon);
            background: var(--fond-champ);
            border: 1px solid var(--bordure);
            color: var(--texte-vif);
            font: inherit;
        }

        .form-group input::placeholder { color: var(--texte-attenue); }
        .form-group input:focus { outline: none; border-color: var(--accent); }

        .form-row { display: flex; gap: 12px; }
        .form-row .form-group { flex: 1; }

        /* ── Les boutons ─────────────────────────────────────────────────── */

        .actions { display: flex; flex-wrap: wrap; gap: 10px; margin-top: 22px; }

        .btn {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            gap: .5rem;
            min-height: 48px;
            padding: .7em 1.5em;
            border-radius: 999px;
            border: 1px solid transparent;
            font: inherit;
            font-weight: 700;
            cursor: pointer;
            text-decoration: none;
            transition: transform .15s ease, background-color .15s ease, border-color .15s ease;
        }

        .btn-primary { background: var(--accent); color: #04121a; }
        .btn-primary:hover:not(:disabled) { transform: translateY(-1px); background: var(--accent-clair); }
        .btn-primary:disabled { opacity: .45; cursor: not-allowed; transform: none; }

        .btn-secondary { background: transparent; color: var(--texte-vif); border-color: var(--bordure-vive); }
        .btn-secondary:hover:not(:disabled) { border-color: var(--accent); color: var(--accent-clair); }
        .btn-secondary:disabled { opacity: .45; cursor: not-allowed; }

        .btn-success { background: var(--succes); color: #04121a; }

        /* ── Les messages ────────────────────────────────────────────────── */

        .status-msg {
            margin-top: 14px;
            padding: .8em 1em;
            border-radius: var(--rayon);
            font-size: .92rem;
            border: 1px solid transparent;
        }

        .status-msg.info { background: rgba(58, 147, 172, .1); border-color: rgba(58, 147, 172, .3); color: var(--accent-clair); }
        .status-msg.success { background: rgba(90, 215, 155, .1); border-color: rgba(90, 215, 155, .3); color: var(--succes); }
        .status-msg.error { background: rgba(255, 128, 128, .1); border-color: rgba(255, 128, 128, .3); color: var(--danger); }

        /* ── La liste des vérifications ──────────────────────────────────── */

        .check-list { list-style: none; }

        .check-list li {
            display: flex;
            align-items: center;
            gap: 12px;
            padding: 11px 0;
            border-bottom: 1px solid var(--bordure);
            font-size: .95rem;
        }

        .check-list li:last-child { border-bottom: none; }

        .check-icon {
            flex: none;
            width: 22px;
            height: 22px;
            border-radius: 50%;
            display: grid;
            place-items: center;
            font-size: .75rem;
            font-weight: 700;
        }

        .check-icon.pass { background: rgba(90, 215, 155, .16); color: var(--succes); }
        .check-icon.fail { background: rgba(255, 128, 128, .16); color: var(--danger); }
        .check-icon.wait { background: rgba(153, 161, 183, .14); color: var(--texte-attenue); }

        /* ── Le choix du stockage ────────────────────────────────────────── */

        .storage-options { display: grid; gap: 12px; margin-bottom: 18px; }

        .storage-option {
            display: flex;
            align-items: flex-start;
            gap: 14px;
            padding: 16px;
            border-radius: var(--rayon);
            border: 1px solid var(--bordure);
            background: var(--fond-champ);
            cursor: pointer;
            transition: border-color .15s ease, background-color .15s ease;
        }

        .storage-option:hover { border-color: var(--bordure-vive); }
        .storage-option.active { border-color: var(--accent); background: rgba(58, 147, 172, .1); }
        .storage-option .storage-icon { font-size: 1.5rem; line-height: 1.2; }
        .storage-option strong { display: block; color: var(--texte-vif); }
        .storage-option p { color: var(--texte-attenue); font-size: .88rem; }

        .sftp-fields { margin-top: 6px; }

        /* ── Les comptes créés ───────────────────────────────────────────── */

        .user-card {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 12px;
            padding: 12px 14px;
            border-radius: var(--rayon);
            background: var(--fond-champ);
            border: 1px solid var(--bordure);
            margin-bottom: 10px;
        }

        .user-card .role {
            font-size: .78rem;
            font-weight: 700;
            letter-spacing: .06em;
            text-transform: uppercase;
            color: var(--texte-attenue);
        }

        .user-card .role.admin { color: var(--accent-clair); }

        /* ── La fin ──────────────────────────────────────────────────────── */

        .done-icon {
            width: 72px;
            height: 72px;
            margin: 0 auto 18px;
            border-radius: 50%;
            display: grid;
            place-items: center;
            font-size: 2rem;
            background: rgba(90, 215, 155, .14);
            border: 1px solid rgba(90, 215, 155, .35);
            color: var(--succes);
        }

        .done-hint { color: var(--texte-attenue); font-size: .92rem; margin-top: 14px; }

        /* ── L'attente ───────────────────────────────────────────────────── */

        .spinner {
            display: inline-block;
            width: 16px;
            height: 16px;
            border: 2px solid rgba(255, 255, 255, .25);
            border-top-color: var(--texte-vif);
            border-radius: 50%;
            animation: spin .7s linear infinite;
        }

        @keyframes spin { to { transform: rotate(360deg); } }

        @media (max-width: 560px) {
            body { padding: 24px 14px 60px; }
            .card { padding: 20px; }
            .form-row { flex-direction: column; gap: 0; }
            .actions .btn { flex: 1 1 100%; }
        }
    </style>
</head>
<body>
<div class="wizard">
    <div class="logo">
        <span class="marque">
            <img src="gulli-mark.png" alt="" width="42" height="60" decoding="async">
            <span>Gulli<span class="fy">FY</span></span>
        </span>
        <p id="setupSubtitle">Assistant de configuration</p>
    </div>

    <div class="steps" id="stepDots"></div>

    <!-- Step 1: Requirements -->
    <div class="card step-card" id="step-1">
        <h2 id="s1-title">Vérification du système</h2>
        <p class="subtitle" id="s1-sub">Vérification des prérequis nécessaires au fonctionnement de Gullify.</p>
        <ul class="check-list" id="reqList">
            <li><span class="check-icon wait">...</span> <span id="s1-checking">Vérification en cours...</span></li>
        </ul>
        <div class="actions">
            <div></div>
            <button class="btn btn-primary" id="reqNext" disabled id="s1-next">Suivant</button>
        </div>
    </div>

    <!-- Step 2: Database -->
    <div class="card step-card hidden" id="step-2">
        <h2 id="s2-title">Base de données</h2>
        <p class="subtitle" id="s2-sub">Configurez la connexion MySQL et testez-la.</p>
        <div class="form-row">
            <div class="form-group">
                <label id="s2-host">Hôte</label>
                <input type="text" id="dbHost" value="<?= e(AppConfig::get('mysql.host', 'db')) ?>">
            </div>
            <div class="form-group" style="max-width: 100px;">
                <label id="s2-port">Port</label>
                <input type="text" id="dbPort" value="<?= e(AppConfig::get('mysql.port', '3306')) ?>">
            </div>
        </div>
        <div class="form-group">
            <label id="s2-dbname">Base de données</label>
            <input type="text" id="dbName" value="<?= e(AppConfig::get('mysql.database', 'gullify')) ?>">
        </div>
        <div class="form-row">
            <div class="form-group">
                <label id="s2-user">Utilisateur</label>
                <input type="text" id="dbUser" value="<?= e(AppConfig::get('mysql.user', 'gullify')) ?>">
            </div>
            <div class="form-group">
                <label id="s2-pass">Mot de passe</label>
                <input type="password" id="dbPass" value="" placeholder="celui du serveur (laisse vide)">
            </div>
        </div>
        <div id="dbStatus"></div>
        <div class="actions">
            <button class="btn btn-secondary" onclick="goStep(1)" id="s2-back">Retour</button>
            <div style="display:flex;gap:8px;">
                <button class="btn btn-secondary" id="dbTestBtn" onclick="testDatabase()">Tester</button>
                <button class="btn btn-primary" id="dbNext" disabled>Suivant</button>
            </div>
        </div>
    </div>

    <!-- Step 3: Admin account -->
    <div class="card step-card hidden" id="step-3">
        <h2 id="s3-title">Compte administrateur</h2>
        <p class="subtitle" id="s3-sub">Créez le premier compte pour accéder à Gullify.</p>
        <div class="form-group">
            <label id="s3-fullname">Nom complet</label>
            <input type="text" id="adminFullName" placeholder="Maxime Dupont">
        </div>
        <div class="form-row">
            <div class="form-group">
                <label id="s3-username">Nom d'utilisateur</label>
                <input type="text" id="adminUser" placeholder="maxime">
            </div>
            <div class="form-group">
                <label id="s3-password">Mot de passe</label>
                <input type="password" id="adminPass" placeholder="Min. 6 caractères">
            </div>
        </div>
        <div id="adminStatus"></div>
        <div id="userList"></div>
        <div class="actions">
            <button class="btn btn-secondary" onclick="goStep(2)" id="s3-back">Retour</button>
            <div style="display:flex;gap:8px;">
                <button class="btn btn-secondary" id="createAdminBtn" onclick="createAdmin()">Créer</button>
                <button class="btn btn-primary" id="adminNext" disabled>Suivant</button>
            </div>
        </div>
    </div>

    <!-- Step 4: Storage -->
    <div class="card step-card hidden" id="step-4">
        <h2 id="s4-title">Stockage de la musique</h2>
        <p class="subtitle" id="s4-sub">Où se trouvent vos fichiers audio ?</p>
        <div class="storage-options">
            <div class="storage-option active" id="opt-local" onclick="selectStorage('local')">
                <div class="storage-icon">🖥️</div>
                <div>
                    <strong id="s4-local-title">Stockage local</strong>
                    <p id="s4-local-desc">Les fichiers sont sur ce serveur, montés via le volume Docker <code>/music</code></p>
                </div>
            </div>
            <div class="storage-option" id="opt-sftp" onclick="selectStorage('sftp')">
                <div class="storage-icon">🌐</div>
                <div>
                    <strong id="s4-sftp-title">SFTP / NAS distant</strong>
                    <p id="s4-sftp-desc">Les fichiers sont sur un NAS ou serveur distant, accessible via SFTP</p>
                </div>
            </div>
        </div>

        <!-- Local fields -->
        <div id="local-fields">
            <div class="form-group">
                <label id="s4-subdir">Sous-dossier dans /music <span style="color:#555">(optionnel)</span></label>
                <input type="text" id="musicDir" placeholder="ex: maxime  — laisser vide pour utiliser /music directement">
            </div>
            <div class="status-msg info" id="s4-local-hint">
                Le dossier <strong>/music</strong> est monté depuis votre machine hôte. Configurez <code>MUSIC_HOST_PATH</code> dans votre <code>.env</code> pour pointer vers votre bibliothèque.
            </div>
        </div>

        <!-- SFTP fields -->
        <div id="sftp-fields" class="hidden sftp-fields">
            <div class="form-row">
                <div class="form-group" style="flex: 3;">
                    <label id="s4-sftp-host">Hôte SFTP</label>
                    <input type="text" id="sftpHost" placeholder="nas.exemple.com ou 192.168.1.100">
                </div>
                <div class="form-group" style="flex: 1;">
                    <label id="s4-sftp-port">Port</label>
                    <input type="number" id="sftpPort" value="22">
                </div>
            </div>
            <div class="form-row">
                <div class="form-group">
                    <label id="s4-sftp-user">Utilisateur SFTP</label>
                    <input type="text" id="sftpUser" placeholder="admin">
                </div>
                <div class="form-group">
                    <label id="s4-sftp-pass">Mot de passe</label>
                    <input type="password" id="sftpPass" placeholder="••••••••">
                </div>
            </div>
            <div class="form-group">
                <label id="s4-sftp-path">Chemin distant</label>
                <input type="text" id="sftpPath" placeholder="/volume1/Musique">
            </div>
            <button class="btn btn-secondary" id="sftpTestBtn" onclick="testSftp()">Tester la connexion</button>
        </div>

        <div id="storageStatus"></div>
        <div class="actions">
            <button class="btn btn-secondary" onclick="goStep(3)" id="s4-back">Retour</button>
            <div style="display:flex;gap:8px;">
                <button class="btn btn-secondary" onclick="goStep(5)" id="s4-skip">Passer</button>
                <button class="btn btn-primary" id="storageSaveBtn" onclick="saveStorage()">Enregistrer</button>
            </div>
        </div>
    </div>

    <!-- Step 5: Done -->
    <div class="card step-card hidden" id="step-5">
        <h2 id="s5-title">Configuration terminée !</h2>
        <p class="subtitle" id="s5-sub">Gullify est prêt à utiliser.</p>
        <div class="done-icon">&#127925;</div>
        <div class="done-hint" id="s5-hint">
            Connectez-vous et rendez-vous dans <strong>Paramètres</strong> pour ajuster votre configuration de stockage et lancer le scan de votre bibliothèque.
        </div>
        <div class="actions">
            <div></div>
            <button class="btn btn-success" onclick="finishSetup()" id="s5-finish">Accéder à Gullify</button>
        </div>
    </div>
</div>

<script>
// i18n: inline translations
window.gullifyLang = <?= $_langData ?>;
window.t = function(key, fallback) {
    const parts = key.split('.');
    let val = window.gullifyLang || {};
    for (const p of parts) { val = val?.[p]; if (val === undefined) return fallback ?? key; }
    return val ?? fallback ?? key;
};

const TOTAL_STEPS = 5;
let currentStep = 1;
let users = [];
let dbConnected = false;
let adminUserId = null;
let selectedStorage = 'local';

// Apply i18n translations to static elements
function applySetupI18n() {
    const m = {
        'setupSubtitle': t('setup.config_wizard', 'Assistant de configuration'),
        's1-title':      t('setup.sys_check', 'Vérification du système'),
        's1-sub':        t('setup.sys_check_subtitle', 'Vérification des prérequis nécessaires au fonctionnement de Gullify.'),
        's1-checking':   t('setup.check_in_progress', 'Vérification en cours...'),
        's2-title':      t('setup.database', 'Base de données'),
        's2-sub':        t('setup.database_subtitle', 'Configurez la connexion MySQL et testez-la.'),
        's2-host':       t('setup.db_host', 'Hôte'),
        's2-port':       t('setup.db_port', 'Port'),
        's2-dbname':     t('setup.db_name', 'Base de données'),
        's2-user':       t('setup.db_user', 'Utilisateur'),
        's2-pass':       t('setup.db_pass', 'Mot de passe'),
        's2-back':       t('setup.back', 'Retour'),
        'dbTestBtn':     t('setup.test', 'Tester'),
        'dbNext':        t('setup.next', 'Suivant'),
        'reqNext':       t('setup.next', 'Suivant'),
        's3-title':      t('setup.admin_account', 'Compte administrateur'),
        's3-sub':        t('setup.admin_subtitle', 'Créez le premier compte pour accéder à Gullify.'),
        's3-fullname':   t('setup.full_name', 'Nom complet'),
        's3-username':   t('setup.username', "Nom d'utilisateur"),
        's3-password':   t('setup.password', 'Mot de passe'),
        's3-back':       t('setup.back', 'Retour'),
        'createAdminBtn': t('setup.create', 'Créer'),
        'adminNext':     t('setup.next', 'Suivant'),
        's4-title':      t('setup.storage_title', 'Stockage de la musique'),
        's4-sub':        t('setup.storage_subtitle', 'Où se trouvent vos fichiers audio ?'),
        's4-local-title': t('setup.local_storage', 'Stockage local'),
        's4-local-desc': t('setup.local_desc', 'Les fichiers sont sur ce serveur, montés via le volume Docker /music'),
        's4-sftp-title': t('setup.sftp_storage', 'SFTP / NAS distant'),
        's4-sftp-desc':  t('setup.sftp_desc', 'Les fichiers sont sur un NAS ou serveur distant, accessible via SFTP'),
        's4-sftp-host':  t('setup.sftp_host', 'Hôte SFTP'),
        's4-sftp-port':  t('setup.sftp_port', 'Port'),
        's4-sftp-user':  t('setup.sftp_user', 'Utilisateur SFTP'),
        's4-sftp-pass':  t('setup.sftp_pass', 'Mot de passe'),
        's4-sftp-path':  t('setup.sftp_path', 'Chemin distant'),
        'sftpTestBtn':   t('setup.test_connection', 'Tester la connexion'),
        's4-back':       t('setup.back', 'Retour'),
        's4-skip':       t('setup.skip', 'Passer'),
        'storageSaveBtn': t('setup.save', 'Enregistrer'),
        's5-title':      t('setup.complete', 'Configuration terminée !'),
        's5-sub':        t('setup.complete_subtitle', 'Gullify est prêt à utiliser.'),
        's5-finish':     t('setup.finish', 'Accéder à Gullify'),
    };
    for (const [id, text] of Object.entries(m)) {
        const el = document.getElementById(id);
        if (el) el.textContent = text;
    }
}

// Init
document.addEventListener('DOMContentLoaded', () => {
    applySetupI18n();
    buildStepDots();
    checkRequirements();
});

function buildStepDots() {
    const c = document.getElementById('stepDots');
    c.innerHTML = '';
    for (let i = 1; i <= TOTAL_STEPS; i++) {
        const d = document.createElement('div');
        d.className = 'step-dot' + (i < currentStep ? ' done' : '') + (i === currentStep ? ' active' : '');
        c.appendChild(d);
    }
}

function goStep(n) {
    document.querySelectorAll('.step-card').forEach(el => el.classList.add('hidden'));
    document.getElementById('step-' + n).classList.remove('hidden');
    currentStep = n;
    buildStepDots();
}

async function api(action, data = null) {
    const opts = { headers: { 'Content-Type': 'application/json' } };
    let url = '/setup/api.php?action=' + action;
    if (data) {
        opts.method = 'POST';
        opts.body = JSON.stringify(data);
    }
    const res = await fetch(url, opts);
    return res.json();
}

function showStatus(id, msg, type) {
    const el = document.getElementById(id);
    el.innerHTML = '<div class="status-msg ' + type + '">' + msg + '</div>';
}

// Step 1
async function checkRequirements() {
    const r = await api('check_requirements');
    const list = document.getElementById('reqList');
    if (r.success) {
        list.innerHTML = '';
        r.requirements.forEach(req => {
            const li = document.createElement('li');
            li.innerHTML = '<span class="check-icon ' + (req.status ? 'pass' : 'fail') + '">' +
                (req.status ? '&#10003;' : '&#10007;') + '</span>' +
                '<span>' + req.name + ' <span style="color:#666">(' + req.current + ')</span></span>';
            list.appendChild(li);
        });
        if (r.all_passed) {
            document.getElementById('reqNext').disabled = false;
            document.getElementById('reqNext').onclick = () => goStep(2);
        }
    }
}

// Les identifiants de la BASE, préfixés : sans ça, « password » désignait à la
// fois le mot de passe de la base et celui du compte à créer, et le premier
// écrasait le second.
function getDbCredentials() {
    return {
        db_host: document.getElementById('dbHost').value,
        db_port: document.getElementById('dbPort').value,
        db_database: document.getElementById('dbName').value,
        db_user: document.getElementById('dbUser').value,
        db_password: document.getElementById('dbPass').value,
    };
}

// Step 2
async function testDatabase() {
    const btn = document.getElementById('dbTestBtn');
    btn.innerHTML = '<span class="spinner"></span>';
    btn.disabled = true;

    const r = await api('test_database', getDbCredentials());

    btn.innerHTML = t('setup.test', 'Tester');
    btn.disabled = false;

    if (r.success) {
        showStatus('dbStatus', r.message, 'success');
        // Auto-create tables
        const r2 = await api('create_tables', getDbCredentials());
        if (r2.success) {
            showStatus('dbStatus', r.message + '<br>Tables: ' + r2.message, 'success');
        }
        dbConnected = true;
        document.getElementById('dbNext').disabled = false;
        document.getElementById('dbNext').onclick = () => goStep(3);
    } else {
        showStatus('dbStatus', r.message, 'error');
    }
}

// Step 3
async function createAdmin() {
    const username = document.getElementById('adminUser').value.trim();
    const password = document.getElementById('adminPass').value;
    const fullName = document.getElementById('adminFullName').value.trim();

    if (!username || !password) {
        showStatus('adminStatus', t('setup.username_pass_required', "Nom d'utilisateur et mot de passe requis."), 'error');
        return;
    }

    const isFirst = users.length === 0;
    const action = isFirst ? 'create_admin' : 'add_user';
    const r = await api(action, { username, password, full_name: fullName, ...getDbCredentials() });

    if (r.success) {
        adminUserId = r.user_id;
        users.push({ username, fullName, isAdmin: isFirst });
        renderUsers();
        showStatus('adminStatus', r.message, 'success');
        document.getElementById('adminUser').value = '';
        document.getElementById('adminPass').value = '';
        document.getElementById('adminFullName').value = '';
        document.getElementById('createAdminBtn').textContent = t('setup.add_user', 'Ajouter utilisateur');
        document.getElementById('adminNext').disabled = false;
        document.getElementById('adminNext').onclick = () => goStep(4);
    } else if (r.message && r.message.includes('existe deja')) {
        if (r.user_id) adminUserId = r.user_id;
        showStatus('adminStatus', r.message + ' ' + t('setup.can_continue', 'Vous pouvez continuer.'), 'info');
        document.getElementById('createAdminBtn').textContent = t('setup.add_user', 'Ajouter utilisateur');
        document.getElementById('adminNext').disabled = false;
        document.getElementById('adminNext').onclick = () => goStep(4);
    } else {
        showStatus('adminStatus', r.message, 'error');
    }
}

function renderUsers() {
    const c = document.getElementById('userList');
    c.innerHTML = users.map(u =>
        '<div class="user-card">' +
        '<span>' + (u.fullName || u.username) + ' <span style="color:#666">(' + u.username + ')</span></span>' +
        '<span class="role ' + (u.isAdmin ? 'admin' : '') + '">' + (u.isAdmin ? 'Admin' : 'Utilisateur') + '</span>' +
        '</div>'
    ).join('');
}

// Step 4 — Storage
function selectStorage(type) {
    selectedStorage = type;
    document.getElementById('opt-local').classList.toggle('active', type === 'local');
    document.getElementById('opt-sftp').classList.toggle('active', type === 'sftp');
    document.getElementById('local-fields').classList.toggle('hidden', type !== 'local');
    document.getElementById('sftp-fields').classList.toggle('hidden', type !== 'sftp');
    document.getElementById('storageStatus').innerHTML = '';
}

async function testSftp() {
    const btn = document.getElementById('sftpTestBtn');
    btn.innerHTML = '<span class="spinner"></span>';
    btn.disabled = true;

    const r = await api('test_sftp', {
        sftp_host: document.getElementById('sftpHost').value,
        sftp_port: document.getElementById('sftpPort').value,
        sftp_user: document.getElementById('sftpUser').value,
        sftp_password: document.getElementById('sftpPass').value,
        sftp_path: document.getElementById('sftpPath').value,
    });

    btn.innerHTML = t('setup.test_connection', 'Tester la connexion');
    btn.disabled = false;
    showStatus('storageStatus', r.message || r.error, r.success ? 'success' : 'error');
}

async function saveStorage() {
    const btn = document.getElementById('storageSaveBtn');
    btn.innerHTML = '<span class="spinner"></span>';
    btn.disabled = true;

    const data = { user_id: adminUserId, storage_type: selectedStorage };

    if (selectedStorage === 'local') {
        data.music_directory = document.getElementById('musicDir').value.trim();
    } else {
        data.sftp_host = document.getElementById('sftpHost').value.trim();
        data.sftp_port = document.getElementById('sftpPort').value;
        data.sftp_user = document.getElementById('sftpUser').value.trim();
        data.sftp_password = document.getElementById('sftpPass').value;
        data.sftp_path = document.getElementById('sftpPath').value.trim();
    }

    const r = await api('save_storage', data);

    btn.innerHTML = t('setup.save', 'Enregistrer');
    btn.disabled = false;

    if (r.success) {
        showStatus('storageStatus', r.message, 'success');
        setTimeout(() => goStep(5), 800);
    } else {
        showStatus('storageStatus', r.message || r.error, 'error');
    }
}

// Step 5
async function finishSetup() {
    const r = await api('finish_setup');
    if (r.success) {
        window.location.href = '/';
    } else {
        alert(t('setup.error', 'Erreur') + ': ' + r.message);
    }
}
</script>
</body>
</html>
