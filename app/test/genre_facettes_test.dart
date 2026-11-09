// Un genre se croise à l'origine de ses artistes, et une origine à leurs
// genres : dans « Rock », [Québec] [France] ; dans « Québec », [Rock] [Folk].
// Le filtre vaut pour les albums comme pour les artistes.
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/models/album.dart';
import 'package:gullify/models/artist.dart';
import 'package:gullify/screens/genre_screen.dart';
import 'package:gullify/state/library.dart';
import 'package:gullify/state/player.dart';
import 'package:gullify/theme.dart';

class _FakePlayerActions extends Fake implements PlayerActions {}

const _artists = [
  Artist(id: 1, name: 'Les Colocs', genres: ['Rock'], origine: 'Québec'),
  Artist(id: 2, name: 'Noir Désir', genres: ['Rock'], origine: 'France'),
  Artist(
    id: 3,
    name: 'Les Cowboys Fringants',
    genres: ['Folk', 'Rock'],
    origine: 'Québec',
  ),
];

const _albums = [
  Album(id: 10, name: 'Atrocetomique', artistId: 1),
  Album(id: 20, name: 'Tostaky', artistId: 2),
  Album(id: 30, name: 'Break syndical', artistId: 3),
];

Widget _wrap(Widget child) => ProviderScope(
  overrides: [
    playerActionsProvider.overrideWithValue(_FakePlayerActions()),
    currentMediaItemProvider.overrideWith(
      (ref) => Stream<MediaItem?>.value(null),
    ),
    playbackStateProvider.overrideWith((ref) => Stream.value(PlaybackState())),
    albumsByGenreProvider('Rock').overrideWith((ref) async => _albums),
    artistsByGenreProvider('Rock').overrideWith((ref) async => _artists),
    albumsByFacetProvider((genre: null, origine: 'Québec'))
        .overrideWith((ref) async => [_albums[0], _albums[2]]),
    artistsByFacetProvider((genre: null, origine: 'Québec'))
        .overrideWith((ref) async => [_artists[0], _artists[2]]),
  ],
  child: MaterialApp(
    theme: gullifyThemeFor(GullifyAccent.indigo, dark: false),
    home: child,
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('un genre se filtre par origine', (tester) async {
    tester.view.physicalSize = const Size(412, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(const GenreScreen(genre: 'Rock')));
    await _settle(tester);

    expect(find.widgetWithText(ChoiceChip, 'Tous · 3'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Québec · 2'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'France · 1'), findsOneWidget);
    expect(find.text('Noir Désir'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Québec · 2'));
    await _settle(tester);

    expect(find.text('Noir Désir'), findsNothing);
    expect(find.text('Tostaky'), findsNothing);
    expect(find.text('Les Colocs'), findsOneWidget);
    expect(find.text('Break syndical'), findsOneWidget);
    expect(find.text('Artistes · 2'), findsOneWidget);

    // Retaper la puce rend tout.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Québec · 2'));
    await _settle(tester);
    expect(find.text('Noir Désir'), findsOneWidget);
  });

  testWidgets('une origine se filtre par genre', (tester) async {
    tester.view.physicalSize = const Size(412, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(const GenreScreen(origine: 'Québec')));
    await _settle(tester);

    expect(find.text('Québec'), findsOneWidget); // le titre
    expect(find.widgetWithText(ChoiceChip, 'Rock · 2'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Folk · 1'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Folk · 1'));
    await _settle(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Folk · 1'));
    await _settle(tester);

    expect(find.text('Les Colocs'), findsNothing);
    expect(find.text('Les Cowboys Fringants'), findsOneWidget);
  });

  testWidgets('une seule origine partout : pas de puces', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        playerActionsProvider.overrideWithValue(_FakePlayerActions()),
        currentMediaItemProvider.overrideWith(
          (ref) => Stream<MediaItem?>.value(null),
        ),
        playbackStateProvider.overrideWith(
          (ref) => Stream.value(PlaybackState()),
        ),
        albumsByGenreProvider('Folk').overrideWith((ref) async => const []),
        artistsByGenreProvider('Folk')
            .overrideWith((ref) async => [_artists[2]]),
      ],
      child: const MaterialApp(home: GenreScreen(genre: 'Folk')),
    ));
    await _settle(tester);

    expect(find.byType(ChoiceChip), findsNothing);
  });
}
