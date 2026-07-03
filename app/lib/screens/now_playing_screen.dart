import 'dart:ui' show ImageFilter;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/favorites.dart';
import '../state/library.dart';
import '../state/player.dart';
import '../state/sleep_timer.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/song_tile.dart';

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

    // Thème verre : la pochette floutée remplit l'arrière-plan du lecteur.
    final frosted =
        Theme.of(context).extension<GullifySurfaces>()?.frosted ?? false;
    final artUrl = item.artUri?.toString();

    // Swipe vers le bas pour fermer le lecteur (en plus de la flèche).
    return Dismissible(
      key: const ValueKey('now-playing'),
      direction: DismissDirection.down,
      onDismissed: (_) => context.pop(),
      child: Scaffold(
        extendBodyBehindAppBar: frosted,
        appBar: AppBar(
          backgroundColor: frosted ? Colors.transparent : null,
          leading: IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: () => context.pop(),
          ),
          title: Text(isRadio ? 'Radio' : 'En lecture'),
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (frosted && artUrl != null)
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                child: Artwork(url: artUrl, borderRadius: 0),
              ),
            if (frosted && artUrl != null)
              const DecoratedBox(
                decoration: BoxDecoration(color: Color(0x990A0F1A)),
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
                          child: Artwork(
                            url: item.artUri?.toString(),
                            borderRadius: 16,
                            icon: isRadio ? Icons.radio : Icons.music_note,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (item.artist != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.artist!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (!isRadio) _SeekBar(duration: item.duration),
                    const SizedBox(height: 8),
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
                        if (songId != null) _FavoriteButton(songId: songId),
                        if (!isRadio)
                          IconButton(
                            icon: const Icon(Icons.lyrics_outlined),
                            tooltip: 'Paroles',
                            onPressed: () => _showLyrics(context, ref, item),
                          ),
                        const _SleepTimerButton(),
                        if (!isRadio)
                          IconButton(
                            icon: const Icon(Icons.queue_music),
                            tooltip: "File d'attente",
                            onPressed: () => _showQueue(context),
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

class _SeekBar extends ConsumerWidget {
  const _SeekBar({this.duration});

  final Duration? duration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final total = duration ?? Duration.zero;
    final max = total.inMilliseconds.toDouble();
    final value = position.inMilliseconds.clamp(0, total.inMilliseconds);

    return Column(
      children: [
        Slider(
          max: max > 0 ? max : 1,
          value: value.toDouble(),
          onChanged: max > 0
              ? (v) => ref
                    .read(playerActionsProvider)
                    .seek(Duration(milliseconds: v.round()))
              : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatDuration(position.inSeconds),
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                formatDuration(total.inSeconds),
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

void _showLyrics(BuildContext context, WidgetRef ref, MediaItem item) {
  final filePath = item.extras?['filePath'] as String?;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (context, controller) => filePath == null
          ? const Center(child: Text('Paroles indisponibles'))
          : Consumer(
              builder: (context, ref, _) {
                final lyrics = ref.watch(lyricsProvider(filePath));
                return lyrics.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Erreur: $e')),
                  data: (text) => text == null
                      ? const Center(child: Text('Aucunes paroles trouvées'))
                      : _LyricsView(text: text, controller: controller),
                );
              },
            ),
    ),
  );
}

class _LrcLine {
  const _LrcLine(this.time, this.text);

  final Duration time;
  final String text;
}

/// Paroles : défilement synchronisé si le texte est au format LRC
/// (`[mm:ss.xx] ligne`), sinon affichage statique.
class _LyricsView extends ConsumerStatefulWidget {
  const _LyricsView({required this.text, required this.controller});

  final String text;
  final ScrollController controller;

  @override
  ConsumerState<_LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<_LyricsView> {
  static final _lrcPattern = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\]\s*(.*)');
  static const _lineExtent = 44.0;

  late final List<_LrcLine> _lines = _parse(widget.text);
  int _lastIndex = -1;

  List<_LrcLine> _parse(String text) {
    final lines = <_LrcLine>[];
    for (final raw in text.split('\n')) {
      final m = _lrcPattern.firstMatch(raw.trim());
      if (m == null) continue;
      final content = m.group(3)!.trim();
      if (content.isEmpty) continue;
      lines.add(
        _LrcLine(
          Duration(
            minutes: int.parse(m.group(1)!),
            milliseconds: (double.parse(m.group(2)!) * 1000).round(),
          ),
          content,
        ),
      );
    }
    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }

  int _indexFor(Duration position) {
    var index = -1;
    for (var i = 0; i < _lines.length; i++) {
      if (_lines[i].time <= position) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }

  @override
  Widget build(BuildContext context) {
    // Moins de 4 lignes horodatées : traite comme des paroles simples.
    if (_lines.length < 4) {
      return SingleChildScrollView(
        controller: widget.controller,
        padding: const EdgeInsets.all(24),
        child: Text(
          widget.text,
          style: const TextStyle(fontSize: 16, height: 1.6),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final current = _indexFor(position);

    if (current != _lastIndex && widget.controller.hasClients) {
      _lastIndex = current;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!widget.controller.hasClients) return;
        final viewport = widget.controller.position.viewportDimension;
        final target = (current * _lineExtent - viewport / 2 + _lineExtent)
            .clamp(0.0, widget.controller.position.maxScrollExtent);
        widget.controller.animateTo(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }

    return ListView.builder(
      controller: widget.controller,
      itemExtent: _lineExtent,
      padding: const EdgeInsets.symmetric(vertical: 120, horizontal: 24),
      itemCount: _lines.length,
      itemBuilder: (context, i) {
        final isCurrent = i == current;
        return InkWell(
          onTap: () => ref.read(playerActionsProvider).seek(_lines[i].time),
          child: Center(
            child: Text(
              _lines[i].text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isCurrent ? 18 : 15,
                height: 1.3,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                color: isCurrent ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      },
    );
  }
}

void _showQueue(BuildContext context) {
  showModalBottomSheet(
    context: context,
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
