import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/bandcamp_repository.dart';
import '../../state/bandcamp.dart';
import '../../state/player.dart';
import 'tv_kit.dart';

/// « Découvrir sur Bandcamp » à la télé (idée #111) : le même parcours que sur
/// le téléphone et dans la voiture — un genre, un sous-genre, puis nouveautés,
/// aléatoire ou populaires. Ici pas de liste à éplucher à la télécommande :
/// on choisit, ça joue, on passe à l'écran de lecture.

/// Les genres : une pilule chacun.
class TvBandcampPage extends ConsumerWidget {
  const TvBandcampPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genres = ref.watch(bcGenresProvider);
    return TvScaffold(
      title: 'Bandcamp',
      child: genres.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const _Unreachable(),
        data: (list) => list.isEmpty
            ? const _Unreachable()
            : _PillWall(
                intro: 'Choisis un genre : Bandcamp en tire une liste de '
                    'lecture — ses nouveautés, un tirage au hasard ou ses '
                    'meilleures ventes.',
                children: [
                  for (final (i, g) in list.indexed)
                    TvPill(
                      label: g.name,
                      accent: false,
                      autofocus: i == 0,
                      onPressed: () => context.push('/tv/bandcamp/${g.slug}'),
                    ),
                ],
              ),
      ),
    );
  }
}

/// Un genre : de quoi le lancer tout entier, puis ses sous-genres.
class TvBandcampGenreScreen extends ConsumerWidget {
  const TvBandcampGenreScreen({super.key, required this.genre});

  final String genre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final found = ref.watch(bcGenreProvider(genre));
    final name = found.value?.name ?? genre;
    return TvScaffold(
      title: name,
      child: found.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const _Unreachable(),
        data: (g) => ListView(
          padding: const EdgeInsets.all(tvFocusMargin),
          children: [
            TvSlicePills(genre: genre, label: 'tout $name', autofocus: true),
            if (g != null && g.subgenres.isNotEmpty) ...[
              const SizedBox(height: 40),
              const TvShelfLabel('Sous-genres'),
              const SizedBox(height: 18),
              Wrap(
                spacing: 20,
                runSpacing: 22,
                children: [
                  for (final sub in g.subgenres)
                    TvPill(
                      label: sub.name,
                      accent: false,
                      compact: true,
                      onPressed: () =>
                          context.push('/tv/bandcamp/$genre/${sub.slug}'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Un sous-genre : ses trois façons de s'écouter.
class TvBandcampSubgenreScreen extends ConsumerWidget {
  const TvBandcampSubgenreScreen({
    super.key,
    required this.genre,
    required this.subgenre,
  });

  final String genre;
  final String subgenre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(bcGenreProvider(genre)).value;
    final name =
        g?.subgenres.where((s) => s.slug == subgenre).firstOrNull?.name ??
        subgenre;
    return TvScaffold(
      title: name,
      child: ListView(
        padding: const EdgeInsets.all(tvFocusMargin),
        children: [
          if (g != null) ...[
            TvShelfLabel(g.name),
            const SizedBox(height: 18),
          ],
          TvSlicePills(
            genre: genre,
            subgenre: subgenre,
            label: name,
            autofocus: true,
          ),
        ],
      ),
    );
  }
}

/// Nouveautés / Aléatoire / Populaires : tire la liste, la joue, et ouvre
/// l'écran de lecture.
class TvSlicePills extends ConsumerStatefulWidget {
  const TvSlicePills({
    super.key,
    required this.genre,
    required this.label,
    this.subgenre = '',
    this.autofocus = false,
  });

  final String genre;
  final String subgenre;

  /// Ce qu'on écoute, pour le message d'échec.
  final String label;
  final bool autofocus;

  @override
  ConsumerState<TvSlicePills> createState() => _TvSlicePillsState();
}

class _TvSlicePillsState extends ConsumerState<TvSlicePills> {
  BcSlice? _busy;
  String? _error;

  Future<void> _play(BcSlice slice) async {
    if (_busy != null) return;
    setState(() {
      _busy = slice;
      _error = null;
    });
    try {
      final repo = ref.read(bandcampRepositoryProvider);
      // Toujours un tirage frais : c'est tout l'intérêt de « Aléatoire », et
      // les nouveautés d'il y a une heure ne sont plus tout à fait celles-là.
      final page = await repo.discover(
        genre: widget.genre,
        subgenre: widget.subgenre,
        slice: slice,
      );
      if (!mounted) return;
      if (page.tracks.isEmpty) {
        setState(() => _error = 'Rien à écouter dans « ${widget.label} ».');
        return;
      }
      await ref.read(playerActionsProvider).playBandcamp(page.tracks, repo);
      if (mounted) context.push('/tv/playing');
    } catch (e) {
      if (mounted) setState(() => _error = 'Bandcamp ne répond pas.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 20,
          runSpacing: 20,
          children: [
            for (final (i, slice) in BcSlice.values.indexed)
              TvPill(
                label: _busy == slice ? 'Chargement…' : slice.label,
                icon: switch (slice) {
                  BcSlice.fresh => Icons.new_releases_rounded,
                  BcSlice.random => Icons.shuffle_rounded,
                  BcSlice.top => Icons.trending_up_rounded,
                },
                accent: i == 0,
                autofocus: widget.autofocus && i == 0,
                onPressed: () => _play(slice),
              ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 18),
          Text(
            _error!,
            style: TextStyle(fontSize: tvMinText, color: scheme.error),
          ),
        ],
      ],
    );
  }
}

class _PillWall extends StatelessWidget {
  const _PillWall({required this.intro, required this.children});

  final String intro;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    // Marge de grossissement : une pilule visée grossit.
    padding: const EdgeInsets.all(tvFocusMargin),
    children: [
      Text(
        intro,
        style: TextStyle(
          fontSize: 24,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 30),
      Wrap(spacing: 20, runSpacing: 22, children: children),
    ],
  );
}

class _Unreachable extends StatelessWidget {
  const _Unreachable();

  @override
  Widget build(BuildContext context) => const TvEmpty(
    message: 'Bandcamp ne répond pas',
    hint: 'Vérifie la connexion du serveur, puis reviens ici.',
    icon: Icons.cloud_off_rounded,
  );
}
