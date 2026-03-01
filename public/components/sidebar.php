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
            <span>Accueil</span>
        </div>
        <div class="nav-item" data-view="artists">
            <i class="ri-mic-line"></i>
            <span>Artistes</span>
        </div>
        <div class="nav-item" data-view="albums">
            <i class="ri-album-fill"></i>
            <span>Albums</span>
        </div>
        <div class="nav-item" data-view="new-releases">
            <i class="ri-album-line"></i>
            <span>Nouveautés</span>
        </div>
        <div class="nav-item" data-view="genres">
            <i class="ri-disc-line"></i>
            <span>Genres</span>
        </div>
        <div class="nav-item" data-view="favorites">
            <i class="ri-heart-line"></i>
            <span>Favoris</span>
        </div>
        <div class="nav-item" data-view="playlists">
            <i class="ri-play-list-line"></i>
            <span>Playlists</span>
        </div>
        <div class="nav-item" data-view="statistics">
            <i class="ri-pie-chart-line"></i>
            <span>Statistiques</span>
        </div>
        <div class="nav-item" data-view="downloads">
            <i class="ri-download-cloud-line"></i>
            <span>Téléchargements</span>
        </div>
        <div class="nav-item" data-view="web-radio">
            <i class="ri-radio-line"></i>
            <span>Radio Web</span>
        </div>
        <div class="nav-item" data-view="settings" style="margin-top: 20px;">
            <i class="ri-settings-3-line"></i>
            <span>Paramètres</span>
        </div>
    </nav>
</aside>
