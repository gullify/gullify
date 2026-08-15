import 'dart:ui' show ImageFilter;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/song.dart';
import '../state/favorites.dart';
import '../state/player.dart';
import '../state/sleep_timer.dart';
import '../widgets/artwork.dart';
import '../widgets/chords_sheet.dart';
import '../widgets/lyrics_sheet.dart';
import '../widgets/retro_chrome.dart';
import '../widgets/retro_lcd.dart';
import '../widgets/share_sheet.dart';

class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(currentMediaItemProvider).value;
    if (item == null) {
      // Nothing playing (e.g. after stop) — leave the screen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && context.canPop()) context.pop();
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    final state = ref.watch(playbackStateProvider).value;
    final actions = ref.read(playerActionsProvider);
    final scheme = Theme.of(context).colorScheme;
    final isRadio = item.extras?['radio'] == true;
    final songId = item.extras?['songId'] as int?;
    final albumId = item.extras?['albumId'] as int?;
    final artistId = item.extras?['artistId'] as int?;

    // La pochette floutée remplit l'arrière-plan (design Liquid Glass).
    final light = scheme.brightness == Brightness.light;
    final artUrl = item.artUri?.toString();
    // Rétro Winamp (idée #82) : le lecteur devient un châssis. Barre de titre
    // hachurée, afficheur à segments, boutons de transport carrés — et pas de
    // pochette floutée derrière : une façade de 1999 est opaque (idée #83).
    final retro = isRetroSkin(context);

    // Swipe vers le bas pour fermer le lecteur (en plus de la flèche).
    return Dismissible(
      key: const ValueKey('now-playing'),
      direction: DismissDirection.down,
      onDismissed: (_) => context.pop(),
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: retro
            ? RetroTitleBar(
                title: isRadio ? 'Radio' : item.album ?? 'Gullify',
                onTitleTap: albumId == null
                    ? null
                    : () => _openDetail(context, '/album/$albumId'),
                onClose: () => context.pop(),
              )
            : AppBar(
                backgroundColor: Colors.transparent,
                leading: IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down, size: 32),
                  onPressed: () => context.pop(),
                ),
                centerTitle: true,
                title: Column(
                  children: [
                    Text(
                      isRadio ? 'RADIO' : 'EN LECTURE DEPUIS',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (item.album != null)
                      _DetailLink(
                        text: item.album!,
                        path: albumId == null ? null : '/album/$albumId',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Sous le rétro, rien de tout ça : le châssis gris est opaque, la
            // pochette floutée en filigrane appartient au verre.
            if (artUrl != null && !retro)
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                child: Artwork(url: artUrl, borderRadius: 0),
              ),
            if (!retro)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: light
                      ? const Color(0xD9FFFFFF)
                      : const Color(0xBF0A0C12),
                ),
              ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const Spacer(),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 340),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: retro
                              // La pochette est SERTIE dans une plaque de
                              // chrome (idée #85) : le cadre est en relief,
                              // la vitre en creux dessous. Pas d'ombre
                              // portée — un châssis ne flotte pas.
                              ? RetroBevel(
                                  gradient: winampChrome,
                                  padding: const EdgeInsets.all(7),
                                  child: RetroBevel(
                                    sunken: true,
                                    fill: winampLcd,
                                    padding: const EdgeInsets.all(2),
                                    child: Artwork(
                                      url: item.artUri?.toString(),
                                      borderRadius: 0,
                                      icon: isRadio
                                          ? Icons.radio
                                          : Icons.music_note,
                                    ),
                                  ),
                                )
                              : DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(28),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x59141932),
                                        blurRadius: 44,
                                        offset: Offset(0, 22),
                                      ),
                                    ],
                                  ),
                                  child: Artwork(
                                    url: item.artUri?.toString(),
                                    borderRadius: 28,
                                    icon: isRadio
                                        ? Icons.radio
                                        : Icons.music_note,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Rétro Winamp (idée #82) : l'afficheur du lecteur de 1999
                    // se glisse au-dessus du titre — temps à segments, cases
                    // creuses, voyants et analyseur de spectre.
                    if (retro) ...[
                      RetroLcd(item: item),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                // Sous le rétro, le titre reste écrit en
                                // clair sur la tôle (idée #85) : le vert est
                                // réservé à ce qui vit derrière une vitre —
                                // et l'afficheur juste au-dessus le dit déjà.
                                style: retro
                                    ? const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.2,
                                        color: Color(0xFFF2F2F7),
                                      )
                                    : const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.5,
                                      ),
                              ),
                              if (item.artist != null)
                                _DetailLink(
                                  text: item.artist!,
                                  path: artistId == null
                                      ? null
                                      : '/artist/$artistId',
                                  chevronSize: 18,
                                  style: retro
                                      ? lcdTextStyle(
                                          size: 18,
                                          color: const Color(0xFF8F8FA0),
                                        )
                                      : TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                ),
                            ],
                          ),
                        ),
                        if (songId != null) _FavoriteButton(songId: songId),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (!isRadio)
                      _Waveform(duration: item.duration, seed: item.title),
                    const SizedBox(height: 8),
                    if (retro)
                      _RetroControls(state: state, isRadio: isRadio)
                    else
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.shuffle,
                              color:
                                  (state?.shuffleMode ??
                                          AudioServiceShuffleMode.none) !=
                                      AudioServiceShuffleMode.none
                                  ? scheme.primary
                                  : null,
                            ),
                            onPressed: isRadio ? null : actions.toggleShuffle,
                          ),
                          IconButton(
                            iconSize: 40,
                            icon: const Icon(Icons.skip_previous),
                            onPressed: isRadio ? null : actions.previous,
                          ),
                          IconButton(
                            iconSize: 72,
                            icon: Icon(
                              (state?.playing ?? false)
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_fill,
                              color: scheme.primary,
                            ),
                            onPressed: actions.togglePlayPause,
                          ),
                          IconButton(
                            iconSize: 40,
                            icon: const Icon(Icons.skip_next),
                            onPressed: isRadio ? null : actions.next,
                          ),
                          IconButton(
                            icon: Icon(
                              switch (state?.repeatMode ??
                                  AudioServiceRepeatMode.none) {
                                AudioServiceRepeatMode.one => Icons.repeat_one,
                                _ => Icons.repeat,
                              },
                              color:
                                  (state?.repeatMode ??
                                          AudioServiceRepeatMode.none) !=
                                      AudioServiceRepeatMode.none
                                  ? scheme.primary
                                  : null,
                            ),
                            onPressed: isRadio ? null : actions.cycleRepeat,
                          ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if (!isRadio)
                          _actionPlate(
                            retro,
                            IconButton(
                              icon: const Icon(Icons.lyrics_outlined),
                              tooltip: 'Paroles',
                              onPressed: () => showLyricsSheet(
                                context,
                                item.extras?['filePath'] as String?,
                              ),
                            ),
                          ),
                        if (!isRadio)
                          _actionPlate(
                            retro,
                            IconButton(
                              icon: const ChordsIcon(),
                              tooltip: 'Accords guitare',
                              onPressed: () => showChordsSheet(
                                context,
                                item.extras?['filePath'] as String?,
                              ),
                            ),
                          ),
                        _actionPlate(retro, const _SleepTimerButton()),
                        if (!isRadio && songId != null)
                          _actionPlate(
                            retro,
                            IconButton(
                              icon: const Icon(Icons.ios_share_rounded),
                              tooltip: 'Partager',
                              onPressed: () => showShareSheet(
                                context,
                                ShareTarget.song(
                                  Song(
                                    id: songId,
                                    title: item.title,
                                    filePath:
                                        item.extras?['filePath'] as String? ??
                                        '',
                                    albumId: albumId,
                                    albumName: item.album,
                                    artistId: artistId,
                                    artistName: item.artist,
                                    artworkUrl: artUrl,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (!isRadio)
                          _actionPlate(
                            retro,
                            IconButton(
                              icon: const Icon(Icons.queue_music),
                              tooltip: "File d'attente",
                              onPressed: () => _showQueue(context),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Les actions secondaires du lecteur (paroles, accords, minuterie, partage,
/// file) prennent chacune leur case sous le rétro — des plaques plates, sans
/// relief : elles ne sont pas les commandes de transport (idée #85).
Widget _actionPlate(bool retro, Widget child) =>
    retro ? RetroPlate(child: child) : child;

/// Ouvre une page de détail depuis le lecteur plein écran : il se referme
/// d'abord, la destination s'ouvre au-dessus de la page d'où l'on vient
/// (mini-lecteur toujours là). On n'empile pas un écran sous le plein écran,
/// sinon la flèche « bas » du lecteur ramènerait à l'artiste.
void _openDetail(BuildContext context, String path) {
  final router = GoRouter.of(context);
  if (context.canPop()) router.pop();
  // Le lecteur a pu être ouvert depuis cette page même (album → lecture →
  // lecteur → « album ») : sa fermeture suffit, on n'empile pas un doublon.
  if (router.routerDelegate.currentConfiguration.uri.toString() == path) return;
  router.push(path);
}

/// Nom d'album ou d'artiste cliquable (idée #64) : chevron discret pour
/// signaler qu'on peut y aller, texte simple quand l'identifiant manque
/// (radio, pré-écoute YouTube, titre sans album connu).
class _DetailLink extends StatelessWidget {
  const _DetailLink({
    required this.text,
    required this.path,
    required this.style,
    this.chevronSize = 15,
  });

  final String text;
  final String? path;
  final TextStyle style;
  final double chevronSize;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    final destination = path;
    if (destination == null) return label;

    return InkWell(
      onTap: () => _openDetail(context, destination),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: label),
            Icon(Icons.chevron_right, size: chevronSize, color: style.color),
          ],
        ),
      ),
    );
  }
}

class _SleepTimerButton extends ConsumerWidget {
  const _SleepTimerButton();

  String _label(SleepTimerState t) {
    if (t.endOfTrack) return 'Fin du titre';
    final r = t.remaining;
    if (r == null) return '';
    final m = (r.inSeconds / 60).ceil();
    return '$m min';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = ref.watch(sleepTimerProvider);
    final scheme = Theme.of(context).colorScheme;

    return IconButton(
      tooltip: 'Minuterie de sommeil',
      icon: Badge(
        isLabelVisible: timer.active,
        label: Text(_label(timer)),
        child: Icon(
          timer.active ? Icons.bedtime : Icons.bedtime_outlined,
          color: timer.active ? scheme.primary : null,
        ),
      ),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        builder: (context) => Consumer(
          builder: (context, ref, _) {
            final t = ref.watch(sleepTimerProvider);
            final notifier = ref.read(sleepTimerProvider.notifier);
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text(
                      'Minuterie de sommeil',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: t.active
                        ? Text('Active · ${_label(t)}')
                        : const Text('La lecture se mettra en pause'),
                  ),
                  for (final minutes in [15, 30, 45, 60])
                    ListTile(
                      leading: const Icon(Icons.timer_outlined),
                      title: Text('$minutes minutes'),
                      onTap: () {
                        notifier.start(Duration(minutes: minutes));
                        Navigator.pop(context);
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.music_note_outlined),
                    title: const Text('À la fin du titre'),
                    onTap: () {
                      notifier.startEndOfTrack();
                      Navigator.pop(context);
                    },
                  ),
                  if (t.active)
                    ListTile(
                      leading: Icon(
                        Icons.close,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      title: const Text('Annuler la minuterie'),
                      onTap: () {
                        notifier.cancel();
                        Navigator.pop(context);
                      },
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FavoriteButton extends ConsumerWidget {
  const _FavoriteButton({required this.songId});

  final int songId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFavorite =
        ref.watch(favoriteIdsProvider).value?.contains(songId) ?? false;
    return IconButton(
      icon: Icon(
        isFavorite ? Icons.favorite : Icons.favorite_border,
        color: isFavorite ? Theme.of(context).colorScheme.primary : null,
      ),
      tooltip: 'Favori',
      onPressed: () => ref.read(favoriteIdsProvider.notifier).toggle(songId),
    );
  }
}

/// Les boutons de transport du châssis (idée #83) : des plaques carrées
/// gravées, serrées les unes contre les autres comme sur la façade d'origine,
/// à la place des ronds de Material. Les bascules (aléatoire, répétition)
/// restent enfoncées tant qu'elles sont actives — en 1999, un état se lisait
/// au relief, pas à la couleur.
class _RetroControls extends ConsumerWidget {
  const _RetroControls({required this.state, required this.isRadio});

  final PlaybackState? state;
  final bool isRadio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(playerActionsProvider);
    final playing = state?.playing ?? false;
    final shuffle =
        (state?.shuffleMode ?? AudioServiceShuffleMode.none) !=
        AudioServiceShuffleMode.none;
    final repeat = state?.repeatMode ?? AudioServiceRepeatMode.none;
    final repeating = repeat != AudioServiceRepeatMode.none;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        RetroButton(
          width: 38,
          height: 30,
          tooltip: 'Lecture aléatoire',
          active: shuffle,
          onPressed: isRadio ? null : actions.toggleShuffle,
          child: Icon(
            Icons.shuffle,
            size: 15,
            color: shuffle ? winampGreen : winampInk,
          ),
        ),
        const SizedBox(width: 8),
        RetroButton(
          width: 44,
          height: 36,
          tooltip: 'Titre précédent',
          onPressed: isRadio ? null : actions.previous,
          child: const RetroGlyph(RetroGlyphKind.previous, size: 11),
        ),
        RetroButton(
          width: 56,
          height: 36,
          tooltip: playing ? 'Pause' : 'Lecture',
          onPressed: actions.togglePlayPause,
          child: RetroGlyph(
            playing ? RetroGlyphKind.pause : RetroGlyphKind.play,
            size: 13,
          ),
        ),
        RetroButton(
          width: 44,
          height: 36,
          tooltip: 'Titre suivant',
          onPressed: isRadio ? null : actions.next,
          child: const RetroGlyph(RetroGlyphKind.next, size: 11),
        ),
        const SizedBox(width: 8),
        RetroButton(
          width: 38,
          height: 30,
          tooltip: 'Répétition',
          active: repeating,
          onPressed: isRadio ? null : actions.cycleRepeat,
          child: Icon(
            repeat == AudioServiceRepeatMode.one
                ? Icons.repeat_one
                : Icons.repeat,
            size: 15,
            color: repeating ? winampGreen : winampInk,
          ),
        ),
      ],
    );
  }
}

/// Scrubber « forme d'onde » du design : barres déterministes par titre,
/// portion écoulée en couleur accent, glisser/taper pour naviguer. Sous le
/// rétro (idée #83), la même prise devient la rainure et le bloc coulissant
/// du lecteur de 1999 — une onde dessinée n'existait pas encore.
class _Waveform extends ConsumerWidget {
  const _Waveform({required this.duration, required this.seed});

  final Duration? duration;
  final String seed;

  static const _barCount = 44;

  List<double> _bars() {
    // Pseudo-aléatoire stable : même chanson, même onde.
    var h = seed.hashCode;
    final bars = <double>[];
    for (var i = 0; i < _barCount; i++) {
      h = 0x1fffffff & (h * 31 + i * 2654435761);
      final v = (h % 1000) / 1000;
      bars.add(0.25 + 0.75 * v);
    }
    return bars;
  }

  void _seekTo(WidgetRef ref, double dx, double width) {
    final total = duration;
    if (total == null || total == Duration.zero) return;
    final fraction = (dx / width).clamp(0.0, 1.0);
    ref
        .read(playerActionsProvider)
        .seek(Duration(milliseconds: (total.inMilliseconds * fraction).round()));
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final total = duration ?? Duration.zero;
    final progress = total.inMilliseconds > 0
        ? (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final bars = _bars();
    final retro = isRetroSkin(context);
    // Les temps sont écrits sur la tôle, pas derrière la vitre (idée #85) :
    // gris, en VT323 — le phosphore est réservé à ce qui s'affiche.
    final labelStyle = retro
        ? lcdTextStyle(size: 15, color: const Color(0xFF8F8FA0))
        : TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          );

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) =>
                _seekTo(ref, d.localPosition.dx, constraints.maxWidth),
            onHorizontalDragUpdate: (d) =>
                _seekTo(ref, d.localPosition.dx, constraints.maxWidth),
            child: SizedBox(
              height: 56,
              // Rétro Winamp (idée #85) : la forme d'onde ne disparaît pas,
              // elle passe DERRIÈRE une vitre — barres carrées, phosphore
              // pour ce qui est joué, vert éteint pour la suite. Le geste de
              // navigation (taper, glisser) est le même qu'ailleurs.
              child: retro
                  ? RetroLcdPanel(
                      padding: const EdgeInsets.all(5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (final (i, h) in bars.indexed) ...[
                            Expanded(
                              child: ColoredBox(
                                color: (i + 0.5) / _barCount <= progress
                                    ? winampGreen
                                    : winampGreenDim,
                                child: SizedBox(height: 6 + 40 * h),
                              ),
                            ),
                            if (i < _barCount - 1) const SizedBox(width: 1),
                          ],
                        ],
                      ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final (i, h) in bars.indexed) ...[
                          Expanded(
                            child: Container(
                              height: 8 + 44 * h,
                              decoration: BoxDecoration(
                                color: (i + 0.5) / _barCount <= progress
                                    ? scheme.primary
                                    : scheme.onSurface.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                          if (i < _barCount - 1) const SizedBox(width: 2),
                        ],
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_fmt(position), style: labelStyle),
            Text(_fmt(total), style: labelStyle),
          ],
        ),
      ],
    );
  }
}

void _showQueue(BuildContext context) {
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (context, controller) => Consumer(
        builder: (context, ref, _) {
          final queue = ref.watch(queueProvider).value ?? [];
          final currentId = ref.watch(currentMediaItemProvider).value?.id;
          final actions = ref.read(playerActionsProvider);
          final scheme = Theme.of(context).colorScheme;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                child: Row(
                  children: [
                    Text(
                      "File d'attente · ${queue.length}",
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: queue.length > 1
                          ? () => actions.clearQueue()
                          : null,
                      icon: const Icon(Icons.clear_all, size: 18),
                      label: const Text('Vider'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  scrollController: controller,
                  itemCount: queue.length,
                  onReorderItem: (from, to) => actions.moveQueueItem(from, to),
                  itemBuilder: (context, i) {
                    final q = queue[i];
                    final isCurrent = q.id == currentId;
                    return Dismissible(
                      key: ValueKey('queue-$i-${q.id}'),
                      direction: isCurrent
                          ? DismissDirection.none
                          : DismissDirection.endToStart,
                      background: Container(
                        color: scheme.errorContainer,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: const Icon(Icons.close),
                      ),
                      onDismissed: (_) => actions.removeQueueItemAt(i),
                      child: ListTile(
                        leading: isCurrent
                            ? Icon(Icons.graphic_eq, color: scheme.primary)
                            : Text(
                                '${i + 1}',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                        title: Text(
                          q.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: isCurrent
                              ? TextStyle(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w600,
                                )
                              : null,
                        ),
                        subtitle: q.artist != null ? Text(q.artist!) : null,
                        trailing: ReorderableDragStartListener(
                          index: i,
                          child: Icon(Icons.drag_handle, color: scheme.outline),
                        ),
                        onTap: () => actions.skipToQueueItem(i),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
