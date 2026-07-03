import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/artist.dart';
import '../state/library.dart';
import '../widgets/alpha_grid.dart';
import '../widgets/artwork.dart';
import '../widgets/shuffle_library_button.dart';

class ArtistsTab extends ConsumerWidget {
  const ArtistsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(artistsProvider);

    return artists.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erreur: $e')),
      data: (list) => AlphaGrid<Artist>(
        items: list,
        nameOf: (a) => a.name,
        hintText: 'Filtrer les artistes…',
        trailing: const ShuffleLibraryButton(),
        maxCrossAxisExtent: 160,
        onRefresh: () => ref.refresh(artistsProvider.future),
        itemBuilder: (context, artist) => InkWell(
          onTap: () => context.push('/artist/${artist.id}'),
          borderRadius: BorderRadius.circular(100),
          child: Column(
            children: [
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Artwork(
                    url: artist.imageUrl,
                    borderRadius: 100,
                    icon: Icons.person,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                artist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                '${artist.albumCount} album${artist.albumCount > 1 ? 's' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
