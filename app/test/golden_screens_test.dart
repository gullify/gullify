// Rendus de contrôle : capture les écrans de détail avec des données
// factices pour vérifier visuellement la mise en page (goldens).
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/library_repository.dart';
import 'package:gullify/models/album.dart';
import 'package:gullify/models/artist.dart';
import 'package:gullify/models/song.dart';
import 'package:gullify/screens/album_screen.dart';
import 'package:gullify/screens/artist_screen.dart';
import 'package:gullify/state/library.dart';
import 'package:gullify/state/player.dart';
import 'package:gullify/state/yt_downloads.dart';
import 'package:gullify/theme.dart';

const _songs = [
  Song(id: 1, title: 'Première chanson', filePath: 'a.mp3', duration: 215,
      artistName: 'Artiste Test', albumName: 'Album Test', trackNumber: 1),
  Song(id: 2, title: 'Deuxième chanson', filePath: 'b.mp3', duration: 187,
      artistName: 'Artiste Test', albumName: 'Album Test', trackNumber: 2),
  Song(id: 3, title: 'Troisième chanson au titre vraiment long pour tester',
      filePath: 'c.mp3', duration: 240,
      artistName: 'Artiste Test', albumName: 'Album Test', trackNumber: 3),
];

const _album = Album(id: 1, name: 'Album Test', year: 2024,
    artistId: 1, artistName: 'Artiste Test');

Widget _wrap(Widget child) {
  return ProviderScope(
    overrides: [
      currentMediaItemProvider
          .overrideWith((ref) => Stream<MediaItem?>.value(null)),
      playbackStateProvider
          .overrideWith((ref) => Stream.value(PlaybackState())),
      positionProvider.overrideWith((ref) => Stream.value(Duration.zero)),
      albumDetailProvider(1).overrideWith(
          (ref) async => const AlbumDetail(album: _album, songs: _songs)),
      artistDetailProvider(1).overrideWith((ref) async => const ArtistDetail(
            artist: Artist(id: 1, name: 'Artiste Test', albumCount: 2),
            albums: [_album, Album(id: 2, name: 'Autre album', year: 2020)],
            topTracks: _songs,
          )),
      artistExtrasProvider('Artiste Test')
          .overrideWith((ref) async => const ArtistExtras()),
      ytArtistAlbumsProvider('Artiste Test')
          .overrideWith((ref) async => []),
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

void main() {
  testWidgets('album screen renders', (tester) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(_wrap(const AlbumScreen(albumId: 1)));
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(AlbumScreen),
      matchesGoldenFile('goldens/album_screen.png'),
    );
  });

  testWidgets('artist screen renders', (tester) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(_wrap(const ArtistScreen(artistId: 1)));
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(ArtistScreen),
      matchesGoldenFile('goldens/artist_screen.png'),
    );
  });
}
