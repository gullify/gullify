import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/stats_repository.dart';
import '../models/album.dart';
import '../state/discover.dart';
import '../state/library.dart';
import '../state/notifications.dart';
import '../state/player.dart';
import '../state/stats.dart';
import '../theme.dart';
import '../widgets/album_card.dart';
import '../widgets/artwork.dart';
import '../widgets/glass_box.dart';
import '../widgets/glass_kit.dart';
import '../widgets/retro_lcd.dart';
import '../widgets/song_menu.dart';
import '../widgets/song_tile.dart';
import 'stats_screen.dart' show relativeTime;
import '../widgets/wordmark.dart';

/// Onglet « Accueil » : logo, boutons de verre, « Nouveautés »
/// (albums récents + lecture aléatoire), « Les plus populaires » (top 5)
/// et « Derniers joués » (historique récent des statistiques).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentAlbumsProvider);
    final popular = ref.watch(popularSongsProvider);
    final stats = ref.watch(statsProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () {
            ref.invalidate(popularSongsProvider);
            ref.invalidate(statsProvider);
            ref.invalidate(discoverArtistProvider);
            return ref.refresh(recentAlbumsProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 18,
            ),
            children: [
              // En-tête : logo « Gullify » + boutons de verre 42.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Row(
                  children: [
                    // La mouette et le nom seuls, en grand : la salutation
                    // rappelait un nom d'utilisateur que l'on connaît déjà,
                    // autant donner la place à la marque (idées #92, #95).
                    Expanded(
                      child: const GulliLogo(
                        fontSize: 38,
                        style: TextStyle(height: 1.02),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
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
              // Accès rapides : lecture aléatoire de toute la bibliothèque
              // et « Découverte » (titres jamais joués).
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 2),
                child: _QuickPlayRow(),
              ),
              // Découvrir (idée #118) : les quatre façons de sortir de sa
              // bibliothèque, réunies sous une seule carte d'accent.
              const _DiscoverBlock(),
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
                    _ShuffleRecentButton(albums: recent.value ?? const []),
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
                          separatorBuilder: (_, _) => const SizedBox(width: 13),
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

class _NotificationsButton extends ConsumerStatefulWidget {
  const _NotificationsButton();

  @override
  ConsumerState<_NotificationsButton> createState() =>
      _NotificationsButtonState();
}

class _NotificationsButtonState extends ConsumerState<_NotificationsButton> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // La pastille doit s'allumer toute seule : une idée confiée à Claude
    // aboutit pendant que l'app est ouverte, et rien ne relit la liste sinon.
    _poll = Timer.periodic(
      const Duration(minutes: 1),
      (_) => mounted ? ref.invalidate(notificationsProvider) : null,
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        onTap: p.albumId > 0 ? () => context.push('/album/${p.albumId}') : null,
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

/// Le bloc « Découvrir » (idée #118) : les quatre portes qui mènent hors de
/// la bibliothèque — un artiste voisin, les nouveautés de YouTube Music, un
/// genre sur Bandcamp, les podcasts — réunies sous une seule carte au lieu
/// d'être semées dans la page.
///
/// La carte porte la couleur d'accent ; les deux services extérieurs gardent,
/// eux, LEUR couleur (bleu Bandcamp, rouge YouTube Music) : c'est à elle
/// qu'on les reconnaît sans lire. Sous le rétro Winamp, le lavis d'accent
/// s'efface — un châssis de 1999 ne se teinte pas.
class _DiscoverBlock extends ConsumerWidget {
  const _DiscoverBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // Rien pendant le chargement comme en cas d'erreur : la rangée de
    // l'artiste voisin apparaît quand il y a vraiment quelqu'un à proposer.
    final discover = ref.watch(discoverArtistProvider).value;
    final retro = isRetroSkin(context);

    final contents = Column(
      // Largeur imposée aux rangées : sans cela les séparateurs, qui n'ont
      // pas d'enfant, se replieraient sur zéro.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 2),
          child: Row(
            children: [
              Icon(Icons.explore_outlined, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                'Découvrir',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ),
        if (discover != null) ...[
          _DiscoverArtistRow(discover: discover),
          const _DiscoverSeparator(),
        ],
        _DiscoverRow(
          icon: Icons.play_circle_fill,
          color: youtubeMusicRed,
          title: 'Nouveautés YouTube Music',
          hint: 'Les albums qui sortent, tes artistes en premier',
          onTap: () {
            // L'onglet Recherche montre les nouveautés quand rien n'est
            // demandé : on vide donc la requête avant d'y aller.
            ref.read(searchQueryProvider.notifier).set('');
            context.go('/search');
          },
        ),
        const _DiscoverSeparator(),
        _DiscoverRow(
          icon: Icons.album_outlined,
          color: bandcampBlue,
          title: 'Découvrir sur Bandcamp',
          hint: 'Un genre, ses nouveautés ou un tirage au hasard',
          onTap: () => context.push('/bandcamp'),
        ),
        const _DiscoverSeparator(),
        _DiscoverRow(
          icon: Icons.podcasts_outlined,
          color: scheme.primary,
          title: 'Podcasts',
          hint: 'Chercher, s\'abonner, écouter ses épisodes',
          onTap: () => context.push('/podcasts'),
        ),
        const SizedBox(height: 4),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
      child: GlassBox(
        radius: 20,
        blur: false,
        child: retro
            ? contents
            : DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      scheme.primary.withValues(alpha: 0.20),
                      scheme.primary.withValues(alpha: 0.05),
                    ],
                  ),
                ),
                child: contents,
              ),
      ),
    );
  }
}

/// Le trait qui sépare deux portes du bloc : un filet d'accent qui s'éteint
/// sur les bords, plutôt qu'une barre d'un mur à l'autre. Séparer sans
/// découper la carte en tranches.
class _DiscoverSeparator extends StatelessWidget {
  const _DiscoverSeparator();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              scheme.primary.withValues(alpha: 0),
              scheme.primary.withValues(alpha: 0.35),
              scheme.primary.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

/// Une porte du bloc « Découvrir » : pastille colorée, titre, sous-titre.
/// La couleur est celle du service (ou l'accent, pour ce qui est de la
/// maison) ; elle ne touche que la pastille, le texte reste à l'encre de
/// l'app pour rester lisible en clair comme en sombre.
class _DiscoverRow extends StatelessWidget {
  const _DiscoverRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.hint,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
        child: Row(
          children: [
            _DiscoverBadge(icon: icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// La pastille d'une porte : l'icône du service dans un carré arrondi de sa
/// propre couleur, posée à plat.
class _DiscoverBadge extends StatelessWidget {
  const _DiscoverBadge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: color.withValues(alpha: 0.16),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }
}

/// La première porte du bloc : un artiste que l'utilisateur ne possède pas,
/// suggéré par YouTube Music à partir d'un artiste de sa bibliothèque. Un tap
/// lance une recherche sur ce nom (pour l'explorer / le télécharger) ; le
/// bouton relance un tirage.
class _DiscoverArtistRow extends ConsumerWidget {
  const _DiscoverArtistRow({required this.discover});

  final DiscoverArtist discover;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () {
        ref.read(searchQueryProvider.notifier).set(discover.artist.name);
        context.go('/search');
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
        child: Row(
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Artwork(
                url: discover.artist.thumbnail.isEmpty
                    ? null
                    : discover.artist.thumbnail,
                size: 52,
                borderRadius: 26,
                icon: Icons.person,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    discover.artist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'Parce que vous avez ${discover.becauseOf} dans votre '
                    'bibliothèque',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.15,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            GlassIconButton(
              icon: Icons.refresh,
              tooltip: 'Une autre suggestion',
              size: 36,
              onPressed: () => ref.invalidate(discoverArtistProvider),
            ),
          ],
        ),
      ),
    );
  }
}

/// Deux accès rapides sur l'accueil : « Aléatoire » (toute la bibliothèque)
/// et « Découverte » (titres jamais joués). Chacun charge puis lance.
class _QuickPlayRow extends ConsumerStatefulWidget {
  const _QuickPlayRow();

  @override
  ConsumerState<_QuickPlayRow> createState() => _QuickPlayRowState();
}

class _QuickPlayRowState extends ConsumerState<_QuickPlayRow> {
  bool _busyRandom = false;
  bool _busyDiscovery = false;

  Future<void> _play({required bool discovery}) async {
    setState(() => discovery ? _busyDiscovery = true : _busyRandom = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Lu au tap (pas dans build) pour ne pas forcer l'ApiClient en test.
      final repo = ref.read(libraryRepositoryProvider);
      final songs = await (discovery
          ? repo.discoverySongs()
          : repo.randomSongs());
      if (songs.isEmpty) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              discovery
                  ? 'Aucun titre jamais joué — tout a déjà été écouté !'
                  : 'Bibliothèque vide',
            ),
          ),
        );
        return;
      }
      await ref.read(playerActionsProvider).playSongs(songs..shuffle());
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Échec : $e')));
    } finally {
      if (mounted) {
        setState(
          () => discovery ? _busyDiscovery = false : _busyRandom = false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickButton(
            icon: Icons.shuffle,
            label: 'Aléatoire',
            busy: _busyRandom,
            onTap: () => _play(discovery: false),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickButton(
            icon: Icons.auto_awesome,
            label: 'Découverte',
            busy: _busyDiscovery,
            onTap: () => _play(discovery: true),
          ),
        ),
      ],
    );
  }
}

class _QuickButton extends StatelessWidget {
  const _QuickButton({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassBox(
      radius: 16,
      blur: false,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
