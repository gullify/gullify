/**
 * Gullify — Now Playing Fullscreen (audiophile theme)
 *
 * Desktop overlay opened by clicking the player cover. Split layout: cover XL
 * on the left, track meta + lyrics + transport controls + visualizer on the
 * right. Hooks into window.gullifyPlayer for state and forwards transport
 * commands back to it.
 */
(function () {
    'use strict';

    const SELECTORS = {
        root: '#nowPlayingFS',
        bg: '#npfsBg',
        art: '#npfsArt',
        title: '#npfsTitle',
        artist: '#npfsArtist',
        album: '#npfsAlbum',
        lyrics: '#npfsLyrics',
        currentTime: '#npfsCurrentTime',
        totalTime: '#npfsTotalTime',
        progressBar: '#npfsProgressBar',
        progressFill: '#npfsProgressFill',
        playBtn: '#npfsPlay',
        prevBtn: '#npfsPrev',
        nextBtn: '#npfsNext',
        shuffleBtn: '#npfsShuffle',
        repeatBtn: '#npfsRepeat',
        favBtn: '#npfsFav',
        closeBtn: '#npfsClose',
        visualizer: '#npfsVisualizer',
    };

    const VISUALIZER_BARS = 48;
    let raf = null;
    let analyser = null;
    let audioCtx = null;
    let audioSrc = null;
    let lyricsLoadedFor = null;

    function $(s) { return document.querySelector(s); }

    function isAudiophile() {
        return document.documentElement.getAttribute('data-theme') === 'audiophile';
    }

    function getPlayer() {
        return window.gullifyPlayer;
    }

    function fmtTime(s) {
        if (!s || isNaN(s)) return '0:00';
        const m = Math.floor(s / 60);
        const sec = Math.floor(s % 60);
        return m + ':' + (sec < 10 ? '0' : '') + sec;
    }

    function buildVisualizerBars(host) {
        if (!host || host.dataset.built === '1') return;
        host.innerHTML = '';
        for (let i = 0; i < VISUALIZER_BARS; i++) {
            const bar = document.createElement('div');
            bar.className = 'viz-bar';
            bar.style.height = '4px';
            host.appendChild(bar);
        }
        host.dataset.built = '1';
    }

    function ensureAnalyser() {
        const player = getPlayer();
        if (!player || !player.audio) return null;
        if (analyser) return analyser;

        try {
            const Ctx = window.AudioContext || window.webkitAudioContext;
            if (!Ctx) return null;
            audioCtx = new Ctx();
            audioSrc = audioCtx.createMediaElementSource(player.audio);
            analyser = audioCtx.createAnalyser();
            analyser.fftSize = 128;
            audioSrc.connect(analyser);
            analyser.connect(audioCtx.destination);
            return analyser;
        } catch (e) {
            // createMediaElementSource throws if already created. In that case,
            // we silently fall back to a faux visualizer driven by time.
            console.warn('Visualizer: real audio analyser unavailable, using fallback', e);
            analyser = 'fallback';
            return analyser;
        }
    }

    function paintVisualizer() {
        const host = $(SELECTORS.visualizer);
        if (!host) return;
        const bars = host.children;
        const n = bars.length;
        if (!n) return;

        const player = getPlayer();
        const isPlaying = player && player.audio && !player.audio.paused;

        if (analyser && analyser !== 'fallback') {
            const data = new Uint8Array(analyser.frequencyBinCount);
            analyser.getByteFrequencyData(data);
            for (let i = 0; i < n; i++) {
                const idx = Math.floor(i * data.length / n);
                const v = data[idx] / 255;
                const h = isPlaying ? Math.max(4, v * 100) : 4;
                bars[i].style.height = h + '%';
            }
        } else {
            // Fallback: a soft sine animation when playing, flat when paused
            const t = Date.now() / 280;
            for (let i = 0; i < n; i++) {
                const v = isPlaying
                    ? (Math.sin(t + i * 0.4) * 0.5 + Math.sin(t * 0.7 + i * 0.13) * 0.5) * 0.5 + 0.5
                    : 0.04;
                bars[i].style.height = (4 + v * 92) + '%';
            }
        }
        raf = requestAnimationFrame(paintVisualizer);
    }

    function syncMeta() {
        const player = getPlayer();
        if (!player || !player.currentTrack) return;
        const t = player.currentTrack;

        const titleEl = $(SELECTORS.title);
        const artistEl = $(SELECTORS.artist);
        const albumEl = $(SELECTORS.album);
        const artEl = $(SELECTORS.art);
        const bgEl = $(SELECTORS.bg);

        if (titleEl) titleEl.textContent = t.title || '';
        if (artistEl) artistEl.textContent = t.artist || '';
        if (albumEl) albumEl.textContent = t.album || '';

        const artUrl = t.artworkUrl || t.artwork || (window.DEFAULT_ALBUM_IMG || '');
        if (artEl && artUrl) artEl.src = artUrl;
        if (bgEl && artUrl) bgEl.style.backgroundImage = 'url("' + artUrl + '")';

        // Tint backdrop based on the artwork's dominant color
        const root = $(SELECTORS.root);
        if (root && window.applyHeroColor && artUrl) window.applyHeroColor(root, artUrl);

        // Refresh lyrics if track changed
        if (t.filePath && t.filePath !== lyricsLoadedFor) {
            loadLyrics(t.filePath);
        }
    }

    async function loadLyrics(filePath) {
        const host = $(SELECTORS.lyrics);
        if (!host) return;
        lyricsLoadedFor = filePath;

        host.innerHTML = '<div class="npfs-lyrics-status mono">Chargement…</div>';
        try {
            const r = await fetch((window.BASE_PATH || '') + '/get_lyrics.php?path=' + encodeURIComponent(filePath));
            const data = await r.json();
            if (lyricsLoadedFor !== filePath) return; // race: track changed mid-fetch
            if (data.success && data.lyrics) {
                const lines = String(data.lyrics).split(/\r?\n/);
                host.innerHTML = lines.map(line => {
                    const safe = line
                        .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
                    return '<div class="lyric-line">' + (safe || '&nbsp;') + '</div>';
                }).join('');
            } else {
                host.innerHTML = '<div class="npfs-lyrics-status mono">Aucune parole disponible</div>';
            }
        } catch (e) {
            host.innerHTML = '<div class="npfs-lyrics-status mono">Erreur de chargement</div>';
        }
    }

    function syncProgress() {
        const player = getPlayer();
        if (!player || !player.audio) return;
        const cur = player.audio.currentTime || 0;
        const dur = player.audio.duration || 0;
        const pct = dur > 0 ? (cur / dur * 100) : 0;

        const cEl = $(SELECTORS.currentTime);
        const tEl = $(SELECTORS.totalTime);
        const fEl = $(SELECTORS.progressFill);
        if (cEl) cEl.textContent = fmtTime(cur);
        if (tEl) tEl.textContent = fmtTime(dur);
        if (fEl) fEl.style.width = pct + '%';
    }

    function syncPlayPause() {
        const player = getPlayer();
        if (!player || !player.audio) return;
        const btn = $(SELECTORS.playBtn);
        if (!btn) return;
        const i = btn.querySelector('i');
        if (!i) return;
        i.className = player.audio.paused ? 'ri-play-fill' : 'ri-pause-fill';
    }

    function syncToggleStates() {
        const player = getPlayer();
        if (!player) return;
        const sBtn = $(SELECTORS.shuffleBtn);
        const rBtn = $(SELECTORS.repeatBtn);
        if (sBtn) sBtn.classList.toggle('active', !!player.shuffle);
        if (rBtn) rBtn.classList.toggle('active', player.repeat && player.repeat !== 'none');
    }

    function open() {
        const root = $(SELECTORS.root);
        if (!root) return;
        if (!isAudiophile()) return;       // only the audiophile theme has the FS overlay
        if (window.innerWidth <= 768) return; // mobile keeps the existing mobile player

        buildVisualizerBars($(SELECTORS.visualizer));

        // Resume audio context (required after user gesture)
        ensureAnalyser();
        if (audioCtx && audioCtx.state === 'suspended') audioCtx.resume();

        root.removeAttribute('hidden');
        root.classList.add('open');
        document.body.classList.add('npfs-open');

        syncMeta();
        syncProgress();
        syncPlayPause();
        syncToggleStates();
        if (raf) cancelAnimationFrame(raf);
        raf = requestAnimationFrame(paintVisualizer);
    }

    function close() {
        const root = $(SELECTORS.root);
        if (!root) return;
        root.classList.remove('open');
        root.setAttribute('hidden', '');
        document.body.classList.remove('npfs-open');
        if (raf) { cancelAnimationFrame(raf); raf = null; }
    }

    function isOpen() {
        const root = $(SELECTORS.root);
        return root && !root.hasAttribute('hidden');
    }

    function bindOnce() {
        const root = $(SELECTORS.root);
        if (!root || root.dataset.bound === '1') return;
        root.dataset.bound = '1';

        // Close on escape, on close button, on backdrop double-click
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && isOpen()) close();
        });
        const closeBtn = $(SELECTORS.closeBtn);
        if (closeBtn) closeBtn.addEventListener('click', close);

        // Transport controls forward to the unified player
        const playBtn = $(SELECTORS.playBtn);
        const prevBtn = $(SELECTORS.prevBtn);
        const nextBtn = $(SELECTORS.nextBtn);
        const shuffleBtn = $(SELECTORS.shuffleBtn);
        const repeatBtn = $(SELECTORS.repeatBtn);

        if (playBtn) playBtn.addEventListener('click', () => {
            const p = getPlayer();
            if (p && typeof p.togglePlay === 'function') p.togglePlay();
        });
        if (prevBtn) prevBtn.addEventListener('click', () => {
            const p = getPlayer();
            if (p && typeof p.playPrevious === 'function') p.playPrevious();
        });
        if (nextBtn) nextBtn.addEventListener('click', () => {
            const p = getPlayer();
            if (p && typeof p.playNext === 'function') p.playNext();
        });
        if (shuffleBtn) shuffleBtn.addEventListener('click', () => {
            const p = getPlayer();
            if (p && typeof p.toggleShuffle === 'function') p.toggleShuffle();
            setTimeout(syncToggleStates, 50);
        });
        if (repeatBtn) repeatBtn.addEventListener('click', () => {
            const p = getPlayer();
            if (p && typeof p.toggleRepeat === 'function') p.toggleRepeat();
            setTimeout(syncToggleStates, 50);
        });

        // Click-to-seek on the progress bar
        const bar = $(SELECTORS.progressBar);
        if (bar) bar.addEventListener('click', (e) => {
            const p = getPlayer();
            if (!p || !p.audio || !p.audio.duration) return;
            const r = bar.getBoundingClientRect();
            const ratio = (e.clientX - r.left) / r.width;
            p.audio.currentTime = Math.max(0, Math.min(1, ratio)) * p.audio.duration;
            syncProgress();
        });

        // Subscribe to audio events on the unified player to keep the FS in sync
        const tryHook = () => {
            const p = getPlayer();
            if (!p || !p.audio) { setTimeout(tryHook, 200); return; }
            p.audio.addEventListener('timeupdate', () => { if (isOpen()) syncProgress(); });
            p.audio.addEventListener('play',  () => { if (isOpen()) syncPlayPause(); });
            p.audio.addEventListener('pause', () => { if (isOpen()) syncPlayPause(); });
            p.audio.addEventListener('loadedmetadata', () => { if (isOpen()) { syncMeta(); syncProgress(); } });
        };
        tryHook();

        // Click on the desktop player cover opens the FS (audiophile + desktop only)
        const desktopCover = document.getElementById('unifiedPlayerCover');
        if (desktopCover) {
            desktopCover.addEventListener('click', (e) => {
                if (!isAudiophile()) return;
                if (window.innerWidth <= 768) return;
                e.stopPropagation();
                open();
            });
            desktopCover.style.cursor = 'pointer';
            desktopCover.title = 'Now Playing';
        }
    }

    // Public API
    window.NowPlayingFS = { open, close, isOpen };

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', bindOnce);
    } else {
        bindOnce();
    }
})();
