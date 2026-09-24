// Idée #112 : les podcasts — chercher une série, s'y abonner, ouvrir ses
// épisodes comme on ouvre un artiste, et reprendre un épisode là où on l'a
// laissé. Ce qui se teste ici : ce que l'app demande au serveur, ce qu'elle
// lit dans ses réponses, la fiche d'un épisode dans le lecteur, la position
// d'écoute retenue en fond, et les deux écrans.
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/api_client.dart';
import 'package:gullify/api/podcasts_repository.dart';
import 'package:gullify/audio/audio_handler.dart';
import 'package:gullify/screens/podcast_show_screen.dart';
import 'package:gullify/screens/podcasts_screen.dart';
import 'package:gullify/state/player.dart';
import 'package:gullify/state/podcasts.dart';

/// Un client qui note ce qu'on lui demande et rend une réponse fixe.
class _FakeClient extends Fake implements ApiClient {
  _FakeClient(this.response);

  final dynamic response;
  final List<Map<String, dynamic>> calls = [];

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    calls.add({'path': path, ...?query});
    return response;
  }

  @override
  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? form,
    Map<String, dynamic>? query,
  }) async {
    calls.add({'path': path, ...?query, 'body': body});
    return response;
  }
}

const _show = PodcastShow(
  feedUrl: 'https://exemple.org/flux.xml',
  title: 'Ma Série',
  author: 'Radio Gullify',
  image: 'https://exemple.org/art.jpg',
  description: 'Une série de test',
  genre: 'Musique',
  itunesId: 42,
  episodeCount: 120,
);

/// Publié le 23 septembre 2026 à midi UTC.
const _publishedAt = 1790510400;

const _episodes = [
  PodcastEpisode(
    guid: 'ep-2',
    title: 'Épisode récent',
    audioUrl: 'https://exemple.org/2.mp3',
    duration: 1800,
    publishedAt: _publishedAt,
    image: 'https://exemple.org/ep2.jpg',
    position: 600,
  ),
  PodcastEpisode(
    guid: 'ep-1',
    title: 'Vieil épisode',
    audioUrl: 'https://exemple.org/1.mp3',
    duration: 1530,
    publishedAt: _publishedAt - 86400,
    completed: true,
  ),
];

/// Un dépôt sans réseau, qui note ce qu'on lui a demandé.
class _FakePodcasts extends Fake implements PodcastsRepository {
  _FakePodcasts({
    this.subscribed = const [_show],
    this.episodesOf = _episodes,
    this.frenchEmpty = false,
  });

  List<PodcastShow> subscribed;
  final List<PodcastEpisode> episodesOf;

  /// Rien de francophone à proposer : le cas d'un palmarès tout en anglais.
  final bool frenchEmpty;
  final List<String> asked = [];
  final List<Map<String, dynamic>> saved = [];

  @override
  Future<List<PodcastGenre>> genres() async => const [
        PodcastGenre(id: 1488, name: 'Crimes réels'),
        PodcastGenre(id: 1310, name: 'Musique'),
      ];

  @override
  Future<List<PodcastShow>> subscriptions() async {
    asked.add('subscriptions');
    return subscribed;
  }

  @override
  Future<List<PodcastShow>> search(
    String query, {
    int limit = 25,
    bool frenchOnly = false,
  }) async {
    asked.add(frenchOnly ? 'search:$query:fr' : 'search:$query');
    if (frenchOnly && frenchEmpty) return const [];
    return [_show.copyWith(subscribed: false)];
  }

  @override
  Future<List<PodcastShow>> discover(
    int genreId, {
    int limit = 30,
    bool frenchOnly = false,
  }) async {
    asked.add(frenchOnly ? 'discover:$genreId:fr' : 'discover:$genreId');
    if (frenchOnly && frenchEmpty) return const [];
    return [_show.copyWith(subscribed: false)];
  }

  @override
  Future<PodcastFeed> episodes(
    String feedUrl, {
    int limit = 100,
    bool refresh = false,
  }) async {
    asked.add('episodes:$feedUrl');
    return PodcastFeed(show: _show, episodes: episodesOf);
  }

  @override
  Future<void> subscribe(PodcastShow show) async {
    asked.add('subscribe:${show.feedUrl}');
    subscribed = [...subscribed, show];
  }

  @override
  Future<void> unsubscribe(String feedUrl) async {
    asked.add('unsubscribe:$feedUrl');
    subscribed = [
      for (final s in subscribed)
        if (s.feedUrl != feedUrl) s,
    ];
  }

  @override
  Future<void> saveProgress({
    required String feedUrl,
    required String guid,
    required int position,
    int duration = 0,
    bool completed = false,
  }) async {
    saved.add({
      'feedUrl': feedUrl,
      'guid': guid,
      'position': position,
      'duration': duration,
      'completed': completed,
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('dépôt', () {
    test('la recherche interroge l\'annuaire et lit les séries', () async {
      final client = _FakeClient([
        {
          'feedUrl': 'https://exemple.org/flux.xml',
          'title': 'Ma Série',
          'author': 'Radio Gullify',
          'image': 'https://exemple.org/art.jpg',
          'genre': 'Musique',
          'itunesId': 42,
          'episodeCount': 120,
          'subscribed': true,
        },
        // Sans flux, rien à écouter : la fiche arrive quand même vide, c'est
        // au serveur de l'écarter — on vérifie juste qu'on ne s'y casse pas.
        {'title': 'Sans flux'},
      ]);

      final shows = await PodcastsRepository(client).search('gullify');

      expect(client.calls.single, {
        'path': 'podcasts.php',
        'action': 'search',
        'q': 'gullify',
        'limit': 25,
      });
      expect(shows, hasLength(2));
      expect(shows.first.title, 'Ma Série');
      expect(shows.first.subscribed, isTrue);
      expect(shows.first.episodeCount, 120);
      expect(shows.last.feedUrl, '');
    });

    test('le palmarès se demande par catégorie', () async {
      final client = _FakeClient(const []);

      await PodcastsRepository(client).discover(1310);

      expect(client.calls.single, {
        'path': 'podcasts.php',
        'action': 'discover',
        'genre': 1310,
        'limit': 30,
      });
    });

    test('« francophone seulement » voyage jusqu\'au serveur', () async {
      final client = _FakeClient(const []);
      final repo = PodcastsRepository(client);

      await repo.search('histoire', frenchOnly: true);
      await repo.discover(1310, frenchOnly: true);

      expect(client.calls.first, {
        'path': 'podcasts.php',
        'action': 'search',
        'q': 'histoire',
        'limit': 25,
        'french': '1',
      });
      expect(client.calls.last, {
        'path': 'podcasts.php',
        'action': 'discover',
        'genre': 1310,
        'limit': 30,
        'french': '1',
      });
      // Sans le filtre, rien de plus dans la requête : c'est le palmarès
      // d'Apple tel quel.
      await repo.discover(1310);
      expect(client.calls.last.containsKey('french'), isFalse);
    });

    test('les épisodes arrivent avec la série et l\'avancement', () async {
      final client = _FakeClient({
        'show': {
          'feedUrl': 'https://exemple.org/flux.xml',
          'title': 'Ma Série',
          'subscribed': true,
        },
        'episodes': [
          {
            'guid': 'ep-2',
            'title': 'Épisode récent',
            'audioUrl': 'https://exemple.org/2.mp3',
            'duration': 1800,
            'publishedAt': _publishedAt,
            'position': 600,
            'completed': false,
            'episode': 12,
            'season': 2,
          },
        ],
      });

      final feed = await PodcastsRepository(client)
          .episodes('https://exemple.org/flux.xml');

      expect(client.calls.single, {
        'path': 'podcasts.php',
        'action': 'episodes',
        'feed': 'https://exemple.org/flux.xml',
        'limit': 100,
      });
      expect(feed.show.subscribed, isTrue);
      final episode = feed.episodes.single;
      expect(episode.title, 'Épisode récent');
      expect(episode.number, 12);
      expect(episode.season, 2);
      expect(episode.position, 600);
      expect(episode.published, isNotNull);
    });

    test('s\'abonner envoie la fiche de la série', () async {
      final client = _FakeClient(null);

      await PodcastsRepository(client).subscribe(_show);

      expect(client.calls.single['action'], 'subscribe');
      expect(
        client.calls.single['body'],
        containsPair('feedUrl', 'https://exemple.org/flux.xml'),
      );
      expect(client.calls.single['body'], containsPair('itunesId', 42));
    });

    test('une adresse de flux vide n\'interroge pas l\'annuaire', () async {
      final client = _FakeClient(const []);

      final shows = await PodcastsRepository(client).search('');

      expect(shows, isEmpty);
      expect(client.calls.single['q'], '');
    });
  });

  group('reprise d\'un épisode', () {
    test('un épisode entamé se reprend, pas un épisode fini', () {
      const started = PodcastEpisode(
        guid: 'a',
        title: 'a',
        audioUrl: 'https://exemple.org/a.mp3',
        duration: 1800,
        position: 600,
      );
      expect(started.resumable, isTrue);
      expect(started.startAt, const Duration(seconds: 600));
      expect(started.progress, closeTo(0.333, 0.01));

      // Les premières secondes ne comptent pas : on n'a rien manqué.
      expect(started.copyAt(10).resumable, isFalse);
      expect(started.copyAt(10).startAt, Duration.zero);
      // Ni la toute fin : ce qui reste, c'est le générique.
      expect(started.copyAt(1790).resumable, isFalse);
      // Un épisode écouté repart du début.
      expect(_episodes[1].resumable, isFalse);
      expect(_episodes[1].progress, 1);
      // Rien d'écouté : aucune barre à afficher.
      expect(started.copyAt(0).progress, isNull);
    });
  });

  group('lecteur', () {
    test('un épisode dans la file : série, durée, pochette et repères', () {
      final handler = GullifyAudioHandler();
      addTearDown(handler.player.dispose);

      final item = handler.podcastMediaItem(
        _episodes.first,
        feedUrl: _show.feedUrl,
        showTitle: _show.title,
        showImage: _show.image,
      );

      expect(item.id, 'https://exemple.org/2.mp3');
      expect(item.title, 'Épisode récent');
      expect(item.artist, 'Ma Série');
      expect(item.album, 'Podcast');
      expect(item.duration, const Duration(seconds: 1800));
      expect(item.artUri.toString(), 'https://exemple.org/ep2.jpg');
      expect(item.extras?[kPodcastEpisode], 'ep-2');
      expect(item.extras?[kPodcastFeed], 'https://exemple.org/flux.xml');
      // Pas de songId : un épisode n'est pas une écoute de la bibliothèque.
      expect(item.extras?.containsKey('songId'), isFalse);
    });

    test('sans image propre, l\'épisode porte la pochette de la série', () {
      final handler = GullifyAudioHandler();
      addTearDown(handler.player.dispose);

      final item = handler.podcastMediaItem(
        _episodes[1],
        feedUrl: _show.feedUrl,
        showTitle: _show.title,
        showImage: _show.image,
      );

      expect(item.artUri.toString(), 'https://exemple.org/art.jpg');
    });
  });

  group('position retenue', () {
    /// Le suivi branché sur des flux de test : ce que le lecteur annonce, et
    /// ce que le dépôt reçoit.
    ({
      _FakePodcasts repo,
      StreamController<MediaItem?> items,
      StreamController<Duration> positions,
      ProviderContainer container,
    }) rig() {
      final repo = _FakePodcasts();
      final items = StreamController<MediaItem?>.broadcast();
      final positions = StreamController<Duration>.broadcast();
      final container = ProviderContainer(
        overrides: [
          podcastsRepositoryProvider.overrideWithValue(repo),
          currentMediaItemProvider.overrideWith((ref) => items.stream),
          positionProvider.overrideWith((ref) => positions.stream),
        ],
      );
      container.listen(podcastProgressSyncProvider, (_, _) {});
      addTearDown(() {
        container.dispose();
        items.close();
        positions.close();
      });
      return (
        repo: repo,
        items: items,
        positions: positions,
        container: container,
      );
    }

    MediaItem episodeItem({Duration? duration}) => MediaItem(
          id: 'https://exemple.org/2.mp3',
          title: 'Épisode récent',
          duration: duration ?? const Duration(seconds: 1800),
          extras: const {
            kPodcastEpisode: 'ep-2',
            kPodcastFeed: 'https://exemple.org/flux.xml',
          },
        );

    test('la position part toutes les vingt secondes', () async {
      final r = rig();
      r.items.add(episodeItem());
      await pumpEventQueue();

      r.positions.add(const Duration(seconds: 5));
      await pumpEventQueue();
      expect(r.repo.saved, isEmpty, reason: 'trop tôt pour écrire');

      r.positions.add(const Duration(seconds: 25));
      await pumpEventQueue();
      expect(r.repo.saved.single, {
        'feedUrl': 'https://exemple.org/flux.xml',
        'guid': 'ep-2',
        'position': 25,
        'duration': 1800,
        'completed': false,
      });
    });

    test('un recul dans l\'épisode s\'écrit tout de suite', () async {
      final r = rig();
      r.items.add(episodeItem());
      await pumpEventQueue();
      r.positions.add(const Duration(seconds: 40));
      await pumpEventQueue();

      r.positions.add(const Duration(seconds: 10));
      await pumpEventQueue();

      expect(r.repo.saved, hasLength(2));
      expect(r.repo.saved.last['position'], 10);
    });

    test('quitter un épisode écrit sa dernière position', () async {
      final r = rig();
      r.items.add(episodeItem());
      await pumpEventQueue();
      r.positions.add(const Duration(seconds: 12));
      await pumpEventQueue();
      expect(r.repo.saved, isEmpty);

      r.items.add(null);
      await pumpEventQueue();

      expect(r.repo.saved.single['position'], 12);
      expect(r.repo.saved.single['completed'], isFalse);
    });

    test('un épisode écouté jusqu\'au bout est marqué comme tel', () async {
      final r = rig();
      r.items.add(episodeItem());
      await pumpEventQueue();
      r.positions.add(const Duration(seconds: 1795));
      await pumpEventQueue();
      r.repo.saved.clear();

      r.items.add(null);
      await pumpEventQueue();

      expect(r.repo.saved.single['completed'], isTrue);
      // Écouté : il repartira du début.
      expect(r.repo.saved.single['position'], 0);
    });

    test('ce qui n\'est pas un podcast n\'est pas suivi', () async {
      final r = rig();
      r.items.add(const MediaItem(id: 'chanson', title: 'Une chanson'));
      await pumpEventQueue();

      r.positions.add(const Duration(seconds: 120));
      await pumpEventQueue();

      expect(r.repo.saved, isEmpty);
    });
  });

  group('écrans', () {
    Future<void> pump(
      WidgetTester tester,
      Widget screen, {
      _FakePodcasts? repo,
      Size size = const Size(360, 780),
      bool french = false,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            podcastsRepositoryProvider.overrideWithValue(repo ?? _FakePodcasts()),
            // La bascule est posée d'entrée : son écriture sur le disque ne
            // regarde pas les écrans.
            if (french)
              podcastFrenchOnlyProvider.overrideWith(_FrenchOnlyOn.new),
          ],
          child: MaterialApp(home: screen),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('la liste montre les abonnements et le palmarès',
        (tester) async {
      final repo = _FakePodcasts();
      await pump(tester, const PodcastsScreen(), repo: repo);

      expect(find.text('Mes abonnements'), findsOneWidget);
      expect(find.text('À découvrir'), findsOneWidget);
      expect(find.text('Crimes réels'), findsOneWidget);
      expect(find.textContaining('Ma Série'), findsWidgets);
      // Le palmarès demandé est celui de la catégorie mise en avant.
      expect(repo.asked, contains('discover:1488'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('sans abonnement, la section le dit plutôt que de rester vide',
        (tester) async {
      await pump(
        tester,
        const PodcastsScreen(),
        repo: _FakePodcasts(subscribed: const []),
      );

      expect(find.textContaining('Aucun abonnement'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('la bascule francophone filtre recherche et palmarès',
        (tester) async {
      final repo = _FakePodcasts();
      await pump(tester, const PodcastsScreen(), repo: repo, french: true);

      expect(find.text('Francophone seulement'), findsOneWidget);
      expect(repo.asked, contains('discover:1488:fr'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('cocher la bascule redemande le palmarès filtré',
        (tester) async {
      final repo = _FakePodcasts();
      await pump(tester, const PodcastsScreen(), repo: repo);
      expect(repo.asked, contains('discover:1488'));

      await tester.tap(find.text('Francophone seulement'));
      await tester.pumpAndSettle();

      expect(repo.asked, contains('discover:1488:fr'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('un palmarès sans francophone le dit plutôt que de crier à la '
        'panne', (tester) async {
      await pump(
        tester,
        const PodcastsScreen(),
        repo: _FakePodcasts(frenchEmpty: true),
        french: true,
      );

      expect(find.text('Rien de francophone ici'), findsOneWidget);
      expect(find.textContaining('L\'annuaire des podcasts'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('la fiche d\'une série liste ses épisodes', (tester) async {
      final repo = _FakePodcasts();
      await pump(
        tester,
        const PodcastShowScreen(feedUrl: 'https://exemple.org/flux.xml'),
        repo: repo,
      );

      expect(find.text('Épisode récent'), findsOneWidget);
      expect(find.text('Vieil épisode'), findsOneWidget);
      expect(find.text('2 épisodes'), findsOneWidget);
      expect(find.text('Dernier épisode'), findsOneWidget);
      // Abonné : le bouton propose de se désabonner.
      expect(find.text('Abonné'), findsOneWidget);
      expect(repo.asked, contains('episodes:https://exemple.org/flux.xml'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('un épisode entamé annonce ce qu\'il en reste',
        (tester) async {
      await pump(
        tester,
        const PodcastShowScreen(feedUrl: 'https://exemple.org/flux.xml'),
      );

      expect(find.textContaining('Reste 20 min'), findsOneWidget);
      expect(find.textContaining('Écouté'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('date et durée d\'un épisode se lisent comme on les dit', () {
      expect(
        formatEpisodeDate(DateTime(2026, 9, 23)),
        '23 sept. 2026',
      );
      expect(formatEpisodeDuration(1530), '26 min');
      expect(formatEpisodeDuration(3600), '1 h');
      expect(formatEpisodeDuration(5520), '1 h 32');
      expect(formatEpisodeDuration(0), '');
    });
  });
}

/// « Francophone seulement » déjà coché, sans passer par le disque.
class _FrenchOnlyOn extends PodcastFrenchOnly {
  @override
  bool build() => true;
}

/// Le même épisode, à une autre position d'écoute.
extension on PodcastEpisode {
  PodcastEpisode copyAt(int seconds) => PodcastEpisode(
        guid: guid,
        title: title,
        audioUrl: audioUrl,
        duration: duration,
        publishedAt: publishedAt,
        image: image,
        position: seconds,
        completed: completed,
      );
}
