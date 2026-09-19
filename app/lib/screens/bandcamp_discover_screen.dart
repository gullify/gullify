import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/bandcamp_repository.dart';
import '../audio/audio_handler.dart';
import '../state/bandcamp.dart';
import '../state/player.dart';
import '../widgets/artwork.dart';
import '../widgets/bandcamp_download.dart';
import '../widgets/glass_box.dart';
import '../widgets/glass_kit.dart';
import '../widgets/mascot_empty.dart';
import 'shell_screen.dart';

/// « Découvrir sur Bandcamp » (idée #111) : un genre, puis l'un de ses
/// sous-genres, puis ses nouveautés, un tirage au hasard ou ses meilleures
/// ventes — et une liste de lecture qui passe par le lecteur principal, donc
/// aussi par la notification, Android Auto et la télé.
///
/// Trois écrans empilés plutôt qu'un seul qui changerait de contenu : « Retour »
/// remonte ainsi d'un cran, comme on s'y attend.

/// Dans l'adresse d'une liste, le « sous-genre » qui veut dire « tout le
/// genre ». Un nom de tag Bandcamp ne peut pas commencer par un tiret bas.
const kBcWholeGenre = '_';

/// Chemin de la liste d'un genre (ou d'un de ses sous-genres).
String bandcampListPath(String genre, [String subgenre = '']) =>
    '/bandcamp/$genre/${subgenre.isEmpty ? kBcWholeGenre : subgenre}';

/// Premier écran : les genres.
class BandcampGenresScreen extends ConsumerWidget {
  const BandcampGenresScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genres = ref.watch(bcGenresProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Découvrir sur Bandcamp')),
      bottomNavigationBar: const DetailDock(),
      body: genres.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Unreachable(
          onRetry: () => ref.invalidate(bcGenresProvider),
        ),
        data: (list) => list.isEmpty
            ? _Unreachable(onRetry: () => ref.invalidate(bcGenresProvider))
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  4,
                  16,
                  MediaQuery.paddingOf(context).bottom + 16,
                ),
                children: [
                  const _Intro(
                    'Choisis un genre, puis un sous-genre : Bandcamp en tire '
                    'une liste de lecture — ses nouveautés, un tirage au '
                    'hasard ou ses meilleures ventes.',
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, box) {
                      // Deux colonnes sur un téléphone, davantage sur une
                      // tablette : une pilule de genre n'a pas besoin de plus
                      // de 200 px.
                      final columns = (box.maxWidth / 200).floor().clamp(2, 5);
                      const gap = 10.0;
                      final width =
                          (box.maxWidth - gap * (columns - 1)) / columns;
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (final g in list)
                            SizedBox(
                              width: width,
                              child: _Pill(
                                label: g.name,
                                trailing: g.subgenres.isEmpty
                                    ? null
                                    : '${g.subgenres.length}',
                                onTap: () =>
                                    context.push('/bandcamp/${g.slug}'),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
      ),
    );
  }
}

/// Deuxième écran : les sous-genres d'un genre, « tout le genre » en tête.
class BandcampGenreScreen extends ConsumerWidget {
  const BandcampGenreScreen({super.key, required this.genre});

  /// Nom de tag du genre (« hip-hop-rap »).
  final String genre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final found = ref.watch(bcGenreProvider(genre));
    final name = found.value?.name ?? genre;
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      bottomNavigationBar: const DetailDock(),
      body: found.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Unreachable(
          onRetry: () => ref.invalidate(bcGenresProvider),
        ),
        data: (g) => ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            4,
            16,
            MediaQuery.paddingOf(context).bottom + 16,
          ),
          children: [
            _Pill(
              label: 'Tout $name',
              icon: Icons.all_inclusive,
              accent: true,
              onTap: () => context.push(bandcampListPath(genre)),
            ),
            if (g != null && g.subgenres.isNotEmpty) ...[
              const SectionTitle(
                'Sous-genres',
                padding: EdgeInsets.fromLTRB(4, 18, 4, 8),
              ),
              for (final sub in g.subgenres)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _Pill(
                    label: sub.name,
                    onTap: () =>
                        context.push(bandcampListPath(genre, sub.slug)),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Troisième écran : la liste de lecture, et le choix de ce qu'on y met.
class BandcampPlaylistScreen extends ConsumerStatefulWidget {
  const BandcampPlaylistScreen({
    super.key,
    required this.genre,
    this.subgenre = '',
  });

  final String genre;

  /// Vide = tout le genre.
  final String subgenre;

  @override
  ConsumerState<BandcampPlaylistScreen> createState() =>
      _BandcampPlaylistScreenState();
}

class _BandcampPlaylistScreenState
    extends ConsumerState<BandcampPlaylistScreen> {
  BcSlice _slice = BcSlice.fresh;

  BcDiscoverKey get _key =>
      (genre: widget.genre, subgenre: widget.subgenre, slice: _slice);

  Future<void> _play(List<BcTrack> tracks, {int startIndex = 0}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(playerActionsProvider).playBandcamp(
            tracks,
            ref.read(bandcampRepositoryProvider),
            startIndex: startIndex,
          );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Lecture impossible : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final genre = ref.watch(bcGenreProvider(widget.genre)).value;
    final genreName = genre?.name ?? widget.genre;
    final subName = widget.subgenre.isEmpty
        ? null
        : genre?.subgenres
                .where((s) => s.slug == widget.subgenre)
                .firstOrNull
                ?.name ??
            widget.subgenre;
    final page = ref.watch(bcDiscoverProvider(_key));
    final playing = ref.watch(currentMediaItemProvider).value;
    final playingId = playing?.extras?[kBandcampTrack] as String?;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subName ?? 'Tout $genreName'),
            if (subName != null)
              Text(
                genreName,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
      bottomNavigationBar: const DetailDock(),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<BcSlice>(
                showSelectedIcon: false,
                segments: [
                  for (final s in BcSlice.values)
                    ButtonSegment(value: s, label: Text(s.label)),
                ],
                selected: {_slice},
                onSelectionChanged: (v) => setState(() => _slice = v.first),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
            child: Text(
              _slice.hint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: page.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _Unreachable(
                onRetry: () => ref.invalidate(bcDiscoverProvider(_key)),
              ),
              data: (p) => p.tracks.isEmpty
                  ? MascotEmpty(
                      message: 'Rien à écouter ici',
                      hint: 'Bandcamp n\'a rien rendu pour ce choix.',
                      action: TextButton(
                        onPressed: () =>
                            ref.invalidate(bcDiscoverProvider(_key)),
                        child: const Text('Réessayer'),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () =>
                          ref.refresh(bcDiscoverProvider(_key).future),
                      child: ListView.builder(
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.paddingOf(context).bottom + 12,
                        ),
                        itemCount: p.tracks.length + 1,
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            return Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 6, 16, 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: AccentPlayButton(
                                      label: 'Lecture',
                                      onPressed: () => _play(p.tracks),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  GlassIconButton(
                                    icon: Icons.shuffle,
                                    tooltip: 'Lecture aléatoire',
                                    size: 50,
                                    onPressed: () =>
                                        _play(p.tracks.toList()..shuffle()),
                                  ),
                                  const SizedBox(width: 8),
                                  GlassIconButton(
                                    icon: Icons.refresh,
                                    tooltip: _slice == BcSlice.random
                                        ? 'Un autre tirage'
                                        : 'Actualiser',
                                    size: 50,
                                    onPressed: () => ref.invalidate(
                                      bcDiscoverProvider(_key),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          final t = p.tracks[i - 1];
                          return BandcampTrackTile(
                            track: t,
                            playing: playingId == t.previewId,
                            onTap: () => _play(p.tracks, startIndex: i - 1),
                            onDownload: () =>
                                downloadBandcampRelease(context, ref, t.release),
                          );
                        },
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rangée d'un titre trouvé sur Bandcamp : pochette, titre, artiste et album,
/// et de quoi télécharger l'album qui le contient.
class BandcampTrackTile extends StatelessWidget {
  const BandcampTrackTile({
    super.key,
    required this.track,
    required this.onTap,
    required this.onDownload,
    this.playing = false,
  });

  final BcTrack track;
  final VoidCallback onTap;
  final VoidCallback onDownload;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final details = [
      track.artist,
      if (track.album.isNotEmpty && track.album != track.title) track.album,
    ].join(' · ');
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.only(left: 16, right: 6),
      leading: Artwork(
        url: track.thumbnail.isEmpty ? null : track.thumbnail,
        size: 48,
        borderRadius: 8,
      ),
      title: Row(
        children: [
          if (playing) ...[
            EqBars(color: scheme.primary, height: 14),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: playing ? scheme.primary : null,
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(details, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: IconButton(
        tooltip: track.itemType == 't'
            ? 'Télécharger ce titre'
            : 'Télécharger l\'album',
        icon: const Icon(Icons.download_outlined),
        onPressed: onDownload,
      ),
    );
  }
}

/// Un genre ou un sous-genre à toucher.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.onTap,
    this.icon,
    this.trailing,
    this.accent = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final String? trailing;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassBox(
      radius: 16,
      blur: false,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: scheme.primary),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: accent ? scheme.primary : null,
                  ),
                ),
              ),
              if (trailing != null)
                Text(
                  trailing!,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            height: 1.3,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
}

/// Bandcamp (ou le serveur) n'a pas répondu.
class _Unreachable extends StatelessWidget {
  const _Unreachable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => MascotEmpty(
        message: 'Bandcamp ne répond pas',
        hint: 'Vérifie la connexion, ou réessaie dans un instant.',
        action: TextButton(onPressed: onRetry, child: const Text('Réessayer')),
      );
}
