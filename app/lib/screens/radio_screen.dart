import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/radio_repository.dart';
import '../state/player.dart';
import '../state/radio.dart';
import '../widgets/artwork.dart';

/// Onglet « Radio » : liste des web radios (lecture au tap, favoris).
class RadioScreen extends ConsumerWidget {
  const RadioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stations = ref.watch(radioStationsProvider);
    final currentId = ref.watch(currentMediaItemProvider).value?.id;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(radioStationsProvider.future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 18,
            ),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Text(
                  'Radio',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    height: 1.02,
                  ),
                ),
              ),
              ...stations.when(
                loading: () => const [
                  Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
                error: (e, _) => [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Center(child: Text('Erreur: $e')),
                  ),
                ],
                data: (list) {
                  if (list.isEmpty) {
                    return const [
                      Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: Text('Aucune station')),
                      ),
                    ];
                  }
                  final sorted = [...list]
                    ..sort((a, b) {
                      if (a.favorite != b.favorite) {
                        return a.favorite ? -1 : 1;
                      }
                      return a.name
                          .toLowerCase()
                          .compareTo(b.name.toLowerCase());
                    });
                  return [
                    for (final s in sorted)
                      _StationRow(station: s, currentId: currentId),
                  ];
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rangée de station : logo 46 r12, nom (accent si en cours), favori.
class _StationRow extends ConsumerWidget {
  const _StationRow({required this.station, required this.currentId});

  final RadioStation station;
  final String? currentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isPlaying = currentId == station.streamUrl;
    final subtitle = [
      if (station.country != null) station.country!,
      if (station.genres.isNotEmpty) station.genres.take(2).join(', '),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => ref.read(playerActionsProvider).playRadio(
              url: station.streamUrl,
              title: station.name,
              logo: station.logo,
            ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Row(
            children: [
              Artwork(
                url: station.logo,
                size: 46,
                borderRadius: 12,
                icon: Icons.radio,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      station.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: isPlaying ? scheme.primary : null,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Favori',
                icon: Icon(
                  station.favorite ? Icons.favorite : Icons.favorite_border,
                  color: station.favorite ? scheme.primary : scheme.outline,
                ),
                onPressed: () async {
                  await ref
                      .read(radioRepositoryProvider)
                      .toggleFavorite(station.id);
                  ref.invalidate(radioStationsProvider);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
