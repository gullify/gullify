/**
 * Gullify — Equalizer modal
 *
 * 10-band peaking/shelving EQ wired to gullifyAudio. Sliders are vertical,
 * range -12dB to +12dB, with a centre detent at 0dB. Presets row underneath
 * (flat, rock, pop, jazz, classical, vocal, electronic, bass+, treble+).
 *
 * Open via window.openEqualizer() — wired to a topbar icon button (gear menu
 * / settings) and to a player extras button.
 */
(function () {
    'use strict';

    const BAND_LABELS = ['32', '64', '125', '250', '500', '1k', '2k', '4k', '8k', '16k'];

    const PRESET_LABELS = {
        flat: 'Flat', rock: 'Rock', pop: 'Pop', jazz: 'Jazz', classical: 'Classical',
        electronic: 'Electronic', vocal: 'Vocal', bass_boost: 'Bass+', treble_boost: 'Treble+',
        custom: 'Custom',
    };

    function $(id) { return document.getElementById(id); }

    function buildBands() {
        const host = $('eqBands');
        if (!host || host.dataset.built === '1') return;
        host.innerHTML = '';
        for (let i = 0; i < 10; i++) {
            const band = document.createElement('div');
            band.className = 'eq-band';
            band.innerHTML = `
                <div class="eq-band-value mono" id="eqBandValue${i}">0</div>
                <input type="range" class="eq-slider" id="eqBandSlider${i}"
                       min="-12" max="12" step="0.5" value="0"
                       orient="vertical" aria-label="${BAND_LABELS[i]} Hz">
                <div class="eq-band-label mono">${BAND_LABELS[i]}</div>
            `;
            host.appendChild(band);
        }
        host.dataset.built = '1';

        for (let i = 0; i < 10; i++) {
            const slider = $('eqBandSlider' + i);
            slider.addEventListener('input', () => {
                const v = parseFloat(slider.value);
                $('eqBandValue' + i).textContent = (v > 0 ? '+' : '') + v.toFixed(1).replace(/\.0$/, '');
                if (window.gullifyAudio) window.gullifyAudio.setBandGain(i, v);
                updatePresetLabel();
            });
        }
    }

    function buildPresets() {
        const host = $('eqPresets');
        if (!host || host.dataset.built === '1') return;
        host.innerHTML = Object.keys(PRESET_LABELS)
            .filter(k => k !== 'custom')
            .map(k => `<button class="chip" data-preset="${k}">${PRESET_LABELS[k]}</button>`)
            .join('');
        host.dataset.built = '1';
        host.addEventListener('click', (e) => {
            const btn = e.target.closest('[data-preset]');
            if (!btn) return;
            const name = btn.dataset.preset;
            if (window.gullifyAudio) window.gullifyAudio.applyPreset(name);
            syncFromAudio();
        });
    }

    function syncFromAudio() {
        if (!window.gullifyAudio || !window.gullifyAudio.ensure()) return;
        for (let i = 0; i < 10; i++) {
            const v = window.gullifyAudio.getBandGain(i);
            const s = $('eqBandSlider' + i);
            const t = $('eqBandValue' + i);
            if (s) s.value = v;
            if (t) t.textContent = (v > 0 ? '+' : '') + v.toFixed(1).replace(/\.0$/, '');
        }
        const enabled = window.gullifyAudio.enabled !== false;
        const cb = $('eqEnabled');
        if (cb) cb.checked = enabled;
        updatePresetLabel();
    }

    function updatePresetLabel() {
        const lbl = $('eqPresetLabel');
        if (!lbl) return;
        const p = (window.gullifyAudio && window.gullifyAudio.preset) || 'flat';
        lbl.textContent = PRESET_LABELS[p] || p;
        document.querySelectorAll('#eqPresets .chip').forEach(b => {
            b.classList.toggle('active', b.dataset.preset === p);
        });
    }

    function open() {
        const m = $('eqModal');
        if (!m) return;
        buildBands();
        buildPresets();
        // Lazy chain init on user gesture
        if (window.gullifyAudio) window.gullifyAudio.ensure();
        syncFromAudio();
        m.removeAttribute('hidden');
        document.body.classList.add('eq-open');
    }

    function close() {
        const m = $('eqModal');
        if (!m) return;
        m.setAttribute('hidden', '');
        document.body.classList.remove('eq-open');
    }

    function bindOnce() {
        const closeBtn = $('eqClose');
        const backdrop = $('eqBackdrop');
        const enabled  = $('eqEnabled');

        if (closeBtn) closeBtn.addEventListener('click', close);
        if (backdrop) backdrop.addEventListener('click', close);
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && !$('eqModal').hasAttribute('hidden')) close();
        });
        if (enabled) enabled.addEventListener('change', () => {
            if (window.gullifyAudio) window.gullifyAudio.setEnabled(enabled.checked);
            syncFromAudio();
        });
    }

    window.openEqualizer = open;
    window.closeEqualizer = close;

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', bindOnce);
    } else {
        bindOnce();
    }
})();
