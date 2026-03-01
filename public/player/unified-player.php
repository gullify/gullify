<!-- Unified Music Player Component -->
<!-- Combines features from global-player and music module player -->
<!-- display:contents makes the wrapper invisible but allows .unified-player CSS selectors to match children -->
<div class="unified-player" style="display:contents;">

<!-- Queue Sidebar -->
<aside class="queue-sidebar" id="unifiedQueueSidebar">
    <div class="queue-sidebar-tabs">
        <button class="queue-sidebar-tab active" data-tab="queue"><i class="ri-play-list-2-line"></i> File d'attente</button>
        <button class="queue-sidebar-tab" data-tab="lyrics"><i class="ri-music-2-line"></i> Paroles</button>
        <button class="queue-sidebar-tab" data-tab="suggestions"><i class="ri-lightbulb-line"></i> Suggestions</button>
    </div>
    <div class="queue-sidebar-panel active" id="unifiedQueuePanel" data-panel="queue">
        <div class="queue-header">
            <h3>File d'attente</h3>
            <button class="queue-clear-btn" id="unifiedClearQueue">Effacer</button>
        </div>
        <div class="queue-list" id="unifiedQueueList">
            <div class="empty-state">
                <div class="empty-state-icon">🎵</div>
                <p>Aucune chanson dans la file</p>
            </div>
        </div>
    </div>
    <div class="queue-sidebar-panel" id="unifiedLyricsPanel" data-panel="lyrics">
        <div class="queue-header">
            <h3>Paroles</h3>
        </div>
        <div class="desktop-lyrics-content" id="unifiedDesktopLyrics">
            <div class="empty-state">
                <div class="empty-state-icon">📝</div>
                <p>Lancez une chanson pour voir les paroles</p>
            </div>
        </div>
    </div>
    <div class="queue-sidebar-panel" id="unifiedSuggestionsPanel" data-panel="suggestions">
        <div class="queue-header">
            <h3>Suggestions</h3>
        </div>
        <div class="desktop-suggestions-content" id="unifiedDesktopSuggestions">
            <div class="empty-state">
                <div class="empty-state-icon">💡</div>
                <p>Lancez une chanson pour voir les suggestions</p>
            </div>
        </div>
    </div>
</aside>

<!-- Mobile Now Playing Fullscreen -->
<div class="mobile-now-playing" id="unifiedMobileNowPlaying">
    <button class="mobile-close-btn" id="unifiedMobileCloseBtn"><i class="ri-arrow-down-s-line"></i></button>

    <div class="mobile-player-cover-large" id="unifiedMobilePlayerCover">
        🎵
    </div>

    <div class="mobile-player-info">
        <div class="mobile-player-title" id="unifiedMobilePlayerTitle">Aucune chanson</div>
        <div class="mobile-player-artist mobile-player-artist-link" id="unifiedMobilePlayerArtist">Selectionnez une chanson</div>
        <button class="mobile-favorite-btn" id="unifiedMobileFavoriteBtn" title="Ajouter aux favoris">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"></path>
            </svg>
        </button>
    </div>

    <div class="mobile-player-controls">
        <div class="mobile-player-progress">
            <div class="mobile-progress-bar" id="unifiedMobileProgressBar">
                <div class="mobile-progress-fill" id="unifiedMobileProgressFill"></div>
            </div>
            <div class="mobile-time-display">
                <span id="unifiedMobileCurrentTime">0:00</span>
                <span id="unifiedMobileTotalTime">0:00</span>
            </div>
        </div>

        <div class="mobile-control-buttons">
            <button class="mobile-player-btn" id="unifiedMobileShuffleBtn">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <polyline points="16 3 21 3 21 8"></polyline>
                    <line x1="4" y1="20" x2="21" y2="3"></line>
                    <polyline points="21 16 21 21 16 21"></polyline>
                    <line x1="15" y1="15" x2="21" y2="21"></line>
                    <line x1="4" y1="4" x2="9" y2="9"></line>
                </svg>
            </button>
            <button class="mobile-player-btn" id="unifiedMobilePrevBtn">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <polygon points="11 19 2 12 11 5 11 19"></polygon>
                    <polygon points="22 19 13 12 22 5 22 19"></polygon>
                </svg>
            </button>
            <button class="mobile-player-btn play-btn" id="unifiedMobilePlayBtn">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <polygon points="5 3 19 12 5 21 5 3"></polygon>
                </svg>
            </button>
            <button class="mobile-player-btn" id="unifiedMobileNextBtn">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <polygon points="13 19 22 12 13 5 13 19"></polygon>
                    <polygon points="2 19 11 12 2 5 2 19"></polygon>
                </svg>
            </button>
            <button class="mobile-player-btn" id="unifiedMobileRepeatBtn">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <polyline points="17 1 21 5 17 9"></polyline>
                    <path d="M3 11V9a4 4 0 0 1 4-4h14"></path>
                    <polyline points="7 23 3 19 7 15"></polyline>
                    <path d="M21 13v2a4 4 0 0 1-4 4H3"></path>
                </svg>
            </button>
        </div>
    </div>

    <div class="mobile-queue-section" id="unifiedMobileQueueSection">
        <div class="mobile-queue-header" id="unifiedMobileQueueHeader">
            <div class="drawer-tabs">
                <button class="drawer-tab active" data-tab="queue"><i class="ri-play-list-line"></i> File d'attente</button>
                <button class="drawer-tab" data-tab="lyrics"><i class="ri-music-2-line"></i> Paroles</button>
                <button class="drawer-tab" data-tab="suggestions"><i class="ri-compass-discover-line"></i> Suggestions</button>
            </div>
        </div>
        <div class="drawer-tab-content">
            <div class="drawer-tab-panel active" id="drawerPanelQueue" data-panel="queue">
                <div id="unifiedMobileQueueList">
                    <div class="empty-state">
                        <div class="empty-state-icon">🎵</div>
                        <p>Aucune chanson dans la file</p>
                    </div>
                </div>
            </div>
            <div class="drawer-tab-panel" id="drawerPanelLyrics" data-panel="lyrics">
                <div id="unifiedMobileLyrics" class="lyrics-content">
                    <div class="empty-state">
                        <div class="empty-state-icon">📝</div>
                        <p>Lancez une chanson pour voir les paroles</p>
                    </div>
                </div>
            </div>
            <div class="drawer-tab-panel" id="drawerPanelSuggestions" data-panel="suggestions">
                <div id="unifiedMobileSuggestions" class="suggestions-content">
                    <div class="empty-state">
                        <div class="empty-state-icon">🎯</div>
                        <p>Lancez une chanson pour voir des suggestions</p>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>

<!-- Desktop Player Bar -->
<div class="player" id="unifiedPlayer">
    <div class="player-progress" id="unifiedProgressBar">
        <div class="player-progress-bar" id="unifiedProgressFill"></div>
    </div>

    <div class="player-song-info" id="unifiedPlayerSongInfo">
        <div class="player-album-cover" id="unifiedPlayerCover">
            🎵
        </div>
        <div class="player-details">
            <div class="player-song-title" id="unifiedPlayerTitle">Aucune chanson</div>
            <div class="player-song-artist" id="unifiedPlayerArtist">Selectionnez une chanson</div>
        </div>
    </div>

    <div class="player-controls">
        <div class="player-buttons">
            <button class="player-btn" id="unifiedShuffleBtn" title="Aleatoire">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <polyline points="16 3 21 3 21 8"></polyline>
                    <line x1="4" y1="20" x2="21" y2="3"></line>
                    <polyline points="21 16 21 21 16 21"></polyline>
                    <line x1="15" y1="15" x2="21" y2="21"></line>
                    <line x1="4" y1="4" x2="9" y2="9"></line>
                </svg>
            </button>
            <button class="player-btn" id="unifiedPrevBtn" title="Precedent">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <polygon points="11 19 2 12 11 5 11 19"></polygon>
                    <polygon points="22 19 13 12 22 5 22 19"></polygon>
                </svg>
            </button>
            <button class="player-btn play-btn" id="unifiedPlayBtn" title="Lecture">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <polygon points="5 3 19 12 5 21 5 3"></polygon>
                </svg>
            </button>
            <button class="player-btn" id="unifiedNextBtn" title="Suivant">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <polygon points="13 19 22 12 13 5 13 19"></polygon>
                    <polygon points="2 19 11 12 2 5 2 19"></polygon>
                </svg>
            </button>
            <button class="player-btn" id="unifiedRepeatBtn" title="Repeter">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <polyline points="17 1 21 5 17 9"></polyline>
                    <path d="M3 11V9a4 4 0 0 1 4-4h14"></path>
                    <polyline points="7 23 3 19 7 15"></polyline>
                    <path d="M21 13v2a4 4 0 0 1-4 4H3"></path>
                </svg>
            </button>
        </div>
        <div class="player-time">
            <span id="unifiedCurrentTime">0:00</span>
            <span>/</span>
            <span id="unifiedTotalTime">0:00</span>
        </div>
    </div>

    <div class="player-extras">
        <button class="player-btn" id="unifiedFavoriteBtn" title="Ajouter aux favoris">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"></path>
            </svg>
        </button>
        <div class="volume-control">
            <button class="player-btn mute-btn" id="unifiedMuteBtn" title="Couper le son">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"></polygon>
                    <path d="M15.54 8.46a5 5 0 0 1 0 7.07"></path>
                </svg>
            </button>
            <input type="range" class="volume-slider" id="unifiedVolumeSlider" min="0" max="100" value="80">
        </div>
        <button class="player-btn" id="unifiedQueueToggle" title="File d'attente">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <line x1="8" y1="6" x2="21" y2="6"></line>
                <line x1="8" y1="12" x2="21" y2="12"></line>
                <line x1="8" y1="18" x2="21" y2="18"></line>
                <line x1="3" y1="6" x2="3.01" y2="6"></line>
                <line x1="3" y1="12" x2="3.01" y2="12"></line>
                <line x1="3" y1="18" x2="3.01" y2="18"></line>
            </svg>
        </button>
    </div>
</div>

<!-- Audio Element -->
<audio id="unifiedAudioPlayer" preload="auto"></audio>

<!-- Toast for notifications -->
<div class="unified-player-toast" id="unifiedPlayerToast"></div>

</div><!-- /.unified-player -->
