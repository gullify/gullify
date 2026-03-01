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
