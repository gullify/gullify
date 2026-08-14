<?php
/**
 * Gullify — page publique d'un partage : une chanson, un album, un artiste.
 *
 * Servie sur https://<domaine>/s/<JETON> (voir .htaccess). Comme la page
 * invité des parties : autonome, tout le style et tout le script en ligne,
 * aucune dépendance externe, pour qu'elle s'ouvre vite sur un téléphone en 4G.
 *
 * Les informations du partage sont rendues ici, côté serveur : le lien envoyé
 * par SMS montre alors sa pochette et son titre dans l'aperçu de la
 * conversation, sans que le destinataire ait à l'ouvrir. Le son, lui, ne part
 * qu'à la demande, par `share.php?action=stream`, titre par titre.
 */
declare(strict_types=1);

require_once __DIR__ . '/../../src/AppConfig.php';
require_once __DIR__ . '/../../src/SongShare.php';

$token = (string)($_GET['t'] ?? '');
$share = SongShare::validToken($token) ? SongShare::byToken($token) : null;

// Un partage dont plus rien n'est écoutable (album effacé depuis) vaut un lien
// mort : mieux vaut le dire que d'ouvrir une page muette.
$tracks = $share ? SongShare::tracks($share) : [];
$emptied = $share !== null && !$tracks;
if ($emptied) $share = null;

$base = rtrim((string)AppConfig::get('app.url', ''), '/');
if ($base === '' || str_contains($base, 'localhost')) {
    $https = ($_SERVER['HTTPS'] ?? '') !== ''
        || ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https';
    $base = ($https ? 'https' : 'http') . '://' . ($_SERVER['HTTP_HOST'] ?? 'localhost');
}

/** Échappement systématique : tout ce qui vient de la base passe par là. */
function e(string $v): string { return htmlspecialchars($v, ENT_QUOTES, 'UTF-8'); }

/** « 3:04 » — une durée de morceau. */
function clock(int $seconds): string {
    if ($seconds <= 0) return '--:--';
    return sprintf('%d:%02d', intdiv($seconds, 60), $seconds % 60);
}

/** « 3 h 20 » / « 45 min » — ce qu'il reste à vivre au lien. */
function human_left(int $ms): string {
    $min = (int)floor($ms / 60000);
    if ($min < 1) return "moins d'une minute";
    if ($min < 60) return $min . ' min';
    $h = intdiv($min, 60);
    $rest = $min % 60;
    return $rest > 0 ? $h . ' h ' . $rest : $h . ' h';
}

/** « 1 h 12 de musique » — le volume de ce qui est partagé. */
function human_total(int $seconds): string {
    $min = (int)round($seconds / 60);
    if ($min < 60) return max(1, $min) . ' min';
    $h = intdiv($min, 60);
    $rest = $min % 60;
    return $rest > 0 ? $h . ' h ' . $rest : $h . ' h';
}

if (!$share) {
    http_response_code(404);
    $kind     = 'song';
    $title    = 'Lien expiré';
    $artist   = '';
    $album    = '';
    $artwork  = '';
    $duration = 0;
    $leftMs   = 0;
} else {
    $view     = SongShare::publicView($share);
    $kind     = (string)$view['kind'];
    $title    = (string)$view['title'];
    $artist   = (string)$view['artist'];
    $album    = (string)$view['album'];
    $artwork  = $view['artworkUrl'] !== '' ? $base . '/' . $view['artworkUrl'] : '';
    $duration = (int)$view['duration'];
    $leftMs   = (int)$view['remainingMs'];
}

$streamBase = $share
    ? $base . '/api/v2/share.php?action=stream&token=' . rawurlencode($token)
    : '';

/** Ce que le lien montre de lui-même, selon ce qu'on a partagé. */
$chip = match ($kind) {
    'album'  => 'Album partagé',
    'artist' => 'Artiste partagé',
    default  => 'Écoute partagée',
};

// La liste passée au lecteur : rien d'autre que de quoi afficher et écouter.
$playlist = [];
foreach ($tracks as $t) {
    $playlist[] = [
        'id'     => (int)$t['id'],
        'title'  => (string)$t['title'],
        'artist' => (string)($t['artist_name'] ?? ''),
        'album'  => (string)($t['album_name'] ?? ''),
        'dur'    => (int)$t['duration'],
        'src'    => $streamBase . '&song=' . (int)$t['id'],
    ];
}
$multi = count($playlist) > 1;
?>
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#14161C">
<meta name="robots" content="noindex, nofollow">
<title><?= $share ? e($title) . ' — Gullify' : 'Gullify' ?></title>
<link rel="icon" href="/favicon.ico">
<?php if ($share): ?>
<meta property="og:type" content="<?= $kind === 'album' ? 'music.album' : ($kind === 'artist' ? 'profile' : 'music.song') ?>">
<meta property="og:site_name" content="Gullify">
<meta property="og:title" content="<?= e($title) ?>">
<?php
$og = match ($kind) {
    'album'  => ($artist !== '' ? $artist . ' — ' : '')
                . count($playlist) . ' titre' . (count($playlist) > 1 ? 's' : '')
                . ', à écouter pendant ' . human_left($leftMs),
    'artist' => count($playlist) . ' titre' . (count($playlist) > 1 ? 's' : '')
                . ' à écouter pendant ' . human_left($leftMs),
    default  => $artist !== ''
                ? $artist . ' — écoute pendant ' . human_left($leftMs)
                : 'Une chanson partagée sur Gullify',
};
?>
<meta property="og:description" content="<?= e($og) ?>">
<?php if ($artwork !== ''): ?>
<meta property="og:image" content="<?= e($artwork) ?>">
<meta name="twitter:card" content="summary_large_image">
<?php else: ?>
<?php /* Sans pochette, l'aperçu montre la mascotte plutôt qu'un cadre vide. */ ?>
<meta property="og:image" content="<?= e($base . '/android-chrome-512x512.png') ?>">
<meta name="twitter:card" content="summary">
<?php endif; ?>
<?php endif; ?>
<style>
  :root {
    --bg: #14161C;
    --glass: rgba(255,255,255,.07);
    --glass-strong: rgba(255,255,255,.12);
    --line: rgba(255,255,255,.14);
    --fg: #F2F4F8;
    --muted: #9AA2B1;
    --accent: #6C7BFF;
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
  /* Les deux mêmes halos que l'app et que la page invité des parties. */
  body::before {
    content: ''; position: fixed; inset: 0; z-index: -1; pointer-events: none;
    background:
      radial-gradient(60vw 60vw at 12% 4%, rgba(108,123,255,.28), transparent 62%),
      radial-gradient(52vw 52vw at 92% 96%, rgba(224,163,46,.16), transparent 60%);
  }
  .wrap { max-width: 520px; margin: 0 auto; padding: 18px 16px 40px; }
  .glass {
    background: var(--glass);
    border: 1px solid var(--line);
    border-radius: 24px;
    backdrop-filter: blur(20px) saturate(140%);
    -webkit-backdrop-filter: blur(20px) saturate(140%);
    box-shadow: 0 10px 30px rgba(0,0,0,.28);
  }
  header.top { display: flex; align-items: center; gap: 10px; margin-bottom: 16px; }
  /* Marque : la mascotte détourée, puis le mot posé à côté en typo. L'ancien
     lockup d'un seul tenant montrait la mouette d'avant ; son « Gullify »
     manuscrit ne se sépare pas du dessin, d'où le mot écrit ici. */
  .brand { display: flex; align-items: center; gap: 8px; text-decoration: none; color: var(--fg); }
  .brand img { height: 38px; width: auto; display: block; }
  .brand span { font-size: 19px; font-weight: 800; letter-spacing: -.5px; }
  .chip {
    font-size: 12.5px; font-weight: 700; letter-spacing: .3px;
    padding: 6px 12px; border-radius: 999px; color: var(--muted);
    background: var(--glass-strong); border: 1px solid var(--line);
  }
  .pad { padding: 20px; }
  .cover {
    width: 100%; aspect-ratio: 1 / 1; border-radius: 20px; object-fit: cover;
    display: block; background: var(--glass-strong); border: 1px solid var(--line);
  }
  /* Pas de pochette : la mascotte prend la place, comme la pochette par
     défaut des albums sur le site. */
  .cover-fallback { display: flex; align-items: center; justify-content: center; }
  .cover-fallback img { width: 62%; height: auto; display: block; opacity: .92; }
  h1 { font-size: 25px; font-weight: 800; letter-spacing: -.6px; margin: 18px 0 2px; }
  .artist { font-size: 16px; font-weight: 600; color: #D5DAE4; }
  .album { font-size: 13.5px; color: var(--muted); margin-top: 2px; }
  .muted { color: var(--muted); font-size: 13.5px; }
  .center { text-align: center; }

  .play {
    margin: 20px auto 6px; display: flex; align-items: center; justify-content: center;
    width: 78px; height: 78px; border-radius: 50%; border: none; cursor: pointer;
    background: var(--accent); color: #fff;
    box-shadow: 0 12px 28px rgba(108,123,255,.45);
    transition: transform .12s ease;
  }
  .play:active { transform: scale(.94); }
  .play svg { width: 34px; height: 34px; fill: currentColor; }
  .play.loading { opacity: .7; }

  /* Le titre en cours, quand le lien en porte plusieurs. */
  .now { text-align: center; margin-top: 2px; }
  .now .now-title { font-size: 15px; font-weight: 700; }
  .now .now-artist { font-size: 12.5px; color: var(--muted); }

  .bar {
    position: relative; height: 6px; border-radius: 999px; margin: 18px 0 6px;
    background: rgba(255,255,255,.12); cursor: pointer;
  }
  .bar .fill {
    position: absolute; inset: 0 auto 0 0; width: 0;
    border-radius: 999px; background: var(--accent);
  }
  .times { display: flex; justify-content: space-between; font-size: 12.5px; color: var(--muted); }

  /* Liste des titres d'un album ou d'un artiste partagé. */
  .tracks { margin-top: 18px; border-top: 1px solid var(--line); }
  .track {
    display: flex; align-items: center; gap: 12px; width: 100%;
    padding: 11px 4px; background: none; border: none; cursor: pointer;
    color: var(--fg); font: inherit; text-align: left;
    border-bottom: 1px solid rgba(255,255,255,.06);
  }
  .track .num {
    width: 22px; flex: 0 0 22px; text-align: center;
    font-size: 12.5px; color: var(--muted); font-variant-numeric: tabular-nums;
  }
  .track .meta { flex: 1 1 auto; min-width: 0; }
  .track .t {
    font-size: 14.5px; font-weight: 600;
    overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
  }
  .track .s {
    font-size: 12px; color: var(--muted);
    overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
  }
  .track .d { font-size: 12.5px; color: var(--muted); font-variant-numeric: tabular-nums; }
  .track.active .t, .track.active .num { color: var(--accent); }

  .note { margin-top: 16px; font-size: 13px; color: var(--muted); text-align: center; }
  .note b { color: #D5DAE4; font-weight: 700; }
  .gone { text-align: center; padding: 34px 20px; }
  .gone h1 { font-size: 22px; margin-bottom: 8px; }
  footer { margin-top: 22px; text-align: center; }
  footer a { color: var(--muted); font-size: 13px; text-decoration: none; }
</style>
</head>
<body>
<div class="wrap">
  <header class="top">
    <a class="brand" href="/">
      <img src="/logo_mark.png" alt="" width="27" height="38">
      <span>Gullify</span>
    </a>
    <span class="chip"><?= $share ? e($chip) : 'Lien expiré' ?></span>
  </header>

<?php if (!$share): ?>
  <div class="glass gone">
    <h1>Ce lien n'est plus valable</h1>
    <p class="muted">
      <?php if ($emptied): ?>
        La musique partagée n'est plus disponible. Demande un nouveau lien à la
        personne qui te l'a envoyé.
      <?php else: ?>
        Un partage s'écoute pendant <?= SongShare::TTL_HOURS ?> h, puis le lien
        s'efface. Demande-en un nouveau à la personne qui te l'a envoyé.
      <?php endif; ?>
    </p>
  </div>
<?php else: ?>
  <div class="glass pad">
    <?php if ($artwork !== ''): ?>
      <img class="cover" src="<?= e($artwork) ?>" alt="">
    <?php else: ?>
      <div class="cover cover-fallback"><img src="/logo_gullify_bo.png" alt=""></div>
    <?php endif; ?>

    <h1><?= e($title) ?></h1>
    <?php if ($artist !== ''): ?><div class="artist"><?= e($artist) ?></div><?php endif; ?>
    <?php if ($album !== ''): ?><div class="album"><?= e($album) ?></div><?php endif; ?>
    <?php if ($multi): ?>
      <div class="album">
        <?= count($playlist) ?> titres · <?= e(human_total($duration)) ?>
      </div>
    <?php endif; ?>

    <button class="play" id="play" aria-label="Écouter">
      <svg id="icon" viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>
    </button>
    <?php if ($multi): ?>
      <div class="now">
        <div class="now-title" id="nowTitle"><?= e($playlist[0]['title']) ?></div>
        <div class="now-artist" id="nowArtist"><?= e($playlist[0]['artist']) ?></div>
      </div>
    <?php endif; ?>
    <div class="center muted" id="hint">Appuie pour écouter</div>

    <div class="bar" id="bar"><div class="fill" id="fill"></div></div>
    <div class="times">
      <span id="cur">0:00</span>
      <span id="dur"><?= e(clock((int)$playlist[0]['dur'])) ?></span>
    </div>

    <?php if ($multi): ?>
      <div class="tracks" id="tracks">
        <?php foreach ($playlist as $i => $t): ?>
          <button class="track<?= $i === 0 ? ' active' : '' ?>" data-i="<?= $i ?>">
            <span class="num"><?= $i + 1 ?></span>
            <span class="meta">
              <span class="t"><?= e($t['title']) ?></span>
              <?php $sub = $kind === 'artist' ? $t['album'] : $t['artist']; ?>
              <?php if ($sub !== ''): ?><span class="s"><?= e($sub) ?></span><?php endif; ?>
            </span>
            <span class="d"><?= e(clock((int)$t['dur'])) ?></span>
          </button>
        <?php endforeach; ?>
      </div>
    <?php endif; ?>

    <div class="note">
      Ce lien s'efface dans <b id="left"><?= e(human_left($leftMs)) ?></b>.
    </div>
  </div>

  <audio id="audio" preload="none" src="<?= e($playlist[0]['src']) ?>"></audio>
<?php endif; ?>

  <footer><a href="/">Gullify</a></footer>
</div>

<?php if ($share): ?>
<script>
(function () {
  var TRACKS = <?= json_encode(
      $playlist,
      JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT | JSON_UNESCAPED_UNICODE
  ) ?>;

  var audio = document.getElementById('audio');
  var play  = document.getElementById('play');
  var icon  = document.getElementById('icon');
  var hint  = document.getElementById('hint');
  var bar   = document.getElementById('bar');
  var fill  = document.getElementById('fill');
  var cur   = document.getElementById('cur');
  var dur   = document.getElementById('dur');
  var left  = document.getElementById('left');
  var list  = document.getElementById('tracks');
  var nowTitle  = document.getElementById('nowTitle');
  var nowArtist = document.getElementById('nowArtist');
  var leftMs = <?= (int)$leftMs ?>;
  var index = 0;

  var PLAY  = 'M8 5v14l11-7z';
  var PAUSE = 'M6 5h4v14H6zM14 5h4v14h-4z';

  function fmt(s) {
    if (!isFinite(s) || s < 0) return '0:00';
    var m = Math.floor(s / 60);
    var r = Math.floor(s % 60);
    return m + ':' + (r < 10 ? '0' : '') + r;
  }

  /** Amène le titre `i` dans le lecteur (sans le lancer). */
  function select(i) {
    index = i;
    var t = TRACKS[i];
    audio.src = t.src;
    fill.style.width = '0';
    cur.textContent = '0:00';
    dur.textContent = t.dur > 0 ? fmt(t.dur) : '--:--';
    if (nowTitle) nowTitle.textContent = t.title;
    if (nowArtist) nowArtist.textContent = t.artist;
    if (list) {
      var rows = list.querySelectorAll('.track');
      for (var k = 0; k < rows.length; k++) {
        rows[k].classList.toggle('active', k === i);
      }
    }
  }

  /** Lance la lecture — la préparation côté serveur peut prendre un instant. */
  function start() {
    play.classList.add('loading');
    hint.textContent = 'Chargement…';
    audio.play().catch(function () {
      play.classList.remove('loading');
      hint.textContent = 'Lecture impossible sur cet appareil';
    });
  }

  play.addEventListener('click', function () {
    // La première lecture peut demander une préparation côté serveur (les
    // formats que le navigateur ne sait pas lire sont convertis) : on le dit
    // plutôt que de laisser le bouton muet.
    if (audio.paused) start(); else audio.pause();
  });

  if (list) {
    list.addEventListener('click', function (ev) {
      var row = ev.target.closest('.track');
      if (!row) return;
      var i = parseInt(row.getAttribute('data-i'), 10);
      if (isNaN(i)) return;
      // Retaper le titre en cours le remet au début, comme partout ailleurs.
      select(i);
      start();
    });
  }

  audio.addEventListener('playing', function () {
    play.classList.remove('loading');
    icon.firstElementChild.setAttribute('d', PAUSE);
    hint.textContent = '';
  });
  audio.addEventListener('pause', function () {
    icon.firstElementChild.setAttribute('d', PLAY);
    hint.textContent = 'En pause';
  });
  audio.addEventListener('ended', function () {
    // Album ou artiste : on enchaîne. Dernier titre (ou lien d'une seule
    // chanson) : on s'arrête là.
    if (index + 1 < TRACKS.length) { select(index + 1); start(); return; }
    icon.firstElementChild.setAttribute('d', PLAY);
    hint.textContent = 'Terminé';
  });
  audio.addEventListener('error', function () {
    play.classList.remove('loading');
    hint.textContent = 'La chanson n\'a pas pu être chargée';
  });
  audio.addEventListener('loadedmetadata', function () {
    if (isFinite(audio.duration)) dur.textContent = fmt(audio.duration);
  });
  audio.addEventListener('timeupdate', function () {
    var total = isFinite(audio.duration) && audio.duration > 0
      ? audio.duration
      : Math.max(1, TRACKS[index].dur);
    fill.style.width = Math.min(100, (audio.currentTime / total) * 100) + '%';
    cur.textContent = fmt(audio.currentTime);
  });

  bar.addEventListener('click', function (ev) {
    if (!isFinite(audio.duration) || audio.duration <= 0) return;
    var r = bar.getBoundingClientRect();
    audio.currentTime = ((ev.clientX - r.left) / r.width) * audio.duration;
  });

  // Compte à rebours : la page reste juste même laissée ouverte des heures.
  setInterval(function () {
    leftMs = Math.max(0, leftMs - 60000);
    if (leftMs === 0) { left.textContent = 'quelques instants'; return; }
    var min = Math.floor(leftMs / 60000);
    if (min < 60) { left.textContent = min + ' min'; return; }
    var h = Math.floor(min / 60), rest = min % 60;
    left.textContent = rest > 0 ? h + ' h ' + rest : h + ' h';
  }, 60000);
})();
</script>
<?php endif; ?>
</body>
</html>
