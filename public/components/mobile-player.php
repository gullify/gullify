<!-- Mobile Now Playing -->
<div class="mobile-now-playing" id="mobileNowPlaying">
    <button class="mobile-close-btn" id="mobileCloseBtn"><i class="ri-arrow-down-s-line"></i></button>

    <div class="mobile-player-cover-large" id="mobilePlayerCover">
        🎵
    </div>

    <div class="mobile-player-info">
        <div class="mobile-player-title" id="mobilePlayerTitle">Aucune chanson</div>
        <div class="mobile-player-artist" id="mobilePlayerArtist">Sélectionnez une chanson</div>
    </div>

    <div class="mobile-player-controls">
        <div class="mobile-player-progress">
            <div class="mobile-progress-bar" id="mobileProgressBar">
                <div class="mobile-progress-fill" id="mobileProgressFill"></div>
            </div>
            <div class="mobile-time-display">
                <span id="mobileCurrentTime">0:00</span>
                <span id="mobileTotalTime">0:00</span>
            </div>
        </div>

        <div class="mobile-control-buttons">
            <button class="mobile-player-btn" onclick="toggleShuffle()" id="mobileShuffleBtn">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <polyline points="16 3 21 3 21 8"></polyline>
                    <line x1="4" y1="20" x2="21" y2="3"></line>
                    <polyline points="21 16 21 21 16 21"></polyline>
                    <line x1="15" y1="15" x2="21" y2="21"></line>
                    <line x1="4" y1="4" x2="9" y2="9"></line>
                </svg>
            </button>
            <button class="mobile-player-btn" onclick="playPrevious()">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <polygon points="11 19 2 12 11 5 11 19"></polygon>
                    <polygon points="22 19 13 12 22 5 22 19"></polygon>
                </svg>
            </button>
            <button class="mobile-player-btn play-btn" onclick="togglePlay()" id="mobilePlayBtn">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <polygon points="5 3 19 12 5 21 5 3"></polygon>
                </svg>
            </button>
            <button class="mobile-player-btn" onclick="playNext()">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <polygon points="13 19 22 12 13 5 13 19"></polygon>
                    <polygon points="2 19 11 12 2 5 2 19"></polygon>
                </svg>
            </button>
            <button class="mobile-player-btn" onclick="toggleRepeat()" id="mobileRepeatBtn">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <polyline points="17 1 21 5 17 9"></polyline>
                    <path d="M3 11V9a4 4 0 0 1 4-4h14"></path>
                    <polyline points="7 23 3 19 7 15"></polyline>
                    <path d="M21 13v2a4 4 0 0 1-4 4H3"></path>
                </svg>
            </button>
        </div>
    </div>

    <div class="mobile-queue-section">
        <div class="mobile-queue-header">File d'attente</div>
        <div id="mobileQueueList">
            <div class="empty-state">
                <div class="empty-state-icon">🎵</div>
                <p>Aucune chanson dans la file</p>
            </div>
        </div>
    </div>
</div>

<!-- Menu Overlay -->
<div class="menu-overlay" id="menuOverlay"></div>
