// Rendus de contrôle : capture les écrans avec des données factices pour
// vérifier visuellement la mise en page (goldens), y compris les quatre
// onglets (Accueil, Bibliothèque, Radio, Recherche) et le mini-lecteur.
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/library_repository.dart';
import 'package:gullify/api/notifications_repository.dart';
import 'package:gullify/api/playlist_repository.dart';
import 'package:gullify/api/radio_repository.dart';
import 'package:gullify/api/stats_repository.dart';
import 'package:gullify/api/yt_downloads_repository.dart';
import 'package:gullify/models/album.dart';
import 'package:gullify/models/artist.dart';
import 'package:gullify/models/song.dart';
import 'package:gullify/screens/album_screen.dart';
import 'package:gullify/screens/artist_screen.dart';
import 'package:gullify/screens/games_screen.dart';
import 'package:gullify/screens/genre_screen.dart';
import 'package:gullify/screens/home_screen.dart';
import 'package:gullify/screens/library_screen.dart';
import 'package:gullify/screens/radio_screen.dart';
import 'package:gullify/screens/search_screen.dart';
import 'package:gullify/screens/shell_screen.dart';
import 'package:gullify/screens/year_screen.dart';
import 'package:gullify/state/favorites.dart';
import 'package:gullify/state/library.dart';
import 'package:gullify/state/notifications.dart';
import 'package:gullify/state/player.dart';
import 'package:gullify/state/playlists.dart';
import 'package:gullify/state/radio.dart';
import 'package:gullify/state/stats.dart';
import 'package:gullify/state/yt_downloads.dart';
import 'package:gullify/theme.dart';
import 'package:gullify/widgets/liquid_glass.dart';
import 'package:gullify/widgets/mini_player.dart';
import 'package:gullify/widgets/retro_chrome.dart';

const _songs = [
  Song(id: 1, title: 'Première chanson', filePath: 'a.mp3', duration: 215,
      artistName: 'Artiste Test', albumName: 'Album Test', trackNumber: 1),
  Song(id: 2, title: 'Deuxième chanson', filePath: 'b.mp3', duration: 187,
      artistName: 'Artiste Test', albumName: 'Album Test', trackNumber: 2),
  Song(id: 3, title: 'Troisième chanson au titre vraiment long pour tester',
      filePath: 'c.mp3', duration: 240,
      artistName: 'Artiste Test', albumName: 'Album Test', trackNumber: 3),
  Song(id: 4, title: 'Quatrième chanson', filePath: 'd.mp3', duration: 198,
      artistName: 'Autre Artiste', albumName: 'Autre album', trackNumber: 1),
  Song(id: 5, title: 'Cinquième chanson', filePath: 'e.mp3', duration: 232,
      artistName: 'Autre Artiste', albumName: 'Autre album', trackNumber: 2),
  Song(id: 6, title: 'Sixième chanson', filePath: 'f.mp3', duration: 176,
      artistName: 'Naïa', albumName: 'Halo', trackNumber: 1),
];

const _album = Album(id: 1, name: 'Album Test', year: 2024,
    artistId: 1, artistName: 'Artiste Test');

const _albums = [
  _album,
  Album(id: 2, name: 'Autre album', year: 2020, artistName: 'Autre Artiste'),
  Album(id: 3, name: 'Reflets', year: 2024, artistName: 'Mira Lune'),
  Album(id: 4, name: 'Littoral', year: 2023, artistName: 'Elian Vos'),
  Album(id: 5, name: 'Halo', year: 2024, artistName: 'Naïa'),
  Album(id: 6, name: 'Grand Large', year: 2023, artistName: 'Tom Brise'),
];

const _artists = [
  Artist(id: 1, name: 'Artiste Test', albumCount: 2, songCount: 12),
  Artist(id: 2, name: 'Autre Artiste', albumCount: 1, songCount: 8),
  Artist(id: 3, name: 'Mira Lune', albumCount: 2, songCount: 7),
  Artist(id: 4, name: 'Elian Vos', albumCount: 2, songCount: 5),
  Artist(id: 5, name: 'Naïa', albumCount: 2, songCount: 5),
  Artist(id: 6, name: 'Tom Brise', albumCount: 1, songCount: 3),
];

const _genres = [
  GenreCount('Chanson française', 3, albumCount: 5),
  GenreCount('Électro', 2, albumCount: 3),
  GenreCount('Jazz', 1, albumCount: 1),
  GenreCount('Rock', 4, albumCount: 9),
];

const _years = [
  YearCount(2024, albumCount: 3, songCount: 41),
  YearCount(2023, albumCount: 2, songCount: 26),
  YearCount(2020, albumCount: 1, songCount: 11),
  YearCount(1994, albumCount: 2, songCount: 24),
];

const _playlists = [
  Playlist(id: 1, name: 'Focus profond', songCount: 24),
  Playlist(id: 2, name: 'Matins calmes', songCount: 31),
  Playlist(id: 3, name: 'Route de nuit', songCount: 18),
  Playlist(id: 4, name: 'Café & pluie', songCount: 42),
];

const _stations = [
  RadioStation(id: 'a', name: 'FIP', streamUrl: 'https://s/fip',
      country: 'France', genres: ['Éclectique', 'Jazz'], favorite: true),
  RadioStation(id: 'b', name: 'Radio Nova', streamUrl: 'https://s/nova',
      country: 'France', genres: ['Groove']),
  RadioStation(id: 'c', name: 'KEXP', streamUrl: 'https://s/kexp',
      country: 'États-Unis', genres: ['Indie', 'Rock']),
];

const _ytAlbums = [
  YtAlbum(title: 'Nevermind', artist: 'Nirvana', year: '1991',
      thumbnail: '', browseId: 'b1'),
  YtAlbum(title: 'In Utero', artist: 'Nirvana', year: '1993',
      thumbnail: '', browseId: 'b2'),
];

const _ytSongs = [
  YtSong(title: 'Smells Like Teen Spirit', artist: 'Nirvana',
      album: 'Nevermind', duration: '5:01', thumbnail: '', videoId: 'v1'),
  YtSong(title: 'Come As You Are', artist: 'Nirvana',
      album: 'Nevermind', duration: '3:38', thumbnail: '', videoId: 'v2'),
];

ListeningStats _stats() => ListeningStats(
      general: const StatsGeneral(
        totalPlays: 128,
        totalListenTimeFormatted: '9 h',
        uniqueSongsPlayed: 64,
        completionRate: 82,
        totalSkips: 4,
        avgDurationFormatted: '3 min',
      ),
      topSongs: const [],
      topArtists: const [],
      topAlbums: const [],
      dailyPlays: const StatsChart(labels: [], data: []),
      hourly: const StatsChart(labels: [], data: []),
      weekday: const StatsChart(labels: [], data: []),
      genres: const [],
      recentPlays: [
        RecentPlay(
          title: 'Première chanson',
          artistName: 'Artiste Test',
          albumId: 1,
          artworkUrl: '',
          playedAt: DateTime.now().subtract(const Duration(minutes: 5)),
          completed: true,
        ),
        RecentPlay(
          title: 'Quatrième chanson',
          artistName: 'Autre Artiste',
          albumId: 2,
          artworkUrl: '',
          playedAt: DateTime.now().subtract(const Duration(hours: 3)),
          completed: true,
        ),
        RecentPlay(
          title: 'Sixième chanson',
          artistName: 'Naïa',
          albumId: 5,
          artworkUrl: '',
          playedAt: DateTime.now().subtract(const Duration(days: 2)),
          completed: false,
        ),
      ],
    );

/// Les goldens ne déclenchent aucune action de lecture : un Fake suffit
/// (le vrai PlayerActions exigerait le handler audio et ses plugins).
class _FakePlayerActions extends Fake implements PlayerActions {}

/// Requête de recherche fixée pour le golden de l'onglet Recherche.
class _FixedQuery extends SearchQuery {
  _FixedQuery(this.q);

  final String q;

  @override
  String build() => q;
}

final _mediaItem = MediaItem(
  id: 'stream-1',
  title: 'Première chanson',
  artist: 'Artiste Test',
  album: 'Album Test',
  duration: const Duration(seconds: 215),
  extras: const {'songId': 1},
);

Widget _wrap(
  Widget child, {
  MediaItem? item,
  String? searchQuery,
  ThemeData? theme,
}) {
  return ProviderScope(
    // NB : liste inline — riverpod 3 n'exporte pas le nom `Override`
    // (collision avec dart:core), le type est donc déduit du paramètre.
    overrides: [
      playerActionsProvider.overrideWithValue(_FakePlayerActions()),
      currentMediaItemProvider
          .overrideWith((ref) => Stream<MediaItem?>.value(item)),
      playbackStateProvider.overrideWith(
          (ref) => Stream.value(PlaybackState(playing: item != null))),
      positionProvider.overrideWith(
          (ref) => Stream.value(const Duration(seconds: 72))),
      recentAlbumsProvider.overrideWith((ref) async => _albums),
      playlistsProvider.overrideWith((ref) async => _playlists),
      popularSongsProvider.overrideWith((ref) async => _songs),
      artistsProvider.overrideWith((ref) async => _artists),
      albumsProvider.overrideWith((ref) async => _albums),
      genresProvider.overrideWith((ref) async => _genres),
      albumsByGenreProvider('Rock').overrideWith((ref) async => _albums),
      artistsByGenreProvider('Rock').overrideWith((ref) async => _artists),
      allFavoritesProvider.overrideWith((ref) async => _songs),
      statsProvider.overrideWith((ref) async => _stats()),
      notificationsProvider.overrideWith((ref) async =>
          const NotificationsPage(items: [], unread: 2)),
      radioStationsProvider.overrideWith((ref) async => _stations),
      yearsProvider.overrideWith((ref) async => _years),
      albumsByYearProvider(2024).overrideWith((ref) async => _albums),
      suggestionsProvider.overrideWith(
          (ref) async => const Suggestions(genre: 'Indie', albums: _albums)),
      if (searchQuery != null) ...[
        searchQueryProvider.overrideWith(() => _FixedQuery(searchQuery)),
        searchResultsProvider.overrideWith((ref) async => SearchResults(
              artists: [_artists.first],
              albums: [_album],
              songs: _songs.take(2).toList(),
            )),
        ytAlbumSearchProvider(searchQuery)
            .overrideWith((ref) async => _ytAlbums),
        ytSongSearchProvider(searchQuery)
            .overrideWith((ref) async => _ytSongs),
      ] else
        searchResultsProvider
            .overrideWith((ref) async => const SearchResults()),
      albumDetailProvider(1).overrideWith(
          (ref) async => const AlbumDetail(album: _album, songs: _songs)),
      artistDetailProvider(1).overrideWith((ref) async => const ArtistDetail(
            artist: Artist(id: 1, name: 'Artiste Test', albumCount: 2),
            albums: [_album, Album(id: 2, name: 'Autre album', year: 2020)],
            topTracks: _songs,
          )),
      artistExtrasProvider('Artiste Test')
          .overrideWith((ref) async => const ArtistExtras()),
      ytArtistAlbumsProvider('Artiste Test').overrideWith((ref) async => []),
    ],
    child: MaterialApp(
      theme: theme ?? gullifyThemeFor(GullifyAccent.indigo, dark: false),
      home: Builder(
        builder: (context) {
          final surfaces = Theme.of(context).extension<GullifySurfaces>();
          final bg = surfaces?.background;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: bg ?? const LinearGradient(colors: [Colors.white, Colors.white]),
            ),
            // Comme main.dart : sous le rétro, la tôle brossée passe entre le
            // fond et les écrans (idée #83) ; sous l'Apple Liquid Glass, c'est
            // le fond d'écran coloré qui s'y glisse (idée #99) — sans lui le
            // golden ne montrerait pas ce que le verre laisse passer.
            child: switch (surfaces) {
              GullifySurfaces(retro: true) => RetroChassis(child: child),
              GullifySurfaces(liquid: true, accentBlob: final accent?) => Stack(
                children: [
                  Positioned.fill(
                    child: LiquidWallpaper(
                      accent: accent,
                      dark: Theme.of(context).brightness == Brightness.dark,
                    ),
                  ),
                  child,
                ],
              ),
              _ => child,
            },
          );
        },
      ),
    ),
  );
}

/// Reproduit le shell (contenu + mini-lecteur + barre d'onglets de verre).
Widget _shellWrap(
  Widget child, {
  MediaItem? item,
  int tab = 0,
  String? searchQuery,
  ThemeData? theme,
}) {
  return _wrap(
    KeyedSubtree(
      key: const Key('golden-root'),
      child: Scaffold(
        extendBody: true,
        body: child,
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiniPlayer(),
            HubDock(currentIndex: tab, onSelect: (_) {}),
          ],
        ),
      ),
    ),
    item: item,
    searchQuery: searchQuery,
    theme: theme,
  );
}

void main() {
  Future<void> pumpScreen(WidgetTester tester, Widget widget) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(widget);
    await tester.pump(const Duration(milliseconds: 300));
    // Deuxième frame : les FutureProvider factices sont résolus.
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('album screen renders', (tester) async {
    await pumpScreen(tester, _wrap(const AlbumScreen(albumId: 1)));
    await expectLater(
      find.byType(AlbumScreen),
      matchesGoldenFile('goldens/album_screen.png'),
    );
  });

  testWidgets('artist screen renders', (tester) async {
    await pumpScreen(tester, _wrap(const ArtistScreen(artistId: 1)));
    await expectLater(
      find.byType(ArtistScreen),
      matchesGoldenFile('goldens/artist_screen.png'),
    );
  });

  testWidgets('home screen renders', (tester) async {
    await pumpScreen(tester, _shellWrap(const HomeScreen()));
    await expectLater(
      find.byKey(const Key('golden-root')),
      matchesGoldenFile('goldens/home_screen.png'),
    );
  });

  testWidgets('home screen renders with mini player', (tester) async {
    await pumpScreen(tester, _shellWrap(const HomeScreen(), item: _mediaItem));
    await expectLater(
      find.byKey(const Key('golden-root')),
      matchesGoldenFile('goldens/home_playing.png'),
    );
  });

  // Le thème rétro Winamp (idée #82) : mêmes écrans, même mise en page —
  // seules les surfaces changent. Le golden est là pour qu'un jour où
  // l'habillage de verre bouge, on voie tout de suite si le rétro a suivi.
  testWidgets('home screen renders in the retro Winamp skin', (tester) async {
    await pumpScreen(
      tester,
      _shellWrap(
        const HomeScreen(),
        item: _mediaItem,
        theme: gullifyTheme(
          GullifySkin.winamp,
          GullifyAccent.indigo,
          dark: true,
        ),
      ),
    );
    await expectLater(
      find.byKey(const Key('golden-root')),
      matchesGoldenFile('goldens/home_winamp.png'),
    );
  });

  // La lentille d'Apple (idée #105) se peint dans un shader, et un shader se
  // charge depuis les assets : deux frames après le premier affichage, il
  // n'est pas encore là et les surfaces sortent nues. Ces quelques frames de
  // plus laissent la matière arriver — sans elles, le golden ne garderait
  // trace que du vide.
  Future<void> pumpLens(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  // Le thème Apple Liquid Glass (idée #98) : même écran, même mise en page —
  // seule la matière change. Le golden garde trace de ce que doivent donner
  // la vitre plus fine, le fond réfracté et les angles en superellipse.
  testWidgets('home screen renders in the Apple Liquid Glass skin',
      (tester) async {
    await pumpScreen(
      tester,
      _shellWrap(
        const HomeScreen(),
        item: _mediaItem,
        theme: gullifyTheme(
          GullifySkin.apple,
          GullifyAccent.indigo,
          dark: false,
        ),
      ),
    );
    await pumpLens(tester);
    await expectLater(
      find.byKey(const Key('golden-root')),
      matchesGoldenFile('goldens/home_apple.png'),
    );
  });

  // …et le même en sombre (idée #99). Le fond d'écran coloré et la vitre
  // amaigrie se jouent surtout là : sur du noir, un verre trop dense
  // redevient un simple panneau gris.
  testWidgets('home screen renders in the Apple Liquid Glass skin (sombre)',
      (tester) async {
    await pumpScreen(
      tester,
      _shellWrap(
        const HomeScreen(),
        item: _mediaItem,
        theme: gullifyTheme(
          GullifySkin.apple,
          GullifyAccent.indigo,
          dark: true,
        ),
      ),
    );
    await pumpLens(tester);
    await expectLater(
      find.byKey(const Key('golden-root')),
      matchesGoldenFile('goldens/home_apple_dark.png'),
    );
  });

  testWidgets('library screen renders (artistes)', (tester) async {
    await pumpScreen(tester, _shellWrap(const LibraryScreen(), tab: 1));
    await expectLater(
      find.byKey(const Key('golden-root')),
      matchesGoldenFile('goldens/library_screen.png'),
    );
  });

  testWidgets('library albums view renders', (tester) async {
    await pumpScreen(tester, _shellWrap(const LibraryScreen(), tab: 1));
    await tester.tap(find.text('Albums'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byKey(const Key('golden-root')),
      matchesGoldenFile('goldens/library_albums.png'),
    );
  });

  testWidgets('library genres view renders', (tester) async {
    await pumpScreen(tester, _shellWrap(const LibraryScreen(), tab: 1));
    await tester.tap(find.text('Genres'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byKey(const Key('golden-root')),
      matchesGoldenFile('goldens/library_genres.png'),
    );
  });

  testWidgets('library years view renders', (tester) async {
    await pumpScreen(tester, _shellWrap(const LibraryScreen(), tab: 1));
    await tester.tap(find.text('Années'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byKey(const Key('golden-root')),
      matchesGoldenFile('goldens/library_years.png'),
    );
  });

  testWidgets('year screen renders', (tester) async {
    await pumpScreen(tester, _wrap(const YearScreen(year: 2024)));
    await expectLater(
      find.byType(YearScreen),
      matchesGoldenFile('goldens/year_screen.png'),
    );
  });

  testWidgets('genre screen renders', (tester) async {
    await pumpScreen(tester, _wrap(const GenreScreen(genre: 'Rock')));
    await expectLater(
      find.byType(GenreScreen),
      matchesGoldenFile('goldens/genre_screen.png'),
    );
  });

  testWidgets('library playlists view renders', (tester) async {
    await pumpScreen(tester, _shellWrap(const LibraryScreen(), tab: 1));
    await tester.tap(find.text('Playlists'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byKey(const Key('golden-root')),
      matchesGoldenFile('goldens/library_playlists.png'),
    );
  });

  testWidgets('radio screen renders', (tester) async {
    await pumpScreen(tester, _shellWrap(const RadioScreen(), tab: 2));
    await expectLater(
      find.byKey(const Key('golden-root')),
      matchesGoldenFile('goldens/radio_screen.png'),
    );
  });

  testWidgets('games screen renders', (tester) async {
    await pumpScreen(tester, _shellWrap(const GamesScreen(), tab: 5));
    await expectLater(
      find.byKey(const Key('golden-root')),
      matchesGoldenFile('goldens/games_screen.png'),
    );
  });

  testWidgets('search screen renders with results', (tester) async {
    await pumpScreen(
      tester,
      _shellWrap(const SearchScreen(), tab: 3, searchQuery: 'nirvana'),
    );
    await expectLater(
      find.byKey(const Key('golden-root')),
      matchesGoldenFile('goldens/search_screen.png'),
    );
  });
}
