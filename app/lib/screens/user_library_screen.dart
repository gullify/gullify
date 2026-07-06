import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/artist.dart';
import '../models/server_user.dart';
import '../state/library.dart';
import '../widgets/artwork.dart';

/// Bibliothèque d'un AUTRE utilisateur du serveur, ouverte depuis la
/// découverte (onglet Recherche). En-tête = photo + nom + volume du
/// catalogue, puis la liste de ses artistes. Un tap ouvre l'artiste via
/// la route habituelle `/artist/:id` (les détails et la lecture sont
/// indexés par id global — voir stream.php).
class UserLibraryScreen extends ConsumerWidget {
  const UserLibraryScreen({super.key, required this.user});

  final ServerUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(userLibraryProvider(user.username));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(user.displayName)),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(userLibraryProvider(user.username).future),
        child: artists.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 120),
              Center(child: Text('Erreur : $e')),
            ],
          ),
          data: (list) => ListView.builder(
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 18,
            ),
            itemCount: list.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) return _Header(user: user);
              final artist = list[i - 1];
              return _ArtistRow(artist: artist);
            },
          ),
        ),
      ),
      backgroundColor: scheme.surface,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.user});

  final ServerUser user;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final parts = [
      '${user.artistCount} artiste${user.artistCount > 1 ? 's' : ''}',
      '${user.albumCount} album${user.albumCount > 1 ? 's' : ''}',
      '${user.songCount} titre${user.songCount > 1 ? 's' : ''}',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x29000000),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Artwork(
              url: user.avatarUrl,
              size: 66,
              borderRadius: 33,
              icon: Icons.person,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  parts.join(' · '),
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Rangée d'artiste — identique au langage de la bibliothèque.
class _ArtistRow extends StatelessWidget {
  const _ArtistRow({required this.artist});

  final Artist artist;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => context.push('/artist/${artist.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        child: Row(
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x29000000),
                    blurRadius: 12,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Artwork(
                url: artist.imageUrl,
                size: 54,
                borderRadius: 27,
                icon: Icons.person,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${artist.albumCount} album'
                    '${artist.albumCount > 1 ? 's' : ''}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 24, color: Color(0xFFB6BAC1)),
          ],
        ),
      ),
    );
  }
}
