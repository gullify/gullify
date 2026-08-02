// Compilations « Various Artists » : chaque piste porte son propre
// interprète (le serveur le renvoie, avec repli sur l'artiste de l'album).
// La page album doit le mettre en préfixe du titre — et seulement là où il
// diffère de l'artiste de l'album.
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/library_repository.dart';
import 'package:gullify/models/album.dart';
import 'package:gullify/models/song.dart';
import 'package:gullify/screens/album_screen.dart';
import 'package:gullify/state/library.dart';
import 'package:gullify/state/player.dart';
import 'package:gullify/theme.dart';

const _compilation = Album(id: 7, name: 'Punk Volume 2', year: 2001,
    artistId: 9, artistName: 'Various Artists');

const _compilationSongs = [
  Song(id: 1, title: 'As Wicked', filePath: 'a.mp3', duration: 180,
      artistId: 11, artistName: 'Rancid', albumName: 'Punk Volume 2',
      trackNumber: 1),
  // Piste sans interprète propre : le serveur retombe sur l'artiste de
  // l'album, qu'il ne faut pas répéter devant le titre.
  Song(id: 2, title: 'Pawn Shop', filePath: 'b.mp3', duration: 160,
      artistId: 9, artistName: 'Various Artists', albumName: 'Punk Volume 2',
      trackNumber: 2),
];

const _regular = Album(id: 8, name: 'Anthologie', year: 1998,
    artistId: 1, artistName: '1755');

const _regularSongs = [
  Song(id: 3, title: 'Boire ma bouteille', filePath: 'c.mp3', duration: 215,
      artistId: 1, artistName: '1755', albumName: 'Anthologie',
      trackNumber: 1),
];

class _FakePlayerActions extends Fake implements PlayerActions {}

Widget _albumApp(int id, AlbumDetail detail) => ProviderScope(
      overrides: [
        playerActionsProvider.overrideWithValue(_FakePlayerActions()),
        currentMediaItemProvider
            .overrideWith((ref) => Stream<MediaItem?>.value(null)),
        playbackStateProvider
            .overrideWith((ref) => Stream.value(PlaybackState())),
        albumDetailProvider(id).overrideWith((ref) async => detail),
      ],
      child: MaterialApp(
        theme: gullifyThemeFor(GullifyAccent.indigo, dark: false),
        home: AlbumScreen(albumId: id),
      ),
    );

void main() {
  // Écran assez haut pour que toute la liste de pistes soit rendue.
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .views.first;
    view.physicalSize = const Size(1200, 3000);
    view.devicePixelRatio = 2.0;
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('compilation : « Interprète — Titre » sur les pistes qui ont '
      'un interprète propre', (tester) async {
    await tester.pumpWidget(_albumApp(
      7,
      const AlbumDetail(album: _compilation, songs: _compilationSongs),
    ));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Rancid — As Wicked'), findsOneWidget);
    // Repli sur l'artiste de l'album : titre seul, sans « Various Artists ».
    expect(find.text('Pawn Shop'), findsOneWidget);
    expect(find.textContaining('Various Artists — '), findsNothing);
  });

  testWidgets('album normal : le titre reste seul (l\'entête donne '
      'l\'artiste)', (tester) async {
    await tester.pumpWidget(_albumApp(
      8,
      const AlbumDetail(album: _regular, songs: _regularSongs),
    ));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Boire ma bouteille'), findsOneWidget);
    // L'artiste n'est répété ni devant le titre ni en sous-titre de rangée :
    // seul l'entête de l'album l'affiche.
    expect(find.text('1755'), findsOneWidget);
  });
}
