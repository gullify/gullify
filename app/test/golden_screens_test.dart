// Rendus de contrôle : capture les écrans avec des données factices pour
// vérifier visuellement la mise en page (goldens), y compris les nouveaux
// onglets Bibliothèque et Explorer avec le mini-lecteur.
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/library_repository.dart';
import 'package:gullify/api/notifications_repository.dart';
import 'package:gullify/api/playlist_repository.dart';
import 'package:gullify/api/radio_repository.dart';
import 'package:gullify/models/album.dart';
import 'package:gullify/models/artist.dart';
import 'package:gullify/models/song.dart';
import 'package:gullify/screens/album_screen.dart';
import 'package:gullify/screens/artist_screen.dart';
import 'package:gullify/screens/explore_screen.dart';
import 'package:gullify/screens/library_home_screen.dart';
import 'package:gullify/screens/shell_screen.dart';
import 'package:gullify/state/favorites.dart';
import 'package:gullify/state/library.dart';
import 'package:gullify/state/notifications.dart';
import 'package:gullify/state/player.dart';
import 'package:gullify/state/playlists.dart';
import 'package:gullify/state/radio.dart';
import 'package:gullify/state/yt_downloads.dart';
import 'package:gullify/theme.dart';
import 'package:gullify/widgets/mini_player.dart';

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

/// Les goldens ne déclenchent aucune action de lecture : un Fake suffit
/// (le vrai PlayerActions exigerait le handler audio et ses plugins).
class _FakePlayerActions extends Fake implements PlayerActions {}

final _mediaItem = MediaItem(
  id: 'stream-1',
  title: 'Première chanson',
  artist: 'Artiste Test',
  album: 'Album Test',
  duration: const Duration(seconds: 215),
  extras: const {'songId': 1},
);

Widget _wrap(Widget child, {MediaItem? item}) {
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
      allFavoritesProvider.overrideWith((ref) async => _songs),
      notificationsProvider.overrideWith((ref) async =>
          const NotificationsPage(items: [], unread: 2)),
      radioStationsProvider.overrideWith((ref) async => _stations),
      suggestionsProvider.overrideWith(
          (ref) async => const Suggestions(genre: 'Indie', albums: _albums)),
      searchResultsProvider.overrideWith((ref) async => const SearchResults()),
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
      theme: gullifyGlassTheme(),
      home: Builder(
        builder: (context) {
          final bg = Theme.of(context)
              .extension<GullifySurfaces>()
              ?.background;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: bg ?? const LinearGradient(colors: [Colors.white, Colors.white]),
            ),
            child: child,
          );
        },
      ),
    ),
  );
}

/// Reproduit le shell (contenu + mini-lecteur + barre d'onglets de verre).
Widget _shellWrap(Widget child, {MediaItem? item, int tab = 0}) {
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
            GlassTabBar(currentIndex: tab, onSelect: (_) {}),
          ],
        ),
      ),
    ),
    item: item,
  );
}

void main() {
  Future<void> pumpScreen(WidgetTester tester, Widget widget) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(widget);
    await tester.pump(const Duration(milliseconds: 300));
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

  testWidgets('library home renders', (tester) async {
    await pumpScreen(tester, _shellWrap(const LibraryHomeScreen()));
    await expectLater(
      find.byKey(const Key('golden-root')),
      matchesGoldenFile('goldens/library_home.png'),
    );
  });

  testWidgets('library home renders with mini player', (tester) async {
    await pumpScreen(
      tester,
      _shellWrap(const LibraryHomeScreen(), item: _mediaItem),
    );
    await expectLater(
      find.byKey(const Key('golden-root')),
      matchesGoldenFile('goldens/library_home_playing.png'),
    );
  });

  testWidgets('library artists view renders', (tester) async {
    await pumpScreen(tester, _shellWrap(const LibraryHomeScreen()));
    await tester.tap(find.text('Artistes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byKey(const Key('golden-root')),
      matchesGoldenFile('goldens/library_artists.png'),
    );
  });

  testWidgets('library albums view renders', (tester) async {
    await pumpScreen(tester, _shellWrap(const LibraryHomeScreen()));
    await tester.tap(find.text('Albums'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byKey(const Key('golden-root')),
      matchesGoldenFile('goldens/library_albums.png'),
    );
  });

  testWidgets('explore screen renders', (tester) async {
    await pumpScreen(
      tester,
      _shellWrap(const ExploreScreen(), item: _mediaItem, tab: 1),
    );
    await expectLater(
      find.byKey(const Key('golden-root')),
      matchesGoldenFile('goldens/explore_screen.png'),
    );
  });
}
