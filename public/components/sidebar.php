<aside class="sidebar" id="sidebar">
    <div class="sidebar-header">
        <span class="sidebar-app-name">Gullify</span>
    </div>

    <div class="user-selector">
        <span class="user-display"><?= htmlspecialchars(ucfirst($currentUsername)) ?></span>
    </div>

    <nav class="nav-menu">
        <div class="nav-item active" data-view="home">
            <i class="ri-home-4-line"></i>
            <span data-i18n="nav.home">Accueil</span>
        </div>
        <div class="nav-item" data-view="artists">
            <i class="ri-mic-line"></i>
            <span data-i18n="nav.artists">Artistes</span>
        </div>
        <div class="nav-item" data-view="albums">
            <i class="ri-album-fill"></i>
            <span data-i18n="nav.albums">Albums</span>
        </div>
        <div class="nav-item" data-view="new-releases">
            <i class="ri-album-line"></i>
            <span data-i18n="nav.new_releases">Nouveautés</span>
        </div>
        <div class="nav-item" data-view="genres">
            <i class="ri-disc-line"></i>
            <span data-i18n="nav.genres">Genres</span>
        </div>
        <div class="nav-item" data-view="favorites">
            <i class="ri-heart-line"></i>
            <span data-i18n="nav.favorites">Favoris</span>
        </div>
        <div class="nav-item" data-view="playlists">
            <i class="ri-play-list-line"></i>
            <span data-i18n="nav.playlists">Playlists</span>
        </div>
        <div class="nav-item" data-view="statistics">
            <i class="ri-pie-chart-line"></i>
            <span data-i18n="nav.statistics">Statistiques</span>
        </div>
        <div class="nav-item" data-view="downloads">
            <i class="ri-download-cloud-line"></i>
            <span data-i18n="nav.downloads">Téléchargements</span>
        </div>
        <div class="nav-item" data-view="web-radio">
            <i class="ri-radio-line"></i>
            <span data-i18n="nav.radio">Radio Web</span>
        </div>
        <div class="nav-item" data-view="settings" style="margin-top: 20px;">
            <i class="ri-settings-3-line"></i>
            <span data-i18n="nav.settings">Paramètres</span>
        </div>
    </nav>
</aside>
