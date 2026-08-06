// Idée #69 : ne plus télécharger deux fois le même album. Le serveur signale
// ce qu'il a déjà (bibliothèque ou file en cours), l'app le dit avant de
// lancer quoi que ce soit — et ne force que si l'utilisateur insiste.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/api_client.dart';
import 'package:gullify/api/yt_downloads_repository.dart';
import 'package:gullify/state/yt_downloads.dart';
import 'package:gullify/widgets/download_confirm.dart';

/// Un dépôt qui note ce qu'on lui demande, sans réseau.
class _Repository extends YtDownloadsRepository {
  _Repository() : super(ApiClient(serverUrl: 'https://exemple.test'));

  bool? forcedStart;

  @override
  Future<List<ServerDownload>> list() async => const [];

  @override
  Future<String> start({
    required String url,
    required String artistName,
    required String albumName,
    String title = '',
    bool force = false,
  }) async {
    forcedStart = force;
    return 'dl_1';
  }

  @override
  Future<String> startUrl(String url, {bool force = false}) async {
    forcedStart = force;
    return 'dl_2';
  }
}

const _album = YtResolvedAlbum(
  playlistUrl: 'https://music.youtube.com/playlist?list=X',
  artist: 'Philippe Katerine',
  title: 'Magnum',
  year: '2005',
  trackCount: 12,
  thumbnail: '',
);

/// Ouvre la fenêtre de confirmation. La liste renvoyée reçoit la réponse de
/// l'utilisateur une fois qu'il a tapé (elle est donc vide à l'ouverture).
Future<List<bool>> _openConfirm(
  WidgetTester tester, {
  YtDuplicate? duplicate,
}) async {
  final answers = <bool>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            answers.add(await showDownloadConfirm(
              context,
              title: 'Magnum',
              subtitle: 'Philippe Katerine',
              details: '2005 · 12 pistes',
              body: 'Le serveur télécharge cet album.',
              duplicate: duplicate,
            ));
          },
          child: const Text('ouvrir'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();
  return answers;
}

void main() {
  test('un album déjà téléchargé arrive marqué du serveur', () {
    final marked = YtAlbum.fromJson(const {
      'title': 'Magnum',
      'artist': 'Philippe Katerine',
      'browseId': 'MPREb_x',
      'in_library': true,
    });
    expect(marked.inLibrary, isTrue);

    // Sans le champ (ancien serveur), on ne prétend rien.
    final plain = YtAlbum.fromJson(const {'title': 'Magnum', 'browseId': 'x'});
    expect(plain.inLibrary, isFalse);
  });

  test('une chanson déjà en bibliothèque est marquée elle aussi', () {
    final s = YtSong.fromJson(const {
      'title': 'Le simplet',
      'artist': 'Philippe Katerine',
      'videoId': 'abc',
      'in_library': true,
    });
    expect(s.inLibrary, isTrue);
    expect(YtSong.fromJson(const {'videoId': 'abc'}).inLibrary, isFalse);
  });

  test('le doublon dit d\'où il vient', () {
    final library = YtDuplicate.fromJson(const {
      'kind': 'library',
      'artist': 'Philippe Katerine',
      'album': 'Magnum',
      'track_count': 12,
      'message': '« Magnum » est déjà dans la bibliothèque (12 pistes).',
    });
    expect(library.isQueued, isFalse);
    expect(library.trackCount, 12);

    final queued = YtDuplicate.fromJson(const {'kind': 'queue'});
    expect(queued.isQueued, isTrue);
  });

  testWidgets('sans doublon, la fenêtre propose simplement de télécharger',
      (tester) async {
    final answers = await _openConfirm(tester);
    expect(find.text('Télécharger'), findsOneWidget);
    expect(find.text('Télécharger quand même'), findsNothing);

    await tester.tap(find.text('Télécharger'));
    await tester.pumpAndSettle();
    expect(answers, [true]);
  });

  testWidgets('album déjà là : la fenêtre prévient et fait insister',
      (tester) async {
    final answers = await _openConfirm(
      tester,
      duplicate: const YtDuplicate(
        kind: 'library',
        artist: 'Philippe Katerine',
        album: 'Magnum',
        trackCount: 12,
        message: '« Magnum » de Philippe Katerine est déjà dans la '
            'bibliothèque (12 pistes).',
      ),
    );
    expect(find.textContaining('déjà dans la bibliothèque'), findsOneWidget);
    expect(find.text('Télécharger'), findsNothing);

    await tester.tap(find.text('Télécharger quand même'));
    await tester.pumpAndSettle();
    expect(answers, [true]);
  });

  testWidgets('déjà en file : rien à forcer, on ne peut que fermer',
      (tester) async {
    final answers = await _openConfirm(
      tester,
      duplicate: const YtDuplicate(
        kind: 'queue',
        artist: 'Philippe Katerine',
        album: 'Magnum',
        trackCount: 0,
        message: '« Magnum » est déjà en cours de téléchargement.',
      ),
    );
    expect(find.textContaining('déjà en cours'), findsOneWidget);
    expect(find.text('Télécharger quand même'), findsNothing);
    expect(find.text('Télécharger'), findsNothing);

    await tester.tap(find.text('Fermer'));
    await tester.pumpAndSettle();
    expect(answers, [false]);
  });

  test('« quand même » atteint bien le serveur', () async {
    final repo = _Repository();
    final container = ProviderContainer(
      overrides: [ytDownloadsRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    await container.read(ytQueueProvider.future);

    await container.read(ytQueueProvider.notifier).start(_album);
    expect(repo.forcedStart, isFalse);

    await container.read(ytQueueProvider.notifier).start(_album, force: true);
    expect(repo.forcedStart, isTrue);

    await container.read(ytQueueProvider.notifier).startUrl('https://y', force: true);
    expect(repo.forcedStart, isTrue);
  });
}
