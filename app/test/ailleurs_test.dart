// La lecture automatique sort de la bibliothèque (serveur 1.21.0, app 3.95.0) :
// la suite mêlée (bibliothèque + titres d'ailleurs), leurs fiches dans la
// file, et le bouton « Télécharger » du lecteur.
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/api_client.dart';
import 'package:gullify/api/bandcamp_repository.dart';
import 'package:gullify/api/library_repository.dart';
import 'package:gullify/api/pour_toi_repository.dart';
import 'package:gullify/api/yt_downloads_repository.dart';
import 'package:gullify/audio/audio_handler.dart';
import 'package:gullify/widgets/download_ailleurs_button.dart';

class _FakeClient extends ApiClient {
  _FakeClient(this.reponse) : super(serverUrl: 'https://maison.test');

  final Map<String, dynamic> reponse;
  final demandes = <Map<String, dynamic>>[];

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    demandes.add({...?query});
    return reponse;
  }
}

const _yt = TitreAilleurs(
  source: 'youtube',
  title: 'Demain, demain',
  artist: 'Thierry Larose',
  url: 'https://music.youtube.com/watch?v=abc123',
  videoId: 'abc123',
  album: 'Cantalou',
  thumbnail: 'https://lh3.test/x.jpg',
  duration: 272,
  origin: 'auto:ailleurs',
  raison: 'Proche de Pierre Lapointe, hors de ta bibliothèque',
);

const _bc = TitreAilleurs(
  source: 'bandcamp',
  title: 'Forêt',
  artist: 'Les Hay Babies',
  url: 'https://hb.bandcamp.com/track/foret',
  trackId: 77,
  bandId: 9,
);

GullifyAudioHandler _handler() {
  final client = ApiClient(serverUrl: 'https://maison.test');
  final handler = GullifyAudioHandler()
    ..repository = LibraryRepository(client)
    ..ytRepository = YtDownloadsRepository(client)
    ..bandcampRepository = BandcampRepository(client);
  addTearDown(handler.player.dispose);
  return handler;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('la suite mêlée : bibliothèque et ailleurs, dans l\'ordre du serveur',
      () async {
    final c = _FakeClient({
      'titres': [
        {
          'id': 12,
          'title': 'Tokébakicitte',
          'duration': 201,
          'filePath': 'a/b.mp3',
          'artistName': 'Jérôme 50',
          'origin': 'auto:voisins',
        },
        {
          'externe': 'youtube',
          'videoId': 'abc123',
          'title': 'Demain, demain',
          'artist': 'Thierry Larose',
          'url': 'https://music.youtube.com/watch?v=abc123',
          'duration': 272,
          'raison': 'Proche de Pierre Lapointe, hors de ta bibliothèque',
        },
        {
          'externe': 'bandcamp',
          'trackId': 77,
          'bandId': 9,
          'title': 'Forêt',
          'artist': 'Les Hay Babies',
          'url': 'https://hb.bandcamp.com/track/foret',
        },
      ],
    });
    final repo = PourToiRepository(c, LibraryRepository(c));
    final suite = await repo.suiteMixte(
      graines: [1, 2],
      artistes: ['Pierre Lapointe', 'Jean Leloup'],
      exclus: [1, 2],
      exclusAilleurs: ['yt:zzz', 'bc:5'],
    );
    expect(suite, hasLength(3));
    expect(suite[0].reco?.song.title, 'Tokébakicitte');
    expect(suite[1].ailleurs?.videoId, 'abc123');
    expect(suite[1].ailleurs?.isBandcamp, isFalse);
    expect(suite[2].ailleurs?.isBandcamp, isTrue);
    expect(suite[2].ailleurs?.jouable, isTrue);
    final q = c.demandes.single;
    expect(q['ailleurs'], '1');
    expect(q['artistes'], 'Pierre Lapointe\nJean Leloup');
    expect(q['exclus_ext'], 'yt:zzz,bc:5');
  });

  test('identité d\'un titre d\'ailleurs dans la file', () {
    expect(ailleursKeyOf({kPreviewVideoId: 'abc'}), 'yt:abc');
    // Pré-écoute Bandcamp lancée de la recherche : déjà préfixée.
    expect(ailleursKeyOf({kPreviewVideoId: 'bc:9'}), 'bc:9');
    expect(ailleursKeyOf({kBandcampTrack: 'bc:7'}), 'bc:7');
    expect(ailleursKeyOf({'songId': 4}), isNull);
    expect(ailleursKeyOf(null), isNull);
  });

  test('fiche YouTube dans la file : flux du proxy, album, raison', () {
    final item = _handler().ailleursMediaItem(_yt)!;
    expect(item.id, contains('action=preview'));
    expect(item.id, contains('video_id=abc123'));
    expect(item.album, 'Cantalou');
    expect(item.duration, const Duration(seconds: 272));
    expect(item.extras?[kPreviewVideoId], 'abc123');
    expect(item.extras?[kSourceAlbum], 'Cantalou');
    expect(item.extras?[kAilleursRaison], startsWith('Proche de'));
    expect(item.extras?.containsKey('songId'), isFalse);
  });

  test('fiche Bandcamp dans la file : flux du proxy et page à télécharger',
      () {
    final item = _handler().ailleursMediaItem(_bc)!;
    expect(item.id, contains('action=bandcamp_preview'));
    expect(item.id, contains('band_id=9&track_id=77'));
    expect(item.album, 'Bandcamp');
    expect(item.duration, isNull);
    expect(item.extras?[kBandcampTrack], 'bc:77');
    expect(item.extras?['bcUrl'], 'https://hb.bandcamp.com/track/foret');
  });

  test('sans dépôt lié, pas de fiche', () {
    final handler = GullifyAudioHandler();
    addTearDown(handler.player.dispose);
    expect(handler.ailleursMediaItem(_yt), isNull);
  });

  group('téléchargement depuis le lecteur', () {
    test('YouTube : la page watch, rangé dans « Singles » sans album', () {
      final dl = AilleursDownload.of(
        const MediaItem(
          id: 'x',
          title: 't',
          album: 'Pré-écoute YouTube',
          extras: {kPreviewVideoId: 'abc'},
        ),
      )!;
      expect(dl.url, 'https://music.youtube.com/watch?v=abc');
      expect(dl.album, 'Singles');
      expect(dl.source, 'YouTube Music');
    });

    test('Bandcamp : sa page et son album ; sans page, rien à proposer', () {
      final dl = AilleursDownload.of(
        const MediaItem(
          id: 'x',
          title: 't',
          extras: {
            kBandcampTrack: 'bc:7',
            'bcUrl': 'https://hb.bandcamp.com/track/foret',
            kSourceAlbum: 'Mon homesick heart',
          },
        ),
      )!;
      expect(dl.url, 'https://hb.bandcamp.com/track/foret');
      expect(dl.album, 'Mon homesick heart');
      expect(
        AilleursDownload.of(
          const MediaItem(id: 'x', title: 't', extras: {kBandcampTrack: 'bc:7'}),
        ),
        isNull,
      );
    });

    Future<void> pump(WidgetTester tester, MediaItem item) =>
        tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(body: DownloadAilleursButton(item: item)),
            ),
          ),
        );

    testWidgets('le bouton n\'apparaît que pour un titre d\'ailleurs',
        (tester) async {
      await pump(
        tester,
        const MediaItem(id: 'x', title: 't', extras: {'songId': 3}),
      );
      expect(find.byIcon(Icons.download_rounded), findsNothing);

      await pump(
        tester,
        const MediaItem(id: 'y', title: 't', extras: {kPreviewVideoId: 'a'}),
      );
      expect(find.byIcon(Icons.download_rounded), findsOneWidget);
      expect(
        find.byTooltip('Télécharger dans ma bibliothèque'),
        findsOneWidget,
      );
    });
  });
}
