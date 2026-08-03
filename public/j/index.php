<?php
/**
 * Gullify — page invité d'une partie multijoueur.
 *
 * Servie sur https://<domaine>/j/<CODE> (voir .htaccess). Autonome : tout le
 * style et tout le script sont en ligne, aucune dépendance externe, pour que
 * la page s'ouvre vite sur le téléphone d'un invité en 4G.
 *
 * Elle ne connaît que deux choses : le code du salon (dans l'URL) et le jeton
 * remis en donnant son prénom (gardé en localStorage pour survivre à un
 * rafraîchissement). Toute la logique de jeu vit côté serveur.
 */
declare(strict_types=1);

$code = strtoupper(preg_replace('/[^A-Za-z0-9]/', '', (string)($_GET['code'] ?? '')));
if (strlen($code) > 8) $code = substr($code, 0, 8);
?>
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#14161C">
<meta name="robots" content="noindex, nofollow">
<title>Gullify — Partie</title>
<link rel="icon" href="/favicon.ico">
<style>
  :root {
    --bg: #14161C;
    --glass: rgba(255,255,255,.07);
    --glass-strong: rgba(255,255,255,.12);
    --line: rgba(255,255,255,.14);
    --fg: #F2F4F8;
    --muted: #9AA2B1;
    --accent: #6C7BFF;
    --ok: #2FA36B;
    --ko: #E5484D;
    --gold: #E0A32E;
  }
  * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
  html, body { margin: 0; padding: 0; min-height: 100%; }
  body {
    background: var(--bg);
    color: var(--fg);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    font-size: 16px;
    line-height: 1.35;
    padding: env(safe-area-inset-top) 0 env(safe-area-inset-bottom);
    overflow-x: hidden;
  }
  /* Deux halos colorés en fond : l'app a le même dégradé « verre nuit ». */
  body::before {
    content: ''; position: fixed; inset: 0; z-index: -1; pointer-events: none;
    background:
      radial-gradient(60vw 60vw at 12% 4%, rgba(108,123,255,.28), transparent 62%),
      radial-gradient(52vw 52vw at 92% 96%, rgba(224,163,46,.16), transparent 60%);
  }
  /* La barre du talkie-walkie flotte au-dessus : on lui garde sa place. */
  .wrap { max-width: 620px; margin: 0 auto; padding: 18px 16px 40px; }
  body.talking .wrap { padding-bottom: 104px; }
  .glass {
    background: var(--glass);
    border: 1px solid var(--line);
    border-radius: 22px;
    backdrop-filter: blur(20px) saturate(140%);
    -webkit-backdrop-filter: blur(20px) saturate(140%);
    box-shadow: 0 10px 30px rgba(0,0,0,.28);
  }
  .pad { padding: 18px; }
  h1 { font-size: 26px; font-weight: 800; letter-spacing: -.7px; margin: 0 0 4px; }
  h2 { font-size: 19px; font-weight: 800; letter-spacing: -.4px; margin: 0 0 10px; }
  .muted { color: var(--muted); font-size: 13.5px; }
  .center { text-align: center; }
  .row { display: flex; align-items: center; gap: 10px; }
  .spacer { flex: 1; }
  .stack > * + * { margin-top: 12px; }

  header.top { display: flex; align-items: center; gap: 10px; margin-bottom: 14px; }
  header.top img { height: 26px; opacity: .95; }
  .code-chip {
    font-weight: 800; letter-spacing: 2px; font-size: 14px;
    padding: 6px 12px; border-radius: 999px;
    background: var(--glass-strong); border: 1px solid var(--line);
  }

  input[type=text] {
    width: 100%; padding: 14px 16px; font-size: 17px; color: var(--fg);
    background: rgba(255,255,255,.06); border: 1px solid var(--line);
    border-radius: 16px; outline: none; font-family: inherit;
  }
  input[type=text]:focus { border-color: var(--accent); }

  button {
    font-family: inherit; font-size: 16px; font-weight: 700; color: var(--fg);
    background: var(--glass-strong); border: 1px solid var(--line);
    border-radius: 16px; padding: 14px 18px; cursor: pointer; width: 100%;
    transition: transform .08s ease, opacity .15s ease;
  }
  button:active { transform: scale(.985); }
  button[disabled] { opacity: .5; cursor: default; }
  button.accent {
    background: var(--accent); border-color: transparent; color: #fff;
    box-shadow: 0 8px 22px rgba(108,123,255,.35);
  }
  button.ghost { background: transparent; border-color: transparent; color: var(--muted); font-weight: 600; }

  /* Choix de réponse */
  .choice { text-align: left; display: block; margin-bottom: 9px; }
  .choice .t { font-size: 15.5px; font-weight: 700; }
  .choice .s { font-size: 12.5px; color: var(--muted); margin-top: 1px; }
  .choice.correct { border-color: var(--ok); background: rgba(47,163,107,.18); }
  .choice.wrong   { border-color: var(--ko); background: rgba(229,72,77,.18); }
  .choice.faded   { opacity: .45; }
  .choice.picked  { box-shadow: 0 0 0 2px var(--accent) inset; }

  /* Chrono de manche */
  .bar { height: 7px; border-radius: 6px; background: rgba(255,255,255,.10); overflow: hidden; }
  .bar > i { display: block; height: 100%; background: var(--accent); border-radius: 6px; transition: background .2s; }
  .bar.low > i { background: var(--ko); }

  /* Pochettes */
  .cover { width: 100%; aspect-ratio: 1/1; border-radius: 18px; overflow: hidden; background: rgba(255,255,255,.05); }
  .cover img { width: 100%; height: 100%; object-fit: cover; display: block; }
  .cover.blurred img { transform: scale(1.12); }

  /* Duel */
  .duel { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
  .duel button { padding: 10px; }
  .duel .cover { border-radius: 14px; margin-bottom: 8px; }
  .duel .t { font-size: 14px; font-weight: 700; line-height: 1.2; }
  .duel .s { font-size: 12px; color: var(--muted); }
  .duel .y { font-size: 20px; font-weight: 800; margin-top: 6px; letter-spacing: -.5px; }
  .vs { text-align: center; font-weight: 800; color: var(--muted); margin: 8px 0; letter-spacing: 1px; }

  /* Frise du Chrono */
  .timeline { display: flex; align-items: stretch; gap: 0; overflow-x: auto; padding: 4px 0 10px; }
  .tl-card {
    flex: 0 0 108px; border-radius: 14px; padding: 8px;
    background: var(--glass-strong); border: 1px solid var(--line); text-align: center;
  }
  .tl-card .y { font-size: 19px; font-weight: 800; letter-spacing: -.5px; }
  .tl-card .t { font-size: 11px; color: var(--muted); margin-top: 2px;
                overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .tl-gap { flex: 0 0 42px; display: flex; align-items: center; justify-content: center; }
  .tl-gap button {
    width: 34px; height: 34px; padding: 0; border-radius: 12px; font-size: 20px; line-height: 1;
    border-style: dashed; color: var(--accent);
  }
  .tl-gap.off button { opacity: .18; border-style: solid; color: var(--muted); }

  /* Joueurs */
  .players { list-style: none; margin: 0; padding: 0; }
  .players li { display: flex; align-items: center; gap: 10px; padding: 9px 2px; border-bottom: 1px solid rgba(255,255,255,.06); }
  .players li:last-child { border-bottom: 0; }
  .players .nm { font-weight: 700; font-size: 15px; }
  .players .sc { font-weight: 800; font-size: 16px; letter-spacing: -.3px; }
  .players .tag { font-size: 11px; color: var(--muted); border: 1px solid var(--line); border-radius: 999px; padding: 2px 7px; }
  .dot { width: 9px; height: 9px; border-radius: 50%; background: rgba(255,255,255,.18); flex: 0 0 auto; }
  .dot.on { background: var(--ok); }
  .dot.ko { background: var(--ko); }
  .rank { width: 22px; color: var(--muted); font-weight: 800; font-size: 13px; }
  .hearts { letter-spacing: 1px; font-size: 13px; }

  .eq { display: flex; align-items: flex-end; gap: 3px; height: 26px; justify-content: center; }
  .eq i { width: 4px; background: var(--accent); border-radius: 2px; height: 6px; }
  .eq.on i { animation: eqb .9s ease-in-out infinite; }
  .eq i:nth-child(2){ animation-delay:.15s } .eq i:nth-child(3){ animation-delay:.3s }
  .eq i:nth-child(4){ animation-delay:.45s } .eq i:nth-child(5){ animation-delay:.6s }
  @keyframes eqb { 0%,100%{height:6px} 50%{height:24px} }

  .verdict { font-weight: 800; font-size: 17px; }
  .verdict.ok { color: var(--ok); } .verdict.ko { color: var(--ko); }
  .big { font-size: 42px; font-weight: 800; letter-spacing: -1.5px; color: var(--accent); }
  .err { color: var(--ko); font-size: 14px; min-height: 18px; }

  /* Talkie-walkie : une barre fixe, toujours à portée de pouce. */
  .talkbar {
    position: fixed; z-index: 20;
    left: 50%; transform: translateX(-50%);
    bottom: calc(12px + env(safe-area-inset-bottom));
    width: min(620px, calc(100% - 24px));
    display: flex; align-items: center; gap: 10px;
    padding: 10px; border-radius: 22px;
  }
  .talkbar[hidden] { display: none; }
  .talkbar .ptt {
    flex: 1 1 auto; min-width: 0; padding: 13px 10px; font-size: 15px;
    touch-action: none; user-select: none; -webkit-user-select: none;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
  }
  .talkbar .ptt.rec {
    background: var(--ko); border-color: transparent; color: #fff;
    box-shadow: 0 8px 22px rgba(229,72,77,.4);
  }
  .talkbar .ptt.hear { background: rgba(108,123,255,.22); border-color: var(--accent); }
  .talkbar .icon { flex: 0 0 50px; width: 50px; padding: 13px 0; font-size: 18px; }
  .talkbar .icon.off { opacity: .4; }

  @media (prefers-reduced-motion: reduce) { .eq.on i { animation: none; } }
</style>
</head>
<body>
<div class="wrap">
  <header class="top">
    <img src="/logo_gullify_wh.png" alt="Gullify">
    <div class="spacer"></div>
    <span class="code-chip" id="codeChip"><?= htmlspecialchars($code, ENT_QUOTES) ?></span>
  </header>
  <main id="app" class="stack"></main>
</div>

<div class="talkbar glass" id="talkbar" hidden>
  <button type="button" class="ptt" id="pttBtn">🎙️ <span id="pttLabel">Maintiens pour parler</span></button>
  <button type="button" class="icon" id="spkBtn" title="Entendre les autres">🔊</button>
</div>

<audio id="snippet" preload="auto" playsinline></audio>
<audio id="voice" preload="auto" playsinline></audio>

<script>
(function () {
  'use strict';

  var API = '/api/v2/party.php';
  var CODE = <?= json_encode($code) ?>;
  var app = document.getElementById('app');
  var audio = document.getElementById('snippet');
  var voice = document.getElementById('voice');
  var talkbar = document.getElementById('talkbar');
  var pttBtn = document.getElementById('pttBtn');
  var pttLabel = document.getElementById('pttLabel');
  var spkBtn = document.getElementById('spkBtn');

  var token = null;
  var state = null;          // dernier état reçu du serveur
  var info = null;           // carte de visite du salon (avant d'avoir rejoint)
  var clockOffset = 0;       // horloge serveur − horloge locale, en ms
  var polling = false;
  var busy = false;          // une réponse est en cours d'envoi
  var lastRoundKey = null;   // pour ne recharger l'extrait qu'au changement
  var audioBlocked = false;
  var errorMsg = '';
  var renderedKey = null;    // évite de reconstruire le DOM à chaque sondage
  var pendingName = '';      // prénom en cours de saisie, conservé aux rebuilds
  var focusedOnce = false;

  var GAMES = {
    blind:  { name: 'Blind test',      goal: 'Reconnais le titre le plus vite possible.' },
    cover:  { name: 'Pochette mystère', goal: 'Reconnais l’album avant que la pochette ne soit nette.' },
    duel:   { name: 'Duel d’années', goal: 'Désigne le plus ancien des deux albums.' },
    chrono: { name: 'Chrono',           goal: 'Place chaque titre au bon endroit de ta frise.' }
  };

  // ───────────────────────────────────────────────────────────── réseau ──

  function call(action, params, method) {
    var url = API + '?action=' + encodeURIComponent(action);
    var opts = { method: method || 'GET', headers: {} };
    if (opts.method === 'GET') {
      for (var k in params) if (params[k] !== undefined && params[k] !== null) {
        url += '&' + k + '=' + encodeURIComponent(params[k]);
      }
    } else {
      opts.headers['Content-Type'] = 'application/json';
      opts.body = JSON.stringify(params || {});
    }
    return fetch(url, opts).then(function (r) { return r.json(); }).then(function (j) {
      if (j && j.success) return j.data;
      var e = new Error((j && j.error && j.error.message) || 'Erreur réseau');
      e.code = (j && j.error && j.error.code) || 'unknown';
      throw e;
    });
  }

  function storeKey() { return 'gullify_party_' + CODE; }

  function saveToken(t) {
    token = t;
    try { localStorage.setItem(storeKey(), t); } catch (e) {}
  }

  function forgetToken() {
    token = null;
    try { localStorage.removeItem(storeKey()); } catch (e) {}
  }

  // ────────────────────────────────────────────────────────── sondage ──

  function applyState(s) {
    state = s;
    clockOffset = s.serverNow - Date.now();
    errorMsg = '';
    syncAudio();
    syncVoice();
    render();
  }

  function poll() {
    if (!token || polling) return;
    polling = true;
    call('state', { code: CODE, token: token }).then(applyState).catch(function (e) {
      if (e.code === 'party_not_found' || e.code === 'player_not_found') {
        forgetToken();
        state = null;
        renderedKey = null;
        errorMsg = e.message;
        stopVoice();
        render();
      }
    }).then(function () { polling = false; });
  }

  // ──────────────────────────────────────────────────────────── audio ──

  /** Charge l'extrait de la manche quand elle change (mode « à distance »). */
  function syncAudio() {
    if (!state || state.audioMode !== 'guests' || !state.round) { stopAudio(); return; }
    if (state.round.kind !== 'blind' && state.round.kind !== 'chrono') { stopAudio(); return; }
    var key = state.roundIndex + ':' + state.phase;
    if (key === lastRoundKey) return;
    lastRoundKey = key;
    if (state.phase !== 'guessing') { stopAudio(); return; }

    audio.src = API + '?action=snippet&code=' + encodeURIComponent(CODE) +
                '&token=' + encodeURIComponent(token) + '&round=' + state.roundIndex;
    audioBlocked = false;
    play();
  }

  /**
   * Lance l'extrait. Un refus (lecture automatique bloquée, ou navigateur qui
   * ne sait pas jouer) ne doit jamais casser la manche : on retombe sur un
   * bouton « Lancer l'extrait ».
   */
  function play() {
    try {
      var p = audio.play();
      if (p && p.catch) p.catch(blocked);
    } catch (e) { blocked(); }
  }

  function blocked() {
    audioBlocked = true;
    render();
  }

  function stopAudio() {
    try { audio.pause(); audio.removeAttribute('src'); audio.load(); } catch (e) {}
  }

  function replay() {
    audioBlocked = false;
    try { audio.currentTime = 0; } catch (e) {}
    play();
    render();
  }

  // ────────────────────────────────────────────────────────── actions ──

  function doJoin(name) {
    errorMsg = '';
    render();
    call('join', { code: CODE, name: name }, 'POST').then(function (d) {
      saveToken(d.token);
      renderedKey = null;
      applyState(d.state);
    }).catch(function (e) {
      errorMsg = e.message;
      render();
    });
  }

  function doAnswer(answer) {
    if (busy || !state || state.phase !== 'guessing') return;
    busy = true;
    // La réponse est affichée tout de suite : le serveur confirmera.
    if (state.round) state.round.myAnswer = String(answer);
    render();
    call('answer', { code: CODE, token: token, answer: String(answer) }, 'POST')
      .then(applyState)
      .catch(function (e) { errorMsg = e.message; render(); })
      .then(function () { busy = false; });
  }

  function doSkip() {
    if (busy) return;
    busy = true;
    call('skip', { code: CODE, token: token }, 'POST')
      .then(applyState)
      .catch(function (e) { errorMsg = e.message; render(); })
      .then(function () { busy = false; });
  }

  function doLeave() {
    call('leave', { code: CODE, token: token }, 'POST').catch(function () {}).then(function () {
      forgetToken();
      state = null;
      renderedKey = null;
      stopVoice();
      loadInfo();
    });
  }

  // ────────────────────────────────────────────────────── construction ──

  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text !== undefined && text !== null) n.textContent = text;
    return n;
  }

  function card(cls) {
    var c = el('section', 'glass pad' + (cls ? ' ' + cls : ''));
    return c;
  }

  function remainingMs() {
    if (!state) return 0;
    var total = state.phase === 'revealed' ? state.revealMs : state.roundMs;
    var elapsed = (Date.now() + clockOffset) - state.phaseAt;
    return Math.max(0, total - elapsed);
  }

  /**
   * Clé de rendu : tant qu'elle ne change pas, seuls le chrono et la pochette
   * sont rafraîchis. Sans ça, reconstruire le DOM chaque seconde annulerait
   * l'appui sur un bouton et ferait clignoter la page.
   */
  function renderKey() {
    if (!token) return 'join:' + (info ? info.status + ':' + (info.players || []).length : '?') + ':' + errorMsg;
    if (!state) return 'nostate:' + errorMsg;
    var k = [state.status, state.phase, state.roundIndex, state.version, errorMsg, audioBlocked].join('|');
    if (state.round) k += '|' + (state.round.myAnswer || '');
    return k;
  }

  function render() {
    var key = renderKey();
    if (key !== renderedKey) {
      renderedKey = key;
      app.innerHTML = '';
      build();
    }
    // La barre du talkie-walkie vit hors du DOM reconstruit : un appui sur le
    // micro ne doit pas être annulé par l'arrivée d'un autre joueur.
    renderTalk();
    tickVisuals();
  }

  function build() {
    if (!CODE) { app.appendChild(viewNoCode()); return; }
    if (!token) { app.appendChild(viewJoin()); return; }
    if (!state) { app.appendChild(viewMessage('Connexion au salon…')); return; }
    if (state.status === 'lobby') { app.appendChild(viewLobby()); return; }
    if (state.status === 'finished') { app.appendChild(viewFinished()); return; }
    app.appendChild(viewRound());
    app.appendChild(viewScores(false));
  }

  function viewNoCode() {
    var c = card();
    c.appendChild(el('h1', null, 'Rejoindre une partie'));
    c.appendChild(el('p', 'muted', 'Saisis le code que l’hôte t’a envoyé.'));
    var input = el('input');
    input.type = 'text';
    input.maxLength = 8;
    input.placeholder = 'CODE';
    input.autocapitalize = 'characters';
    input.style.textTransform = 'uppercase';
    input.style.letterSpacing = '4px';
    input.style.textAlign = 'center';
    input.style.marginTop = '12px';
    c.appendChild(input);
    var go = el('button', 'accent', 'Continuer');
    go.style.marginTop = '12px';
    go.onclick = function () {
      var v = (input.value || '').replace(/[^A-Za-z0-9]/g, '').toUpperCase();
      if (v) location.href = '/j/' + v;
    };
    c.appendChild(go);
    return c;
  }

  function viewJoin() {
    var c = card();
    if (!info) {
      c.appendChild(el('h1', null, 'Partie ' + CODE));
      c.appendChild(el('p', 'muted', 'Chargement du salon…'));
      return c;
    }
    if (info.error) {
      c.appendChild(el('h1', null, 'Partie introuvable'));
      c.appendChild(el('p', 'muted', 'Ce lien a expiré ou la partie est terminée. Demande un nouveau lien à l’hôte.'));
      return c;
    }
    var g = GAMES[info.game] || { name: info.game, goal: '' };
    c.appendChild(el('h1', null, g.name));
    c.appendChild(el('p', 'muted', g.goal));

    var sub = el('p', 'muted');
    sub.style.marginTop = '10px';
    sub.textContent = 'Chez ' + (info.hostName || 'l’hôte') + ' · ' +
      (info.players || []).length + '/' + info.maxPlayers + ' joueurs';
    c.appendChild(sub);

    if ((info.players || []).length) {
      c.appendChild(el('p', 'muted', (info.players || []).join(' · ')));
    }

    if (info.status !== 'lobby') {
      var w = el('p', 'err', 'La partie a déjà commencé — impossible de la rejoindre.');
      w.style.marginTop = '14px';
      c.appendChild(w);
      return c;
    }

    var input = el('input');
    input.type = 'text';
    input.maxLength = 20;
    input.placeholder = 'Ton prénom';
    input.autocomplete = 'nickname';
    input.style.marginTop = '16px';
    // Le salon se rafraîchit pendant qu'on tape (un autre invité arrive) :
    // la saisie en cours doit survivre à la reconstruction de la page.
    input.value = pendingName;
    input.addEventListener('input', function () { pendingName = input.value; });
    c.appendChild(input);

    var err = el('p', 'err', errorMsg);
    err.style.marginTop = '8px';
    c.appendChild(err);

    var go = el('button', 'accent', 'Rejoindre la partie');
    go.onclick = function () {
      var v = (input.value || '').trim();
      if (!v) { input.focus(); return; }
      go.disabled = true;
      // Premier geste de l'invité : il débloque la lecture audio du navigateur.
      unlockAudio();
      doJoin(v);
    };
    c.appendChild(go);
    input.addEventListener('keydown', function (e) { if (e.key === 'Enter') go.click(); });
    if (!focusedOnce) {
      focusedOnce = true;
      setTimeout(function () { input.focus(); }, 60);
    }
    return c;
  }

  /**
   * Débloque l'audio au premier geste de l'invité (le tap « Rejoindre », ou
   * n'importe quel autre s'il revient avec son jeton en poche). Les navigateurs
   * mobiles n'autorisent la lecture qu'après un geste : on joue un silence
   * maintenant pour que les extraits — et les messages vocaux — puissent partir
   * tout seuls ensuite.
   */
  var SILENCE = 'data:audio/wav;base64,UklGRiQAAABXQVZFZm10IBAAAAABAAEAgD4AAIA+AAABAAgAZGF0YQAAAAA=';
  var unlocked = false;

  function unlockEl(el) {
    try {
      // Ne jamais écraser une lecture en cours : on ne débloque que le vide.
      if (!el.getAttribute('src')) el.src = SILENCE;
      var p = el.play();
      if (p && p.catch) p.catch(function () {});
    } catch (e) { /* navigateur sans audio : la partie reste jouable */ }
  }

  function unlockAudio() {
    if (unlocked) return;
    unlocked = true;
    unlockEl(audio);
    unlockEl(voice);
  }

  function viewMessage(msg) {
    var c = card('center');
    c.appendChild(el('p', 'muted', msg));
    return c;
  }

  function viewLobby() {
    var frag = document.createDocumentFragment();
    var g = GAMES[state.game] || { name: state.game, goal: '' };
    var c = card();
    c.appendChild(el('h1', null, g.name));
    c.appendChild(el('p', 'muted', g.goal));
    var mode = el('p', 'muted');
    mode.style.marginTop = '10px';
    mode.textContent = state.audioMode === 'guests'
      ? '🎧 Chacun écoute sur son appareil — monte le son.'
      : '🔈 L’audio sort de l’appareil de l’hôte.';
    c.appendChild(mode);
    var wait = el('p', null, 'En attente du lancement par l’hôte…');
    wait.style.marginTop = '14px';
    wait.style.fontWeight = '700';
    c.appendChild(wait);
    frag.appendChild(c);
    frag.appendChild(viewScores(true));

    var quit = el('button', 'ghost', 'Quitter le salon');
    quit.style.marginTop = '12px';
    quit.onclick = doLeave;
    frag.appendChild(quit);

    var host = el('section');
    host.appendChild(frag);
    return host;
  }

  function viewScores(lobby) {
    var c = card();
    c.appendChild(el('h2', null, lobby ? 'Joueurs' : 'Classement'));
    var list = el('ul', 'players');
    var players = (state.players || []).slice();
    if (!lobby) players.sort(function (a, b) { return b.score - a.score; });

    players.forEach(function (p, i) {
      var li = el('li');
      if (!lobby) li.appendChild(el('span', 'rank', '#' + (i + 1)));
      var dot = el('span', 'dot' + (p.answered ? (p.correct === false ? ' ko' : ' on') : ''));
      li.appendChild(dot);
      var nm = el('span', 'nm', p.name + (state.me && p.id === state.me.id ? ' (toi)' : ''));
      li.appendChild(nm);
      if (p.isHost) li.appendChild(el('span', 'tag', 'hôte'));
      if (state.game === 'chrono' && state.status === 'playing') {
        li.appendChild(el('span', 'hearts', '❤️'.repeat(Math.max(0, p.lives))));
      }
      li.appendChild(el('span', 'spacer'));
      if (!lobby) {
        var sc = el('span', 'sc', String(p.score));
        if (p.gained) sc.textContent = p.score + ' (+' + p.gained + ')';
        li.appendChild(sc);
      }
      list.appendChild(li);
    });
    c.appendChild(list);
    return c;
  }

  function viewFinished() {
    var frag = el('section');
    var players = (state.players || []).slice().sort(function (a, b) { return b.score - a.score; });
    var me = state.me ? players.findIndex(function (p) { return p.id === state.me.id; }) : -1;
    var c = card('center');
    c.appendChild(el('h1', null, 'Partie terminée'));
    if (me >= 0) {
      c.appendChild(el('p', 'muted', me === 0 ? 'Tu gagnes 🏆' : 'Tu finis ' + (me + 1) + 'ᵉ'));
      c.appendChild(el('div', 'big', String(players[me].score)));
      c.appendChild(el('p', 'muted', state.game === 'chrono' ? 'cartes bien placées' : 'points'));
    }
    frag.appendChild(c);
    frag.appendChild(viewScores(false));
    var quit = el('button', 'ghost', 'Fermer');
    quit.style.marginTop = '12px';
    quit.onclick = doLeave;
    frag.appendChild(quit);
    return frag;
  }

  // ───────────────────────────────────────────────────────── les manches ──

  function viewRound() {
    var r = state.round;
    if (!r) return viewMessage('Manche en préparation…');
    var c = card();

    var head = el('div', 'row');
    head.appendChild(el('span', 'muted', 'Manche ' + (state.roundIndex + 1) + '/' + state.roundCount));
    head.appendChild(el('span', 'spacer'));
    head.appendChild(el('span', 'muted', (GAMES[state.game] || {}).name || ''));
    c.appendChild(head);

    var bar = el('div', 'bar');
    bar.id = 'timerBar';
    bar.appendChild(el('i'));
    bar.style.margin = '12px 0 4px';
    c.appendChild(bar);
    var cd = el('p', 'muted center');
    cd.id = 'countdown';
    c.appendChild(cd);

    if (r.kind === 'blind')  buildBlind(c, r);
    if (r.kind === 'cover')  buildCover(c, r);
    if (r.kind === 'duel')   buildDuel(c, r);
    if (r.kind === 'chrono') buildChrono(c, r);

    if (errorMsg) c.appendChild(el('p', 'err', errorMsg));
    return c;
  }

  function audioControls(parent) {
    if (state.audioMode !== 'guests') {
      var p = el('p', 'muted center', '🔈 Écoute sur l’appareil de l’hôte');
      p.style.margin = '14px 0';
      parent.appendChild(p);
      return;
    }
    var eq = el('div', 'eq' + (audioBlocked ? '' : ' on'));
    for (var i = 0; i < 5; i++) eq.appendChild(el('i'));
    eq.style.margin = '16px 0 10px';
    parent.appendChild(eq);

    var b = el('button', audioBlocked ? 'accent' : '', audioBlocked ? '▶ Lancer l’extrait' : '↻ Réécouter');
    b.onclick = replay;
    b.style.marginBottom = '12px';
    parent.appendChild(b);
  }

  function choiceButton(opt, r) {
    var b = el('button', 'choice');
    var picked = r.myAnswer !== null && r.myAnswer !== undefined && String(r.myAnswer) === String(opt.id);
    if (state.phase === 'revealed' && r.answerId !== undefined) {
      if (String(opt.id) === String(r.answerId)) b.className += ' correct';
      else if (picked) b.className += ' wrong';
      else b.className += ' faded';
    } else if (picked) {
      b.className += ' picked';
    }
    b.appendChild(el('div', 't', opt.title));
    if (opt.subtitle) b.appendChild(el('div', 's', opt.subtitle));
    b.disabled = state.phase !== 'guessing' || r.myAnswer != null;
    b.onclick = function () { doAnswer(opt.id); };
    return b;
  }

  function revealBanner(parent, r, correct) {
    var v = el('p', 'verdict center ' + (correct ? 'ok' : 'ko'),
      correct ? 'Bien vu !' : (r.myAnswer == null ? 'Temps écoulé' : 'Raté'));
    v.style.margin = '14px 0 6px';
    parent.appendChild(v);
    if (r.title) {
      var t = el('p', 'center', r.title);
      t.style.fontWeight = '700';
      parent.appendChild(t);
      if (r.artist) parent.appendChild(el('p', 'muted center', r.artist));
    }
  }

  function buildBlind(c, r) {
    if (state.phase === 'guessing') {
      c.appendChild(el('h2', 'center', 'Quel est ce titre ?'));
      audioControls(c);
    } else {
      var correct = r.answerId !== undefined && String(r.myAnswer) === String(r.answerId);
      if (r.artworkUrl) {
        var w = el('div', 'cover');
        w.style.maxWidth = '150px';
        w.style.margin = '14px auto 0';
        var img = el('img');
        img.src = '/' + r.artworkUrl;
        img.alt = '';
        w.appendChild(img);
        c.appendChild(w);
      }
      revealBanner(c, r, correct);
    }
    (r.options || []).forEach(function (o) { c.appendChild(choiceButton(o, r)); });
  }

  function buildCover(c, r) {
    var w = el('div', 'cover blurred');
    w.id = 'coverBox';
    w.style.maxWidth = '260px';
    w.style.margin = '10px auto 16px';
    var img = el('img');
    img.id = 'coverImg';
    img.src = '/' + r.artworkUrl;
    img.alt = '';
    w.appendChild(img);
    c.appendChild(w);

    if (state.phase === 'revealed') {
      var correct = r.answerId !== undefined && String(r.myAnswer) === String(r.answerId);
      revealBanner(c, r, correct);
    } else {
      c.appendChild(el('h2', 'center', 'Quel est cet album ?'));
    }
    (r.options || []).forEach(function (o) { c.appendChild(choiceButton(o, r)); });
  }

  function duelSide(side, r) {
    var b = el('button');
    var picked = r.myAnswer != null && String(r.myAnswer) === String(side.id);
    if (state.phase === 'revealed' && r.answerId !== undefined) {
      if (String(side.id) === String(r.answerId)) b.className = 'correct';
      else if (picked) b.className = 'wrong';
      else b.className = 'faded';
    } else if (picked) {
      b.className = 'picked';
    }
    var w = el('div', 'cover');
    var img = el('img');
    img.src = '/' + side.artworkUrl;
    img.alt = '';
    w.appendChild(img);
    b.appendChild(w);
    b.appendChild(el('div', 't', side.title));
    b.appendChild(el('div', 's', side.subtitle));
    if (side.year) b.appendChild(el('div', 'y', String(side.year)));
    b.disabled = state.phase !== 'guessing' || r.myAnswer != null;
    b.onclick = function () { doAnswer(side.id); };
    return b;
  }

  function buildDuel(c, r) {
    c.appendChild(el('h2', 'center', 'Lequel est le plus ancien ?'));
    var g = el('div', 'duel');
    g.appendChild(duelSide(r.left, r));
    g.appendChild(duelSide(r.right, r));
    c.appendChild(g);
    if (state.phase === 'revealed') {
      var correct = r.answerId !== undefined && String(r.myAnswer) === String(r.answerId);
      revealBanner(c, r, correct);
    }
  }

  function myPlayer() {
    if (!state || !state.me) return null;
    for (var i = 0; i < state.players.length; i++) {
      if (state.players[i].id === state.me.id) return state.players[i];
    }
    return null;
  }

  function playerById(id) {
    for (var i = 0; i < (state.players || []).length; i++) {
      if (state.players[i].id === id) return state.players[i];
    }
    return null;
  }

  function buildChrono(c, r) {
    var mine = state.turnPlayerId != null && state.me && state.turnPlayerId === state.me.id;
    var turnPlayer = playerById(state.turnPlayerId);
    var me = myPlayer();

    if (mine) {
      c.appendChild(el('h2', 'center', state.phase === 'guessing' ? 'À toi de placer' : 'Ton tour'));
      if (state.phase === 'guessing') audioControls(c);
    } else {
      c.appendChild(el('h2', 'center', 'Au tour de ' + (turnPlayer ? turnPlayer.name : '…')));
      if (state.phase === 'guessing') {
        c.appendChild(el('p', 'muted center', 'Écoute avec — tu ne peux pas répondre à sa place.'));
      }
    }

    if (state.phase === 'revealed' && r.year) {
      var v = el('p', 'center');
      v.style.margin = '12px 0 4px';
      v.appendChild(el('span', 'big', String(r.year)));
      c.appendChild(v);
      if (r.title) {
        var t = el('p', 'center', r.title);
        t.style.fontWeight = '700';
        c.appendChild(t);
        c.appendChild(el('p', 'muted center', r.artist || ''));
      }
    }

    // La frise affichée est celle du joueur du tour : c'est elle qui bouge.
    var shown = mine ? me : turnPlayer;
    var cards = (shown && shown.timeline) || [];
    c.appendChild(el('p', 'muted', mine ? 'Ta frise' : 'La frise de ' + (turnPlayer ? turnPlayer.name : '')));

    var tl = el('div', 'timeline');
    var canPlace = mine && state.phase === 'guessing' && r.myAnswer == null;
    for (var i = 0; i <= cards.length; i++) {
      var gap = el('div', 'tl-gap' + (canPlace ? '' : ' off'));
      var gb = el('button', null, '+');
      gb.disabled = !canPlace;
      (function (idx) { gb.onclick = function () { doAnswer(idx); }; })(i);
      gap.appendChild(gb);
      tl.appendChild(gap);
      if (i < cards.length) {
        var cc = el('div', 'tl-card');
        cc.appendChild(el('div', 'y', String(cards[i].year)));
        cc.appendChild(el('div', 't', cards[i].title || ''));
        tl.appendChild(cc);
      }
    }
    c.appendChild(tl);

    if (canPlace) {
      var sk = el('button', 'ghost', 'Passer mon tour');
      sk.onclick = doSkip;
      c.appendChild(sk);
    }
  }

  // ─────────────────────────────────────────────────────── talkie-walkie ──
  //
  // On ne tient pas un canal ouvert en permanence : on s'envoie des messages.
  // L'invité maintient le bouton, parle, relâche — le message part en entier et
  // les autres l'entendent au sondage suivant (une seconde plus tard au pire).
  // C'est ce qui permet de se parler sans rien installer, depuis un simple lien.

  var micOk = !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia && window.MediaRecorder);
  var VOICE_MAX_MS = 15000;      // bornes rappelées par le serveur à chaque état
  var VOICE_MIN_MS = 350;
  var VOICE_MAX_BYTES = 500000;

  var recorder = null, recStream = null, recChunks = [], recStartedAt = 0, recTimer = null;
  var recording = false, arming = false, releasedEarly = false;
  var speakerOn = true;
  var talkMsg = '', talkMsgAt = 0;

  var voiceQueue = [], voicePlaying = false, voiceDone = null;
  var lastVoiceId = 0, voicePrimed = false;

  /** Sourdine de l'extrait pendant qu'on parle ou qu'on écoute quelqu'un. */
  var ducks = 0;
  function duck(on) {
    ducks = Math.max(0, ducks + (on ? 1 : -1));
    try { audio.volume = ducks > 0 ? 0.18 : 1; } catch (e) {}
  }

  function talkStatus(msg) {
    talkMsg = msg;
    talkMsgAt = Date.now();
    renderTalk();
  }

  // ── parler ──

  /** Le meilleur format que sache produire ce navigateur, parmi ceux acceptés. */
  function pickMime() {
    var candidates = [
      'audio/webm;codecs=opus', 'audio/webm',
      'audio/ogg;codecs=opus', 'audio/ogg',
      'audio/mp4', 'audio/aac'
    ];
    for (var i = 0; i < candidates.length; i++) {
      if (window.MediaRecorder.isTypeSupported &&
          MediaRecorder.isTypeSupported(candidates[i])) return candidates[i];
    }
    return '';
  }

  function stopStream(stream) {
    if (!stream) return;
    try { stream.getTracks().forEach(function (t) { t.stop(); }); } catch (e) {}
  }

  function startTalk() {
    if (!micOk || !token || recording || arming) return;
    unlockAudio();
    arming = true;
    releasedEarly = false;
    talkStatus('Micro…');
    // Le micro n'est ouvert que le temps du message : pas de voyant rouge qui
    // traîne dans la barre du navigateur entre deux prises de parole.
    navigator.mediaDevices.getUserMedia({ audio: true }).then(function (stream) {
      arming = false;
      if (releasedEarly) { stopStream(stream); talkStatus(''); return; }
      recStream = stream;
      recChunks = [];
      var mime = pickMime();
      try {
        recorder = mime
          ? new MediaRecorder(stream, { mimeType: mime, audioBitsPerSecond: 32000 })
          : new MediaRecorder(stream);
      } catch (e) {
        recorder = new MediaRecorder(stream);
      }
      recorder.ondataavailable = function (e) { if (e.data && e.data.size) recChunks.push(e.data); };
      recorder.onstop = finishTalk;
      recorder.start();
      recording = true;
      recStartedAt = Date.now();
      duck(true);
      // Filet : un bouton resté enfoncé (ou un doigt oublié) ne bloque rien.
      recTimer = setTimeout(stopTalk, VOICE_MAX_MS);
      talkStatus('');
    }).catch(function () {
      arming = false;
      talkStatus('Micro refusé');
    });
  }

  function stopTalk() {
    if (recTimer) { clearTimeout(recTimer); recTimer = null; }
    if (arming) { releasedEarly = true; return; }
    if (!recording) return;
    recording = false;
    renderTalk();
    try { recorder.stop(); } catch (e) { finishTalk(); }
  }

  /** Le micro est refermé : on emballe ce qui a été capté et on l'envoie. */
  function finishTalk() {
    var ms = Date.now() - recStartedAt;
    var chunks = recChunks;
    var mime = (recorder && recorder.mimeType) || 'audio/webm';
    recChunks = [];
    recording = false;
    stopStream(recStream);
    recStream = null;
    recorder = null;
    duck(false);

    if (!chunks.length || ms < VOICE_MIN_MS) { talkStatus(''); return; }
    var blob = new Blob(chunks, { type: mime });
    if (blob.size > VOICE_MAX_BYTES) { talkStatus('Message trop lourd'); return; }

    talkStatus('Envoi…');
    blobToBase64(blob).then(function (b64) {
      return call('voice', {
        code: CODE, token: token, audio: b64, mime: mime, ms: ms
      }, 'POST');
    }).then(function () {
      talkStatus('Envoyé ✓');
    }).catch(function (e) {
      talkStatus(e.message || 'Message non envoyé');
    });
  }

  function blobToBase64(blob) {
    return new Promise(function (resolve, reject) {
      var r = new FileReader();
      r.onload = function () { resolve(String(r.result).split(',')[1] || ''); };
      r.onerror = function () { reject(new Error('Message illisible')); };
      r.readAsDataURL(blob);
    });
  }

  // ── écouter ──

  /**
   * Repère les messages arrivés depuis le dernier état. Le tout premier état
   * sert de point de départ : on ne rejoue jamais l'historique du salon à
   * quelqu'un qui vient d'arriver (ou qui rafraîchit sa page).
   */
  function syncVoice() {
    if (!state) return;
    var v = state.voice || {};
    if (v.maxMs) VOICE_MAX_MS = v.maxMs;
    if (v.minMs) VOICE_MIN_MS = v.minMs;

    var clips = v.clips || [];
    var maxId = lastVoiceId;
    for (var i = 0; i < clips.length; i++) {
      var c = clips[i];
      if (c.id > maxId) maxId = c.id;
      if (!voicePrimed || c.id <= lastVoiceId) continue;
      if (state.me && c.playerId === state.me.id) continue;  // on ne se réécoute pas
      if (!speakerOn) continue;
      voiceQueue.push(c);
    }
    lastVoiceId = maxId;
    voicePrimed = true;
    playNextVoice();
  }

  function playNextVoice() {
    if (voicePlaying || !speakerOn || !voiceQueue.length || !token) return;
    var c = voiceQueue.shift();
    var finished = false;
    voicePlaying = true;
    duck(true);
    talkStatus('🔊 ' + (c.name || 'Quelqu’un') + '…');

    var done = function () {
      if (finished) return;
      finished = true;
      voicePlaying = false;
      voiceDone = null;
      voice.onended = null;
      voice.onerror = null;
      duck(false);
      if (talkMsg.charAt(0) === '🔊') talkStatus('');
      playNextVoice();
    };
    voiceDone = done;
    voice.onended = done;
    voice.onerror = done;

    voice.src = API + '?action=voiceclip&code=' + encodeURIComponent(CODE) +
                '&token=' + encodeURIComponent(token) + '&id=' + c.id;
    try {
      var p = voice.play();
      if (p && p.catch) p.catch(done);
    } catch (e) { done(); return; }
    // Si le navigateur ne rend jamais la main (lecture refusée en silence),
    // le message suivant ne doit pas rester bloqué derrière.
    setTimeout(done, (c.ms || 3000) + 5000);
  }

  /** Coupe l'écoute en cours et jette la file (haut-parleur off, salon perdu). */
  function stopVoice() {
    voiceQueue = [];
    try { voice.pause(); } catch (e) {}
    if (voiceDone) voiceDone();
    renderTalk();
  }

  function toggleSpeaker() {
    speakerOn = !speakerOn;
    if (!speakerOn) stopVoice(); else renderTalk();
  }

  // ── la barre ──

  function renderTalk() {
    var show = !!(token && state);
    talkbar.hidden = !show;
    document.body.classList.toggle('talking', show);
    if (!show) return;

    pttBtn.disabled = !micOk;
    pttBtn.className = 'ptt' + (recording ? ' rec' : (voicePlaying ? ' hear' : ''));
    spkBtn.className = 'icon' + (speakerOn ? '' : ' off');
    spkBtn.textContent = speakerOn ? '🔊' : '🔇';
    spkBtn.title = speakerOn ? 'Couper les voix' : 'Entendre les autres';

    if (!micOk) {
      pttLabel.textContent = 'Micro indisponible ici';
    } else if (recording) {
      var s = Math.min(VOICE_MAX_MS, Date.now() - recStartedAt) / 1000;
      pttLabel.textContent = 'Relâche pour envoyer · ' + s.toFixed(1) + ' s';
    } else if (arming) {
      pttLabel.textContent = 'Micro…';
    } else if (talkMsg) {
      pttLabel.textContent = talkMsg;
    } else {
      pttLabel.textContent = 'Maintiens pour parler';
    }
  }

  /** Le compteur d'enregistrement, et l'effacement des messages passagers. */
  function tickTalk() {
    if (talkbar.hidden) return;
    if (recording) { renderTalk(); return; }
    if (talkMsg && talkMsg.charAt(0) !== '🔊' && Date.now() - talkMsgAt > 2200) {
      talkStatus('');
    }
  }

  if (window.PointerEvent) {
    pttBtn.addEventListener('pointerdown', function (e) { e.preventDefault(); startTalk(); });
    pttBtn.addEventListener('pointerup', function (e) { e.preventDefault(); stopTalk(); });
    pttBtn.addEventListener('pointercancel', stopTalk);
    pttBtn.addEventListener('pointerleave', stopTalk);
  } else {
    pttBtn.addEventListener('touchstart', function (e) { e.preventDefault(); startTalk(); });
    pttBtn.addEventListener('touchend', function (e) { e.preventDefault(); stopTalk(); });
    pttBtn.addEventListener('mousedown', startTalk);
    pttBtn.addEventListener('mouseup', stopTalk);
    pttBtn.addEventListener('mouseleave', stopTalk);
  }
  spkBtn.addEventListener('click', toggleSpeaker);
  // Relâcher en dehors du bouton doit couper le micro comme un relâchement.
  window.addEventListener('pointerup', function () { if (recording || arming) stopTalk(); });
  window.addEventListener('blur', function () { if (recording || arming) stopTalk(); });

  // ────────────────────────────────────── rafraîchissements légers (60 Hz) ──

  function tickVisuals() {
    if (!state || state.status !== 'playing') return;
    var left = remainingMs();
    var total = state.phase === 'revealed' ? state.revealMs : state.roundMs;
    var ratio = total > 0 ? Math.max(0, Math.min(1, left / total)) : 0;

    var bar = document.getElementById('timerBar');
    if (bar) {
      bar.firstChild.style.width = (ratio * 100).toFixed(1) + '%';
      bar.className = 'bar' + (state.phase === 'guessing' && ratio < 0.25 ? ' low' : '');
    }
    var cd = document.getElementById('countdown');
    if (cd) {
      cd.textContent = state.phase === 'revealed'
        ? 'Manche suivante…'
        : Math.ceil(left / 1000) + ' s';
    }
    // La pochette se précise à mesure que le temps passe.
    var img = document.getElementById('coverImg');
    if (img) {
      var blur = state.phase === 'revealed' ? 0 : (1.2 + 20.8 * ratio);
      img.style.filter = 'blur(' + blur.toFixed(1) + 'px)';
    }
  }

  // ─────────────────────────────────────────────────────────── démarrage ──

  function loadInfo() {
    if (!CODE) { render(); return; }
    call('info', { code: CODE }).then(function (d) {
      info = d;
      renderedKey = null;
      render();
    }).catch(function (e) {
      info = { error: true, message: e.message };
      renderedKey = null;
      render();
    });
  }

  try { token = localStorage.getItem(storeKey()); } catch (e) {}

  render();
  if (token) poll(); else loadInfo();

  // Un sondage par seconde suffit : c'est aussi lui qui fait avancer les
  // manches côté serveur (il n'y a pas de tâche de fond).
  setInterval(function () { if (token) poll(); else if (!info || info.status === 'lobby') loadInfo(); }, 1000);
  (function loopVisuals() { tickVisuals(); tickTalk(); requestAnimationFrame(loopVisuals); })();

  // Un invité qui revient avec son jeton en poche ne passe pas par « Rejoindre » :
  // son premier geste, quel qu'il soit, débloque l'audio du navigateur.
  document.addEventListener('pointerdown', unlockAudio, { once: true });
  document.addEventListener('touchstart', unlockAudio, { once: true });

  document.addEventListener('visibilitychange', function () {
    if (!document.hidden) { lastRoundKey = null; poll(); }
  });
})();
</script>
</body>
</html>
