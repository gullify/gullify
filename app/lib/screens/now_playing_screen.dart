import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/favorites.dart';
import '../state/library.dart';
import '../state/player.dart';
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

    // Swipe vers le bas pour fermer le lecteur (en plus de la flèche).
    return Dismissible(
      key: const ValueKey('now-playing'),
      direction: DismissDirection.down,
      onDismissed: (_) => context.pop(),
      child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => context.pop(),
        ),
        title: Text(isRadio ? 'Radio' : 'En lecture'),
      ),
      body: SafeArea(
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
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
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
                      color: (state?.shuffleMode ??
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
                      switch (
                          state?.repeatMode ?? AudioServiceRepeatMode.none) {
                        AudioServiceRepeatMode.one => Icons.repeat_one,
                        _ => Icons.repeat,
                      },
                      color: (state?.repeatMode ??
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
                      : SingleChildScrollView(
                          controller: controller,
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            text,
                            style: const TextStyle(fontSize: 16, height: 1.6),
                          ),
                        ),
                );
              },
            ),
    ),
  );
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
          return ListView.builder(
            controller: controller,
            itemCount: queue.length,
            itemBuilder: (context, i) {
              final q = queue[i];
              final isCurrent = q.id == currentId;
              final scheme = Theme.of(context).colorScheme;
              return ListTile(
                leading: isCurrent
                    ? Icon(Icons.graphic_eq, color: scheme.primary)
                    : Text(
                        '${i + 1}',
                        style: TextStyle(color: scheme.onSurfaceVariant),
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
                onTap: () =>
                    ref.read(playerActionsProvider).skipToQueueItem(i),
              );
            },
          );
        },
      ),
    ),
  );
}
