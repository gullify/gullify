// Idée #111 : découvrir de la musique sur Bandcamp — un genre, un sous-genre,
// puis ses nouveautés, un tirage au hasard ou ses meilleures ventes, et une
// liste de lecture qui passe par le lecteur principal (donc aussi la voiture
// et la télé). Ce qui se teste ici : que l'app demande au serveur ce qu'il
// faut, lise ses réponses, et que le même parcours existe dans Android Auto.
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/api_client.dart';
import 'package:gullify/api/bandcamp_repository.dart';
import 'package:gullify/api/library_repository.dart';
import 'package:gullify/audio/audio_handler.dart';
import 'package:gullify/screens/bandcamp_discover_screen.dart';
import 'package:gullify/state/bandcamp.dart';

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

  @override
  String resourceUrl(String relative) => 'https://exemple.test/$relative';
}

const _genres = [
  BcGenre(
    name: 'electronic',
    slug: 'electronic',
    subgenres: [
      BcGenre(name: 'house', slug: 'house'),
      BcGenre(name: 'drum & bass', slug: 'drum-bass'),
    ],
  ),
  BcGenre(name: 'hip-hop/rap', slug: 'hip-hop-rap'),
];

const _track = BcTrack(
  title: 'Lost in The Woods',
  artist: 'Varothar',
  album: 'Forêts',
  thumbnail: 'https://f4.bcbits.com/img/a1_2.jpg',
  url: 'https://varothar.bandcamp.com/album/forets',
  trackId: 1491657157,
  bandId: 974176246,
  itemId: 42,
  albumBandId: 555,
  duration: 308,
  released: '2026-09-18',
);

/// Un dépôt Bandcamp sans réseau, qui note ce qu'on lui a demandé.
class _FakeBandcamp extends Fake implements BandcampRepository {
  _FakeBandcamp({this.tracks = const [_track]});

  final List<BcTrack> tracks;
  final List<({String genre, String subgenre, BcSlice slice})> asked = [];

  @override
  Future<List<BcGenre>> genres() async => _genres;

  @override
  Future<BcDiscoverPage> discover({
    required String genre,
    String subgenre = '',
    BcSlice slice = BcSlice.fresh,
    int limit = 40,
    String cursor = '',
  }) async {
    asked.add((genre: genre, subgenre: subgenre, slice: slice));
    return BcDiscoverPage(tracks: tracks);
  }

  @override
  String trackUrl(BcTrack track) =>
      'https://exemple.test/bc/${track.bandId}/${track.trackId}';
}

GullifyAudioHandler _handler(_FakeBandcamp bandcamp) {
  final handler = GullifyAudioHandler()
    ..repository = LibraryRepository(ApiClient(serverUrl: 'https://exemple.test'))
    ..bandcampRepository = bandcamp;
  addTearDown(handler.player.dispose);
  return handler;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('dépôt', () {
    test('les genres arrivent avec leurs sous-genres', () async {
      final client = _FakeClient({
        'genres': [
          {
            'name': 'electronic',
            'slug': 'electronic',
            'subgenres': [
              {'name': 'house', 'slug': 'house'},
              {'name': 'sans tag', 'slug': ''},
            ],
          },
          {'name': 'sans tag', 'slug': ''},
        ],
      });

      final genres = await BandcampRepository(client).genres();

      expect(client.calls.single,
          {'path': 'download.php', 'action': 'bandcamp_genres'});
      expect(genres.map((g) => g.slug), ['electronic']);
      // Un sous-genre sans nom de tag ne se chercherait pas : écarté.
      expect(genres.single.subgenres.map((s) => s.slug), ['house']);
    });

    test('la découverte demande genre, sous-genre et façon de parcourir',
        () async {
      final client = _FakeClient({
        'tracks': [
          {
            'title': 'Lost in The Woods',
            'artist': 'Varothar',
            'album': 'Forêts',
            'thumbnail': '',
            'url': 'https://varothar.bandcamp.com/album/forets',
            'trackId': 1491657157,
            'bandId': 974176246,
            'itemId': 42,
            'albumBandId': 555,
            'itemType': 'a',
            'duration': 308,
            'released': '2026-09-18',
          },
          // Sans identifiant, le titre ne se jouerait pas : écarté.
          {'title': 'Rien', 'trackId': 0, 'bandId': 1},
        ],
        'cursor': 'abc',
      });

      final page = await BandcampRepository(client).discover(
        genre: 'metal',
        subgenre: 'black-metal',
        slice: BcSlice.random,
        limit: 30,
      );

      expect(client.calls.single, {
        'path': 'download.php',
        'action': 'bandcamp_discover',
        'genre': 'metal',
        'subgenre': 'black-metal',
        'slice': 'rand',
        'limit': '30',
      });
      expect(page.cursor, 'abc');
      expect(page.tracks, hasLength(1));
      expect(page.tracks.single.duration, 308);
    });

    test('tout le genre : pas de sous-genre dans la requête', () async {
      final client = _FakeClient({'tracks': []});

      await BandcampRepository(client).discover(genre: 'rock');

      expect(client.calls.single.containsKey('subgenre'), isFalse);
      expect(client.calls.single['slice'], 'new');
    });

    test('un titre joue par le proxy du serveur et désigne son album', () {
      final repo = BandcampRepository(
        ApiClient(serverUrl: 'https://exemple.test'),
      );

      expect(
        repo.trackUrl(_track),
        'https://exemple.test/api/download.php?action=bandcamp_preview'
        '&band_id=974176246&track_id=1491657157',
      );
      // Le téléchargement vise l'album, et par le groupe qui le vend (un
      // label, parfois), pas par celui qui joue le titre.
      final release = _track.release;
      expect(release.itemId, 42);
      expect(release.bandId, 555);
      expect(release.title, 'Forêts');
      expect(release.year, '2026');
    });

    test('les trois façons de parcourir se relisent depuis leur paramètre',
        () {
      for (final slice in BcSlice.values) {
        expect(BcSlice.fromParam(slice.param), slice);
      }
      expect(BcSlice.fromParam('n\'importe quoi'), BcSlice.fresh);
    });
  });

  group('Android Auto', () {
    test('l\'accueil propose « Découvrir sur Bandcamp »', () async {
      final handler = _handler(_FakeBandcamp());

      final home = await handler.getChildren(BrowseIds.home);

      final entry = home.where((i) => i.id == BrowseIds.bandcamp).single;
      expect(entry.title, 'Découvrir sur Bandcamp');
      expect(entry.playable, isFalse);
    });

    test('genres, puis de quoi lancer le genre, puis ses sous-genres',
        () async {
      final handler = _handler(_FakeBandcamp());

      final genres = await handler.getChildren(BrowseIds.bandcamp);
      expect(genres.map((i) => i.id),
          ['BC_GENRE_electronic', 'BC_GENRE_hip-hop-rap']);
      expect(genres.every((i) => i.playable == false), isTrue);

      final genre = await handler.getChildren('BC_GENRE_electronic');
      // Au volant, chaque cran compte : le genre se lance tout de suite.
      expect(genre.map((i) => i.id), [
        'BC_PLAY_electronic//new',
        'BC_PLAY_electronic//rand',
        'BC_SUB_electronic/house',
        'BC_SUB_electronic/drum-bass',
      ]);
      expect(genre.first.title, 'Nouveautés — tout electronic');
      expect(genre.take(2).every((i) => i.playable == true), isTrue);

      final sub = await handler.getChildren('BC_SUB_electronic/drum-bass');
      expect(sub.map((i) => i.id), [
        'BC_PLAY_electronic/drum-bass/new',
        'BC_PLAY_electronic/drum-bass/rand',
        'BC_PLAY_electronic/drum-bass/top',
      ]);
      // Le nom affiché, pas le nom de tag.
      expect(sub.first.title, 'Nouveautés — drum & bass');
    });

    test('lancer une liste demande le bon tirage à Bandcamp', () async {
      // Rien à jouer : on vérifie la requête sans lancer de lecture réelle.
      final bandcamp = _FakeBandcamp(tracks: const []);
      final handler = _handler(bandcamp);

      await handler.playFromMediaId('BC_PLAY_electronic/house/rand');

      expect(bandcamp.asked.single,
          (genre: 'electronic', subgenre: 'house', slice: BcSlice.random));
      // Rien trouvé : la voiture ne doit pas rester sur un chargement sans fin.
      expect(handler.playbackState.value.processingState,
          AudioProcessingState.idle);
    });

    test('un titre Bandcamp dans la file : titre, album, durée, pochette',
        () {
      final handler = _handler(_FakeBandcamp());

      final item = handler.bandcampMediaItem(_track, 'https://flux.test/1');

      expect(item.id, 'https://flux.test/1');
      expect(item.title, 'Lost in The Woods');
      expect(item.artist, 'Varothar');
      expect(item.album, 'Forêts');
      expect(item.duration, const Duration(seconds: 308));
      expect(item.artUri.toString(), 'https://f4.bcbits.com/img/a1_2.jpg');
      expect(item.extras?[kBandcampTrack], 'bc:1491657157');
      // Pas de songId : rien ici ne compte comme une écoute de la
      // bibliothèque.
      expect(item.extras?.containsKey('songId'), isFalse);
    });
  });

  group('écrans', () {
    Future<void> pump(
      WidgetTester tester,
      Widget screen, {
      _FakeBandcamp? bandcamp,
      Size size = const Size(360, 780),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bandcampRepositoryProvider
                .overrideWithValue(bandcamp ?? _FakeBandcamp()),
          ],
          child: MaterialApp(home: screen),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('les genres s\'affichent', (tester) async {
      await pump(tester, const BandcampGenresScreen());

      expect(find.text('electronic'), findsOneWidget);
      expect(find.text('hip-hop/rap'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un genre : « tout le genre » puis ses sous-genres',
        (tester) async {
      await pump(tester, const BandcampGenreScreen(genre: 'electronic'));

      expect(find.text('Tout electronic'), findsOneWidget);
      expect(find.text('house'), findsOneWidget);
      expect(find.text('drum & bass'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'la liste : nouveautés d\'abord, puis un autre tirage au choix — '
        'et elle tient sur un téléphone étroit', (tester) async {
      final bandcamp = _FakeBandcamp();
      await pump(
        tester,
        const BandcampPlaylistScreen(genre: 'electronic', subgenre: 'house'),
        bandcamp: bandcamp,
      );

      expect(find.text('house'), findsOneWidget);
      expect(find.text('Lost in The Woods'), findsOneWidget);
      expect(find.text('Varothar · Forêts'), findsOneWidget);
      expect(bandcamp.asked.last.slice, BcSlice.fresh);

      await tester.tap(find.text('Aléatoire'));
      await tester.pump();
      await tester.pump();

      expect(bandcamp.asked.last,
          (genre: 'electronic', subgenre: 'house', slice: BcSlice.random));
      expect(tester.takeException(), isNull);
    });

    test('l\'adresse de « tout le genre » ne se confond avec aucun tag', () {
      expect(bandcampListPath('rock'), '/bandcamp/rock/$kBcWholeGenre');
      expect(bandcampListPath('rock', 'grunge'), '/bandcamp/rock/grunge');
      expect(RegExp(r'^[a-z0-9]').hasMatch(kBcWholeGenre), isFalse);
    });
  });
}
