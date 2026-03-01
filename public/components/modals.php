<!-- Toast notifications -->
<div class="toast" id="toast"></div>

<!-- Premium Tag Editor Modal -->
<div class="tag-editor-overlay" id="tagEditorOverlay">
    <div class="tag-editor-modal">
        <!-- Header -->
        <div class="tag-editor-header">
            <h2>
                <span class="icon">🏷️</span>
                Éditeur de Tags
            </h2>
            <button class="tag-editor-close" onclick="tagEditor.close()">&times;</button>
        </div>

        <!-- Tabs -->
        <div class="tag-editor-tabs">
            <button class="tag-editor-tab active" data-tab="edit" onclick="tagEditor.switchTab('edit')">
                ✏️ Édition
                <span class="badge" id="songCountBadge">0</span>
            </button>
            <button class="tag-editor-tab" data-tab="youtube" onclick="tagEditor.switchTab('youtube')">
                🎵 YouTube Music
            </button>
            <button class="tag-editor-tab" data-tab="files" onclick="tagEditor.switchTab('files')">
                📁 Fichiers
            </button>
        </div>

        <!-- Content -->
        <div class="tag-editor-content" id="tagEditorContent">
            <div class="loading-spinner"></div>
        </div>

        <!-- Footer -->
        <div class="tag-editor-footer">
            <div class="footer-info">
                <span class="status-indicator" id="statusIndicator"></span>
                <span id="statusText">Prêt</span>
            </div>
            <div class="footer-actions">
                <button class="btn btn-secondary" onclick="tagEditor.close()">Annuler</button>
                <button class="btn btn-primary btn-apply-all" id="saveAllBtn" onclick="tagEditor.saveAll()">
                    💾 Sauvegarder tout
                </button>
            </div>
        </div>
    </div>
</div>

<!-- Tag Editor Toast -->
<div class="tag-editor-toast" id="tagEditorToast"></div>
