/**
 * Gullify - Shared Logic (Base)
 */

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
        contentBody.innerHTML = '<div class="loading"><div class="loading-spinner"></div><p>Chargement...</p></div>';
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
