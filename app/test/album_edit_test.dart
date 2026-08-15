// Corriger l'artiste ou le titre d'un album (idée #94) : le menu de la fiche
// ouvre les deux noms déjà remplis, et l'album va rejoindre l'artiste ainsi
// nommé. Quand il fusionne avec un homonyme, l'ancien identifiant ne désigne
// plus rien — la fiche doit suivre le survivant.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gullify/api/api_client.dart';
import 'package:gullify/api/library_repository.dart';
import 'package:gullify/models/album.dart';
import 'package:gullify/screens/album_screen.dart';
import 'package:gullify/state/library.dart';

class _FakeLibraryRepo extends Fake implements LibraryRepository {
  final List<(int, String, String)> calls = [];
  Object? failWith;

  /// Ce que le serveur répond ; par défaut, un simple transfert.
  AlbumEdit Function(String artist, String album) reply =
      (artist, album) => AlbumEdit(
            albumId: 7,
            artistId: 2,
            artist: artist,
            album: album,
            changed: true,
            moved: true,
            renamed: false,
            merged: false,
            removedArtist: 'Katch 22',
            songs: 13,
            tagsWritten: 13,
            tagsFailed: 0,
          );

  @override
  Future<AlbumEdit> editAlbum(
    int albumId, {
    required String artist,
    required String album,
  }) async {
    calls.add((albumId, artist, album));
    if (failWith != null) throw failWith!;
    return reply(artist, album);
  }
}

const _album = Album(
  id: 7,
  name: 'Dinosaur Sounds',
  artistId: 1,
  artistName: 'Katch 22',
);

const _twin = Album(
  id: 9,
  name: 'Dinosaur Sounds',
  artistId: 2,
  artistName: 'Catch 22',
);

/// Un routeur pour de vrai : la fusion change de fiche, on veut voir où.
GoRouter _router(_FakeLibraryRepo repo) => GoRouter(
      initialLocation: '/album/7',
      routes: [
        GoRoute(
          path: '/album/:id',
          builder: (_, state) =>
              AlbumScreen(albumId: int.parse(state.pathParameters['id']!)),
        ),
      ],
    );

Widget _wrap(_FakeLibraryRepo repo, GoRouter router) => ProviderScope(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(repo),
        albumDetailProvider(7).overrideWith(
          (ref) async => const AlbumDetail(album: _album, songs: []),
        ),
        albumDetailProvider(9).overrideWith(
          (ref) async => const AlbumDetail(album: _twin, songs: []),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );

/// Laisse tout se poser. Pas `pumpAndSettle` : l'égaliseur qui bat à côté du
/// titre n'a pas de fin.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late GoRouter router;

  Future<void> openDialog(WidgetTester tester, _FakeLibraryRepo repo) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    router = _router(repo);
    addTearDown(router.dispose);
    await tester.pumpWidget(_wrap(repo, router));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await settle(tester);
    await tester.tap(find.text("Corriger l'artiste ou le titre"));
    await settle(tester);
  }

  testWidgets('les deux noms arrivent déjà remplis', (tester) async {
    await openDialog(tester, _FakeLibraryRepo());

    expect(find.widgetWithText(TextField, 'Katch 22'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Dinosaur Sounds'), findsOneWidget);
    // Rien n'a changé : il n'y a rien à enregistrer.
    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Enregistrer'),
    );
    expect(save.onPressed, isNull);
  });

  testWidgets('corriger l\'artiste transfère l\'album', (tester) async {
    final repo = _FakeLibraryRepo();
    await openDialog(tester, repo);

    await tester.enterText(find.byType(TextField).first, 'Catch 22');
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
    await settle(tester);

    // Le titre part inchangé : le serveur ne doit pas le deviner.
    expect(repo.calls, [(7, 'Catch 22', 'Dinosaur Sounds')]);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Album transféré à Catch 22'), findsOneWidget);
    // Pas de fusion : on reste sur la même fiche.
    expect(router.state.uri.toString(), '/album/7');
  });

  testWidgets('un album fusionné emmène la fiche sur le survivant',
      (tester) async {
    final repo = _FakeLibraryRepo()
      ..reply = (artist, album) => AlbumEdit(
            albumId: 9, // l'album d'accueil
            artistId: 2,
            artist: artist,
            album: album,
            changed: true,
            moved: true,
            renamed: false,
            merged: true,
            removedArtist: 'Katch 22',
            songs: 13,
            tagsWritten: 13,
            tagsFailed: 0,
          );
    await openDialog(tester, repo);

    await tester.enterText(find.byType(TextField).first, 'Catch 22');
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
    await settle(tester);

    expect(find.text('Album réuni avec « Dinosaur Sounds »'), findsOneWidget);
    // L'album 7 n'existe plus : sa fiche afficherait une erreur.
    expect(router.state.uri.toString(), '/album/9');
  });

  testWidgets('un champ vidé garde son nom d\'avant', (tester) async {
    final repo = _FakeLibraryRepo();
    await openDialog(tester, repo);

    await tester.enterText(find.byType(TextField).last, '');
    await settle(tester);
    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Enregistrer'),
    );
    expect(save.onPressed, isNull);
  });

  testWidgets('les tags qui résistent sont annoncés', (tester) async {
    final repo = _FakeLibraryRepo()
      ..reply = (artist, album) => AlbumEdit(
            albumId: 7,
            artistId: 2,
            artist: artist,
            album: album,
            changed: true,
            moved: true,
            renamed: false,
            merged: false,
            removedArtist: null,
            songs: 13,
            tagsWritten: 11,
            tagsFailed: 2,
          );
    await openDialog(tester, repo);

    await tester.enterText(find.byType(TextField).first, 'Catch 22');
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
    await settle(tester);

    expect(
      find.text('Album transféré à Catch 22 — tags de 2 fichiers inchangés'),
      findsOneWidget,
    );
  });

  testWidgets('un refus du serveur reste dans le dialogue', (tester) async {
    // Rien n'a changé : refermer obligerait à tout ressaisir, et le message
    // expliquant pourquoi serait perdu.
    final repo = _FakeLibraryRepo()
      ..failWith = ApiException('legacy_error', 'Album introuvable.');
    await openDialog(tester, repo);

    await tester.enterText(find.byType(TextField).first, 'Catch 22');
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
    await settle(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Album introuvable.'), findsOneWidget);
  });
}
