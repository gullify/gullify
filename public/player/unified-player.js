/**
 * Unified Music Player
 * Combines global-player and music module player into a single reusable component
 */

// Global image error handler for player images
document.addEventListener('error', function(e) {
    if (e.target.tagName === 'IMG' && !e.target.dataset.fallbackApplied) {
        e.target.dataset.fallbackApplied = 'true';
        if (e.target.src.includes('serve_image.php') ||
            e.target.closest('.player-cover, .queue-item-thumbnail, .mobile-player-cover-large')) {
            e.target.src = DEFAULT_ALBUM_IMG;
        }
    }
}, true);

class UnifiedMusicPlayer {
    constructor(options = {}) {
        console.log('UnifiedMusicPlayer: Initializing...', options);

        // Configuration
        this.isGlobal = options.isGlobal !== false;
        this.user = options.user || 'maxime';
        this.apiBaseUrl = options.apiBaseUrl ?? '/modules/music';
        this.containerSelector = options.container || (this.isGlobal ? '#unified-player-container' : '.unified-player');

        // Clean up corrupted localStorage
        this.cleanupLocalStorage();

        // Get DOM elements
        this.initDomElements();

        // State
        this.queue = [];
        this.currentTrackIndex = -1;
        this.isPlaying = false;
        this.shuffle = false;
        this.repeat = 'none'; // 'none', 'all', 'one'
        this.volume = 0.8;
        this.radioMode = false;
        this.radioUser = null;
        this.radioStarting = false;
        this.radioLoading = false;
        this.favorites = [];
        this.currentTrack = null;

        // Initialize
        this.attachEventListeners();
        this.setupPostMessageHandler();
        this.setupMediaSession();
        this.restoreState();

        console.log('UnifiedMusicPlayer: Initialized');
    }

    cleanupLocalStorage() {
        try {
            const saved = localStorage.getItem('unifiedPlayerState');
            if (saved && saved.length > 500000) {
                console.warn('UnifiedMusicPlayer: Detected corrupted localStorage, clearing...');
                localStorage.removeItem('unifiedPlayerState');
            }
        } catch (e) {
            console.warn('UnifiedMusicPlayer: Error checking localStorage, clearing...', e);
            localStorage.removeItem('unifiedPlayerState');
        }
    }

    initDomElements() {
        const container = document.querySelector(this.containerSelector) || document;

        // Main elements
        this.container = container.id ? container : document.querySelector('#unified-player-container') || document.body;
        this.audio = document.getElementById('unifiedAudioPlayer');

        // Desktop player controls
        this.playBtn = document.getElementById('unifiedPlayBtn');
        this.prevBtn = document.getElementById('unifiedPrevBtn');
        this.nextBtn = document.getElementById('unifiedNextBtn');
        this.shuffleBtn = document.getElementById('unifiedShuffleBtn');
        this.repeatBtn = document.getElementById('unifiedRepeatBtn');
        this.favoriteBtn = document.getElementById('unifiedFavoriteBtn');
        this.progressBar = document.getElementById('unifiedProgressBar');
        this.progressFill = document.getElementById('unifiedProgressFill');
        this.currentTimeEl = document.getElementById('unifiedCurrentTime');
        this.totalTimeEl = document.getElementById('unifiedTotalTime');
        this.volumeSlider = document.getElementById('unifiedVolumeSlider');
        this.muteBtn = document.getElementById('unifiedMuteBtn');
        this.queueToggle = document.getElementById('unifiedQueueToggle');
        this.queueSidebar = document.getElementById('unifiedQueueSidebar');
        this.queueList = document.getElementById('unifiedQueueList');
        this.clearQueueBtn = document.getElementById('unifiedClearQueue');
        this.desktopLyricsPanel = document.getElementById('unifiedDesktopLyrics');
        this.desktopSuggestionsPanel = document.getElementById('unifiedDesktopSuggestions');

        // Info elements
        this.playerBar = document.getElementById('unifiedPlayer');
        this.playerTitle = document.getElementById('unifiedPlayerTitle');
        this.playerArtist = document.getElementById('unifiedPlayerArtist');
        this.playerCover = document.getElementById('unifiedPlayerCover');
        this.playerSongInfo = document.getElementById('unifiedPlayerSongInfo');

        // Mobile elements
        this.mobileNowPlaying = document.getElementById('unifiedMobileNowPlaying');
        this.mobileCloseBtn = document.getElementById('unifiedMobileCloseBtn');
        this.mobilePlayerCover = document.getElementById('unifiedMobilePlayerCover');
        this.mobilePlayerTitle = document.getElementById('unifiedMobilePlayerTitle');
        this.mobilePlayerArtist = document.getElementById('unifiedMobilePlayerArtist');
        this.mobilePlayBtn = document.getElementById('unifiedMobilePlayBtn');
        this.mobilePrevBtn = document.getElementById('unifiedMobilePrevBtn');
        this.mobileNextBtn = document.getElementById('unifiedMobileNextBtn');
        this.mobileShuffleBtn = document.getElementById('unifiedMobileShuffleBtn');
        this.mobileRepeatBtn = document.getElementById('unifiedMobileRepeatBtn');
        this.mobileFavoriteBtn = document.getElementById('unifiedMobileFavoriteBtn');
        this.mobileProgressBar = document.getElementById('unifiedMobileProgressBar');
        this.mobileProgressFill = document.getElementById('unifiedMobileProgressFill');
        this.mobileCurrentTimeEl = document.getElementById('unifiedMobileCurrentTime');
        this.mobileTotalTimeEl = document.getElementById('unifiedMobileTotalTime');
        this.mobileQueueList = document.getElementById('unifiedMobileQueueList');
        this.mobileLyricsPanel = document.getElementById('unifiedMobileLyrics');
        this.mobileSuggestionsPanel = document.getElementById('unifiedMobileSuggestions');
        this.drawerTabs = document.querySelectorAll('#unifiedMobileQueueSection .drawer-tab');
        this.drawerPanels = document.querySelectorAll('#unifiedMobileQueueSection .drawer-tab-panel');

        // Toast
        this.toast = document.getElementById('unifiedPlayerToast');
    }

    attachEventListeners() {
        if (!this.audio) {
            console.error('UnifiedMusicPlayer: Audio element not found');
            return;
        }

        // Audio events
        this.audio.addEventListener('timeupdate', () => this.updateProgress());
        this.audio.addEventListener('ended', () => this.handleTrackEnded());
        this.audio.addEventListener('loadedmetadata', () => this.updateDuration());
        this.audio.addEventListener('error', (e) => this.handleAudioError(e));
        this.audio.addEventListener('play', () => this.onPlay());
        this.audio.addEventListener('pause', () => this.onPause());

        // Resume playback if the screen was locked and unlocked while we were playing
        document.addEventListener('visibilitychange', () => {
            if (!document.hidden && this.isPlaying && this.audio.paused && !this.isRadioPlaying) {
                this.audio.play().catch(() => {});
            }
        });

        // Desktop control buttons
        if (this.playBtn) this.playBtn.addEventListener('click', () => this.togglePlay());
        if (this.prevBtn) this.prevBtn.addEventListener('click', () => this.playPrevious());
        if (this.nextBtn) this.nextBtn.addEventListener('click', () => this.playNext());
        if (this.shuffleBtn) this.shuffleBtn.addEventListener('click', () => this.toggleShuffle());
        if (this.repeatBtn) this.repeatBtn.addEventListener('click', () => this.toggleRepeat());
        if (this.favoriteBtn) this.favoriteBtn.addEventListener('click', () => this.toggleFavorite());

        // Progress bar
        if (this.progressBar) {
            this.progressBar.addEventListener('click', (e) => this.seekTo(e));
        }

        // Volume
        if (this.volumeSlider) {
            this.volumeSlider.addEventListener('input', (e) => {
                this.volume = e.target.value / 100;
                this.audio.volume = this.volume;
                if (this.audio.muted) this.audio.muted = false;
                this.updateMuteButton();
                this.saveState();
            });
        }

        // Mute
        if (this.muteBtn) {
            this.muteBtn.addEventListener('click', () => this.toggleMute());
        }

        // Queue toggle
        const queueToggle = document.getElementById('unifiedQueueToggle');
        if (queueToggle) {
            queueToggle.onclick = (e) => {
                e.preventDefault();
                e.stopPropagation();
                const sidebar = document.getElementById('unifiedQueueSidebar');
                if (sidebar) {
                    sidebar.classList.toggle('open');
                }
            };
        }

        // Clear queue
        if (this.clearQueueBtn) {
            this.clearQueueBtn.addEventListener('click', () => {
                if (confirm('Vider la file d\'attente?')) {
                    this.clearQueue();
                }
            });
        }

        // Mobile player toggle - click on player bar opens mobile fullscreen
        if (this.playerBar) {
            this.playerBar.addEventListener('click', (e) => {
                // Only open mobile player if on mobile and not clicking on a control button
                if (window.innerWidth <= 768 && !e.target.closest('.player-btn') && !e.target.closest('.player-progress')) {
                    this.openMobilePlayer();
                }
            });
        }

        // Mobile player controls - close button
        if (this.mobileCloseBtn) {
            // Use a flag to prevent double-firing from touch + click
            let closeTouched = false;

            this.mobileCloseBtn.addEventListener('touchstart', (e) => {
                closeTouched = true;
            }, { passive: true });

            this.mobileCloseBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                console.log('UnifiedMusicPlayer: Close button clicked');
                this.closeMobilePlayer();
            });
        } else {
            console.warn('UnifiedMusicPlayer: mobileCloseBtn not found');
        }

        // Drawer tab switching (mobile)
        if (this.drawerTabs.length > 0) {
            this.drawerTabs.forEach(tab => {
                tab.addEventListener('click', (e) => {
                    e.stopPropagation();
                    const tabName = tab.dataset.tab;
                    this.switchDrawerTab(tabName);
                });
            });
        }

        // Desktop sidebar tab switching
        this.setupDesktopSidebarTabs();

        // Click on artist name to navigate to artist page
        if (this.mobilePlayerArtist) {
            this.mobilePlayerArtist.addEventListener('click', () => this.navigateToCurrentArtist());
        }

        if (this.mobilePlayBtn) {
            this.mobilePlayBtn.addEventListener('click', () => this.togglePlay());
        }

        if (this.mobilePrevBtn) {
            this.mobilePrevBtn.addEventListener('click', () => this.playPrevious());
        }

        if (this.mobileNextBtn) {
            this.mobileNextBtn.addEventListener('click', () => this.playNext());
        }

        if (this.mobileShuffleBtn) {
            this.mobileShuffleBtn.addEventListener('click', () => this.toggleShuffle());
        }

        if (this.mobileRepeatBtn) {
            this.mobileRepeatBtn.addEventListener('click', () => this.toggleRepeat());
        }

        if (this.mobileFavoriteBtn) {
            this.mobileFavoriteBtn.addEventListener('click', () => this.toggleFavorite());
        }

        if (this.mobileProgressBar) {
            this.mobileProgressBar.addEventListener('click', (e) => this.seekTo(e, true));
        }

        // Mobile queue swipe
        this.setupMobileQueueSwipe();
    }

    setupPostMessageHandler() {
        // Only setup postMessage handler in global mode
        if (!this.isGlobal) return;

        window.addEventListener('message', (event) => {
            if (event.data?.type === 'PLAYER_COMMAND') {
                // Send acknowledgment immediately
                if (event.source) {
                    event.source.postMessage({
                        type: 'PLAYER_COMMAND_ACK',
                        payload: { success: true }
                    }, '*');
                }

                // Execute command asynchronously
                this.handleCommand(event.data.command, event.data.payload)
                    .catch(error => {
                        console.error('UnifiedMusicPlayer: Command failed:', error);
                    });
            } else if (event.data?.type === 'PLAYER_REQUEST_STATE') {
                this.broadcastState();
            }
        });
    }

    setupMediaSession() {
        if (!('mediaSession' in navigator)) return;

        navigator.mediaSession.setActionHandler('play', () => this.togglePlay());
        navigator.mediaSession.setActionHandler('pause', () => this.togglePlay());
        navigator.mediaSession.setActionHandler('previoustrack', () => this.playPrevious());
        navigator.mediaSession.setActionHandler('nexttrack', () => this.playNext());
        navigator.mediaSession.setActionHandler('seekto', (details) => {
            if (details.seekTime !== undefined) {
                this.audio.currentTime = details.seekTime;
            }
        });
    }

    updateMediaSession(track) {
        if (!('mediaSession' in navigator) || !track) return;

        const artworkSrc = track.artworkUrl || track.artwork;
        const artworkArray = [];

        if (artworkSrc) {
            // Use normalizeImageUrl first, then convert to absolute URL
            const normalizedUrl = this.normalizeImageUrl(artworkSrc);
            const fullUrl = normalizedUrl.startsWith('http') || normalizedUrl.startsWith('data:')
                ? normalizedUrl
                : new URL(normalizedUrl, window.location.href).href;

            artworkArray.push(
                { src: fullUrl, sizes: '96x96', type: 'image/jpeg' },
                { src: fullUrl, sizes: '128x128', type: 'image/jpeg' },
                { src: fullUrl, sizes: '256x256', type: 'image/jpeg' },
                { src: fullUrl, sizes: '512x512', type: 'image/jpeg' }
            );
        }

        navigator.mediaSession.metadata = new MediaMetadata({
            title: track.title || 'Unknown',
            artist: track.artist || 'Unknown',
            album: track.album || '',
            artwork: artworkArray
        });
    }

    setupMobileQueueSwipe() {
        const queueSection = document.getElementById('unifiedMobileQueueSection');
        const queueHeader = document.getElementById('unifiedMobileQueueHeader');

        if (!queueSection || !queueHeader) {
            console.warn('UnifiedMusicPlayer: Mobile queue elements not found');
            return;
        }

        let startY = 0;
        let currentY = 0;
        let isDragging = false;
        let isExpanded = false;

        // Only the drag handle (::before pseudo-element area, top 20px) should trigger swipe/toggle
        const isOnDragHandle = (e) => {
            const target = e.target;
            // If touching a tab button, don't handle as swipe
            if (target.closest('.drawer-tab')) return false;
            // Only the top portion of the header is the drag handle
            const rect = queueHeader.getBoundingClientRect();
            const touchY = e.touches ? e.touches[0].clientY : e.clientY;
            return (touchY - rect.top) < 24;
        };

        const handleTouchStart = (e) => {
            if (e.target.closest('.drawer-tab')) return;
            startY = e.touches[0].clientY;
            currentY = startY;
            isDragging = true;
            queueSection.style.transition = 'none';
        };

        const handleTouchMove = (e) => {
            if (!isDragging) return;

            currentY = e.touches[0].clientY;
            const deltaY = currentY - startY;

            if (isExpanded) {
                if (deltaY > 0) {
                    e.preventDefault();
                    const progress = Math.min(deltaY / (window.innerHeight * 0.8), 1);
                    const translateY = progress * (window.innerHeight * 0.8 - 60);
                    queueSection.style.transform = `translateY(${translateY}px)`;
                }
            } else {
                if (deltaY < 0) {
                    e.preventDefault();
                    const progress = Math.min(Math.abs(deltaY) / (window.innerHeight * 0.8), 1);
                    const baseTranslate = window.innerHeight * 0.8 - 60;
                    const translateY = baseTranslate - (progress * baseTranslate);
                    queueSection.style.transform = `translateY(${translateY}px)`;
                }
            }
        };

        const handleTouchEnd = () => {
            if (!isDragging) return;

            const deltaY = currentY - startY;
            queueSection.style.transition = 'transform 0.3s cubic-bezier(0.4, 0, 0.2, 1)';

            if (Math.abs(deltaY) > 50) {
                if (deltaY < 0 && !isExpanded) {
                    isExpanded = true;
                    queueSection.classList.add('expanded');
                } else if (deltaY > 0 && isExpanded) {
                    isExpanded = false;
                    queueSection.classList.remove('expanded');
                }
            }
            queueSection.style.transform = '';
            isDragging = false;
        };

        queueHeader.addEventListener('touchstart', handleTouchStart, { passive: true });
        queueHeader.addEventListener('touchmove', handleTouchMove, { passive: false });
        queueHeader.addEventListener('touchend', handleTouchEnd);

        // Click on drag handle area only (not on tabs) toggles expand
        queueHeader.addEventListener('click', (e) => {
            if (e.target.closest('.drawer-tab')) return;
            isExpanded = !isExpanded;
            queueSection.classList.toggle('expanded', isExpanded);
            queueSection.style.transform = '';
        });

        // Swipe down on content area to collapse
        const tabContent = queueSection.querySelector('.drawer-tab-content');
        if (tabContent) {
            let contentStartY = 0;
            let contentDragging = false;

            tabContent.addEventListener('touchstart', (e) => {
                contentStartY = e.touches[0].clientY;
                contentDragging = true;
            }, { passive: true });

            tabContent.addEventListener('touchend', (e) => {
                if (!contentDragging) return;
                contentDragging = false;
                const activePanel = queueSection.querySelector('.drawer-tab-panel.active');
                const isAtTop = !activePanel || activePanel.scrollTop <= 0;
                const deltaY = e.changedTouches[0].clientY - contentStartY;
                if (isAtTop && deltaY > 80 && isExpanded) {
                    isExpanded = false;
                    queueSection.classList.remove('expanded');
                }
            });
        }
    }

    // Playback controls
    togglePlay() {
        // Allow toggle when playing radio even without queue
        if (this.queue.length === 0 && !this.isRadioPlaying) {
            console.log('UnifiedMusicPlayer: No tracks in queue');
            return;
        }

        if (this.isPlaying) {
            this.audio.pause();
        } else {
            const playPromise = this.audio.play();
            if (playPromise !== undefined) {
                playPromise.catch(err => {
                    if (err.name !== 'AbortError') {
                        console.error('Error playing audio:', err);
                    }
                });
            }
        }
    }



    onPlay() {
        this.isPlaying = true;
        this.updatePlayButton(true);
        if ('mediaSession' in navigator) {
            navigator.mediaSession.playbackState = 'playing';
        }
        this.saveState();
    }

    onPause() {
        this.isPlaying = false;
        this.updatePlayButton(false);
        if ('mediaSession' in navigator) {
            navigator.mediaSession.playbackState = 'paused';
        }
        this.saveState();
    }

    updatePlayButton(playing) {
        const playIcon = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="5 3 19 12 5 21 5 3"></polygon></svg>';
        const pauseIcon = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="6" y="4" width="4" height="16"></rect><rect x="14" y="4" width="4" height="16"></rect></svg>';

        const icon = playing ? pauseIcon : playIcon;

        if (this.playBtn) {
            this.playBtn.innerHTML = icon;
            this.playBtn.classList.toggle('playing', playing);
        }
        if (this.mobilePlayBtn) {
            this.mobilePlayBtn.innerHTML = icon;
            this.mobilePlayBtn.classList.toggle('playing', playing);
        }
    }

    playNext() {
        if (this.queue.length === 0) return;

        if (this.repeat === 'one') {
            this.audio.currentTime = 0;
            this.audio.play();
            return;
        }

        let nextIndex = this.currentTrackIndex + 1;

        if (this.shuffle) {
            nextIndex = Math.floor(Math.random() * this.queue.length);
        }

        if (nextIndex >= this.queue.length) {
            if (this.repeat === 'all') {
                nextIndex = 0;
            } else if (this.radioMode) {
                // In radio mode, load more songs
                this.checkAndReloadRadio().then(() => {
                    if (this.currentTrackIndex < this.queue.length - 1) {
                        this.loadTrack(this.queue[this.currentTrackIndex + 1], this.currentTrackIndex + 1);
                    }
                });
                return;
            } else {
                this.audio.pause();
                this.isPlaying = false;
                return;
            }
        }

        this.loadTrack(this.queue[nextIndex], nextIndex);
    }

    playPrevious() {
        if (this.queue.length === 0) return;

        if (this.audio.currentTime > 3) {
            this.audio.currentTime = 0;
            return;
        }

        let prevIndex = this.currentTrackIndex - 1;
        if (prevIndex < 0) {
            prevIndex = this.repeat === 'all' ? this.queue.length - 1 : 0;
        }

        this.loadTrack(this.queue[prevIndex], prevIndex);
    }

    toggleShuffle() {
        this.shuffle = !this.shuffle;
        if (this.shuffleBtn) this.shuffleBtn.classList.toggle('active', this.shuffle);
        if (this.mobileShuffleBtn) this.mobileShuffleBtn.classList.toggle('active', this.shuffle);
        this.saveState();
    }

    toggleRepeat() {
        const modes = ['none', 'all', 'one'];
        const currentIndex = modes.indexOf(this.repeat);
        this.repeat = modes[(currentIndex + 1) % modes.length];

        const isActive = this.repeat !== 'none';
        if (this.repeatBtn) this.repeatBtn.classList.toggle('active', isActive);
        if (this.mobileRepeatBtn) this.mobileRepeatBtn.classList.toggle('active', isActive);

        // Update icon for repeat one
        if (this.repeat === 'one') {
            const repeatOneIcon = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="17 1 21 5 17 9"></polyline><path d="M3 11V9a4 4 0 0 1 4-4h14"></path><polyline points="7 23 3 19 7 15"></polyline><path d="M21 13v2a4 4 0 0 1-4 4H3"></path><text x="12" y="16" text-anchor="middle" fill="currentColor" font-size="10" font-weight="bold">1</text></svg>';
            if (this.repeatBtn) this.repeatBtn.innerHTML = repeatOneIcon;
            if (this.mobileRepeatBtn) this.mobileRepeatBtn.innerHTML = repeatOneIcon;
        } else {
            const repeatIcon = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="17 1 21 5 17 9"></polyline><path d="M3 11V9a4 4 0 0 1 4-4h14"></path><polyline points="7 23 3 19 7 15"></polyline><path d="M21 13v2a4 4 0 0 1-4 4H3"></path></svg>';
            if (this.repeatBtn) this.repeatBtn.innerHTML = repeatIcon;
            if (this.mobileRepeatBtn) this.mobileRepeatBtn.innerHTML = repeatIcon;
        }

        this.saveState();
    }

    toggleMute() {
        this.audio.muted = !this.audio.muted;
        this.updateMuteButton();
    }

    updateMuteButton() {
        if (!this.muteBtn) return;
        const muted = this.audio.muted || this.audio.volume === 0;
        const iconOn  = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"></polygon><path d="M15.54 8.46a5 5 0 0 1 0 7.07"></path></svg>';
        const iconOff = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"></polygon><line x1="23" y1="9" x2="17" y2="15"></line><line x1="17" y1="9" x2="23" y2="15"></line></svg>';
        this.muteBtn.innerHTML = muted ? iconOff : iconOn;
        this.muteBtn.classList.toggle('active', muted);
    }

    async toggleFavorite() {
        const track = this.queue[this.currentTrackIndex];
        if (!track || !track.id) {
            console.log('UnifiedMusicPlayer: No track to favorite');
            return;
        }

        const isFavorite = this.favorites.includes(track.id);

        try {
            const action = isFavorite ? 'remove_favorite' : 'add_favorite';
            const baseUrl = this.apiBaseUrl.replace(/\/$/, '');

            // API expects POST request with form data
            const formData = new FormData();
            formData.append('song_id', track.id);
            formData.append('user', this.user);

            const response = await fetch(`api/library.php?action=${action}`, {
                method: 'POST',
                body: formData
            });
            const result = await response.json();

            if (!result.error) {
                if (isFavorite) {
                    this.favorites = this.favorites.filter(id => id !== track.id);
                } else {
                    this.favorites.push(track.id);
                }
                this.updateFavoriteButton();
                this.showToast(isFavorite ? 'Retiré des favoris' : 'Ajouté aux favoris', 'success');
            } else {
                console.error('UnifiedMusicPlayer: Favorite toggle failed:', result);
                this.showToast('Erreur: ' + (result.message || 'Échec'), 'error');
            }
        } catch (error) {
            console.error('UnifiedMusicPlayer: Error toggling favorite:', error);
            this.showToast('Erreur lors de la modification des favoris', 'error');
        }
    }

    updateFavoriteButton() {
        const track = this.queue[this.currentTrackIndex];
        const isFavorite = track && this.favorites.includes(track.id);

        const emptyHeart = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"></path></svg>';
        const filledHeart = '<svg viewBox="0 0 24 24" fill="currentColor" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"></path></svg>';

        // Update desktop favorite button
        if (this.favoriteBtn) {
            this.favoriteBtn.classList.toggle('active', isFavorite);
            this.favoriteBtn.innerHTML = isFavorite ? filledHeart : emptyHeart;
        }

        // Update mobile favorite button
        if (this.mobileFavoriteBtn) {
            this.mobileFavoriteBtn.classList.toggle('active', isFavorite);
            this.mobileFavoriteBtn.innerHTML = isFavorite ? filledHeart : emptyHeart;
        }
    }

    loadTrack(track, index, autoPlay = true) {
        if (!track) return;

        // Prevent rapid successive loads causing AbortError
        if (this.isLoadingTrack && autoPlay) {
            console.log('UnifiedMusicPlayer: Already loading a track, queuing this one');
            this.pendingTrack = { track, index, autoPlay };
            return;
        }

        this.isLoadingTrack = true;
        console.log('UnifiedMusicPlayer: Loading track', track, 'autoPlay:', autoPlay);

        this.currentTrackIndex = index !== undefined ? index : this.currentTrackIndex;
        this.currentTrack = track;

        // Invalidate lyrics/suggestions cache for new track
        this._lyricsLoadedFor = null;
        this._suggestionsLoadedFor = null;

        // Update UI
        if (this.playerTitle) this.playerTitle.textContent = track.title || 'Unknown';
        if (this.playerArtist) this.playerArtist.textContent = track.artist || 'Unknown';

        // Update cover - fix path for images
        const artworkSrc = track.artworkUrl || track.artwork;
        if (artworkSrc) {
            const imgSrc = this.normalizeImageUrl(artworkSrc);
            if (this.playerCover) {
                this.playerCover.innerHTML = `<img src="${imgSrc}" alt="Album" style="width: 100%; height: 100%; object-fit: cover; border-radius: 4px;">`;
            }
        } else {
            if (this.playerCover) {
                this.playerCover.innerHTML = `<img src="${DEFAULT_ALBUM_IMG}" alt="Album" style="width: 100%; height: 100%; object-fit: cover; border-radius: 4px;">`;
            }
        }

        // Load audio
        const streamUrl = `stream.php?path=${encodeURIComponent(track.filePath)}`;
        this.audio.src = streamUrl;

        // Show player bar
        if (this.playerBar) this.playerBar.classList.add('active');
        document.body.classList.add('player-visible');

        // If not auto-playing, just prepare the track without playing
        if (!autoPlay) {
            this.isLoadingTrack = false;
            this.updatePlayButton(false);
            this.renderQueue();
            this.syncMobilePlayer();
            this.updateMediaSession(track);
            this.updateFavoriteButton();
            // Show player container
            if (this.container) {
                this.container.classList.add('active');
                this.container.style.display = 'block';
            }
            return;
        }

        // Wait for audio to be ready before playing
        const playWhenReady = () => {
            this.audio.play().then(() => {
                this.isLoadingTrack = false;
                // Check if there's a pending track
                if (this.pendingTrack) {
                    const pending = this.pendingTrack;
                    this.pendingTrack = null;
                    this.loadTrack(pending.track, pending.index, pending.autoPlay);
                }
            }).catch(error => {
                this.isLoadingTrack = false;
                if (error.name !== 'AbortError' && error.name !== 'NotAllowedError') {
                    console.error('UnifiedMusicPlayer: Error playing track:', error);
                }
                // Check if there's a pending track
                if (this.pendingTrack) {
                    const pending = this.pendingTrack;
                    this.pendingTrack = null;
                    this.loadTrack(pending.track, pending.index, pending.autoPlay);
                }
            });
        };

        // Use canplay event to wait for audio to be ready
        this.audio.addEventListener('canplay', playWhenReady, { once: true });

        // Fallback timeout in case canplay doesn't fire
        setTimeout(() => {
            if (this.isLoadingTrack) {
                this.audio.removeEventListener('canplay', playWhenReady);
                playWhenReady();
            }
        }, 1000);

        // Show player container
        if (this.container) {
            this.container.classList.add('active');
            // Force visibility with inline style as fallback
            this.container.style.display = 'block';
        }

        // Update queue UI
        this.renderQueue();

        // Sync mobile player
        this.syncMobilePlayer();

        // Update Media Session
        this.updateMediaSession(track);

        // Update favorite button
        this.updateFavoriteButton();

        // Reload active drawer tab content if visible
        this.refreshActiveDrawerTab();

        // Reset desktop sidebar cache for new track
        this.resetDesktopSidebarCache();

        this.saveState();
        this.broadcastState();
    }

    // ============ WEB RADIO METHODS ============

    playRadioStream(streamUrl, stationName, logoUrl) {
        console.log('UnifiedMusicPlayer: Playing radio stream', { streamUrl, stationName });

        this.isRadioPlaying = true;
        this.radioStationName = stationName;
        this.radioStreamUrl = streamUrl;

        // Update UI for radio mode - Desktop
        if (this.playerTitle) this.playerTitle.textContent = stationName;
        if (this.playerArtist) this.playerArtist.textContent = 'Radio en direct';
        if (this.playerCover) {
            const logoSrc = logoUrl || 'assets/radio-placeholder.svg';
            this.playerCover.innerHTML = `<img src="${logoSrc}" alt="${stationName}" onerror="this.src='assets/radio-placeholder.svg'" style="width:100%;height:100%;object-fit:cover;">`;
        }

        // Mobile UI
        if (this.mobilePlayerTitle) this.mobilePlayerTitle.textContent = stationName;
        if (this.mobilePlayerArtist) this.mobilePlayerArtist.textContent = 'Radio en direct';
        if (this.mobilePlayerCover) {
            const logoSrc = logoUrl || 'assets/radio-placeholder.svg';
            this.mobilePlayerCover.innerHTML = `<img src="${logoSrc}" alt="${stationName}" onerror="this.src='assets/radio-placeholder.svg'" style="width:100%;height:100%;object-fit:cover;">`;
        }

        // Hide progress bar for live stream
        if (this.progressBar) this.progressBar.style.opacity = '0.3';
        if (this.mobileProgressBar) this.mobileProgressBar.style.opacity = '0.3';

        // Update time display
        if (this.currentTimeEl) this.currentTimeEl.textContent = 'LIVE';
        if (this.totalTimeEl) this.totalTimeEl.textContent = '';
        if (this.mobileCurrentTimeEl) this.mobileCurrentTimeEl.textContent = 'LIVE';
        if (this.mobileTotalTimeEl) this.mobileTotalTimeEl.textContent = '';

        // Show player
        if (this.container) {
            this.container.classList.add('active');
            this.container.style.display = 'block';
        }
        if (this.playerBar) {
            this.playerBar.classList.add('active');
        }

        // Open mobile player on mobile devices
        const isMobileWidth = window.innerWidth <= 768;
        const isTouchDevice = 'ontouchstart' in window || navigator.maxTouchPoints > 0;
        console.log('playRadioStream mobile check:', {
            isMobileWidth,
            isTouchDevice,
            innerWidth: window.innerWidth,
            mobileNowPlaying: !!this.mobileNowPlaying,
            playerBar: !!this.playerBar
        });

        if ((isMobileWidth || isTouchDevice) && this.mobileNowPlaying) {
            console.log('Opening mobile player for radio');
            this.openMobilePlayer();
        }

        // Add one-time error handler for radio stream
        const radioErrorHandler = (e) => {
            console.error('Radio stream error:', e);
            const errorCode = this.audio.error?.code;
            let errorMsg = 'Impossible de lire la station';

            if (errorCode === 2) {
                errorMsg = 'Erreur réseau - vérifiez votre connexion';
            } else if (errorCode === 3) {
                errorMsg = 'Format audio non supporté';
            } else if (errorCode === 4) {
                errorMsg = 'Stream non disponible';
            }

            this.showToast(errorMsg, 'error');
            this.stopRadio();
        };

        this.audio.addEventListener('error', radioErrorHandler, { once: true });

        // Set source and play - try immediately (required for user interaction context on mobile)
        this.audio.src = streamUrl;

        const playPromise = this.audio.play();
        if (playPromise !== undefined) {
            playPromise.then(() => {
                console.log('Radio stream playing successfully');
                this.updatePlayButton(true);
                this.isPlaying = true;
                // Remove error handler if successful
                this.audio.removeEventListener('error', radioErrorHandler);
            }).catch(err => {
                console.error('Error playing radio stream:', err);
                if (err.name === 'NotAllowedError') {
                    // On mobile, user needs to tap play button
                    console.log('Autoplay blocked, waiting for user interaction');
                    this.showToast('Appuyez sur play pour démarrer', 'info');
                    this.updatePlayButton(false);
                    this.isPlaying = false;
                } else if (err.name !== 'AbortError') {
                    this.showToast('Erreur de lecture radio', 'error');
                }
            });
        }

        // Update Media Session
        if ('mediaSession' in navigator) {
            navigator.mediaSession.metadata = new MediaMetadata({
                title: stationName,
                artist: 'Radio en direct',
                artwork: logoUrl ? [{ src: logoUrl, sizes: '512x512', type: 'image/png' }] : []
            });
        }
    }

    stopRadio() {
        if (!this.isRadioPlaying) return;

        console.log('UnifiedMusicPlayer: Stopping radio');

        this.audio.pause();
        this.audio.src = '';
        this.isRadioPlaying = false;
        this.isPlaying = false;
        this.radioStationName = null;
        this.radioStreamUrl = null;

        // Restore progress bar
        if (this.progressBar) this.progressBar.style.opacity = '1';
        if (this.mobileProgressBar) this.mobileProgressBar.style.opacity = '1';

        // Reset time display
        if (this.currentTimeEl) this.currentTimeEl.textContent = '0:00';
        if (this.mobileCurrentTimeEl) this.mobileCurrentTimeEl.textContent = '0:00';

        // Reset UI if no queue
        if (this.queue.length === 0) {
            if (this.container) {
                this.container.classList.remove('active');
            }
            if (this.playerBar) {
                this.playerBar.classList.remove('active');
            }
        }

        this.updatePlayButton(false);
    }

    // ============ END WEB RADIO METHODS ============

    // Progress and time
    updateProgress() {
        if (!this.audio.duration) return;

        const progress = (this.audio.currentTime / this.audio.duration) * 100;

        if (this.progressFill) this.progressFill.style.width = progress + '%';
        if (this.currentTimeEl) this.currentTimeEl.textContent = this.formatTime(this.audio.currentTime);

        // Mobile
        if (this.mobileProgressFill) this.mobileProgressFill.style.width = progress + '%';
        if (this.mobileCurrentTimeEl) this.mobileCurrentTimeEl.textContent = this.formatTime(this.audio.currentTime);

        // Update lock screen / notification progress bar
        if ('mediaSession' in navigator && this.audio.duration > 0) {
            navigator.mediaSession.setPositionState({
                duration: this.audio.duration,
                playbackRate: this.audio.playbackRate || 1,
                position: this.audio.currentTime,
            });
        }
    }

    updateDuration() {
        if (this.totalTimeEl) this.totalTimeEl.textContent = this.formatTime(this.audio.duration);
        if (this.mobileTotalTimeEl) this.mobileTotalTimeEl.textContent = this.formatTime(this.audio.duration);
    }

    seekTo(e, isMobile = false) {
        const bar = isMobile ? this.mobileProgressBar : this.progressBar;
        if (!bar) return;

        const rect = bar.getBoundingClientRect();
        const x = e.clientX - rect.left;
        const percentage = x / rect.width;
        this.audio.currentTime = percentage * this.audio.duration;
    }

    formatTime(seconds) {
        if (!seconds || isNaN(seconds)) return '0:00';
        const mins = Math.floor(seconds / 60);
        const secs = Math.floor(seconds % 60);
        return `${mins}:${secs.toString().padStart(2, '0')}`;
    }

    // Track ended handler
    async handleTrackEnded() {
        const currentTrack = this.queue[this.currentTrackIndex];
        if (currentTrack && currentTrack.id) {
            this.recordPlay(currentTrack.id, currentTrack.duration || this.audio.duration, true);
        }

        // Check if we need to reload radio songs before playing next
        if (this.radioMode && this.queue.length - this.currentTrackIndex <= 2) {
            await this.checkAndReloadRadio();
        }

        this.playNext();
    }

    handleAudioError(e) {
        console.error('UnifiedMusicPlayer: Audio error:', e);

        // Don't handle errors for radio here - radio has its own error handler
        if (this.isRadioPlaying) {
            return;
        }

        const currentTrack = this.queue[this.currentTrackIndex];

        if (currentTrack) {
            this.showToast(`Impossible de lire: ${currentTrack.title}`, 'error');

            setTimeout(() => {
                if (this.currentTrackIndex < this.queue.length - 1) {
                    this.playNext();
                }
            }, 2000);
        }

        this.updatePlayButton(false);
        this.isPlaying = false;
    }

    refreshActiveDrawerTab() {
        const activeTab = document.querySelector('#unifiedMobileQueueSection .drawer-tab.active');
        if (!activeTab) return;
        const tabName = activeTab.dataset.tab;
        if (tabName === 'lyrics') {
            this.loadLyrics();
        } else if (tabName === 'suggestions') {
            this.loadSuggestions();
        }
    }

    // Drawer tab switching
    switchDrawerTab(tabName) {
        this.drawerTabs.forEach(t => t.classList.toggle('active', t.dataset.tab === tabName));
        this.drawerPanels.forEach(p => p.classList.toggle('active', p.dataset.panel === tabName));

        if (tabName === 'lyrics' && this.currentTrack) {
            this.loadLyrics();
        } else if (tabName === 'suggestions' && this.currentTrack) {
            this.loadSuggestions();
        }
    }

    // Lyrics loading
    async loadLyrics() {
        if (!this.mobileLyricsPanel || !this.currentTrack) return;

        // Don't reload if same track
        if (this._lyricsLoadedFor === this.currentTrack.filePath) return;

        this.mobileLyricsPanel.innerHTML = `
            <div class="lyrics-loading">
                <i class="ri-loader-4-line ri-spin"></i>
                Chargement des paroles...
            </div>
        `;

        try {
            const response = await fetch(`${this.apiBaseUrl}/get_lyrics.php?path=${encodeURIComponent(this.currentTrack.filePath)}`);
            const result = await response.json();

            if (result.success && result.lyrics) {
                this._lyricsLoadedFor = this.currentTrack.filePath;
                const sourceLabel = result.source === 'musixmatch' ? '<div class="lyrics-source">via Musixmatch</div>' : '';
                this.mobileLyricsPanel.innerHTML = `<div class="lyrics-text">${this.escapeHtml(result.lyrics)}</div>${sourceLabel}`;
            } else {
                this._lyricsLoadedFor = this.currentTrack.filePath;
                this.mobileLyricsPanel.innerHTML = `
                    <div class="empty-state">
                        <div class="empty-state-icon">📝</div>
                        <p>Aucune parole disponible pour cette chanson</p>
                    </div>
                `;
            }
        } catch (error) {
            console.error('Error loading lyrics:', error);
            this.mobileLyricsPanel.innerHTML = `
                <div class="empty-state">
                    <div class="empty-state-icon">⚠️</div>
                    <p>Erreur lors du chargement des paroles</p>
                </div>
            `;
        }
    }

    // Suggestions loading
    async loadSuggestions() {
        if (!this.mobileSuggestionsPanel || !this.currentTrack) return;

        const trackKey = `${this.currentTrack.artistId || ''}_${this.currentTrack.artist || ''}`;
        if (this._suggestionsLoadedFor === trackKey) return;

        this.mobileSuggestionsPanel.innerHTML = `
            <div class="suggestions-loading">
                <i class="ri-loader-4-line ri-spin"></i>
                Chargement des suggestions...
            </div>
        `;

        try {
            const params = new URLSearchParams();
            params.set('user', this.user);
            if (this.currentTrack.filePath) {
                params.set('file_path', this.currentTrack.filePath);
            }
            if (this.currentTrack.artistId) {
                params.set('artist_id', this.currentTrack.artistId);
            }
            if (this.currentTrack.genre) {
                params.set('genre', this.currentTrack.genre);
            }

            const response = await fetch(`${this.apiBaseUrl}/get_suggestions.php?${params.toString()}`);
            const result = await response.json();

            if (!result.success || !result.data) {
                this._suggestionsLoadedFor = trackKey;
                this.mobileSuggestionsPanel.innerHTML = `
                    <div class="empty-state">
                        <div class="empty-state-icon">🎯</div>
                        <p>Aucune suggestion disponible</p>
                    </div>
                `;
                return;
            }

            this._suggestionsLoadedFor = trackKey;
            const data_result = result.data;
            this._suggestionsData = data_result.songs || [];
            let html = '';

            if (data_result.genre) {
                html += `<div style="text-align: center; padding: 6px 0 2px; font-size: 12px; color: var(--text-secondary);">Genre : ${this.escapeHtml(data_result.genre)}</div>`;
            }

            // Songs section
            if (data_result.songs && data_result.songs.length > 0) {
                html += `<div class="suggestions-section">`;
                html += `<div class="suggestions-section-title">Chansons similaires</div>`;
                data_result.songs.forEach((song, idx) => {
                    html += `
                        <div class="suggestion-item" onclick="window.gullifyPlayer.playSuggestionByIndex(${idx})">
                            <div class="suggestion-item-img"><img src="${this.escapeHtml(song.artworkUrl)}" alt="" loading="lazy"></div>
                            <div class="suggestion-item-info">
                                <div class="suggestion-item-title">${this.escapeHtml(song.title)}</div>
                                <div class="suggestion-item-sub">${this.escapeHtml(song.artist_name)}</div>
                            </div>
                            <button class="suggestion-play-btn"><i class="ri-play-fill"></i></button>
                        </div>
                    `;
                });
                html += `</div>`;
            }

            // Artists section
            if (data_result.artists && data_result.artists.length > 0) {
                html += `<div class="suggestions-section">`;
                html += `<div class="suggestions-section-title">Artistes similaires</div>`;
                data_result.artists.forEach(artist => {
                    html += `
                        <div class="suggestion-item" onclick="window.gullifyPlayer.navigateToArtist(${artist.id})">
                            <div class="suggestion-item-img round"><img src="${this.escapeHtml(artist.imageUrl)}" alt="" loading="lazy"></div>
                            <div class="suggestion-item-info">
                                <div class="suggestion-item-title">${this.escapeHtml(artist.name)}</div>
                                <div class="suggestion-item-sub">${artist.albumCount} album${artist.albumCount > 1 ? 's' : ''}</div>
                            </div>
                        </div>
                    `;
                });
                html += `</div>`;
            }

            // Albums section
            if (data_result.albums && data_result.albums.length > 0) {
                html += `<div class="suggestions-section">`;
                html += `<div class="suggestions-section-title">Albums à découvrir</div>`;
                data_result.albums.forEach(album => {
                    html += `
                        <div class="suggestion-item" onclick="window.gullifyPlayer.navigateToAlbum(${album.id})">
                            <div class="suggestion-item-img"><img src="${this.escapeHtml(album.artworkUrl)}" alt="" loading="lazy"></div>
                            <div class="suggestion-item-info">
                                <div class="suggestion-item-title">${this.escapeHtml(album.name)}</div>
                                <div class="suggestion-item-sub">${this.escapeHtml(album.artist_name)}${album.year ? ' · ' + album.year : ''}</div>
                            </div>
                        </div>
                    `;
                });
                html += `</div>`;
            }

            if (!html) {
                html = `
                    <div class="empty-state">
                        <div class="empty-state-icon">🎯</div>
                        <p>Aucune suggestion disponible</p>
                    </div>
                `;
            }

            this.mobileSuggestionsPanel.innerHTML = html;
        } catch (error) {
            console.error('Error loading suggestions:', error);
            this.mobileSuggestionsPanel.innerHTML = `
                <div class="empty-state">
                    <div class="empty-state-icon">⚠️</div>
                    <p>Erreur lors du chargement des suggestions</p>
                </div>
            `;
        }
    }

    // Desktop sidebar tabs
    setupDesktopSidebarTabs() {
        const tabs = document.querySelectorAll('#unifiedQueueSidebar .queue-sidebar-tab');
        tabs.forEach(tab => {
            tab.addEventListener('click', () => {
                const tabName = tab.dataset.tab;
                this.switchDesktopSidebarTab(tabName);
            });
        });
    }

    switchDesktopSidebarTab(tabName) {
        this._desktopSidebarTab = tabName;

        // Update tab active states
        document.querySelectorAll('#unifiedQueueSidebar .queue-sidebar-tab').forEach(t => {
            t.classList.toggle('active', t.dataset.tab === tabName);
        });

        // Update panel visibility
        document.querySelectorAll('#unifiedQueueSidebar .queue-sidebar-panel').forEach(p => {
            p.classList.toggle('active', p.dataset.panel === tabName);
        });

        // Load content if needed
        if (tabName === 'lyrics') {
            this.loadDesktopLyrics();
        } else if (tabName === 'suggestions') {
            this.loadDesktopSuggestions();
        }
    }

    async loadDesktopLyrics() {
        if (!this.desktopLyricsPanel) return;

        if (!this.currentTrack || !this.currentTrack.filePath) {
            this.desktopLyricsPanel.innerHTML = `
                <div class="empty-state">
                    <div class="empty-state-icon">📝</div>
                    <p>Lancez une chanson pour voir les paroles</p>
                </div>
            `;
            return;
        }

        // Don't reload if same track
        if (this._desktopLyricsLoadedFor === this.currentTrack.filePath) return;

        this.desktopLyricsPanel.innerHTML = `
            <div class="empty-state">
                <div class="loading-spinner"></div>
                <p>Chargement des paroles...</p>
            </div>
        `;

        try {
            const response = await fetch(`${this.apiBaseUrl}/get_lyrics.php?path=${encodeURIComponent(this.currentTrack.filePath)}`);
            const result = await response.json();

            if (result.success && result.lyrics) {
                this._desktopLyricsLoadedFor = this.currentTrack.filePath;
                const sourceLabel = result.source === 'musixmatch' ? '<div class="lyrics-source">via Musixmatch</div>' : '';
                this.desktopLyricsPanel.innerHTML = `<div class="lyrics-text">${this.escapeHtml(result.lyrics)}</div>${sourceLabel}`;
            } else {
                this._desktopLyricsLoadedFor = this.currentTrack.filePath;
                this.desktopLyricsPanel.innerHTML = `
                    <div class="empty-state">
                        <div class="empty-state-icon">📝</div>
                        <p>Aucune parole disponible</p>
                    </div>
                `;
            }
        } catch (error) {
            console.error('Error loading desktop lyrics:', error);
            this.desktopLyricsPanel.innerHTML = `
                <div class="empty-state">
                    <div class="empty-state-icon">⚠️</div>
                    <p>Erreur de chargement</p>
                </div>
            `;
        }
    }

    async loadDesktopSuggestions() {
        if (!this.desktopSuggestionsPanel) return;

        if (!this.currentTrack) {
            this.desktopSuggestionsPanel.innerHTML = `
                <div class="empty-state">
                    <div class="empty-state-icon">💡</div>
                    <p>Lancez une chanson pour voir les suggestions</p>
                </div>
            `;
            return;
        }

        const trackKey = `${this.currentTrack.artistId || ''}_${this.currentTrack.artist || ''}`;
        if (this._desktopSuggestionsLoadedFor === trackKey) return;

        this.desktopSuggestionsPanel.innerHTML = `
            <div class="empty-state">
                <div class="loading-spinner"></div>
                <p>Chargement des suggestions...</p>
            </div>
        `;

        try {
            const params = new URLSearchParams();
            params.set('user', this.user);
            if (this.currentTrack.filePath) params.set('file_path', this.currentTrack.filePath);
            if (this.currentTrack.artistId) params.set('artist_id', this.currentTrack.artistId);
            if (this.currentTrack.genre) params.set('genre', this.currentTrack.genre);

            const response = await fetch(`${this.apiBaseUrl}/get_suggestions.php?${params.toString()}`);
            const result = await response.json();

            if (!result.success || !result.data) {
                this._desktopSuggestionsLoadedFor = trackKey;
                this.desktopSuggestionsPanel.innerHTML = `
                    <div class="empty-state">
                        <div class="empty-state-icon">💡</div>
                        <p>Aucune suggestion disponible</p>
                    </div>
                `;
                return;
            }

            this._desktopSuggestionsLoadedFor = trackKey;
            const data_result = result.data;
            this._suggestionsData = data_result.songs || [];

            let html = '';

            if (data_result.songs && data_result.songs.length > 0) {
                data_result.songs.forEach((song, idx) => {
                    html += `
                        <div class="suggestion-item" onclick="window.gullifyPlayer.playSuggestionByIndex(${idx})">
                            <img class="suggestion-cover" src="${this.escapeHtml(song.artworkUrl)}" alt="">
                            <div class="suggestion-info">
                                <div class="suggestion-title">${this.escapeHtml(song.title)}</div>
                                <div class="suggestion-artist">${this.escapeHtml(song.artist_name)}</div>
                            </div>
                        </div>
                    `;
                });
            }

            if (!html) {
                html = `
                    <div class="empty-state">
                        <div class="empty-state-icon">💡</div>
                        <p>Aucune suggestion disponible</p>
                    </div>
                `;
            }

            this.desktopSuggestionsPanel.innerHTML = html;
        } catch (error) {
            console.error('Error loading desktop suggestions:', error);
            this.desktopSuggestionsPanel.innerHTML = `
                <div class="empty-state">
                    <div class="empty-state-icon">⚠️</div>
                    <p>Erreur de chargement</p>
                </div>
            `;
        }
    }

    resetDesktopSidebarCache() {
        this._desktopLyricsLoadedFor = null;
        this._desktopSuggestionsLoadedFor = null;
        // Reload current tab content if visible
        if (this._desktopSidebarTab === 'lyrics') {
            this.loadDesktopLyrics();
        } else if (this._desktopSidebarTab === 'suggestions') {
            this.loadDesktopSuggestions();
        }
    }

    playSuggestionByIndex(idx) {
        if (!this._suggestionsData || !this._suggestionsData[idx]) return;
        const song = this._suggestionsData[idx];
        const track = {
            id: song.id,
            title: song.title,
            artist: song.artist_name,
            album: song.album_name,
            filePath: song.file_path,
            artworkUrl: song.artworkUrl,
            duration: song.duration,
            albumId: song.album_id,
            artistId: song.artist_id
        };
        this.addToQueue([track]);
        this.loadTrack(track, this.queue.length - 1);
    }

    async navigateToCurrentArtist() {
        if (!this.currentTrack) return;
        if (typeof viewArtist !== 'function') return;

        // If we already have artistId, use it directly
        if (this.currentTrack.artistId) {
            this.closeMobilePlayer();
            viewArtist(this.currentTrack.artistId);
            return;
        }

        // Look up artist ID from file_path
        if (this.currentTrack.filePath) {
            try {
                const response = await fetch(`${this.apiBaseUrl}/get_suggestions.php?user=${this.user}&file_path=${encodeURIComponent(this.currentTrack.filePath)}`);
                const result = await response.json();
                if (result.success && result.data?.artist_id) {
                    this.closeMobilePlayer();
                    viewArtist(result.data.artist_id);
                }
            } catch (e) {
                console.error('Error looking up artist:', e);
            }
        }
    }

    navigateToArtist(artistId) {
        this.closeMobilePlayer();
        if (typeof viewArtist === 'function') {
            viewArtist(artistId);
        }
    }

    navigateToAlbum(albumId) {
        this.closeMobilePlayer();
        if (typeof viewAlbum === 'function') {
            viewAlbum(albumId);
        }
    }

    // Queue management
    renderQueue() {
        const emptyHtml = `
            <div class="empty-state">
                <div class="empty-state-icon">🎵</div>
                <p>Aucune chanson dans la file</p>
            </div>
        `;

        if (this.queue.length === 0) {
            if (this.queueList) this.queueList.innerHTML = emptyHtml;
            if (this.mobileQueueList) this.mobileQueueList.innerHTML = emptyHtml;
            return;
        }

        let html = '';

        if (this.radioLoading) {
            html += `<div id="queue-loading-indicator" style="padding: 10px; text-align: center; color: var(--accent, #ff0000); font-size: 12px; border-bottom: 1px solid var(--border, #e0e0e0);">Chargement de nouvelles chansons...</div>`;
        }

        this.queue.forEach((track, index) => {
            const isActive = index === this.currentTrackIndex;
            const activeClass = isActive ? 'active' : '';
            const artworkSrc = track.artworkUrl || track.artwork;
            const imgSrc = artworkSrc ? this.normalizeImageUrl(artworkSrc) : DEFAULT_ALBUM_IMG;
            const thumbnailHtml = `<div class="queue-item-thumbnail"><img src="${imgSrc}" alt="Album" style="width: 100%; height: 100%; object-fit: cover;"></div>`;

            html += `
                <div class="queue-item ${activeClass}" onclick="window.gullifyPlayer.jumpToTrack(${index})">
                    ${thumbnailHtml}
                    <div class="queue-item-info">
                        <div class="queue-item-title">${this.escapeHtml(track.title)}</div>
                        <div class="queue-item-artist">${this.escapeHtml(track.artist)}</div>
                    </div>
                    <button class="queue-item-remove" onclick="event.stopPropagation(); window.gullifyPlayer.removeFromQueue(${index});" title="Retirer">&times;</button>
                </div>
            `;
        });

        if (this.queueList) this.queueList.innerHTML = html;
        if (this.mobileQueueList) this.mobileQueueList.innerHTML = html;
    }

    jumpToTrack(index) {
        if (index >= 0 && index < this.queue.length) {
            this.loadTrack(this.queue[index], index);

            if (this.radioMode && this.queue.length - index < 5) {
                this.checkAndReloadRadio();
            }
        }
    }

    removeFromQueue(index) {
        if (index < 0 || index >= this.queue.length) return;

        this.queue.splice(index, 1);

        if (index < this.currentTrackIndex) {
            this.currentTrackIndex--;
        } else if (index === this.currentTrackIndex) {
            if (this.queue.length > 0) {
                this.currentTrackIndex = Math.min(this.currentTrackIndex, this.queue.length - 1);
                this.loadTrack(this.queue[this.currentTrackIndex], this.currentTrackIndex);
            } else {
                this.clearQueue();
            }
        }

        this.renderQueue();
        this.saveState();
        this.broadcastState();
    }

    addToQueue(tracks) {
        if (!Array.isArray(tracks)) tracks = [tracks];
        this.queue.push(...tracks);
        this.renderQueue();
        this.saveState();
        this.broadcastState();
        console.log('UnifiedMusicPlayer: Added', tracks.length, 'tracks to queue');
    }

    clearQueue() {
        this.queue = [];
        this.currentTrackIndex = -1;
        this.currentTrack = null;
        this.radioMode = false;
        this.audio.pause();
        this.audio.src = '';
        this.isPlaying = false;
        this.updatePlayButton(false);

        if (this.isGlobal && this.container) {
            this.container.classList.remove('active');
        }

        this.renderQueue();
        this.saveState();
        this.broadcastState();
    }

    escapeHtml(text) {
        if (!text) return '';
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    // Mobile player
    openMobilePlayer() {
        console.log('UnifiedMusicPlayer: Opening mobile player');

        if (this.mobileNowPlaying) {
            this.renderQueue();
            this.mobileNowPlaying.classList.add('active');
            this.mobileNowPlaying.style.display = 'flex';
            document.body.classList.add('mobile-player-open');
            document.body.style.overflow = 'hidden';
            this.syncMobilePlayer();
        }
    }

    closeMobilePlayer() {
        console.log('UnifiedMusicPlayer: Closing mobile player');
        if (this.mobileNowPlaying) {
            this.mobileNowPlaying.classList.remove('active');
            this.mobileNowPlaying.style.display = '';
            document.body.classList.remove('mobile-player-open');
            document.body.style.overflow = '';
        }
    }

    syncMobilePlayer() {
        if (this.mobilePlayerCover && this.playerCover) {
            this.mobilePlayerCover.innerHTML = this.playerCover.innerHTML;
        }

        if (this.mobilePlayerTitle && this.playerTitle) {
            this.mobilePlayerTitle.textContent = this.playerTitle.textContent;
        }

        if (this.mobilePlayerArtist && this.playerArtist) {
            this.mobilePlayerArtist.textContent = this.playerArtist.textContent;
        }

        if (this.mobilePlayBtn) {
            this.mobilePlayBtn.classList.toggle('playing', this.isPlaying);
        }

        if (this.mobileShuffleBtn) {
            this.mobileShuffleBtn.classList.toggle('active', this.shuffle);
        }

        if (this.mobileRepeatBtn) {
            this.mobileRepeatBtn.classList.toggle('active', this.repeat !== 'none');
        }

        // Sync favorite button state
        if (this.mobileFavoriteBtn && this.favoriteBtn) {
            this.mobileFavoriteBtn.classList.toggle('active', this.favoriteBtn.classList.contains('active'));
        }

        if (this.mobileQueueList && this.queueList) {
            this.mobileQueueList.innerHTML = this.queueList.innerHTML;
        }
    }

    // Command handler for postMessage
    async handleCommand(command, payload) {
        console.log('UnifiedMusicPlayer: Received command', command, payload);

        switch (command) {
            case 'PLAY_ALBUM':
                await this.playAlbum(payload.albumId, payload.user || this.user, payload.shuffle, payload.startIndex);
                break;

            case 'PLAY_ARTIST':
                await this.playArtist(payload.artistId, payload.user || this.user);
                break;

            case 'PLAY_RANDOM':
                await this.playRandom(payload.user || this.user);
                break;

            case 'PLAY_RANDOM_ARTIST':
                await this.playRandomArtist(payload.user || this.user);
                break;

            case 'START_RADIO':
                await this.startRadio(payload.user || this.user, payload.genre || null);
                break;

            case 'ADD_TO_QUEUE':
                this.addToQueue(payload.tracks);
                break;

            case 'TOGGLE_PLAY':
                this.togglePlay();
                break;

            case 'NEXT':
                this.playNext();
                break;

            case 'PREVIOUS':
                this.playPrevious();
                break;

            case 'CLEAR_QUEUE':
                this.clearQueue();
                break;

            case 'PLAY_SONGS':
                if (payload.songs && payload.songs.length > 0) {
                    this.queue = payload.songs;
                    this.currentTrackIndex = payload.startIndex || 0;
                    this.radioMode = false;
                    this.loadTrack(this.queue[this.currentTrackIndex], this.currentTrackIndex);
                }
                break;

            default:
                console.warn('UnifiedMusicPlayer: Unknown command', command);
        }
    }

    // Album/Artist/Radio playback
    async playAlbum(albumId, user, shuffle = false, startIndex = 0) {
        console.log('UnifiedMusicPlayer: Loading album', albumId);
        this.radioMode = false;

        try {
            const baseUrl = this.apiBaseUrl.replace(/\/$/, '');
            const apiUrl = this.isGlobal
                ? `api/music-proxy.php?action=album&id=${albumId}&user=${user}`
                : `api/library.php?user=${user}&action=album&id=${albumId}`;

            const response = await fetch(apiUrl);
            const result = await response.json();

            if (result.error) {
                throw new Error(result.message || 'Failed to load album');
            }

            const albumData = result.data || result;
            const songs = albumData.songs || [];

            let tracks = songs.map(song => ({
                id: song.id,
                title: song.title,
                artist: albumData.artist?.name || song.artistName || 'Unknown',
                album: albumData.name || song.albumName || 'Unknown',
                filePath: song.filePath || song.file_path,
                artworkUrl: song.artworkUrl || albumData.artwork || null,
                artwork: albumData.artwork || null,
                duration: song.duration
            }));

            if (shuffle) {
                tracks = this.shuffleArray(tracks);
            }

            this.queue = tracks;
            this.currentTrackIndex = Math.min(startIndex, tracks.length - 1);
            this.loadTrack(this.queue[this.currentTrackIndex], this.currentTrackIndex);

            console.log('UnifiedMusicPlayer: Album loaded, queue has', this.queue.length, 'tracks');
        } catch (error) {
            console.error('UnifiedMusicPlayer: Failed to load album', error);
            this.showToast('Erreur lors du chargement de l\'album', 'error');
        }
    }

    async playArtist(artistId, user) {
        console.log('UnifiedMusicPlayer: Loading artist', artistId);
        this.radioMode = false;

        try {
            const baseUrl = this.apiBaseUrl.replace(/\/$/, '');
            const apiUrl = this.isGlobal
                ? `api/music-proxy.php?action=artist&id=${artistId}&user=${user}`
                : `api/library.php?user=${user}&action=artist&id=${artistId}`;

            const response = await fetch(apiUrl);
            const result = await response.json();

            if (result.error) {
                throw new Error(result.message || 'Failed to load artist');
            }

            const albums = result.data?.albums || result.albums || [];
            const allSongs = [];

            for (const album of albums) {
                const albumApiUrl = this.isGlobal
                    ? `/api/music-proxy.php?action=album&id=${album.id}&user=${user}`
                    : `api/library.php?user=${user}&action=album&id=${album.id}`;

                const albumResponse = await fetch(albumApiUrl);
                const albumResult = await albumResponse.json();

                if (!albumResult.error) {
                    const albumData = albumResult.data || albumResult;
                    (albumData.songs || []).forEach(song => {
                        allSongs.push({
                            id: song.id,
                            title: song.title,
                            artist: albumData.artist?.name || song.artistName || 'Unknown',
                            album: albumData.name || 'Unknown',
                            filePath: song.filePath || song.file_path,
                            artworkUrl: song.artworkUrl || albumData.artwork || null,
                            artwork: albumData.artwork || null,
                            duration: song.duration
                        });
                    });
                }
            }

            if (allSongs.length === 0) {
                console.warn('UnifiedMusicPlayer: No songs found for artist');
                return;
            }

            this.queue = this.shuffleArray(allSongs);
            this.currentTrackIndex = 0;
            this.loadTrack(this.queue[0], 0);

            console.log('UnifiedMusicPlayer: Artist loaded, queue has', this.queue.length, 'tracks');
        } catch (error) {
            console.error('UnifiedMusicPlayer: Failed to load artist', error);
            this.showToast('Erreur lors du chargement de l\'artiste', 'error');
        }
    }

    async startRadio(user, genre = null) {
        console.log('UnifiedMusicPlayer: Starting Radio for user', user, genre ? `(genre: ${genre})` : '');

        if (this.radioStarting) {
            console.log('UnifiedMusicPlayer: Radio already starting');
            return;
        }

        // Allow restart if genre changed
        if (this.radioMode && this.queue.length > 0 && this.radioGenre === genre) {
            console.log('UnifiedMusicPlayer: Radio already running with same genre');
            return;
        }

        this.radioStarting = true;

        try {
            localStorage.removeItem('unifiedPlayerState');

            this.radioMode = true;
            this.radioUser = user;
            this.radioGenre = genre;
            this.queue = [];
            this.currentTrackIndex = -1;

            await this.loadMoreRadioSongs(user);

            if (this.queue.length > 0) {
                this.currentTrackIndex = 0;
                this.loadTrack(this.queue[0], 0);
                const label = genre ? `Radio ${genre}` : 'Radio';
                console.log(`UnifiedMusicPlayer: ${label} started with`, this.queue.length, 'tracks');
            }
        } catch (error) {
            console.error('UnifiedMusicPlayer: Failed to start radio', error);
            this.showToast('Erreur lors du demarrage de la radio', 'error');
        } finally {
            this.radioStarting = false;
        }
    }

    async loadMoreRadioSongs(user) {
        try {
            console.log('UnifiedMusicPlayer: Loading more radio songs...');
            this.radioLoading = true;
            this.renderQueue();

            const baseUrl = this.apiBaseUrl.replace(/\/$/, '');
            let radioUrl = `api/radio.php?action=get_random&limit=10&user=${user || this.radioUser}`;
            if (this.radioGenre) {
                radioUrl += `&genre=${encodeURIComponent(this.radioGenre)}`;
            }
            const response = await fetch(radioUrl);
            const result = await response.json();

            this.radioLoading = false;

            if (!result.success) {
                console.error('UnifiedMusicPlayer: Error loading radio songs:', result.message);
                return;
            }

            console.log(`UnifiedMusicPlayer: Loaded ${result.count} new songs for radio`);

            result.songs.forEach(song => {
                this.queue.push({
                    id: song.id,
                    title: song.title,
                    artist: song.artist,
                    album: song.album,
                    filePath: song.filePath,
                    duration: song.duration,
                    artworkUrl: song.artworkUrl || null,
                    artwork: song.artworkUrl || null
                });
            });

            this.renderQueue();
            this.broadcastState();
        } catch (error) {
            this.radioLoading = false;
            console.error('UnifiedMusicPlayer: Error loading more radio songs:', error);
        }
    }

    async checkAndReloadRadio() {
        if (this.radioMode && this.queue.length - this.currentTrackIndex < 5) {
            if (this.queue.length < 50) {
                console.log('UnifiedMusicPlayer: Queue running low, loading more...');
                await this.loadMoreRadioSongs(this.radioUser);
            } else {
                console.log('UnifiedMusicPlayer: Queue at max size, trimming...');
                if (this.currentTrackIndex > 15) {
                    this.queue.splice(0, this.currentTrackIndex - 5);
                    this.currentTrackIndex = 5;
                    this.renderQueue();
                }
                await this.loadMoreRadioSongs(this.radioUser);
            }
        }
    }

    async playRandom(user) {
        console.log('UnifiedMusicPlayer: Playing random for user', user);
        await this.startRadio(user, null);
    }

    async playRandomArtist(user) {
        console.log('UnifiedMusicPlayer: Playing random artist for user', user);
        this.radioMode = false;

        try {
            const baseUrl = this.apiBaseUrl.replace(/\/$/, '');
            const apiUrl = this.isGlobal
                ? `api/music-proxy.php?action=library&user=${user}&limit=9999`
                : `api/library.php?user=${user}&action=library&limit=9999`;

            const response = await fetch(apiUrl);
            const result = await response.json();

            if (result.error) {
                throw new Error(result.message || 'Failed to load library');
            }

            const artists = result.data?.artists || result.artists || [];
            if (artists.length === 0) {
                console.warn('UnifiedMusicPlayer: No artists found');
                return;
            }

            const randomIndex = Math.floor(Math.random() * artists.length);
            const randomArtist = artists[randomIndex];

            await this.playArtist(randomArtist.id, user);
        } catch (error) {
            console.error('UnifiedMusicPlayer: Failed to load random artist', error);
        }
    }

    // Record play stats
    async recordPlay(songId, durationPlayed, completed) {
        try {
            const formData = new FormData();
            formData.append('song_id', songId);
            formData.append('user', this.radioUser || this.user);
            formData.append('duration_played', durationPlayed);
            formData.append('completed', completed ? 1 : 0);

            await fetch(`api/radio.php?action=record_play`, {
                method: 'POST',
                body: formData
            });
        } catch (error) {
            console.error('UnifiedMusicPlayer: Error recording play:', error);
        }
    }

    // Utilities
    shuffleArray(array) {
        const shuffled = [...array];
        for (let i = shuffled.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
        }
        return shuffled;
    }

    // Normalize image URL to include proper path prefix
    normalizeImageUrl(artworkSrc) {
        if (!artworkSrc) return null;

        // Already absolute URL or data URI
        if (artworkSrc.startsWith('data:') || artworkSrc.startsWith('http://') || artworkSrc.startsWith('https://')) {
            return artworkSrc;
        }

        // Already has leading slash (absolute path from root)
        if (artworkSrc.startsWith('/')) {
            return artworkSrc;
        }

        // Remove leading ./ if present
        const cleanPath = artworkSrc.replace(/^\.\//, '');

        // Prefix with apiBaseUrl
        return `${this.apiBaseUrl}/${cleanPath}`;
    }

    // State management
    saveState() {
        if (this.radioMode) return;

        try {
            const state = {
                queue: this.queue.slice(0, 20), // Limit to prevent localStorage overflow
                currentTrackIndex: this.currentTrackIndex,
                isPlaying: this.isPlaying,
                shuffle: this.shuffle,
                repeat: this.repeat,
                volume: this.volume,
                currentTime: this.audio.currentTime,
                user: this.user
            };

            localStorage.setItem('unifiedPlayerState', JSON.stringify(state));
        } catch (error) {
            console.warn('UnifiedMusicPlayer: Failed to save state:', error.message);
        }
    }

    restoreState() {
        const saved = localStorage.getItem('unifiedPlayerState');
        if (!saved) return;

        if (saved.length > 1000000) {
            console.warn('UnifiedMusicPlayer: Saved state too large, clearing');
            localStorage.removeItem('unifiedPlayerState');
            return;
        }

        try {
            const state = JSON.parse(saved);

            if (state.radioMode) {
                console.log('UnifiedMusicPlayer: Previous session was in radio mode, not restoring');
                localStorage.removeItem('unifiedPlayerState');
                return;
            }

            this.queue = state.queue || [];
            this.currentTrackIndex = state.currentTrackIndex || -1;
            this.shuffle = state.shuffle || false;
            this.repeat = state.repeat || 'none';
            this.volume = state.volume || 0.8;
            this.user = state.user || this.user;

            // Set volume
            this.audio.volume = this.volume;
            if (this.volumeSlider) this.volumeSlider.value = this.volume * 100;

            // Update UI
            if (this.shuffleBtn) this.shuffleBtn.classList.toggle('active', this.shuffle);
            if (this.repeatBtn) this.repeatBtn.classList.toggle('active', this.repeat !== 'none');

            // Render queue
            if (this.queue.length > 0) {
                this.renderQueue();
            }

            // Restore track without auto-playing (browser autoplay restrictions)
            if (this.queue.length > 0 && this.currentTrackIndex >= 0) {
                const track = this.queue[this.currentTrackIndex];
                if (track) {
                    // Don't auto-play on restore - user must click play
                    this.loadTrack(track, this.currentTrackIndex, false);
                    if (state.currentTime) {
                        this.audio.currentTime = state.currentTime;
                    }
                }
            }

            console.log('UnifiedMusicPlayer: State restored');
        } catch (error) {
            console.error('UnifiedMusicPlayer: Failed to restore state', error);
        }
    }

    broadcastState() {
        const state = {
            queue: this.queue,
            currentTrackIndex: this.currentTrackIndex,
            isPlaying: this.isPlaying,
            shuffle: this.shuffle,
            repeat: this.repeat,
            currentTrack: this.queue[this.currentTrackIndex] || null
        };

        // Send to iframes
        const iframe = document.getElementById('content-frame');
        if (iframe && iframe.contentWindow) {
            iframe.contentWindow.postMessage({
                type: 'PLAYER_STATE_UPDATE',
                payload: state
            }, '*');
        }
    }

    // Toast notifications
    showToast(message, type = 'info', duration = 3000) {
        if (!this.toast) return;

        let icon = 'i';
        if (type === 'error') icon = '!';
        if (type === 'success') icon = '✓';

        this.toast.innerHTML = `<span>${icon}</span><span>${message}</span>`;
        this.toast.className = 'unified-player-toast show ' + type;

        setTimeout(() => {
            this.toast.classList.remove('show');
        }, duration);
    }

    // Public API for testing
    async testPlay(albumId = 9383) {
        console.log('UnifiedMusicPlayer: Testing with album ID', albumId);
        await this.playAlbum(albumId, this.user);
    }

    // Set user
    setUser(user) {
        this.user = user;
        this.saveState();
    }

    // Load favorites
    async loadFavorites() {
        try {
            const baseUrl = this.apiBaseUrl.replace(/\/$/, '');
            const response = await fetch(`api/library.php?action=get_favorites&user=${this.user}`);
            const result = await response.json();
            if (!result.error && Array.isArray(result.data)) {
                this.favorites = result.data.map(f => f.id);
            }
        } catch (error) {
            console.error('UnifiedMusicPlayer: Error loading favorites:', error);
        }
    }
}

window.UnifiedMusicPlayer = UnifiedMusicPlayer;

// Export for module usage
if (typeof module !== 'undefined' && module.exports) {
    module.exports = UnifiedMusicPlayer;
}

