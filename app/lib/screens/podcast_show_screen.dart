import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/podcasts_repository.dart';
import '../audio/audio_handler.dart';
import '../state/player.dart';
import '../state/podcasts.dart';
import '../widgets/album_card.dart' show kArtShadow;
import '../widgets/artwork.dart';
import '../widgets/glass_kit.dart';
import '../widgets/mascot_empty.dart';
import 'podcasts_screen.dart' show PodcastSubscribeButton;
import 'shell_screen.dart';

/// La fiche d'une série de podcast (idée #112) : sa pochette, sa présentation,
/// et ses épisodes — comme une page d'artiste.
///
/// Lancer un épisode pose toute la liste en file : « suivant » descend donc
/// vers les épisodes plus anciens, exactement ce que l'on voit à l'écran. Et
/// l'on reprend chaque épisode là où on l'avait laissé.
class PodcastShowScreen extends ConsumerWidget {
  const PodcastShowScreen({super.key, required this.feedUrl, this.known});

  /// L'adresse du flux : l'identité de la série.
  final String feedUrl;

  /// La fiche déjà connue (venue de la liste d'où l'on arrive) : elle évite un
  /// écran vide le temps que le flux soit lu.
  final PodcastShow? known;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(podcastFeedProvider(feedUrl));
    final show = feed.value?.show ?? known;
    final playing = ref.watch(currentMediaItemProvider).value;
    final playingGuid = playing?.extras?[kPodcastEpisode] as String?;
    final playingFeed = playing?.extras?[kPodcastFeed] as String?;

    return Scaffold(
      appBar: AppBar(title: Text(show?.title ?? 'Podcast')),
      bottomNavigationBar: const DetailDock(),
      body: feed.when(
        loading: () => _Head(
          feedUrl: feedUrl,
          show: show,
          episodes: const [],
          child: const Padding(
            padding: EdgeInsets.all(28),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
        error: (e, _) => MascotEmpty(
          message: 'Ce flux ne répond pas',
          hint: 'Le podcast est peut-être hors ligne. Réessaie dans un '
              'instant.',
          action: TextButton(
            onPressed: () => ref.invalidate(podcastFeedProvider(feedUrl)),
            child: const Text('Réessayer'),
          ),
        ),
        data: (data) => RefreshIndicator(
          onRefresh: () => ref.refresh(podcastFeedProvider(feedUrl).future),
          child: _Head(
            feedUrl: feedUrl,
            show: data.show,
            episodes: data.episodes,
            playingGuid: playingFeed == feedUrl ? playingGuid : null,
          ),
        ),
      ),
    );
  }
}

/// L'en-tête de la série, puis ses épisodes (ou ce qu'on met à leur place le
/// temps du chargement).
class _Head extends ConsumerWidget {
  const _Head({
    required this.feedUrl,
    required this.show,
    required this.episodes,
    this.child,
    this.playingGuid,
  });

  final String feedUrl;
  final PodcastShow? show;
  final List<PodcastEpisode> episodes;
  final Widget? child;
  final String? playingGuid;

  Future<void> _play(
    BuildContext context,
    WidgetRef ref, {
    int startIndex = 0,
  }) async {
    final series = show;
    if (series == null || episodes.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(audioHandlerProvider).playPodcast(
            episodes,
            feedUrl: feedUrl,
            showTitle: series.title,
            showImage: series.image,
            startIndex: startIndex,
          );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Lecture impossible : $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final series = show;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + 16,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [kArtShadow],
                ),
                child: Artwork(
                  url: (series?.image ?? '').isEmpty ? null : series!.image,
                  size: 112,
                  borderRadius: 18,
                  icon: Icons.podcasts,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      series?.title ?? '',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    if ((series?.author ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        series!.author,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    if (series != null)
                      PodcastSubscribeButton(show: series, wide: true),
                  ],
                ),
              ),
            ],
          ),
        ),
        if ((series?.description ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
            child: _Description(text: series!.description),
          ),
        if (episodes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: AccentPlayButton(
                    label: 'Dernier épisode',
                    onPressed: () => _play(context, ref),
                  ),
                ),
                const SizedBox(width: 12),
                GlassIconButton(
                  icon: Icons.refresh,
                  tooltip: 'Actualiser le flux',
                  size: 50,
                  onPressed: () =>
                      ref.invalidate(podcastFeedProvider(feedUrl)),
                ),
              ],
            ),
          ),
        ?child,
        if (episodes.isNotEmpty) ...[
          SectionTitle(
            '${episodes.length} épisode${episodes.length > 1 ? 's' : ''}',
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          ),
          for (var i = 0; i < episodes.length; i++)
            PodcastEpisodeTile(
              episode: episodes[i],
              playing: playingGuid != null && playingGuid == episodes[i].guid,
              onTap: () => _play(context, ref, startIndex: i),
            ),
        ] else if (child == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: MascotEmpty(
              message: 'Aucun épisode',
              hint: 'Ce flux n\'en publie aucun pour le moment.',
            ),
          ),
      ],
    );
  }
}

/// La présentation de la série : trois lignes, dépliables d'un toucher.
class _Description extends StatefulWidget {
  const _Description({required this.text});

  final String text;

  @override
  State<_Description> createState() => _DescriptionState();
}

class _DescriptionState extends State<_Description> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => setState(() => _open = !_open),
        child: Text(
          widget.text,
          maxLines: _open ? null : 3,
          overflow: _open ? TextOverflow.visible : TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            height: 1.35,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
}

/// Rangée d'un épisode : date, durée, et où l'on en est.
class PodcastEpisodeTile extends StatelessWidget {
  const PodcastEpisodeTile({
    super.key,
    required this.episode,
    required this.onTap,
    this.playing = false,
  });

  final PodcastEpisode episode;
  final VoidCallback onTap;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = episode.progress;
    final details = [
      if (episode.published != null) formatEpisodeDate(episode.published!),
      if (episode.duration > 0) formatEpisodeDuration(episode.duration),
      if (episode.completed)
        'Écouté'
      else if (episode.resumable)
        'Reste ${formatEpisodeDuration(episode.duration - episode.position)}',
    ].join(' · ');

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      leading: Artwork(
        url: episode.image.isEmpty ? null : episode.image,
        size: 48,
        borderRadius: 10,
        icon: Icons.podcasts,
      ),
      title: Row(
        children: [
          if (playing) ...[
            EqBars(color: scheme.primary, height: 14),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              episode.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: playing ? scheme.primary : null,
              ),
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            details,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          if (progress != null && progress > 0) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: scheme.onSurface.withValues(alpha: 0.12),
              ),
            ),
          ],
        ],
      ),
      trailing: Icon(
        episode.resumable ? Icons.play_circle_outline : Icons.play_arrow,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}

/// « 23 sept. 2026 » — la date d'un épisode, telle qu'on la lit.
String formatEpisodeDate(DateTime date) {
  const months = [
    'janv.',
    'févr.',
    'mars',
    'avr.',
    'mai',
    'juin',
    'juill.',
    'août',
    'sept.',
    'oct.',
    'nov.',
    'déc.',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

/// « 1 h 32 » ou « 25 min » — la durée d'un épisode, arrondie comme on la dit.
String formatEpisodeDuration(int seconds) {
  if (seconds <= 0) return '';
  final minutes = (seconds / 60).round();
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours h' : '$hours h ${rest.toString().padLeft(2, '0')}';
}
