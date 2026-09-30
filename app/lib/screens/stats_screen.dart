import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/stats_repository.dart';
import '../state/library.dart';
import '../state/stats.dart';
import '../widgets/artwork.dart';
import '../widgets/stats_chart.dart';

/// Statistiques d'écoute : chiffres phares, activité (jour/heure/semaine),
/// genres et tops. Une seule série par graphique → teinte primaire du thème,
/// pas de légende; étiquettes sélectives (max + bornes d'axe).
///
/// Les graphiques eux-mêmes sont peints dans `widgets/stats_chart.dart`
/// (idée #120) : une courbe d'aire pour les trente jours, des histogrammes à
/// tête arrondie pour l'heure et le jour, une barre de parts pour les genres.
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
      ref.invalidate(popularSongsProvider);
      // Rechargement FORCÉ et attendu : garantit l'affichage à jour (une
      // simple invalidation pouvait laisser des chiffres périmés à l'écran).
      ref.invalidate(statsProvider);
      await ref.read(statsProvider.future);
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
                        // Trente jours, c'est une évolution : une courbe la
                        // raconte, trente barres la découpent.
                        trend: true,
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

/// Une carte de graphique : son titre, la valeur touchée (ou le total quand
/// rien ne l'est), puis le tracé.
class _ChartCard extends StatefulWidget {
  const _ChartCard({
    required this.title,
    required this.chart,
    this.trend = false,
    this.sparseLabels = false,
    this.labelEvery,
  });

  final String title;
  final StatsChart chart;

  /// Courbe d'aire au lieu d'un histogramme : pour une série qui AVANCE dans
  /// le temps (les trente derniers jours), pas pour des tranches qui
  /// reviennent (les heures, les jours de la semaine).
  final bool trend;

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
    final muted = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: scheme.onSurfaceVariant);
    // La valeur touchée s'écrit dans l'en-tête ; sans rien de touché, c'est
    // le total de la série — l'en-tête ne saute donc pas d'une ligne.
    final at = _selected;
    final reading = at != null && at < chart.data.length
        ? '${chart.labels[at]} · ${_plays(chart.data[at])}'
        : _plays(chart.data.fold(0, (sum, v) => sum + v));

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                Text(reading, style: muted),
              ],
            ),
            const SizedBox(height: 14),
            if (widget.trend)
              StatsTrendChart(
                data: chart.data,
                labels: chart.labels,
                selected: _selected,
                onSelected: (i) => setState(() => _selected = i),
                showsLabel: _axisLabel,
              )
            else
              StatsBarChart(
                data: chart.data,
                labels: chart.labels,
                selected: _selected,
                onSelected: (i) => setState(() => _selected = i),
                showsLabel: _axisLabel,
              ),
          ],
        ),
      ),
    );
  }

  String _plays(int n) => '$n écoute${n > 1 ? 's' : ''}';

  bool _axisLabel(int i) {
    if (widget.sparseLabels) {
      return i == 0 || i == widget.chart.labels.length - 1;
    }
    if (widget.labelEvery != null) return i % widget.labelEvery! == 0;
    return true;
  }
}

/// Les genres : une part-à-tout, donc UN tout que l'on découpe — une barre de
/// parts, puis la légende chiffrée.
///
/// Le serveur en renvoie jusqu'à quatorze, avec dix couleurs recyclées : deux
/// genres finissaient de la même teinte, et quatorze classes de couleur ne se
/// distinguent de toute façon plus à l'œil. Les six premiers gardent donc leur
/// teinte, le reste se replie sur « Autres » en gris (idée #120). Chaque
/// ligne de légende porte son compte et son pourcentage : rien ne se lit
/// par la seule couleur.
class _GenresCard extends StatelessWidget {
  const _GenresCard(this.genres);

  final List<StatsGenre> genres;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = genres.fold(0, (sum, g) => sum + g.count).clamp(1, 1 << 31);
    final named = genres.take(StatsShare.maxSlots).toList();
    final tail = genres
        .skip(StatsShare.maxSlots)
        .fold(0, (sum, g) => sum + g.count);
    final shares = [
      for (final (i, g) in named.indexed)
        StatsShare(label: g.label, value: g.count, slot: i),
      if (tail > 0)
        StatsShare(label: 'Autres', value: tail, slot: null),
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Genres',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${genres.length} genre${genres.length > 1 ? 's' : ''}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            StatsShareBar(shares: shares),
            const SizedBox(height: 14),
            for (final share in shares)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: share.color(scheme.brightness),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        share.label,
                        style: Theme.of(context).textTheme.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${share.value} · ${(share.value / total * 100).round()} %',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                  ],
                ),
              ),
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
