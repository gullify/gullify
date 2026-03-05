
        function showAlbumBackground(imageUrl) {
            const albumBackground = document.getElementById('albumBackground');
            const albumBackgroundImage = document.getElementById('albumBackgroundImage');
            if (albumBackground && albumBackgroundImage && imageUrl) {
                albumBackgroundImage.style.backgroundImage = `url('${imageUrl}')`;
                albumBackground.classList.add('active');
            } else {
                if (albumBackground) albumBackground.classList.remove('active');
            }
        }

        function showArtistBackground(imageUrl) {
            showAlbumBackground(imageUrl);
        }

        function hideAlbumBackground() {
            const albumBackground = document.getElementById('albumBackground');
            if (albumBackground) albumBackground.classList.remove('active');
        }

        // Bridge function to unified player
        function loadTrack(track) {
            if (window.gullifyPlayer) {
                window.gullifyPlayer.loadTrack(track, 0, true);
            }
        }

        function renderQueue() {
            if (window.gullifyPlayer) {
                window.gullifyPlayer.renderQueue();
            }
        }


        // SVG Icons (without fixed width/height - let CSS control size)
        const ICON_PLAY = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="5 3 19 12 5 21 5 3"></polygon></svg>';
        const ICON_PAUSE = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="6" y="4" width="4" height="16"></rect><rect x="14" y="4" width="4" height="16"></rect></svg>';
        const ICON_REPEAT = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="17 1 21 5 17 9"></polyline><path d="M3 11V9a4 4 0 0 1 4-4h14"></path><polyline points="7 23 3 19 7 15"></polyline><path d="M21 13v2a4 4 0 0 1-4 4H3"></path></svg>';
        const ICON_REPEAT_ONE = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="17 1 21 5 17 9"></polyline><path d="M3 11V9a4 4 0 0 1 4-4h14"></path><polyline points="7 23 3 19 7 15"></polyline><path d="M21 13v2a4 4 0 0 1-4 4H3"></path><text x="12" y="16" text-anchor="middle" fill="currentColor" font-size="10" font-weight="bold">1</text></svg>';
        const ICON_HEART_EMPTY = '<i class="ri-heart-line"></i>';
        const ICON_HEART_FILLED = '<i class="ri-heart-fill" style="color: var(--accent);"></i>';

        // Global image error handler - fallback to default album image on 404
        document.addEventListener('error', function(e) {
            if (e.target.tagName === 'IMG' && !e.target.dataset.fallbackApplied) {
                // Mark as handled to prevent infinite loop
                e.target.dataset.fallbackApplied = 'true';
                // Check if it's a music-related image
                if (e.target.src.includes('serve_image.php') ||
                    e.target.closest('.album-cover, .album-cover-large, .artist-image, .song-thumbnail, .player-cover, .queue-item-thumbnail, .nouveaute-cover, .stat-item-image, .album-card, .artist-card')) {
                    e.target.src = DEFAULT_ALBUM_IMG;
                }
            }
        }, true);

        // Recently played management
        function saveToRecentlyPlayed(track) {
            const maxRecent = 15;
            const storageKey = `recentlyPlayed_${app.currentUser}`;

            // Get existing history
            let recent = [];
            try {
                const stored = localStorage.getItem(storageKey);
                if (stored) {
                    recent = JSON.parse(stored);
                }
            } catch (e) {
                console.error('Error loading recent history:', e);
            }

            // Remove duplicate if exists
            recent = recent.filter(t => t.id !== track.id);

            // Add to beginning
            recent.unshift({
                id: track.id,
                title: track.title,
                artist: track.artist,
                filePath: track.filePath,
                artworkUrl: track.artworkUrl,
                duration: track.duration,
                playedAt: Date.now()
            });

            // Limit to max
            recent = recent.slice(0, maxRecent);

            // Save to localStorage
            try {
                localStorage.setItem(storageKey, JSON.stringify(recent));
                app.recentlyPlayed = recent;
            } catch (e) {
                console.error('Error saving recent history:', e);
            }
        }

        function loadRecentlyPlayed() {
            const storageKey = `recentlyPlayed_${app.currentUser}`;
            try {
                const stored = localStorage.getItem(storageKey);
                if (stored) {
                    app.recentlyPlayed = JSON.parse(stored);
                }
            } catch (e) {
                console.error('Error loading recent history:', e);
                app.recentlyPlayed = [];
            }
        }

        let contextMenuSongId = null;

        function showContextMenu(event, songId) {
            event.preventDefault();
            hideContextMenu(); // Hide any existing menu
            contextMenuSongId = songId;
            window._contextMenuSongId = songId; // Expose for inline onclick handlers

            const contextMenu = document.getElementById('contextMenu');
            if (!contextMenu) return;
            contextMenu.style.display = 'block';

            const rect = event.target.getBoundingClientRect();
            const viewportHeight = window.innerHeight;
            const menuHeight = contextMenu.offsetHeight;

            let top = event.pageY;
            if (top + menuHeight > viewportHeight) {
                top = event.pageY - menuHeight;
            }

            contextMenu.style.left = `${event.pageX}px`;
            contextMenu.style.top = `${top}px`;

            // Populate playlist sub-menu
            const subMenu = document.getElementById('contextMenuPlaylistSubMenu');
            subMenu.innerHTML = `<div class="context-menu-item">${t('context_menu.loading', 'Chargement...')}</div>`;

            fetch(`${API_URL}?action=get_playlists&user=${app.currentUser}`)
                .then(res => res.json())
                .then(result => {
                    if (result.error) {
                        subMenu.innerHTML = `<div class="context-menu-item">${t('context_menu.error', 'Erreur')}</div>`;
                        return;
                    }
                    if (result.data.length === 0) {
                        subMenu.innerHTML = `<div class="context-menu-item">${t('context_menu.no_playlist', 'Aucune playlist')}</div>`;
                        return;
                    }
                    subMenu.innerHTML = result.data.map(p =>
                        `<div class="context-menu-item" onclick="addToPlaylistHandler(${p.id})">${escapeHtml(p.name)}</div>`
                    ).join('');
                });

            document.addEventListener('click', hideContextMenu, { once: true });
        }

        async function showSongProperties(songId) {
            hideContextMenu();
            if (!songId) return;
            const overlay = document.getElementById('songPropsOverlay');
            const content = document.getElementById('songPropsContent');
            overlay.style.display = 'flex';
            content.innerHTML = '<div style="color:var(--text-secondary);text-align:center;padding:20px;">Chargement…</div>';

            try {
                const res = await fetch(`${BASE_PATH}/api/library.php?action=song_properties&user=${encodeURIComponent(app.currentUser)}&song_id=${songId}`);
                const result = await res.json();
                if (result.error) { content.innerHTML = `<p style="color:#e74c3c;">${result.message}</p>`; return; }
                const p = result.data;

                const fmtSize = (bytes) => {
                    if (!bytes) return '—';
                    if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + ' Mo';
                    return (bytes / 1024).toFixed(0) + ' Ko';
                };
                const fmtDate = (ts) => {
                    if (!ts) return '—';
                    return new Date(ts * 1000).toLocaleDateString('fr-FR', { year:'numeric', month:'long', day:'numeric', hour:'2-digit', minute:'2-digit' });
                };
                const fmtDur = (sec) => {
                    if (!sec) return '—';
                    const m = Math.floor(sec / 60), s = sec % 60;
                    return `${m}:${String(s).padStart(2,'0')}`;
                };

                const row = (label, value, mono = false) => `
                    <div style="display:flex;gap:12px;padding:7px 0;border-bottom:1px solid var(--border);align-items:baseline;">
                        <span style="color:var(--text-secondary);font-size:12px;min-width:110px;flex-shrink:0;">${label}</span>
                        <span style="color:var(--text-primary);font-size:13px;word-break:break-all;${mono ? 'font-family:monospace;font-size:11px;' : ''}">${escapeHtml(String(value ?? '—'))}</span>
                    </div>`;

                content.innerHTML = `
                    ${row(t('props.title','Titre'),         p.title)}
                    ${row(t('props.artist','Artiste'),       p.artist)}
                    ${row(t('props.album','Album'),         p.album)}
                    ${row(t('props.year','Année'),         p.year || '—')}
                    ${row(t('props.track_number','Piste n°'),      p.track_number || '—')}
                    ${row(t('props.duration','Durée'),         fmtDur(p.duration))}
                    ${row(t('props.format','Format'),        p.format)}
                    ${row(t('props.file_size','Taille'),        fmtSize(p.file_size))}
                    ${row(t('props.modified','Modifié le'),    fmtDate(p.mtime))}
                    ${row(t('props.storage','Stockage'),      p.storage_type)}
                    ${row(t('props.path','Chemin'),        p.file_path, true)}
                    ${row(t('props.hash','Hash'),          p.file_hash, true)}
                `;
            } catch (e) {
                content.innerHTML = `<p style="color:#e74c3c;">${t('common.error_prefix','Erreur : ')}${e.message}</p>`;
            }
        }

        function closeSongProperties() {
            document.getElementById('songPropsOverlay').style.display = 'none';
        }

        // ── Artwork editor (album + artist) ─────────────────────────────────────

        let _artworkMode     = 'album'; // 'album' | 'artist'
        let _artworkTargetId = null;

        function _openArtworkEditorBase(targetId, mode, currentUrl, ytQuery, title) {
            _artworkMode     = mode;
            _artworkTargetId = targetId;
            document.getElementById('artworkFileInput').value = '';
            document.getElementById('artworkUrlInput').value = '';
            document.getElementById('artworkSaveStatus').textContent = '';
            document.getElementById('artworkPreviewImg').src = currentUrl;
            document.getElementById('artworkYtResults').innerHTML = '';
            document.getElementById('artworkYtQuery').value = ytQuery;
            document.getElementById('artworkSaveBtn').disabled = false;
            const titleEl = document.getElementById('artworkEditorTitle');
            if (titleEl) titleEl.textContent = title;
            document.getElementById('artworkEditorOverlay').style.display = 'flex';
        }

        function openArtworkEditor(albumId, currentUrl, artistName, albumName) {
            _openArtworkEditorBase(
                albumId, 'album', currentUrl,
                [artistName, albumName].filter(Boolean).join(' '),
                t('artwork.album_title', "Pochette de l'album")
            );
        }

        function openArtistArtworkEditor(artistId, currentUrl, artistName) {
            _openArtworkEditorBase(
                artistId, 'artist', currentUrl,
                artistName,
                t('artwork.artist_title', "Photo de l'artiste")
            );
        }

        function closeArtworkEditor() {
            document.getElementById('artworkEditorOverlay').style.display = 'none';
            _artworkTargetId = null;
        }

        function previewArtworkFile() {
            const file = document.getElementById('artworkFileInput').files[0];
            if (!file) return;
            document.getElementById('artworkUrlInput').value = '';
            const reader = new FileReader();
            reader.onload = e => { document.getElementById('artworkPreviewImg').src = e.target.result; };
            reader.readAsDataURL(file);
        }

        function previewArtworkUrl() {
            const url = document.getElementById('artworkUrlInput').value.trim();
            if (!url) return;
            document.getElementById('artworkFileInput').value = '';
            document.getElementById('artworkPreviewImg').src = url;
        }

        async function saveArtwork() {
            if (!_artworkTargetId) return;
            const fileInput = document.getElementById('artworkFileInput');
            const urlInput  = document.getElementById('artworkUrlInput');
            const statusEl  = document.getElementById('artworkSaveStatus');
            const saveBtn   = document.getElementById('artworkSaveBtn');

            const hasFile = fileInput.files.length > 0;
            const hasUrl  = urlInput.value.trim().length > 0;
            if (!hasFile && !hasUrl) {
                statusEl.style.color = '#e74c3c';
                statusEl.textContent = 'Choisir un fichier ou coller une URL.';
                return;
            }

            saveBtn.disabled = true;
            statusEl.style.color = 'var(--text-secondary)';
            statusEl.textContent = 'Enregistrement…';

            const isArtist = _artworkMode === 'artist';
            const fd = new FormData();
            if (isArtist) fd.append('artist_id', _artworkTargetId);
            else          fd.append('album_id',  _artworkTargetId);
            if (hasFile) fd.append('artwork', fileInput.files[0]);
            else         fd.append('artwork_url', urlInput.value.trim());

            try {
                const action = isArtist ? 'update_artist_image' : 'update_artwork';
                const res = await fetch(`${BASE_PATH}/tag_editor_api.php?action=${action}`, { method: 'POST', body: fd });
                const result = await res.json();
                if (!result.success) {
                    statusEl.style.color = '#e74c3c';
                    statusEl.textContent = 'Erreur : ' + (result.error || 'Inconnue');
                    saveBtn.disabled = false;
                    return;
                }

                if (isArtist) {
                    // Update artist avatar in the current artist view
                    const newUrl = `${BASE_PATH}/serve_image.php?artist_id=${_artworkTargetId}&t=${result.cache_bust}`;
                    const avatarEl = document.getElementById(`artist-avatar-${_artworkTargetId}`);
                    if (avatarEl) {
                        const img = avatarEl.querySelector('img');
                        if (img) img.src = newUrl;
                        else avatarEl.innerHTML = `<img src="${newUrl}" style="width:100%;height:100%;object-fit:cover;">` + (avatarEl.querySelector('.artwork-edit-overlay')?.outerHTML || '');
                    }
                    // Update grid card image
                    const gridEl = document.getElementById(`artist-grid-${_artworkTargetId}`);
                    if (gridEl) gridEl.innerHTML = `<img src="${newUrl}" alt="Artist" style="width:100%;height:100%;object-fit:cover;">`;
                    showArtistBackground(newUrl);
                } else {
                    // Update album cover + song thumbnails
                    const newUrl = `${BASE_PATH}/serve_image.php?album_id=${_artworkTargetId}&t=${result.cache_bust}`;
                    const coverEl = document.getElementById(`album-cover-large-${_artworkTargetId}`);
                    if (coverEl) { const img = coverEl.querySelector('img'); if (img) img.src = newUrl; }
                    document.querySelectorAll(`#song-list-${_artworkTargetId} .song-thumbnail img`).forEach(img => { img.src = newUrl; });
                }

                closeArtworkEditor();
            } catch (e) {
                statusEl.style.color = '#e74c3c';
                statusEl.textContent = 'Erreur : ' + e.message;
                saveBtn.disabled = false;
            }
        }

        async function searchArtworkYt() {
            const query     = document.getElementById('artworkYtQuery').value.trim();
            if (!query) return;
            const resultsEl = document.getElementById('artworkYtResults');
            resultsEl.innerHTML = '<div style="grid-column:1/-1;text-align:center;color:var(--text-secondary);font-size:12px;padding:10px;">Recherche…</div>';
            try {
                const isArtist = _artworkMode === 'artist';
                const action   = isArtist ? 'get_ytmusic_artist_image' : 'get_ytmusic_artist';
                const res      = await fetch(`${BASE_PATH}/tag_editor_api.php?action=${action}&artist=${encodeURIComponent(query)}`);
                const result   = await res.json();

                let items = [];
                if (isArtist) {
                    items = result.data?.artists || [];
                    if (!result.success || !items.length) {
                        resultsEl.innerHTML = '<div style="grid-column:1/-1;text-align:center;color:var(--text-secondary);font-size:12px;padding:10px;">Aucun résultat.</div>';
                        return;
                    }
                    resultsEl.innerHTML = items.map(a => {
                        if (!a.thumbnail) return '';
                        const safeUrl   = escapeHtml(a.thumbnail);
                        const safeTitle = escapeHtml(a.name || '');
                        return `<div onclick="selectArtworkYt('${safeUrl}')" title="${safeTitle}"
                            style="cursor:pointer;border-radius:8px;overflow:hidden;border:2px solid transparent;transition:border-color 0.15s;aspect-ratio:1;"
                            class="artwork-yt-thumb">
                            <img src="${safeUrl}" style="width:100%;height:100%;object-fit:cover;" loading="lazy">
                        </div>`;
                    }).join('');
                } else {
                    items = result.data?.albums || [];
                    if (!result.success || !items.length) {
                        resultsEl.innerHTML = '<div style="grid-column:1/-1;text-align:center;color:var(--text-secondary);font-size:12px;padding:10px;">Aucun résultat.</div>';
                        return;
                    }
                    resultsEl.innerHTML = items.map(album => {
                        if (!album.thumbnail) return '';
                        const safeUrl   = escapeHtml(album.thumbnail);
                        const safeTitle = escapeHtml((album.artist || '') + ' — ' + (album.title || ''));
                        return `<div onclick="selectArtworkYt('${safeUrl}')" title="${safeTitle}"
                            style="cursor:pointer;border-radius:8px;overflow:hidden;border:2px solid transparent;transition:border-color 0.15s;aspect-ratio:1;"
                            class="artwork-yt-thumb">
                            <img src="${safeUrl}" style="width:100%;height:100%;object-fit:cover;" loading="lazy">
                        </div>`;
                    }).join('');
                }
            } catch (e) {
                resultsEl.innerHTML = `<div style="grid-column:1/-1;text-align:center;color:#e74c3c;font-size:12px;padding:10px;">Erreur : ${e.message}</div>`;
            }
        }

        function selectArtworkYt(url) {
            document.getElementById('artworkUrlInput').value = url;
            document.getElementById('artworkPreviewImg').src = url;
            document.getElementById('artworkFileInput').value = '';
            // Highlight selected thumb
            document.querySelectorAll('.artwork-yt-thumb').forEach(el => {
                el.style.borderColor = el.querySelector('img')?.src === url ? 'var(--accent)' : 'transparent';
            });
        }

        function hideContextMenu() {
            const contextMenu = document.getElementById('contextMenu');
            if (contextMenu) {
                contextMenu.style.display = 'none';
            }
            document.removeEventListener('click', hideContextMenu);
            contextMenuSongId = null;
        }

        async function addToPlaylistHandler(playlistId) {
            if (!contextMenuSongId) return;

            const formData = new FormData();
            formData.append('user', app.currentUser);
            formData.append('playlist_id', playlistId);
            formData.append('song_id', contextMenuSongId);

            try {
                const response = await fetch(`${API_URL}?action=add_to_playlist`, { method: 'POST', body: formData });
                const result = await response.json();
                if (result.error) throw new Error(result.error);
                showToast(t('toast.song_added_playlist', 'Chanson ajoutée à la playlist!'), 'success');
            } catch (error) {
                showToast(`${t('common.error','Erreur')}: ${error.message}`, 'error');
            }
            hideContextMenu();
        }

        // Éléments DOM
        const navItems = document.querySelectorAll('.nav-item');
        const contentTitle = document.getElementById('contentTitle');
        const contentBody = document.getElementById('contentBody');
        const searchInput = document.getElementById('searchInput');

        // Initialisation
        function init() {
            // Apply i18n to static DOM elements (sidebar, player tooltips)
            if (window.applyI18n) applyI18n();

            // Instantiate unified player
            if (window.UnifiedMusicPlayer && window.gullifyPlayerConfig) {
                window.gullifyPlayer = new UnifiedMusicPlayer(window.gullifyPlayerConfig);
            }

            loadTheme();
            loadUserPreference();
            loadRecentlyPlayed();
            loadGenreTaxonomy();
            setupEventListeners();
            loadInitialData();
        }

        // Gestion du thème
        function loadTheme() {
            initThemeSync();
        }

        function setTheme(theme) {
            document.documentElement.setAttribute('data-theme', theme);
            const themeIcon = document.getElementById('themeIcon');
            const themeText = document.getElementById('themeText');

            if (themeIcon && themeText) {
                if (theme === 'dark') {
                    themeIcon.className = 'ri-sun-line';
                    themeText.textContent = t('settings.light_mode', 'Mode Clair');
                } else {
                    themeIcon.className = 'ri-moon-line';
                    themeText.textContent = t('settings.dark_mode', 'Mode Sombre');
                }
            }

            localStorage.setItem('musicTheme', theme);
        }

        // Detect if in iframe and sync dark mode with parent
        function initThemeSync() {
            const isInIframe = window.self !== window.top;

            if (isInIframe) {
                document.body.classList.add('in-iframe');

                try {
                    // Try to get dark mode state from parent window
                    if (window.parent && window.parent !== window) {
                        const parentDarkMode = window.parent.localStorage.getItem('darkMode');
                        if (parentDarkMode === 'enabled') {
                            setTheme('dark');
                        } else {
                            setTheme('light');
                        }
                    }
                } catch (e) {
                    // Cross-origin restrictions, fall back to own localStorage
                    const savedTheme = localStorage.getItem('musicTheme') || 'light';
                    setTheme(savedTheme);
                }

                // Listen for dark mode changes from parent
                window.addEventListener('message', function(event) {
                    if (event.data && event.data.type === 'darkModeChange') {
                        setTheme(event.data.enabled ? 'dark' : 'light');
                    }
                });
            } else {
                // Not in iframe, use own theme preference
                const savedTheme = localStorage.getItem('musicTheme') || 'light';
                setTheme(savedTheme);
            }
        }

        function toggleTheme() {
            const currentTheme = document.documentElement.getAttribute('data-theme');
            setTheme(currentTheme === 'dark' ? 'light' : 'dark');
        }

        // Gestion utilisateur (set by server-side session)
        function loadUserPreference() {
            // User is determined by login session
        }

        async function loadInitialData() {
            try {
                showLoading();

                const [statsResponse, favsResponse] = await Promise.all([
                    fetch(`${BASE_PATH}/api/library.php?action=get_stats&user=${app.currentUser}`),
                    fetch(`${BASE_PATH}/api/library.php?action=get_favorites&user=${app.currentUser}`)
                ]);

                const statsResult = await statsResponse.json();
                if (statsResult.error) {
                    showError(t('errors.load_stats', 'Erreur lors du chargement des statistiques.'));
                    return;
                }

                const favsResult = await favsResponse.json();
                if (!favsResult.error && favsResult.data) {
                    app.favorites = favsResult.data.map(song => song.id);
                }

                app.library = {
                    artists: null, // Artists will be loaded on demand
                    totalSongs: statsResult.data.totalSongs,
                    totalArtists: statsResult.data.totalArtists
                };

                // Restore saved view state or show home
                const savedView = localStorage.getItem('musicCurrentView');
                const savedAlbumId = localStorage.getItem('musicCurrentAlbumId');
                const savedArtistId = localStorage.getItem('musicCurrentArtistId');

                if (savedView === 'album' && savedAlbumId) {
                    viewAlbum(parseInt(savedAlbumId));
                } else if (savedView === 'artist' && savedArtistId) {
                    renderView('artists', () => viewArtist(parseInt(savedArtistId)));
                } else if (savedView && ['home', 'artists', 'albums', 'songs', 'favorites'].includes(savedView)) {
                    renderView(savedView);
                } else {
                    renderView('home');
                }

            } catch (error) {
                console.error('Error loading initial data:', error);
                showError(t('errors.load_data_fail', 'Impossible de charger les données initiales.'));
            }
        }

        // Chargement de la bibliothèque
        async function loadLibrary(reset = true, callback = null) {
            try {
                if (reset) {
                    showLoading();
                    app.artistsOffset = 0;
                    if (app.library) {
                        app.library.artists = null;
                    }
                }

                const response = await fetch(`${BASE_PATH}/api/library.php?user=${app.currentUser}&action=library&limit=${app.artistsLimit}&offset=${app.artistsOffset}`);
                const result = await response.json();
				console.log("CONTENU BIBLIOTHÈQUE :", result.data);

                if (result.error) {
                    showError(t('errors.load_library', 'Erreur lors du chargement de la bibliothèque'), 'loadLibrary()');
                    return;
                }

                if (reset || !app.library || !app.library.artists) {
                    app.library = app.library || {}; // Ensure library object exists
                    app.library.artists = result.data.artists;
                    app.library.totalSongs = result.data.totalSongs;
                    app.library.totalArtists = result.data.totalArtists;
                } else {
                    // Append new artists
                    app.library.artists.push(...result.data.artists);
                }

                app.hasMoreArtists = result.data.has_more;
                app.artistsOffset += app.artistsLimit;

                if (callback) {
                    callback();
                } else {
                    renderView(app.currentView);
                }

            } catch (error) {
                console.error('Error loading library:', error);
                showError(t('errors.load_library_fail', 'Impossible de charger la bibliothèque'), 'loadLibrary()');
            }
        }

        // Charger plus d'artistes
        async function loadMoreArtists() {
            if (app.loadingMore || !app.hasMoreArtists) return;

            app.loadingMore = true;
            await loadLibrary(false);
            app.loadingMore = false;
        }

        // Affichage des vues
        function renderView(view, callback = null) {
            console.log('Changing view to:', view);

            // Remove infinite scroll before changing view
            if (view !== 'artists') {
                removeInfiniteScroll();
            }

            // Close settings accordion when navigating away
            if (view !== 'settings') {
                document.getElementById('settingsSubmenu')?.classList.remove('open');
                document.querySelector('[data-view="settings"]')?.classList.remove('open');
            }

            app.currentView = view;

            // Save current view to localStorage
            localStorage.setItem('musicCurrentView', view);

            // Update nav active state
            navItems.forEach(item => {
                item.classList.toggle('active', item.dataset.view === view);
            });

            if (callback) {
                callback();
                return;
            }

            switch (view) {
                case 'home':
                    renderHome();
                    break;
                case 'artists':
                    if (!app.library || !app.library.artists) {
                        loadLibrary(true, () => renderArtists());
                    } else {
                        renderArtists();
                    }
                    break;
                case 'albums':
                    renderAlbums();
                    break;
                case 'songs':
                    renderSongs();
                    break;
                case 'favorites':
                    renderFavorites();
                    break;
                case 'new-releases':
                    renderNewReleases();
                    break;
                case 'genres':
                    renderGenres();
                    break;
                case 'playlists':
                    renderPlaylists();
                    break;
                case 'statistics':
                    renderStatistics();
                    break;
                case 'downloads':
                    renderDownloads();
                    break;
                case 'web-radio':
                    renderWebRadio();
                    break;
                case 'settings':
                    renderSettings();
                    break;
            }
        }

        async function renderNewReleases() {
            hideAlbumBackground();
            showLoading();
            contentTitle.textContent = t('nav.new_releases', 'Nouveautés');

            try {
                // Fetch albums from last 30 days
                const response = await fetch(`${BASE_PATH}/api/library.php?action=recent_albums&user=${app.currentUser}&days=30`);
                const result = await response.json();

                if (result.error) {
                    showError(t('errors.load_new_releases', 'Erreur lors du chargement des nouveautés.'));
                    return;
                }

                const albums = result.data || [];
                window.recentAlbumsData = albums;

                if (albums.length === 0) {
                    showEmpty(t('empty.no_releases', 'Aucune nouveauté ce mois-ci'));
                    return;
                }

                const html = `
                    <div style="margin-bottom: 16px; display: flex; justify-content: space-between; align-items: center;">
                        <p style="color: var(--text-secondary); margin: 0;">${t('new_releases.count', '{n} albums ajoutés ces 30 derniers jours').replace('{n}', albums.length)}</p>
                        <button onclick="playRecentAlbums()" class="nouveautes-play-btn">
                            <i class="ri-play-fill"></i> ${t('new_releases.play_all', 'Tout écouter')}
                        </button>
                    </div>
                    <div class="album-grid" style="grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));">
                        ${albums.map(album => {
                            const imgSrc = album.artworkUrl || DEFAULT_ALBUM_IMG;
                            return `
                                <div class="artist-card" onclick="viewAlbum(${album.id})" style="cursor: pointer;">
                                    <div class="artist-image" style="border-radius: 8px; overflow: hidden;">
                                        <img src="${imgSrc}" alt="${escapeHtml(album.name)}" style="width: 100%; height: 100%; object-fit: cover;">
                                    </div>
                                    <div class="artist-name" style="font-size: 13px; margin-top: 8px;">${escapeHtml(album.name)}</div>
                                    <div class="artist-info" style="font-size: 11px;">${escapeHtml(album.artistName)}${album.year ? ' • ' + album.year : ''}</div>
                                </div>
                            `;
                        }).join('')}
                    </div>
                `;
                contentBody.innerHTML = html;

            } catch (error) {
                console.error('Error loading new releases:', error);
                showError(t('errors.load_new_releases', 'Erreur lors du chargement des nouveautés.'));
            }
        }

        async function renderGenres(selectedGenre = null) {
            hideAlbumBackground();
            showLoading();

            try {
                if (selectedGenre) {
                    // Show artists for selected genre
                    contentTitle.textContent = t('genres.genre_title', 'Genre : {name}').replace('{name}', selectedGenre);

                    const response = await fetch(`${BASE_PATH}/api/library.php?user=${app.currentUser}&action=get_artists_by_genre&genre=${encodeURIComponent(selectedGenre)}`);
                    const result = await response.json();

                    if (result.error) {
                        showError(t('errors.load_artists', 'Erreur lors du chargement des artistes.'));
                        return;
                    }

                    const artists = result.data.artists;

                    if (artists.length === 0) {
                        showEmpty(t('empty.no_genre_artists', 'Aucun artiste dans ce genre'));
                        return;
                    }

                    const html = `
                        <div style="margin-bottom: 15px; display:flex; align-items:center; gap:10px; flex-wrap:wrap;">
                            <button onclick="renderGenres()" style="padding: 8px 16px; background: var(--hover-bg); border: none; border-radius: 8px; color: var(--text-primary); cursor: pointer; font-size: 14px;">
                                ${t('genres.back', '← Retour aux genres')}
                            </button>
                            <button onclick="startGenreRadio('${escapeHtml(selectedGenre).replace(/'/g, "\\'")}')" class="rescan-btn" style="font-size:13px;">
                                <i class="ri-radio-line"></i> Radio ${escapeHtml(selectedGenre)}
                            </button>
                        </div>
                        <div class="artist-grid">
                            ${artists.map(artist => {
                                let imageHtml = '👤';
                                if (artist.imageUrl) {
                                    imageHtml = '<img src="' + artist.imageUrl + '" alt="' + escapeHtml(artist.name) + '" style="width: 100%; height: 100%; object-fit: cover;">';
                                }
                                return `
                                    <div class="artist-card" onclick="viewArtist(${artist.id})">
                                        <div class="artist-image" style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); display: flex; align-items: center; justify-content: center; font-size: 48px;">
                                            ${imageHtml}
                                        </div>
                                        <div class="artist-name">${escapeHtml(artist.name)}</div>
                                        <div class="artist-info">${t('counts.albums_songs','{a} albums • {s} chansons').replace('{a}', artist.albumCount).replace('{s}', artist.songCount)}</div>
                                    </div>
                                `;
                            }).join('')}
                        </div>
                    `;
                    contentBody.innerHTML = html;
                } else {
                    // Show all genres
                    contentTitle.textContent = t('nav.genres', 'Genres');

                    const response = await fetch(`${BASE_PATH}/api/library.php?user=${app.currentUser}&action=get_genres`);
                    const result = await response.json();

                    if (result.error) {
                        showError(t('errors.load_genres', 'Erreur lors du chargement des genres.'));
                        return;
                    }

                    const genres = result.data.genres;

                    if (genres.length === 0) {
                        showEmpty(t('empty.no_genres', "Aucun genre trouvé. Assignez des genres à vos albums via l'éditeur de tags."));
                        return;
                    }

                    const genreHues = [
                        0, 25, 45, 70, 120, 160, 195, 220, 255, 280, 310, 340,
                        15, 55, 90, 140, 175, 205, 240, 270, 295, 325
                    ];

                    const html = `
                        <div style="margin-bottom: 12px; display:flex; align-items:center; gap:10px;">
                            <button onclick="toggleGenreManager()" class="rescan-btn" style="font-size:13px;padding:6px 14px;">
                                <i class="ri-settings-3-line"></i> ${t('genres.manage_btn', 'Gérer les genres')}
                            </button>
                        </div>
                        <div id="genre-manager-container" style="display:none;"></div>
                        <div id="genre-grid-container">
                            <div class="genre-grid">
                                ${genres.map((genre, idx) => {
                                    const hue = genreHues[idx % genreHues.length];
                                    return `
                                    <div class="genre-card genre-card-colored" style="--genre-hue:${hue};" onclick="renderGenres('${escapeHtml(genre.name).replace(/'/g, "\\'")}')">
                                        <div class="genre-icon"><i class="ri-disc-fill"></i></div>
                                        <div class="genre-name">${escapeHtml(genre.name)}</div>
                                        <div class="genre-stats">${t('genres.artists_albums', '{a} artistes • {b} albums').replace('{a}', genre.artistCount).replace('{b}', genre.albumCount)}</div>
                                        <button class="genre-radio-btn" onclick="startGenreRadio('${escapeHtml(genre.name).replace(/'/g, "\\'")}')" title="Radio ${escapeHtml(genre.name)}">
                                            <i class="ri-radio-line"></i>
                                        </button>
                                    </div>`;
                                }).join('')}
                            </div>
                        </div>
                    `;
                    contentBody.innerHTML = html;
                }
            } catch (e) {
                console.error('Error loading genres:', e);
                showError(t('errors.load_genres', 'Erreur lors du chargement des genres.'));
            }
        }

        // Make renderGenres available globally for onclick
        window.renderGenres = renderGenres;
        window.startGenreRadio = startGenreRadio;

        async function renderPlaylists() {
            hideAlbumBackground();
            contentTitle.textContent = t('nav.playlists', 'Playlists');
            showLoading();

            try {
                const response = await fetch(`${API_URL}?action=get_playlists&user=${app.currentUser}`);
                const result = await response.json();

                if (result.error) {
                    showError(t('errors.load_playlists', 'Erreur lors du chargement des playlists.'));
                    return;
                }

                const playlists = result.data;

                let html = `
                    <div style="margin-bottom: 20px; text-align: right;">
                        <button onclick="createNewPlaylist()" class="album-action-btn album-play-btn">
                            ${t('playlists.new_btn', '➕ Nouvelle Playlist')}
                        </button>
                    </div>
                `;

                if (playlists.length === 0) {
                    html += `<div class="empty-state" style="text-align: center; padding: 40px;">
                                <div style="font-size: 48px; margin-bottom: 16px;">🎶</div>
                                <p>${t('empty.no_playlist', "Vous n'avez pas encore de playlist.")}</p>
                             </div>`;
                } else {
                    html += `
                        <div class="album-grid">
                            ${playlists.map(p => `
                                <div class="album-card">
                                    <div class="album-cover" style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); cursor: pointer;" onclick="viewPlaylist(${p.id})">
                                        <div style="color: white; font-size: 48px; font-weight: 700;">🎶</div>
                                    </div>
                                    <div class="album-name">${escapeHtml(p.name)}</div>
                                    <div class="album-info">${t('counts.songs','{n} chansons').replace('{n}', p.song_count)}</div>
                                    <div class="playlist-actions" style="margin-top: 10px; display: flex; gap: 10px; justify-content: center;">
                                        <button class="song-action-btn" onclick="renamePlaylist(${p.id}, '${jsStr(p.name)}')">✏️</button>
                                        <button class="song-action-btn" onclick="deletePlaylist(${p.id}, '${jsStr(p.name)}')">🗑️</button>
                                    </div>
                                </div>
                            `).join('')}
                        </div>
                    `;
                }

                contentBody.innerHTML = html;

            } catch (error) {
                console.error('Error rendering playlists:', error);
                showError(t('errors.load_playlists_fail', 'Impossible de charger les playlists.'));
            }
        }

        async function viewPlaylist(playlistId) {
             hideAlbumBackground();
             showLoading();

            try {
                // Inefficient, but simple. Could be combined into one API call later.
                const [playlistsResponse, songsResponse] = await Promise.all([
                    fetch(`${API_URL}?action=get_playlists&user=${app.currentUser}`),
                    fetch(`${API_URL}?action=get_playlist_songs&user=${app.currentUser}&playlist_id=${playlistId}`)
                ]);

                const playlistsResult = await playlistsResponse.json();
                const songsResult = await songsResponse.json();

                if (playlistsResult.error || songsResult.error) {
                    showError(songsResult.error || t('errors.load_playlist', 'Erreur lors du chargement de la playlist.'));
                    return;
                }

                const playlist = playlistsResult.data.find(p => p.id == playlistId);
                const songs = songsResult.data;
                contentTitle.textContent = playlist ? playlist.name : t('playlists.label', 'Playlist');

                let html = `
                    <div>
                        <div style="margin-bottom: 20px;">
                            <button onclick="renderView('playlists')" class="back-btn">
                                ${t('playlists.back', '← Retour aux playlists')}
                            </button>
                        </div>
                        <div class="album-header-container">
                            <div class="album-cover-large" style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);">
                                <div style="color: white; font-size: 80px; font-weight: 700;">🎶</div>
                            </div>
                            <div class="album-header-info">
                                <p style="color: var(--text-secondary); font-size: 11px; text-transform: uppercase; font-weight: 600; margin-bottom: 5px;">${t('playlists.label', 'Playlist')}</p>
                                <h2 class="album-title">${escapeHtml(playlist.name)}</h2>
                                <p style="color: var(--text-secondary); font-size: 13px; margin-bottom: 15px;">${t('counts.songs','{n} chansons').replace('{n}', songs.length)}</p>
                                <button onclick="playPlaylist(${playlistId})" class="album-action-btn album-play-btn">
                                    ${t('common.play_all', '▶ Lire tout')}
                                </button>
                            </div>
                        </div>
                        <div class="song-list">
                            ${songs.map((song, index) => `
                                <div class="song-item" data-song-id="${song.id}" onclick="playPlaylist(${playlistId}, ${index})">
                                    <div class="song-number">${index + 1}</div>
                                    <div class="song-play-icon">▶</div>
                                    <div class="song-thumbnail">
                                        <img src="${song.artworkUrl || DEFAULT_ALBUM_IMG}" alt="${escapeHtml(song.title)}">
                                    </div>
                                    <div class="song-info">
                                        <div class="song-title">${escapeHtml(song.title)}</div>
                                        <div class="song-artist">${escapeHtml(song.artist)}</div>
                                    </div>
                                    <div class="song-duration">${formatDuration(song.duration)}</div>
                                    <div class="song-actions">
                                        <button class="song-action-btn" onclick="event.stopPropagation(); removeFromPlaylistHandler(${song.playlist_song_id}, ${playlist.id})">🗑️</button>
                                    </div>
                                </div>
                            `).join('')}
                        </div>
                    </div>
                `;

                contentBody.innerHTML = html;

            } catch (error) {
                console.error('Error loading playlist:', error);
                showError(t('errors.load_playlist_fail', 'Impossible de charger la playlist.'));
            }
        }

        async function playPlaylist(playlistId, startIndex = 0) {
            try {
                const response = await fetch(`${API_URL}?action=get_playlist_songs&user=${app.currentUser}&playlist_id=${playlistId}`);
                const result = await response.json();
                if (result.error) throw new Error(result.error);

                const songs = result.data;
                if (songs.length === 0) return;

                app.queue = songs.map(s => ({...s, artist: s.artist, album: s.album, artworkUrl: s.artworkUrl, filePath: s.filePath, duration: s.duration, title: s.title, id: s.id}));
                app.currentTrackIndex = startIndex;
                loadTrack(app.queue[startIndex]);
                renderQueue();
            } catch (error) {
                showToast(`${t('common.error','Erreur')}: ${error.message}`, 'error');
            }
        }

        async function removeFromPlaylistHandler(playlistSongId, playlistId) {
            if (!confirm(t('confirm.remove_song_playlist', "Êtes-vous sûr de vouloir retirer cette chanson de la playlist ?"))) return;

            const formData = new FormData();
            formData.append('user', app.currentUser);
            formData.append('playlist_song_id', playlistSongId);

            try {
                const response = await fetch(`${API_URL}?action=remove_from_playlist`, { method: 'POST', body: formData });
                const result = await response.json();
                if (result.error) throw new Error(result.error);
                showToast(t('toast.song_removed_playlist', 'Chanson retirée!'), 'success');
                viewPlaylist(playlistId); // Refresh the view
            } catch (error) {
                showToast(`${t('common.error','Erreur')}: ${error.message}`, 'error');
            }
        }



        async function createNewPlaylist() {
            const name = prompt(t('playlists.prompt_create', 'Entrez le nom de la nouvelle playlist :'));
            if (!name) return;

            const formData = new FormData();
            formData.append('user', app.currentUser);
            formData.append('name', name);

            try {
                const response = await fetch(`${API_URL}?action=create_playlist`, { method: 'POST', body: formData });
                const result = await response.json();
                if (result.error) throw new Error(result.error);
                showToast(t('toast.playlist_created', 'Playlist créée!'), 'success');
                renderPlaylists(); // Refresh the view
            } catch (error) {
                showToast(`${t('common.error','Erreur')}: ${error.message}`, 'error');
            }
        }

        async function renamePlaylist(playlistId, currentName) {
            const newName = prompt(t('playlists.prompt_rename', 'Entrez le nouveau nom de la playlist :'), currentName);
            if (!newName || newName === currentName) return;

            const formData = new FormData();
            formData.append('user', app.currentUser);
            formData.append('playlist_id', playlistId);
            formData.append('name', newName);

            try {
                const response = await fetch(`${API_URL}?action=rename_playlist`, { method: 'POST', body: formData });
                const result = await response.json();
                if (result.error) throw new Error(result.error);
                showToast(t('toast.playlist_renamed', 'Playlist renommée!'), 'success');
                renderPlaylists(); // Refresh the view
            } catch (error) {
                showToast(`${t('common.error','Erreur')}: ${error.message}`, 'error');
            }
        }

        async function deletePlaylist(playlistId, playlistName) {
            if (!confirm(t('confirm.delete_playlist', 'Êtes-vous sûr de vouloir supprimer la playlist "{name}" ?').replace('{name}', playlistName))) return;

            const formData = new FormData();
            formData.append('user', app.currentUser);
            formData.append('playlist_id', playlistId);

            try {
                const response = await fetch(`${API_URL}?action=delete_playlist`, { method: 'POST', body: formData });
                const result = await response.json();
                if (result.error) throw new Error(result.error);
                showToast(t('toast.playlist_deleted', 'Playlist supprimée!'), 'success');
                renderPlaylists(); // Refresh the view
            } catch (error) {
                showToast(`${t('common.error','Erreur')}: ${error.message}`, 'error');
            }
        }

        async function renderStatistics() {
            hideAlbumBackground();
            contentTitle.textContent = t('nav.statistics', 'Statistiques');
            showLoading();

            try {
                const response = await fetch(`api/library.php?action=get_stats&user=${app.currentUser}`);
                const result = await response.json();

                if (result.error) {
                    showError(result.message || t('errors.load_stats', 'Erreur lors du chargement des statistiques.'));
                    return;
                }

                const stats = result.data;
                window.currentStatsData = stats;

                const maxSongPlays = stats.topSongs.length > 0 ? Math.max(...stats.topSongs.map(s => parseInt(s.play_count))) : 1;

                // Helper: relative time
                function timeAgo(dateStr) {
                    const now = new Date();
                    const date = new Date(dateStr);
                    const diffMs = now - date;
                    const diffMin = Math.floor(diffMs / 60000);
                    if (diffMin < 1) return t('common.just_now', "à l'instant");
                    if (diffMin < 60) return t('common.ago_min', 'il y a {n}min').replace('{n}', diffMin);
                    const diffH = Math.floor(diffMin / 60);
                    if (diffH < 24) return t('common.ago_hours', 'il y a {n}h').replace('{n}', diffH);
                    const diffD = Math.floor(diffH / 24);
                    if (diffD < 7) return t('common.ago_days', 'il y a {n}j').replace('{n}', diffD);
                    return date.toLocaleDateString(app.lang === 'en' ? 'en-GB' : 'fr-FR', { day: 'numeric', month: 'short' });
                }

                // Section 1: Hero Metrics
                const heroHtml = `
                    <div class="stats-hero">
                        <div class="glass-card stats-hero-card">
                            <i class="ri-play-circle-fill stats-hero-icon accent"></i>
                            <div class="stats-hero-value">${stats.general.totalPlays.toLocaleString()}</div>
                            <div class="stats-hero-label">${t('stats.total_plays', 'Écoutes totales')}</div>
                        </div>
                        <div class="glass-card stats-hero-card">
                            <i class="ri-time-fill stats-hero-icon blue"></i>
                            <div class="stats-hero-value">${stats.general.totalListenTimeFormatted}</div>
                            <div class="stats-hero-label">${t('stats.listen_time', "Temps d'écoute")}</div>
                        </div>
                        <div class="glass-card stats-hero-card">
                            <i class="ri-music-2-fill stats-hero-icon green"></i>
                            <div class="stats-hero-value">${stats.general.uniqueSongsPlayed.toLocaleString()}</div>
                            <div class="stats-hero-label">${t('stats.unique_songs', 'Chansons uniques')}</div>
                        </div>
                        <div class="glass-card stats-hero-card">
                            <i class="ri-check-double-fill stats-hero-icon purple"></i>
                            <div class="stats-hero-value">${stats.general.completionRate}%</div>
                            <div class="stats-hero-label">${t('stats.completion_rate', 'Taux de complétion')}</div>
                        </div>
                    </div>
                `;

                // Section 2: Activity Charts
                const activityHtml = `
                    <div class="stats-section">
                        <div class="stats-section-title"><i class="ri-bar-chart-2-fill"></i> ${t('stats.activity', "Activité d'écoute")}</div>
                        <div class="stats-row">
                            <div class="glass-card">
                                <div class="chart-wrapper"><canvas id="dailyPlaysChart"></canvas></div>
                            </div>
                            <div class="glass-card">
                                <div class="chart-wrapper"><canvas id="hourlyChart"></canvas></div>
                            </div>
                        </div>
                    </div>
                `;

                // Section 3: Library Growth
                const growthHtml = stats.libraryGrowth.labels.length > 1 ? `
                    <div class="stats-section">
                        <div class="stats-section-title"><i class="ri-line-chart-fill"></i> ${t('stats.library_growth', 'Croissance de la bibliothèque')}</div>
                        <div class="glass-card">
                            <div class="chart-wrapper"><canvas id="growthChart"></canvas></div>
                        </div>
                    </div>
                ` : '';

                // Section 4: Genres
                const hasGenres = stats.genreChart.labels.length > 0;
                const gc = stats.genreCoverage || { totalArtists: 0, artistsWithGenre: 0, percent: 0 };
                const genreHtml = `
                    <div class="stats-section">
                        <div class="stats-section-title" style="display:flex;align-items:center;gap:12px;flex-wrap:wrap;">
                            <span><i class="ri-disc-fill"></i> Genres</span>
                            <button id="genre-scan-btn" onclick="startGenreScan()" class="rescan-btn" style="font-size:12px;padding:6px 14px;">
                                <i class="ri-radar-line" id="genre-scan-icon"></i> ${t('scan.genres_btn','Scanner les genres')}
                            </button>
                            <label style="display:flex;align-items:center;gap:6px;font-size:12px;color:var(--text-secondary);cursor:pointer;">
                                <input type="checkbox" id="genre-scan-force" style="cursor:pointer;">
                                ${t('stats.genre_force', 'Forcer (réécrire existants)')}
                            </label>
                            <button id="orphan-cleanup-btn" onclick="cleanupOrphans()" class="rescan-btn" style="font-size:12px;padding:6px 14px;">
                                <i class="ri-delete-bin-2-line" id="orphan-cleanup-icon"></i> ${t('scan.clean_btn','Nettoyer les orphelins')}
                            </button>
                            ${gc.totalArtists > 0 ? `<span style="font-size:13px;color:var(--text-secondary);font-weight:400;">${gc.artistsWithGenre}/${gc.totalArtists} artistes (${gc.percent}%)</span>` : ''}
                        </div>
                        <div id="genre-scan-progress" style="display:none;margin-bottom:16px;">
                            <div class="glass-card" style="display:flex;align-items:center;gap:12px;padding:14px 18px;">
                                <div class="scan-spinner"></div>
                                <span id="genre-scan-progress-text">${t('stats.scanning', 'Scan en cours...')}</span>
                            </div>
                        </div>
                        ${hasGenres ? `
                        <div class="stats-row">
                            <div class="glass-card">
                                <div class="chart-wrapper"><canvas id="genreChart"></canvas></div>
                            </div>
                            <div class="glass-card">
                                ${stats.genreChart.labels.map((genre, i) => {
                                    const maxGenre = Math.max(...stats.genreChart.data);
                                    const pct = maxGenre > 0 ? (stats.genreChart.data[i] / maxGenre * 100) : 0;
                                    return `<div class="stats-genre-item">
                                        <div class="stats-genre-name">${genre}</div>
                                        <div class="stats-genre-bar">
                                            <div class="stats-genre-bar-fill" style="width:${pct}%; background:${stats.genreChart.colors[i] || 'var(--accent)'}"></div>
                                        </div>
                                        <div class="stats-genre-count">${stats.genreChart.data[i]}</div>
                                    </div>`;
                                }).join('')}
                            </div>
                        </div>
                        ` : `
                        <div class="glass-card stats-empty-note">
                            <i class="ri-disc-line" style="font-size:32px;margin-bottom:8px;display:block;"></i>
                            ${t('empty.few_genres','Peu de genres assignés dans la bibliothèque.<br>Cliquez sur <strong>"Scanner les genres"</strong> pour analyser les tags ID3 de vos fichiers.')}
                        </div>
                        `}
                    </div>
                `;

                // Section 5: Listening Habits
                const habitsHtml = `
                    <div class="stats-section">
                        <div class="stats-section-title"><i class="ri-calendar-fill"></i> ${t('stats.habits', "Habitudes d'écoute")}</div>
                        <div class="stats-row">
                            <div class="glass-card">
                                <div class="chart-wrapper"><canvas id="weekdayChart"></canvas></div>
                            </div>
                            <div class="glass-card stats-insight">
                                <div class="stats-insight-item">
                                    <div class="stats-insight-icon"><i class="ri-timer-flash-line"></i></div>
                                    <div>
                                        <div class="stats-insight-label">${t('stats.avg_duration', 'Durée moyenne par écoute')}</div>
                                        <div class="stats-insight-value">${stats.general.avgDurationFormatted}</div>
                                    </div>
                                </div>
                                <div class="stats-insight-item">
                                    <div class="stats-insight-icon"><i class="ri-fire-fill"></i></div>
                                    <div>
                                        <div class="stats-insight-label">${t('stats.most_active_day', 'Jour le plus actif')}</div>
                                        <div class="stats-insight-value">${stats.insights.mostActiveDay || '—'}</div>
                                    </div>
                                </div>
                                <div class="stats-insight-item">
                                    <div class="stats-insight-icon"><i class="ri-skip-forward-fill"></i></div>
                                    <div>
                                        <div class="stats-insight-label">${t('stats.skipped', 'Chansons passées')}</div>
                                        <div class="stats-insight-value">${stats.general.totalSkips.toLocaleString()}</div>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                `;

                // Section 6: Top Artists & Albums (reuse home page card style)
                const topGridHtml = `
                    <div class="stats-section">
                        <div class="stats-section-title"><i class="ri-star-fill"></i> ${t('stats.top_artists', 'Top Artistes')}</div>
                        <div class="artist-grid">
                            ${stats.topArtists.map(artist => `
                                <div class="artist-card" onclick="viewArtist(${artist.id})">
                                    <div class="artist-image">
                                        <img src="${artist.imageUrl}" alt="${artist.name}" loading="lazy" style="width:100%;height:100%;object-fit:cover;">
                                    </div>
                                    <div class="artist-name">${artist.name}</div>
                                    <div class="artist-info">${t('home.plays', '{n} écoutes').replace('{n}', artist.play_count)}</div>
                                </div>
                            `).join('')}
                        </div>
                    </div>
                    <div class="stats-section">
                        <div class="stats-section-title"><i class="ri-album-fill"></i> ${t('stats.top_albums', 'Top Albums')}</div>
                        <div class="artist-grid">
                            ${stats.topAlbums.map(album => `
                                <div class="album-card" onclick="viewAlbum(${album.id})">
                                    <div class="album-cover">
                                        <img src="${album.artworkUrl}" alt="${album.name}" loading="lazy" style="width:100%;height:100%;object-fit:cover;">
                                    </div>
                                    <div class="album-name">${album.name}</div>
                                    <div class="album-info">${escapeHtml(album.artist_name)} · ${t('home.plays', '{n} écoutes').replace('{n}', album.play_count)}</div>
                                </div>
                            `).join('')}
                        </div>
                    </div>
                `;

                // Section 7: Top Songs
                const topSongsHtml = `
                    <div class="stats-section">
                        <div class="stats-section-title"><i class="ri-music-fill"></i> ${t('stats.top_songs', 'Top Chansons')}</div>
                        <div class="glass-card">
                            ${stats.topSongs.map((song, index) => {
                                const pct = maxSongPlays > 0 ? (parseInt(song.play_count) / maxSongPlays * 100) : 0;
                                return `<div class="stats-song-item" onclick="playFromStats(${index})">
                                    <div class="stats-song-rank">${index + 1}</div>
                                    <img src="${song.artworkUrl}" class="stats-song-artwork" loading="lazy">
                                    <div class="stats-song-info">
                                        <div class="stats-song-title">${song.title}</div>
                                        <div class="stats-song-artist">${song.artist_name}</div>
                                    </div>
                                    <div class="stats-song-bar-wrapper">
                                        <div class="stats-song-bar">
                                            <div class="stats-song-bar-fill" style="width:${pct}%"></div>
                                        </div>
                                        <div class="stats-song-count">${song.play_count}</div>
                                    </div>
                                </div>`;
                            }).join('')}
                        </div>
                    </div>
                `;

                // Section 8: Recent Plays
                const recentHtml = stats.recentPlays.length > 0 ? `
                    <div class="stats-section">
                        <div class="stats-section-title"><i class="ri-history-fill"></i> ${t('stats.recent', 'Écoutes récentes')}</div>
                        <div class="glass-card">
                            ${stats.recentPlays.map(play => `
                                <div class="stats-timeline-item" onclick="viewAlbum(${play.album_id})">
                                    <img src="${play.artworkUrl}" class="stats-timeline-artwork" loading="lazy">
                                    <div class="stats-timeline-info">
                                        <div class="stats-timeline-title">${play.title}</div>
                                        <div class="stats-timeline-artist">${play.artist_name}</div>
                                    </div>
                                    <div class="stats-timeline-time">${timeAgo(play.played_at_iso)}</div>
                                </div>
                            `).join('')}
                        </div>
                    </div>
                ` : '';

                contentBody.innerHTML = `
                    <div class="stats-page">
                        ${heroHtml}
                        ${activityHtml}
                        ${growthHtml}
                        ${genreHtml}
                        ${habitsHtml}
                        ${topGridHtml}
                        ${topSongsHtml}
                        ${recentHtml}
                    </div>
                `;

                // Chart.js defaults
                const isDark = document.documentElement.getAttribute('data-theme') === 'dark';
                const gridColor = isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)';
                const tickColor = isDark ? '#95a5a6' : '#5f6368';

                Chart.defaults.color = tickColor;
                Chart.defaults.borderColor = gridColor;

                // Chart 1: Daily plays (30 days) - Line chart with gradient
                const dailyCtx = document.getElementById('dailyPlaysChart').getContext('2d');
                const dailyGradient = dailyCtx.createLinearGradient(0, 0, 0, 250);
                dailyGradient.addColorStop(0, 'rgba(255, 0, 0, 0.3)');
                dailyGradient.addColorStop(1, 'rgba(255, 0, 0, 0.02)');

                new Chart(dailyCtx, {
                    type: 'line',
                    data: {
                        labels: stats.dailyPlaysChart.labels,
                        datasets: [{
                            label: t('stats.plays', 'Écoutes'),
                            data: stats.dailyPlaysChart.data,
                            borderColor: 'rgba(255, 0, 0, 0.9)',
                            backgroundColor: dailyGradient,
                            fill: true,
                            tension: 0.4,
                            borderWidth: 2,
                            pointRadius: 0,
                            pointHoverRadius: 5,
                            pointHoverBackgroundColor: '#ff0000',
                        }]
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        interaction: { mode: 'index', intersect: false },
                        scales: {
                            y: { beginAtZero: true, grid: { color: gridColor }, ticks: { color: tickColor } },
                            x: { grid: { display: false }, ticks: { color: tickColor, maxRotation: 45, maxTicksLimit: 10 } }
                        },
                        plugins: {
                            legend: { display: false },
                            title: { display: true, text: t('home.last_30_days', '30 derniers jours'), color: tickColor, font: { size: 13 } }
                        }
                    }
                });

                // Chart 2: Hourly distribution - Polar area
                const hourlyCtx = document.getElementById('hourlyChart').getContext('2d');
                const hourlyColors = stats.hourlyChart.data.map((val, i) => {
                    const maxH = Math.max(...stats.hourlyChart.data, 1);
                    const alpha = 0.2 + (val / maxH) * 0.6;
                    return `rgba(0, 122, 255, ${alpha})`;
                });

                new Chart(hourlyCtx, {
                    type: 'polarArea',
                    data: {
                        labels: stats.hourlyChart.labels,
                        datasets: [{
                            data: stats.hourlyChart.data,
                            backgroundColor: hourlyColors,
                            borderColor: 'rgba(0, 122, 255, 0.3)',
                            borderWidth: 1,
                        }]
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        scales: {
                            r: {
                                ticks: { display: false },
                                grid: { color: gridColor },
                            }
                        },
                        plugins: {
                            legend: { display: false },
                            title: { display: true, text: t('stats.listen_hours', "Heures d'écoute"), color: tickColor, font: { size: 13 } }
                        }
                    }
                });

                // Chart 3: Library Growth (if data)
                if (stats.libraryGrowth.labels.length > 1) {
                    const growthCtx = document.getElementById('growthChart').getContext('2d');
                    new Chart(growthCtx, {
                        type: 'line',
                        data: {
                            labels: stats.libraryGrowth.labels,
                            datasets: [
                                {
                                    label: t('nav.songs', 'Chansons'),
                                    data: stats.libraryGrowth.songs,
                                    borderColor: '#34C759',
                                    backgroundColor: 'rgba(52, 199, 89, 0.1)',
                                    fill: true,
                                    tension: 0.3,
                                    borderWidth: 2,
                                    pointRadius: 3,
                                    yAxisID: 'y',
                                },
                                {
                                    label: t('nav.albums', 'Albums'),
                                    data: stats.libraryGrowth.albums,
                                    borderColor: '#007AFF',
                                    backgroundColor: 'rgba(0, 122, 255, 0.1)',
                                    fill: true,
                                    tension: 0.3,
                                    borderWidth: 2,
                                    pointRadius: 3,
                                    yAxisID: 'y1',
                                },
                                {
                                    label: t('nav.artists', 'Artistes'),
                                    data: stats.libraryGrowth.artists,
                                    borderColor: '#AF52DE',
                                    backgroundColor: 'rgba(175, 82, 222, 0.1)',
                                    fill: true,
                                    tension: 0.3,
                                    borderWidth: 2,
                                    pointRadius: 3,
                                    yAxisID: 'y1',
                                }
                            ]
                        },
                        options: {
                            responsive: true,
                            maintainAspectRatio: false,
                            interaction: { mode: 'index', intersect: false },
                            scales: {
                                y: {
                                    type: 'linear',
                                    position: 'left',
                                    grid: { color: gridColor },
                                    ticks: { color: '#34C759' },
                                    title: { display: true, text: t('nav.songs', 'Chansons'), color: '#34C759' }
                                },
                                y1: {
                                    type: 'linear',
                                    position: 'right',
                                    grid: { drawOnChartArea: false },
                                    ticks: { color: '#007AFF' },
                                    title: { display: true, text: t('stats.albums_artists', 'Albums / Artistes'), color: '#007AFF' }
                                },
                                x: { grid: { display: false }, ticks: { color: tickColor } }
                            },
                            plugins: {
                                legend: { display: true, labels: { usePointStyle: true, pointStyle: 'circle', color: tickColor } }
                            }
                        }
                    });
                }

                // Chart 4: Genre Doughnut (if data)
                if (stats.genreChart.labels.length > 0) {
                    const genreCtx = document.getElementById('genreChart').getContext('2d');
                    new Chart(genreCtx, {
                        type: 'doughnut',
                        data: {
                            labels: stats.genreChart.labels,
                            datasets: [{
                                data: stats.genreChart.data,
                                backgroundColor: stats.genreChart.colors,
                                borderWidth: 0,
                                hoverOffset: 8,
                            }]
                        },
                        options: {
                            responsive: true,
                            maintainAspectRatio: false,
                            cutout: '60%',
                            plugins: {
                                legend: { position: 'bottom', labels: { usePointStyle: true, pointStyle: 'circle', padding: 12, color: tickColor } }
                            }
                        }
                    });
                }

                // Chart 5: Weekday bar chart
                const weekdayCtx = document.getElementById('weekdayChart').getContext('2d');
                const weekdayColors = stats.weekdayChart.data.map((val, i) => {
                    const maxW = Math.max(...stats.weekdayChart.data, 1);
                    const alpha = 0.3 + (val / maxW) * 0.5;
                    return `rgba(175, 82, 222, ${alpha})`;
                });

                new Chart(weekdayCtx, {
                    type: 'bar',
                    data: {
                        labels: stats.weekdayChart.labels,
                        datasets: [{
                            label: t('stats.plays', 'Écoutes'),
                            data: stats.weekdayChart.data,
                            backgroundColor: weekdayColors,
                            borderRadius: 6,
                            borderSkipped: false,
                        }]
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        indexAxis: 'y',
                        scales: {
                            x: { beginAtZero: true, grid: { color: gridColor }, ticks: { color: tickColor } },
                            y: { grid: { display: false }, ticks: { color: tickColor, font: { weight: 500 } } }
                        },
                        plugins: {
                            legend: { display: false },
                            title: { display: true, text: t('stats.by_day', 'Écoutes par jour'), color: tickColor, font: { size: 13 } }
                        }
                    }
                });

            } catch (error) {
                console.error('Error rendering statistics:', error);
                showError(t('errors.load_stats', 'Erreur lors du chargement des statistiques.'));
            }
        }

        function playFromStats(songIndex) {
            if (!window.currentStatsData || !window.currentStatsData.topSongs) return;
            const song = window.currentStatsData.topSongs[songIndex];
            playAlbum(song.album_id);
            setTimeout(() => {
                const songIndexInQueue = app.queue.findIndex(t => t.id === song.id);
                if (songIndexInQueue !== -1) {
                    jumpToTrack(songIndexInQueue);
                }
            }, 1000);
        }




        async function renderFavorites() {
            hideAlbumBackground();
            contentTitle.textContent = t('favorites.title', 'Vos favoris');
            showLoading();

            try {
                const response = await fetch(`${API_URL}?action=get_all_favorites&user=${app.currentUser}`);
                const result = await response.json();

                if (result.error) {
                    showError(t('errors.load_favorites', 'Erreur lors du chargement des favoris.'));
                    return;
                }

                const { artists, albums, songs } = result.data;
                const totalFavorites = artists.length + albums.length + songs.length;

                if (totalFavorites === 0) {
                    showEmpty(t('favorites.none', "Vous n'avez pas encore de favoris. Cliquez sur le ♡ pour en ajouter !"));
                    return;
                }

                let html = '';

                // Artists section
                if (artists.length > 0) {
                    html += `
                        <div class="favorites-section">
                            <div class="favorites-section-header">
                                <h3 class="favorites-section-title"><i class="ri-mic-line"></i> ${t('nav.artists', 'Artistes')} (${artists.length})</h3>
                                <button onclick="playFavoriteArtists()" class="favorites-play-btn"><i class="ri-play-fill"></i> ${t('favorites.play_all', 'Tout lire')}</button>
                            </div>
                            <div class="artist-grid" style="grid-template-columns: repeat(auto-fill, minmax(120px, 1fr));">
                                ${artists.map(artist => `
                                    <div class="artist-card" onclick="viewArtist(${artist.id})">
                                        <div class="artist-image" style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);">
                                            ${artist.imageUrl ? `<img src="${artist.imageUrl}" alt="${escapeHtml(artist.name)}" style="width: 100%; height: 100%; object-fit: cover;">` : artist.name.charAt(0).toUpperCase()}
                                        </div>
                                        <div class="artist-name">${escapeHtml(artist.name)}</div>
                                        <div class="artist-info">${t('counts.albums', '{n} albums').replace('{n}', artist.album_count)}</div>
                                    </div>
                                `).join('')}
                            </div>
                        </div>
                    `;
                }

                // Albums section
                if (albums.length > 0) {
                    html += `
                        <div class="favorites-section">
                            <div class="favorites-section-header">
                                <h3 class="favorites-section-title"><i class="ri-album-line"></i> ${t('nav.albums', 'Albums')} (${albums.length})</h3>
                                <button onclick="playFavoriteAlbums()" class="favorites-play-btn"><i class="ri-play-fill"></i> ${t('favorites.play_all', 'Tout lire')}</button>
                            </div>
                            <div class="album-grid" style="grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));">
                                ${albums.map(album => `
                                    <div class="album-card" onclick="viewAlbum(${album.id})">
                                        <div class="album-cover">
                                            <img src="${album.artworkUrl || DEFAULT_ALBUM_IMG}" alt="${escapeHtml(album.name)}" style="width: 100%; height: 100%; object-fit: cover;">
                                        </div>
                                        <div class="album-name">${escapeHtml(album.name)}</div>
                                        <div class="album-info">${escapeHtml(album.artist_name)}${album.year ? ' • ' + album.year : ''}</div>
                                    </div>
                                `).join('')}
                            </div>
                        </div>
                    `;
                }

                // Songs section
                if (songs.length > 0) {
                    html += `
                        <div class="favorites-section">
                            <div class="favorites-section-header">
                                <h3 class="favorites-section-title"><i class="ri-music-2-line"></i> ${t('nav.songs', 'Chansons')} (${songs.length})</h3>
                                <button onclick="playFavorites(0)" class="favorites-play-btn"><i class="ri-play-fill"></i> ${t('favorites.play_all', 'Tout lire')}</button>
                            </div>
                            <div class="song-list">
                                ${songs.map((song, index) => `
                                    <div class="song-item" data-song-id="${song.id}" onclick="playFavorites(${index})" oncontextmenu="showContextMenu(event, ${song.id})">
                                        <div class="song-number">${index + 1}</div>
                                        <div class="song-play-icon">▶</div>
                                        <div class="song-thumbnail">
                                             <img src="${song.artworkUrl || DEFAULT_ALBUM_IMG}" alt="${escapeHtml(song.title)}">
                                        </div>
                                        <div class="song-info">
                                            <div class="song-title">${escapeHtml(song.title)}</div>
                                            <div class="song-artist">${escapeHtml(song.artist)}</div>
                                        </div>
                                        <div class="song-duration">${formatDuration(song.duration)}</div>
                                        <div class="song-actions">
                                            <button class="song-action-btn favorite-btn active" data-song-id="${song.id}" onclick="event.stopPropagation(); toggleFavorite(${song.id})">
                                                <i class="ri-heart-fill" style="color: var(--accent);"></i>
                                            </button>
                                        </div>
                                    </div>
                                `).join('')}
                            </div>
                        </div>
                    `;
                }

                contentBody.innerHTML = html;
                // Store for playback
                window.currentFavorites = songs;
                window.currentFavoriteArtists = artists;
                window.currentFavoriteAlbums = albums;
            } catch (error) {
                console.error('Error rendering favorites:', error);
                showError(t('errors.load_favorites_fail', 'Impossible de charger les favoris.'));
            }
        }

        function playFavorites(startIndex) {
            if (!window.currentFavorites || window.currentFavorites.length === 0) return;
            app.radioMode = false;
            app.queue = window.currentFavorites.map(s => ({...s, artist: s.artist, album: s.album, artworkUrl: s.artworkUrl, filePath: s.filePath, duration: s.duration, title: s.title, id: s.id}));
            app.currentTrackIndex = startIndex;
            loadTrack(app.queue[startIndex]);
            renderQueue();
        }

        async function playFavoriteArtists() {
            if (!window.currentFavoriteArtists || window.currentFavoriteArtists.length === 0) return;
            app.radioMode = false;

            try {
                const allSongs = [];
                for (const artist of window.currentFavoriteArtists) {
                    const response = await fetch(`${BASE_PATH}/api/library.php?user=${app.currentUser}&action=artist&id=${artist.id}`);
                    const result = await response.json();
                    if (!result.error && result.data.albums) {
                        for (const album of result.data.albums) {
                            const albumResponse = await fetch(`${BASE_PATH}/api/library.php?user=${app.currentUser}&action=album&id=${album.id}`);
                            const albumResult = await albumResponse.json();
                            if (!albumResult.error && albumResult.data.songs) {
                                albumResult.data.songs.forEach(song => {
                                    allSongs.push({
                                        id: song.id,
                                        title: song.title,
                                        artist: artist.name,
                                        filePath: song.filePath,
                                        artworkUrl: albumResult.data.artworkUrl,
                                        duration: song.duration
                                    });
                                });
                            }
                        }
                    }
                }
                if (allSongs.length > 0) {
                    app.queue = shuffleArray(allSongs);
                    app.currentTrackIndex = 0;
                    loadTrack(app.queue[0]);
                    renderQueue();
                }
            } catch (error) {
                console.error('Error playing favorite artists:', error);
            }
        }

        async function playFavoriteAlbums() {
            if (!window.currentFavoriteAlbums || window.currentFavoriteAlbums.length === 0) return;
            app.radioMode = false;

            try {
                const allSongs = [];
                for (const album of window.currentFavoriteAlbums) {
                    const response = await fetch(`${BASE_PATH}/api/library.php?user=${app.currentUser}&action=album&id=${album.id}`);
                    const result = await response.json();
                    if (!result.error && result.data.songs) {
                        result.data.songs.forEach(song => {
                            allSongs.push({
                                id: song.id,
                                title: song.title,
                                artist: album.artist_name,
                                filePath: song.filePath,
                                artworkUrl: result.data.artworkUrl,
                                duration: song.duration
                            });
                        });
                    }
                }
                if (allSongs.length > 0) {
                    app.queue = shuffleArray(allSongs);
                    app.currentTrackIndex = 0;
                    loadTrack(app.queue[0]);
                    renderQueue();
                }
            } catch (error) {
                console.error('Error playing favorite albums:', error);
            }
        }

        // ============ DOWNLOADS SECTION ============

        let downloadsPollInterval = null;
        let _dlSearchAlbums = []; // store search results for index-based onclick

        async function renderDownloads() {
            hideAlbumBackground();
            contentTitle.textContent = t('nav.downloads', 'Téléchargements');

            // Clear any existing poll
            if (downloadsPollInterval) {
                clearInterval(downloadsPollInterval);
                downloadsPollInterval = null;
            }

            const html = `
                <div class="downloads-page">
                    <!-- YouTube Music Search -->
                    <div class="download-form-card">
                        <h3><i class="ri-music-2-line"></i> Rechercher sur YouTube Music</h3>
                        <div class="download-form">
                            <input type="text" id="dlSearchQuery" placeholder="Artiste, album…" class="download-url-input"
                                   onkeypress="if(event.key==='Enter') searchYtMusicForDownload()">
                            <input type="hidden" id="downloadUser" value="${app.currentUser}">
                            <button onclick="searchYtMusicForDownload()" class="download-fetch-btn" id="dlSearchBtn">
                                <i class="ri-search-line"></i> Rechercher
                            </button>
                        </div>
                        <div id="dlSearchResults"></div>
                    </div>

                    <!-- New Download via URL -->
                    <details class="download-form-card" style="cursor:pointer">
                        <summary style="font-weight:600;font-size:15px;list-style:none;display:flex;align-items:center;gap:8px">
                            <i class="ri-links-line"></i> Télécharger via URL
                            <span style="font-size:12px;font-weight:400;color:var(--text-secondary);margin-left:4px">(YouTube Music, playlist…)</span>
                        </summary>
                        <div style="margin-top:14px">
                            <div class="download-form">
                                <input type="text" id="downloadUrl" placeholder="https://music.youtube.com/playlist?list=…" class="download-url-input">
                                <button onclick="fetchYoutubeMetadata()" class="download-fetch-btn" id="fetchMetadataBtn">
                                    <i class="ri-search-line"></i> ${t('editor.analyze_btn', 'Analyser')}
                                </button>
                            </div>
                            <div id="downloadMetadataPreview" style="display: none;"></div>
                        </div>
                    </details>

                    <!-- Active Downloads -->
                    <div class="downloads-section">
                        <h3><i class="ri-download-line"></i> ${t('downloads.active', 'En cours')}</h3>
                        <div id="activeDownloads">
                            <div class="loading-spinner"></div>
                        </div>
                    </div>

                    <!-- Recent Downloads -->
                    <div class="downloads-section">
                        <h3><i class="ri-history-line"></i> ${t('downloads.recent', 'Récents')}</h3>
                        <div id="recentDownloads">
                            <div class="loading-spinner"></div>
                        </div>
                    </div>
                </div>
            `;

            contentBody.innerHTML = html;

            // Load downloads
            await refreshDownloadsList();

            // Start polling for updates
            downloadsPollInterval = setInterval(refreshDownloadsList, 3000);
        }

        async function searchYtMusicForDownload() {
            const query = document.getElementById('dlSearchQuery').value.trim();
            if (!query) return;
            const btn = document.getElementById('dlSearchBtn');
            const resultsDiv = document.getElementById('dlSearchResults');
            btn.disabled = true;
            resultsDiv.innerHTML = '<div class="loading-spinner" style="margin:16px auto"></div>';
            try {
                const r = await fetch(`${BASE_PATH}/download_album_api.php?action=search_ytmusic&query=${encodeURIComponent(query)}`);
                const res = await r.json();
                const albums = res.data?.albums || [];
                if (!albums.length) {
                    resultsDiv.innerHTML = '<p style="color:var(--text-secondary);padding:12px 0;text-align:center">Aucun résultat</p>';
                    return;
                }
                _dlSearchAlbums = albums;
                resultsDiv.innerHTML = albums.map((album, i) => `
                    <div class="dl-search-result">
                        <div class="dl-search-thumb">
                            ${album.thumbnail ? `<img src="${album.thumbnail}" alt="">` : '<i class="ri-music-2-line"></i>'}
                        </div>
                        <div class="dl-search-info">
                            <div class="dl-search-title">${album.title.replace(/</g,'&lt;')}</div>
                            <div class="dl-search-meta">${album.artist.replace(/</g,'&lt;')}${album.year ? ' · ' + album.year : ''}</div>
                        </div>
                        <button class="btn btn-primary dl-search-dl-btn" onclick="startDownloadFromSearch(${i})">
                            <i class="ri-download-line"></i> Télécharger
                        </button>
                    </div>
                `).join('');
            } catch(e) {
                resultsDiv.innerHTML = '<p style="color:var(--text-secondary);padding:12px 0">Erreur de recherche</p>';
            } finally {
                btn.disabled = false;
            }
        }

        async function startDownloadFromSearch(idx) {
            const album = _dlSearchAlbums[idx];
            if (!album?.browseId) return;

            // Show loading on the button
            const btns = document.querySelectorAll('.dl-search-dl-btn');
            const btn = btns[idx];
            if (btn) {
                btn.disabled = true;
                btn.innerHTML = '<i class="ri-loader-4-line ri-spin"></i>';
            }

            try {
                // Resolve browseId to playlist URL
                const r = await fetch(`${BASE_PATH}/download_album_api.php?action=resolve_album&browse_id=${encodeURIComponent(album.browseId)}`);
                const res = await r.json();
                if (!res.success) {
                    showToast(res.error || 'Impossible de résoudre l\'album', 'error');
                    return;
                }

                const data = res.data;

                // Open URL details section and populate
                const details = document.querySelector('.downloads-page details.download-form-card');
                if (details) details.open = true;

                const urlInput = document.getElementById('downloadUrl');
                if (urlInput) urlInput.value = data.playlistUrl;

                const previewDiv = document.getElementById('downloadMetadataPreview');
                if (previewDiv) {
                    previewDiv.innerHTML = `
                        <div class="download-metadata-preview">
                            <div class="metadata-thumbnail">
                                ${data.thumbnail ? `<img src="${data.thumbnail}" alt="Thumbnail">` : '<i class="ri-album-line"></i>'}
                            </div>
                            <div class="metadata-fields">
                                <div class="metadata-field">
                                    <label>${t('props.artist', 'Artiste')}</label>
                                    <input type="text" id="metaArtist" value="${escapeHtml(data.artist || '')}" placeholder="${t('downloads.artist_ph', "Nom de l'artiste")}">
                                </div>
                                <div class="metadata-field">
                                    <label>${t('props.album', 'Album')}</label>
                                    <input type="text" id="metaAlbum" value="${escapeHtml(data.title || '')}" placeholder="${t('downloads.album_ph', "Nom de l'album")}">
                                </div>
                                <div class="metadata-info">
                                    ${data.track_count ? `<span><i class="ri-music-2-line"></i> ${data.track_count} pistes</span>` : ''}
                                </div>
                            </div>
                            <button onclick="startDownload('${jsStr(data.playlistUrl)}')" class="download-start-btn">
                                <i class="ri-download-line"></i> ${t('downloads.download_btn', 'Télécharger')}
                            </button>
                        </div>
                    `;
                    previewDiv.style.display = 'block';
                    previewDiv.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
                }
            } catch(e) {
                showToast('Erreur de connexion', 'error');
            } finally {
                if (btn) {
                    btn.disabled = false;
                    btn.innerHTML = '<i class="ri-download-line"></i> Télécharger';
                }
            }
        }

        async function refreshDownloadsList() {
            try {
                const response = await fetch(`${BASE_PATH}/download_album_api.php?action=list&user=${encodeURIComponent(app.currentUser)}`);
                const result = await response.json();

                if (!result.success) {
                    console.error('Error fetching downloads:', result.error);
                    return;
                }

                const downloads = result.data || [];
                const active = downloads.filter(d => ['queued', 'downloading', 'scanning'].includes(d.status));
                const recent = downloads.filter(d => ['completed', 'error', 'cancelled'].includes(d.status))
                    .sort((a, b) => new Date(b.updated_at || b.created_at || 0) - new Date(a.updated_at || a.created_at || 0));

                // Render active downloads
                const activeContainer = document.getElementById('activeDownloads');
                if (activeContainer) {
                    if (active.length === 0) {
                        activeContainer.innerHTML = `<p class="empty-downloads">${t('empty.no_downloads', 'Aucun téléchargement en cours')}</p>`;
                    } else {
                        activeContainer.innerHTML = active.map(d => renderDownloadItem(d, true)).join('');
                    }
                }

                // Render recent downloads
                const recentContainer = document.getElementById('recentDownloads');
                if (recentContainer) {
                    if (recent.length === 0) {
                        recentContainer.innerHTML = `<p class="empty-downloads">${t('empty.no_recent_downloads', 'Aucun téléchargement récent')}</p>`;
                    } else {
                        recentContainer.innerHTML = recent.map(d => renderDownloadItem(d, false)).join('');
                    }
                }
            } catch (error) {
                console.error('Error refreshing downloads:', error);
            }
        }

        function renderDownloadItem(download, isActive) {
            const statusIcons = {
                'queued': 'ri-time-line',
                'downloading': 'ri-download-line',
                'scanning': 'ri-folder-search-line',
                'completed': 'ri-check-line',
                'error': 'ri-error-warning-line',
                'cancelled': 'ri-close-circle-line'
            };
            const statusColors = {
                'queued': '#f39c12',
                'downloading': '#3498db',
                'scanning': '#9b59b6',
                'completed': '#27ae60',
                'error': '#e74c3c',
                'cancelled': '#95a5a6'
            };

            const icon = statusIcons[download.status] || 'ri-question-line';
            const color = statusColors[download.status] || '#888';
            const progress = download.progress || 0;

            return `
                <div class="download-item ${download.status}">
                    <div class="download-item-icon" style="color: ${color};">
                        <i class="${icon} ${download.status === 'downloading' ? 'ri-spin' : ''}"></i>
                    </div>
                    <div class="download-item-info">
                        <div class="download-item-title">${escapeHtml(download.album || t('common.unknown_album', 'Album inconnu'))}</div>
                        <div class="download-item-artist">${escapeHtml(download.artist || t('common.unknown_artist', 'Artiste inconnu'))} • ${escapeHtml(download.user)}</div>
                        <div class="download-item-message">${escapeHtml(download.message || '')}</div>
                        ${isActive && download.status === 'downloading' ? `
                            <div class="download-progress-bar">
                                <div class="download-progress-fill" style="width: ${progress}%"></div>
                            </div>
                            <div class="download-progress-text">${progress}%</div>
                        ` : ''}
                    </div>
                    ${isActive ? `
                        <button onclick="cancelDownload('${download.id}')" class="download-cancel-btn" title="${t('common.cancel', 'Annuler')}">
                            <i class="ri-close-line"></i>
                        </button>
                    ` : ''}
                    ${!isActive && (download.status === 'error' || download.status === 'cancelled') ? `
                        <button onclick="retryDownload('${download.id}')" class="download-retry-btn" title="${t('downloads.retry_title', 'Réessayer')}">
                            <i class="ri-refresh-line"></i>
                        </button>
                    ` : ''}
                    ${!isActive ? `
                        <button onclick="deleteDownload('${download.id}')" class="download-delete-btn" title="${t('common.delete', 'Supprimer')}">
                            <i class="ri-delete-bin-line"></i>
                        </button>
                    ` : ''}
                </div>
            `;
        }

        async function retryDownload(downloadId) {
            try {
                const formData = new FormData();
                formData.append('download_id', downloadId);
                const response = await fetch(`${BASE_PATH}/download_album_api.php?action=retry`, { method: 'POST', body: formData });
                const result = await response.json();
                if (result.success) {
                    await refreshDownloadsList();
                } else {
                    showToast(t('common.error','Erreur') + ': ' + (result.error || t('errors.retry','Impossible de réessayer')), 'error');
                }
            } catch (error) {
                console.error('Error retrying download:', error);
                showToast(t('toast.retry_error', 'Erreur lors du réessai'), 'error');
            }
        }

        async function deleteDownload(downloadId) {
            if (!confirm(t('confirm.delete_download', 'Supprimer ce téléchargement de la liste?'))) return;
            try {
                const formData = new FormData();
                formData.append('download_id', downloadId);
                const response = await fetch(`${BASE_PATH}/download_album_api.php?action=delete`, { method: 'POST', body: formData });
                const result = await response.json();
                if (result.success) {
                    await refreshDownloadsList();
                } else {
                    showToast(t('common.error','Erreur') + ': ' + (result.error || ''), 'error');
                }
            } catch (error) {
                showToast(t('toast.delete_error', 'Erreur lors de la suppression'), 'error');
            }
        }

        async function fetchYoutubeMetadata() {
            const urlInput = document.getElementById('downloadUrl');
            const url = urlInput.value.trim();
            const previewDiv = document.getElementById('downloadMetadataPreview');
            const fetchBtn = document.getElementById('fetchMetadataBtn');

            if (!url) {
                alert(t('alert.enter_yt_url', 'Veuillez entrer une URL YouTube Music'));
                return;
            }

            if (!url.includes('youtube.com') && !url.includes('youtu.be')) {
                alert(t('alert.invalid_url', 'URL invalide. Utilisez une URL YouTube ou YouTube Music.'));
                return;
            }

            fetchBtn.innerHTML = `<i class="ri-loader-4-line ri-spin"></i> ${t('editor.analyzing','Analyse...')}`;
            fetchBtn.disabled = true;

            try {
                const response = await fetch(`${BASE_PATH}/get_youtube_metadata.php?url=${encodeURIComponent(url)}`);
                const result = await response.json();

                if (result.error) {
                    previewDiv.innerHTML = `<p style="color: #e74c3c; margin-top: 15px;"><i class="ri-error-warning-line"></i> ${escapeHtml(result.error)}</p>`;
                    previewDiv.style.display = 'block';
                    return;
                }

                const meta = result.data;
                previewDiv.innerHTML = `
                    <div class="download-metadata-preview">
                        <div class="metadata-thumbnail">
                            ${meta.thumbnail ? `<img src="${meta.thumbnail}" alt="Thumbnail">` : '<i class="ri-album-line"></i>'}
                        </div>
                        <div class="metadata-fields">
                            <div class="metadata-field">
                                <label>${t('props.artist', 'Artiste')}</label>
                                <input type="text" id="metaArtist" value="${escapeHtml(meta.artist || meta.uploader || '')}" placeholder="${t('downloads.artist_ph', "Nom de l'artiste")}">
                            </div>
                            <div class="metadata-field">
                                <label>${t('props.album', 'Album')}</label>
                                <input type="text" id="metaAlbum" value="${escapeHtml(meta.album || meta.title || '')}" placeholder="${t('downloads.album_ph', "Nom de l'album")}">
                            </div>
                            <div class="metadata-info">
                                ${meta.track_count ? `<span><i class="ri-music-2-line"></i> ${t('counts.tracks','{n} pistes').replace('{n}', meta.track_count)}</span>` : ''}
                            </div>
                        </div>
                        <button onclick="startDownload('${jsStr(url)}')" class="download-start-btn">
                            <i class="ri-download-line"></i> ${t('downloads.download_btn', 'Télécharger')}
                        </button>
                    </div>
                `;
                previewDiv.style.display = 'block';

            } catch (error) {
                console.error('Error fetching metadata:', error);
                previewDiv.innerHTML = `<p style="color: #e74c3c; margin-top: 15px;"><i class="ri-error-warning-line"></i> ${t('errors.detect','Erreur lors de l\'analyse')}</p>`;
                previewDiv.style.display = 'block';
            } finally {
                fetchBtn.innerHTML = `<i class="ri-search-line"></i> ${t('editor.analyze_btn','Analyser')}`;
                fetchBtn.disabled = false;
            }
        }

        async function startDownload(url) {
            const user = document.getElementById('downloadUser').value;
            const artist = document.getElementById('metaArtist')?.value.trim() || '';
            const album = document.getElementById('metaAlbum')?.value.trim() || '';

            if (!artist || !album) {
                alert(t('alert.fill_artist_album', "Veuillez remplir le nom de l'artiste et de l'album"));
                return;
            }

            try {
                const formData = new FormData();
                formData.append('url', url);
                formData.append('user', user);
                formData.append('artist_name', artist);
                formData.append('album_name', album);
                formData.append('artist_id', 'new');

                const response = await fetch(`${BASE_PATH}/download_album_api.php?action=start`, {
                    method: 'POST',
                    body: formData
                });
                const result = await response.json();

                if (result.success) {
                    // Clear form
                    document.getElementById('downloadUrl').value = '';
                    document.getElementById('downloadMetadataPreview').style.display = 'none';
                    // Refresh list
                    await refreshDownloadsList();
                } else {
                    alert(t('common.error','Erreur') + ': ' + (result.error || t('errors.download_start', 'Impossible de démarrer le téléchargement')));
                }
            } catch (error) {
                console.error('Error starting download:', error);
                alert(t('errors.download_start', 'Erreur lors du démarrage du téléchargement'));
            }
        }

        async function cancelDownload(downloadId) {
            if (!confirm(t('confirm.cancel_download', 'Annuler ce téléchargement?'))) return;

            try {
                const formData = new FormData();
                formData.append('download_id', downloadId);

                const response = await fetch(`${BASE_PATH}/download_album_api.php?action=cancel`, {
                    method: 'POST',
                    body: formData
                });
                const result = await response.json();

                if (result.success) {
                    await refreshDownloadsList();
                } else {
                    alert(t('common.error','Erreur') + ': ' + (result.error || t('errors.cancel_download', "Impossible d'annuler")));
                }
            } catch (error) {
                console.error('Error cancelling download:', error);
            }
        }

        // Clean up polling when leaving downloads view
        const originalRenderView = renderView;
        renderView = function(view) {
            if (downloadsPollInterval && view !== 'downloads') {
                clearInterval(downloadsPollInterval);
                downloadsPollInterval = null;
            }
            return originalRenderView(view);
        };

        // ============ END DOWNLOADS SECTION ============

        // ============ WEB RADIO SECTION ============
        let webRadioStations = [];
        let webRadioCurrentStation = null;

        async function renderWebRadio() {
            hideAlbumBackground();
            showLoading();
            contentTitle.textContent = t('nav.radio', 'Radio Web');

            try {
                const response = await fetch(`${BASE_PATH}/web_radio_api.php?action=list`);
                const result = await response.json();

                if (!result.success) {
                    showEmpty(t('empty.no_stations', 'Erreur de chargement des stations'));
                    return;
                }

                webRadioStations = result.data.stations || [];
                const genres = {};

                // Group by genre
                webRadioStations.forEach(station => {
                    (station.genres || ['Autre']).forEach(genre => {
                        if (!genres[genre]) genres[genre] = [];
                        genres[genre].push(station);
                    });
                });

                // Sort genres by count
                const sortedGenres = Object.entries(genres).sort((a, b) => b[1].length - a[1].length);

                let html = `
                    <div class="web-radio-container">
                        <div class="web-radio-header">
                            <div class="web-radio-filters">
                                <input type="text" id="radioSearchInput" placeholder="${t('radio.search_ph', 'Rechercher une station...')}" class="search-input">
                                <select id="radioGenreSelect" class="genre-select">
                                    <option value="all">${t('radio.all_genres', 'Tous les genres ({n})').replace('{n}', result.data.count)}</option>
                                    ${sortedGenres.map(([genre, stations]) =>
                                        `<option value="${genre}">${genre} (${stations.length})</option>`
                                    ).join('')}
                                </select>
                            </div>
                            <div class="web-radio-info">
                                ${result.data.count} ${t('radio.station','station')}${result.data.count > 1 ? 's' : ''}
                            </div>
                        </div>

                        <div class="web-radio-now-playing" id="radioNowPlaying" style="display: none;">
                            <div class="now-playing-info">
                                <div class="now-playing-animation">
                                    <span></span><span></span><span></span>
                                </div>
                                <span class="now-playing-name"></span>
                            </div>
                            <button class="stop-radio-btn" onclick="stopWebRadio()">
                                <i class="ri-stop-fill"></i> ${t('radio.stop_btn', 'Arrêter')}
                            </button>
                        </div>

                        <div class="web-radio-grid" id="radioStationsGrid">
                            ${webRadioStations.map(station => renderRadioStationCard(station)).join('')}
                        </div>
                    </div>
                `;

                contentBody.innerHTML = html;

                // Setup search and genre filter
                document.getElementById('radioSearchInput').addEventListener('input', filterRadioStations);
                document.getElementById('radioGenreSelect').addEventListener('change', filterRadioStations);

                // Setup play buttons with event delegation
                document.getElementById('radioStationsGrid').addEventListener('click', function(e) {
                    const btn = e.target.closest('.play-radio-btn');
                    if (btn) {
                        e.preventDefault();
                        e.stopPropagation();
                        const card = btn.closest('.radio-station-card');
                        const stationId = card?.dataset.stationId;
                        console.log('Play button clicked, stationId:', stationId);
                        if (stationId) {
                            playWebRadio(stationId);
                        }
                    }
                });

            } catch (error) {
                console.error('Error loading web radio:', error);
                showEmpty(t('empty.no_stations', 'Erreur de chargement des stations radio'));
            }
        }

        function renderRadioStationCard(station) {
            const streamUrl = station.streams?.[0]?.url || '';
            const format = station.streams?.[0]?.format || '';
            const genres = (station.genres || []).slice(0, 2).join(', ');
            const logo = station.logo || `${BASE_PATH}/assets/radio-placeholder.svg`;

            return `
                <div class="radio-station-card" data-station-id="${station.id}" data-genres="${(station.genres || []).join(',').toLowerCase()}">
                    <div class="radio-station-logo">
                        <img src="${logo}" alt="${station.name}" onerror="this.src='${BASE_PATH}/assets/radio-placeholder.svg'">
                        <button class="play-radio-btn">
                            <i class="ri-play-fill"></i>
                        </button>
                    </div>
                    <div class="radio-station-info">
                        <h3 class="radio-station-name">${station.name}</h3>
                        <p class="radio-station-genre">${genres || station.language || 'Radio'}</p>
                        <span class="radio-station-format">${format}</span>
                    </div>
                </div>
            `;
        }

        function filterRadioStations() {
            const searchTerm = document.getElementById('radioSearchInput').value.toLowerCase();
            const selectedGenre = document.getElementById('radioGenreSelect')?.value || 'all';

            let visibleCount = 0;
            document.querySelectorAll('.radio-station-card').forEach(card => {
                const name = card.querySelector('.radio-station-name').textContent.toLowerCase();
                const genres = card.dataset.genres.toLowerCase();

                const matchesSearch = !searchTerm || name.includes(searchTerm) || genres.includes(searchTerm);
                const matchesGenre = selectedGenre === 'all' || genres.includes(selectedGenre.toLowerCase());

                const visible = matchesSearch && matchesGenre;
                card.style.display = visible ? '' : 'none';
                if (visible) visibleCount++;
            });

            // Update count in header
            const infoEl = document.querySelector('.web-radio-info');
            if (infoEl) {
                infoEl.textContent = `${visibleCount} ${t('radio.station','station')}${visibleCount > 1 ? 's' : ''}`;
            }
        }

        function playWebRadio(stationId) {
            const station = webRadioStations.find(s => s.id === stationId);
            if (!station || !station.streams?.[0]?.url) {
                showToast(t('toast.stream_unavailable', 'Stream non disponible'), 'error');
                return;
            }

            webRadioCurrentStation = station;
            let streamUrl = station.streams[0].url;
            const isMobile = /iPhone|iPad|iPod|Android/i.test(navigator.userAgent);
            const isSecure = streamUrl.startsWith('https://');

            console.log('playWebRadio:', { stationId, name: station.name, streamUrl, isMobile, isSecure });

            // Use proxy for HTTP streams to avoid mixed content issues
            if (!isSecure && window.location.protocol === 'https:') {
                console.log('Using proxy for HTTP stream');
                streamUrl = `${BASE_PATH}/radio_proxy.php?url=${encodeURIComponent(streamUrl)}`;
            }

            // Use the unified player if available
            console.log('unifiedPlayer available:', !!window.gullifyPlayer);
            if (window.gullifyPlayer && window.gullifyPlayer.audio) {
                console.log('Using unified player for radio');
                window.gullifyPlayer.playRadioStream(streamUrl, station.name, station.logo);
            } else {
                console.log('Using fallback audio element (unifiedPlayer not ready)');
                // Fallback: create audio element and simple player UI
                let radioAudio = document.getElementById('webRadioAudio');
                if (!radioAudio) {
                    radioAudio = document.createElement('audio');
                    radioAudio.id = 'webRadioAudio';
                    document.body.appendChild(radioAudio);
                }
                radioAudio.src = streamUrl;
                radioAudio.play().then(() => {
                    showToast(t('toast.now_playing', 'En lecture: {name}').replace('{name}', station.name), 'success');
                }).catch(err => {
                    console.error('Fallback audio play failed:', err);
                    showToast(t('toast.play_retry', 'Erreur de lecture - appuyez pour réessayer'), 'error');
                });
            }

            // Update now playing display
            const nowPlaying = document.getElementById('radioNowPlaying');
            if (nowPlaying) {
                nowPlaying.style.display = 'flex';
                nowPlaying.querySelector('.now-playing-name').textContent = station.name;
            }

            // Update card states
            document.querySelectorAll('.radio-station-card').forEach(card => {
                card.classList.remove('playing');
                if (card.dataset.stationId === stationId) {
                    card.classList.add('playing');
                }
            });

            showToast(t('toast.playing', 'Lecture: {name}').replace('{name}', station.name), 'success');
        }

        function stopWebRadio() {
            webRadioCurrentStation = null;

            // Stop unified player radio
            if (window.gullifyPlayer) {
                window.gullifyPlayer.stopRadio();
            }

            // Stop fallback audio
            const radioAudio = document.getElementById('webRadioAudio');
            if (radioAudio) {
                radioAudio.pause();
                radioAudio.src = '';
            }

            // Update UI
            const nowPlaying = document.getElementById('radioNowPlaying');
            if (nowPlaying) {
                nowPlaying.style.display = 'none';
            }

            document.querySelectorAll('.radio-station-card').forEach(card => {
                card.classList.remove('playing');
            });
        }

        // Expose radio functions globally for onclick handlers
        window.playWebRadio = playWebRadio;
        window.stopWebRadio = stopWebRadio;

        // ============ END WEB RADIO SECTION ============

        async function renderHome() {
            hideAlbumBackground();
            contentTitle.textContent = t('home.title', 'Accueil');

            if (!app.library) {
                showEmpty(t('empty.no_music', 'Aucune musique disponible'));
                return;
            }

            // Actions Rapides
            const actionsHtml = `
                <div style="margin-bottom: 20px;">
                    <h3 style="margin-bottom: 12px; font-size: 18px; font-weight: 600;"><i class="ri-play-circle-line"></i> ${t('home.quick_actions', 'Actions Rapides')}</h3>
                    <div style="display: flex; gap: 12px; flex-wrap: wrap;">
                        <button onclick="window.startRadio()" style="padding: 12px 30px; background: rgba(255, 255, 255, 0.1); color: var(--text-primary); border: 1px solid rgba(255, 255, 255, 0.2); border-radius: 25px; backdrop-filter: blur(10px); -webkit-backdrop-filter: blur(10px); cursor: pointer; font-size: 14px; font-weight: 600; box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1); transition: all 0.2s ease;" onmouseenter="this.style.background='rgba(255, 255, 255, 0.2)'; this.style.transform='translateY(-2px)'; this.style.boxShadow='0 6px 12px rgba(0, 0, 0, 0.15)'" onmouseleave="this.style.background='rgba(255, 255, 255, 0.1)'; this.style.transform='translateY(0)'; this.style.boxShadow='0 4px 6px rgba(0, 0, 0, 0.1)'">
                            <i class="ri-radio-line"></i> Radio
                        </button>
                        <button onclick="playRandomArtist()" style="padding: 12px 30px; background: rgba(255, 255, 255, 0.1); color: var(--text-primary); border: 1px solid rgba(255, 255, 255, 0.2); border-radius: 25px; backdrop-filter: blur(10px); -webkit-backdrop-filter: blur(10px); cursor: pointer; font-size: 14px; font-weight: 600; box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1); transition: all 0.2s ease;" onmouseenter="this.style.background='rgba(255, 255, 255, 0.2)'; this.style.transform='translateY(-2px)'; this.style.boxShadow='0 6px 12px rgba(0, 0, 0, 0.15)'" onmouseleave="this.style.background='rgba(255, 255, 255, 0.1)'; this.style.transform='translateY(0)'; this.style.boxShadow='0 4px 6px rgba(0, 0, 0, 0.1)'">
                            <i class="ri-user-star-line"></i> ${t('home.random_artist', 'Artiste Aléatoire')}
                        </button>
                    </div>
                </div>
            `;

            // Fetch random artists for the home page
            let randomArtistsHtml = '<div class="artist-grid-placeholder"></div>'; // Placeholder
            const fetchRandomArtists = async () => {
                try {
                    const response = await fetch(`${BASE_PATH}/api/library.php?user=${app.currentUser}&action=get_random_artists&limit=12`);
                    const result = await response.json();
                    if (result.error || !result.data.artists) return;

                    const artistsToShow = result.data.artists;
                    const gridHtml = artistsToShow.map(artist => {
                        let imageHtml = '👤';
                        if (artist.imageUrl) {
                            imageHtml = '<img src="' + artist.imageUrl + '" alt="' + artist.name + '" style="width: 100%; height: 100%; object-fit: cover;">';
                        }
                        return '<div class="artist-card" onclick="viewArtist(' + artist.id + ')">' +
                            '<div class="artist-image" id="artist-img-' + artist.id + '" style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); display: flex; align-items: center; justify-content: center; font-size: 48px;">' +
                                imageHtml +
                            '</div>' +
                            '<div class="artist-name">' + artist.name + '</div>' +
                            '<div class="artist-info">' + t('counts.albums_songs', '{a} albums • {s} chansons').replace('{a}', artist.album_count || 0).replace('{s}', artist.song_count || 0) + '</div>' +
                        '</div>';
                    }).join('');

                    const placeholder = contentBody.querySelector('.artist-grid-placeholder');
                    if(placeholder) placeholder.innerHTML = `<div class="artist-grid">${gridHtml}</div>`;

                } catch (e) {
                    console.error("Could not load random artists", e);
                }
            };

            // Placeholder for all sections
            contentBody.innerHTML = `
                <div>
                    ${actionsHtml}
                    <div class="recent-albums-placeholder"></div>
                    <div style="margin-bottom: 20px;">
                        <h3 style="margin-bottom: 12px; font-size: 18px; font-weight: 600;"><i class="ri-lightbulb-line"></i> ${t('home.suggestions', 'Suggestions')}</h3>
                        ${randomArtistsHtml}
                    </div>
                    <div class="popular-placeholder"></div>
                </div>
            `;

            // Asynchronously load all sections
            fetchRandomArtists();

            const fetchPopular = async () => {
                try {
                    const response = await fetch(`${BASE_PATH}/get_popular.php?user=${app.currentUser}&limit=6`);
                    const result = await response.json();
                    let popularHtml = '';
                    if (!result.error && result.data && result.data.length > 0) {
                        // Aggregate songs by artist to get top artists
                        const artistMap = {};
                        result.data.forEach(song => {
                            const aid = song.artistId;
                            if (!artistMap[aid]) {
                                artistMap[aid] = { id: aid, name: song.artistName, imageUrl: 'serve_image.php?artist_id=' + aid, playCount: 0 };
                            }
                            artistMap[aid].playCount += song.playCount || 0;
                        });
                        const topArtists = Object.values(artistMap).sort((a, b) => b.playCount - a.playCount).slice(0, 6);

                        if (topArtists.length > 0) {
                            popularHtml = `
                                <div style="margin-bottom: 20px;">
                                    <h3 style="margin-bottom: 12px; font-size: 18px; font-weight: 600;"><i class="ri-fire-line"></i> ${t('home.popular', 'Plus populaires')}</h3>
                                    <div class="artist-grid" style="grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));">
                                        ${topArtists.map(artist => {
                                            let imageHtml = '👤';
                                            if (artist.imageUrl) {
                                                imageHtml = '<img src="' + artist.imageUrl + '" alt="' + artist.name + '" style="width: 100%; height: 100%; object-fit: cover;">';
                                            }
                                            return `<div class="artist-card" onclick="viewArtist(${artist.id})">
                                                <div class="artist-image" style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); display: flex; align-items: center; justify-content: center; font-size: 36px;">
                                                    ${imageHtml}
                                                </div>
                                                <div class="artist-name">${artist.name}</div>
                                                <div class="artist-info">${t('home.plays', '{n} écoutes').replace('{n}', artist.playCount)}</div>
                                            </div>`;
                                        }).join('')}
                                    </div>
                                </div>
                            `;
                        }
                    }
                    const placeholder = contentBody.querySelector('.popular-placeholder');
                    if(placeholder) placeholder.innerHTML = popularHtml;
                } catch(e) { console.error(e); }
            };

            const fetchRecentAlbums = async () => {
                try {
                    const response = await fetch(`${BASE_PATH}/api/library.php?action=recent_albums&user=${app.currentUser}&days=30&limit=12`);
                    const result = await response.json();
                    let recentAlbumsHtml = '';
                    if (!result.error && result.data && result.data.length > 0) {
                        const recentAlbums = result.data;
                        window.recentAlbumsData = recentAlbums; // Store for play function
                        recentAlbumsHtml = `
                            <div class="nouveautes-section">
                                <div class="nouveautes-header">
                                    <h3><i class="ri-sparkling-line"></i> ${t('nav.new_releases', 'Nouveautés')}</h3>
                                    <button onclick="playRecentAlbums()" class="nouveautes-play-btn">
                                        <i class="ri-play-fill"></i> ${t('home.listen', 'Écouter')}
                                    </button>
                                </div>
                                <div class="nouveautes-slider">
                                    <div class="swiper nouveautes-swiper">
                                        <div class="swiper-wrapper">
                                            ${recentAlbums.map(album => `
                                                    <div class="swiper-slide">
                                                        <div class="nouveaute-card" onclick="viewAlbum(${album.id})">
                                                            <div class="nouveaute-cover">
                                                                <img src="${album.artworkUrl || DEFAULT_ALBUM_IMG}" alt="${escapeHtml(album.name)}">
                                                            </div>
                                                            <div class="nouveaute-title">${escapeHtml(album.name)}</div>
                                                            <div class="nouveaute-artist">${escapeHtml(album.artistName)}</div>
                                                        </div>
                                                    </div>
                                                `).join('')}
                                            <div class="swiper-slide">
                                                <div class="nouveaute-card nouveaute-more" onclick="renderView('new-releases')">
                                                    <div class="nouveaute-cover">
                                                        <div class="nouveaute-plus"><i class="ri-add-line"></i></div>
                                                    </div>
                                                    <div class="nouveaute-title">${t('home.see_all', 'Voir tout')}</div>
                                                    <div class="nouveaute-artist">${t('home.last_30_days', '30 derniers jours')}</div>
                                                </div>
                                            </div>
                                        </div>
                                    </div>
                                    <div class="swiper-button-prev nouveautes-prev"></div>
                                    <div class="swiper-button-next nouveautes-next"></div>
                                </div>
                            </div>
                        `;
                    }
                    const placeholder = contentBody.querySelector('.recent-albums-placeholder');
                    if(placeholder) {
                        placeholder.innerHTML = recentAlbumsHtml;
                        // Initialize Swiper after inserting HTML
                        if (recentAlbumsHtml) {
                            new Swiper('.nouveautes-swiper', {
                                slidesPerView: 'auto',
                                spaceBetween: 16,
                                navigation: {
                                    nextEl: '.nouveautes-next',
                                    prevEl: '.nouveautes-prev',
                                },
                                breakpoints: {
                                    320: { slidesPerView: 2.3 },
                                    480: { slidesPerView: 3.3 },
                                    640: { slidesPerView: 4.3 },
                                    800: { slidesPerView: 5.3 },
                                    1024: { slidesPerView: 6.3 }
                                }
                            });
                        }
                    }
                } catch(e) { console.error(e); }
            };

            fetchRecentAlbums();
            fetchPopular();
        }

        function playRecentTrack(index) {
            const track = app.recentlyPlayed[index];
            if (!track) return;

            app.queue = [track];
            app.currentTrackIndex = 0;
            loadTrack(track);
            renderQueue();
        }

        function playPopularSong(index) {
            if (!window.topSongsData || !window.topSongsData[index]) return;

            const song = window.topSongsData[index];

            // Convert to track format
            const track = {
                id: song.id,
                title: song.title,
                artist: song.artistName,
                album: song.albumName,
                duration: song.duration,
                artwork: song.artwork,
                albumId: song.albumId,
                artistId: song.artistId,
                filePath: null  // Will be loaded by loadTrack
            };

            app.queue = [track];
            app.currentTrackIndex = 0;
            loadTrack(track);
            renderQueue();
        }

        async function playRecentAlbums() {
            if (!window.recentAlbumsData || window.recentAlbumsData.length === 0) {
                showToast(t('toast.no_recent_albums', 'Aucun album récent disponible'), 'error');
                return;
            }

            showToast(t('toast.loading_new', 'Chargement des nouveautés...'), 'info');

            try {
                // Fetch songs from all recent albums
                const allTracks = [];
                for (const album of window.recentAlbumsData) {
                    const response = await fetch(`${BASE_PATH}/api/library.php?user=${app.currentUser}&action=album&id=${album.id}`);
                    const result = await response.json();

                    if (!result.error && result.data && result.data.songs) {
                        const albumData = result.data;
                        for (const song of albumData.songs) {
                            allTracks.push({
                                id: song.id,
                                title: song.title,
                                artist: albumData.artist?.name || album.artistName,
                                album: album.name,
                                duration: song.duration,
                                artworkUrl: album.artworkUrl,
                                filePath: song.file_path || song.filePath,
                                albumId: album.id,
                                artistId: albumData.artist?.id
                            });
                        }
                    }
                }

                if (allTracks.length === 0) {
                    showToast(t('toast.no_songs_found', 'Aucune chanson trouvée'), 'error');
                    return;
                }

                // Shuffle the tracks
                for (let i = allTracks.length - 1; i > 0; i--) {
                    const j = Math.floor(Math.random() * (i + 1));
                    [allTracks[i], allTracks[j]] = [allTracks[j], allTracks[i]];
                }

                app.queue = allTracks;
                app.currentTrackIndex = 0;
                loadTrack(allTracks[0]);
                renderQueue();
                showToast(t('toast.songs_added', '{n} chansons ajoutées').replace('{n}', allTracks.length), 'success');
            } catch (e) {
                console.error('Error playing recent albums:', e);
                showToast(t('toast.load_error', 'Erreur lors du chargement'), 'error');
            }
        }

        function renderArtists() {
            hideAlbumBackground();
            artistManageState = null;
            contentTitle.textContent = t('counts.artists_total','Artistes ({n}/{total})').replace('{n}', app.library.artists.length).replace('{total}', app.library.totalArtists);

            if (!app.library || !app.library.artists || app.library.artists.length === 0) {
                showEmpty(t('empty.no_artists', 'Aucun artiste trouvé'));
                return;
            }

            // Sort artists alphabetically
            const sortedArtists = [...app.library.artists].sort((a, b) =>
                a.name.localeCompare(b.name, 'fr', { sensitivity: 'base' })
            );

            // Get available letters
            const availableLetters = new Set();
            sortedArtists.forEach(artist => {
                const firstLetter = artist.name.charAt(0).toUpperCase();
                if (/[A-Z]/.test(firstLetter)) {
                    availableLetters.add(firstLetter);
                }
            });

            const html = `
                <div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap;margin-bottom:16px;">
                    <button id="manage-artists-btn" onclick="toggleArtistManageMode()" class="rescan-btn" style="font-size:12px;padding:6px 14px;">
                        <i class="ri-edit-box-line"></i> ${t('editor.manage_btn', 'Gérer')}
                    </button>
                    <button id="detect-artist-dupes-btn" onclick="detectArtistDuplicates()" class="rescan-btn" style="font-size:12px;padding:6px 14px;">
                        <i id="detect-artist-dupes-icon" class="ri-search-line"></i> ${t('home.probable_dupes', 'Doublons probables')}
                    </button>
                </div>

                <div id="artist-manage-bar" style="display:none;position:sticky;top:0;z-index:50;background:var(--bg-secondary);border:1px solid var(--border);border-radius:12px;padding:12px 16px;margin-bottom:12px;align-items:center;gap:10px;flex-wrap:wrap;backdrop-filter:blur(10px);">
                    <span id="artist-manage-count" style="color:var(--text-primary);font-size:14px;font-weight:600;flex:1;">${t('common.none_selected', 'Aucun sélectionné')}</span>
                    <button id="rename-artist-btn" onclick="openRenameArtistDialog()" class="rescan-btn" style="font-size:12px;padding:6px 14px;" disabled>
                        <i class="ri-pencil-line"></i> ${t('home.rename', 'Renommer')}
                    </button>
                    <button id="merge-artists-btn" onclick="openMergeArtistsDialog()" class="rescan-btn" style="font-size:12px;padding:6px 14px;background:var(--accent);color:white;" disabled>
                        <i class="ri-git-merge-line"></i> ${t('home.merge', 'Fusionner')}
                    </button>
                    <button id="delete-artists-btn" onclick="deleteSelectedArtists()" class="rescan-btn" style="font-size:12px;padding:6px 14px;background:#c0392b;color:white;" disabled>
                        <i class="ri-delete-bin-line"></i> ${t('common.delete', 'Supprimer')}
                    </button>
                    <button onclick="toggleArtistManageMode()" class="rescan-btn" style="font-size:12px;padding:6px 14px;">
                        <i class="ri-close-line"></i> ${t('editor.done_btn', 'Terminer')}
                    </button>
                </div>

                <div id="artists-duplicates-panel" style="display:none;border:1px solid var(--border);border-radius:10px;margin-bottom:14px;background:var(--bg-secondary);overflow:hidden;"></div>

                <div class="artist-grid" id="artistGrid">
                    ${sortedArtists.map(artist => {
                        const firstLetter = artist.name.charAt(0).toUpperCase();

                        // Use image from API response
                        let imageHtml;
                        if (artist.imageUrl) {
                            imageHtml = '<img src="' + artist.imageUrl + '" alt="' + artist.name + '" style="width: 100%; height: 100%; object-fit: cover;">';
                        } else {
                            imageHtml = '<div style="color: white; font-size: 48px; font-weight: 700;">' + firstLetter + '</div>';
                        }

                        return '<div class="artist-card" data-letter="' + firstLetter + '" data-artist-id="' + artist.id + '" onclick="viewArtist(' + artist.id + ')">' +
                                '<div class="artist-image" id="artist-grid-' + artist.id + '" style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);">' +
                                    imageHtml +
                                '</div>' +
                                '<div class="artist-name">' + artist.name + '</div>' +
                                '<div class="artist-info">' + t('counts.albums_songs','{a} albums • {s} chansons').replace('{a}', artist.albumCount || 0).replace('{s}', artist.songCount || 0) + '</div>' +
                            '</div>';
                    }).join('')}
                </div>
                <div class="alphabet-index" id="alphabetIndex">
                    ${'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('').map(letter => {
                        const isAvailable = availableLetters.has(letter);
                        return `<div class="alphabet-letter ${isAvailable ? '' : 'disabled'}"
                                     data-letter="${letter}"
                                     onclick="${isAvailable ? `scrollToLetter('${letter}')` : ''}"
                                     style="${!isAvailable ? 'opacity: 0.3; cursor: default;' : ''}">
                            ${letter}
                        </div>`;
                    }).join('')}
                </div>
                ${app.hasMoreArtists ? `
                    <div style="text-align: center; padding: 30px;">
                        <button id="loadMoreBtn" onclick="loadMoreArtists()" style="padding: 12px 30px; background: var(--accent); color: white; border: none; border-radius: 25px; cursor: pointer; font-size: 14px; font-weight: 600;">
                            ${t('common.load_more','Charger plus ({n} restants)').replace('{n}', app.library.totalArtists - app.library.artists.length)}
                        </button>
                    </div>
                ` : `
                    <div style="text-align: center; padding: 30px; color: var(--text-secondary);">
                        ${t('common.all_artists_loaded', 'Tous les artistes chargés ✓')}
                    </div>
                `}
            `;

            contentBody.innerHTML = html;

            // Images are now loaded directly from API response, no need to fetch separately
            // app.library.artists.forEach(artist => {
            //     if (!app.imageCache[`artist-${artist.id}`]) {
            //         loadArtistImageForGrid(artist.id);
            //     }
            // });

            // Setup infinite scroll
            setupInfiniteScroll();

            // Setup lazy loading of artist images from YouTube Music
            // Only loads images for visible artists, 2 at a time
            setupArtistImageObserver();
        }

        // Scroll to artists starting with a specific letter
        function scrollToLetter(letter) {
            const firstArtistWithLetter = document.querySelector(`.artist-card[data-letter="${letter}"]`);
            if (firstArtistWithLetter) {
                // Get the content body element
                const contentBodyEl = document.getElementById('contentBody');

                // Calculate the position to scroll to
                const artistCardTop = firstArtistWithLetter.offsetTop;
                const gridTop = document.getElementById('artistGrid').offsetTop;

                // Scroll to position (with some offset for better visibility)
                contentBodyEl.scrollTo({
                    top: artistCardTop + gridTop - 20,
                    behavior: 'smooth'
                });

                // Visual feedback - highlight the letter briefly
                const letterElements = document.querySelectorAll('.alphabet-letter');
                letterElements.forEach(el => el.classList.remove('active'));
                const activeLetter = document.querySelector(`.alphabet-letter[data-letter="${letter}"]`);
                if (activeLetter) {
                    activeLetter.classList.add('active');
                    setTimeout(() => activeLetter.classList.remove('active'), 1000);
                }
            }
        }

        function setupInfiniteScroll() {
            const contentBodyEl = document.getElementById('contentBody');

            // Remove previous scroll handler if exists
            if (app.scrollHandler) {
                contentBodyEl.removeEventListener('scroll', app.scrollHandler);
                app.scrollHandler = null;
                console.log('Removed previous scroll handler');
            }

            // Only add if we're in artists view
            if (app.currentView === 'artists') {
                app.scrollHandler = function(e) {
                    // Verify we're still in artists view
                    if (app.currentView !== 'artists') {
                        console.log('Not in artists view anymore, ignoring scroll');
                        return;
                    }

                    if (!app.hasMoreArtists || app.loadingMore) return;

                    const element = e.target;
                    const scrollBottom = element.scrollHeight - element.scrollTop - element.clientHeight;

                    // Load more when 200px from bottom
                    if (scrollBottom < 200) {
                        console.log('Near bottom, loading more artists');
                        loadMoreArtists();
                    }
                };

                contentBodyEl.addEventListener('scroll', app.scrollHandler);
                console.log('Scroll handler attached for artists view');
            }
        }

        function removeInfiniteScroll() {
            const contentBodyEl = document.getElementById('contentBody');
            if (app.scrollHandler) {
                contentBodyEl.removeEventListener('scroll', app.scrollHandler);
                app.scrollHandler = null;
                console.log('Infinite scroll removed');
            }
        }

        async function renderArtistNews(artistName) {
            const container = document.getElementById('artist-news-container');
            if (!container) return;

            container.innerHTML = '<div class="loading-spinner"></div>';

            try {
                const response = await fetch(`${BASE_PATH}/get_artist_news.php?artist=${encodeURIComponent(artistName)}`);
                const result = await response.json();

                if (!result.success) {
                    container.innerHTML = `<p style="color: var(--text-secondary);">${result.error || t('errors.unknown', 'Erreur inconnue')}</p>`;
                    return;
                }

                const articles = result.news?.articles || [];
                if (articles.length === 0) {
                    container.innerHTML = `<p style="color: var(--text-secondary);">${t('empty.no_news', 'Aucune actualité récente trouvée pour cet artiste.')}</p>`;
                    return;
                }

                const newsHtml = articles.map(article => `
                    <a class="news-item" href="${article.url}" target="_blank" rel="noopener noreferrer">
                        <div class="news-title">${escapeHtml(article.title)}</div>
                        <div class="news-source">${escapeHtml(article.source)} - <span class="news-date">${new Date(article.date).toLocaleDateString()}</span></div>
                    </a>
                `).join('');

                container.innerHTML = newsHtml;

            } catch (error) {
                console.error('Error fetching artist news:', error);
                container.innerHTML = `<p style="color: var(--text-secondary);">${t('errors.artist_news', 'Erreur lors du chargement des actualités.')}</p>`;
            }
        }

        async function viewArtist(artistId) {
            try {
                // Don't hide background yet - we'll show artist background
                // hideAlbumBackground();
                // Remove infinite scroll when leaving artists view
                removeInfiniteScroll();

                // Save current artist view
                localStorage.setItem('musicCurrentView', 'artist');
                localStorage.setItem('musicCurrentArtistId', artistId);

                showLoading();

                // Note: Auto-scan removed - use the "Rescan" button to check for changes
                // This prevents constant refreshes during downloads

                const response = await fetch(`${BASE_PATH}/api/library.php?user=${app.currentUser}&action=artist&id=${artistId}`);
                const result = await response.json();

                if (result.error) {
                    showError(t('errors.load_artist', "Erreur lors du chargement de l'artiste"));
                    return;
                }

                // Get artist info from API response
                const artistData = result.data.artist || {};
                const artist = {
                    id: artistId,
                    name: artistData.name || 'Artiste',
                    imageUrl: artistData.imageUrl || null,
                    genre: artistData.genre || null
                };

                // Filter out albums with no songs
                const albums = (result.data.albums || []).filter(album => album.songCount > 0);
                const totalSongs = result.data.totalSongs || 0;

                // Store for navigation
                window.currentArtist = { id: artistId, name: artist.name };

                contentTitle.textContent = artist.name;

                const html = `
                    <div>
                        <!-- Breadcrumb -->
                        <div style="margin-bottom: 20px;">
                            <button onclick="searchInput.value=''; renderView('artists')" class="back-btn">
                                ${t('artist.back', '← Retour aux artistes')}
                            </button>
                        </div>

                        <div style="display: flex; align-items: center; gap: 20px; margin-bottom: 30px;">
                            <div>
                                <div id="artist-avatar-${artistId}" class="artist-avatar-large" style="cursor:pointer;position:relative;" onclick="openArtistArtworkEditor(${artistId}, '${(artist.imageUrl || '').replace(/'/g, "\\'")}', '${artist.name.replace(/'/g, "\\'")}')">
                                    ${artist.imageUrl ? '<img src="' + artist.imageUrl + '" style="width:100%;height:100%;object-fit:cover;">' : '<span style="color:white;font-size:48px;font-weight:700;">' + artist.name.charAt(0).toUpperCase() + '</span>'}
                                    <div class="artwork-edit-overlay">
                                        <i class="ri-image-edit-line" style="font-size:24px;"></i>
                                        <span style="font-size:11px;margin-top:4px;">${t('common.edit', 'Modifier')}</span>
                                    </div>
                                </div>
                            </div>
                            <div>
                                <h2 style="font-size: 32px; margin-bottom: 10px; color: white; text-shadow: 0 1px 3px rgba(0,0,0,0.8), 0 0 10px rgba(0,0,0,0.5);">${artist.name}</h2>
                                <p style="color: rgba(255,255,255,0.85); font-size: 14px; text-shadow: 0 1px 2px rgba(0,0,0,0.6);">
                                    <span id="artist-stats-${artistId}">${t('counts.albums_songs','{a} albums • {s} chansons').replace('{a}', albums.length).replace('{s}', totalSongs)}</span>
                                    <span id="artist-scan-status-${artistId}" class="artist-scan-indicator" style="display: none; margin-left: 10px;"></span>
                                </p>
                                <div id="artist-genre-display-${artistId}" style="margin-top:8px;display:flex;align-items:center;gap:8px;flex-wrap:wrap;">
                                    ${artist.genre ? `
                                        <span class="genre-badge">${artist.genre}</span>
                                    ` : `
                                        <span style="color:rgba(255,255,255,0.5);font-size:13px;">${t('empty.no_genre', 'Aucun genre')}</span>
                                    `}
                                    <button onclick="editArtistGenre(${artistId}, '${(artist.genre || '').replace(/'/g, "\\'")}')" class="genre-edit-btn" title="Modifier le genre">
                                        <i class="ri-pencil-line"></i>
                                    </button>
                                </div>
                                <div id="artist-genre-edit-${artistId}" style="display:none;margin-top:8px;">
                                    <div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap;">
                                        <select id="genre-select-${artistId}" class="genre-select"></select>
                                        <label style="color:rgba(255,255,255,0.8);font-size:12px;display:flex;align-items:center;gap:4px;cursor:pointer;">
                                            <input type="checkbox" id="genre-apply-albums-${artistId}" checked> ${t('artist.apply_to_albums', 'Appliquer aux albums')}
                                        </label>
                                    </div>
                                    <div style="display:flex;gap:8px;margin-top:8px;">
                                        <button onclick="saveArtistGenre(${artistId})" class="rescan-btn" style="font-size:12px;padding:5px 14px;">
                                            <i class="ri-check-line"></i> ${t('common.save', 'Enregistrer')}
                                        </button>
                                        <button onclick="cancelEditGenre(${artistId})" class="rescan-btn" style="font-size:12px;padding:5px 14px;">
                                            <i class="ri-close-line"></i> ${t('common.cancel', 'Annuler')}
                                        </button>
                                    </div>
                                </div>
                                <div style="display: flex; gap: 10px; margin-top: 15px; flex-wrap: wrap;">
                                    <button onclick="playArtistSongs(${artistId})" style="padding: 12px 30px; background: rgba(255, 255, 255, 0.1); color: white; border: 1px solid rgba(255, 255, 255, 0.2); border-radius: 25px; cursor: pointer; font-size: 14px; font-weight: 600; backdrop-filter: blur(10px); -webkit-backdrop-filter: blur(10px); box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1); transition: all 0.2s ease;" onmouseenter="this.style.background='rgba(255, 255, 255, 0.2)'; this.style.transform='translateY(-2px)'; this.style.boxShadow='0 6px 12px rgba(0, 0, 0, 0.15)'" onmouseleave="this.style.background='rgba(255, 255, 255, 0.1)'; this.style.transform='translateY(0)'; this.style.boxShadow='0 4px 6px rgba(0, 0, 0, 0.1)'">
                                        ${t('common.play_all', '▶ Lire tout')}
                                    </button>
                                    <button id="artist-fav-btn-${artistId}" onclick="toggleArtistFavorite(${artistId})" class="fav-action-btn" title="Ajouter aux favoris">
                                        <i class="ri-heart-line"></i>
                                    </button>
                                    <button onclick="rescanArtist(${artistId})" class="rescan-btn" title="Rechercher nouveaux albums/chansons">
                                        <i class="ri-refresh-line"></i> ${t('artist.rescan', 'Rescan')}
                                    </button>
                                </div>
                            </div>
                        </div>

                        <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:15px;">
                            <h3 style="font-size: 20px; color: white; text-shadow: 0 1px 3px rgba(0,0,0,0.8), 0 0 10px rgba(0,0,0,0.5);">${t('nav.albums', 'Albums')}</h3>
                            ${albums.length > 1 ? `
                            <button id="manage-albums-btn-${artistId}" onclick="toggleAlbumManageMode(${artistId})" class="rescan-btn" style="font-size:12px;padding:5px 14px;">
                                <i class="ri-edit-box-line"></i> ${t('editor.manage_btn', 'Gérer')}
                            </button>` : ''}
                        </div>
                        ${albums.length > 0 ? `
                            <div class="album-grid" id="album-grid-${artistId}">
                                ${albums.map(album => `
                                    <div class="album-card" data-album-id="${album.id}" onclick="viewAlbum(${album.id})">
                                        <div class="album-cover" id="album-cover-${album.id}">
                                            <img src="${album.artworkUrl || DEFAULT_ALBUM_IMG}" alt="${album.name}" style="width: 100%; height: 100%; object-fit: cover;">
                                        </div>
                                        <div class="album-name">${album.name}</div>
                                        <div class="album-info">${album.year || 'N/A'} • ${t('counts.songs','{n} chansons').replace('{n}', album.songCount || 0)}</div>
                                    </div>
                                `).join('')}
                            </div>
                            <div id="album-manage-bar-${artistId}" style="display:none;position:sticky;bottom:80px;z-index:50;background:var(--bg-secondary);border:1px solid var(--border);border-radius:12px;padding:12px 16px;margin-top:12px;align-items:center;gap:10px;flex-wrap:wrap;backdrop-filter:blur(10px);">
                                <span id="album-manage-count-${artistId}" style="color:var(--text-primary);font-size:14px;font-weight:600;flex:1;">${t('common.none_selected', 'Aucun sélectionné')}</span>
                                <button id="rename-album-btn-${artistId}" onclick="openRenameAlbumDialog(${artistId})" class="rescan-btn" style="font-size:12px;padding:6px 14px;" disabled>
                                    <i class="ri-pencil-line"></i> ${t('home.rename', 'Renommer')}
                                </button>
                                <button id="merge-albums-btn-${artistId}" onclick="openMergeAlbumsDialog(${artistId})" class="rescan-btn" style="font-size:12px;padding:6px 14px;background:var(--accent);color:white;" disabled>
                                    <i class="ri-git-merge-line"></i> ${t('home.merge', 'Fusionner')}
                                </button>
                                <button id="delete-albums-btn-${artistId}" onclick="deleteSelectedAlbums(${artistId})" class="rescan-btn" style="font-size:12px;padding:6px 14px;background:#c0392b;color:white;" disabled>
                                    <i class="ri-delete-bin-line"></i> ${t('common.delete', 'Supprimer')}
                                </button>
                                <button onclick="toggleAlbumManageMode(${artistId})" class="rescan-btn" style="font-size:12px;padding:6px 14px;">
                                    <i class="ri-close-line"></i> ${t('editor.done_btn', 'Terminer')}
                                </button>
                            </div>
                        ` : `
                            <div style="padding: 40px; text-align: center; color: var(--text-secondary); background: var(--bg-secondary); border-radius: 12px;">
                                <div style="font-size: 48px; margin-bottom: 16px;">📀</div>
                                <p style="font-size: 16px; margin-bottom: 8px;">${t('artist.no_albums', 'Aucun album trouvé')}</p>
                                ${totalSongs > 0 ? `
                                    <p style="font-size: 14px;">${t('artist.songs_no_albums', 'Cet artiste a {n} chanson(s), mais elles ne sont pas organisées en albums.').replace('{n}', totalSongs)}</p>
                                    <p style="font-size: 14px; margin-top: 8px;">${t('empty.no_songs_library', "Cet artiste n'a pas encore de chansons dans la bibliothèque.")}</p>
                                ` : `
                                    <p style="font-size: 14px;">${t('empty.no_songs_library', "Cet artiste n'a pas encore de chansons dans la bibliothèque.")}</p>
                                `}
                            </div>
                        `}

                        <!-- Artist News Section -->
                        <div class="artist-news-section">
                            <h3 style="margin-bottom: 15px; font-size: 20px; color: white; text-shadow: 0 1px 3px rgba(0,0,0,0.8), 0 0 10px rgba(0,0,0,0.5);">${t('artist.recent_news', 'Actualités Récentes')}</h3>
                            <div id="artist-news-container">
                                <div class="loading-spinner"></div>
                            </div>
                        </div>
                    </div>
                `;

                contentBody.innerHTML = html;

                // Check if artist is favorited
                checkArtistFavorite(artistId);

                if (artist.imageUrl) {
                    showArtistBackground(artist.imageUrl);
                } else {
                    hideAlbumBackground();
                }

                // Album covers are now loaded directly from API response via artworkUrl
                // No need to fetch them separately
                // albums.forEach(album => loadAlbumCover(album.id));

                // Load YouTube Music albums suggestions and artist image
                loadYouTubeAlbumSuggestions(artistId, artist.name, artist.imageUrl, albums);

                // Fetch and render artist news
                renderArtistNews(artist.name);

            } catch (error) {
                console.error('Error loading artist:', error);
                showError(t('errors.load_artist_fail', "Impossible de charger l'artiste"));
            }
        }

        // ── Albums duplicate detection & auto-merge ──────────────────────────────
        async function detectAlbumDuplicates() {
            const btn  = document.getElementById('detect-dupes-btn');
            const icon = document.getElementById('detect-dupes-icon');
            const panel = document.getElementById('albums-duplicates-panel');
            if (!panel) return;

            if (btn)  btn.disabled = true;
            if (icon) icon.className = 'ri-loader-4-line scan-spin-icon';
            panel.style.display = 'block';
            panel.innerHTML = '<div style="padding:14px;color:var(--text-secondary);font-size:13px;">' + t('dupes.analyzing', 'Analyse en cours...') + '</div>';

            try {
                const res    = await fetch(`${BASE_PATH}/api/library.php?action=detect_duplicates&user=${app.currentUser}`);
                const result = await res.json();
                if (result.error) { panel.innerHTML = `<div style="color:var(--error,#e74c3c);padding:14px;">${result.message}</div>`; return; }

                const { groups, total_groups, total_redundant } = result.data;

                if (total_groups === 0) {
                    panel.innerHTML = `
                        <div class="glass-card" style="padding:14px 18px;display:flex;align-items:center;gap:10px;color:var(--text-secondary);font-size:13px;">
                            <i class="ri-checkbox-circle-line" style="color:#2ecc71;font-size:18px;"></i>
                            ${t('dupes.none_clean', 'Aucun doublon détecté — bibliothèque propre !')}
                        </div>`;
                    return;
                }

                const rows = groups.map(g => `
                    <div style="display:flex;align-items:baseline;gap:10px;padding:6px 0;border-bottom:1px solid var(--border);">
                        <span style="color:var(--text-secondary);font-size:12px;min-width:160px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;" title="${escapeHtml(g.artist_name)}">${escapeHtml(g.artist_name)}</span>
                        <span style="flex:1;font-size:13px;" title="${g.album_names.map(n => escapeHtml(n)).join(' / ')}">${escapeHtml(g.canonical_name)}</span>
                        <span style="color:var(--accent);font-size:12px;white-space:nowrap;">${t('dupes.versions_songs', '{count} versions • {s} chansons').replace('{count}', g.album_count).replace('{s}', g.total_songs)}</span>
                    </div>
                `).join('');

                panel.innerHTML = `
                    <div class="glass-card" style="padding:16px 18px;">
                        <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:14px;gap:12px;flex-wrap:wrap;">
                            <div>
                                <span style="font-weight:600;font-size:14px;">${t('dupes.groups_found', '{n} groupe(s) de doublons trouvés').replace('{n}', total_groups)}</span>
                                <span style="color:var(--text-secondary);font-size:12px;margin-left:8px;">${t('dupes.redundant', '({n} album(s) redondant(s) à supprimer)').replace('{n}', total_redundant)}</span>
                            </div>
                            <button onclick="autoMergeDuplicates()" id="auto-merge-btn"
                                style="background:var(--accent);color:white;border:none;border-radius:8px;padding:8px 18px;cursor:pointer;font-size:13px;font-weight:600;white-space:nowrap;">
                                <i class="ri-git-merge-line"></i> Tout fusionner + mettre à jour les tags
                            </button>
                        </div>
                        <div style="max-height:220px;overflow-y:auto;font-size:13px;">
                            <div style="display:flex;gap:10px;padding:4px 0 8px;border-bottom:2px solid var(--border);font-size:11px;color:var(--text-secondary);font-weight:600;text-transform:uppercase;letter-spacing:.05em;">
                                <span style="min-width:160px;">${t('dupes.col_artist', 'Artiste')}</span><span style="flex:1;">${t('dupes.col_album', 'Album (nom retenu)')}</span><span>${t('dupes.col_detail', 'Détail')}</span>
                            </div>
                            ${rows}
                        </div>
                    </div>`;
            } catch (e) {
                console.error('detect duplicates error:', e);
                panel.innerHTML = '<div style="color:var(--error,#e74c3c);padding:14px;">' + t('errors.detect', 'Erreur lors de la détection.') + '</div>';
            } finally {
                if (btn)  btn.disabled = false;
                if (icon) icon.className = 'ri-scan-line';
            }
        }

        async function autoMergeDuplicates() {
            const btn = document.getElementById('auto-merge-btn');
            if (!confirm(t('confirm.merge_duplicates','Fusionner tous les doublons et mettre à jour les tags ID3 ?\nCette opération peut prendre quelques instants.'))) return;

            if (btn) { btn.disabled = true; btn.innerHTML = `<i class="ri-loader-4-line scan-spin-icon"></i> ${t('editor.merging','Fusion en cours...')}`; }

            try {
                const fd = new FormData();
                fd.append('user', app.currentUser);
                const res    = await fetch(`${BASE_PATH}/api/library.php?action=auto_merge_duplicates`, { method: 'POST', body: fd });
                const result = await res.json();
                if (result.error) { alert(t('common.error_prefix','Erreur : ') + result.message); return; }

                const d = result.data;
                let msg = t('dupes.merge_complete', 'Fusion terminée : {n} groupe(s) traité(s).').replace('{n}', d.groups_merged);
                if (d.tags_updated > 0) msg += '\n' + t('dupes.tags_updated', '{n} tag(s) ID3 mis à jour.').replace('{n}', d.tags_updated);
                if (d.tags_failed  > 0) msg += '\n' + t('dupes.tags_failed', '⚠ {n} fichier(s) non modifiés.').replace('{n}', d.tags_failed);
                alert(msg);

                // Refresh albums view
                renderAlbums(true);
            } catch (e) {
                console.error('auto merge error:', e);
                alert(t('errors.merge','Erreur lors de la fusion.'));
                if (btn) { btn.disabled = false; btn.innerHTML = `<i class="ri-git-merge-line"></i> ${t('editor.merge_btn','Tout fusionner + mettre à jour les tags')}`; }
            }
        }

        // ── Compilation detection & merge ────────────────────────────────────────

        async function detectCompilations() {
            const btn   = document.getElementById('detect-compilations-btn');
            const icon  = document.getElementById('detect-comp-icon');
            const panel = document.getElementById('albums-compilations-panel');
            if (!panel) return;

            if (btn) btn.disabled = true;
            if (icon) icon.className = 'ri-loader-4-line scan-spin-icon';

            try {
                const res    = await fetch(`${BASE_PATH}/api/library.php?action=detect_compilations&user=${encodeURIComponent(app.currentUser)}&threshold=3`);
                const result = await res.json();

                if (result.error) { alert(t('common.error_prefix','Erreur : ') + result.message); return; }

                const list = result.data.compilations;
                if (list.length === 0) {
                    panel.style.display = 'block';
                    panel.innerHTML = `<div class="glass-card" style="padding:14px 18px;color:var(--text-secondary);font-size:13px;">${t('empty.no_compilations','Aucune compilation détectée (seuil : 3 artistes).')}</div>`;
                    return;
                }

                panel.style.display = 'block';
                panel.innerHTML = `
                    <div class="glass-card" style="padding:16px 20px;">
                        <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:14px;flex-wrap:wrap;gap:10px;">
                            <span style="font-weight:600;font-size:14px;color:var(--text-primary);">
                                <i class="ri-group-line" style="color:var(--accent);"></i>
                                ${t('compilations.detected', '{n} compilation(s) détectée(s)').replace('{n}', list.length)}
                            </span>
                            <button onclick="mergeAllCompilations()" class="rescan-btn" style="font-size:12px;padding:6px 14px;background:var(--accent);color:white;">
                                <i class="ri-git-merge-line"></i> ${t('compilations.merge_all_btn', 'Tout fusionner sous "Various Artists"')}
                            </button>
                        </div>
                        ${list.map((c, i) => `
                            <div style="border-top:1px solid var(--border);padding:12px 0;display:flex;align-items:flex-start;gap:12px;flex-wrap:wrap;">
                                <div style="flex:1;min-width:200px;">
                                    <div style="font-weight:600;font-size:13px;color:var(--text-primary);">${escapeHtml(c.album_name)}</div>
                                    <div style="font-size:11px;color:var(--text-secondary);margin-top:3px;">
                                        ${t('compilations.artists_songs', '{a} artistes · {s} chanson(s)').replace('{a}', c.artist_count).replace('{s}', c.total_songs)}
                                    </div>
                                    <div style="font-size:11px;color:var(--text-secondary);margin-top:2px;">${c.artist_names.slice(0,5).map(a => escapeHtml(a)).join(', ')}${c.artist_names.length > 5 ? '…' : ''}</div>
                                </div>
                                <div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap;">
                                    <input type="text" id="comp-artist-${i}" value="Various Artists"
                                        style="width:140px;padding:5px 8px;border-radius:6px;border:1px solid var(--border);background:var(--bg-tertiary);color:var(--text-primary);font-size:12px;">
                                    <button onclick="mergeCompilation(${i})" class="rescan-btn" style="font-size:12px;padding:5px 12px;">
                                        <i class="ri-git-merge-line"></i> Fusionner
                                    </button>
                                </div>
                            </div>
                        `).join('')}
                    </div>
                `;
                // Store list for use by mergeCompilation()
                panel._compilationList = list;
            } catch (e) {
                alert(t('common.error_prefix','Erreur : ') + e.message);
            } finally {
                if (btn)  btn.disabled = false;
                if (icon) icon.className = 'ri-group-line';
            }
        }

        async function mergeCompilation(index) {
            const panel = document.getElementById('albums-compilations-panel');
            const list  = panel?._compilationList;
            if (!list?.[index]) return;

            const c          = list[index];
            const artistName = document.getElementById(`comp-artist-${index}`)?.value.trim() || 'Various Artists';

            const confirmed = confirm(
                t('compilations.confirm_merge', 'Fusionner "{album}" ({a} artistes, {s} chansons) sous "{artist}" ?\nLes tags ID3 album_artist seront mis à jour.')
                    .replace('{album}', c.album_name)
                    .replace('{a}', c.artist_count)
                    .replace('{s}', c.total_songs)
                    .replace('{artist}', artistName)
            );
            if (!confirmed) return;

            try {
                const res = await fetch(`${BASE_PATH}/api/library.php?action=merge_compilation&user=${encodeURIComponent(app.currentUser)}`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ album_ids: c.album_ids.map(Number), artist_name: artistName, album_name: c.album_name }),
                });
                const result = await res.json();
                if (result.error) { alert(t('common.error_prefix','Erreur : ') + result.message); return; }

                const d = result.data;
                let msg = t('compilations.merge_result', '"{name}" fusionné sous "{artist}" ({n} chansons).').replace('{name}', d.name).replace('{artist}', d.artist).replace('{n}', d.songs);
                if (d.tags_updated > 0) msg += '\n' + t('dupes.tags_updated', '{n} tag(s) ID3 mis à jour.').replace('{n}', d.tags_updated);
                if (d.tags_failed  > 0) msg += '\n' + t('dupes.tags_failed', '⚠ {n} fichier(s) non modifiés.').replace('{n}', d.tags_failed);
                alert(msg);

                renderAlbums(true);
            } catch (e) {
                alert(t('common.error_prefix','Erreur : ') + e.message);
            }
        }

        async function mergeAllCompilations() {
            const panel = document.getElementById('albums-compilations-panel');
            const list  = panel?._compilationList;
            if (!list?.length) return;

            if (!confirm(t('compilations.confirm_merge_all', 'Fusionner {n} compilation(s) sous "Various Artists" ?\nLes tags ID3 album_artist seront mis à jour.').replace('{n}', list.length))) return;

            let done = 0, failed = 0;
            for (let i = 0; i < list.length; i++) {
                const artistInput = document.getElementById(`comp-artist-${i}`);
                const artistName  = artistInput?.value.trim() || 'Various Artists';
                const c = list[i];
                try {
                    const res = await fetch(`${BASE_PATH}/api/library.php?action=merge_compilation&user=${encodeURIComponent(app.currentUser)}`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ album_ids: c.album_ids.map(Number), artist_name: artistName, album_name: c.album_name }),
                    });
                    const result = await res.json();
                    if (result.error) failed++; else done++;
                } catch { failed++; }
            }
            alert(t('compilations.merge_all_result', '{done} compilation(s) fusionnée(s).').replace('{done}', done) + (failed ? '\n' + t('dupes.tags_failed', '⚠ {n} fichier(s) non modifiés.').replace('{n}', failed) : ''));
            renderAlbums(true);
        }

        // ── Albums view state ────────────────────────────────────────────────────
        let albumsViewState = { albums: [], total: 0, offset: 0, limit: 48, sort: 'name', search: '', loading: false };
        let albumsSearchTimer = null;

        function albumsSearchDebounce(val) {
            clearTimeout(albumsSearchTimer);
            albumsSearchTimer = setTimeout(() => {
                albumsViewState.search = val;
                renderAlbums(true);
            }, 400);
        }

        function renderAlbumCards(albums) {
            return albums.map(album => `
                <div class="artist-card" onclick="viewAlbum(${album.id})" style="cursor:pointer;" title="${escapeHtml(album.name)}">
                    <div class="artist-image" style="border-radius:8px;overflow:hidden;">
                        <img src="${album.artworkUrl || DEFAULT_ALBUM_IMG}" alt="${escapeHtml(album.name)}" style="width:100%;height:100%;object-fit:cover;" loading="lazy">
                    </div>
                    <div class="artist-name" style="font-size:13px;margin-top:8px;">${escapeHtml(album.name)}</div>
                    <div class="artist-info" style="font-size:11px;">${escapeHtml(album.artistName)}${album.year ? ' • ' + album.year : ''}</div>
                </div>
            `).join('');
        }

        async function renderAlbums(reset = true) {
            hideAlbumBackground();

            if (reset) {
                albumsViewState.albums  = [];
                albumsViewState.offset  = 0;
                const sortEl = document.getElementById('albums-sort-select');
                if (sortEl) albumsViewState.sort = sortEl.value;
                showLoading();
            }

            if (albumsViewState.loading) return;
            albumsViewState.loading = true;

            try {
                const params = new URLSearchParams({
                    action: 'get_all_albums',
                    user:   app.currentUser,
                    limit:  albumsViewState.limit,
                    offset: albumsViewState.offset,
                    sort:   albumsViewState.sort,
                    search: albumsViewState.search,
                });
                const res    = await fetch(`${BASE_PATH}/api/library.php?${params}`);
                const result = await res.json();
                if (result.error) { showError(t('errors.load_albums', 'Erreur lors du chargement des albums.')); return; }

                const { albums, total } = result.data;
                albumsViewState.albums  = reset ? albums : [...albumsViewState.albums, ...albums];
                albumsViewState.total   = total;
                albumsViewState.offset += albums.length;

                const hasMore = albumsViewState.offset < total;

                if (reset) {
                    contentTitle.textContent = t('counts.albums_total','Albums ({n})').replace('{n}', total);
                    contentBody.innerHTML = `
                        <div style="display:flex;gap:12px;align-items:center;margin-bottom:16px;flex-wrap:wrap;">
                            <select id="albums-sort-select" onchange="albumsViewState.sort=this.value; renderAlbums(true)"
                                style="background:var(--surface);color:var(--text-primary);border:1px solid var(--border);border-radius:8px;padding:6px 12px;font-size:13px;cursor:pointer;">
                                <option value="name">${t('album.sort_name', 'Par nom')}</option>
                                <option value="artist">${t('album.sort_artist', 'Par artiste')}</option>
                                <option value="year">${t('album.sort_year', 'Par année')}</option>
                                <option value="recent">${t('album.sort_recent', 'Récemment ajoutés')}</option>
                            </select>
                            <input id="albums-search" type="text" placeholder="${t('album.search_placeholder', 'Rechercher un album ou artiste...')}"
                                value="${escapeHtml(albumsViewState.search)}"
                                oninput="albumsSearchDebounce(this.value)"
                                style="background:var(--surface);color:var(--text-primary);border:1px solid var(--border);border-radius:8px;padding:6px 12px;font-size:13px;flex:1;min-width:180px;outline:none;">
                            <span style="color:var(--text-secondary);font-size:13px;white-space:nowrap;">${total} albums</span>
                            <button id="detect-dupes-btn" onclick="detectAlbumDuplicates()" class="rescan-btn" style="font-size:12px;padding:6px 14px;white-space:nowrap;">
                                <i class="ri-scan-line" id="detect-dupes-icon"></i> ${t('album.detect_dupes', 'Détecter les doublons')}
                            </button>
                            <button id="detect-compilations-btn" onclick="detectCompilations()" class="rescan-btn" style="font-size:12px;padding:6px 14px;white-space:nowrap;">
                                <i class="ri-group-line" id="detect-comp-icon"></i> ${t('album.compilations_btn', 'Compilations')}
                            </button>
                        </div>
                        <div id="albums-duplicates-panel" style="display:none;margin-bottom:20px;"></div>
                        <div id="albums-compilations-panel" style="display:none;margin-bottom:20px;"></div>
                        <div class="album-grid" id="albums-grid" style="grid-template-columns:repeat(auto-fill,minmax(140px,1fr));">
                            ${renderAlbumCards(albums)}
                        </div>
                        <div id="albums-load-more" style="text-align:center;padding:24px;display:${hasMore ? 'block' : 'none'};">
                            <button onclick="renderAlbums(false)"
                                style="padding:10px 28px;background:var(--accent);color:white;border:none;border-radius:25px;cursor:pointer;font-size:14px;font-weight:600;">
                                ${t('common.load_more', 'Charger plus ({n} restants)').replace('{n}', total - albumsViewState.offset)}
                            </button>
                        </div>
                    `;
                    document.getElementById('albums-sort-select').value = albumsViewState.sort;
                } else {
                    const grid = document.getElementById('albums-grid');
                    if (grid) grid.insertAdjacentHTML('beforeend', renderAlbumCards(albums));
                    const loadMore = document.getElementById('albums-load-more');
                    if (loadMore) {
                        if (!hasMore) {
                            loadMore.style.display = 'none';
                        } else {
                            loadMore.innerHTML = `<button onclick="renderAlbums(false)"
                                style="padding:10px 28px;background:var(--accent);color:white;border:none;border-radius:25px;cursor:pointer;font-size:14px;font-weight:600;">
                                ${t('common.load_more', 'Charger plus ({n} restants)').replace('{n}', total - albumsViewState.offset)}
                            </button>`;
                        }
                    }
                }
            } catch (e) {
                console.error('Error loading albums:', e);
                showError(t('errors.load_albums', 'Erreur lors du chargement des albums.'));
            } finally {
                albumsViewState.loading = false;
            }
        }

        async function viewAlbum(albumId) {
            songManageState = null;
            try {
                // Remove infinite scroll when leaving artists view
                removeInfiniteScroll();

                // Save current album view
                localStorage.setItem('musicCurrentView', 'album');
                localStorage.setItem('musicCurrentAlbumId', albumId);

                showLoading();
                const response = await fetch(`${BASE_PATH}/api/library.php?user=${app.currentUser}&action=album&id=${albumId}`);
                const result = await response.json();

                if (result.error) {
                    showError(t('errors.load_album', "Erreur lors du chargement de l'album"));
                    return;
                }

                const albumData = result.data;
                const songs = albumData.songs || [];

                contentTitle.textContent = albumData.name;

                // Use album's artist for back button
                const backArtist = albumData.artist || window.currentArtist;

                const html = `
                    <div>
                        <!-- Breadcrumb -->
                        <div style="margin-bottom: 20px;">
                            ${backArtist ? `
                                <button onclick="viewArtist(${backArtist.id})" class="back-btn">
                                    ${t('album.back_to', '← Retour à {name}').replace('{name}', backArtist.name)}
                                </button>
                            ` : `
                                <button onclick="searchInput.value=''; renderView('artists')" class="back-btn">
                                    ${t('artist.back', '← Retour aux artistes')}
                                </button>
                            `}
                        </div>

                        <div class="album-header-container">
                            <div id="album-cover-large-${albumId}" class="album-cover-large" style="position:relative;cursor:pointer;" onclick="openArtworkEditor(${albumId}, '${(albumData.artworkUrl || DEFAULT_ALBUM_IMG).replace(/'/g, "\\'")}', '${(albumData.artist?.name || '').replace(/'/g, "\\'")}', '${albumData.name.replace(/'/g, "\\'")}')">
                                <img src="${albumData.artworkUrl || DEFAULT_ALBUM_IMG}" alt="${albumData.name}" style="width:100%; height:100%; object-fit:cover;">
                                <div class="artwork-edit-overlay">
                                    <i class="ri-image-edit-line" style="font-size:28px;"></i>
                                    <span style="font-size:12px;margin-top:4px;">${t('common.edit', 'Modifier')}</span>
                                </div>
                            </div>
                            <div class="album-header-info">
                                <p style="color: rgba(255,255,255,0.7); font-size: 11px; text-transform: uppercase; font-weight: 600; margin-bottom: 5px;">${t('album.label', 'Album')}</p>
                                <h2 class="album-title">${albumData.name}</h2>
                                <p style="color: rgba(255,255,255,0.85); font-size: 13px; margin-bottom: 15px;">${albumData.artist.name || t('common.unknown_artist','Artiste inconnu')} • ${albumData.year || 'N/A'} • ${t('counts.songs','{n} chansons').replace('{n}', songs.length)}</p>
                                <div style="display: flex; gap: 10px; flex-wrap: wrap;">
                                    <button onclick="playAlbum(${albumId})" class="album-action-btn album-play-btn">
                                        <i class="ri-play-fill"></i> ${t('album.play', 'Lire')}
                                    </button>
                                    <button onclick="shuffleAlbum(${albumId})" class="album-action-btn album-shuffle-btn">
                                        <i class="ri-shuffle-line"></i> ${t('player.shuffle', 'Aléatoire')}
                                    </button>
                                    <button id="album-fav-btn-${albumId}" onclick="toggleAlbumFavorite(${albumId})" class="album-action-btn fav-action-btn" title="Ajouter aux favoris">
                                        <i class="ri-heart-line"></i>
                                    </button>
                                    <button onclick="openEditAlbumModal(${albumId})" class="album-action-btn album-edit-btn">
                                        <i class="ri-edit-line"></i> ${t('album.edit', 'Éditer')}
                                    </button>
                                    <button id="manage-songs-btn-${albumId}" onclick="toggleSongManageMode(${albumId})" class="album-action-btn" style="background:var(--bg-tertiary);color:var(--text-primary);">
                                        <i class="ri-checkbox-multiple-line"></i> ${t('editor.manage_btn', 'Gérer')}
                                    </button>
                                </div>
                            </div>
                        </div>

                        <div id="song-manage-bar-${albumId}" style="display:none;position:sticky;top:0;z-index:50;background:var(--bg-secondary);border:1px solid var(--border);border-radius:12px;padding:10px 16px;margin-bottom:10px;align-items:center;gap:10px;flex-wrap:wrap;backdrop-filter:blur(10px);">
                            <span id="song-manage-count-${albumId}" style="color:var(--text-primary);font-size:14px;font-weight:600;flex:1;">${t('common.none_selected_f', 'Aucune sélectionnée')}</span>
                            <button id="delete-songs-btn-${albumId}" onclick="deleteSelectedSongs(${albumId})" class="rescan-btn" style="font-size:12px;padding:6px 14px;background:#c0392b;color:white;" disabled>
                                <i class="ri-delete-bin-line"></i> ${t('common.delete', 'Supprimer')}
                            </button>
                            <button onclick="toggleSongManageMode(${albumId})" class="rescan-btn" style="font-size:12px;padding:6px 14px;">
                                <i class="ri-close-line"></i> ${t('editor.done_btn', 'Terminer')}
                            </button>
                        </div>

                        <div class="song-list" id="song-list-${albumId}">
                            ${songs.map((song, index) => `
                                <div class="song-item" data-song-id="${song.id}" onclick="playSongFromAlbum(${albumId}, ${index})" oncontextmenu="showContextMenu(event, ${song.id})">
                                    <div class="song-number">${song.trackNumber || index + 1}</div>
                                    <div class="song-play-icon">▶</div>
                                    <div class="song-thumbnail" id="song-thumb-${song.id}">
                                        <img src="${albumData.artworkUrl || DEFAULT_ALBUM_IMG}" alt="Song" style="width:100%; height:100%; object-fit:cover;">
                                    </div>
                                    <div class="song-info">
                                        <div class="song-title">${song.title}</div>
                                        <div class="song-artist">${escapeHtml(song.artistName || albumData.artist.name || t('common.unknown_artist', 'Artiste inconnu'))}</div>
                                    </div>
                                    <div class="song-duration">${formatDuration(song.duration)}</div>
                                    <div class="song-actions">
                                        <button class="song-action-btn favorite-btn ${app.favorites.includes(song.id) ? 'active' : ''}" data-song-id="${song.id}" onclick="event.stopPropagation(); toggleFavorite(${song.id})" title="Favoris">
                                            <i class="${app.favorites.includes(song.id) ? 'ri-heart-fill' : 'ri-heart-line'}"></i>
                                        </button>
                                        <button class="song-action-btn" onclick="event.stopPropagation(); addSongToQueueById(${song.id})" title="${t('context_menu.add_to_queue', 'Ajouter à la file')}">
                                            <i class="ri-add-line"></i>
                                        </button>
                                    </div>
                                </div>
                            `).join('')}
                        </div>
                    </div>
                `;

                contentBody.innerHTML = html;

                // Check if album is favorited
                checkAlbumFavorite(albumId);

                if (albumData.artworkUrl) {
                    showAlbumBackground(albumData.artworkUrl);
                } else {
                    hideAlbumBackground();
                }

                // Store album data for playback
                window.currentAlbumData = albumData;
            } catch (error) {
                console.error('Error loading album:', error);
                showError(t('errors.load_album_fail', "Impossible de charger l'album"));
            }
        }

        function renderSongs() {
            contentTitle.textContent = t('nav.songs', 'Chansons');

            const html = `
                <div style="text-align: center; padding: 60px 20px;">
                    <div style="font-size: 64px; margin-bottom: 20px;">🎵</div>
                    <h3 style="margin-bottom: 10px; font-size: 20px;">${t('songs.view_title', 'Vue Chansons')}</h3>
                    <p style="color: var(--text-secondary); margin-bottom: 30px;">
                        ${app.library ? t('songs.library_count', 'Votre bibliothèque contient {n} chansons !').replace('{n}', `<strong>${app.library.totalSongs.toLocaleString()}</strong>`) + '<br>' : ''}
                        ${t('songs.browse_hint', 'Pour écouter vos chansons, naviguez dans les Artistes puis sélectionnez un album.')}
                    </p>
                    <div style="display: flex; gap: 15px; justify-content: center; flex-wrap: wrap;">
                        <button onclick="window.startRadio()" style="padding: 12px 30px; background: rgba(255, 255, 255, 0.1); color: var(--text-primary); border: 1px solid rgba(255, 255, 255, 0.2); border-radius: 25px; backdrop-filter: blur(10px); -webkit-backdrop-filter: blur(10px); cursor: pointer; font-size: 14px; font-weight: 600; box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1); transition: all 0.2s ease;" onmouseenter="this.style.background='rgba(255, 255, 255, 0.2)'; this.style.transform='translateY(-2px)'; this.style.boxShadow='0 6px 12px rgba(0, 0, 0, 0.15)'" onmouseleave="this.style.background='rgba(255, 255, 255, 0.1)'; this.style.transform='translateY(0)'; this.style.boxShadow='0 4px 6px rgba(0, 0, 0, 0.1)'">
                            📻 Radio
                        </button>
                        <button onclick="renderView('artists')" style="padding: 12px 30px; background: rgba(255, 255, 255, 0.1); color: var(--text-primary); border: 1px solid rgba(255, 255, 255, 0.2); border-radius: 25px; backdrop-filter: blur(10px); -webkit-backdrop-filter: blur(10px); cursor: pointer; font-size: 14px; font-weight: 600; box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1); transition: all 0.2s ease;" onmouseenter="this.style.background='rgba(255, 255, 255, 0.2)'; this.style.transform='translateY(-2px)'; this.style.boxShadow='0 6px 12px rgba(0, 0, 0, 0.15)'" onmouseleave="this.style.background='rgba(255, 255, 255, 0.1)'; this.style.transform='translateY(0)'; this.style.boxShadow='0 4px 6px rgba(0, 0, 0, 0.1)'">
                            👤 ${t('songs.see_artists', 'Voir les Artistes')}
                        </button>
                    </div>
                </div>
            `;

            contentBody.innerHTML = html;
        }

        // Utilitaires d'affichage
        function showLoading() {
            contentBody.innerHTML = `
                <div class="loading">
                    <div class="loading-spinner"></div>
                    <p>${t('common.loading', 'Chargement...')}</p>
                </div>
            `;
        }

        function showEmpty(message) {
            contentBody.innerHTML = `
                <div class="empty-state">
                    <div class="empty-state-icon">🎵</div>
                    <p>${message}</p>
                </div>
            `;
        }

        function showError(message, retryAction = null) {
            const retryButton = retryAction ? `
                <button onclick="${retryAction}" style="margin-top: 20px; padding: 12px 30px; background: var(--accent); color: white; border: none; border-radius: 25px; cursor: pointer; font-size: 14px; font-weight: 600;">
                    ${t('common.retry', '🔄 Réessayer')}
                </button>
            ` : '';

            contentBody.innerHTML = `
                <div class="empty-state">
                    <div class="empty-state-icon">⚠️</div>
                    <p style="color: var(--accent); margin-bottom: 10px; font-weight: 600;">${message}</p>
                    <p style="color: var(--text-secondary); font-size: 14px;">
                        ${t('common.check_connection', 'Vérifiez votre connexion ou réessayez plus tard.')}
                    </p>
                    ${retryButton}
                </div>
            `;
        }

        // Formatage
        function formatDuration(seconds) {
            if (!seconds || seconds === 0) return '0:00';
            const mins = Math.floor(seconds / 60);
            const secs = Math.floor(seconds % 60);
            return `${mins}:${secs.toString().padStart(2, '0')}`;
        }

        // Fonctions utilitaires
        function escapeHtml(text) {
            if (!text) return '';
            return String(text)
                .replace(/&/g, '&amp;')
                .replace(/</g, '&lt;')
                .replace(/>/g, '&gt;')
                .replace(/"/g, '&quot;');
        }
        function jsStr(text) {
            return escapeHtml(text).replace(/'/g, "\\'");
        }

        // ============================================
        // Artist Auto-Scan Functions
        // ============================================

        /**
         * Scan an artist's folder in the background and update UI if changes are found
         */
        async function scanArtistInBackground(artistId) {
            const statusEl = document.getElementById(`artist-scan-status-${artistId}`);
            const statsEl = document.getElementById(`artist-stats-${artistId}`);

            if (statusEl) {
                statusEl.style.display = 'inline-flex';
                statusEl.innerHTML = `<span class="scan-spinner"></span> ${t('editor.sync','Synchronisation...')}`;
            }

            try {
                const response = await fetch(`${BASE_PATH}/scan_artist_api.php?artist_id=${artistId}&user=${app.currentUser}`);
                const result = await response.json();

                if (result.success && result.data.has_changes) {
                    const changes = result.data.changes;
                    const summary = result.data.summary;

                    // Build change notification
                    let changeText = [];
                    if (summary.new_albums > 0) changeText.push(`+${summary.new_albums} album${summary.new_albums > 1 ? 's' : ''}`);
                    if (summary.new_songs > 0) changeText.push(`+${summary.new_songs} chanson${summary.new_songs > 1 ? 's' : ''}`);
                    if (summary.removed_songs > 0) changeText.push(`-${summary.removed_songs} chanson${summary.removed_songs > 1 ? 's' : ''}`);
                    if (summary.updated_songs > 0) changeText.push(`${summary.updated_songs} modifié${summary.updated_songs > 1 ? 's' : ''}`);

                    if (statusEl) {
                        statusEl.innerHTML = `<span style="color: var(--te-success);">✓</span> ${changeText.join(', ')}`;
                        statusEl.style.color = 'var(--te-success)';
                    }

                    // Show toast notification
                    showToast(`${t('toast.library_updated', 'Bibliothèque mise à jour !')}: ${changeText.join(', ')}`, 'success');

                    // Reload artist page after a short delay to show updated data
                    // BUT only if user is still on this artist's page
                    setTimeout(() => {
                        if (statusEl) statusEl.style.display = 'none';

                        // Check if user is still viewing this artist
                        const currentView = localStorage.getItem('musicCurrentView');
                        const currentArtistId = localStorage.getItem('musicCurrentArtistId');

                        if (currentView === 'artist' && parseInt(currentArtistId) === artistId) {
                            // Refresh artist data to show updates
                            viewArtist(artistId);
                        }
                    }, 2000);

                } else {
                    // No changes
                    if (statusEl) {
                        statusEl.innerHTML = `<span style="color: var(--te-success);">✓</span> ${t('editor.up_to_date','À jour')}`;
                        setTimeout(() => {
                            statusEl.style.display = 'none';
                        }, 2000);
                    }
                }

            } catch (error) {
                console.error('Artist scan error:', error);
                if (statusEl) {
                    statusEl.innerHTML = `<span style="color: var(--te-danger);">⚠</span> ${t('errors.sync','Erreur sync')}`;
                    setTimeout(() => {
                        statusEl.style.display = 'none';
                    }, 3000);
                }
            }
        }

        /**
         * Manual rescan button for artist page
         */
        async function rescanArtist(artistId) {
            const btn = event?.target;
            if (btn) {
                btn.disabled = true;
                btn.innerHTML = t('scan.in_progress','🔄 Scan en cours...');
            }

            await scanArtistInBackground(artistId);

            if (btn) {
                btn.disabled = false;
                btn.innerHTML = '🔄 Rescan';
            }
        }

        // ========== ARTIST GENRE EDIT ==========
        let GENRE_TAXONOMY = [
            'Alternative', 'Anime', 'Blues', "Children's Music", 'Classical', 'Comedy', 'Country',
            'Dance', 'Disney', 'Easy Listening', 'Electronic', 'Enka', 'Folk', 'French Pop',
            'German Pop', 'German Folk', 'Fitness & Workout', 'Hip-Hop', 'Holiday', 'Indie Pop',
            'Industrial', 'Inspirational', 'Instrumental', 'J-Pop', 'Jazz', 'K-Pop', 'Karaoke',
            'Latin', 'Metal', 'New Age', 'Opera', 'Pop', 'Post-Disco', 'Progressive', 'R&B',
            'Reggae', 'Rock', 'Singer/Songwriter', 'Soundtrack', 'Spoken Word', 'Tex-Mex',
            'Vocal', 'World'
        ];

        async function loadGenreTaxonomy() {
            try {
                const res = await fetch(`${BASE_PATH}/edit_tags.php?action=get_genres`);
                const data = await res.json();
                if (data.success && data.data.genres.length > 0) {
                    GENRE_TAXONOMY = data.data.genres.map(g => g.name).sort();
                }
            } catch (e) {
                console.error('Failed to load genre taxonomy:', e);
            }
        }

        function editArtistGenre(artistId, currentGenre) {
            document.getElementById(`artist-genre-display-${artistId}`).style.display = 'none';
            document.getElementById(`artist-genre-edit-${artistId}`).style.display = 'block';

            const select = document.getElementById(`genre-select-${artistId}`);
            select.innerHTML = `<option value="">${t('empty.no_genre_opt','-- Aucun genre --')}</option>` +
                GENRE_TAXONOMY.map(g => `<option value="${g}" ${g === currentGenre ? 'selected' : ''}>${g}</option>`).join('');
        }

        function cancelEditGenre(artistId) {
            document.getElementById(`artist-genre-display-${artistId}`).style.display = 'flex';
            document.getElementById(`artist-genre-edit-${artistId}`).style.display = 'none';
        }

        async function saveArtistGenre(artistId) {
            const genre = document.getElementById(`genre-select-${artistId}`).value;
            const applyToAlbums = document.getElementById(`genre-apply-albums-${artistId}`).checked ? '1' : '0';

            try {
                const formData = new FormData();
                formData.append('artist_id', artistId);
                formData.append('genre', genre);
                formData.append('apply_to_albums', applyToAlbums);

                const res = await fetch(`${BASE_PATH}/api/library.php?action=set_artist_genre`, {
                    method: 'POST',
                    body: formData
                });
                const data = await res.json();
                if (!data.success) {
                    alert(data.error || t('common.error','Erreur'));
                    return;
                }

                // Update display
                const displayEl = document.getElementById(`artist-genre-display-${artistId}`);
                displayEl.innerHTML = (genre ? `<span class="genre-badge">${genre}</span>` : `<span style="color:rgba(255,255,255,0.5);font-size:13px;">Aucun genre</span>`) +
                    `<button onclick="editArtistGenre(${artistId}, '${genre.replace(/'/g, "\\'")}')" class="genre-edit-btn" title="Modifier le genre"><i class="ri-pencil-line"></i></button>`;

                cancelEditGenre(artistId);
            } catch (e) {
                console.error('Error saving genre:', e);
                alert(t('errors.genre_save','Erreur lors de la sauvegarde du genre.'));
            }
        }

        // ========== GENRE TAXONOMY MANAGER ==========
        let genreManagerVisible = false;

        function toggleGenreManager() {
            genreManagerVisible = !genreManagerVisible;
            const manager = document.getElementById('genre-manager-container');
            const grid = document.getElementById('genre-grid-container');
            if (genreManagerVisible) {
                manager.style.display = 'block';
                grid.style.display = 'none';
                renderGenreManager();
            } else {
                manager.style.display = 'none';
                grid.style.display = 'block';
            }
        }

        async function renderGenreManager() {
            const container = document.getElementById('genre-manager-container');
            container.innerHTML = `<div style="color:var(--text-secondary);padding:20px;">${t('common.loading','Chargement...')}</div>`;

            try {
                const res = await fetch(`${BASE_PATH}/edit_tags.php?action=get_genres`);
                const data = await res.json();
                if (!data.success) { container.innerHTML = `<div style="color:red;">${t('common.error','Erreur')}</div>`; return; }

                const genres = data.data.genres;

                let html = '<div class="genre-manager">';
                html += '<div class="genre-manager-header"><h3 style="margin:0;color:var(--text-primary);">' + t('genres.manager_title', 'Gestion des genres') + '</h3>';
                html += '<button onclick="toggleGenreManager()" style="background:none;border:none;color:var(--text-secondary);cursor:pointer;font-size:18px;"><i class="ri-close-line"></i></button></div>';

                genres.forEach(genre => {
                    html += `<div class="genre-manager-item">
                        <span class="genre-manager-name">${escapeHtml(genre.name)}</span>
                        <div class="genre-manager-actions">
                            <button class="genre-manager-btn" onclick="renameGenre(${genre.id}, '${escapeHtml(genre.name).replace(/'/g, "\\'")}')" title="${t('home.rename','Renommer')}"><i class="ri-pencil-line"></i></button>
                            <button class="genre-manager-btn genre-manager-btn-danger" onclick="deleteGenre(${genre.id}, '${escapeHtml(genre.name).replace(/'/g, "\\'")}')" title="${t('common.delete','Supprimer')}"><i class="ri-delete-bin-line"></i></button>
                            <button class="genre-manager-btn genre-manager-btn-add" onclick="addGenre(${genre.id})" title="${t('genres.add_subgenre','Ajouter un sous-genre')}"><i class="ri-add-line"></i></button>
                        </div>
                    </div>`;

                    if (genre.subgenres && genre.subgenres.length > 0) {
                        genre.subgenres.forEach(sub => {
                            html += `<div class="genre-manager-item genre-manager-sub">
                                <span class="genre-manager-name">${escapeHtml(sub.name)}</span>
                                <div class="genre-manager-actions">
                                    <button class="genre-manager-btn" onclick="renameGenre(${sub.id}, '${escapeHtml(sub.name).replace(/'/g, "\\'")}')" title="${t('home.rename','Renommer')}"><i class="ri-pencil-line"></i></button>
                                    <button class="genre-manager-btn genre-manager-btn-danger" onclick="deleteGenre(${sub.id}, '${escapeHtml(sub.name).replace(/'/g, "\\'")}')" title="${t('common.delete','Supprimer')}"><i class="ri-delete-bin-line"></i></button>
                                </div>
                            </div>`;
                        });
                    }
                });

                html += '<div style="margin-top:12px;"><button class="genre-manager-add" onclick="addGenre(null)"><i class="ri-add-line"></i> ' + t('genres.add_main', 'Ajouter un genre principal') + '</button></div>';
                html += '</div>';
                container.innerHTML = html;
            } catch (e) {
                console.error('Error loading genre manager:', e);
                container.innerHTML = `<div style="color:red;">${t('genres.load_error', 'Erreur de chargement.')}</div>`;
            }
        }

        async function addGenre(parentId) {
            const label = parentId ? t('genres.prompt_subgenre', 'Nom du sous-genre :') : t('genres.prompt_main_genre', 'Nom du genre principal :');
            const name = prompt(label);
            if (!name || !name.trim()) return;

            try {
                const formData = new FormData();
                formData.append('action', 'add_genre');
                formData.append('name', name.trim());
                if (parentId) formData.append('parent_id', parentId);

                const res = await fetch(`${BASE_PATH}/edit_tags.php`, { method: 'POST', body: formData });
                const data = await res.json();
                if (!data.success) { alert(data.error || t('common.error','Erreur')); return; }

                renderGenreManager();
                loadGenreTaxonomy();
                // Invalidate TagEditor genre cache
                if (typeof tagEditor !== 'undefined') tagEditor.genres = [];
            } catch (e) {
                console.error('Error adding genre:', e);
                alert(t('errors.genre_add',"Erreur lors de l'ajout du genre."));
            }
        }

        async function renameGenre(id, currentName) {
            const newName = prompt(t('genres.prompt_rename', 'Nouveau nom du genre :'), currentName);
            if (!newName || !newName.trim() || newName.trim() === currentName) return;

            try {
                const formData = new FormData();
                formData.append('action', 'rename_genre');
                formData.append('id', id);
                formData.append('name', newName.trim());

                const res = await fetch(`${BASE_PATH}/edit_tags.php`, { method: 'POST', body: formData });
                const data = await res.json();
                if (!data.success) { alert(data.error || t('common.error','Erreur')); return; }

                renderGenreManager();
                loadGenreTaxonomy();
                if (typeof tagEditor !== 'undefined') tagEditor.genres = [];
            } catch (e) {
                console.error('Error renaming genre:', e);
                alert(t('errors.genre_rename','Erreur lors du renommage du genre.'));
            }
        }

        async function deleteGenre(id, name) {
            if (!confirm(t('confirm.delete_genre','Supprimer le genre "{name}" ? Les sous-genres seront aussi supprimés.').replace('{name}', name))) return;

            try {
                const formData = new FormData();
                formData.append('action', 'delete_genre');
                formData.append('id', id);

                const res = await fetch(`${BASE_PATH}/edit_tags.php`, { method: 'POST', body: formData });
                const data = await res.json();
                if (!data.success) { alert(data.error || t('common.error','Erreur')); return; }

                renderGenreManager();
                loadGenreTaxonomy();
                if (typeof tagEditor !== 'undefined') tagEditor.genres = [];
            } catch (e) {
                console.error('Error deleting genre:', e);
                alert(t('errors.genre_delete','Erreur lors de la suppression du genre.'));
            }
        }

        window.toggleGenreManager = toggleGenreManager;
        window.addGenre = addGenre;
        window.renameGenre = renameGenre;
        window.deleteGenre = deleteGenre;

        // ========== GENRE SCAN ==========
        let genreScanPollInterval = null;

        async function startGenreScan() {
            const btn = document.getElementById('genre-scan-btn');
            if (btn) {
                btn.disabled = true;
                const icon = document.getElementById('genre-scan-icon');
                if (icon) icon.className = 'ri-loader-4-line scan-spin-icon';
            }

            try {
                const force = document.getElementById('genre-scan-force')?.checked ? '&force=1' : '';
                const res = await fetch(`${BASE_PATH}/api/scan.php?action=genre_scan&user=${app.currentUser}${force}`);
                const data = await res.json();
                if (!data.success) {
                    alert(data.error || t('errors.genre_scan','Erreur lors du lancement du scan.'));
                    if (btn) btn.disabled = false;
                    return;
                }

                // Show progress bar
                const progressEl = document.getElementById('genre-scan-progress');
                if (progressEl) progressEl.style.display = 'block';

                // Start polling
                if (genreScanPollInterval) clearInterval(genreScanPollInterval);
                genreScanPollInterval = setInterval(pollGenreScanStatus, 2000);
            } catch (e) {
                console.error('Genre scan error:', e);
                if (btn) btn.disabled = false;
            }
        }

        async function pollGenreScanStatus() {
            try {
                const res = await fetch(`${BASE_PATH}/api/scan.php?action=genre_scan_status`);
                const data = await res.json();
                if (!data.success) return;

                const progress = data.data.progress || {};
                const scanning = data.data.scanning;
                const textEl = document.getElementById('genre-scan-progress-text');

                if (progress.status === 'scanning' && scanning) {
                    if (textEl) {
                        textEl.textContent = `${progress.current_artist || '...'} (${progress.processed}/${progress.total} - ${progress.percent}%)`;
                    }
                } else if (progress.status === 'completed' || !scanning) {
                    // Scan finished
                    if (genreScanPollInterval) {
                        clearInterval(genreScanPollInterval);
                        genreScanPollInterval = null;
                    }

                    const progressEl = document.getElementById('genre-scan-progress');
                    if (progressEl) progressEl.style.display = 'none';

                    const btn = document.getElementById('genre-scan-btn');
                    if (btn) {
                        btn.disabled = false;
                        const icon = document.getElementById('genre-scan-icon');
                        if (icon) icon.className = 'ri-radar-line';
                    }

                    // Reload stats to update genre chart
                    renderStatistics();
                }
            } catch (e) {
                console.error('Genre scan poll error:', e);
            }
        }

        async function cleanupOrphans() {
            const btn = document.getElementById('orphan-cleanup-btn');
            const icon = document.getElementById('orphan-cleanup-icon');
            if (btn) btn.disabled = true;
            if (icon) icon.className = 'ri-loader-4-line scan-spin-icon';

            try {
                const res = await fetch(`${BASE_PATH}/api/scan.php?action=cleanup_orphans&user=${app.currentUser}`);
                const data = await res.json();
                if (!data.success) {
                    alert(data.error || t('errors.genre_cleanup','Erreur lors du nettoyage.'));
                } else {
                    const d = data.data;
                    const msg = d.artists_deleted === 0 && d.albums_deleted === 0
                        ? t('genres.no_orphans', 'Aucun orphelin trouvé.')
                        : t('genres.cleanup_result', 'Nettoyage terminé : {a} artiste(s) et {b} album(s) supprimés.').replace('{a}', d.artists_deleted).replace('{b}', d.albums_deleted);
                    alert(msg);
                    renderStatistics();
                }
            } catch (e) {
                console.error('Cleanup orphans error:', e);
                alert(t('errors.genre_cleanup','Erreur lors du nettoyage.'));
            } finally {
                if (btn) btn.disabled = false;
                if (icon) icon.className = 'ri-delete-bin-2-line';
            }
        }

        function shuffleArray(array) {
            const shuffled = [...array];
            for (let i = shuffled.length - 1; i > 0; i--) {
                const j = Math.floor(Math.random() * (i + 1));
                [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
            }
            return shuffled;
        }

        // Lecture
        async function playSongFromAlbum(albumId, songIndex) {
            if (!window.currentAlbumData) return;

            const albumData = window.currentAlbumData;
            const songs = albumData.songs;

            // Disable radio mode
            app.radioMode = false;

            // Créer la queue avec toutes les chansons de l'album
            const tracks = songs.map(song => ({
                id: song.id,
                title: song.title,
                artist: song.artistName || albumData.artist.name,
                album: albumData.name,
                filePath: song.filePath,
                artworkUrl: song.artworkUrl,
                duration: song.duration
            }));

            app.queue = tracks;
            app.currentTrackIndex = songIndex;

            if (window.gullifyPlayer) {
                window.gullifyPlayer.queue = tracks;
                window.gullifyPlayer.loadTrack(tracks[songIndex], songIndex, true);
            }
        }

        async function playAlbum(albumId) {
            if (window.gullifyPlayer) {
                window.gullifyPlayer.playAlbum(albumId, app.currentUser, false);
            }
        }

        async function shuffleAlbum(albumId) {
            if (window.gullifyPlayer) {
                window.gullifyPlayer.playAlbum(albumId, app.currentUser, true);
            }
        }

        async function uploadArtistImage(artistId, inputElement) {
            try {
                const file = inputElement.files[0];
                if (!file) return;

                // Validate file type
                const allowedTypes = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp'];
                if (!allowedTypes.includes(file.type)) {
                    alert(t('alert.invalid_file_type', 'Type de fichier non supporté. Utilisez JPG, PNG ou WebP.'));
                    return;
                }

                // Validate file size (max 5MB)
                const maxSize = 5 * 1024 * 1024;
                if (file.size > maxSize) {
                    alert(t('alert.file_too_large', 'Le fichier est trop volumineux. Taille maximale: 5MB'));
                    return;
                }

                // Show loading indicator
                const avatarEl = document.getElementById(`artist-avatar-${artistId}`);
                const originalContent = avatarEl.innerHTML;
                avatarEl.innerHTML = '<div style="font-size: 24px;">⏳</div>';

                // Prepare form data
                const formData = new FormData();
                formData.append('image', file);
                formData.append('artist_id', artistId);

                // Upload image
                const response = await fetch(`${BASE_PATH}/upload_artist_image.php`, {
                    method: 'POST',
                    body: formData
                });

                const result = await response.json();

                if (result.error) {
                    throw new Error(result.message);
                }

                // Update UI with new image
                const imgSrc = `data:image/jpeg;base64,${result.image}`;
                avatarEl.innerHTML = `<img src="${imgSrc}" alt="Artist" style="width: 100%; height: 100%; object-fit: cover;">`;

                // Update cache
                const cacheKey = `artist-${artistId}`;
                app.imageCache[cacheKey] = imgSrc;

                // Also update grid if present
                const gridEl = document.getElementById(`artist-grid-${artistId}`);
                if (gridEl) {
                    gridEl.innerHTML = `<img src="${imgSrc}" alt="Artist" style="width: 100%; height: 100%; object-fit: cover;">`;
                }

                // Update background with new artist image
                showArtistBackground(imgSrc);

                // Show success message
                showToast('✅ ' + t('toast.image_uploaded', 'Image uploadée avec succès!'));

            } catch (error) {
                console.error('Error uploading artist image:', error);
                alert(t('errors.upload_image', "Erreur lors de l'upload de l'image: ") + error.message);
                // Restore original content on error
                const avatarEl = document.getElementById(`artist-avatar-${artistId}`);
                if (avatarEl) {
                    avatarEl.innerHTML = originalContent;
                }
            } finally {
                // Clear input
                inputElement.value = '';
            }
        }

        async function playArtistSongs(artistId) {
            if (window.gullifyPlayer) {
                window.gullifyPlayer.playArtist(artistId, app.currentUser);
            }
        }

        async function playRandomSongs() {
            if (window.gullifyPlayer) {
                window.gullifyPlayer.playRandom(app.currentUser);
            }
        }

        async function playRandomArtist() {
            if (window.gullifyPlayer) {
                window.gullifyPlayer.playRandomArtist(app.currentUser);
            }
        }

        async function startRadio(genre = null) {
            if (window.gullifyPlayer) {
                window.gullifyPlayer.startRadio(app.currentUser, genre);
            }
        }

        function startGenreRadio(genreName) {
            event && event.stopPropagation();
            // Use window.startRadio so overrides (unified/global player) are applied
            window.startRadio(genreName);
        }

        async function loadMoreRadioSongs(limit = 20) {
            try {
                console.log(`Loading more radio songs (${limit})...`);

                let radioUrl = `${BASE_PATH}/radio_api_mysql.php?action=get_random&limit=${limit}&user=${app.currentUser}`;
                if (radioGenre) {
                    radioUrl += `&genre=${encodeURIComponent(radioGenre)}`;
                }
                const response = await fetch(radioUrl);
                const result = await response.json();

                if (result.error) {
                    console.error('Error loading radio songs:', result.message);
                    return;
                }

                console.log(`Loaded ${result.count} new songs for radio`);

                // Add songs to queue
                result.songs.forEach(song => {
                    app.queue.push({
                        id: song.id,
                        title: song.title,
                        artist: song.artist,
                        album: song.album,
                        filePath: song.filePath,
                        duration: song.duration,
                        artworkUrl: song.artworkUrl || null,
                        artwork: song.artwork || null
                    });
                });

                renderQueue();
            } catch (error) {
                console.error('Error loading more radio songs:', error);
            }
        }

        async function recordPlay(songId, durationPlayed, completed) {
            try {
                const formData = new FormData();
                formData.append('song_id', songId);
                formData.append('user', app.currentUser);
                formData.append('duration_played', durationPlayed);
                formData.append('completed', completed ? 1 : 0);

                await fetch(`${BASE_PATH}/radio_api_mysql.php?action=record_play`, {
                    method: 'POST',
                    body: formData
                });

                console.log(`Recorded play for song ${songId}, duration: ${durationPlayed}s, completed: ${completed}`);
            } catch (error) {
                console.error('Error recording play:', error);
            }
        }

        function addSongToQueueById(songId) {
            if (!window.currentAlbumData) return;

            const song = window.currentAlbumData.songs.find(s => s.id === songId);
            if (!song) return;

            const track = {
                id: song.id,
                title: song.title,
                artist: song.artistName || window.currentAlbumData.artist.name,
                filePath: song.filePath,
                artworkUrl: song.artworkUrl,
                duration: song.duration
            };

            addSongToQueue(track);
        }

        function addSongToQueue(song) {
            if (window.gullifyPlayer) {
                window.gullifyPlayer.addToQueue(song);
                showToast(t('toast.added_queue', "Ajouté à la file d'attente"), 'success');
            }
        }

        // ── Settings section HTML helpers ───────────────────────────────────────

        function getSettingsAppearanceHtml() {
            const currentTheme = document.documentElement.getAttribute('data-theme') || 'light';
            const isDark = currentTheme === 'dark';
            return `
                <div class="settings-section">
                    <div class="settings-section-title"><i class="ri-palette-line"></i> ${t('settings.appearance', 'Apparence')}</div>
                    <div class="settings-row">
                        <div class="settings-row-label">
                            <span>${t('settings.theme', 'Thème')}</span>
                            <span>${t('settings.theme_desc', 'Basculer entre le mode clair et sombre')}</span>
                        </div>
                        <button class="rescan-btn" id="settingsThemeBtn" onclick="toggleTheme(); updateThemeButton();" style="flex-shrink:0;">
                            <i class="${isDark ? 'ri-sun-line' : 'ri-moon-line'}" id="themeIcon"></i>
                            <span id="themeText">${isDark ? t('settings.light_mode', 'Mode Clair') : t('settings.dark_mode', 'Mode Sombre')}</span>
                        </button>
                    </div>
                </div>
            `;
        }

        function getSettingsLanguageHtml() {
            return `
                <div class="settings-section">
                    <div class="settings-section-title"><i class="ri-translate-2"></i> ${t('settings.language', 'Langue')}</div>
                    <div class="settings-row">
                        <div class="settings-row-label">
                            <span>${t('settings.interface_lang', "Langue de l'interface")}</span>
                            <span>${t('settings.change_lang', "Changer la langue d'affichage")}</span>
                        </div>
                        <div style="display:flex;gap:8px;flex-shrink:0;">
                            <button class="rescan-btn" onclick="setLang('fr')" id="langFrBtn" style="${app.lang === 'fr' ? 'background:var(--accent);color:#fff;' : ''}">🇫🇷 Français</button>
                            <button class="rescan-btn" onclick="setLang('en')" id="langEnBtn" style="${app.lang === 'en' ? 'background:var(--accent);color:#fff;' : ''}">🇬🇧 English</button>
                        </div>
                    </div>
                </div>
            `;
        }

        function getSettingsLibraryHtml() {
            return `
                <div class="settings-section">
                    <div class="settings-section-title"><i class="ri-music-library-line"></i> ${t('scan.library', 'Bibliothèque')}</div>
                    <div class="settings-row">
                        <div class="settings-row-label">
                            <span>${t('scan.quick', 'Scan rapide')}</span>
                            <span>${t('scan.quick_desc', 'Détecte les nouveaux fichiers sans relire les métadonnées ID3 ni les pochettes')}</span>
                        </div>
                        <button class="rescan-btn" onclick="window.triggerLibraryScan('fast', this)" style="flex-shrink:0;">
                            <i class="ri-folder-search-line"></i>
                            <span>${t('common.run', 'Lancer')}</span>
                        </button>
                    </div>
                    <div class="settings-row">
                        <div class="settings-row-label">
                            <span>${t('scan.full', 'Scan complet')}</span>
                            <span>${t('scan.full_desc', 'Relit toutes les métadonnées ID3 et met à jour les pochettes')}</span>
                        </div>
                        <button class="rescan-btn" onclick="window.triggerLibraryScan('force', this)" style="flex-shrink:0;">
                            <i class="ri-refresh-line"></i>
                            <span>${t('common.run', 'Lancer')}</span>
                        </button>
                    </div>
                    <div class="settings-row">
                        <div class="settings-row-label">
                            <span>${t('scan.artwork', 'Scan artwork')}</span>
                            <span>${t('scan.artwork_desc', 'Met à jour les pochettes manquantes uniquement (cover.jpg + ID3 embarqué)')}</span>
                        </div>
                        <button class="rescan-btn" onclick="window.triggerLibraryScan('artwork', this)" style="flex-shrink:0;">
                            <i class="ri-image-line"></i>
                            <span>${t('common.run', 'Lancer')}</span>
                        </button>
                    </div>
                </div>

                <div id="scan-progress-container" style="display:none; margin-top:-10px; margin-bottom:20px;">
                    <div class="settings-section" style="border:1px solid var(--accent);background:rgba(var(--accent-rgb),0.05);">
                        <div class="settings-section-title"><i class="ri-loader-4-line"></i> ${t('scan.progress', 'Progression du scan')}</div>
                        <div style="display:flex;justify-content:space-between;margin-bottom:6px;font-size:13px;">
                            <span id="scan-status-text" style="font-weight:600;">${t('scan.initializing', 'Initialisation...')}</span>
                            <span id="scan-percent-text" style="color:var(--accent);font-weight:600;">0%</span>
                        </div>
                        <div style="width:100%;height:8px;background:var(--hover-bg);border-radius:4px;overflow:hidden;margin-bottom:6px;">
                            <div id="scan-progress-bar" style="width:0%;height:100%;background:var(--accent);border-radius:4px;transition:width 0.3s ease;"></div>
                        </div>
                        <div id="scan-current-file" style="font-size:11px;color:var(--text-secondary);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;font-family:monospace;"></div>
                    </div>
                </div>

                <div class="settings-section">
                    <div class="settings-section-title"><i class="ri-hard-drive-line"></i> ${t('settings.storage','Stockage')}</div>
                    <div class="settings-row">
                        <div class="settings-row-label">
                            <span>${t('settings.storage_source','Source de la bibliothèque')}</span>
                            <span>${app.storageType === 'sftp'
                                ? `<span style="color:#00b894"><i class="ri-server-line"></i> SFTP — ${escapeHtml(app.sftpHost)}${app.sftpPath ? ':' + escapeHtml(app.sftpPath) : ''}</span>`
                                : app.musicDir ? `<i class="ri-folder-line"></i> ${escapeHtml(app.musicDir)}` : `<span style="color:var(--text-secondary)">${t('settings.not_configured','Non configuré')}</span>`
                            }</span>
                        </div>
                        <button class="rescan-btn" onclick="openStorageModal()" style="flex-shrink:0;">
                            <i class="ri-settings-3-line"></i> ${t('settings.configure','Configurer')}
                        </button>
                    </div>
                </div>
            `;
        }

        function getSettingsAdminHtml() {
            return `
                <div class="settings-section" id="adminUsersSection">
                    <div class="settings-section-title"><i class="ri-shield-user-line"></i> ${t('admin.users_title','Administration — Utilisateurs')}</div>

                    <div id="adminUsersList" style="margin-bottom:20px;">
                        <div style="color:var(--text-secondary);font-size:13px;padding:8px 0;">${t('common.loading','Chargement...')}</div>
                    </div>

                    <div style="border-top:1px solid var(--border-color,rgba(128,128,128,0.1));padding-top:16px;">
                        <div style="font-size:11px;font-weight:700;color:var(--text-secondary);text-transform:uppercase;letter-spacing:.6px;margin-bottom:12px;">${t('settings.new_user','Nouvel utilisateur')}</div>
                        <div class="admin-form-grid">
                            <input type="text" id="newUsername" placeholder="${t('setup.username',"Nom d'utilisateur")}" class="admin-input">
                            <input type="text" id="newFullName" placeholder="${t('setup.full_name','Nom complet')}" class="admin-input">
                            <input type="password" id="newPassword" placeholder="${t('settings.password_ph','Mot de passe (min 6 car.)')}" class="admin-input">
                            <select id="newMusicDir" class="admin-input">
                                <option value="">${t('settings.music_dir_placeholder','— Répertoire musique —')}</option>
                            </select>
                        </div>
                        <div class="admin-form-footer">
                            <label>
                                <input type="checkbox" id="newIsAdmin"> ${t('settings.administrator','Administrateur')}
                            </label>
                            <button class="rescan-btn" id="createUserBtn" onclick="adminCreateUser()" style="margin-left:auto;">
                                <i class="ri-user-add-line"></i> ${t('settings.create_user',"Créer l'utilisateur")}
                            </button>
                        </div>
                    </div>
                </div>

                <div class="settings-section" id="adminDirsSection">
                    <div class="settings-section-title"><i class="ri-folder-music-line"></i> ${t('admin.dirs_title','Administration — Répertoires')}</div>
                    <div id="adminDirsList">
                        <div style="color:var(--text-secondary);font-size:13px;padding:8px 0;">${t('common.loading','Chargement...')}</div>
                    </div>
                </div>
            `;
        }

        function getSettingsSectionHtml(section) {
            switch (section) {
                case 'appearance': return getSettingsAppearanceHtml();
                case 'language':   return getSettingsLanguageHtml();
                case 'library':    return getSettingsLibraryHtml();
                case 'admin':      return getSettingsAdminHtml();
                default:           return getSettingsAppearanceHtml();
            }
        }

        function initAdminSection() {
            if (!app.isAdmin) return;
            const ADMIN_URL = `${BASE_PATH}/api/admin.php`;

            const adminFetch = async (action, body = null) => {
                const opts = { method: body ? 'POST' : 'GET' };
                if (body) { const fd = new FormData(); Object.entries(body).forEach(([k,v]) => fd.append(k, v)); opts.body = fd; }
                const r = await fetch(`${ADMIN_URL}?action=${action}`, opts);
                return r.json();
            };

            const loadAdminUsers = async () => {
                const result = await adminFetch('list_users');
                const container = document.getElementById('adminUsersList');
                if (!container) return;
                if (!result.success) { container.innerHTML = `<p style="color:#ff6b6b">${result.error}</p>`; return; }

                container.innerHTML = `
                    <table class="admin-table">
                        <thead><tr><th>${t('admin.col_user','Utilisateur')}</th><th>${t('admin.col_name','Nom')}</th><th>${t('admin.col_storage','Stockage')}</th><th>${t('admin.col_role','Rôle')}</th><th>${t('admin.col_status','Statut')}</th><th style="text-align:right">${t('admin.col_actions','Actions')}</th></tr></thead>
                        <tbody>
                        ${result.data.map(u => `
                            <tr class="${!u.is_active ? 'admin-row-inactive' : ''}">
                                <td data-label="${t('admin.col_user','Utilisateur')}"><strong>${escapeHtml(u.username)}</strong></td>
                                <td data-label="${t('admin.col_name','Nom')}">${escapeHtml(u.full_name || '—')}</td>
                                <td data-label="${t('admin.col_storage','Stockage')}">
                                    ${u.storage_type === 'sftp'
                                        ? `<span class="admin-dir-badge" style="color:#00b894;border-color:rgba(0,184,148,.4)"><i class="ri-server-line"></i> ${escapeHtml(u.sftp_host || '?')}</span>`
                                        : `<span class="admin-dir-badge"><i class="ri-folder-line"></i> ${escapeHtml(u.music_directory || '—')}</span>`
                                    }
                                </td>
                                <td data-label="${t('admin.col_role','Rôle')}">${u.is_admin ? '<span class="admin-badge">Admin</span>' : `<span style="font-size:12px;color:var(--text-secondary)">${t('settings.user_role','Utilisateur')}</span>`}</td>
                                <td data-label="${t('admin.col_status','Statut')}">${u.is_active ? `<span style="color:#00b894;font-size:12px;font-weight:600">${t('settings.active','● Actif')}</span>` : `<span style="color:#ff6b6b;font-size:12px;font-weight:600">${t('settings.inactive','● Inactif')}</span>`}</td>
                                <td data-label="${t('admin.col_actions','Actions')}" class="admin-actions">
                                    <button class="admin-btn" onclick="adminChangePassword(${u.id}, '${jsStr(u.username)}')" title="${t('settings.change_password','Changer le mot de passe')}"><i class="ri-key-line"></i></button>
                                    <button class="admin-btn" onclick="adminChangeDir(${u.id}, '${jsStr(u.username)}', '${jsStr(u.music_directory || '')}')" title="${t('settings.change_dir','Changer le répertoire local')}"><i class="ri-folder-line"></i></button>
                                    <button class="admin-btn ${u.storage_type === 'sftp' ? 'admin-btn-sftp' : ''}" onclick="adminEditSftp(${u.id}, '${jsStr(u.username)}', '${jsStr(u.storage_type || 'local')}', '${jsStr(u.sftp_host || '')}', ${u.sftp_port || 22}, '${jsStr(u.sftp_user || '')}', '${jsStr(u.sftp_path || '')}')" title="${t('settings.sftp_settings','Paramètres SFTP')}"><i class="ri-server-line"></i></button>
                                    <button class="admin-btn" onclick="adminToggleAdmin(${u.id})" title="${u.is_admin ? t('admin.remove_admin','Retirer admin') : t('admin.make_admin','Rendre admin')}"><i class="ri-shield-${u.is_admin ? 'fill' : 'line'}"></i></button>
                                    <button class="admin-btn" onclick="adminToggleActive(${u.id})" title="${u.is_active ? t('settings.deactivate','Désactiver') : t('settings.activate','Activer')}"><i class="ri-toggle-${u.is_active ? 'fill' : 'line'}"></i></button>
                                    <button class="admin-btn admin-btn-danger" onclick="adminDeleteUser(${u.id}, '${escapeHtml(u.username)}')" title="${t('common.delete','Supprimer')}"><i class="ri-delete-bin-line"></i></button>
                                </td>
                            </tr>
                        `).join('')}
                        </tbody>
                    </table>
                `;
            };

            const loadAdminDirs = async () => {
                const result = await adminFetch('list_directories');
                const container = document.getElementById('adminDirsList');
                if (!container) return;
                if (!result.success) { container.innerHTML = `<p style="color:#ff6b6b">${result.error}</p>`; return; }

                const sel = document.getElementById('newMusicDir');
                if (sel) {
                    result.data.forEach(d => {
                        const opt = document.createElement('option');
                        opt.value = d; opt.textContent = d;
                        sel.appendChild(opt);
                    });
                }

                container.innerHTML = `
                    <div style="font-size:13px;color:var(--text-secondary);margin-bottom:8px;">${t('settings.dirs_in','Répertoires dans')} <code>${escapeHtml(result.base_path)}</code></div>
                    <div style="display:flex;flex-wrap:wrap;gap:8px;">
                        ${result.data.map(d => `<span class="admin-dir-badge"><i class="ri-folder-music-line"></i> ${escapeHtml(d)}</span>`).join('')}
                        ${result.data.length === 0 ? `<span style="color:var(--text-secondary)">${t('settings.no_dirs','Aucun répertoire trouvé')}</span>` : ''}
                    </div>
                `;
            };

            window.adminCreateUser = async () => {
                const username = document.getElementById('newUsername')?.value.trim();
                const password = document.getElementById('newPassword')?.value;
                const fullName = document.getElementById('newFullName')?.value.trim();
                const musicDir = document.getElementById('newMusicDir')?.value;
                const isAdmin  = document.getElementById('newIsAdmin')?.checked ? 1 : 0;

                if (!username || !password) { showToast(t('setup.username_pass_required', "Nom d'utilisateur et mot de passe requis"), 'error'); return; }

                const result = await adminFetch('create_user', { username, password, full_name: fullName, music_directory: musicDir, is_admin: isAdmin });
                if (result.success) {
                    showToast(t('toast.user_created', 'Utilisateur créé'), 'success');
                    document.getElementById('newUsername').value = '';
                    document.getElementById('newPassword').value = '';
                    document.getElementById('newFullName').value = '';
                    document.getElementById('newMusicDir').value = '';
                    document.getElementById('newIsAdmin').checked = false;
                    loadAdminUsers();
                } else {
                    showToast(result.error, 'error');
                }
            };

            window.adminDeleteUser = async (userId, username) => {
                if (!confirm(t('confirm.delete_user',"Supprimer l'utilisateur \"{name}\" ? Cette action est irréversible.").replace('{name}', username))) return;
                const result = await adminFetch('delete_user', { user_id: userId });
                if (result.success) { showToast(t('toast.user_deleted', 'Utilisateur supprimé'), 'success'); loadAdminUsers(); }
                else showToast(result.error, 'error');
            };

            window.adminToggleActive = async (userId) => {
                const result = await adminFetch('toggle_active', { user_id: userId });
                if (result.success) loadAdminUsers();
                else showToast(result.error, 'error');
            };

            window.adminToggleAdmin = async (userId) => {
                const result = await adminFetch('toggle_admin', { user_id: userId });
                if (result.success) loadAdminUsers();
                else showToast(result.error, 'error');
            };

            window.adminChangePassword = async (userId, username) => {
                const password = prompt(t('confirm.change_password','Nouveau mot de passe pour "{name}" (min 6 caractères) :').replace('{name}', username));
                if (!password) return;
                const result = await adminFetch('update_password', { user_id: userId, password });
                if (result.success) showToast(t('toast.password_updated', 'Mot de passe mis à jour'), 'success');
                else showToast(result.error, 'error');
            };

            window.adminChangeDir = async (userId, username, currentDir) => {
                const dirs = await adminFetch('list_directories');
                if (!dirs.success) { showToast(dirs.error, 'error'); return; }

                const options = dirs.data.map(d => `<option value="${escapeHtml(d)}" ${d === currentDir ? 'selected' : ''}>${escapeHtml(d)}</option>`).join('');
                const modal = document.createElement('div');
                modal.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,.6);z-index:99999;display:flex;align-items:center;justify-content:center;';
                modal.innerHTML = `
                    <div style="background:var(--bg-secondary);border:1px solid var(--border);border-radius:16px;padding:28px;min-width:320px;max-width:480px;width:90%;">
                        <h3 style="margin-bottom:16px;">${t('settings.dir_of','Répertoire de {name}').replace('{name}', escapeHtml(username))}</h3>
                        <select id="dirModalSelect" class="admin-input" style="width:100%;margin-bottom:16px;">
                            <option value="">${t('settings.none_option','— Aucun —')}</option>
                            ${options}
                        </select>
                        <div style="display:flex;gap:8px;justify-content:flex-end;">
                            <button class="rescan-btn" onclick="this.closest('div[style]').remove()">${t('common.cancel','Annuler')}</button>
                            <button class="rescan-btn" id="dirModalSave" style="background:var(--accent);color:#fff;">${t('common.save','Enregistrer')}</button>
                        </div>
                    </div>
                `;
                document.body.appendChild(modal);
                document.getElementById('dirModalSave').onclick = async () => {
                    const dir = document.getElementById('dirModalSelect').value;
                    const result = await adminFetch('update_directory', { user_id: userId, music_directory: dir });
                    modal.remove();
                    if (result.success) { showToast(t('toast.dir_updated', 'Répertoire mis à jour'), 'success'); loadAdminUsers(); }
                    else showToast(result.error, 'error');
                };
            };

            // ── SFTP settings modal ─────────────────────────────────────────────
            window.adminEditSftp = (userId, username, storageType, sftpHost, sftpPort, sftpUser, sftpPath) => {
                const modal = document.createElement('div');
                modal.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,.6);z-index:99999;display:flex;align-items:center;justify-content:center;';
                modal.innerHTML = `
                    <div style="background:var(--bg-secondary);border:1px solid var(--border);border-radius:16px;padding:28px;min-width:360px;max-width:520px;width:92%;">
                        <h3 style="margin-bottom:18px;"><i class="ri-server-line"></i> ${t('settings.storage_of','Stockage — {name}').replace('{name}', escapeHtml(username))}</h3>

                        <div style="margin-bottom:14px;">
                            <label style="font-size:13px;display:block;margin-bottom:6px;">${t('admin.storage_type','Type de stockage')}</label>
                            <select id="sftpModalType" class="admin-input" style="width:100%" onchange="document.getElementById('sftpFields').style.display=this.value==='sftp'?'block':'none'">
                                <option value="local" ${storageType !== 'sftp' ? 'selected' : ''}>${t('settings.local_storage','Local (répertoire sur le serveur)')}</option>
                                <option value="sftp" ${storageType === 'sftp' ? 'selected' : ''}>${t('settings.sftp_storage','SFTP (serveur distant)')}</option>
                            </select>
                        </div>

                        <div id="sftpFields" style="display:${storageType === 'sftp' ? 'block' : 'none'}">
                            <div style="display:grid;grid-template-columns:1fr auto;gap:8px;margin-bottom:10px;">
                                <div>
                                    <label style="font-size:12px;display:block;margin-bottom:4px;">${t('settings.host','Hôte')}</label>
                                    <input id="sftpHost" class="admin-input" style="width:100%" placeholder="sftp.example.com" value="${escapeHtml(sftpHost)}">
                                </div>
                                <div style="width:80px;">
                                    <label style="font-size:12px;display:block;margin-bottom:4px;">${t('setup.sftp_port','Port')}</label>
                                    <input id="sftpPort" class="admin-input" type="number" style="width:100%" value="${sftpPort || 22}">
                                </div>
                            </div>
                            <div style="margin-bottom:10px;">
                                <label style="font-size:12px;display:block;margin-bottom:4px;">${t('setup.sftp_user','Utilisateur SFTP')}</label>
                                <input id="sftpUser" class="admin-input" style="width:100%" placeholder="user" value="${escapeHtml(sftpUser)}">
                            </div>
                            <div style="margin-bottom:10px;">
                                <label style="font-size:12px;display:block;margin-bottom:4px;">${t('settings.sftp_pass_label','Mot de passe SFTP')} <span style="color:var(--text-secondary);font-size:11px">${t('settings.sftp_pass_hint',"(laisser vide pour conserver l'actuel)")}</span></label>
                                <input id="sftpPassword" class="admin-input" type="password" style="width:100%" placeholder="••••••••">
                            </div>
                            <div style="margin-bottom:14px;">
                                <label style="font-size:12px;display:block;margin-bottom:4px;">${t('settings.sftp_path_label','Chemin distant (racine musique)')}</label>
                                <input id="sftpPath" class="admin-input" style="width:100%" placeholder="/home/user/music" value="${escapeHtml(sftpPath)}">
                            </div>
                            <div style="margin-bottom:16px;">
                                <button id="sftpTestBtn" class="rescan-btn" style="width:100%;justify-content:center;" onclick="adminTestSftp(${userId})">
                                    <i class="ri-wifi-line"></i> ${t('setup.test_connection','Tester la connexion')}
                                </button>
                                <div id="sftpTestResult" style="margin-top:6px;font-size:12px;min-height:16px;"></div>
                            </div>
                        </div>

                        <div style="display:flex;gap:8px;justify-content:flex-end;">
                            <button class="rescan-btn" onclick="this.closest('div[style*=fixed]').remove()">${t('common.cancel','Annuler')}</button>
                            <button class="rescan-btn" id="sftpSaveBtn" style="background:var(--accent);color:#fff;" onclick="adminSaveSftp(${userId})">
                                <i class="ri-save-line"></i> ${t('common.save','Enregistrer')}
                            </button>
                        </div>
                    </div>
                `;
                document.body.appendChild(modal);
            };

            window.adminTestSftp = async (userId) => {
                const btn    = document.getElementById('sftpTestBtn');
                const result = document.getElementById('sftpTestResult');
                btn.disabled = true;
                result.textContent = t('settings.testing', 'Test en cours…');
                result.style.color = 'var(--text-secondary)';

                const r = await adminFetch('test_sftp_connection', {
                    user_id:       userId,
                    sftp_host:     document.getElementById('sftpHost')?.value || '',
                    sftp_port:     document.getElementById('sftpPort')?.value || '22',
                    sftp_user:     document.getElementById('sftpUser')?.value || '',
                    sftp_password: document.getElementById('sftpPassword')?.value || '',
                    sftp_path:     document.getElementById('sftpPath')?.value || '',
                });

                btn.disabled = false;
                if (r.success) {
                    result.textContent = r.message || t('admin.connection_ok', '✓ Connexion réussie');
                    result.style.color = '#00b894';
                } else {
                    result.textContent = r.error || t('admin.connection_fail', '✗ Erreur inconnue');
                    result.style.color = '#ff6b6b';
                }
            };

            window.adminSaveSftp = async (userId) => {
                const storageType = document.getElementById('sftpModalType')?.value || 'local';
                const r = await adminFetch('update_sftp', {
                    user_id:       userId,
                    storage_type:  storageType,
                    sftp_host:     document.getElementById('sftpHost')?.value || '',
                    sftp_port:     document.getElementById('sftpPort')?.value || '22',
                    sftp_user:     document.getElementById('sftpUser')?.value || '',
                    sftp_password: document.getElementById('sftpPassword')?.value || '',
                    sftp_path:     document.getElementById('sftpPath')?.value || '',
                });
                document.querySelector('div[style*=fixed]')?.remove();
                if (r.success) { showToast(t('toast.storage_saved','Paramètres de stockage enregistrés'), 'success'); loadAdminUsers(); }
                else showToast(r.error || t('common.error','Erreur'), 'error');
            };

            loadAdminUsers();
            loadAdminDirs();
        }

        function renderSettings(activeSection = 'appearance') {
            // Open accordion in sidebar
            document.getElementById('settingsSubmenu')?.classList.add('open');
            document.querySelector('[data-view="settings"]')?.classList.add('open');

            // Sync main nav active state
            navItems.forEach(item => item.classList.toggle('active', item.dataset.view === 'settings'));
            app.currentView = 'settings';
            localStorage.setItem('musicCurrentView', 'settings');

            // Sync sub-item active state
            document.querySelectorAll('.nav-subitem[data-settings-section]').forEach(item => {
                item.classList.toggle('active', item.dataset.settingsSection === activeSection);
            });

            hideAlbumBackground();
            contentTitle.textContent = t('settings.title', 'Paramètres');
            contentBody.innerHTML = `<div class="settings-page">${getSettingsSectionHtml(activeSection)}</div>`;

            // ── Storage settings modal (for current user) ─────────────────────
            const STORAGE_URL = `${BASE_PATH}/api/storage.php`;
            const storageFetch = async (action, body = null) => {
                const opts = { method: body ? 'POST' : 'GET' };
                if (body) { const fd = new FormData(); Object.entries(body).forEach(([k,v]) => fd.append(k, v)); opts.body = fd; }
                const r = await fetch(`${STORAGE_URL}?action=${action}`, opts);
                return r.json();
            };

            window.openStorageModal = () => {
                const storageType = app.storageType || 'local';
                const modal = document.createElement('div');
                modal.id = 'storageModal';
                modal.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,.6);z-index:99999;display:flex;align-items:center;justify-content:center;';
                modal.innerHTML = `
                    <div style="background:var(--bg-secondary);border:1px solid var(--border);border-radius:16px;padding:28px;min-width:360px;max-width:520px;width:92%;">
                        <h3 style="margin-bottom:18px;"><i class="ri-server-line"></i> ${t('settings.storage_of','Stockage — {name}').replace('{name}', escapeHtml(app.currentUser))}</h3>

                        <div style="margin-bottom:14px;">
                            <label style="font-size:13px;display:block;margin-bottom:6px;">${t('admin.storage_type','Type de stockage')}</label>
                            <select id="myStorageType" class="admin-input" style="width:100%" onchange="document.getElementById('myLocalFields').style.display=this.value==='local'?'block':'none';document.getElementById('mySftpFields').style.display=this.value==='sftp'?'block':'none'">
                                <option value="local" ${storageType !== 'sftp' ? 'selected' : ''}>${t('settings.local_storage','Local (répertoire sur le serveur)')}</option>
                                <option value="sftp" ${storageType === 'sftp' ? 'selected' : ''}>${t('settings.sftp_storage','SFTP (serveur distant)')}</option>
                            </select>
                        </div>

                        <div id="myLocalFields" style="display:${storageType !== 'sftp' ? 'block' : 'none'};margin-bottom:14px;">
                            <label style="font-size:12px;display:block;margin-bottom:4px;">${t('settings.local_subdir_label','Sous-dossier musique (relatif à /music)')}</label>
                            <input id="myMusicDir" class="admin-input" style="width:100%" placeholder="maxime" value="${escapeHtml(app.musicDir || '')}">
                        </div>

                        <div id="mySftpFields" style="display:${storageType === 'sftp' ? 'block' : 'none'}">
                            <div style="display:grid;grid-template-columns:1fr auto;gap:8px;margin-bottom:10px;">
                                <div>
                                    <label style="font-size:12px;display:block;margin-bottom:4px;">${t('settings.host','Hôte')}</label>
                                    <input id="mySftpHost" class="admin-input" style="width:100%" placeholder="sftp.example.com" value="${escapeHtml(app.sftpHost || '')}">
                                </div>
                                <div style="width:80px;">
                                    <label style="font-size:12px;display:block;margin-bottom:4px;">${t('setup.sftp_port','Port')}</label>
                                    <input id="mySftpPort" class="admin-input" type="number" style="width:100%" value="${app.sftpPort || 22}">
                                </div>
                            </div>
                            <div style="margin-bottom:10px;">
                                <label style="font-size:12px;display:block;margin-bottom:4px;">${t('setup.sftp_user','Utilisateur SFTP')}</label>
                                <input id="mySftpUser" class="admin-input" style="width:100%" placeholder="user" value="${escapeHtml(app.sftpUser || '')}">
                            </div>
                            <div style="margin-bottom:10px;">
                                <label style="font-size:12px;display:block;margin-bottom:4px;">${t('settings.sftp_pass_label','Mot de passe SFTP')} <span style="color:var(--text-secondary);font-size:11px">${t('settings.sftp_pass_hint',"(laisser vide pour conserver l'actuel)")}</span></label>
                                <input id="mySftpPassword" class="admin-input" type="password" style="width:100%" placeholder="••••••••">
                            </div>
                            <div style="margin-bottom:14px;">
                                <label style="font-size:12px;display:block;margin-bottom:4px;">${t('settings.sftp_path_label','Chemin distant (racine musique)')}</label>
                                <input id="mySftpPath" class="admin-input" style="width:100%" placeholder="/home/user/music" value="${escapeHtml(app.sftpPath || '')}">
                            </div>
                            <div style="margin-bottom:16px;">
                                <button id="myStorageTestBtn" class="rescan-btn" style="width:100%;justify-content:center;" onclick="testMyStorage()">
                                    <i class="ri-wifi-line"></i> ${t('setup.test_connection','Tester la connexion')}
                                </button>
                                <div id="myStorageTestResult" style="margin-top:6px;font-size:12px;min-height:16px;"></div>
                            </div>
                        </div>

                        <div style="display:flex;gap:8px;justify-content:flex-end;">
                            <button class="rescan-btn" onclick="document.getElementById('storageModal')?.remove()">${t('common.cancel','Annuler')}</button>
                            <button class="rescan-btn" style="background:var(--accent);color:#fff;" onclick="saveMyStorage()">
                                <i class="ri-save-line"></i> ${t('common.save','Enregistrer')}
                            </button>
                        </div>
                    </div>
                `;
                document.body.appendChild(modal);
            };

            window.testMyStorage = async () => {
                const btn    = document.getElementById('myStorageTestBtn');
                const result = document.getElementById('myStorageTestResult');
                btn.disabled = true;
                result.textContent = t('settings.testing', 'Test en cours…');
                result.style.color = 'var(--text-secondary)';

                const r = await storageFetch('test_sftp', {
                    sftp_host:     document.getElementById('mySftpHost')?.value || '',
                    sftp_port:     document.getElementById('mySftpPort')?.value || '22',
                    sftp_user:     document.getElementById('mySftpUser')?.value || '',
                    sftp_password: document.getElementById('mySftpPassword')?.value || '',
                    sftp_path:     document.getElementById('mySftpPath')?.value || '',
                });

                btn.disabled = false;
                if (r.success) {
                    result.textContent = r.message || t('admin.connection_ok', '✓ Connexion réussie');
                    result.style.color = '#00b894';
                } else {
                    result.textContent = r.error || t('admin.connection_fail', '✗ Erreur inconnue');
                    result.style.color = '#ff6b6b';
                }
            };

            window.saveMyStorage = async () => {
                const storageType = document.getElementById('myStorageType')?.value || 'local';
                const r = await storageFetch('update_storage', {
                    storage_type:  storageType,
                    music_directory: document.getElementById('myMusicDir')?.value || '',
                    sftp_host:     document.getElementById('mySftpHost')?.value || '',
                    sftp_port:     document.getElementById('mySftpPort')?.value || '22',
                    sftp_user:     document.getElementById('mySftpUser')?.value || '',
                    sftp_password: document.getElementById('mySftpPassword')?.value || '',
                    sftp_path:     document.getElementById('mySftpPath')?.value || '',
                });
                document.getElementById('storageModal')?.remove();
                if (r.success) {
                    app.storageType = storageType;
                    if (storageType === 'local') {
                        app.musicDir = document.getElementById('myMusicDir')?.value || '';
                        app.sftpHost = ''; app.sftpPath = '';
                    } else {
                        app.sftpHost = document.getElementById('mySftpHost')?.value || '';
                        app.sftpPort = parseInt(document.getElementById('mySftpPort')?.value || '22');
                        app.sftpUser = document.getElementById('mySftpUser')?.value || '';
                        app.sftpPath = document.getElementById('mySftpPath')?.value || '';
                    }
                    showToast(t('toast.storage_saved', 'Paramètres de stockage enregistrés'), 'success');
                    renderSettings('library');
                } else {
                    showToast(r.error || t('common.error', 'Erreur'), 'error');
                }
            };

            // ── Lang ──────────────────────────────────────────────────────────
            window.setLang = async (lang) => {
                app.lang = lang;
                localStorage.setItem('gullify_lang', lang);
                document.cookie = `gullify_lang=${encodeURIComponent(lang)};path=/;max-age=31536000`;
                try {
                    const resp = await fetch(`get_lang.php?lang=${encodeURIComponent(lang)}`);
                    window.gullifyLang = await resp.json();
                } catch (e) {
                    console.warn('Failed to load translations for', lang, e);
                }
                document.documentElement.lang = lang;
                applyI18n();
                renderSettings('language');
            };

            // Post-render hook for admin section
            if (activeSection === 'admin') initAdminSection();

            // Expose as global so sidebar onclick="renderSettingsSection(...)" works
            window.renderSettingsSection = renderSettings;

        }

        // ── Library scan buttons ────────────────────────────────────────────────
        // Global functions called via onclick in renderSettings HTML.
        let _scanPollingInterval = null;

        window.triggerLibraryScan = async function(scanType, btn) {
            if (btn.disabled) return;
            const icon = btn.querySelector('i');
            const text = btn.querySelector('span');
            const origIcon = icon ? icon.className : '';
            const origText = text ? text.textContent : t('common.run', 'Lancer');

            btn.disabled = true;
            if (icon) icon.className = 'ri-loader-4-line ri-spin';
            if (text) text.textContent = t('scan.scanning', 'Scan en cours...');

            const actionMap = { fast: 'fast_scan', force: 'force_scan', artwork: 'artwork_scan' };
            const action = actionMap[scanType] || 'force_scan';

            try {
                const response = await fetch(`${API_URL}?action=${action}&user=${encodeURIComponent(app.currentUser)}`);
                const result = await response.json();
                if (!result.success) throw new Error(result.error || t('common.error', 'Erreur'));
                showToast(t('scan.launched', 'Scan lancé...'), 'info');

                const progressContainer = document.getElementById('scan-progress-container');
                const statusText = document.getElementById('scan-status-text');
                const percentText = document.getElementById('scan-percent-text');
                const scanProgressBar = document.getElementById('scan-progress-bar');
                const currentFile = document.getElementById('scan-current-file');

                if (progressContainer) progressContainer.style.display = 'block';

                if (_scanPollingInterval) clearInterval(_scanPollingInterval);
                _scanPollingInterval = setInterval(async () => {
                    try {
                        const sr = await fetch(`${API_URL}?action=scan_status`);
                        const st = await sr.json();

                        if (st.success && st.data) {
                            const data = st.data;
                            const progress = data.progress;

                            if (progress) {
                                let label = 'Scan en cours...';
                                let percent = 0;

                                switch(progress.status) {
                                    case 'counting': label = t('scan.counting','Comptage des fichiers...'); break;
                                                                        case 'scanning': 
                                                                            if (progress.total > 0) {
                                                                                label = `${t('scan.scanning','Scan des fichiers')} (${progress.processed}/${progress.total})`;
                                                                                percent = Math.round((progress.processed / progress.total) * 100);
                                                                                if (scanProgressBar) scanProgressBar.classList.remove('progress-indeterminate');
                                                                            } else {
                                                                                label = `${t('scan.scanning','Scan des fichiers')} (${progress.processed})`;
                                                                                percent = 100; // Bar is full width but with the animation
                                                                                if (scanProgressBar) scanProgressBar.classList.add('progress-indeterminate');
                                                                            }
                                                                            break;
                                                                        case 'pruning': label = t('scan.pruning','Nettoyage des fichiers supprimés...'); percent = 90; break;
                                                                        case 'artwork': label = t('scan.artwork_caching','Mise en cache des pochettes...'); percent = 95; break;
                                                                        case 'artist_images': label = t('scan.artist_images',"Images d'artistes..."); percent = 97; break;
                                                                        case 'stats': label = t('scan.stats_update','Mise à jour des statistiques...'); percent = 99; break;
                                                                        case 'idle': label = t('scan.complete','Terminé !'); percent = 100; break;
                                                                    }
                                    
                                                                    if (statusText) statusText.textContent = label;
                                                                    if (percentText) percentText.textContent = percent + '%';
                                                                    if (scanProgressBar) scanProgressBar.style.width = percent + '%';
                                                                    if (currentFile) currentFile.textContent = progress.current_file || '';
                                                                }
                                    
                                                                if (!data.scanning) {
                                                                    clearInterval(_scanPollingInterval);
                                                                    _scanPollingInterval = null;
                                                                    if (icon) icon.className = 'ri-check-line';
                                                                    if (text) text.textContent = t('scan.complete', 'Terminé !');
                                                                    if (percentText) percentText.textContent = '100%';
                                                                    if (scanProgressBar) scanProgressBar.style.width = '100%';
                                                                    await loadLibrary();
                                showToast(t('toast.library_updated', 'Bibliothèque mise à jour !'), 'success');

                                setTimeout(() => {
                                    btn.disabled = false;
                                    if (icon) icon.className = origIcon;
                                    if (text) text.textContent = origText;
                                    if (progressContainer) progressContainer.style.display = 'none';
                                }, 3000);
                            }
                        }
                    } catch(e) { console.error('Polling error:', e); }
                }, 1500);

            } catch (error) {
                if (icon) icon.className = 'ri-error-warning-line';
                if (text) text.textContent = t('common.error', 'Erreur');
                showToast(error.message, 'error');
                setTimeout(() => {
                    btn.disabled = false;
                    if (icon) icon.className = origIcon;
                    if (text) text.textContent = origText;
                }, 3000);
            }
        };

        window.updateThemeButton = function() {
            const isDark = document.documentElement.getAttribute('data-theme') === 'dark';
            const icon = document.getElementById('themeIcon');
            const text = document.getElementById('themeText');
            if (icon && text) {
                icon.className = isDark ? 'ri-sun-line' : 'ri-moon-line';
                text.textContent = isDark ? 'Mode Clair' : 'Mode Sombre';
            }
        };

        // Expose functions to window for global player overrides
        window.playAlbum = playAlbum;
        window.shuffleAlbum = shuffleAlbum;
        window.playArtistSongs = playArtistSongs;
        window.playRandomSongs = playRandomSongs;
        window.playRandomArtist = playRandomArtist;
        window.playSongFromAlbum = playSongFromAlbum;
        window.addSongToQueue = addSongToQueue;
        window.startRadio = startRadio;

        // Event Listeners
        function setupEventListeners() {
            // User selection
            // User is determined by login session (no user selector)

            // Navigation
            navItems.forEach(item => {
                item.addEventListener('click', () => {
                    if (item.classList.contains('nav-item-parent')) {
                        item.classList.toggle('open');
                        document.getElementById('settingsSubmenu')?.classList.toggle('open');
                        return;
                    }
                    renderView(item.dataset.view);
                    closeMenu();
                });
            });

            // Settings submenu items
            document.querySelectorAll('.nav-subitem[data-settings-section]').forEach(item => {
                item.addEventListener('click', () => {
                    app.currentView = 'settings';
                    navItems.forEach(n => n.classList.toggle('active', n.dataset.view === 'settings'));
                    renderSettings(item.dataset.settingsSection);
                    closeMenu();
                });
            });

            // Search
            let searchTimeout;
            searchInput.addEventListener('input', (e) => {
                clearTimeout(searchTimeout);
                searchTimeout = setTimeout(() => performSearch(e.target.value), 300);
            });

            // Keyboard shortcuts
            document.addEventListener('keydown', handleKeyboardShortcuts);
        }

        function handleKeyboardShortcuts(e) {
            // Ignore if user is typing in an input field
            if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || !window.gullifyPlayer) {
                return;
            }

            const audio = window.gullifyPlayer.audio;

            switch(e.code) {
                case 'Space':
                    e.preventDefault();
                    window.gullifyPlayer.togglePlay();
                    break;
                case 'ArrowRight':
                    e.preventDefault();
                    // Skip forward 5 seconds
                    if (audio && audio.duration) {
                        audio.currentTime = Math.min(audio.currentTime + 5, audio.duration);
                    }
                    break;
                case 'ArrowLeft':
                    e.preventDefault();
                    // Skip backward 5 seconds
                    if (audio && audio.duration) {
                        audio.currentTime = Math.max(audio.currentTime - 5, 0);
                    }
                    break;
                case 'ArrowUp':
                    e.preventDefault();
                    // Volume up
                    window.gullifyPlayer.volume = Math.min(window.gullifyPlayer.volume + 0.1, 1);
                    if (audio) audio.volume = window.gullifyPlayer.volume;
                    if (window.gullifyPlayer.volumeSlider) window.gullifyPlayer.volumeSlider.value = window.gullifyPlayer.volume * 100;
                    break;
                case 'ArrowDown':
                    e.preventDefault();
                    // Volume down
                    window.gullifyPlayer.volume = Math.max(window.gullifyPlayer.volume - 0.1, 0);
                    if (audio) audio.volume = window.gullifyPlayer.volume;
                    if (window.gullifyPlayer.volumeSlider) window.gullifyPlayer.volumeSlider.value = window.gullifyPlayer.volume * 100;
                    break;
                case 'KeyN':
                    e.preventDefault();
                    window.gullifyPlayer.playNext();
                    break;
                case 'KeyP':
                    e.preventDefault();
                    window.gullifyPlayer.playPrevious();
                    break;
                case 'KeyS':
                    e.preventDefault();
                    window.gullifyPlayer.toggleShuffle();
                    break;
                case 'KeyR':
                    e.preventDefault();
                    window.gullifyPlayer.toggleRepeat();
                    break;
            }
        }

        async function toggleFavorite(songId) {
            try {
                const isCurrentlyFavorite = app.favorites.includes(songId);

                // Optimistic UI update
                if (isCurrentlyFavorite) {
                    const index = app.favorites.indexOf(songId);
                    if (index > -1) {
                        app.favorites.splice(index, 1);
                    }
                } else {
                    app.favorites.push(songId);
                }
                updateFavoriteIcons(songId);


                const formData = new FormData();
                formData.append('song_id', songId);
                formData.append('user', app.currentUser);

                const response = await fetch(`${API_URL}?action=toggle_favorite`, {
                    method: 'POST',
                    body: formData
                });
                const result = await response.json();

                if (result.error) {
                    throw new Error(result.error);
                }

                // If the current view is favorites, re-render it to remove the item
                if (app.currentView === 'favorites' && result.data.status === 'removed') {
                    renderFavorites();
                }

            } catch (error) {
                console.error('Failed to toggle favorite:', error);
                // Revert optimistic UI update on error
                if (app.favorites.includes(songId)) {
                    app.favorites = app.favorites.filter(id => id !== songId);
                } else {
                    app.favorites.push(songId);
                }
                updateFavoriteIcons(songId);
                showToast(t('toast.update_favorites_error', 'Erreur lors de la mise à jour des favoris'), 'error');
            }
        }

        function updateFavoriteIcons(songId) {
            const isFavorite = app.favorites.includes(songId);
            const buttons = document.querySelectorAll(`.favorite-btn[data-song-id="${songId}"]`);
            buttons.forEach(btn => {
                btn.innerHTML = isFavorite ? ICON_HEART_FILLED : ICON_HEART_EMPTY;
                btn.classList.toggle('active', isFavorite);
            });

            // Update main player button if it's the current song
            const currentTrack = app.queue[app.currentTrackIndex];
            if (currentTrack && currentTrack.id === songId) {
                playerFavoriteBtn.innerHTML = isFavorite ? ICON_HEART_FILLED : ICON_HEART_EMPTY;
                playerFavoriteBtn.classList.toggle('active', isFavorite);
            }
        }

        // ========== ARTIST FAVORITES ==========
        async function toggleArtistFavorite(artistId) {
            const btn = document.getElementById(`artist-fav-btn-${artistId}`);
            if (!btn) return;

            try {
                const formData = new FormData();
                formData.append('artist_id', artistId);
                formData.append('user', app.currentUser);

                const response = await fetch(`${API_URL}?action=toggle_favorite_artist`, {
                    method: 'POST',
                    body: formData
                });
                const result = await response.json();

                if (result.error) {
                    throw new Error(result.message);
                }

                const isFavorite = result.data.isFavorite;
                btn.innerHTML = isFavorite ? '<i class="ri-heart-fill"></i>' : '<i class="ri-heart-line"></i>';
                btn.classList.toggle('active', isFavorite);
                showToast(isFavorite ? t('favorites.artist_added', 'Artiste ajouté aux favoris') : t('favorites.artist_removed', 'Artiste retiré des favoris'), 'success');
            } catch (error) {
                console.error('Error toggling artist favorite:', error);
                showToast(t('toast.update_error', 'Erreur lors de la mise à jour'), 'error');
            }
        }

        async function checkArtistFavorite(artistId) {
            try {
                const response = await fetch(`${API_URL}?action=is_artist_favorite&artist_id=${artistId}&user=${app.currentUser}`);
                const result = await response.json();
                if (!result.error && result.data.isFavorite) {
                    const btn = document.getElementById(`artist-fav-btn-${artistId}`);
                    if (btn) {
                        btn.innerHTML = '<i class="ri-heart-fill"></i>';
                        btn.classList.add('active');
                    }
                }
            } catch (error) {
                console.error('Error checking artist favorite:', error);
            }
        }

        // ========== ALBUM FAVORITES ==========
        async function toggleAlbumFavorite(albumId) {
            const btn = document.getElementById(`album-fav-btn-${albumId}`);
            if (!btn) return;

            try {
                const formData = new FormData();
                formData.append('album_id', albumId);
                formData.append('user', app.currentUser);

                const response = await fetch(`${API_URL}?action=toggle_favorite_album`, {
                    method: 'POST',
                    body: formData
                });
                const result = await response.json();

                if (result.error) {
                    throw new Error(result.message);
                }

                const isFavorite = result.data.isFavorite;
                btn.innerHTML = isFavorite ? '<i class="ri-heart-fill"></i>' : '<i class="ri-heart-line"></i>';
                btn.classList.toggle('active', isFavorite);
                showToast(isFavorite ? t('favorites.album_added', 'Album ajouté aux favoris') : t('favorites.album_removed', 'Album retiré des favoris'), 'success');
            } catch (error) {
                console.error('Error toggling album favorite:', error);
                showToast(t('toast.update_error', 'Erreur lors de la mise à jour'), 'error');
            }
        }

        async function checkAlbumFavorite(albumId) {
            try {
                const response = await fetch(`${API_URL}?action=is_album_favorite&album_id=${albumId}&user=${app.currentUser}`);
                const result = await response.json();
                if (!result.error && result.data.isFavorite) {
                    const btn = document.getElementById(`album-fav-btn-${albumId}`);
                    if (btn) {
                        btn.innerHTML = '<i class="ri-heart-fill"></i>';
                        btn.classList.add('active');
                    }
                }
            } catch (error) {
                console.error('Error checking album favorite:', error);
            }
        }

        function togglePlay() {
            if (app.isPlaying) {
                window.gullifyPlayer.audio.pause();
                window.gullifyPlayer.playBtn.innerHTML = ICON_PLAY;
                const mobilePlayBtn = document.getElementById('mobilePlayBtn');
                if (mobilePlayBtn) {
                    mobilePlayBtn.innerHTML = ICON_PLAY;
                }
                app.isPlaying = false;
            } else {
                window.gullifyPlayer.audio.play();
                window.gullifyPlayer.playBtn.innerHTML = ICON_PAUSE;
                const mobilePlayBtn = document.getElementById('mobilePlayBtn');
                if (mobilePlayBtn) {
                    mobilePlayBtn.innerHTML = ICON_PAUSE;
                }
                app.isPlaying = true;
            }
        }

        function playPrevious() {
            if (app.currentTrackIndex > 0) {
                app.currentTrackIndex--;
                loadTrack(app.queue[app.currentTrackIndex]);
            }
        }

        function playNext() {
            if (app.currentTrackIndex < app.queue.length - 1) {
                app.currentTrackIndex++;
                loadTrack(app.queue[app.currentTrackIndex]);
            }
        }

        function toggleShuffle() {
            app.shuffle = !app.shuffle;
            window.gullifyPlayer.shuffleBtn.classList.toggle('active', app.shuffle);
            const mobileShuffleBtn = document.getElementById('mobileShuffleBtn');
            if (mobileShuffleBtn) {
                mobileShuffleBtn.style.color = app.shuffle ? 'var(--text-primary)' : 'var(--text-secondary)';
            }
        }

        function toggleRepeat() {
            const modes = ['none', 'all', 'one'];
            const currentIndex = modes.indexOf(app.repeat);
            app.repeat = modes[(currentIndex + 1) % modes.length];

            window.gullifyPlayer.repeatBtn.classList.toggle('active', app.repeat !== 'none');
            const mobileRepeatBtn = document.getElementById('mobileRepeatBtn');

            if (app.repeat === 'one') {
                window.gullifyPlayer.repeatBtn.innerHTML = ICON_REPEAT_ONE;
                if (mobileRepeatBtn) {
                    mobileRepeatBtn.innerHTML = ICON_REPEAT_ONE;
                    mobileRepeatBtn.style.color = 'var(--text-primary)';
                }
            } else if (app.repeat === 'all') {
                window.gullifyPlayer.repeatBtn.innerHTML = ICON_REPEAT;
                if (mobileRepeatBtn) {
                    mobileRepeatBtn.innerHTML = ICON_REPEAT;
                    mobileRepeatBtn.style.color = 'var(--text-primary)';
                }
            } else {
                window.gullifyPlayer.repeatBtn.innerHTML = ICON_REPEAT;
                if (mobileRepeatBtn) {
                    mobileRepeatBtn.innerHTML = ICON_REPEAT;
                    mobileRepeatBtn.style.color = 'var(--text-primary)';
                }
            }
        }

        function seekTo(e) {
            const rect = window.gullifyPlayer.progressBar.getBoundingClientRect();
            const percent = (e.clientX - rect.left) / rect.width;
            window.gullifyPlayer.audio.currentTime = percent * window.gullifyPlayer.audio.duration;
        }

        function updateProgress() {
            if (!window.gullifyPlayer.audio.duration || isNaN(window.gullifyPlayer.audio.duration)) return;
            const percent = (window.gullifyPlayer.audio.currentTime / window.gullifyPlayer.audio.duration) * 100;
            window.gullifyPlayer.progressFill.style.width = percent + '%';
            window.gullifyPlayer.currentTimeEl.textContent = formatDuration(window.gullifyPlayer.audio.currentTime);

            // Update mobile player progress and time
            const mobileProgressFill = document.getElementById('mobileProgressFill');
            const mobileCurrentTime = document.getElementById('mobileCurrentTime');
            const mobileTotalTime = document.getElementById('mobileTotalTime');

            if (mobileProgressFill) mobileProgressFill.style.width = percent + '%';
            if (mobileCurrentTime) mobileCurrentTime.textContent = formatDuration(window.gullifyPlayer.audio.currentTime);
            if (mobileTotalTime) mobileTotalTime.textContent = formatDuration(window.gullifyPlayer.audio.duration);

            // Update lock screen / notification progress bar
            if ('mediaSession' in navigator && window.gullifyPlayer.audio.duration > 0) {
                navigator.mediaSession.setPositionState({
                    duration: window.gullifyPlayer.audio.duration,
                    playbackRate: window.gullifyPlayer.audio.playbackRate || 1,
                    position: window.gullifyPlayer.audio.currentTime,
                });
            }
        }

        function updateDuration() {
            if (!window.gullifyPlayer.audio.duration || isNaN(window.gullifyPlayer.audio.duration)) return;
            window.gullifyPlayer.totalTimeEl.textContent = formatDuration(window.gullifyPlayer.audio.duration);

            // Update mobile player
            const mobileTotalTime = document.getElementById('mobileTotalTime');
            if (mobileTotalTime) mobileTotalTime.textContent = formatDuration(window.gullifyPlayer.audio.duration);
        }

        function handleTrackEnded() {
            // Record completed play
            const currentTrack = app.queue[app.currentTrackIndex];
            if (currentTrack && currentTrack.id) {
                recordPlay(currentTrack.id, currentTrack.duration || window.gullifyPlayer.audio.duration, true);
            }

            // Check if we need to reload radio songs
            checkAndReloadRadio();

            if (app.repeat === 'one') {
                window.gullifyPlayer.audio.currentTime = 0;
                window.gullifyPlayer.audio.play();
            } else if (app.currentTrackIndex < app.queue.length - 1) {
                playNext();
            } else if (app.repeat === 'all') {
                app.currentTrackIndex = 0;
                loadTrack(app.queue[0]);
            } else if (app.radioMode) {
                // In radio mode, always continue playing
                playNext();
            } else {
                window.gullifyPlayer.playBtn.innerHTML = ICON_PLAY;
                app.isPlaying = false;
            }
        }

        function handleAudioError(e) {
            console.error('Audio playback error:', e);
            const currentTrack = app.queue[app.currentTrackIndex];

            if (currentTrack) {
                showToast(t('toast.play_error','Impossible de lire: {title}').replace('{title}', currentTrack.title), 'error', 4000);

                // Try to skip to next track after a short delay
                setTimeout(() => {
                    if (app.currentTrackIndex < app.queue.length - 1) {
                        playNext();
                    }
                }, 2000);
            } else {
                showToast(t('toast.play_audio_error', 'Erreur de lecture audio'), 'error');
            }

            window.gullifyPlayer.playBtn.innerHTML = ICON_PLAY;
            const mobilePlayBtn = document.getElementById('mobilePlayBtn');
            if (mobilePlayBtn) {
                mobilePlayBtn.innerHTML = ICON_PLAY;
            }
            app.isPlaying = false;
        }

        // Redundant audio playback and queue management functions removed
        // (Handled by UnifiedMusicPlayer)

        async function performSearch(query) {
            if (!query || query.length < 2) {
                renderView(app.currentView);
                return;
            }

            try {
                showLoading();

                const response = await fetch(`${BASE_PATH}/api/library.php?user=${app.currentUser}&action=search&q=${encodeURIComponent(query)}`);
                const result = await response.json();

                if (result.error) {
                    showError(t('errors.search', 'Erreur lors de la recherche'), `performSearch('${escapeHtml(query)}')`);
                    return;
                }

                const songs = result.data.songs || [];

                if (songs.length === 0) {
                    contentBody.innerHTML = `
                        <div class="empty-state">
                            <div class="empty-state-icon">🔍</div>
                            <p>Aucun résultat pour "${escapeHtml(query)}"</p>
                            <button onclick="searchInput.value=''; renderView('home')" class="back-btn" style="margin-top: 20px; padding: 10px 25px;">
                                ← Retour à l'accueil
                            </button>
                        </div>
                    `;
                    return;
                }

                contentTitle.textContent = t('counts.search_results','Résultats pour "{q}" ({n})').replace('{q}', query).replace('{n}', songs.length);

                const html = `
                    <div>
                        <div class="song-list">
                            ${songs.map((song, index) => `
                                <div class="song-item" data-song-id="${song.id}" onclick="playFromSearchResults(${index})" oncontextmenu="showContextMenu(event, ${song.id})">
                                    <div class="song-number">${index + 1}</div>
                                    <div class="song-play-icon">▶</div>
                                    <div class="song-thumbnail">
                                        <img src="${song.artworkUrl || DEFAULT_ALBUM_IMG}" alt="${escapeHtml(song.title)}">
                                    </div>
                                    <div class="song-info">
                                        <div class="song-title">${escapeHtml(song.title)}</div>
                                        <div class="song-artist">${escapeHtml(song.artistName)}</div>
                                    </div>
                                    <div class="song-duration">${formatDuration(song.duration)}</div>
                                </div>
                            `).join('')}
                        </div>
                    </div>
                `;

                contentBody.innerHTML = html;
                window.currentSearchResults = songs; // Store for playback
            } catch (error) {
                console.error('Error searching:', error);
                showError(t('errors.search_fail', "Impossible d'effectuer la recherche"));
            }
        }

        function playFromSearchResults(index) {
            if (!window.currentSearchResults) return;
            const track = window.currentSearchResults[index];
            app.queue = [{
                ...track,
                artist: track.artistName, // Ensure correct property mapping
                album: track.albumName
            }];
            app.currentTrackIndex = 0;
            loadTrack(app.queue[0]);
            renderQueue();
        }

        // Chargement des images avec cache
        async function loadArtistImage(artistId) {
            try {
                const cacheKey = `artist-${artistId}`;

                // Check cache first
                if (app.imageCache[cacheKey]) {
                    // Try multiple possible IDs
                    const el = document.getElementById(`artist-avatar-${artistId}`) ||
                               document.getElementById(`artist-img-${artistId}`);
                    if (el) {
                        el.innerHTML = `<img src="${app.imageCache[cacheKey]}" alt="Artist" style="width: 100%; height: 100%; object-fit: cover;">`;
                    }
                    return;
                }

                const response = await fetch(`${BASE_PATH}/get_image_mysql.php?type=artist&id=${artistId}`);
                const result = await response.json();

                if (!result.error && result.image) {
                    const imgSrc = `data:image/jpeg;base64,${result.image}`;
                    app.imageCache[cacheKey] = imgSrc; // Store in cache

                    // Try multiple possible IDs
                    const el = document.getElementById(`artist-avatar-${artistId}`) ||
                               document.getElementById(`artist-img-${artistId}`);
                    if (el) {
                        el.innerHTML = `<img src="${imgSrc}" alt="Artist" style="width: 100%; height: 100%; object-fit: cover;">`;
                    }
                }
            } catch (error) {
                console.error('Error loading artist image:', error);
            }
        }

        async function loadAlbumCover(albumId) {
            try {
                const cacheKey = `album-${albumId}`;

                // Check cache first
                if (app.imageCache[cacheKey]) {
                    const el = document.getElementById(`album-cover-${albumId}`);
                    if (el) {
                        el.innerHTML = `<img src="${app.imageCache[cacheKey]}" alt="Album" style="width: 100%; height: 100%; object-fit: cover;">`;
                    }
                    return;
                }

                const response = await fetch(`${BASE_PATH}/get_image_mysql.php?type=album&id=${albumId}`);
                const result = await response.json();

                if (!result.error && result.image) {
                    const imgSrc = `data:image/jpeg;base64,${result.image}`;
                    app.imageCache[cacheKey] = imgSrc; // Store in cache

                    const el = document.getElementById(`album-cover-${albumId}`);
                    if (el) {
                        el.innerHTML = `<img src="${imgSrc}" alt="Album" style="width: 100%; height: 100%; object-fit: cover;">`;
                    }
                }
            } catch (error) {
                console.error('Error loading album cover:', error);
            }
        }

        async function loadAlbumCoverLarge(albumId) {
            try {
                const cacheKey = `album-${albumId}`;

                let imgSrc = app.imageCache[cacheKey];

                if (!imgSrc) {
                    const response = await fetch(`${BASE_PATH}/get_image_mysql.php?type=album&id=${albumId}`);
                    const result = await response.json();

                    if (!result.error && result.image) {
                        imgSrc = `data:image/jpeg;base64,${result.image}`;
                        app.imageCache[cacheKey] = imgSrc; // Store in cache
                    }
                }

                if (imgSrc) {
                    const el = document.getElementById(`album-cover-large-${albumId}`);
                    if (el) {
                        el.innerHTML = `<img src="${imgSrc}" alt="Album" style="width: 100%; height: 100%; object-fit: cover;">`;
                    }

                    // Also update song thumbnails
                    const songThumbs = document.querySelectorAll('[id^="song-thumb-"]');
                    songThumbs.forEach(thumb => {
                        thumb.innerHTML = `<img src="${imgSrc}" alt="Song" style="width: 100%; height: 100%; object-fit: cover;">`;
                    });

                    // Update currentAlbumData with artwork
                    if (window.currentAlbumData) {
                        window.currentAlbumData.artwork = imgSrc;
                    }
                }
            } catch (error) {
                console.error('Error loading album cover:', error);
            }
        }

        // Auto-load missing artist images from YouTube Music
        async function autoLoadMissingArtistImages() {
            if (!app.library || !app.library.artists) return;

            // Find all artists without images
            const artistsWithoutImages = app.library.artists.filter(artist => !artist.image);

            if (artistsWithoutImages.length === 0) {
                console.log('All artists have images!');
                return;
            }

            console.log(`Found ${artistsWithoutImages.length} artists without images. Loading from YouTube Music...`);

            // Load images progressively (one at a time with delay to avoid rate limiting)
            for (let i = 0; i < artistsWithoutImages.length; i++) {
                const artist = artistsWithoutImages[i];

                try {
                    console.log(`[${i + 1}/${artistsWithoutImages.length}] Loading image for: ${artist.name}`);

                    // Fetch YouTube Music data for this artist
                    const url = `${BASE_PATH}/youtube-search.php?artist=${encodeURIComponent(artist.name)}`;
                    const response = await fetch(url);
                    const result = await response.json();

                    // If we found an artist image on YouTube Music, download and save it
                    if (result.artist && result.artist.thumbnail) {
                        await downloadAndSaveArtistImage(artist.id, result.artist.thumbnail);
                        console.log(`✅ Image saved for: ${artist.name}`);

                        // Update the artist object in memory so we don't try to reload it
                        artist.image = true; // Mark as having image
                    } else {
                        console.log(`⚠️ No image found on YouTube Music for: ${artist.name}`);
                    }

                    // Wait 1 second between requests to avoid rate limiting
                    if (i < artistsWithoutImages.length - 1) {
                        await new Promise(resolve => setTimeout(resolve, 1000));
                    }

                } catch (error) {
                    console.error(`Error loading image for ${artist.name}:`, error);
                    // Continue with next artist even if this one fails
                }
            }

            console.log('✅ Finished loading artist images from YouTube Music');
        }

        // Download artist image from YouTube Music and save to database
        async function downloadAndSaveArtistImage(artistId, imageUrl) {
            try {
                // Fetch the image from YouTube Music
                const response = await fetch(imageUrl);
                if (!response.ok) throw new Error('Failed to fetch image');

                const blob = await response.blob();

                // Create a File object from the blob
                const file = new File([blob], 'artist.jpg', { type: 'image/jpeg' });

                // Prepare form data
                const formData = new FormData();
                formData.append('image', file);
                formData.append('artist_id', artistId);

                // Upload to server
                const uploadResponse = await fetch(`${BASE_PATH}/upload_artist_image.php`, {
                    method: 'POST',
                    body: formData
                });

                const uploadResult = await uploadResponse.json();

                if (uploadResult.error) {
                    throw new Error(uploadResult.message);
                }

                // Update UI with new image
                const imgSrc = 'data:image/jpeg;base64,' + uploadResult.image;
                const avatarEl = document.getElementById('artist-avatar-' + artistId);
                if (avatarEl) {
                    avatarEl.innerHTML = '<img src="' + imgSrc + '" style="width: 100%; height: 100%; object-fit: cover;">';
                }

                // Update cache
                app.imageCache['artist-' + artistId] = imgSrc;

                // Also update grid if present
                const gridEl = document.getElementById('artist-grid-' + artistId);
                if (gridEl) {
                    gridEl.innerHTML = '<img src="' + imgSrc + '" style="width: 100%; height: 100%; object-fit: cover;">';
                }

                // If we're currently viewing this artist, update the background
                if (avatarEl) {
                    // We're on the artist page, show as background
                    showArtistBackground(imgSrc);
                }

                console.log('✅ Artist image downloaded and saved from YouTube Music');

            } catch (error) {
                console.error('Error downloading/saving artist image:', error);
                throw error;
            }
        }

        // Lazy load artist images using Intersection Observer
        function setupArtistImageObserver() {
            // Track which artists we're already processing
            if (!app.artistImageQueue) {
                app.artistImageQueue = new Set();
            }

            // Create artist lookup map for quick access
            const artistMap = new Map();
            if (app.library && app.library.artists) {
                app.library.artists.forEach(artist => {
                    artistMap.set(artist.id, artist);
                });
            }

            // Limit concurrent fetches
            let activeFetches = 0;
            const maxConcurrent = 2;
            const pendingQueue = [];

            async function processArtist(artistId, element) {
                if (activeFetches >= maxConcurrent) {
                    pendingQueue.push({ artistId, element });
                    return;
                }

                activeFetches++;
                const artist = artistMap.get(artistId);

                try {
                    // Fetch YouTube Music data for this artist
                    const url = `${BASE_PATH}/youtube-search.php?artist=${encodeURIComponent(artist.name)}`;
                    const response = await fetch(url);
                    const result = await response.json();

                    // If we found an artist image on YouTube Music, download and save it
                    if (result.artist && result.artist.thumbnail) {
                        await downloadAndSaveArtistImage(artistId, result.artist.thumbnail);
                        console.log(`✅ Image loaded for: ${artist.name}`);

                        // Mark artist as having image now
                        artist.hasImage = true;
                        artist.imageUrl = `serve_image.php?artist_id=${artistId}`;
                    }
                } catch (error) {
                    console.error(`Error loading image for ${artist.name}:`, error);
                }

                activeFetches--;

                // Process next in queue
                if (pendingQueue.length > 0) {
                    const next = pendingQueue.shift();
                    processArtist(next.artistId, next.element);
                }
            }

            const observer = new IntersectionObserver((entries) => {
                entries.forEach(entry => {
                    if (entry.isIntersecting) {
                        const card = entry.target;
                        const artistId = parseInt(card.dataset.artistId);

                        // Only process if not already queued/processed
                        if (!app.artistImageQueue.has(artistId)) {
                            const artist = artistMap.get(artistId);

                            // Only fetch if artist doesn't have an image
                            if (artist && !artist.hasImage) {
                                app.artistImageQueue.add(artistId);
                                processArtist(artistId, card);
                            }
                        }

                        // Stop observing this element
                        observer.unobserve(card);
                    }
                });
            }, {
                root: document.getElementById('contentBody'),
                rootMargin: '100px', // Start loading 100px before visible
                threshold: 0.1
            });

            // Observe all artist cards
            document.querySelectorAll('.artist-card').forEach(card => {
                observer.observe(card);
            });

            // Store observer for cleanup
            app.artistImageObserver = observer;
        }

        // Download album in background (auto mode)
        async function downloadAlbumBackground(url, artistName, albumName, artistId) {
            try {
                showToast(t('toast.download_starting', '⚡ Lancement du téléchargement...'), 'info');

                const formData = new FormData();
                formData.append('action', 'start');
                formData.append('url', decodeURIComponent(url));
                formData.append('artist_name', artistName);
                formData.append('album_name', albumName);
                formData.append('user', app.currentUser);
                formData.append('artist_id', artistId);

                const response = await fetch(`${BASE_PATH}/download_album_api.php`, {
                    method: 'POST',
                    body: formData
                });

                const result = await response.json();

                if (result.success) {
                    showToast(t('toast.download_started','📥 Téléchargement démarré: {name}').replace('{name}', albumName), 'success', 5000);

                    // Poll for completion
                    const downloadId = result.download_id;
                    pollDownloadStatus(downloadId, artistName, albumName);
                } else {
                    showToast(t('toast.download_error','❌ Erreur: {msg}').replace('{msg}', result.error), 'error');
                }

            } catch (error) {
                console.error('Error starting download:', error);
                showToast(t('toast.download_start_error', '❌ Erreur lors du démarrage du téléchargement'), 'error');
            }
        }

        // Poll download status
        async function pollDownloadStatus(downloadId, artistName, albumName) {
            const checkStatus = async () => {
                try {
                    const response = await fetch(`${BASE_PATH}/download_album_api.php?action=status&download_id=${downloadId}`);
                    const result = await response.json();

                    if (result.success) {
                        const download = result.download;

                        if (download.status === 'completed') {
                            showToast(t('toast.download_complete','✅ {name} téléchargé et scanné!').replace('{name}', albumName), 'success', 5000);
                            // Reload library to show the new album
                            await loadLibrary();
                            return true; // Stop polling
                        } else if (download.status === 'error') {
                            showToast(`❌ Échec: ${download.message}`, 'error', 5000);
                            return true; // Stop polling
                        } else if (download.status === 'completed_scan_failed') {
                            showToast(t('toast.download_scan_fail','⚠️ {name} téléchargé mais scan échoué').replace('{name}', albumName), 'warning', 5000);
                            return true; // Stop polling
                        }
                        // Continue polling for queued, downloading, scanning
                    }

                    return false; // Continue polling
                } catch (error) {
                    console.error('Error checking download status:', error);
                    return false; // Continue polling despite errors
                }
            };

            // Poll every 3 seconds
            const pollInterval = setInterval(async () => {
                const shouldStop = await checkStatus();
                if (shouldStop) {
                    clearInterval(pollInterval);
                }
            }, 3000);

            // Initial check
            checkStatus();
        }

        // Load YouTube Music album suggestions and artist image
        async function loadYouTubeAlbumSuggestions(artistId, artistName, currentArtistImage, ownedAlbums) {
            try {
                console.log('Loading YouTube albums for:', artistName);
                // Fetch YouTube Music albums for this artist
                const url = `${BASE_PATH}/youtube-search.php?artist=${encodeURIComponent(artistName)}`;
                console.log('Fetching from:', url);
                const response = await fetch(url);
                console.log('Response status:', response.status);
                const result = await response.json();
                console.log('YouTube albums result:', result);

                // Download and save artist image from YouTube Music if we don't have one
                if (!currentArtistImage && result.artist && result.artist.thumbnail) {
                    console.log('Downloading artist image from YouTube Music:', result.artist.thumbnail);
                    try {
                        await downloadAndSaveArtistImage(artistId, result.artist.thumbnail);
                    } catch (imgError) {
                        console.error('Failed to download artist image:', imgError);
                        // Continue even if image download fails
                    }
                }

                if (result.error || !result.albums || result.albums.length === 0) {
                    console.log('No YouTube albums found or error');
                    return; // No suggestions available
                }

                // Normalize owned album titles for comparison
                const ownedTitles = ownedAlbums.map(album =>
                    album.name.toLowerCase().trim().replace(/[^a-z0-9]/g, '')
                );

                // Filter out albums we already own
                const missingAlbums = result.albums.filter(ytAlbum => {
                    const normalizedTitle = ytAlbum.title.toLowerCase().trim().replace(/[^a-z0-9]/g, '');
                    return !ownedTitles.includes(normalizedTitle);
                });

                if (missingAlbums.length === 0) {
                    return; // We own all albums
                }

                // Add a section for YouTube Music suggestions
                const suggestionsHTML = `
                    <div style="margin-top: 40px;">
                        <h3 style="margin-bottom: 15px; font-size: 20px; display: flex; align-items: center; gap: 10px;">
                            <span>Albums disponibles</span>
                            <span style="background: #FF0000; color: white; padding: 4px 10px; border-radius: 12px; font-size: 11px; font-weight: 700;">YouTube Music</span>
                        </h3>
                        <div class="album-grid">
                            ${missingAlbums.map(ytAlbum => `
                                <div class="album-card youtube-suggestion"
                                     style="opacity: 0.7; position: relative; cursor: pointer;"
                                     onmouseenter="this.style.opacity='1'"
                                     onmouseleave="this.style.opacity='0.7'"
                                     onclick="window.open('${ytAlbum.url}', '_blank')"
                                     title="Cliquez pour écouter sur YouTube Music">
                                    <div class="album-cover" style="position: relative; overflow: hidden;">
                                        ${ytAlbum.thumbnail ?
                                            `<img src="${ytAlbum.thumbnail}" alt="${ytAlbum.title}" style="width: 100%; height: 100%; object-fit: cover; filter: brightness(0.8);">` :
                                            `<div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); width: 100%; height: 100%; display: flex; align-items: center; justify-content: center;">
                                                <div style="color: white; font-size: 32px; font-weight: 700;">${ytAlbum.title.charAt(0).toUpperCase()}</div>
                                            </div>`
                                        }
                                        <div style="position: absolute; top: 8px; right: 8px; display: flex; gap: 8px;">
                                            <button onclick="event.stopPropagation(); downloadAlbumBackground('${encodeURIComponent(ytAlbum.url)}', '${escapeHtml(artistName)}', '${escapeHtml(ytAlbum.title)}', ${artistId})"
                                               style="background: rgba(76,175,80,0.95); color: white; width: 40px; height: 40px; border: none; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 20px; cursor: pointer; transition: transform 0.2s; box-shadow: 0 2px 8px rgba(0,0,0,0.3);"
                                               onmouseenter="this.style.transform='scale(1.15)'; this.style.background='rgba(76,175,80,1)'"
                                               onmouseleave="this.style.transform='scale(1)'; this.style.background='rgba(76,175,80,0.95)'"
                                               title="Télécharger automatiquement en arrière-plan">
                                                ⚡
                                            </button>
                                            <a href="/modules/yt_plex_download.php?yturl=${encodeURIComponent(ytAlbum.url)}&user=${encodeURIComponent(app.currentUser)}"
                                               target="_blank"
                                               onclick="event.stopPropagation()"
                                               style="background: rgba(0,0,0,0.85); color: white; width: 40px; height: 40px; border-radius: 50%; display: flex; align-items: center; justify-content: center; text-decoration: none; font-size: 20px; cursor: pointer; transition: transform 0.2s; box-shadow: 0 2px 8px rgba(0,0,0,0.3);"
                                               onmouseenter="this.style.transform='scale(1.15)'; this.style.background='rgba(0,0,0,0.95)'"
                                               onmouseleave="this.style.transform='scale(1)'; this.style.background='rgba(0,0,0,0.85)'"
                                               title="Télécharger manuellement (suivi en direct)">
                                                📥
                                            </a>
                                        </div>
                                    </div>
                                    <div class="album-name" style="opacity: 0.9;">${ytAlbum.title}</div>
                                    <div class="album-info" style="opacity: 0.7;">${ytAlbum.year || ''}</div>
                                </div>
                            `).join('')}
                        </div>
                        <p style="color: var(--text-secondary); font-size: 13px; margin-top: 15px; font-style: italic;">
                            💡 Cliquez sur l'album pour l'écouter sur YouTube Music • ⚡ Téléchargement auto • 📥 Téléchargement manuel
                        </p>
                    </div>
                `;

                // Append to content body
                contentBody.insertAdjacentHTML('beforeend', suggestionsHTML);

            } catch (error) {
                console.error('Error loading YouTube suggestions:', error);
            }
        }

        // Load album background for blur effect
        async function loadAlbumBackground(albumId) {
            try {
                const cacheKey = `album-${albumId}`;
                const albumBackground = document.getElementById('albumBackground');
                const albumBackgroundImage = document.getElementById('albumBackgroundImage');

                let imgSrc = app.imageCache[cacheKey];

                if (!imgSrc) {
                    const response = await fetch(`${BASE_PATH}/get_image_mysql.php?type=album&id=${albumId}`);
                    const result = await response.json();

                    if (!result.error && result.image) {
                        imgSrc = `data:image/jpeg;base64,${result.image}`;
                        app.imageCache[cacheKey] = imgSrc;
                    }
                }

                if (imgSrc) {
                    albumBackgroundImage.style.backgroundImage = `url('${imgSrc}')`;
                    albumBackground.classList.add('active');
                } else {
                    // If no image, hide background
                    albumBackground.classList.remove('active');
                }
            } catch (error) {
                console.error('Error loading album background:', error);
            }
        }

        // Hide album background
        function hideAlbumBackground() {
            const albumBackground = document.getElementById('albumBackground');
            if (albumBackground) {
                albumBackground.classList.remove('active');
            }
        }

        // Show artist image as background (Handled by bridge at top of file)

        // Mobile functions
        function showMobilePlayer() {
            if (window.gullifyPlayer) {
                window.gullifyPlayer.openMobilePlayer();
            }
        }

        function hideMobilePlayer() {
            if (window.gullifyPlayer) {
                window.gullifyPlayer.closeMobilePlayer();
            }
        }

        function toggleMobileMenu() {
            const sidebar = document.getElementById('sidebar');
            const menuOverlay = document.getElementById('menuOverlay');
            const mainContent = document.querySelector('.main-content');

            // Desktop mode (>1025px): toggle collapsed state
            if (window.innerWidth > 1025) {
                sidebar.classList.toggle('collapsed');
                if (mainContent) mainContent.classList.toggle('sidebar-collapsed');
            } else {
                // Mobile mode: toggle open state with overlay
                sidebar.classList.toggle('open');
                menuOverlay.classList.toggle('active');
            }
        }

        function closeMenu() {
            const sidebar = document.getElementById('sidebar');
            const menuOverlay = document.getElementById('menuOverlay');
            if (sidebar) sidebar.classList.remove('open');
            if (menuOverlay) menuOverlay.classList.remove('active');
        }

        function toggleSearch() {
            const headerTop = document.getElementById('headerTop');
            const input = document.getElementById('searchInput');
            const icon = document.getElementById('searchBtnIcon');
            const isActive = headerTop && headerTop.classList.contains('search-active');

            if (isActive) {
                headerTop.classList.remove('search-active');
                if (icon) icon.className = 'ri-search-line';
                input.blur();
                input.value = '';
                if (app.currentView === 'artists' || app.currentView === 'albums' || app.currentView === 'songs') {
                    renderView(app.currentView);
                }
            } else {
                if (headerTop) headerTop.classList.add('search-active');
                if (icon) icon.className = 'ri-close-line';
                setTimeout(() => input.focus(), 50);
            }
        }

        // Menu listeners
        const menuBtn = document.getElementById('menuBtn');
        const sidebar = document.getElementById('sidebar');

        if (menuBtn) {
            menuBtn.addEventListener('click', toggleMobileMenu);
        }

        // Empêcher la fermeture du menu quand on clique dedans
        if (sidebar) {
            sidebar.addEventListener('click', (e) => {
                e.stopPropagation();
            });
        }

        // Overlay listener - ferme le menu quand on clique dessus
        const menuOverlay = document.getElementById('menuOverlay');
        if (menuOverlay) {
            menuOverlay.addEventListener('click', closeMenu);
        }

        // Search button listener
        const searchBtn = document.getElementById('searchBtn');
        if (searchBtn) {
            searchBtn.addEventListener('click', toggleSearch);
        }

        // Close search when clicking outside
        document.addEventListener('click', (e) => {
            const headerTop = document.getElementById('headerTop');
            const wrap = document.getElementById('headerSearchWrap');
            if (headerTop && headerTop.classList.contains('search-active')) {
                if (wrap && !wrap.contains(e.target)) {
                    toggleSearch();
                }
            }
        });

        // Mobile close button
        const mobileCloseBtn = document.getElementById('mobileCloseBtn');
        if (mobileCloseBtn) {
            mobileCloseBtn.addEventListener('click', hideMobilePlayer);
        }

        // Mobile progress bar
        const mobileProgressBar = document.getElementById('mobileProgressBar');
        if (mobileProgressBar) {
            mobileProgressBar.addEventListener('click', (e) => {
                const rect = mobileProgressBar.getBoundingClientRect();
                const percent = (e.clientX - rect.left) / rect.width;
                window.gullifyPlayer.audio.currentTime = percent * window.gullifyPlayer.audio.duration;
            });
        }

        // Click on player on mobile opens now playing
        if (window.innerWidth <= 768) {
            document.querySelector('.player-song-info').addEventListener('click', () => {
                if (app.queue.length > 0) {
                    showMobilePlayer();
                }
            });
        }

        // ============================================
        // Premium Tag Editor - Apple Liquid Glass Style
        // ============================================

        const tagEditor = {
            albumId: null,
            albumData: null,
            songs: [],
            originalTags: {},
            modifiedSongs: new Set(),
            currentTab: 'edit',
            ytMusicResults: [],
            selectedYtAlbum: null,
            ytTrackList: null,        // full tracklist from YT Music (fetched on select)
            mbResults: [],            // MusicBrainz search results
            selectedMbRelease: null,  // selected MusicBrainz release
            mbTrackList: null,        // full tracklist from MusicBrainz
            pendingTrackList: null,   // { tracks, albumInfo } waiting for applyTrackList()
            _pendingYear: null,       // year to pre-fill after renderEditTab()
            _manualMapping: {},       // localSongIdx → proposedTrackIdx (-1 = ignore)
            genres: [], // List of all genres from database

            // Load genres from database (cached after first load)
            async loadGenres() {
                if (this.genres.length > 0) return; // Already loaded

                try {
                    const response = await fetch(`${BASE_PATH}/edit_tags.php?action=get_genres`);
                    const result = await response.json();
                    if (result.success) {
                        this.genres = result.data.genres;
                    }
                } catch (e) {
                    console.error('Failed to load genres:', e);
                }
            },

            // Build genre select HTML
            buildGenreSelect(selectedGenre, id, onchangeHandler) {
                let html = `<select id="${id}" class="genre-select" onchange="${onchangeHandler}">`;
                html += `<option value="">-- Sélectionner un genre --</option>`;

                this.genres.forEach(genre => {
                    const isMainSelected = selectedGenre === genre.name;
                    html += `<optgroup label="${this.escapeHtml(genre.name)}">`;
                    html += `<option value="${this.escapeHtml(genre.name)}" ${isMainSelected ? 'selected' : ''}>📁 ${this.escapeHtml(genre.name)}</option>`;

                    if (genre.subgenres && genre.subgenres.length > 0) {
                        genre.subgenres.forEach(sub => {
                            const isSubSelected = selectedGenre === sub.name;
                            html += `<option value="${this.escapeHtml(sub.name)}" ${isSubSelected ? 'selected' : ''}>&nbsp;&nbsp;&nbsp;${this.escapeHtml(sub.name)}</option>`;
                        });
                    }
                    html += `</optgroup>`;
                });

                html += `</select>`;
                return html;
            },

            // Open the tag editor for an album
            async open(albumId) {
                this.albumId = albumId;
                this.modifiedSongs.clear();
                this.selectedYtAlbum = null;

                const overlay = document.getElementById('tagEditorOverlay');
                overlay.classList.add('active');

                this.setStatus('Chargement...', 'loading');

                // Load genres in parallel with album data
                await Promise.all([
                    this.loadGenres(),
                    this.loadAlbumData()
                ]);

                // Render after both are loaded
                if (this.albumData) {
                    this.renderEditTab();
                }
            },

            // Close the editor
            close() {
                const overlay = document.getElementById('tagEditorOverlay');
                overlay.classList.remove('active');
                this.albumId = null;
                this.albumData = null;
                this.songs = [];
                this.originalTags = {};
                this.modifiedSongs.clear();
                this.selectedYtAlbum = null;
                this.ytMusicResults = [];
                this.ytTrackList = null;
                this.mbResults = [];
                this.selectedMbRelease = null;
                this.mbTrackList = null;
                this.pendingTrackList = null;
                this._pendingYear = null;
                this._manualMapping = {};
            },

            // Load album data from API
            async loadAlbumData() {
                try {
                    const response = await fetch(`${BASE_PATH}/tag_editor_api.php?action=get_album_tags&album_id=${this.albumId}`);
                    const result = await response.json();

                    if (!result.success) {
                        this.showEditorToast('Erreur: ' + (result.error || 'Impossible de charger l\'album'), 'error');
                        this.close();
                        return;
                    }

                    this.albumData = result.data.album;
                    this.songs = result.data.songs;

                    // Store original tags for change detection
                    this.songs.forEach(song => {
                        this.originalTags[song.id] = { ...song.file_tags };
                    });

                    document.getElementById('songCountBadge').textContent = this.songs.length;
                    this.setStatus('Prêt', 'ready');
                    // Note: renderEditTab() is now called from open() after genres are loaded

                } catch (error) {
                    console.error('Error loading album:', error);
                    this.showEditorToast('Erreur de chargement', 'error');
                    this.close();
                }
            },

            // Switch between tabs
            switchTab(tab) {
                this.currentTab = tab;

                // Update tab buttons
                document.querySelectorAll('.tag-editor-tab').forEach(btn => {
                    btn.classList.toggle('active', btn.dataset.tab === tab);
                });

                // Render appropriate content
                switch (tab) {
                    case 'edit':
                        this.renderEditTab();
                        break;
                    case 'youtube':
                        this.renderYouTubeTab();
                        break;
                    case 'musicbrainz':
                        this.renderMusicBrainzTab();
                        break;
                    case 'files':
                        this.renderFilesTab();
                        break;
                }
            },

            // Render the main edit tab
            renderEditTab() {
                const content = document.getElementById('tagEditorContent');

                let html = `
                    <!-- Album Header -->
                    <div class="album-info-header fade-in">
                        <div class="album-artwork">
                            ${this.albumData.artwork
                                ? `<img src="serve_image.php?album_id=${this.albumId}" alt="Album Art">`
                                : '<div class="placeholder">🎵</div>'}
                        </div>
                        <div class="album-details">
                            <h3>${this.escapeHtml(this.albumData.album_name)}</h3>
                            <p class="artist-name">${this.escapeHtml(this.albumData.artist_name)}</p>
                            <div class="album-meta">
                                <span class="album-meta-item">🎵 ${this.songs.length} pistes</span>
                                <span class="album-meta-item">📁 ${this.songs.filter(s => s.file_exists).length} fichiers trouvés</span>
                            </div>
                        </div>
                    </div>

                    <!-- Common Tags Section -->
                    <div class="common-tags-section fade-in">
                        <h4>🎨 Tags communs (appliqués à tout l'album)</h4>
                        <div class="common-tags-grid">
                            <div class="form-field">
                                <label>Artiste</label>
                                <input type="text" id="common_artist" value="${this.escapeHtml(this.albumData.artist_name)}"
                                       onchange="tagEditor.applyCommonTag('artist', this.value)">
                            </div>
                            <div class="form-field">
                                <label>Album</label>
                                <input type="text" id="common_album" value="${this.escapeHtml(this.albumData.album_name)}"
                                       onchange="tagEditor.applyCommonTag('album', this.value)">
                            </div>
                            <div class="form-field">
                                <label>Année</label>
                                <input type="text" id="common_year" value="${this.escapeHtml(this._pendingYear || this.songs[0]?.file_tags?.year || '')}"
                                       onchange="tagEditor.applyCommonTag('year', this.value)" placeholder="Ex: 2024">
                            </div>
                            <div class="form-field">
                                <label>Genre</label>
                                ${this.buildGenreSelect(this.albumData.genre || '', 'common_genre', "tagEditor.saveAlbumGenre(this.value)")}
                            </div>
                        </div>
                    </div>

                    <!-- Songs Table -->
                    <div class="songs-table-container fade-in">
                        <table class="songs-table">
                            <thead>
                                <tr>
                                    <th class="track-num">#</th>
                                    <th class="title-cell">Titre</th>
                                    <th>Artiste</th>
                                    <th class="filename-cell">Fichier</th>
                                    <th class="actions-cell">Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                `;

                this.songs.forEach((song, index) => {
                    const tags = song.file_tags || {};
                    const isModified = this.modifiedSongs.has(song.id);
                    const rowClass = isModified ? 'modified' : '';

                    html += `
                        <tr id="song-row-${song.id}" class="${rowClass}">
                            <td class="track-num">
                                <input type="text" class="song-input" id="track_${song.id}"
                                       value="${this.escapeHtml(song.track || tags.track || index + 1)}"
                                       onchange="tagEditor.markModified(${song.id})" style="width: 50px; text-align: center;">
                            </td>
                            <td class="title-cell">
                                <input type="text" class="song-input" id="title_${song.id}"
                                       value="${this.escapeHtml(tags.title || song.db_title)}"
                                       onchange="tagEditor.markModified(${song.id})">
                            </td>
                            <td>
                                <input type="text" class="song-input" id="artist_${song.id}"
                                       value="${this.escapeHtml(song.track_artist || tags.artist || this.albumData.artist_name)}"
                                       onchange="tagEditor.markModified(${song.id})">
                            </td>
                            <td class="filename-cell" title="${this.escapeHtml(song.filename)}">
                                ${this.escapeHtml(song.filename)}
                            </td>
                            <td class="actions-cell">
                                <button class="btn btn-icon btn-secondary" onclick="tagEditor.saveSingle(${song.id})" title="Sauvegarder">
                                    💾
                                </button>
                            </td>
                        </tr>
                    `;
                });

                html += `
                            </tbody>
                        </table>
                    </div>
                `;

                content.innerHTML = html;
                this._pendingYear = null; // consumed
            },

            // Render YouTube Music tab
            renderYouTubeTab() {
                const content = document.getElementById('tagEditorContent');

                html = `
                    <div class="ytmusic-panel fade-in">
                        <h4>
                            <span class="icon">▶️</span>
                            Rechercher sur YouTube Music
                        </h4>
                        <p style="color: var(--te-text-secondary); margin-bottom: 16px; font-size: 14px;">
                            Trouvez l'album sur YouTube Music pour vérifier et copier les tags corrects.
                        </p>
                        <div class="ytmusic-search-box">
                            <input type="text" id="ytSearchQuery"
                                   placeholder="Rechercher un album ou artiste..."
                                   value="${this.escapeHtml(this.albumData.artist_name + ' ' + this.albumData.album_name)}"
                                   onkeypress="if(event.key==='Enter') tagEditor.searchYouTube()">
                            <button class="btn btn-primary" onclick="tagEditor.searchYouTube()">
                                🔍 Rechercher
                            </button>
                        </div>
                        <div class="ytmusic-results" id="ytResults">
                            ${this.ytMusicResults.length > 0 ? this.renderYtResults() : '<p style="color: var(--te-text-secondary); text-align: center; padding: 20px;">Lancez une recherche pour trouver l\'album</p>'}
                        </div>
                    </div>

                    ${this.selectedYtAlbum ? this.renderTrackComparison(
                        this.ytTrackList,
                        { title: this.selectedYtAlbum.title, artist: this.selectedYtAlbum.artist,
                          year: this.selectedYtAlbum.year, thumbnail: this.selectedYtAlbum.thumbnail },
                        'applyYtTags', 'youtube'
                    ) : ''}
                `;

                content.innerHTML = html;
            },

            // Search YouTube Music
            async searchYouTube() {
                const query = document.getElementById('ytSearchQuery').value;
                if (!query) return;

                this.setStatus('Recherche YouTube Music...', 'loading');
                document.getElementById('ytResults').innerHTML = '<div class="loading-spinner"></div>';

                try {
                    const response = await fetch(`${BASE_PATH}/tag_editor_api.php?action=get_ytmusic_artist&artist=${encodeURIComponent(query)}`);
                    const result = await response.json();

                    if (result.success && result.data.albums) {
                        this.ytMusicResults = result.data.albums;
                        document.getElementById('ytResults').innerHTML = this.renderYtResults();
                        this.setStatus('Recherche terminée', 'ready');
                    } else {
                        document.getElementById('ytResults').innerHTML = '<p style="color: var(--te-text-secondary); text-align: center; padding: 20px;">Aucun résultat trouvé</p>';
                        this.setStatus('Aucun résultat', 'ready');
                    }
                } catch (error) {
                    console.error('YouTube search error:', error);
                    this.showEditorToast('Erreur lors de la recherche', 'error');
                    this.setStatus('Erreur de recherche', 'error');
                }
            },

            // Render YouTube results
            renderYtResults() {
                if (!this.ytMusicResults.length) return '';

                return this.ytMusicResults.map((album, index) => `
                    <div class="ytmusic-result-item ${this.selectedYtAlbum?.title === album.title ? 'selected' : ''}"
                         onclick="tagEditor.selectYtAlbum(${index})">
                        <div class="ytmusic-result-thumb">
                            ${album.thumbnail ? `<img src="${album.thumbnail}" alt="">` : '🎵'}
                        </div>
                        <div class="ytmusic-result-info">
                            <div class="title">${this.escapeHtml(album.title)}</div>
                            <div class="artist">${this.escapeHtml(album.artist)}</div>
                            ${album.year ? `<div class="year">${album.year}</div>` : ''}
                        </div>
                    </div>
                `).join('');
            },

            // Select a YouTube album → fetch its full tracklist
            selectYtAlbum(index) {
                this.selectedYtAlbum = this.ytMusicResults[index];
                this.ytTrackList = null;
                this._manualMapping = {};
                this.renderYouTubeTab();
                if (this.selectedYtAlbum.browseId) {
                    this.fetchYtTracks(this.selectedYtAlbum.browseId);
                }
            },

            async fetchYtTracks(browseId) {
                this.setStatus('Chargement tracklist...', 'loading');
                try {
                    const r = await fetch(`${BASE_PATH}/tag_editor_api.php?action=get_ytmusic_tracks&browse_id=${encodeURIComponent(browseId)}`);
                    const res = await r.json();
                    if (res.success) {
                        this.ytTrackList = res.data; // { title, artist, year, tracks:[{track_number,title,artist}] }
                    } else {
                        this.showEditorToast('Tracklist indisponible', 'error');
                    }
                } catch(e) {
                    this.showEditorToast('Erreur chargement tracklist', 'error');
                } finally {
                    this.setStatus('Prêt', 'ready');
                    this.renderYouTubeTab();
                }
            },

            // Shared: match local songs to proposed tracks (track# first, then title similarity)
            // Returns array of proposed-track indices (length = localSongs.length), -1 = no match
            _matchTracks(localSongs, proposedTracks) {
                const result = new Array(localSongs.length).fill(-1);
                const used = new Set();
                // Normalize: lowercase + strip all punctuation incl. Unicode quotes/apostrophes
                const norm = s => (s||'').toLowerCase()
                    .replace(/[\u2018\u2019\u201c\u201d\u2032\u2033\[\]()'"!?,;:.&\-]/g,' ')
                    .replace(/\s+/g,' ').trim();
                const words = s => new Set(norm(s).split(' ').filter(Boolean));

                // Pass 1: track number
                const propByNum = new Map();
                proposedTracks.forEach((t, j) => { if (t.track_number) propByNum.set(t.track_number, j); });
                localSongs.forEach((song, i) => {
                    if (!song.track) return;
                    const j = propByNum.get(song.track);
                    if (j !== undefined && !used.has(j)) { result[i] = j; used.add(j); }
                });

                // Pass 2: exact normalized title
                localSongs.forEach((song, i) => {
                    if (result[i] >= 0) return;
                    const ln = norm(song.db_title || song.filename || '');
                    for (let j = 0; j < proposedTracks.length; j++) {
                        if (used.has(j)) continue;
                        if (norm(proposedTracks[j].title) === ln) { result[i] = j; used.add(j); break; }
                    }
                });

                // Pass 3: one title contains the other (normalized)
                localSongs.forEach((song, i) => {
                    if (result[i] >= 0) return;
                    const ln = norm(song.db_title || song.filename || '');
                    for (let j = 0; j < proposedTracks.length; j++) {
                        if (used.has(j)) continue;
                        const pn = norm(proposedTracks[j].title);
                        if (ln && pn && (ln.includes(pn) || pn.includes(ln))) {
                            result[i] = j; used.add(j); break;
                        }
                    }
                });

                // Pass 4: word-overlap (≥70% of shorter title's words in common, min 2 shared words)
                localSongs.forEach((song, i) => {
                    if (result[i] >= 0) return;
                    const lw = words(song.db_title || song.filename || '');
                    if (lw.size < 2) return;
                    let bestJ = -1, bestScore = 0;
                    for (let j = 0; j < proposedTracks.length; j++) {
                        if (used.has(j)) continue;
                        const pw = words(proposedTracks[j].title || '');
                        const common = [...lw].filter(w => pw.has(w)).length;
                        const shorter = Math.min(lw.size, pw.size);
                        const score = (shorter >= 2 && common >= 2) ? common / shorter : 0;
                        if (score >= 0.7 && score > bestScore) { bestScore = score; bestJ = j; }
                    }
                    if (bestJ >= 0) { result[i] = bestJ; used.add(bestJ); }
                });

                return result;
            },

            // Called by select onchange — save user's manual assignment
            setTrackMapping(localIdx, proposedIdx, tab) {
                const pIdx = parseInt(proposedIdx);
                const tracks = tab === 'youtube'
                    ? (this.ytTrackList?.tracks || [])
                    : (this.mbTrackList?.tracks || []);
                const sorted = [...this.songs].sort((a,b) => (a.track||999)-(b.track||999));
                const autoMap = this._matchTracks(sorted, tracks);

                // If another row already claims this proposed track, release it
                if (pIdx >= 0) {
                    sorted.forEach((_, otherIdx) => {
                        if (otherIdx === localIdx) return;
                        const eff = otherIdx in this._manualMapping
                            ? this._manualMapping[otherIdx] : autoMap[otherIdx];
                        if (eff === pIdx) this._manualMapping[otherIdx] = -1;
                    });
                }

                this._manualMapping[localIdx] = pIdx;
                if (tab === 'youtube') this.renderYouTubeTab();
                else this.renderMusicBrainzTab();
            },

            // Shared: interactive tracklist comparison — select per row
            renderTrackComparison(trackList, albumInfo, applyFnName, tabName) {
                if (!trackList) {
                    return `<div style="text-align:center;padding:28px;color:var(--te-text-secondary)">
                        <div class="loading-spinner" style="margin:0 auto 12px"></div>
                        <p>Chargement de la tracklist…</p></div>`;
                }

                const proposed = trackList.tracks || [];
                const local = [...this.songs].sort((a, b) => (a.track||999)-(b.track||999));
                const autoMap = this._matchTracks(local, proposed);

                // Effective mapping: manual override takes priority over auto
                const effectiveMap = local.map((_, i) =>
                    i in this._manualMapping ? this._manualMapping[i] : autoMap[i]
                );
                const assignedSet = new Set(effectiveMap.filter(j => j >= 0));
                const assignedCount = assignedSet.size;

                const thumb = albumInfo.thumbnail
                    ? `<img src="${albumInfo.thumbnail}" alt="">` : '🎵';

                let rows = '';
                local.forEach((L, i) => {
                    const curJ = effectiveMap[i];
                    const isAuto = !(i in this._manualMapping) && curJ >= 0;

                    const options = proposed.map((t, j) => {
                        const takenByOther = assignedSet.has(j) && j !== curJ;
                        const label = `${t.track_number ? t.track_number + '. ' : ''}${t.title}`
                            + (t.artist ? ' — ' + t.artist : '')
                            + (takenByOther ? ' ✓' : '');
                        return `<option value="${j}" ${j === curJ ? 'selected' : ''}>${this.escapeHtml(label)}</option>`;
                    }).join('');

                    rows += `<tr>
                        <td class="tc-current">
                            <span class="tc-num">${L.track||'?'}</span>
                            <span class="tc-title">${this.escapeHtml(L.db_title)}</span>
                            ${L.track_artist ? `<br><span class="tc-artist">${this.escapeHtml(L.track_artist)}</span>` : ''}
                        </td>
                        <td class="tc-sep">${curJ >= 0 ? '→' : '✗'}</td>
                        <td style="padding:4px 8px">
                            <select class="tc-select" onchange="tagEditor.setTrackMapping(${i}, this.value, '${tabName}')">
                                <option value="-1" ${curJ < 0 ? 'selected' : ''}>— Ignorer —</option>
                                ${options}
                            </select>
                            ${isAuto ? '<span class="tc-auto-badge">auto</span>' : ''}
                        </td>
                    </tr>`;
                });

                return `
                    <div class="tracklist-comparison fade-in" style="margin-top:20px">
                        <div class="source-album-header">
                            <div class="source-album-thumb">${thumb}</div>
                            <div class="source-album-info">
                                <strong>${this.escapeHtml(albumInfo.title || trackList.title || '')}</strong>
                                <span>${this.escapeHtml(albumInfo.artist || trackList.artist || '')}</span>
                                ${(albumInfo.year||trackList.year) ? `<span>${albumInfo.year||trackList.year}</span>` : ''}
                                <span>${proposed.length} piste(s) disponibles</span>
                            </div>
                        </div>
                        <div class="track-compare-wrap">
                            <table class="track-compare-table">
                                <thead><tr>
                                    <th>Piste locale</th><th></th><th>Assigner →</th>
                                </tr></thead>
                                <tbody>${rows}</tbody>
                            </table>
                        </div>
                        <div class="comparison-apply-bar">
                            <span class="tc-assign-count">${assignedCount} / ${local.length} assignée(s)</span>
                            <div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap">
                                ${tabName === 'musicbrainz' && this.selectedMbRelease?.id ? `
                                <a href="https://musicbrainz.org/release/${this.selectedMbRelease.id}/edit"
                                   target="_blank" rel="noopener"
                                   class="btn btn-secondary tc-mb-edit-link"
                                   title="Ouvrir la page d'édition MusicBrainz (compte MB requis)">
                                    🌐 Corriger sur MusicBrainz
                                </a>` : ''}
                                <button class="btn btn-primary" onclick="tagEditor.${applyFnName}()">
                                    ✨ Appliquer ${assignedCount} tag(s)
                                </button>
                            </div>
                        </div>
                    </div>`;
            },

            // Shared: apply a tracklist to the edit tab
            applyTrackList() {
                if (!this.pendingTrackList) return;
                const { tracks, albumInfo } = this.pendingTrackList;
                this.pendingTrackList = null;

                const sorted = [...this.songs].sort((a, b) => (a.track||999)-(b.track||999));
                const autoMap = this._matchTracks(sorted, tracks);

                let applied = 0;
                sorted.forEach((song, i) => {
                    // Manual override wins over auto
                    const pIdx = i in this._manualMapping ? this._manualMapping[i] : autoMap[i];
                    if (pIdx < 0) return;
                    const t = tracks[pIdx];
                    if (!t) return;
                    const idx = this.songs.findIndex(s => s.id === song.id);
                    if (idx !== -1) {
                        this.songs[idx].track = t.track_number;
                        this.songs[idx].db_title = t.title;
                        this.songs[idx].track_artist = t.artist;
                        // Also update file_tags so renderEditTab inputs show updated values
                        if (!this.songs[idx].file_tags) this.songs[idx].file_tags = {};
                        this.songs[idx].file_tags.title = t.title;
                        this.songs[idx].file_tags.track = t.track_number;
                        if (t.artist) this.songs[idx].file_tags.artist = t.artist;
                        applied++;
                    }
                    this.modifiedSongs.add(song.id);
                });

                // Re-sort songs by their new track numbers so renderEditTab shows correct order
                this.songs.sort((a, b) => (a.track || 999) - (b.track || 999));
                this._manualMapping = {};
                if (albumInfo.title) this.albumData.album_name = albumInfo.title;
                if (albumInfo.year)  this._pendingYear = albumInfo.year;

                this.switchTab('edit');
                this.showEditorToast(`Tags de ${applied} piste(s) appliqués — vérifiez et sauvegardez`, 'success');
            },

            // YouTube Music: "appliquer" → set pending + apply
            applyYtTags() {
                if (!this.ytTrackList) return;
                this.pendingTrackList = {
                    tracks: this.ytTrackList.tracks,
                    albumInfo: {
                        title: this.ytTrackList.title || this.selectedYtAlbum?.title,
                        artist: this.ytTrackList.artist || this.selectedYtAlbum?.artist,
                        year: this.ytTrackList.year || this.selectedYtAlbum?.year,
                        thumbnail: this.ytTrackList.thumbnail || this.selectedYtAlbum?.thumbnail,
                    }
                };
                this.applyTrackList();
            },

            // ── MusicBrainz tab ──────────────────────────────────────────────

            renderMusicBrainzTab() {
                const content = document.getElementById('tagEditorContent');
                const defaultQuery = this.albumData.album_name;

                let resultsHtml = '';
                if (this.mbResults.length > 0) {
                    resultsHtml = this.mbResults.map((r, i) => `
                        <div class="mb-result-item ${this.selectedMbRelease?.id === r.id ? 'selected' : ''}"
                             onclick="tagEditor.selectMbRelease(${i})">
                            <div class="mb-result-badge">🎼</div>
                            <div class="mb-result-info">
                                <div class="title">${this.escapeHtml(r.title)}</div>
                                <div class="meta">
                                    ${this.escapeHtml(r.artist)}
                                    ${r.year ? ` · ${r.year}` : ''}
                                    ${r.track_count ? ` · ${r.track_count} pistes` : ''}
                                    ${r.country ? ` · ${r.country}` : ''}
                                    ${r.status ? ` · ${r.status}` : ''}
                                </div>
                            </div>
                        </div>`).join('');
                } else if (this._mbSearched) {
                    resultsHtml = '<p style="color:var(--te-text-secondary);text-align:center;padding:20px">Aucun résultat</p>';
                } else {
                    resultsHtml = '<p style="color:var(--te-text-secondary);text-align:center;padding:20px">Lancez une recherche pour trouver la release</p>';
                }

                content.innerHTML = `
                    <div class="ytmusic-panel fade-in">
                        <h4><span class="icon">🎼</span> Rechercher sur MusicBrainz</h4>
                        <p style="color:var(--te-text-secondary);margin-bottom:16px;font-size:14px">
                            Base de données musicale ouverte — tracklists complètes avec artiste par piste.
                        </p>
                        <div class="ytmusic-search-box">
                            <input type="text" id="mbSearchQuery"
                                   placeholder="Nom de l'album…"
                                   value="${this.escapeHtml(defaultQuery)}"
                                   onkeypress="if(event.key==='Enter') tagEditor.searchMusicBrainz()">
                            <button class="btn btn-primary" onclick="tagEditor.searchMusicBrainz()">
                                🔍 Rechercher
                            </button>
                        </div>
                        <div id="mbResults" class="ytmusic-results">${resultsHtml}</div>
                    </div>
                    ${this.selectedMbRelease ? this.renderTrackComparison(
                        this.mbTrackList,
                        { title: this.selectedMbRelease.title, artist: this.selectedMbRelease.artist,
                          year: this.selectedMbRelease.year },
                        'applyMbTracks', 'musicbrainz'
                    ) : ''}
                `;
            },

            async searchMusicBrainz() {
                const query = document.getElementById('mbSearchQuery')?.value?.trim();
                if (!query) return;
                this._mbSearched = false;
                this.mbResults = [];
                this.selectedMbRelease = null;
                this.mbTrackList = null;
                document.getElementById('mbResults').innerHTML = '<div class="loading-spinner" style="margin:20px auto"></div>';
                this.setStatus('Recherche MusicBrainz…', 'loading');
                try {
                    const r = await fetch(`${BASE_PATH}/tag_editor_api.php?action=musicbrainz_search&query=${encodeURIComponent(query)}`);
                    const res = await r.json();
                    if (res.success) {
                        this.mbResults = res.data.releases || [];
                        this._mbSearched = true;
                    }
                } catch(e) {
                    this.showEditorToast('Erreur recherche MusicBrainz', 'error');
                } finally {
                    this.setStatus('Prêt', 'ready');
                    this.renderMusicBrainzTab();
                }
            },

            selectMbRelease(index) {
                this.selectedMbRelease = this.mbResults[index];
                this.mbTrackList = null;
                this._manualMapping = {};
                this.renderMusicBrainzTab();
                this.fetchMbTracks(this.selectedMbRelease.id);
            },

            async fetchMbTracks(releaseId) {
                this.setStatus('Chargement tracklist MusicBrainz…', 'loading');
                try {
                    const r = await fetch(`${BASE_PATH}/tag_editor_api.php?action=musicbrainz_tracks&release_id=${encodeURIComponent(releaseId)}`);
                    const res = await r.json();
                    if (res.success) {
                        this.mbTrackList = res.data;
                    } else {
                        this.showEditorToast('Tracklist indisponible: ' + (res.error || ''), 'error');
                    }
                } catch(e) {
                    this.showEditorToast('Erreur chargement MusicBrainz', 'error');
                } finally {
                    this.setStatus('Prêt', 'ready');
                    this.renderMusicBrainzTab();
                }
            },

            applyMbTracks() {
                if (!this.mbTrackList) return;
                this.pendingTrackList = {
                    tracks: this.mbTrackList.tracks,
                    albumInfo: {
                        title: this.mbTrackList.title || this.selectedMbRelease?.title,
                        artist: this.mbTrackList.artist || this.selectedMbRelease?.artist,
                        year: this.mbTrackList.year || this.selectedMbRelease?.year,
                    }
                };
                this.applyTrackList();
            },

            // Render files tab (for renaming)
            renderFilesTab() {
                const content = document.getElementById('tagEditorContent');

                let html = `
                    <div class="fade-in">
                        <div style="margin-bottom: 24px;">
                            <h4 style="color: var(--te-text-primary); margin: 0 0 8px 0;">📁 Gestion des fichiers</h4>
                            <p style="color: var(--te-text-secondary); font-size: 14px;">
                                Renommez les fichiers selon un format standardisé basé sur les tags.
                            </p>
                        </div>

                        <div style="margin-bottom: 20px; padding: 16px; background: var(--te-hover-bg); border-radius: 12px;">
                            <label class="checkbox-label">
                                <input type="checkbox" id="autoRename" checked>
                                Renommer automatiquement lors de la sauvegarde (format: "## - Titre.mp3")
                            </label>
                        </div>

                        <div class="songs-table-container">
                            <table class="songs-table">
                                <thead>
                                    <tr>
                                        <th>#</th>
                                        <th>Nom actuel</th>
                                        <th>Nouveau nom suggéré</th>
                                        <th>Actions</th>
                                    </tr>
                                </thead>
                                <tbody>
                `;

                this.songs.forEach((song, index) => {
                    const tags = song.file_tags || {};
                    const trackNum = tags.track || index + 1;
                    const title = tags.title || song.db_title;
                    const suggestedName = this.generateFilename(trackNum, title);
                    const needsRename = song.filename !== suggestedName;

                    html += `
                        <tr>
                            <td style="text-align: center;">${index + 1}</td>
                            <td style="font-family: monospace; font-size: 13px;">${this.escapeHtml(song.filename)}</td>
                            <td>
                                <input type="text" class="song-input" id="newname_${song.id}"
                                       value="${this.escapeHtml(suggestedName)}"
                                       style="font-family: monospace; font-size: 13px; ${needsRename ? 'border-color: var(--te-warning);' : ''}">
                            </td>
                            <td>
                                <button class="btn btn-small btn-secondary" onclick="tagEditor.renameSingle(${song.id})"
                                        ${!needsRename ? 'disabled' : ''}>
                                    📝 Renommer
                                </button>
                            </td>
                        </tr>
                    `;
                });

                html += `
                                </tbody>
                            </table>
                        </div>

                        <div style="margin-top: 20px; text-align: right;">
                            <button class="btn btn-primary" onclick="tagEditor.renameAll()">
                                📁 Renommer tous les fichiers
                            </button>
                        </div>
                    </div>
                `;

                content.innerHTML = html;
            },

            // Generate standardized filename
            generateFilename(track, title) {
                const cleanTitle = title.replace(/[<>:"\/\\|?*]/g, '').trim();
                const trackNum = parseInt(track) || 0;
                if (trackNum > 0) {
                    return `${String(trackNum).padStart(2, '0')} - ${cleanTitle}.mp3`;
                }
                return `${cleanTitle}.mp3`;
            },

            // Save album genre directly to database (not to files)
            async saveAlbumGenre(genre) {
                try {
                    const response = await fetch(`${BASE_PATH}/edit_tags.php?action=set_album_genre&album_id=${this.albumId}&genre=${encodeURIComponent(genre)}`);
                    const result = await response.json();

                    if (result.success) {
                        this.albumData.genre = genre;
                        this.showEditorToast(t('editor.genre_saved','Genre enregistré: {genre}').replace('{genre}', genre || t('editor.no_genre','(aucun)')), 'success');
                    } else {
                        this.showEditorToast(t('common.error','Erreur') + ': ' + result.error, 'error');
                    }
                } catch (e) {
                    console.error('Failed to save genre:', e);
                    this.showEditorToast(t('errors.genre_save','Erreur lors de la sauvegarde du genre'), 'error');
                }
            },

            // Apply common tag to all songs
            applyCommonTag(field, value) {
                // For common-only fields (genre, year, album), mark all songs as modified
                const commonOnlyFields = ['genre', 'year', 'album'];

                if (commonOnlyFields.includes(field)) {
                    // These fields only exist as common inputs, mark all songs modified
                    this.songs.forEach(song => {
                        this.markModified(song.id);
                    });
                } else {
                    // For fields with individual inputs (artist, title, track), update each input
                    this.songs.forEach(song => {
                        const input = document.getElementById(`${field}_${song.id}`);
                        if (input) {
                            input.value = value;
                            this.markModified(song.id);
                        }
                    });
                }
            },

            // Mark a song as modified
            markModified(songId) {
                this.modifiedSongs.add(songId);
                const row = document.getElementById(`song-row-${songId}`);
                if (row) {
                    row.classList.add('modified');
                }
                this.updateSaveButton();
            },

            // Update save button state
            updateSaveButton() {
                const btn = document.getElementById('saveAllBtn');
                const count = this.modifiedSongs.size;
                btn.textContent = count > 0 ? `💾 Sauvegarder (${count})` : '💾 Sauvegarder tout';
            },

            // Save a single song
            async saveSingle(songId) {
                const song = this.songs.find(s => s.id === songId);
                if (!song) return;

                this.setStatus('Sauvegarde...', 'loading');

                try {
                    const tags = {
                        title: document.getElementById(`title_${songId}`)?.value || song.db_title,
                        artist: document.getElementById(`artist_${songId}`)?.value || this.albumData.artist_name,
                        album: document.getElementById('common_album')?.value || this.albumData.album_name,
                        year: document.getElementById('common_year')?.value || '',
                        genre: document.getElementById('common_genre')?.value || '',
                        track: document.getElementById(`track_${songId}`)?.value || ''
                    };

                    // Check if auto-rename is enabled
                    const autoRename = document.getElementById('autoRename')?.checked;
                    let renameFile = false;
                    let newFilename = null;

                    if (autoRename) {
                        newFilename = this.generateFilename(tags.track, tags.title);
                        if (newFilename !== song.filename) {
                            renameFile = true;
                        }
                    }

                    const response = await fetch(`${BASE_PATH}/tag_editor_api.php`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({
                            action: 'save_tags',
                            song_id: songId,
                            file_path: song.file_path,
                            tags: tags,
                            rename_file: renameFile,
                            new_filename: newFilename
                        })
                    });

                    const result = await response.json();

                    if (result.success) {
                        this.modifiedSongs.delete(songId);
                        const row = document.getElementById(`song-row-${songId}`);
                        if (row) {
                            row.classList.remove('modified');
                            row.classList.add('saved');
                            setTimeout(() => row.classList.remove('saved'), 2000);
                        }

                        // Update song data if file was renamed
                        if (result.data.new_file_path) {
                            song.file_path = result.data.new_file_path;
                            song.filename = result.data.new_file_path.split('/').pop();
                        }

                        this.showEditorToast(t('editor.saved','Chanson sauvegardée!'), 'success');
                        this.setStatus('Prêt', 'ready');
                        this.updateSaveButton();
                    } else {
                        throw new Error(result.error || 'Échec de la sauvegarde');
                    }

                } catch (error) {
                    console.error('Save error:', error);
                    this.showEditorToast(t('common.error','Erreur') + ': ' + error.message, 'error');
                    this.setStatus('Erreur', 'error');
                }
            },

            // Save all modified songs
            async rescanAlbum() {
                if (!this.albumId) return;
                const albumName = this.albumData?.album_name || 'cet album';

                if (!confirm(`Rescanner "${albumName}" ?\n\nCela va relire les métadonnées depuis les fichiers et corriger les numéros de piste et les artistes manquants.`)) {
                    return;
                }

                this.setStatus('Rescan en cours...', 'loading');
                const rescanBtn = document.getElementById('rescanAlbumBtn');
                const saveBtn   = document.getElementById('saveAllBtn');
                if (rescanBtn) rescanBtn.disabled = true;
                if (saveBtn)   saveBtn.disabled   = true;

                try {
                    const response = await fetch(`${BASE_PATH}/tag_editor_api.php?action=rescan_album`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ album_id: this.albumId })
                    });
                    const result = await response.json();

                    if (!result.success) {
                        this.showEditorToast('Erreur: ' + (result.error || 'Rescan échoué'), 'error');
                        return;
                    }

                    const d = result.data;
                    let msg = `${d.songs_updated} piste(s) mise(s) à jour`;
                    if (d.tags_written > 0) msg += `, ${d.tags_written} tag(s) écrits`;
                    if (d.errors > 0)       msg += `, ${d.errors} erreur(s)`;
                    this.showEditorToast(msg, 'success');

                    // Reload to reflect updated track numbers / titles
                    this.modifiedSongs.clear();
                    await this.loadAlbumData();
                    this.renderEditTab();

                } catch (err) {
                    this.showEditorToast('Erreur réseau lors du rescan', 'error');
                    console.error(err);
                } finally {
                    if (rescanBtn) rescanBtn.disabled = false;
                    if (saveBtn)   saveBtn.disabled   = false;
                    this.setStatus('Prêt', 'ready');
                }
            },

            async saveAll() {
                const songsToSave = this.modifiedSongs.size > 0
                    ? this.songs.filter(s => this.modifiedSongs.has(s.id))
                    : this.songs;

                if (songsToSave.length === 0) {
                    this.showEditorToast(t('editor.no_changes','Aucune modification à sauvegarder'), 'info');
                    return;
                }

                this.setStatus(`Sauvegarde de ${songsToSave.length} fichiers...`, 'loading');
                document.getElementById('saveAllBtn').disabled = true;

                const autoRename = document.getElementById('autoRename')?.checked;
                const batchData = [];

                for (const song of songsToSave) {
                    const tags = {
                        title: document.getElementById(`title_${song.id}`)?.value || song.db_title,
                        artist: document.getElementById(`artist_${song.id}`)?.value || this.albumData.artist_name,
                        album: document.getElementById('common_album')?.value || this.albumData.album_name,
                        year: document.getElementById('common_year')?.value || '',
                        genre: document.getElementById('common_genre')?.value || '',
                        track: document.getElementById(`track_${song.id}`)?.value || ''
                    };

                    let renameTo = null;
                    if (autoRename) {
                        const newName = this.generateFilename(tags.track, tags.title);
                        if (newName !== song.filename) {
                            renameTo = newName;
                        }
                    }

                    batchData.push({
                        song_id: song.id,
                        file_path: song.file_path,
                        tags: tags,
                        rename_to: renameTo
                    });
                }

                try {
                    const response = await fetch(`${BASE_PATH}/tag_editor_api.php`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({
                            action: 'batch_save',
                            songs: batchData,
                            album_tags: {
                                album: document.getElementById('common_album')?.value,
                                year: document.getElementById('common_year')?.value,
                                genre: document.getElementById('common_genre')?.value
                            }
                        })
                    });

                    const result = await response.json();

                    if (result.success) {
                        const { saved, failed } = result.data;

                        // Update UI for saved songs
                        result.data.results?.forEach(r => {
                            this.modifiedSongs.delete(r.song_id);
                            const row = document.getElementById(`song-row-${r.song_id}`);
                            if (row) {
                                row.classList.remove('modified');
                                row.classList.add('saved');
                            }
                        });

                        // Mark errors
                        result.data.errors?.forEach(e => {
                            const row = document.getElementById(`song-row-${e.song_id}`);
                            if (row) row.classList.add('error');
                        });

                        if (failed === 0) {
                            this.showEditorToast(`✅ ${saved} ${t('editor.all_saved','fichiers sauvegardés!')}`, 'success');
                        } else {
                            this.showEditorToast(t('editor.all_saved_with_errors','{saved} sauvegardés, {failed} erreurs').replace('{saved}',saved).replace('{failed}',failed), 'warning');
                        }

                        this.setStatus('Terminé!', 'ready');
                        this.updateSaveButton();

                        // Refresh after successful save
                        setTimeout(() => {
                            document.querySelectorAll('.songs-table tr.saved').forEach(row => {
                                row.classList.remove('saved');
                            });
                        }, 3000);

                    } else {
                        throw new Error(result.error || 'Erreur lors de la sauvegarde batch');
                    }

                } catch (error) {
                    console.error('Batch save error:', error);
                    this.showEditorToast(t('common.error','Erreur') + ': ' + error.message, 'error');
                    this.setStatus('Erreur', 'error');
                } finally {
                    document.getElementById('saveAllBtn').disabled = false;
                }
            },

            // Rename a single file
            async renameSingle(songId) {
                const song = this.songs.find(s => s.id === songId);
                if (!song) return;

                const newFilename = document.getElementById(`newname_${songId}`)?.value;
                if (!newFilename || newFilename === song.filename) {
                    this.showEditorToast(t('editor.no_rename','Aucun changement de nom'), 'info');
                    return;
                }

                this.setStatus('Renommage...', 'loading');

                try {
                    const response = await fetch(`${BASE_PATH}/tag_editor_api.php`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({
                            action: 'rename_file',
                            song_id: songId,
                            file_path: song.file_path,
                            new_filename: newFilename
                        })
                    });

                    const result = await response.json();

                    if (result.success) {
                        song.file_path = result.data.new_file_path;
                        song.filename = result.data.new_filename;
                        this.showEditorToast(t('editor.renamed','Fichier renommé!'), 'success');
                        this.renderFilesTab();
                    } else {
                        throw new Error(result.error);
                    }

                } catch (error) {
                    console.error('Rename error:', error);
                    this.showEditorToast(t('common.error','Erreur') + ': ' + error.message, 'error');
                } finally {
                    this.setStatus('Prêt', 'ready');
                }
            },

            // Rename all files
            async renameAll() {
                for (const song of this.songs) {
                    const newFilename = document.getElementById(`newname_${song.id}`)?.value;
                    if (newFilename && newFilename !== song.filename) {
                        await this.renameSingle(song.id);
                    }
                }
                this.showEditorToast(t('editor.all_saved','Tous les fichiers ont été renommés!'), 'success');
            },

            // Update status indicator
            setStatus(text, state) {
                const indicator = document.getElementById('statusIndicator');
                const statusText = document.getElementById('statusText');

                statusText.textContent = text;

                indicator.style.background = {
                    'ready': 'var(--te-success)',
                    'loading': 'var(--te-warning)',
                    'error': 'var(--te-danger)'
                }[state] || 'var(--te-success)';

                if (state === 'loading') {
                    indicator.style.animation = 'pulse 1s infinite';
                } else {
                    indicator.style.animation = 'pulse 2s infinite';
                }
            },

            // Show toast notification
            showEditorToast(message, type = 'info') {
                const toast = document.getElementById('tagEditorToast');
                toast.textContent = message;
                toast.className = 'tag-editor-toast show ' + type;

                setTimeout(() => {
                    toast.classList.remove('show');
                }, 3000);
            },

            // Escape HTML
            escapeHtml(text) {
                if (!text) return '';
                const div = document.createElement('div');
                div.textContent = text;
                return div.innerHTML;
            }
        };

        // Backward compatibility function
        function openEditAlbumModal(albumId) {
            tagEditor.open(albumId);
        }

        // ── Artist management (rename / merge / delete) ──────────────────────
        let artistManageState = null; // null | { selections: Set<number> }

        function toggleArtistManageMode() {
            const grid = document.getElementById('artistGrid');
            const bar  = document.getElementById('artist-manage-bar');
            const btn  = document.getElementById('manage-artists-btn');
            if (!grid) return;

            if (artistManageState) {
                artistManageState = null;
                grid.querySelectorAll('.artist-card').forEach(card => {
                    const id = parseInt(card.dataset.artistId);
                    card.classList.remove('artist-selected');
                    card.onclick = () => viewArtist(id);
                    const ov = card.querySelector('.artist-manage-overlay');
                    if (ov) ov.remove();
                });
                if (bar) bar.style.display = 'none';
                if (btn) btn.innerHTML = `<i class="ri-edit-box-line"></i> ${t('editor.manage_btn','Gérer')}`;
                return;
            }

            artistManageState = { selections: new Set() };
            grid.querySelectorAll('.artist-card').forEach(card => {
                const id = parseInt(card.dataset.artistId);
                card.onclick = null;

                const ov = document.createElement('div');
                ov.className = 'artist-manage-overlay';
                ov.style.cssText = 'position:absolute;inset:0;z-index:5;cursor:pointer;border-radius:inherit;';
                ov.onclick = (e) => { e.stopPropagation(); toggleArtistCardSelection(id); };

                const cb = document.createElement('div');
                cb.id = `artist-cb-${id}`;
                cb.style.cssText = 'position:absolute;top:6px;left:6px;width:22px;height:22px;border-radius:50%;border:2px solid white;background:rgba(0,0,0,0.55);display:flex;align-items:center;justify-content:center;font-size:13px;color:white;transition:background 0.15s;';
                ov.appendChild(cb);
                card.style.position = 'relative';
                card.prepend(ov);
            });

            if (bar) bar.style.display = 'flex';
            if (btn) btn.innerHTML = `<i class="ri-close-line"></i> ${t('editor.done_btn','Terminer')}`;
            updateArtistManageBar();
        }

        function toggleArtistCardSelection(id) {
            if (!artistManageState) return;
            const card = document.querySelector(`.artist-card[data-artist-id="${id}"]`);
            const cb   = document.getElementById(`artist-cb-${id}`);
            if (artistManageState.selections.has(id)) {
                artistManageState.selections.delete(id);
                if (card) card.classList.remove('artist-selected');
                if (cb)   { cb.textContent = ''; cb.style.background = 'rgba(0,0,0,0.55)'; }
            } else {
                artistManageState.selections.add(id);
                if (card) card.classList.add('artist-selected');
                if (cb)   { cb.textContent = '✓'; cb.style.background = 'var(--accent)'; }
            }
            updateArtistManageBar();
        }

        function updateArtistManageBar() {
            if (!artistManageState) return;
            const n = artistManageState.selections.size;
            const countEl   = document.getElementById('artist-manage-count');
            const renameBtn = document.getElementById('rename-artist-btn');
            const mergeBtn  = document.getElementById('merge-artists-btn');
            const deleteBtn = document.getElementById('delete-artists-btn');
            if (countEl)   countEl.textContent = n === 0 ? t('common.none_selected','Aucun sélectionné') : `${n} artiste${n > 1 ? 's' : ''} sélectionné${n > 1 ? 's' : ''}`;
            if (renameBtn) renameBtn.disabled = (n !== 1);
            if (mergeBtn)  mergeBtn.disabled  = (n < 2);
            if (deleteBtn) deleteBtn.disabled = (n < 1);
        }

        async function openRenameArtistDialog() {
            if (!artistManageState || artistManageState.selections.size !== 1) return;
            const artistId   = [...artistManageState.selections][0];
            const card       = document.querySelector(`.artist-card[data-artist-id="${artistId}"]`);
            const currentName = card?.querySelector('.artist-name')?.textContent?.trim() || '';
            const newName = prompt('Nouveau nom de l\'artiste :', currentName);
            if (!newName || newName.trim() === currentName) return;

            const fd = new FormData();
            fd.append('user', app.currentUser);
            fd.append('artist_id', artistId);
            fd.append('name', newName.trim());
            const res    = await fetch(`${BASE_PATH}/api/library.php?action=rename_artist`, { method: 'POST', body: fd });
            const result = await res.json();
            if (result.error) { alert(t('common.error_prefix','Erreur : ') + result.message); return; }

            const d = result.data;
            showToast(`"${d.name}" renommé. ${d.tags_updated} tag(s) mis à jour.`, 'success');
            artistManageState = null;
            await loadLibrary();
            renderArtists();
        }

        async function openMergeArtistsDialog() {
            if (!artistManageState || artistManageState.selections.size < 2) return;
            const ids   = [...artistManageState.selections];
            const names = ids.map(id => {
                const card = document.querySelector(`.artist-card[data-artist-id="${id}"]`);
                return card?.querySelector('.artist-name')?.textContent?.trim() || `Artiste ${id}`;
            });
            const newName = prompt(t('confirm.merge_artists',"Fusionner {n} artistes en un seul.\nNom de l'artiste résultant :").replace('{n}', ids.length), names[0]);
            if (!newName) return;

            const fd = new FormData();
            fd.append('user', app.currentUser);
            fd.append('new_name', newName.trim());
            ids.forEach(id => fd.append('source_ids[]', id));
            const res    = await fetch(`${BASE_PATH}/api/library.php?action=merge_artists`, { method: 'POST', body: fd });
            const result = await res.json();
            if (result.error) { alert(t('common.error_prefix','Erreur : ') + result.message); return; }

            const d = result.data;
            let msg = `Fusion terminée : ${d.songs_total} chanson(s) regroupées sous "${d.name}".`;
            if (d.tags_updated > 0) msg += `\n${d.tags_updated} tag(s) ID3 mis à jour.`;
            if (d.tags_failed  > 0) msg += `\n⚠ ${d.tags_failed} fichier(s) non modifiable(s).`;
            showToast(msg, 'success');
            artistManageState = null;
            await loadLibrary();
            renderArtists();
        }

        async function deleteSelectedArtists() {
            if (!artistManageState || artistManageState.selections.size < 1) return;
            const ids   = [...artistManageState.selections];
            const names = ids.map(id => {
                const card = document.querySelector(`.artist-card[data-artist-id="${id}"]`);
                return card?.querySelector('.artist-name')?.textContent?.trim() || `Artiste ${id}`;
            });
            const plural = ids.length > 1 ? 's' : '';
            if (!confirm(`Supprimer ${ids.length} artiste${plural} ?\n\n${names.join('\n')}\n\nTous les albums et fichiers audio seront supprimés du disque. Irréversible.`)) return;

            let totalFiles = 0, errors = [];
            for (const artistId of ids) {
                const fd = new FormData();
                fd.append('user', app.currentUser);
                fd.append('artist_id', artistId);
                try {
                    const res    = await fetch(`${BASE_PATH}/api/library.php?action=delete_artist`, { method: 'POST', body: fd });
                    const result = await res.json();
                    if (result.error) errors.push(result.message);
                    else totalFiles += result.data?.deleted_files || 0;
                } catch (e) { errors.push(`Artiste ${artistId}: ${e.message}`); }
            }

            let msg = `${ids.length} artiste${plural} supprimé${plural}. ${totalFiles} fichier${totalFiles > 1 ? 's' : ''} supprimé${totalFiles > 1 ? 's' : ''}.`;
            if (errors.length) msg += '\n\nErreurs :\n' + errors.join('\n');
            alert(msg);
            artistManageState = null;
            await loadLibrary();
            renderArtists();
        }

        async function detectArtistDuplicates() {
            const btn  = document.getElementById('detect-artist-dupes-btn');
            const icon = document.getElementById('detect-artist-dupes-icon');
            const panel = document.getElementById('artists-duplicates-panel');
            if (!panel) return;

            if (btn)  btn.disabled = true;
            if (icon) icon.className = 'ri-loader-4-line scan-spin-icon';
            panel.style.display = 'block';
            panel.innerHTML = '<div style="padding:14px;color:var(--text-secondary);font-size:13px;">Analyse en cours…</div>';

            try {
                const fd = new FormData();
                fd.append('user', app.currentUser);
                const res    = await fetch(`${BASE_PATH}/api/library.php?action=detect_artist_duplicates`, { method: 'POST', body: fd });
                const result = await res.json();
                const groups = result.data?.groups || [];

                if (!groups.length) {
                    panel.innerHTML = '<div style="padding:14px;color:var(--text-secondary);font-size:13px;">Aucun doublon probable détecté.</div>';
                    return;
                }

                panel.innerHTML = `
                    <div style="padding:10px 14px 6px;font-size:13px;font-weight:600;color:var(--text-primary);">
                        ${groups.length} groupe${groups.length > 1 ? 's' : ''} de doublons probables
                    </div>
                    ${groups.map((g, i) => `
                        <div style="border:1px solid var(--border);border-radius:8px;margin:6px 14px;padding:10px 14px;background:var(--bg-tertiary);">
                            <div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap;margin-bottom:6px;">
                                ${g.artists.map(a => `<span style="background:var(--bg-secondary);border:1px solid var(--border);border-radius:6px;padding:3px 10px;font-size:12px;color:var(--text-primary);">${a.name}</span>`).join('<span style="color:var(--text-secondary);font-size:11px;">≈</span>')}
                                <span style="margin-left:auto;font-size:11px;color:var(--text-secondary);">${g.total_songs} chanson${g.total_songs > 1 ? 's' : ''}</span>
                            </div>
                            <button onclick="preselectArtistGroup(${i})" class="rescan-btn" style="font-size:11px;padding:4px 12px;">
                                <i class="ri-cursor-line"></i> Sélectionner
                            </button>
                        </div>
                    `).join('')}
                `;
                panel._groups = groups;
            } catch (e) {
                panel.innerHTML = `<div style="color:var(--error,#e74c3c);padding:14px;font-size:13px;">Erreur : ${e.message}</div>`;
            } finally {
                if (btn)  btn.disabled = false;
                if (icon) icon.className = 'ri-search-line';
            }
        }

        function preselectArtistGroup(groupIndex) {
            const panel = document.getElementById('artists-duplicates-panel');
            const groups = panel?._groups;
            if (!groups || !groups[groupIndex]) return;
            if (!artistManageState) toggleArtistManageMode();
            const ids = groups[groupIndex].artists.map(a => a.id);
            ids.forEach(id => {
                if (!artistManageState.selections.has(id)) toggleArtistCardSelection(id);
            });
            // Scroll to manage bar
            document.getElementById('artist-manage-bar')?.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
        }

        // ── Album management (rename / merge) ────────────────────────────────
        let albumManageState = null; // null | { artistId, selections: Set<number> }

        function toggleAlbumManageMode(artistId) {
            const grid = document.getElementById(`album-grid-${artistId}`);
            const bar  = document.getElementById(`album-manage-bar-${artistId}`);
            const btn  = document.getElementById(`manage-albums-btn-${artistId}`);
            if (!grid) return;

            if (albumManageState) {
                // Exit manage mode: restore click handlers, remove overlays
                albumManageState = null;
                grid.querySelectorAll('.album-card').forEach(card => {
                    const id = parseInt(card.dataset.albumId);
                    card.classList.remove('album-selected');
                    card.onclick = () => viewAlbum(id);
                    const ov = card.querySelector('.album-manage-overlay');
                    if (ov) ov.remove();
                });
                if (bar) bar.style.display = 'none';
                if (btn) btn.innerHTML = `<i class="ri-edit-box-line"></i> ${t('editor.manage_btn','Gérer')}`;
                return;
            }

            // Enter manage mode
            albumManageState = { artistId, selections: new Set() };
            grid.querySelectorAll('.album-card').forEach(card => {
                const id = parseInt(card.dataset.albumId);
                card.onclick = null;

                // Overlay with checkbox indicator
                const ov = document.createElement('div');
                ov.className = 'album-manage-overlay';
                ov.style.cssText = 'position:absolute;inset:0;z-index:5;cursor:pointer;';
                ov.onclick = (e) => { e.stopPropagation(); toggleAlbumCardSelection(id); };

                const cb = document.createElement('div');
                cb.id = `album-cb-${id}`;
                cb.style.cssText = 'position:absolute;top:8px;left:8px;width:22px;height:22px;border-radius:50%;border:2px solid white;background:rgba(0,0,0,0.55);display:flex;align-items:center;justify-content:center;font-size:13px;color:white;transition:background 0.15s;';
                ov.appendChild(cb);
                card.prepend(ov);
            });

            if (bar) bar.style.display = 'flex';
            if (btn) btn.innerHTML = `<i class="ri-close-line"></i> ${t('editor.done_btn','Terminer')}`;
        }

        function toggleAlbumCardSelection(albumId) {
            if (!albumManageState) return;
            const card = document.querySelector(`.album-card[data-album-id="${albumId}"]`);
            const cb   = document.getElementById(`album-cb-${albumId}`);
            if (albumManageState.selections.has(albumId)) {
                albumManageState.selections.delete(albumId);
                card?.classList.remove('album-selected');
                if (cb) { cb.textContent = ''; cb.style.background = 'rgba(0,0,0,0.55)'; }
            } else {
                albumManageState.selections.add(albumId);
                card?.classList.add('album-selected');
                if (cb) { cb.textContent = '✓'; cb.style.background = 'var(--accent)'; }
            }
            updateAlbumManageBar();
        }

        function updateAlbumManageBar() {
            if (!albumManageState) return;
            const { artistId, selections } = albumManageState;
            const n = selections.size;
            const countEl   = document.getElementById(`album-manage-count-${artistId}`);
            const renameBtn = document.getElementById(`rename-album-btn-${artistId}`);
            const mergeBtn  = document.getElementById(`merge-albums-btn-${artistId}`);
            const deleteBtn = document.getElementById(`delete-albums-btn-${artistId}`);
            if (countEl)   countEl.textContent = n === 0 ? t('common.none_selected','Aucun sélectionné') : `${n} album${n > 1 ? 's' : ''} sélectionné${n > 1 ? 's' : ''}`;
            if (renameBtn) renameBtn.disabled = (n !== 1);
            if (mergeBtn)  mergeBtn.disabled  = (n < 2);
            if (deleteBtn) deleteBtn.disabled = (n < 1);
        }

        async function openRenameAlbumDialog(artistId) {
            if (!albumManageState || albumManageState.selections.size !== 1) return;
            const albumId    = [...albumManageState.selections][0];
            const card       = document.querySelector(`.album-card[data-album-id="${albumId}"]`);
            const currentName = card?.querySelector('.album-name')?.textContent?.trim() || '';
            const newName = prompt('Nouveau nom de l\'album :', currentName);
            if (!newName || newName.trim() === currentName) return;

            const fd = new FormData();
            fd.append('user', app.currentUser);
            fd.append('album_id', albumId);
            fd.append('name', newName.trim());
            const res = await fetch(`${BASE_PATH}/api/library.php?action=rename_album`, { method: 'POST', body: fd });
            const result = await res.json();
            if (result.error) { alert(t('common.error_prefix','Erreur : ') + result.message); return; }

            albumManageState = null;
            viewArtist(artistId);
        }

        async function openMergeAlbumsDialog(artistId) {
            if (!albumManageState || albumManageState.selections.size < 2) return;
            const ids = [...albumManageState.selections];
            const names = ids.map(id => {
                const card = document.querySelector(`.album-card[data-album-id="${id}"]`);
                return card?.querySelector('.album-name')?.textContent?.trim() || `Album ${id}`;
            });
            const newName = prompt(t('confirm.merge_albums',"Fusionner {n} albums en un seul.\nNom de l'album résultant :").replace('{n}', ids.length), names[0]);
            if (!newName) return;

            const fd = new FormData();
            fd.append('user', app.currentUser);
            fd.append('new_name', newName.trim());
            ids.forEach(id => fd.append('source_ids[]', id));
            const res = await fetch(`${BASE_PATH}/api/library.php?action=merge_albums`, { method: 'POST', body: fd });
            const result = await res.json();
            if (result.error) { alert(t('common.error_prefix','Erreur : ') + result.message); return; }

            const d = result.data;
            let msg = `Fusion terminée : ${d.songs_total} chanson(s) regroupées dans "${d.name}".`;
            if (d.tags_updated > 0) msg += `\n${d.tags_updated} tag(s) ID3 mis à jour dans les fichiers.`;
            if (d.tags_failed  > 0) msg += `\n⚠ ${d.tags_failed} fichier(s) n'ont pas pu être modifiés.`;
            alert(msg);

            albumManageState = null;
            viewArtist(artistId);
        }

        // ── Song manage mode (album view) ────────────────────────────────────────

        let songManageState = null; // null | { albumId, selections: Set<number> }

        function toggleSongManageMode(albumId) {
            const list = document.getElementById(`song-list-${albumId}`);
            const bar  = document.getElementById(`song-manage-bar-${albumId}`);
            const btn  = document.getElementById(`manage-songs-btn-${albumId}`);
            if (!list) return;

            if (songManageState) {
                // Exit manage mode
                songManageState = null;
                list.querySelectorAll('.song-item').forEach(row => {
                    const id = parseInt(row.dataset.songId);
                    row.classList.remove('song-selected');
                    row.style.paddingLeft = '';
                    const cb = row.querySelector('.song-manage-cb');
                    if (cb) cb.remove();
                    row.onclick = () => {
                        const idx = parseInt(row.dataset.index);
                        playSongFromAlbum(albumId, idx);
                    };
                });
                if (bar) bar.style.display = 'none';
                if (btn) btn.innerHTML = '<i class="ri-checkbox-multiple-line"></i> Gérer';
                return;
            }

            // Enter manage mode
            songManageState = { albumId, selections: new Set() };
            let idx = 0;
            list.querySelectorAll('.song-item').forEach(row => {
                const songId = parseInt(row.dataset.songId);
                row.dataset.index = idx++;
                row.onclick = null;

                const cb = document.createElement('div');
                cb.className = 'song-manage-cb';
                cb.style.cssText = 'width:22px;height:22px;border-radius:50%;border:2px solid var(--text-secondary);background:transparent;display:flex;align-items:center;justify-content:center;font-size:13px;color:white;flex-shrink:0;margin-right:10px;margin-left:6px;cursor:pointer;transition:background 0.15s;';
                cb.onclick = (e) => { e.stopPropagation(); toggleSongSelection(albumId, songId); };
                row.prepend(cb);
                row.style.cursor = 'pointer';
                row.onclick = (e) => toggleSongSelection(albumId, songId);
            });

            if (bar) bar.style.display = 'flex';
            if (btn) btn.innerHTML = `<i class="ri-close-line"></i> ${t('editor.done_btn','Terminer')}`;
        }

        function toggleSongSelection(albumId, songId) {
            if (!songManageState || songManageState.albumId !== albumId) return;
            const row = document.querySelector(`.song-item[data-song-id="${songId}"]`);
            const cb  = row?.querySelector('.song-manage-cb');
            if (songManageState.selections.has(songId)) {
                songManageState.selections.delete(songId);
                row?.classList.remove('song-selected');
                if (cb) { cb.textContent = ''; cb.style.background = 'transparent'; cb.style.borderColor = 'var(--text-secondary)'; }
            } else {
                songManageState.selections.add(songId);
                row?.classList.add('song-selected');
                if (cb) { cb.textContent = '✓'; cb.style.background = 'var(--accent)'; cb.style.borderColor = 'var(--accent)'; }
            }
            updateSongManageBar(albumId);
        }

        function updateSongManageBar(albumId) {
            if (!songManageState) return;
            const n = songManageState.selections.size;
            const countEl   = document.getElementById(`song-manage-count-${albumId}`);
            const deleteBtn = document.getElementById(`delete-songs-btn-${albumId}`);
            if (countEl)   countEl.textContent = n === 0 ? t('common.none_selected_f','Aucune sélectionnée') : `${n} chanson${n > 1 ? 's' : ''} sélectionnée${n > 1 ? 's' : ''}`;
            if (deleteBtn) deleteBtn.disabled = (n < 1);
        }

        async function deleteSelectedSongs(albumId) {
            if (!songManageState || songManageState.selections.size < 1) return;
            const ids = [...songManageState.selections];
            const titles = ids.map(id => {
                const row = document.querySelector(`.song-item[data-song-id="${id}"]`);
                return row?.querySelector('.song-title')?.textContent?.trim() || `Chanson ${id}`;
            });
            const plural = ids.length > 1 ? 's' : '';
            const confirmed = confirm(
                `Supprimer ${ids.length} chanson${plural} ?\n\n` +
                titles.join('\n') +
                `\n\nLes fichiers seront supprimés du disque. Cette action est irréversible.`
            );
            if (!confirmed) return;

            try {
                const res = await fetch(`${BASE_PATH}/api/library.php?action=delete_songs&user=${encodeURIComponent(app.currentUser)}`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ song_ids: ids }),
                });
                const result = await res.json();
                if (result.error) { alert(t('common.error_prefix','Erreur : ') + result.message); return; }

                const d = result.data;
                let msg = `${d.deleted} chanson${d.deleted > 1 ? 's' : ''} supprimée${d.deleted > 1 ? 's' : ''}.`;
                if (d.failed?.length) msg += `\n⚠ ${d.failed.length} chanson(s) non trouvée(s).`;
                alert(msg);
            } catch (e) {
                alert(t('common.error_prefix','Erreur : ') + e.message);
                return;
            }

            songManageState = null;
            // Reload the album view (it may be empty now, which will trigger artist view)
            viewAlbum(albumId);
        }

        async function deleteSelectedAlbums(artistId) {
            if (!albumManageState || albumManageState.selections.size < 1) return;
            const ids = [...albumManageState.selections];
            const names = ids.map(id => {
                const card = document.querySelector(`.album-card[data-album-id="${id}"]`);
                return card?.querySelector('.album-name')?.textContent?.trim() || `Album ${id}`;
            });
            const plural = ids.length > 1 ? 's' : '';
            const confirmed = confirm(
                `Supprimer ${ids.length} album${plural} ?\n\n` +
                names.join('\n') +
                `\n\nTous les fichiers audio seront supprimés du disque. Cette action est irréversible.`
            );
            if (!confirmed) return;

            let totalFiles = 0;
            let errors = [];
            for (const albumId of ids) {
                const fd = new FormData();
                fd.append('user', app.currentUser);
                fd.append('album_id', albumId);
                try {
                    const res = await fetch(`${BASE_PATH}/api/library.php?action=delete_album`, { method: 'POST', body: fd });
                    const result = await res.json();
                    if (result.error) errors.push(result.message);
                    else totalFiles += result.data?.deleted_files || 0;
                } catch (e) {
                    errors.push(`Album ${albumId}: ${e.message}`);
                }
            }

            let msg = `${ids.length} album${plural} supprimé${plural}. ${totalFiles} fichier${totalFiles > 1 ? 's' : ''} supprimé${totalFiles > 1 ? 's' : ''}.`;
            if (errors.length) msg += '\n\nErreurs :\n' + errors.join('\n');
            alert(msg);

            albumManageState = null;
            viewArtist(artistId);
        }

        function closeEditTagsModal() {
            tagEditor.close();
        }

        // Close song properties on overlay click
        document.getElementById('songPropsOverlay').addEventListener('click', (e) => {
            if (e.target.id === 'songPropsOverlay') closeSongProperties();
        });

        // Close artwork editor on overlay click
        document.getElementById('artworkEditorOverlay').addEventListener('click', (e) => {
            if (e.target.id === 'artworkEditorOverlay') closeArtworkEditor();
        });

        // Close modal on overlay click
        document.getElementById('tagEditorOverlay').addEventListener('click', (e) => {
            if (e.target.id === 'tagEditorOverlay') {
                tagEditor.close();
            }
        });

        // Close on Escape key
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && document.getElementById('tagEditorOverlay').classList.contains('active')) {
                tagEditor.close();
            }
        });

        // Initialize app
        init();
