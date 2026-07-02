import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/album.dart';
import '../state/auth.dart';
import '../state/library.dart';
import '../state/notifications.dart';
import '../state/player.dart';
import '../widgets/artwork.dart';
import '../widgets/song_menu.dart';
import '../widgets/song_tile.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final recent = ref.watch(recentAlbumsProvider);
    final popular = ref.watch(popularSongsProvider);
    final suggestions = ref.watch(suggestionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gullify'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Statistiques',
            onPressed: () => context.push('/stats'),
          ),
          const _NotificationsButton(),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Paramètres',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () {
          ref.invalidate(popularSongsProvider);
          ref.invalidate(suggestionsProvider);
          return ref.refresh(recentAlbumsProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Bonjour, ${auth.user?.fullName ?? auth.user?.username ?? ''}',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 24),
            Text(
              'Ajouts récents',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 190,
              child: recent.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Erreur: $e')),
                data: (albums) => albums.isEmpty
                    ? const Center(child: Text('Aucun album'))
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: albums.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, i) =>
                            _AlbumCard(album: albums[i]),
                      ),
              ),
            ),
            // Les plus écoutés — masqué tant qu'il n'y a pas d'historique.
            ...popular.maybeWhen(
              data: (songs) => songs.isEmpty
                  ? const <Widget>[]
                  : [
                      const SizedBox(height: 24),
                      Text(
                        'Les plus écoutés',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                      const SizedBox(height: 4),
                      for (final (i, song) in songs.take(5).indexed)
                        SongTile(
                          song: song,
                          onTap: () => ref
                              .read(playerActionsProvider)
                              .playSongs(songs, startIndex: i),
                          onLongPress: () => showSongMenu(context, song),
                        ),
                    ],
              orElse: () => const <Widget>[],
            ),
            // Suggestions par genre — masqué si le serveur n'en a pas.
            ...suggestions.maybeWhen(
              data: (s) => s.albums.isEmpty
                  ? const <Widget>[]
                  : [
                      const SizedBox(height: 24),
                      Text(
                        s.genre != null
                            ? 'Suggestions · ${s.genre}'
                            : 'Suggestions',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 190,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: s.albums.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(width: 12),
                          itemBuilder: (context, i) =>
                              _AlbumCard(album: s.albums[i]),
                        ),
                      ),
                    ],
              orElse: () => const <Widget>[],
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationsButton extends ConsumerWidget {
  const _NotificationsButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(notificationsProvider).value?.unread ?? 0;
    return IconButton(
      tooltip: 'Notifications',
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text('$unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
      onPressed: () => context.push('/notifications'),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album});

  final Album album;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/album/${album.id}'),
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Artwork(url: album.artworkUrl, size: 140),
            const SizedBox(height: 8),
            Text(
              album.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (album.artistName != null)
              Text(
                album.artistName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
