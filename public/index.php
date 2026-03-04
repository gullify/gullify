<?php
require_once __DIR__ . '/../src/AppConfig.php';

// Language detection (cookie → default fr)
$_allowedLangs = ['fr', 'en'];
$appLang = $_COOKIE['gullify_lang'] ?? 'fr';
if (!in_array($appLang, $_allowedLangs, true)) $appLang = 'fr';
$_langFile = __DIR__ . '/lang/' . $appLang . '.json';
$_langData = file_exists($_langFile) ? file_get_contents($_langFile) : '{}';

// Redirect to setup wizard if not configured
if (!AppConfig::isSetupDone()) {
    header('Location: /setup/');
    exit;
}

// Require authentication
require_once __DIR__ . '/../src/auth_required.php';
require_once __DIR__ . '/../src/PathHelper.php';

$currentUsername = $_SESSION['username'];

// Fetch current user's storage settings
try {
    $pathHelper = new PathHelper();
    $currentMusicDir = $pathHelper->getUserPath($currentUsername);
    $db = AppConfig::getDB();
    $stmt = $db->prepare("SELECT id, music_directory, storage_type, sftp_host, sftp_port, sftp_user, sftp_path FROM users WHERE username = ?");
    $stmt->execute([$currentUsername]);
    $row = $stmt->fetch();
    $currentUserId       = (int)($row['id'] ?? 0);
    $currentMusicDirName = $row['music_directory'] ?? '';
    $currentStorageType  = $row['storage_type']    ?? 'local';
    $currentSftpHost     = $row['sftp_host']        ?? '';
    $currentSftpPort     = (int)($row['sftp_port']  ?? 22);
    $currentSftpUser     = $row['sftp_user']        ?? '';
    $currentSftpPath     = $row['sftp_path']        ?? '';
} catch (Exception $e) {
    $currentUserId = 0;
    $currentMusicDirName = '';
    $currentStorageType = 'local';
    $currentSftpHost = $currentSftpUser = $currentSftpPath = '';
    $currentSftpPort = 22;
}
?>
<!DOCTYPE html>
<html lang="<?= htmlspecialchars($appLang) ?>">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Gullify - Musique</title>

    <!-- PWA & Meta -->
    <meta name="theme-color" content="#2c3e50">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
    <link rel="icon" type="image/x-icon" href="favicon.ico">
    <link rel="apple-touch-icon" href="apple-touch-icon.png">
    <link rel="manifest" href="manifest.json">

    <!-- Fonts & Icons -->
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Shadows+Into+Light&display=swap" rel="stylesheet">
    <link href="https://cdn.jsdelivr.net/npm/remixicon@3.5.0/fonts/remixicon.css" rel="stylesheet">

    <!-- Libraries -->
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/swiper@11/swiper-bundle.min.css">
    <script src="https://cdn.jsdelivr.net/npm/swiper@11/swiper-bundle.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>

    <!-- Gullify Styles -->
    <link rel="stylesheet" href="css/style.css?v=<?= time() ?>">
    <link rel="stylesheet" href="player/unified-player.css?v=<?= time() ?>">
    <link rel="stylesheet" href="context-menu.css">
    <link rel="stylesheet" href="tag-editor.css">
</head>
<body>
    <!-- Background -->
    <div class="album-background" id="albumBackground">
        <div class="album-background-image" id="albumBackgroundImage"></div>
        <div class="album-background-gradient"></div>
    </div>

    <div class="app-container">
        <?php include 'components/sidebar.php'; ?>

        <!-- Main Content -->
        <main class="main-content">
            <div class="content-header">
                <div class="header-top" id="headerTop">
                    <button class="menu-btn" id="menuBtn">☰</button>
                    <h2 id="contentTitle" data-i18n="home.title">Accueil</h2>
                    <div class="header-search-wrap" id="headerSearchWrap">
                        <input type="text" class="header-search-input" id="searchInput" placeholder="Rechercher artistes, albums, chansons..." data-i18n="common.search_placeholder" data-i18n-attr="placeholder">
                        <button class="search-icon-btn" id="searchBtn">
                            <i class="ri-search-line" id="searchBtnIcon"></i>
                        </button>
                    </div>
                </div>
            </div>

            <div class="content-body" id="contentBody">
                <div class="loading">
                    <div class="loading-spinner"></div>
                    <p>Chargement de votre bibliothèque...</p>
                </div>
            </div>
        </main>
    </div>

    <?php include 'player/unified-player.php'; ?>
    <?php include 'components/modals.php'; ?>

    <!-- Menu overlay for mobile sidebar -->
    <div class="menu-overlay" id="menuOverlay"></div>

    <!-- Context menu for song right-click -->
    <div class="context-menu" id="contextMenu">
        <div class="context-menu-item" onclick="addSongToQueueById(window._contextMenuSongId)">
            <i class="ri-add-line"></i> <span data-i18n="context_menu.add_to_queue">Ajouter à la file</span>
        </div>
        <div class="context-menu-divider"></div>
        <div class="context-menu-item" style="position:relative;">
            <i class="ri-play-list-add-line"></i> <span data-i18n="context_menu.add_to_playlist">Ajouter à une playlist</span>
            <div class="context-menu-sub-menu" id="contextMenuPlaylistSubMenu"></div>
        </div>
        <div class="context-menu-divider"></div>
        <div class="context-menu-item" onclick="showSongProperties(window._contextMenuSongId)">
            <i class="ri-file-info-line"></i> <span data-i18n="context_menu.properties">Propriétés</span>
        </div>
    </div>

    <!-- Song properties modal -->
    <div id="songPropsOverlay" style="display:none;position:fixed;inset:0;z-index:9000;background:rgba(0,0,0,0.6);backdrop-filter:blur(4px);align-items:center;justify-content:center;">
        <div id="songPropsModal" style="background:var(--bg-secondary);border:1px solid var(--border);border-radius:16px;padding:28px 32px;min-width:360px;max-width:560px;width:90%;box-shadow:0 24px 60px rgba(0,0,0,0.5);position:relative;">
            <button onclick="closeSongProperties()" style="position:absolute;top:14px;right:16px;background:none;border:none;color:var(--text-secondary);font-size:20px;cursor:pointer;line-height:1;">&times;</button>
            <h3 style="margin:0 0 20px;font-size:16px;color:var(--text-primary);display:flex;align-items:center;gap:8px;">
                <i class="ri-file-info-line" style="color:var(--accent);"></i> Propriétés
            </h3>
            <div id="songPropsContent">Chargement…</div>
        </div>
    </div>

    <!-- Artwork editor modal -->
    <div id="artworkEditorOverlay" style="display:none;position:fixed;inset:0;z-index:9000;background:rgba(0,0,0,0.65);backdrop-filter:blur(4px);align-items:center;justify-content:center;">
        <div style="background:var(--bg-secondary);border:1px solid var(--border);border-radius:16px;padding:28px 32px;width:90%;max-width:480px;box-shadow:0 24px 60px rgba(0,0,0,0.5);position:relative;">
            <button onclick="closeArtworkEditor()" style="position:absolute;top:14px;right:16px;background:none;border:none;color:var(--text-secondary);font-size:20px;cursor:pointer;line-height:1;">&times;</button>
            <h3 style="margin:0 0 20px;font-size:16px;color:var(--text-primary);display:flex;align-items:center;gap:8px;">
                <i class="ri-image-edit-line" style="color:var(--accent);"></i> <span id="artworkEditorTitle">Pochette de l'album</span>
            </h3>

            <!-- Current / preview artwork -->
            <div style="display:flex;justify-content:center;margin-bottom:20px;">
                <img id="artworkPreviewImg" src="" alt="Pochette" style="width:200px;height:200px;object-fit:cover;border-radius:12px;border:2px solid var(--border);">
            </div>

            <!-- File upload -->
            <label style="display:block;font-size:12px;color:var(--text-secondary);margin-bottom:6px;">Choisir un fichier image</label>
            <input type="file" id="artworkFileInput" accept="image/*" onchange="previewArtworkFile()" style="width:100%;margin-bottom:14px;color:var(--text-primary);">

            <!-- URL input -->
            <label style="display:block;font-size:12px;color:var(--text-secondary);margin-bottom:6px;">Ou coller une URL d'image</label>
            <input type="url" id="artworkUrlInput" placeholder="https://…" oninput="previewArtworkUrl()" style="width:100%;padding:8px 12px;border-radius:8px;border:1px solid var(--border);background:var(--bg-tertiary);color:var(--text-primary);font-size:13px;box-sizing:border-box;margin-bottom:18px;">

            <!-- YouTube Music search -->
            <div style="border-top:1px solid var(--border);padding-top:16px;margin-bottom:16px;">
                <label style="display:block;font-size:12px;color:var(--text-secondary);margin-bottom:8px;display:flex;align-items:center;gap:6px;">
                    <i class="ri-youtube-line" style="color:#ff0000;"></i> Rechercher sur YouTube Music
                </label>
                <div style="display:flex;gap:8px;margin-bottom:10px;">
                    <input type="text" id="artworkYtQuery" placeholder="Artiste + Album…" style="flex:1;padding:7px 12px;border-radius:8px;border:1px solid var(--border);background:var(--bg-tertiary);color:var(--text-primary);font-size:13px;" onkeydown="if(event.key==='Enter') searchArtworkYt()">
                    <button onclick="searchArtworkYt()" class="rescan-btn" style="font-size:12px;padding:7px 14px;flex-shrink:0;">
                        <i class="ri-search-line"></i> Chercher
                    </button>
                </div>
                <div id="artworkYtResults" style="display:grid;grid-template-columns:repeat(auto-fill,minmax(80px,1fr));gap:8px;max-height:200px;overflow-y:auto;"></div>
            </div>

            <div style="display:flex;gap:10px;justify-content:flex-end;">
                <button onclick="closeArtworkEditor()" class="rescan-btn" style="font-size:13px;padding:8px 18px;">Annuler</button>
                <button id="artworkSaveBtn" onclick="saveArtwork()" class="rescan-btn" style="font-size:13px;padding:8px 18px;background:var(--accent);color:white;">
                    <i class="ri-save-line"></i> Enregistrer
                </button>
            </div>
            <div id="artworkSaveStatus" style="margin-top:10px;font-size:12px;text-align:center;"></div>
        </div>
    </div>

    <!-- i18n: inline translations to avoid FOUC -->
    <script>window.gullifyLang = <?= $_langData ?>;</script>

    <!-- Scripts -->
    <script>
        // Global Constants
        var BASE_PATH = window.location.pathname.replace('/index.php', '').replace(/\/$/, '');
        var API_URL = BASE_PATH + '/api-mysql.php';
        var DEFAULT_ALBUM_IMG = BASE_PATH + '/logo_gullify_bo.png';

        // Gullify Player Configuration
        window.gullifyPlayerConfig = {
            user: '<?= $currentUsername ?>',
            apiBaseUrl: BASE_PATH,
            isGlobal: false,
            container: '#unifiedPlayer'
        };

        // Transmit PHP state to JS
        window.app = {
            currentUser: '<?= $currentUsername ?>',
            userId: <?= $currentUserId ?>,
            musicDir: '<?= $currentMusicDirName ?>',
            storageType: '<?= $currentStorageType ?>',
            sftpHost: '<?= $currentSftpHost ?>',
            sftpPort: <?= $currentSftpPort ?>,
            sftpUser: '<?= $currentSftpUser ?>',
            sftpPath: '<?= $currentSftpPath ?>',
            isAdmin: <?= !empty($_SESSION['is_admin']) ? 'true' : 'false' ?>,
            currentView: 'home',
            library: null,
            favorites: [],
            artistsOffset: 0,
            artistsLimit: 10000,
            loadingMore: false,
            hasMoreArtists: true,
            queue: [],
            currentTrackIndex: -1,
            isPlaying: false,
            shuffle: false,
            repeat: 'none',
            volume: 0.8,
            scrollHandler: null,
            showMobilePlayer: false,
            imageCache: {},
            recentlyPlayed: [],
            radioMode: false,
            lang: localStorage.getItem('gullify_lang') || 'fr'
        };
    </script>
    <script src="player/unified-player.js?v=<?= filemtime(__DIR__ . '/player/unified-player.js') ?>"></script>
    <script src="js/app.js?v=<?= filemtime(__DIR__ . '/js/app.js') ?>"></script>
    <script src="js/ui.js?v=<?= filemtime(__DIR__ . '/js/ui.js') ?>"></script>
</body>
</html>
