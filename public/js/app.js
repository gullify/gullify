/**
 * Gullify - Shared Logic (Base)
 */

/**
 * i18n: Translation helper (dot-notation key lookup)
 * Usage: t('nav.home') or t('common.loading', 'Loading...')
 */
window.t = function(key, fallback) {
    const parts = key.split('.');
    let val = window.gullifyLang || {};
    for (const p of parts) {
        val = val?.[p];
        if (val === undefined) return fallback ?? key;
    }
    return val ?? fallback ?? key;
};

/**
 * i18n: Apply data-i18n attributes to DOM elements
 * Elements with data-i18n="key" get their textContent replaced.
 * Elements with data-i18n-attr="placeholder" get that attribute set instead.
 */
window.applyI18n = function() {
    document.querySelectorAll('[data-i18n]').forEach(el => {
        const key = el.dataset.i18n;
        const attr = el.dataset.i18nAttr;
        const translation = window.t(key, el.textContent);
        if (attr) {
            el.setAttribute(attr, translation);
        } else {
            el.textContent = translation;
        }
    });
};

/**
 * Utility: Format Time
 */
function formatTime(seconds) {
    if (isNaN(seconds) || seconds === null) return '0:00';
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = Math.floor(seconds % 60);
    if (h > 0) {
        return h + ":" + (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
    }
    return m + ":" + (s < 10 ? "0" : "") + s;
}

/**
 * Toast notifications
 */
function showToast(message, type = 'info') {
    const toast = document.getElementById('toast');
    if (!toast) return;
    toast.textContent = message;
    toast.className = 'toast show ' + type;
    setTimeout(() => { toast.classList.remove('show'); }, 3000);
}

/**
 * Extract a representative dominant color from an image URL.
 * Returns a Promise resolving to an oklch() color string, or a sensible fallback.
 * Used by the audiophile theme to tint album/artist hero backdrops.
 */
window._heroColorCache = {};
window.extractHeroColor = function(imgUrl) {
    if (!imgUrl) return Promise.resolve('oklch(0.30 0.06 250 / 0.4)');
    if (window._heroColorCache[imgUrl]) return Promise.resolve(window._heroColorCache[imgUrl]);
    return new Promise((resolve) => {
        const img = new Image();
        img.crossOrigin = 'anonymous';
        const fallback = 'oklch(0.30 0.06 250 / 0.4)';
        img.onerror = () => resolve(fallback);
        img.onload = () => {
            try {
                const size = 32;
                const canvas = document.createElement('canvas');
                canvas.width = size; canvas.height = size;
                const ctx = canvas.getContext('2d');
                ctx.drawImage(img, 0, 0, size, size);
                const data = ctx.getImageData(0, 0, size, size).data;
                // Pick the most saturated, mid-luminance pixel
                let bestR = 0, bestG = 0, bestB = 0, bestScore = -1;
                for (let i = 0; i < data.length; i += 4) {
                    const r = data[i], g = data[i+1], b = data[i+2], a = data[i+3];
                    if (a < 128) continue;
                    const max = Math.max(r, g, b), min = Math.min(r, g, b);
                    const lum = (max + min) / 2 / 255;
                    const sat = max === 0 ? 0 : (max - min) / max;
                    // Reward saturation, penalize extreme darks/lights
                    const score = sat * (1 - Math.abs(lum - 0.5));
                    if (score > bestScore) {
                        bestScore = score;
                        bestR = r; bestG = g; bestB = b;
                    }
                }
                const hex = '#' +
                    [bestR, bestG, bestB].map(v => v.toString(16).padStart(2, '0')).join('');
                // Use oklch with limited chroma + 0.4 alpha for a soft hero gradient
                const color = `color-mix(in oklch, ${hex} 55%, transparent)`;
                window._heroColorCache[imgUrl] = color;
                resolve(color);
            } catch (e) {
                resolve(fallback);
            }
        };
        img.src = imgUrl;
    });
};

/**
 * Apply the extracted hero color to an element as the --hero-color CSS variable.
 */
window.applyHeroColor = function(el, imgUrl) {
    if (!el) return;
    window.extractHeroColor(imgUrl).then(color => {
        el.style.setProperty('--hero-color', color);
    });
};

/**
 * Audiophile-only: queue panel toggle (desktop ≥1025px).
 * The right-rail queue is permanent. Both the player-bar queue button
 * (#unifiedQueueToggle) and the new topbar button (#topbarQueueToggle) toggle
 * `.collapsed` on the sidebar and `.queue-collapsed` on .main-content, giving
 * the user a way to hide the panel for a full-width main view. State persists
 * across sessions. Outside audiophile-desktop the legacy slide-in drawer
 * behavior is left untouched.
 */
(function () {
    function isAudiophileDesktop() {
        return document.documentElement.getAttribute('data-theme') === 'audiophile'
            && window.innerWidth >= 1025;
    }
    function applyState(collapsed, sidebar, main, topBtn) {
        sidebar.classList.toggle('collapsed', collapsed);
        main.classList.toggle('queue-collapsed', collapsed);
        if (topBtn) topBtn.classList.toggle('active', !collapsed);
    }
    function bindQueueCollapse() {
        const playerBtn = document.getElementById('unifiedQueueToggle');
        const topBtn    = document.getElementById('topbarQueueToggle');
        const sidebar   = document.getElementById('unifiedQueueSidebar');
        const main      = document.querySelector('.main-content');
        if (!sidebar || !main) { setTimeout(bindQueueCollapse, 250); return; }

        const stored = localStorage.getItem('gullifyQueueCollapsed') === '1';
        if (isAudiophileDesktop()) {
            applyState(stored, sidebar, main, topBtn);
        }

        function onClick() {
            if (!isAudiophileDesktop()) return;
            const willCollapse = !sidebar.classList.contains('collapsed');
            applyState(willCollapse, sidebar, main, topBtn);
            localStorage.setItem('gullifyQueueCollapsed', willCollapse ? '1' : '0');
        }
        if (playerBtn) playerBtn.addEventListener('click', onClick);
        if (topBtn)    topBtn.addEventListener('click', onClick);

        // If the theme switches at runtime, reset margins / state cleanly
        const observer = new MutationObserver(() => {
            if (isAudiophileDesktop()) {
                applyState(localStorage.getItem('gullifyQueueCollapsed') === '1', sidebar, main, topBtn);
            } else {
                sidebar.classList.remove('collapsed');
                main.classList.remove('queue-collapsed');
                if (topBtn) topBtn.classList.remove('active');
            }
        });
        observer.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
    }
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', bindQueueCollapse);
    } else {
        bindQueueCollapse();
    }
})();

/**
 * Audiophile-only: notifications system.
 *
 * Polls /api/notifications.php for a count every 30s, updates the topbar
 * bell's badge dot, and renders items into the popover when opened. Items
 * are clickable for navigation when the payload carries an albumId or
 * artistId. "Mark all read" + "Effacer tout" actions live in the popover
 * footer.
 */
(function () {
    const POLL_MS = 30_000;
    let pollTimer = null;
    let lastUnread = 0;

    function $(id) { return document.getElementById(id); }
    function basePath() { return window.BASE_PATH || ''; }

    async function fetchCount() {
        try {
            const r = await fetch(basePath() + '/api/notifications.php?action=count', { credentials: 'same-origin' });
            const j = await r.json();
            if (j && j.success) updateBadge(j.unread || 0);
        } catch (e) { /* silent */ }
    }

    async function fetchList() {
        try {
            const r = await fetch(basePath() + '/api/notifications.php?action=list&limit=30', { credentials: 'same-origin' });
            const j = await r.json();
            if (j && j.success) {
                renderList(j.data || []);
                updateBadge(j.unread || 0);
            }
        } catch (e) { /* silent */ }
    }

    function updateBadge(count) {
        lastUnread = count;
        const dot = $('topbarNotifDot');
        if (dot) dot.toggleAttribute('hidden', !(count > 0));
    }

    function timeAgo(iso) {
        const d = new Date(String(iso).replace(' ', 'T'));
        if (isNaN(d)) return '';
        const sec = Math.max(0, Math.floor((Date.now() - d.getTime()) / 1000));
        if (sec < 60)        return `il y a ${sec}s`;
        if (sec < 3600)      return `il y a ${Math.floor(sec / 60)}m`;
        if (sec < 86400)     return `il y a ${Math.floor(sec / 3600)}h`;
        if (sec < 604800)    return `il y a ${Math.floor(sec / 86400)}j`;
        return d.toLocaleDateString('fr-FR');
    }

    function escapeHtml(s) {
        return String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    }

    const ICONS = {
        scan_complete: 'ri-radar-line',
        download_done: 'ri-download-cloud-line',
        download_failed: 'ri-error-warning-line',
        import:         'ri-add-circle-line',
        info:           'ri-information-line',
    };

    function renderList(items) {
        const host = $('notifList');
        if (!host) return;
        if (!items.length) {
            host.innerHTML = '<div class="cast-empty mono">Aucune notification</div>';
            const footer = $('notifFooter');
            if (footer) footer.hidden = true;
            return;
        }
        host.innerHTML = items.map(n => {
            const icon = ICONS[n.type] || ICONS.info;
            const cls  = 'notif-item' + (n.unread ? ' unread' : '');
            const data = n.data || {};
            const action =
                data.albumId  ? `data-album-id="${data.albumId}"`   :
                data.artistId ? `data-artist-id="${data.artistId}"` : '';
            const msg = n.message ? `<div class="notif-message">${escapeHtml(n.message)}</div>` : '';
            return `
                <div class="${cls}" data-id="${n.id}" ${action}>
                    <span class="notif-icon"><i class="${icon}"></i></span>
                    <div class="notif-body">
                        <div class="notif-title">${escapeHtml(n.title)}</div>
                        ${msg}
                        <div class="notif-time mono">${timeAgo(n.created_at)}</div>
                    </div>
                    <button class="notif-clear" title="Supprimer" aria-label="Clear">
                        <i class="ri-close-line"></i>
                    </button>
                </div>
            `;
        }).join('');
        const footer = $('notifFooter');
        if (footer) footer.hidden = false;
    }

    async function markRead(id = 0) {
        try {
            const r = await fetch(basePath() + `/api/notifications.php?action=mark_read&id=${id}`,
                { method: 'POST', credentials: 'same-origin' });
            const j = await r.json();
            if (j && j.success) updateBadge(j.unread || 0);
        } catch (e) {}
    }
    async function clearOne(id = 0) {
        try {
            const r = await fetch(basePath() + `/api/notifications.php?action=clear&id=${id}`,
                { method: 'POST', credentials: 'same-origin' });
            const j = await r.json();
            if (j && j.success) {
                updateBadge(j.unread || 0);
                fetchList();
            }
        } catch (e) {}
    }

    function bindNotifPopover() {
        const list = $('notifList');
        if (list && list.dataset.bound !== '1') {
            list.dataset.bound = '1';
            list.addEventListener('click', async (e) => {
                const clearBtn = e.target.closest('.notif-clear');
                const item     = e.target.closest('.notif-item');
                if (!item) return;
                const id = parseInt(item.dataset.id, 10);
                if (clearBtn) {
                    e.stopPropagation();
                    await clearOne(id);
                    return;
                }
                // Open mark-as-read + navigate (album/artist) if payload allows
                await markRead(id);
                item.classList.remove('unread');
                if (item.dataset.albumId && typeof window.viewAlbum === 'function') {
                    window.viewAlbum(parseInt(item.dataset.albumId, 10));
                } else if (item.dataset.artistId && typeof window.viewArtist === 'function') {
                    window.viewArtist(parseInt(item.dataset.artistId, 10));
                }
            });
        }
        const markAllBtn = $('notifMarkAll');
        const clearAllBtn = $('notifClearAll');
        if (markAllBtn && markAllBtn.dataset.bound !== '1') {
            markAllBtn.dataset.bound = '1';
            markAllBtn.addEventListener('click', async () => {
                await markRead(0);
                document.querySelectorAll('#notifList .notif-item.unread').forEach(el => el.classList.remove('unread'));
            });
        }
        if (clearAllBtn && clearAllBtn.dataset.bound !== '1') {
            clearAllBtn.dataset.bound = '1';
            clearAllBtn.addEventListener('click', async () => {
                await clearOne(0);
            });
        }
    }

    function startPolling() {
        if (pollTimer) return;
        fetchCount();
        pollTimer = setInterval(fetchCount, POLL_MS);
    }

    // Public hook: opens the popover and refreshes the list
    window.gullifyNotifications = {
        refreshList: fetchList,
        refreshCount: fetchCount,
        markAllRead: () => markRead(0),
    };

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', () => { bindNotifPopover(); startPolling(); });
    } else {
        bindNotifPopover();
        startPolling();
    }
})();

/**
 * Audiophile-only: topbar action bindings (nav arrows, cast, notifications,
 * settings). The buttons are rendered for all themes by default but the CSS
 * only reveals them in audiophile-desktop. Wire them up unconditionally;
 * activation is gated by visibility.
 */
(function () {
    function isAudiophileDesktop() {
        return document.documentElement.getAttribute('data-theme') === 'audiophile'
            && window.innerWidth >= 1025;
    }
    function $(id) { return document.getElementById(id); }

    function closePopover(id) {
        const el = $(id);
        if (el) el.setAttribute('hidden', '');
    }
    function openPopover(id, anchorBtn) {
        // Close any other popover first
        ['castPopover', 'notifPopover'].forEach(p => { if (p !== id) closePopover(p); });
        const el = $(id);
        if (!el) return;
        el.removeAttribute('hidden');
        // Position under the anchor button
        if (anchorBtn) {
            const r = anchorBtn.getBoundingClientRect();
            el.style.right = (window.innerWidth - r.right) + 'px';
            el.style.top = (r.bottom + 8) + 'px';
        }
    }

    function bindTopbarActions() {
        const back     = $('topbarBackBtn');
        const fwd      = $('topbarForwardBtn');
        const cast     = $('topbarCastBtn');
        const notif    = $('topbarNotifBtn');
        const settings = $('topbarSettingsBtn');
        const castPop  = $('castPopover');
        const notifPop = $('notifPopover');
        const castClose  = $('castClose');
        const notifClose = $('notifClose');

        if (back)     back.addEventListener('click',     () => history.back());
        if (fwd)      fwd.addEventListener('click',      () => history.forward());
        if (cast)     cast.addEventListener('click',     () => openPopover('castPopover',  cast));
        if (notif)    notif.addEventListener('click',    () => {
            openPopover('notifPopover', notif);
            if (window.gullifyNotifications) window.gullifyNotifications.refreshList();
        });
        if (castClose)  castClose.addEventListener('click',  () => closePopover('castPopover'));
        if (notifClose) notifClose.addEventListener('click', () => closePopover('notifPopover'));

        const eqBtn = $('topbarEqBtn');
        if (eqBtn) eqBtn.addEventListener('click', () => {
            if (typeof window.openEqualizer === 'function') window.openEqualizer();
        });

        if (settings) settings.addEventListener('click', () => {
            // Open the settings submenu and render the first section.
            // The nav-item[data-view="settings"] is a parent that toggles the
            // submenu; clicking it alone doesn't render content. We click the
            // first sub-item which calls renderSettings() internally.
            const parent = document.querySelector('.nav-item[data-view="settings"]');
            const submenu = document.getElementById('settingsSubmenu');
            if (parent && !parent.classList.contains('open')) {
                parent.classList.add('open');
                if (submenu) submenu.classList.add('open');
            }
            const firstSection = document.querySelector('.nav-subitem[data-settings-section]');
            if (firstSection) firstSection.click();
        });

        // Close popovers on outside click or Esc
        document.addEventListener('click', (e) => {
            if (castPop && !castPop.hasAttribute('hidden')) {
                if (!castPop.contains(e.target) && e.target !== cast && !(cast && cast.contains(e.target))) {
                    closePopover('castPopover');
                }
            }
            if (notifPop && !notifPop.hasAttribute('hidden')) {
                if (!notifPop.contains(e.target) && e.target !== notif && !(notif && notif.contains(e.target))) {
                    closePopover('notifPopover');
                }
            }
        });
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape') {
                closePopover('castPopover');
                closePopover('notifPopover');
            }
        });
    }
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', bindTopbarActions);
    } else {
        bindTopbarActions();
    }
})();

/**
 * UI State Helpers
 */
function showLoading() {
    const contentBody = document.getElementById('contentBody');
    if (contentBody) {
        contentBody.innerHTML = `<div class="loading"><div class="loading-spinner"></div><p>${t('common.loading', 'Chargement...')}</p></div>`;
    }
}

function showError(message) {
    const contentBody = document.getElementById('contentBody');
    if (contentBody) {
        contentBody.innerHTML = `<div class="empty-state"><div class="empty-state-icon">⚠️</div><p>${message}</p></div>`;
    }
}

function showEmpty(message) {
    const contentBody = document.getElementById('contentBody');
    if (contentBody) {
        contentBody.innerHTML = `<div class="empty-state"><div class="empty-state-icon">🎵</div><p>${message}</p></div>`;
    }
}
