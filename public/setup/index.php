<?php
require_once __DIR__ . '/../../src/AppConfig.php';
// If already set up, go to main app
if (AppConfig::isSetupDone()) {
    header('Location: /');
    exit;
}
?>
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Gullify - Configuration</title>
    <link rel="icon" href="/favicon.ico">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #0a0a0a;
            color: #e0e0e0;
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: flex-start;
            padding: 40px 20px;
        }
        .wizard {
            max-width: 560px;
            width: 100%;
        }
        .logo {
            text-align: center;
            margin-bottom: 32px;
        }
        .logo img {
            max-width: 200px;
            height: auto;
        }
        .logo p {
            color: #888;
            margin-top: 8px;
            font-size: 14px;
        }
        .steps {
            display: flex;
            gap: 4px;
            margin-bottom: 28px;
        }
        .steps .step-dot {
            flex: 1;
            height: 4px;
            border-radius: 2px;
            background: #222;
            transition: background 0.3s;
        }
        .steps .step-dot.active { background: #6c5ce7; }
        .steps .step-dot.done { background: #00b894; }
        .card {
            background: #141414;
            border: 1px solid #222;
            border-radius: 12px;
            padding: 28px;
        }
        .card h2 {
            font-size: 18px;
            margin-bottom: 6px;
            color: #fff;
        }
        .card .subtitle {
            font-size: 13px;
            color: #888;
            margin-bottom: 20px;
        }
        .form-group {
            margin-bottom: 16px;
        }
        .form-group label {
            display: block;
            font-size: 13px;
            color: #aaa;
            margin-bottom: 6px;
            font-weight: 500;
        }
        .form-group input {
            width: 100%;
            padding: 10px 12px;
            background: #1a1a1a;
            border: 1px solid #333;
            border-radius: 8px;
            color: #e0e0e0;
            font-size: 14px;
            outline: none;
            transition: border-color 0.2s;
        }
        .form-group input:focus {
            border-color: #6c5ce7;
        }
        .form-row {
            display: flex;
            gap: 12px;
        }
        .form-row .form-group { flex: 1; }
        .btn {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            gap: 6px;
            padding: 10px 20px;
            border-radius: 8px;
            font-size: 14px;
            font-weight: 500;
            cursor: pointer;
            border: none;
            transition: all 0.2s;
        }
        .btn-primary {
            background: #6c5ce7;
            color: #fff;
        }
        .btn-primary:hover { background: #5a4bd1; }
        .btn-primary:disabled {
            background: #333;
            color: #666;
            cursor: not-allowed;
        }
        .btn-secondary {
            background: #222;
            color: #ccc;
        }
        .btn-secondary:hover { background: #2a2a2a; }
        .btn-success {
            background: #00b894;
            color: #fff;
        }
        .actions {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-top: 24px;
        }
        .check-list {
            list-style: none;
        }
        .check-list li {
            display: flex;
            align-items: center;
            gap: 10px;
            padding: 8px 0;
            font-size: 14px;
            border-bottom: 1px solid #1a1a1a;
        }
        .check-list li:last-child { border-bottom: none; }
        .check-icon {
            width: 20px;
            height: 20px;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 11px;
            flex-shrink: 0;
        }
        .check-icon.pass { background: #00b89433; color: #00b894; }
        .check-icon.fail { background: #e1725633; color: #e17256; }
        .check-icon.wait { background: #33333366; color: #666; }
        .status-msg {
            padding: 10px 14px;
            border-radius: 8px;
            font-size: 13px;
            margin-top: 12px;
        }
        .status-msg.success { background: #00b89420; color: #00b894; border: 1px solid #00b89433; }
        .status-msg.error { background: #e1725620; color: #e17256; border: 1px solid #e1725633; }
        .status-msg.info { background: #6c5ce720; color: #a29bfe; border: 1px solid #6c5ce733; }
        .hidden { display: none !important; }
        .spinner {
            display: inline-block;
            width: 16px;
            height: 16px;
            border: 2px solid #444;
            border-top-color: #6c5ce7;
            border-radius: 50%;
            animation: spin 0.6s linear infinite;
        }
        @keyframes spin { to { transform: rotate(360deg); } }
        .user-card {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 10px 14px;
            background: #1a1a1a;
            border-radius: 8px;
            margin-bottom: 8px;
            font-size: 14px;
        }
        .user-card .role {
            font-size: 11px;
            padding: 2px 8px;
            border-radius: 4px;
            background: #6c5ce733;
            color: #a29bfe;
        }
        .user-card .role.admin { background: #fdcb6e33; color: #fdcb6e; }
        .done-icon {
            text-align: center;
            font-size: 48px;
            margin: 16px 0;
        }
        .done-hint {
            font-size: 13px;
            color: #888;
            margin-top: 12px;
            padding: 10px 14px;
            background: #1a1a1a;
            border-radius: 8px;
        }
    </style>
</head>
<body>
<div class="wizard">
    <div class="logo">
        <img src="../logo_gullify_wh.png" alt="Gullify">
        <p>Assistant de configuration</p>
    </div>

    <div class="steps" id="stepDots"></div>

    <!-- Step 1: Requirements -->
    <div class="card step-card" id="step-1">
        <h2>Verification du systeme</h2>
        <p class="subtitle">Verification des prerequis necessaires au fonctionnement de Gullify.</p>
        <ul class="check-list" id="reqList">
            <li><span class="check-icon wait">...</span> Verification en cours...</li>
        </ul>
        <div class="actions">
            <div></div>
            <button class="btn btn-primary" id="reqNext" disabled>Suivant</button>
        </div>
    </div>

    <!-- Step 2: Database -->
    <div class="card step-card hidden" id="step-2">
        <h2>Base de donnees</h2>
        <p class="subtitle">Les parametres MySQL sont preconfigures via Docker. Verifiez la connexion.</p>
        <div class="form-row">
            <div class="form-group">
                <label>Hote</label>
                <input type="text" id="dbHost" value="db" readonly>
            </div>
            <div class="form-group" style="max-width: 100px;">
                <label>Port</label>
                <input type="text" id="dbPort" value="3306" readonly>
            </div>
        </div>
        <div class="form-group">
            <label>Base de donnees</label>
            <input type="text" id="dbName" value="gullify" readonly>
        </div>
        <div class="form-row">
            <div class="form-group">
                <label>Utilisateur</label>
                <input type="text" id="dbUser" value="gullify" readonly>
            </div>
            <div class="form-group">
                <label>Mot de passe</label>
                <input type="password" id="dbPass" value="gullify_secret" readonly>
            </div>
        </div>
        <div id="dbStatus"></div>
        <div class="actions">
            <button class="btn btn-secondary" onclick="goStep(1)">Retour</button>
            <div style="display:flex;gap:8px;">
                <button class="btn btn-secondary" id="dbTestBtn" onclick="testDatabase()">Tester</button>
                <button class="btn btn-primary" id="dbNext" disabled>Suivant</button>
            </div>
        </div>
    </div>

    <!-- Step 3: Admin account -->
    <div class="card step-card hidden" id="step-3">
        <h2>Compte administrateur</h2>
        <p class="subtitle">Creez le premier compte pour acceder a Gullify. Vous pourrez configurer le stockage depuis les parametres.</p>
        <div class="form-group">
            <label>Nom complet</label>
            <input type="text" id="adminFullName" placeholder="Maxime Dupont">
        </div>
        <div class="form-row">
            <div class="form-group">
                <label>Nom d'utilisateur</label>
                <input type="text" id="adminUser" placeholder="maxime">
            </div>
            <div class="form-group">
                <label>Mot de passe</label>
                <input type="password" id="adminPass" placeholder="Min. 6 caracteres">
            </div>
        </div>
        <div id="adminStatus"></div>
        <div id="userList"></div>
        <div class="actions">
            <button class="btn btn-secondary" onclick="goStep(2)">Retour</button>
            <div style="display:flex;gap:8px;">
                <button class="btn btn-secondary" id="createAdminBtn" onclick="createAdmin()">Creer</button>
                <button class="btn btn-primary" id="adminNext" disabled>Suivant</button>
            </div>
        </div>
    </div>

    <!-- Step 4: Done -->
    <div class="card step-card hidden" id="step-4">
        <h2>Configuration terminee !</h2>
        <p class="subtitle">Gullify est pret a utiliser.</p>
        <div class="done-icon">&#127925;</div>
        <div class="done-hint">
            Connectez-vous et rendez-vous dans <strong>Parametres</strong> pour configurer votre bibliotheque musicale (dossier local ou SFTP) et lancer le scan.
        </div>
        <div class="actions">
            <div></div>
            <button class="btn btn-success" onclick="finishSetup()">Acceder a Gullify</button>
        </div>
    </div>
</div>

<script>
const TOTAL_STEPS = 4;
let currentStep = 1;
let users = [];
let dbConnected = false;

// Init
document.addEventListener('DOMContentLoaded', () => {
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

// Step 2
async function testDatabase() {
    const btn = document.getElementById('dbTestBtn');
    btn.innerHTML = '<span class="spinner"></span>';
    btn.disabled = true;

    const r = await api('test_database', {
        host: document.getElementById('dbHost').value,
        port: document.getElementById('dbPort').value,
        database: document.getElementById('dbName').value,
        user: document.getElementById('dbUser').value,
        password: document.getElementById('dbPass').value,
    });

    btn.innerHTML = 'Tester';
    btn.disabled = false;

    if (r.success) {
        showStatus('dbStatus', r.message, 'success');
        // Auto-create tables
        const r2 = await api('create_tables', {
            host: document.getElementById('dbHost').value,
            port: document.getElementById('dbPort').value,
            database: document.getElementById('dbName').value,
            user: document.getElementById('dbUser').value,
            password: document.getElementById('dbPass').value,
        });
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
        showStatus('adminStatus', 'Nom d\'utilisateur et mot de passe requis.', 'error');
        return;
    }

    const isFirst = users.length === 0;
    const action = isFirst ? 'create_admin' : 'add_user';

    const data = { username, password, full_name: fullName };

    const r = await api(action, data);
    if (r.success) {
        users.push({ username, fullName, isAdmin: isFirst });
        renderUsers();
        showStatus('adminStatus', r.message, 'success');
        document.getElementById('adminUser').value = '';
        document.getElementById('adminPass').value = '';
        document.getElementById('adminFullName').value = '';
        document.getElementById('createAdminBtn').textContent = 'Ajouter utilisateur';
        document.getElementById('adminNext').disabled = false;
        document.getElementById('adminNext').onclick = () => goStep(4);
    } else if (r.message && r.message.includes('existe deja')) {
        // Admin already exists — allow proceeding
        showStatus('adminStatus', r.message + ' Vous pouvez continuer.', 'info');
        document.getElementById('createAdminBtn').textContent = 'Ajouter utilisateur';
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

// Step 4
async function finishSetup() {
    const r = await api('finish_setup');
    if (r.success) {
        window.location.href = '/';
    } else {
        alert('Erreur: ' + r.message);
    }
}
</script>
</body>
</html>
