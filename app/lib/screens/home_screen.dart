import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/album.dart';
import '../state/auth.dart';
import '../state/library.dart';
import '../state/notifications.dart';
import '../state/player.dart';
import '../widgets/artwork.dart';
import '../widgets/glass_kit.dart';
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

    final hour = DateTime.now().hour;
    final greeting = hour >= 18 || hour < 5 ? 'Bonsoir' : 'Bonjour';

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () {
          ref.invalidate(popularSongsProvider);
          ref.invalidate(suggestionsProvider);
          return ref.refresh(recentAlbumsProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 0, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$greeting, ${auth.user?.fullName ?? auth.user?.username ?? ''}',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                          const Text(
                            'Gullify',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                              height: 1.02,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GlassIconButton(
                      icon: Icons.bar_chart,
                      tooltip: 'Statistiques',
                      size: 42,
                      onPressed: () => context.push('/stats'),
                    ),
                    const SizedBox(width: 8),
                    const _NotificationsButton(),
                    const SizedBox(width: 8),
                    GlassIconButton(
                      icon: Icons.settings_outlined,
                      tooltip: 'Paramètres',
                      size: 42,
                      onPressed: () => context.push('/settings'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
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
    return Badge(
      isLabelVisible: unread > 0,
      label: Text('$unread'),
      child: GlassIconButton(
        icon: Icons.notifications_outlined,
        tooltip: 'Notifications',
        size: 42,
        onPressed: () => context.push('/notifications'),
      ),
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
