/**
 * Gullify — Shared Web Audio chain
 *
 * The HTMLMediaElement source can only be tapped ONCE via
 * createMediaElementSource. Centralize that here so the visualizer (in
 * now-playing-fs.js) and the equalizer (in equalizer.js) share the same node
 * graph.
 *
 * Graph: <audio> → source → EQ[0..9] → analyser → destination
 *
 * The chain is built lazily on the first call to ensureChain() (which must
 * happen during a user gesture so the AudioContext can resume).
 */
(function () {
    'use strict';

    const BANDS_HZ = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

    const PRESETS = {
        flat:        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        rock:        [4, 3, 2, 0, -1, -1, 0, 2, 3, 4],
        pop:         [-1, 0, 1, 3, 4, 4, 3, 1, 0, -1],
        jazz:        [3, 2, 1, 2, -2, -2, 0, 1, 2, 3],
        classical:   [4, 3, 2, 0, 0, 0, -2, -2, -2, -3],
        electronic:  [4, 3, 1, 0, -2, 2, 1, 1, 3, 4],
        vocal:       [-2, -3, -3, 1, 4, 4, 3, 1, 0, -1],
        bass_boost:  [6, 5, 4, 2, 0, 0, 0, 0, 0, 0],
        treble_boost:[0, 0, 0, 0, 0, 1, 2, 4, 5, 6],
    };

    const STATE_KEY = 'gullifyEqState';

    let ctx = null;
    let source = null;
    let analyser = null;
    let bands = [];      // BiquadFilterNode[]
    let initFailed = false;
    let initOnce = false;

    function loadState() {
        try {
            const raw = localStorage.getItem(STATE_KEY);
            if (!raw) return null;
            const parsed = JSON.parse(raw);
            if (!parsed || !Array.isArray(parsed.gains) || parsed.gains.length !== BANDS_HZ.length) return null;
            return parsed;
        } catch (e) { return null; }
    }
    function saveState() {
        const gains = bands.map(b => b ? b.gain.value : 0);
        try {
            localStorage.setItem(STATE_KEY, JSON.stringify({ gains, enabled: !!api.enabled, preset: api.preset }));
        } catch (e) { /* ignore */ }
    }

    function ensureChain() {
        if (initOnce) return !initFailed;
        initOnce = true;

        const audio = document.getElementById('unifiedAudioPlayer');
        if (!audio) { initFailed = true; return false; }

        const Ctx = window.AudioContext || window.webkitAudioContext;
        if (!Ctx) { initFailed = true; return false; }

        try {
            ctx = new Ctx();
            source = ctx.createMediaElementSource(audio);

            // Build a chain of 10 peaking/shelving filters
            bands = BANDS_HZ.map((freq, i) => {
                const f = ctx.createBiquadFilter();
                if (i === 0)                  f.type = 'lowshelf';
                else if (i === BANDS_HZ.length - 1) f.type = 'highshelf';
                else                          f.type = 'peaking';
                f.frequency.value = freq;
                f.Q.value = 1.0;
                f.gain.value = 0;
                return f;
            });

            analyser = ctx.createAnalyser();
            analyser.fftSize = 128;

            // Wire: source → bands[0] → bands[1] → ... → analyser → destination
            let prev = source;
            for (const b of bands) { prev.connect(b); prev = b; }
            prev.connect(analyser);
            analyser.connect(ctx.destination);

            // Restore persisted state
            const saved = loadState();
            if (saved) {
                api.enabled = saved.enabled !== false;
                api.preset  = saved.preset || 'flat';
                if (api.enabled) {
                    saved.gains.forEach((g, i) => bands[i].gain.value = g || 0);
                }
            }

            return true;
        } catch (e) {
            console.warn('gullifyAudio: init failed', e);
            initFailed = true;
            return false;
        }
    }

    const api = {
        BANDS_HZ,
        PRESETS,
        enabled: true,
        preset: 'flat',

        ensure: ensureChain,
        getAnalyser: () => { ensureChain(); return analyser; },
        getContext:  () => { ensureChain(); return ctx; },
        getBands:    () => { ensureChain(); return bands; },

        setBandGain(i, dB) {
            if (!ensureChain() || !bands[i]) return;
            const v = Math.max(-12, Math.min(12, Number(dB) || 0));
            bands[i].gain.value = api.enabled ? v : 0;
            api.preset = 'custom';
            saveState();
            // Even when disabled we still remember the user's setting via state
            if (!api.enabled) {
                const saved = loadState() || { gains: bands.map(() => 0), enabled: false, preset: 'custom' };
                saved.gains[i] = v;
                try { localStorage.setItem(STATE_KEY, JSON.stringify(saved)); } catch (e) {}
            }
        },
        getBandGain(i) {
            ensureChain();
            return bands[i] ? bands[i].gain.value : 0;
        },
        applyPreset(name) {
            if (!ensureChain()) return;
            const preset = PRESETS[name];
            if (!preset) return;
            api.preset = name;
            preset.forEach((g, i) => { if (bands[i]) bands[i].gain.value = api.enabled ? g : 0; });
            saveState();
        },
        reset() {
            api.applyPreset('flat');
        },
        setEnabled(on) {
            ensureChain();
            api.enabled = !!on;
            if (api.enabled) {
                // Re-apply the persisted gains
                const saved = loadState();
                if (saved && Array.isArray(saved.gains)) {
                    saved.gains.forEach((g, i) => { if (bands[i]) bands[i].gain.value = g || 0; });
                }
            } else {
                bands.forEach(b => { if (b) b.gain.value = 0; });
            }
            saveState();
        },
    };

    window.gullifyAudio = api;
})();
