// Idée #110 : télécharger aussi depuis Bandcamp. La recherche a désormais
// trois sources (bibliothèque, YouTube, Bandcamp) ; ce qui se teste ici, c'est
// que l'app demande à Bandcamp ce qu'il faut, lise ses réponses, et fasse
// partir le téléchargement dans la MÊME file que YouTube.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/api_client.dart';
import 'package:gullify/api/bandcamp_repository.dart';
import 'package:gullify/api/library_repository.dart';
import 'package:gullify/api/yt_downloads_repository.dart';
import 'package:gullify/models/server_user.dart';
import 'package:gullify/screens/search_screen.dart';
import 'package:gullify/state/bandcamp.dart';
import 'package:gullify/state/library.dart';
import 'package:gullify/state/yt_downloads.dart';
import 'package:gullify/widgets/download_confirm.dart';

/// Un client qui note ce qu'on lui demande et rend une réponse fixe.
class _FakeClient extends Fake implements ApiClient {
  _FakeClient(this.response);

  final Map<String, dynamic> response;
  final List<Map<String, dynamic>> calls = [];

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    calls.add({'path': path, ...?query});
    return response;
  }
}

/// Requête de recherche fixée (le champ n'est pas tapé dans ces tests).
class _FixedQuery extends SearchQuery {
  _FixedQuery(this.q);

  final String q;

  @override
  String build() => q;
}

const _album = BcRelease(
  title: 'Slow Riot for New Zero Kanada',
  artist: 'Godspeed You Black Emperor!',
  year: '1999',
  thumbnail: '',
  url: 'https://gybe.bandcamp.com/album/slow-riot',
  itemId: 3803531554,
  bandId: 1687675700,
  itemType: 'a',
);

const _artist = BcArtist(
  name: 'Godspeed You! Black Emperor',
  bandId: 1687675700,
  thumbnail: '',
  location: 'Montreal, Québec',
);

const _song = BcSong(
  title: 'Moya',
  artist: 'Godspeed You Black Emperor!',
  album: 'Slow Riot for New Zero Kanada',
  thumbnail: '',
  url: 'https://gybe.bandcamp.com/track/moya',
  trackId: 1587484362,
  bandId: 1687675700,
);

const _resolved = BcResolved(
  url: 'https://gybe.bandcamp.com/album/slow-riot',
  artist: 'Godspeed You Black Emperor!',
  title: 'Slow Riot for New Zero Kanada',
  album: 'Slow Riot for New Zero Kanada',
  year: '1999',
  trackCount: 2,
  thumbnail: '',
  isTrack: false,
);

/// Un dépôt Bandcamp sans réseau, qui note ce qu'on lui a demandé.
class _FakeBandcamp extends Fake implements BandcampRepository {
  _FakeBandcamp({this.albums = const [_album]});

  final List<BcRelease> albums;
  final List<BcSong> songs = const [_song];
  final List<BcArtist> artists = const [_artist];
  final BcResolved resolved = _resolved;

  final List<int> discographyOf = [];
  Map<String, Object>? resolveArgs;

  @override
  Future<List<BcRelease>> searchAlbums(String query, {int limit = 10}) async =>
      albums;

  @override
  Future<List<BcSong>> searchSongs(String query, {int limit = 10}) async =>
      songs;

  @override
  Future<List<BcArtist>> searchArtists(String query, {int limit = 10}) async =>
      artists;

  @override
  Future<List<BcRelease>> artistAlbums(int bandId, {int limit = 50}) async {
    discographyOf.add(bandId);
    return albums;
  }

  @override
  Future<BcResolved> resolve({
    int bandId = 0,
    int itemId = 0,
    String itemType = 'a',
    String url = '',
  }) async {
    resolveArgs = {
      'bandId': bandId,
      'itemId': itemId,
      'itemType': itemType,
      'url': url,
    };
    return resolved;
  }
}

/// La file de téléchargement : la même que pour YouTube.
class _FakeQueue extends Fake implements YtDownloadsRepository {
  Map<String, Object>? started;

  @override
  Future<List<ServerDownload>> list() async => const [];

  @override
  Future<YtDuplicate?> checkDuplicate({
    String artist = '',
    String album = '',
    String url = '',
    String title = '',
  }) async =>
      null;

  @override
  Future<String> start({
    required String url,
    required String artistName,
    required String albumName,
    String title = '',
    bool force = false,
  }) async {
    started = {
      'url': url,
      'artist': artistName,
      'album': albumName,
      'title': title,
      'force': force,
    };
    return 'dl_1';
  }
}

/// L'écran de recherche, requête déjà saisie, source Bandcamp choisie.
Future<void> _pumpBandcamp(
  WidgetTester tester, {
  required _FakeBandcamp bandcamp,
  _FakeQueue? queue,
  Size size = const Size(412, 892),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bandcampRepositoryProvider.overrideWithValue(bandcamp),
        ytDownloadsRepositoryProvider.overrideWithValue(queue ?? _FakeQueue()),
        searchQueryProvider.overrideWith(() => _FixedQuery('godspeed')),
        searchResultsProvider.overrideWith((ref) async => const SearchResults()),
        serverUsersProvider.overrideWith((ref) async => const <ServerUser>[]),
      ],
      child: const MaterialApp(home: SearchScreen()),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('Bandcamp'));
  await tester.pump();
  await tester.pump();
}

void main() {
  group('dépôt', () {
    test('la recherche d\'albums demande la bonne page', () async {
      final client = _FakeClient({
        'albums': [
          {
            'title': 'Slow Riot for New Zero Kanada',
            'artist': 'Godspeed You Black Emperor!',
            'year': '',
            'thumbnail': 'https://f4.bcbits.com/img/a565708888_2.jpg',
            'url': 'https://gybe.bandcamp.com/album/slow-riot',
            'itemId': 3803531554,
            'bandId': 1687675700,
            'itemType': 'a',
            'in_library': true,
          },
          // Sans titre, la sortie n'est pas montrable : on l'écarte.
          {'title': '', 'url': 'https://gybe.bandcamp.com/album/x'},
        ],
      });

      final albums =
          await BandcampRepository(client).searchAlbums('godspeed', limit: 12);

      expect(client.calls.single, {
        'path': 'download.php',
        'action': 'search_bandcamp',
        'type': 'albums',
        'query': 'godspeed',
        'limit': '12',
      });
      expect(albums, hasLength(1));
      expect(albums.single.itemId, 3803531554);
      expect(albums.single.inLibrary, isTrue);
      expect(albums.single.isTrack, isFalse);
    });

    test('un titre porte son identité de pré-écoute et son flux', () async {
      final client = _FakeClient({
        'songs': [
          {
            'title': 'Moya',
            'artist': 'Godspeed You Black Emperor!',
            'album': 'Slow Riot for New Zero Kanada',
            'thumbnail': '',
            'url': 'https://gybe.bandcamp.com/track/moya',
            'itemId': 1587484362,
            'bandId': 1687675700,
            'itemType': 't',
          },
        ],
      });
      final repo = BandcampRepository(client);
      final songs = await repo.searchSongs('moya');

      expect(songs.single.previewId, 'bc:1587484362');
      // L'identité ne peut pas se confondre avec un identifiant YouTube.
      expect(songs.single.previewId.startsWith('bc:'), isTrue);

      expect(
        BandcampRepository(ApiClient(serverUrl: 'https://exemple.test'))
            .previewUrl(songs.single),
        'https://exemple.test/api/download.php?action=bandcamp_preview'
        '&band_id=1687675700&track_id=1587484362',
      );
    });

    test('la résolution passe par les identifiants quand elle les a',
        () async {
      final client = _FakeClient({
        'url': 'https://gybe.bandcamp.com/track/moya',
        'artist': 'Godspeed You Black Emperor!',
        'title': 'Moya',
        'album': '',
        'year': '1999',
        'track_count': 1,
        'thumbnail': '',
        'is_track': true,
      });
      final repo = BandcampRepository(client);

      final byIds = await repo.resolve(
        bandId: 1687675700,
        itemId: 1587484362,
        itemType: 't',
        url: 'https://gybe.bandcamp.com/track/moya',
      );
      expect(client.calls.single['band_id'], '1687675700');
      expect(client.calls.single.containsKey('url'), isFalse);
      // Un titre sans album rejoint « Singles », comme sur YouTube.
      expect(byIds.albumName, 'Singles');

      // Lien collé : rien d'autre à envoyer que l'URL.
      await repo.resolve(url: 'https://gybe.bandcamp.com/track/moya');
      expect(client.calls.last['url'], 'https://gybe.bandcamp.com/track/moya');
      expect(client.calls.last.containsKey('band_id'), isFalse);
    });
  });

  group('écran de recherche', () {
    testWidgets('la source Bandcamp montre artistes, titres et albums',
        (tester) async {
      await _pumpBandcamp(tester, bandcamp: _FakeBandcamp());

      expect(find.text('Godspeed You! Black Emperor'), findsOneWidget);
      expect(find.text('Artiste · Montreal, Québec'), findsOneWidget);
      expect(find.text('Moya'), findsOneWidget);
      expect(
        find.text('Slow Riot for New Zero Kanada'),
        findsOneWidget, // l'album ; le titre affiche le sien en sous-titre
      );
      expect(
        find.text('Godspeed You Black Emperor! · 1999 · Album'),
        findsOneWidget,
      );
    });

    testWidgets('les trois sources tiennent sur un téléphone étroit',
        (tester) async {
      // Un segment qui déborde lèverait une exception de layout ici.
      await _pumpBandcamp(
        tester,
        bandcamp: _FakeBandcamp(),
        size: const Size(360, 780),
      );

      expect(find.text('Bibliothèque'), findsOneWidget);
      expect(find.text('YouTube'), findsOneWidget);
      expect(find.text('Bandcamp'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('une sortie déjà rangée porte sa pastille', (tester) async {
      await _pumpBandcamp(
        tester,
        bandcamp: _FakeBandcamp(albums: const [
          BcRelease(
            title: 'Slow Riot for New Zero Kanada',
            artist: 'Godspeed You Black Emperor!',
            year: '1999',
            thumbnail: '',
            url: 'https://gybe.bandcamp.com/album/slow-riot',
            itemId: 3803531554,
            bandId: 1687675700,
            itemType: 'a',
            inLibrary: true,
          ),
        ]),
      );

      expect(find.byType(InLibraryBadge), findsOneWidget);
    });

    testWidgets('un artiste tapé ouvre sa discographie', (tester) async {
      final bandcamp = _FakeBandcamp();
      await _pumpBandcamp(tester, bandcamp: bandcamp);

      await tester.tap(find.text('Godspeed You! Black Emperor'));
      await tester.pump();
      await tester.pump();

      expect(bandcamp.discographyOf, [1687675700]);
      expect(find.text('Discographie'), findsOneWidget);
      // En discographie, l'artiste ne se répète pas sous chaque sortie.
      expect(find.text('1999 · Album'), findsOneWidget);
    });

    testWidgets('un album tapé est résolu puis mis dans la file',
        (tester) async {
      final bandcamp = _FakeBandcamp();
      final queue = _FakeQueue();
      await _pumpBandcamp(tester, bandcamp: bandcamp, queue: queue);

      await tester.tap(find.text('Godspeed You Black Emperor! · 1999 · Album'));
      await tester.pumpAndSettle();

      // La résolution part avec les identifiants de la recherche.
      expect(bandcamp.resolveArgs?['bandId'], 1687675700);
      expect(bandcamp.resolveArgs?['itemId'], 3803531554);

      // La fenêtre de confirmation annonce la sortie avant de rien lancer.
      expect(find.text('1999 · 2 pistes · Bandcamp'), findsOneWidget);
      expect(queue.started, isNull);

      await tester.tap(find.widgetWithText(FilledButton, 'Télécharger'));
      await tester.pumpAndSettle();

      expect(queue.started, {
        'url': 'https://gybe.bandcamp.com/album/slow-riot',
        'artist': 'Godspeed You Black Emperor!',
        'album': 'Slow Riot for New Zero Kanada',
        'title': '',
        'force': false,
      });
    });

    testWidgets('un titre tapé rejoint la file sous son propre nom',
        (tester) async {
      final bandcamp = _FakeBandcamp();
      final queue = _FakeQueue();
      await _pumpBandcamp(tester, bandcamp: bandcamp, queue: queue);

      await tester.tap(find.byTooltip('Télécharger').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Télécharger'));
      await tester.pumpAndSettle();

      expect(queue.started, {
        'url': 'https://gybe.bandcamp.com/track/moya',
        'artist': 'Godspeed You Black Emperor!',
        'album': 'Slow Riot for New Zero Kanada',
        'title': 'Moya',
        'force': false,
      });
      // Un titre seul ne passe pas par la résolution : il a déjà son lien.
      expect(bandcamp.resolveArgs, isNull);
    });
  });
}
