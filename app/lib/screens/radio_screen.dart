import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/radio_repository.dart';
import '../state/player.dart';
import '../state/radio.dart';
import '../widgets/artwork.dart';

class RadioScreen extends ConsumerWidget {
  const RadioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stations = ref.watch(radioStationsProvider);
    final currentId = ref.watch(currentMediaItemProvider).value?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Radio')),
      body: stations.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('Aucune station'));
          }
          final sorted = [...list]
            ..sort((a, b) {
              if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
              return a.name.toLowerCase().compareTo(b.name.toLowerCase());
            });
          return RefreshIndicator(
            onRefresh: () => ref.refresh(radioStationsProvider.future),
            child: ListView.builder(
              itemCount: sorted.length,
              itemBuilder: (context, i) =>
                  _StationTile(station: sorted[i], currentId: currentId),
            ),
          );
        },
      ),
    );
  }
}

class _StationTile extends ConsumerWidget {
  const _StationTile({required this.station, required this.currentId});

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

    return ListTile(
      leading: Artwork(url: station.logo, size: 44, icon: Icons.radio),
      title: Text(
        station.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: isPlaying
            ? TextStyle(color: scheme.primary, fontWeight: FontWeight.w600)
            : null,
      ),
      subtitle: subtitle.isNotEmpty
          ? Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: IconButton(
        icon: Icon(
          station.favorite ? Icons.favorite : Icons.favorite_border,
          color: station.favorite ? scheme.primary : null,
        ),
        onPressed: () async {
          await ref.read(radioRepositoryProvider).toggleFavorite(station.id);
          ref.invalidate(radioStationsProvider);
        },
      ),
      onTap: () => ref.read(playerActionsProvider).playRadio(
            url: station.streamUrl,
            title: station.name,
            logo: station.logo,
          ),
    );
  }
}
