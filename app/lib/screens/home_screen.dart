import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/stats_repository.dart';
import '../models/album.dart';
import '../state/auth.dart';
import '../state/library.dart';
import '../state/notifications.dart';
import '../state/player.dart';
import '../state/stats.dart';
import '../widgets/album_card.dart';
import '../widgets/artwork.dart';
import '../widgets/glass_box.dart';
import '../widgets/glass_kit.dart';
import '../widgets/song_menu.dart';
import '../widgets/song_tile.dart';
import 'stats_screen.dart' show relativeTime;

/// Onglet « Accueil » : salutation + boutons de verre, « Nouveautés »
/// (albums récents + lecture aléatoire), « Les plus populaires » (top 5)
/// et « Derniers joués » (historique récent des statistiques).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final recent = ref.watch(recentAlbumsProvider);
    final popular = ref.watch(popularSongsProvider);
    final stats = ref.watch(statsProvider);
    final scheme = Theme.of(context).colorScheme;

    final hour = DateTime.now().hour;
    final greeting = hour >= 18 || hour < 5 ? 'Bonsoir' : 'Bonjour';
    final userName = auth.user?.fullName ?? auth.user?.username;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () {
            ref.invalidate(popularSongsProvider);
            ref.invalidate(statsProvider);
            return ref.refresh(recentAlbumsProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 18,
            ),
            children: [
              // En-tête : salutation + « Accueil » + boutons de verre 42.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userName == null
                                ? greeting
                                : '$greeting, $userName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const Text(
                            'Accueil',
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
                      icon: Icons.person_outlined,
                      tooltip: 'Paramètres',
                      size: 42,
                      onPressed: () => context.push('/settings'),
                    ),
                  ],
                ),
              ),
              // Recherche rapide : mène à l'onglet Recherche (local + YouTube).
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                child: GlassBox(
                  radius: 16,
                  blur: false,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      ref.read(searchFocusRequestProvider.notifier).request();
                      context.go('/search');
                    },
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                      child: Row(
                        children: [
                          Icon(Icons.search, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Rechercher — ici ou sur YouTube',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Nouveautés : titre + bouton aléatoire des nouveautés.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Nouveautés',
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _ShuffleRecentButton(
                      albums: recent.value ?? const [],
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 208,
                child: recent.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Erreur: $e')),
                  data: (albums) => albums.isEmpty
                      ? const Center(child: Text('Aucun album'))
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                          itemCount: albums.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(width: 13),
                          itemBuilder: (context, i) =>
                              AlbumCard(album: albums[i]),
                        ),
                ),
              ),
              // Les plus populaires — masqué tant qu'il n'y a pas d'écoutes.
              // Titre cliquable → liste complète.
              ...popular.maybeWhen(
                data: (songs) => songs.isEmpty
                    ? const <Widget>[]
                    : [
                        _SectionHeaderLink(
                          title: 'Les plus populaires',
                          onTap: () => context.push('/popular'),
                        ),
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
              // Derniers joués (historique des stats — pas de lecture
              // directe : ces données n'ont pas de filePath). 5 + « Voir tout ».
              ...stats.maybeWhen(
                data: (s) => s.recentPlays.isEmpty
                    ? const <Widget>[]
                    : [
                        const SectionTitle(
                          'Derniers joués',
                          padding: EdgeInsets.fromLTRB(20, 14, 20, 4),
                        ),
                        for (final p in s.recentPlays.take(5))
                          _RecentPlayRow(p: p),
                        if (s.recentPlays.length > 5)
                          _ShowMoreTile(onTap: () => context.push('/stats')),
                      ],
                orElse: () => const <Widget>[],
              ),
            ],
          ),
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

/// Lecture aléatoire des nouveautés : charge les chansons des ~10 premiers
/// albums récents, mélange et joue.
class _ShuffleRecentButton extends ConsumerStatefulWidget {
  const _ShuffleRecentButton({required this.albums});

  final List<Album> albums;

  @override
  ConsumerState<_ShuffleRecentButton> createState() =>
      _ShuffleRecentButtonState();
}

class _ShuffleRecentButtonState extends ConsumerState<_ShuffleRecentButton> {
  bool _busy = false;

  Future<void> _shuffle() async {
    final albums = widget.albums;
    if (albums.isEmpty || _busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = ref.read(libraryRepositoryProvider);
      final details = await Future.wait(
        albums.take(10).map((a) => repo.albumDetail(a.id)),
      );
      final songs = [for (final d in details) ...d.songs]..shuffle();
      if (songs.isEmpty) return;
      await ref.read(playerActionsProvider).playSongs(songs);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const SizedBox(
        width: 42,
        height: 42,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return GlassIconButton(
      icon: Icons.shuffle,
      tooltip: 'Lecture aléatoire des nouveautés',
      size: 42,
      onPressed: widget.albums.isEmpty ? null : _shuffle,
    );
  }
}

/// Rangée « Derniers joués » : pochette, titre, artiste, « il y a X ».
class _RecentPlayRow extends StatelessWidget {
  const _RecentPlayRow({required this.p});

  final RecentPlay p;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: p.albumId > 0
            ? () => context.push('/album/${p.albumId}')
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              Artwork(
                url: p.artworkUrl.isEmpty ? null : p.artworkUrl,
                size: 46,
                borderRadius: 12,
                icon: Icons.music_note,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      p.artistName,
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
              const SizedBox(width: 8),
              Text(
                relativeTime(p.playedAt),
                style: TextStyle(fontSize: 12.5, color: scheme.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// En-tête de section cliquable (titre + chevron) menant à une vue complète.
class _SectionHeaderLink extends StatelessWidget {
  const _SectionHeaderLink({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 16, 4),
        child: Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 22, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Tuile « Voir tout » en bas d'une liste tronquée.
class _ShowMoreTile extends StatelessWidget {
  const _ShowMoreTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Voir tout',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
            Icon(Icons.expand_more, size: 20, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}
