// Reproduction du bug device : page artiste avec musique en cours et
// insets d'écran réels (notch + barre gestuelle), taille du téléphone.
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/library_repository.dart';
import 'package:gullify/models/album.dart';
import 'package:gullify/models/artist.dart';
import 'package:gullify/models/song.dart';
import 'package:gullify/screens/artist_screen.dart';
import 'package:gullify/state/library.dart';
import 'package:gullify/state/player.dart';
import 'package:gullify/state/yt_downloads.dart';
import 'package:gullify/theme.dart';

const _songs = [
  Song(id: 1, title: 'Boire ma bouteille', filePath: 'a.mp3', duration: 215,
      artistName: '1755', albumName: 'Anthologie', trackNumber: 1),
  Song(id: 2, title: 'Deuxième', filePath: 'b.mp3', duration: 187,
      artistName: '1755', albumName: 'Anthologie', trackNumber: 2),
];
const _album = Album(id: 1, name: 'Anthologie', year: 1998,
    artistId: 1, artistName: '1755');

class _FakePlayerActions extends Fake implements PlayerActions {}

final _item = MediaItem(
  id: 'https://x/stream.mp3',
  title: 'Boire ma bouteille',
  artist: '1755',
  album: 'Anthologie',
  duration: const Duration(minutes: 3, seconds: 35),
  extras: const {'songId': 1, 'filePath': 'a.mp3'},
);

void main() {
  testWidgets('artist page, playing item, real insets', (tester) async {
    tester.view.physicalSize = const Size(1344, 2992);
    tester.view.devicePixelRatio = 3.5;
    tester.view.padding = FakeViewPadding(
      top: (52 * 3.5),
      bottom: (34 * 3.5),
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        playerActionsProvider.overrideWithValue(_FakePlayerActions()),
        currentMediaItemProvider
            .overrideWith((ref) => Stream<MediaItem?>.value(_item)),
        playbackStateProvider.overrideWith(
            (ref) => Stream.value(PlaybackState(playing: true))),
        positionProvider
            .overrideWith((ref) => Stream.value(const Duration(seconds: 65))),
        artistDetailProvider(1).overrideWith((ref) async => const ArtistDetail(
              artist: Artist(id: 1, name: '1755', albumCount: 1),
              albums: [_album],
              topTracks: _songs,
            )),
        artistExtrasProvider('1755')
            .overrideWith((ref) async => const ArtistExtras()),
        ytArtistAlbumsProvider('1755').overrideWith((ref) async => []),
      ],
      child: MaterialApp(
        theme: gullifyGlassTheme(),
        home: const ArtistScreen(artistId: 1),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
      find.byType(ArtistScreen),
      matchesGoldenFile('goldens/artist_bug_repro.png'),
    );
  });
}
