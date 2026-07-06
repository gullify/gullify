import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/stats_repository.dart';
import '../state/library.dart';
import '../state/stats.dart';
import '../widgets/artwork.dart';

/// Statistiques d'écoute : chiffres phares, activité (jour/heure/semaine),
/// genres et tops. Une seule série par graphique → teinte primaire du thème,
/// pas de légende; étiquettes sélectives (max + bornes d'axe).
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Réinitialiser les statistiques ?'),
        content: const Text(
          'Tout ton historique d\'écoute et tes compteurs seront effacés. '
          'Les titres, albums et favoris ne sont pas touchés. Irréversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Réinitialiser'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(statsRepositoryProvider).reset();
      ref.invalidate(statsProvider);
      ref.invalidate(popularSongsProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('Statistiques réinitialisées')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Échec : $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistiques'),
        actions: [
          IconButton(
            tooltip: 'Réinitialiser',
            icon: const Icon(Icons.restart_alt),
            onPressed: () => _confirmReset(context, ref),
          ),
        ],
      ),
      body: stats.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (s) => !s.hasPlays
            ? const Center(
                child: Text('Écoutez de la musique pour voir vos statistiques'),
              )
            : RefreshIndicator(
                onRefresh: () => ref.refresh(statsProvider.future),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _StatTiles(s.general),
                    const SizedBox(height: 24),
                    if (!s.dailyPlays.isEmpty) ...[
                      _ChartCard(
                        title: '30 derniers jours',
                        chart: s.dailyPlays,
                        sparseLabels: true,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (!s.hourly.isEmpty) ...[
                      _ChartCard(
                        title: 'Par heure',
                        chart: s.hourly,
                        labelEvery: 6,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (!s.weekday.isEmpty) ...[
                      _ChartCard(title: 'Par jour', chart: s.weekday),
                      const SizedBox(height: 16),
                    ],
                    if (s.genres.isNotEmpty) ...[
                      _GenresCard(s.genres),
                      const SizedBox(height: 16),
                    ],
                    if (s.topSongs.isNotEmpty)
                      _TopSection(
                        title: 'Top titres',
                        children: [
                          for (final (i, t) in s.topSongs.take(5).indexed)
                            _TopTile(
                              rank: i + 1,
                              title: t.title,
                              subtitle: t.artistName,
                              artworkUrl: t.artworkUrl,
                              playCount: t.playCount,
                              onTap: () => context.push('/album/${t.albumId}'),
                            ),
                        ],
                      ),
                    if (s.topArtists.isNotEmpty)
                      _TopSection(
                        title: 'Top artistes',
                        children: [
                          for (final (i, a) in s.topArtists.take(5).indexed)
                            _TopTile(
                              rank: i + 1,
                              title: a.name,
                              artworkUrl: a.imageUrl,
                              round: true,
                              playCount: a.playCount,
                              onTap: () => context.push('/artist/${a.id}'),
                            ),
                        ],
                      ),
                    if (s.topAlbums.isNotEmpty)
                      _TopSection(
                        title: 'Top albums',
                        children: [
                          for (final (i, a) in s.topAlbums.take(5).indexed)
                            _TopTile(
                              rank: i + 1,
                              title: a.name,
                              subtitle: a.artistName,
                              artworkUrl: a.artworkUrl,
                              playCount: a.playCount,
                              onTap: () => context.push('/album/${a.id}'),
                            ),
                        ],
                      ),
                    if (s.recentPlays.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
                        child: Text(
                          'Historique récent',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      for (final p in s.recentPlays)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Artwork(url: p.artworkUrl, size: 44),
                          title: Text(
                            p.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            p.artistName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text(
                            relativeTime(p.playedAt),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                          onTap: p.albumId > 0
                              ? () => context.push('/album/${p.albumId}')
                              : null,
                        ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

/// « il y a X » — partagé avec l'écran d'accueil (Derniers joués).
String relativeTime(DateTime? t) {
  if (t == null) return '';
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return "à l'instant";
  if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
  if (diff.inDays < 7) return 'il y a ${diff.inDays} j';
  return '${t.day}/${t.month}';
}

class _StatTiles extends StatelessWidget {
  const _StatTiles(this.g);

  final StatsGeneral g;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      ('Écoutes', '${g.totalPlays}'),
      ("Temps d'écoute", g.totalListenTimeFormatted),
      ('Titres uniques', '${g.uniqueSongsPlayed}'),
      ('Complétion', '${g.completionRate} %'),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.9,
      children: [
        for (final (label, value) in tiles)
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    child: Text(
                      value,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ChartCard extends StatefulWidget {
  const _ChartCard({
    required this.title,
    required this.chart,
    this.sparseLabels = false,
    this.labelEvery,
  });

  final String title;
  final StatsChart chart;

  /// N'affiche que la première et la dernière étiquette d'axe.
  final bool sparseLabels;

  /// Affiche une étiquette toutes les N barres.
  final int? labelEvery;

  @override
  State<_ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends State<_ChartCard> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final chart = widget.chart;
    final scheme = Theme.of(context).colorScheme;
    final maxValue =
        chart.data.reduce((a, b) => a > b ? a : b).clamp(1, 1 << 31);
    final maxIndex = chart.data.indexOf(maxValue);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                // « Tooltip » mobile : la barre touchée s'affiche ici.
                if (_selected != null && _selected! < chart.labels.length)
                  Text(
                    '${chart.labels[_selected!]} · '
                    '${chart.data[_selected!]} écoute'
                    '${chart.data[_selected!] > 1 ? 's' : ''}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 96,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final (i, v) in chart.data.indexed)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(
                          () => _selected = _selected == i ? null : i,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (i == maxIndex && v > 0)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  '$v',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              ),
                            Container(
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 1),
                              height: (v / maxValue * 72).clamp(2, 72),
                              decoration: BoxDecoration(
                                color: _selected == i
                                    ? scheme.primary
                                    : v == 0
                                        ? scheme.surfaceContainerHighest
                                        : scheme.primary
                                            .withValues(alpha: 0.75),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Divider(height: 8, thickness: 1, color: scheme.outlineVariant),
            Row(
              children: [
                for (final (i, label) in chart.labels.indexed)
                  Expanded(
                    child: _axisLabel(i, label)
                        ? Text(
                            label,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                            overflow: TextOverflow.visible,
                            softWrap: false,
                          )
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _axisLabel(int i, String label) {
    if (widget.sparseLabels) {
      return i == 0 || i == widget.chart.labels.length - 1;
    }
    if (widget.labelEvery != null) return i % widget.labelEvery! == 0;
    return true;
  }
}

class _GenresCard extends StatelessWidget {
  const _GenresCard(this.genres);

  final List<StatsGenre> genres;

  Color _parse(String hex, Color fallback) {
    final h = hex.replaceFirst('#', '');
    if (h.length != 6) return fallback;
    final v = int.tryParse(h, radix: 16);
    return v == null ? fallback : Color(0xFF000000 | v);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = genres.fold(0, (sum, g) => sum + g.count).clamp(1, 1 << 31);
    final maxCount =
        genres.map((g) => g.count).reduce((a, b) => a > b ? a : b).clamp(1, 1 << 31);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Genres',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            for (final g in genres) ...[
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _parse(g.color, scheme.primary),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      g.label,
                      style: Theme.of(context).textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${(g.count / total * 100).round()} %',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 8),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: (g.count / maxCount).clamp(0.02, 1),
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: _parse(g.color, scheme.primary)
                          .withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TopSection extends StatelessWidget {
  const _TopSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        ...children,
      ],
    );
  }
}

class _TopTile extends StatelessWidget {
  const _TopTile({
    required this.rank,
    required this.title,
    this.subtitle,
    required this.artworkUrl,
    required this.playCount,
    this.round = false,
    this.onTap,
  });

  final int rank;
  final String title;
  final String? subtitle;
  final String artworkUrl;
  final int playCount;
  final bool round;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            child: Text(
              '$rank',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(width: 4),
          Artwork(
            url: artworkUrl,
            size: 44,
            borderRadius: round ? 22 : 6,
            icon: round ? Icons.person : Icons.album,
          ),
        ],
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle != null
          ? Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: Text(
        '$playCount',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
      onTap: onTap,
    );
  }
}
