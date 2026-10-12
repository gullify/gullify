// Le menu de la voiture, modèle A : quatre portes, et un accueil qui tient
// dans un seul écran.
//
// Trois choses se jouaient contre nous avant ça. La racine servait cinq
// entrées alors que la voiture en annonce quatre — la cinquième, Favoris,
// était hors cadre et déjà présente ailleurs. L'accueil était un menu vers
// d'autres menus : trois taps avant la moindre note. Et aucune indication de
// présentation n'était déclarée, donc la voiture ignorait grilles et titres de
// section, faute d'avoir été prévenue qu'on savait les lire.
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/api_client.dart';
import 'package:gullify/api/library_repository.dart';
import 'package:gullify/api/podcasts_repository.dart';
import 'package:gullify/audio/audio_handler.dart';
import 'package:gullify/audio/resume_store.dart';
import 'package:gullify/models/album.dart';
import 'package:gullify/models/song.dart';

Song _song(int id, String title, {String artist = 'Les Hay Babies'}) => Song(
      id: id,
      title: title,
      filePath: '/musique/$id.mp3',
      artistName: artist,
      albumName: 'Un album',
      artworkUrl: 'https://exemple.test/art/$id.jpg',
      duration: 200,
    );

/// Un serveur qui répond — ou qui ne répond pas, quand on le décide.
class _Repository extends LibraryRepository {
  _Repository() : super(ApiClient(serverUrl: 'https://exemple.test'));

  bool online = true;

  /// Ce que « Derniers joués » rend, et donc aussi les trois premiers de
  /// l'accueil. Plus long que l'accueil n'en montre : c'est tout l'objet du
  /// partage de cache.
  List<Song> recents = [
    _song(1, 'Paquetville'),
    _song(2, 'Jolie Louise'),
    _song(3, 'Full Moon'),
    _song(4, 'Un quatrième'),
  ];

  @override
  Future<List<Song>> recentSongs({int limit = 50}) async {
    if (!online) throw ApiException('network', 'pas de réseau');
    return recents;
  }

  @override
  Future<List<Album>> recentAlbums({int limit = 20}) async {
    if (!online) throw ApiException('network', 'pas de réseau');
    return [
      for (var i = 1; i <= 8; i++)
        Album(
          id: i,
          name: 'Album $i',
          artistName: 'Quelqu\'un',
          artworkUrl: 'https://exemple.test/album/$i.jpg',
        ),
    ];
  }
}

/// Une série suivie, et ses trois épisodes : un commencé, un terminé, un
/// jamais touché.
class _Podcasts extends PodcastsRepository {
  _Podcasts() : super(ApiClient(serverUrl: 'https://exemple.test'));

  static const feed = 'https://radio.ca/annees-lumiere.xml';
  static const show = PodcastShow(
    feedUrl: feed,
    title: 'Les Années lumière',
    author: 'Radio-Canada',
  );

  @override
  Future<List<PodcastShow>> subscriptions() async => const [show];

  @override
  Future<PodcastFeed> episodes(
    String feedUrl, {
    int limit = 100,
    bool refresh = false,
  }) async =>
      const PodcastFeed(
        show: show,
        episodes: [
          PodcastEpisode(
            guid: 'commence',
            title: 'Épisode du 9 octobre',
            audioUrl: 'https://radio.ca/1.mp3',
            description: '',
            duration: 3600,
            publishedAt: 0,
            image: '',
            number: 0,
            season: 0,
            position: 900,
          ),
          PodcastEpisode(
            guid: 'termine',
            title: 'Épisode du 2 octobre',
            audioUrl: 'https://radio.ca/2.mp3',
            description: '',
            duration: 3600,
            publishedAt: 0,
            image: '',
            number: 0,
            season: 0,
            position: 3600,
            completed: true,
          ),
          PodcastEpisode(
            guid: 'neuf',
            title: 'Épisode du 25 septembre',
            audioUrl: 'https://radio.ca/3.mp3',
            description: '',
            duration: 3600,
            publishedAt: 0,
            image: '',
            number: 0,
            season: 0,
          ),
        ],
      );
}

Directory _tempDir() {
  final dir = Directory.systemTemp.createTempSync('gullify_modele_a');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

GullifyAudioHandler _handler({
  _Repository? repo,
  Directory? resumeDir,
  bool podcasts = false,
}) {
  final handler = GullifyAudioHandler();
  addTearDown(handler.player.dispose);
  handler.reloadDelays = const [Duration(milliseconds: 5)];
  handler.accueilAttente = const Duration(milliseconds: 20);
  handler.resume.useDirectoryForTest(resumeDir ?? _tempDir());
  if (repo != null) handler.repository = repo;
  if (podcasts) handler.podcastsRepository = _Podcasts();
  return handler;
}

/// Une écoute précédente, écrite sur le disque comme l'aurait fait l'app.
Future<Directory> _derniereEcoute({Duration position = Duration.zero}) async {
  final dir = _tempDir();
  final store = ResumeStore()..useDirectoryForTest(dir);
  await store.remember([_song(1, 'Paquetville')], index: 0);
  if (position > Duration.zero) {
    await store.rememberPosition(position, songId: 1);
  }
  return dir;
}

/// Le nom de la section d'un élément, tel que la voiture le lira.
String? _section(MediaItem item) =>
    item.extras?[GullifyAudioHandler.titreDeSection] as String?;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('la racine tient dans le cadre annoncé par la voiture', () {
    test('quatre portes, et Favoris n\'en est plus une', () async {
      final root = await _handler().getChildren(BrowseIds.root);

      expect(root.map((i) => i.title),
          ['Accueil', 'Bibliothèque', 'Balados', 'Radios']);
      // Favoris était la cinquième : hors cadre, donc invisible, et de toute
      // façon en double avec Bibliothèque.
      expect(root.map((i) => i.id), isNot(contains(BrowseIds.favorites)));
      expect(root.every((i) => i.playable == false), isTrue);
    });

    test('Accueil et Balados annoncent une grille pour leurs enfants',
        () async {
      final root = await _handler().getChildren(BrowseIds.root);
      final accueil = root.firstWhere((i) => i.id == BrowseIds.home);
      final balados = root.firstWhere((i) => i.id == BrowseIds.podcasts);

      for (final item in [accueil, balados]) {
        expect(item.extras?[AndroidContentStyle.browsableHintKey],
            AndroidContentStyle.gridItemHintValue);
        // Dans le même écran, ce qui se joue reste une liste : c'est ce qui
        // permet à l'accueil d'aligner des raccourcis au-dessus de pochettes.
        expect(item.extras?[AndroidContentStyle.playableHintKey],
            AndroidContentStyle.listItemHintValue);
      }
    });
  });

  group('l\'accueil est un écran, plus un menu vers des menus', () {
    test('trois sections, dans l\'ordre, chacune d\'un seul tenant', () async {
      final handler = _handler(
        repo: _Repository(),
        resumeDir: await _derniereEcoute(position: const Duration(minutes: 1)),
      );

      final home = await handler.getChildren(BrowseIds.home);
      final sections = home.map(_section).toList();

      // Aucun élément sans section : un seul orphelin, et la voiture retombe
      // sur une liste plate.
      expect(sections.contains(null), isFalse);
      // L'ordre des sections, et le fait qu'elles ne s'entrelacent pas.
      expect(sections.toSet().toList(), [
        GullifyAudioHandler.sectionReprendre,
        GullifyAudioHandler.sectionRoute,
        GullifyAudioHandler.sectionNouveautes,
      ]);
      for (final titre in sections.toSet()) {
        final premiers = sections.indexOf(titre);
        final derniers = sections.lastIndexOf(titre);
        expect(derniers - premiers + 1,
            sections.where((s) => s == titre).length,
            reason: 'la section « $titre » doit être contiguë');
      }
    });

    test('un seul tap suffit : les raccourcis se jouent', () async {
      final home = await _handler(repo: _Repository())
          .getChildren(BrowseIds.home);
      final route = home
          .where((i) => _section(i) == GullifyAudioHandler.sectionRoute)
          .toList();

      expect(route.map((i) => i.title),
          ['Lecture aléatoire', 'Découverte', 'Favoris en vrac']);
      expect(route.every((i) => i.playable == true), isTrue);
    });

    test('les nouveautés sont des pochettes à ouvrir, pas des titres',
        () async {
      final home = await _handler(repo: _Repository())
          .getChildren(BrowseIds.home);
      final nouveautes = home
          .where((i) => _section(i) == GullifyAudioHandler.sectionNouveautes)
          .toList();

      // Six au plus : au-delà, la section chasse le reste de l'écran.
      expect(nouveautes, hasLength(6));
      expect(nouveautes.every((i) => i.playable == false), isTrue);
      expect(nouveautes.first.id, BrowseIds.album(1));
      expect(nouveautes.first.artUri, isNotNull);
    });

    test('ce qu\'on écoutait vient en tête, avec sa progression', () async {
      final handler = _handler(
        repo: _Repository(),
        resumeDir: await _derniereEcoute(position: const Duration(minutes: 1)),
      );

      final home = await handler.getChildren(BrowseIds.home);

      expect(home.first.id, BrowseIds.resume);
      expect(home.first.title, 'Paquetville');
      expect(home.first.playable, isTrue);
      // 60 s sur 200 : la voiture dessine la barre elle-même.
      expect(
        home.first.extras?[
            'androidx.media.MediaItem.Extras.COMPLETION_PERCENTAGE'],
        closeTo(0.3, 0.001),
      );
    });

    test('la reprise ne compte pas deux fois', () async {
      // Le titre qu'on reprend est presque toujours aussi le dernier joué.
      final handler = _handler(
        repo: _Repository(),
        resumeDir: await _derniereEcoute(position: const Duration(minutes: 1)),
      );

      final home = await handler.getChildren(BrowseIds.home);
      final reprendre = home
          .where((i) => _section(i) == GullifyAudioHandler.sectionReprendre)
          .toList();

      expect(reprendre.first.id, BrowseIds.resume);
      expect(reprendre.where((i) => i.title == 'Paquetville'), hasLength(1));
      // Trois lignes malgré tout : la reprise, puis les joués suivants.
      expect(reprendre.map((i) => i.title),
          ['Paquetville', 'Jolie Louise', 'Full Moon']);
    });

    test('les derniers joués partagent l\'espace d\'identifiants de leur '
        'catégorie', () async {
      // Toucher l'un des trois de l'accueil doit poser la file entière à la
      // bonne piste — donc les mêmes identifiants, et le même cache, que
      // « Derniers joués ».
      final handler = _handler(repo: _Repository());

      final home = await handler.getChildren(BrowseIds.home);
      final recents = home
          .where((i) => _section(i) == GullifyAudioHandler.sectionReprendre)
          .toList();
      expect(recents.map((i) => i.id),
          ['RECENTPLAYS_TRACK_0', 'RECENTPLAYS_TRACK_1', 'RECENTPLAYS_TRACK_2']);

      final categorie = await handler.getChildren(BrowseIds.recentPlays);
      final pistes =
          categorie.where((i) => i.id.startsWith('RECENTPLAYS_TRACK_')).toList();
      for (final item in recents) {
        expect(pistes.firstWhere((p) => p.id == item.id).title, item.title);
      }
    });

    test('sans serveur, l\'accueil garde ses raccourcis', () async {
      // Les autres catégories retombent sur « Réessayer » ; l'accueil, non.
      // Le temps d'y toucher, la session est souvent revenue — et un accueil
      // qui n'offre rien est le symptôme qu'on vient de corriger.
      final handler = _handler(
        resumeDir: await _derniereEcoute(),
      ); // aucun repository

      final home = await handler.getChildren(BrowseIds.home);

      expect(home.map((i) => i.title), contains('Lecture aléatoire'));
      expect(home.map((i) => i.title), isNot(contains('Réessayer')));
      expect(home.first.id, BrowseIds.resume);
    });

    test('serveur muet : l\'accueil ne se vide pas non plus', () async {
      final repo = _Repository()..online = false;
      final home = await _handler(repo: repo).getChildren(BrowseIds.home);

      expect(home, isNotEmpty);
      expect(home.map((i) => i.title), contains('Découverte'));
      expect(home.map((i) => _section(i)),
          isNot(contains(GullifyAudioHandler.sectionNouveautes)));
    });
  });

  group('la bibliothèque a récupéré tout ce qui relève de la fouille', () {
    test('populaires, derniers joués, nouveautés et Bandcamp y sont', () async {
      final tabs = await _handler().getChildren(BrowseIds.library);
      final ids = tabs.map((i) => i.id).toList();

      expect(ids, containsAll([
        BrowseIds.artists,
        BrowseIds.albums,
        BrowseIds.playlists,
        BrowseIds.favorites,
        BrowseIds.genres,
        BrowseIds.popular,
        BrowseIds.recentPlays,
        BrowseIds.recent,
        BrowseIds.bandcamp,
      ]));
      // Artistes et Albums ont des images : ils annoncent une grille.
      for (final id in [BrowseIds.artists, BrowseIds.albums]) {
        expect(
          tabs.firstWhere((i) => i.id == id)
              .extras?[AndroidContentStyle.browsableHintKey],
          AndroidContentStyle.gridItemHintValue,
        );
      }
    });
  });

  group('un épisode de balado porte son état d\'écoute', () {
    test('commencé, terminé, jamais touché', () async {
      final handler = _handler(repo: _Repository(), podcasts: true);

      final episodes = await handler
          .getChildren(BrowseIds.podcastShow(_Podcasts.feed));

      const statut = 'androidx.media.MediaItem.Extras.COMPLETION_STATUS';
      const pourcent =
          'androidx.media.MediaItem.Extras.COMPLETION_PERCENTAGE';

      expect(episodes.map((i) => i.extras?[statut]), [1, 2, 0]);
      // 900 s sur 3600 : un quart.
      expect(episodes.first.extras?[pourcent], closeTo(0.25, 0.001));
      // Terminé ou jamais commencé : pas de barre à moitié pleine.
      expect(episodes[1].extras?.containsKey(pourcent), isFalse);
      expect(episodes[2].extras?.containsKey(pourcent), isFalse);
    });
  });

  group('le dossier local tient dans quatre entrées lui aussi', () {
    test('les téléchargements passent en tête des titres', () async {
      final handler = _handler();
      handler.setLocalLibrary(
        mode: true,
        songs: [const Song(id: -1, title: 'Local', filePath: '/carte/a.mp3')],
        paths: {-1: '/carte/a.mp3'},
        albums: const [],
        artists: const <LocalBrowseArtist>[],
      );
      handler.offlineSongs = [_song(12, 'Descendu')];
      handler.offlinePaths = {12: '/telechargements/b.mp3'};

      final root = await handler.getChildren(BrowseIds.root);
      expect(root.map((i) => i.title),
          ['Lecture aléatoire', 'Artistes', 'Albums', 'Titres']);

      // Rien n'est perdu : ce qui est descendu reste à un tap de plus.
      final titres = await handler.getChildren(BrowseIds.localSongs);
      expect(titres.map((i) => i.id), contains(BrowseIds.downloads));
      final descendus = await handler.getChildren(BrowseIds.downloads);
      expect(descendus.any((i) => i.title == 'Descendu'), isTrue);
    });

    test('dossier vide mais des titres descendus : ils prennent la racine',
        () async {
      final handler = _handler();
      handler.setLocalLibrary(mode: true);
      handler.offlineSongs = [_song(12, 'Descendu')];
      handler.offlinePaths = {12: '/telechargements/b.mp3'};
      handler.localLibraryWait = Duration.zero;

      final root = await handler.getChildren(BrowseIds.root);
      expect(root.map((i) => i.title), ['Téléchargements']);
    });
  });
}
