// Android Auto sans réseau : l'écran ne doit plus rester sur « Aucune
// sélection » (idée #60). Ce qui est téléchargé reste navigable et jouable, un
// « Réessayer » est proposé, et la catégorie se remplit d'elle-même dès que le
// serveur répond à nouveau.
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/api_client.dart';
import 'package:gullify/api/library_repository.dart';
import 'package:gullify/audio/audio_handler.dart';
import 'package:gullify/models/album.dart';
import 'package:gullify/models/song.dart';

/// Un dépôt dont le serveur ne répond pas — puis répond, quand on le décide.
class _Repository extends LibraryRepository {
  _Repository() : super(ApiClient(serverUrl: 'https://exemple.test'));

  bool online = false;

  @override
  Future<List<Album>> albums({int limit = 5000, int offset = 0, String? genre}) async {
    if (!online) throw ApiException('network', 'pas de réseau');
    return const [Album(id: 1, name: 'Un album', artistName: 'Quelqu\'un')];
  }

  @override
  Future<SearchResults> search(String query) async {
    if (!online) throw ApiException('network', 'pas de réseau');
    return const SearchResults();
  }

  @override
  String streamUrl(Song song) => 'https://exemple.test/stream/${song.id}';
}

Song _song(int id, String title, {String artist = 'Un artiste'}) => Song(
      id: id,
      title: title,
      filePath: '/musique/$id.mp3',
      artistName: artist,
      duration: 180,
    );

/// Un handler avec deux titres téléchargés sur le téléphone.
GullifyAudioHandler _handler({bool withDownloads = true}) {
  final handler = GullifyAudioHandler();
  addTearDown(handler.player.dispose);
  // Réessais immédiats : un test n'attend pas trois secondes.
  handler.reloadDelays = const [Duration(milliseconds: 5)];
  if (withDownloads) {
    handler.offlineSongs = [_song(1, 'Titre local'), _song(2, 'Autre local')];
    handler.offlinePaths = {1: '/tel/1.mp3', 2: '/tel/2.mp3'};
  }
  return handler;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('hors ligne, une catégorie ne renvoie plus une liste vide', () async {
    final handler = _handler();
    handler.repository = _Repository(); // serveur muet

    final items = await handler.getChildren(BrowseIds.albums);

    expect(items, isNotEmpty);
    expect(items.first.id, BrowseIds.retry(BrowseIds.albums));
    expect(items.first.title, 'Réessayer');
    // Et ce qui est sur le téléphone reste jouable.
    expect(
      items.map((i) => i.title),
      containsAll(<String>['Titre local', 'Autre local']),
    );
  });

  test('sans téléchargements, il reste au moins de quoi réessayer', () async {
    final handler = _handler(withDownloads: false);
    handler.repository = _Repository();

    final items = await handler.getChildren(BrowseIds.albums);

    expect(items.map((i) => i.id), [BrowseIds.retry(BrowseIds.albums)]);
  });

  test('les téléchargements se listent sans session ni réseau', () async {
    final handler = _handler(); // aucun repository : session non restaurée

    final tabs = await handler.getChildren(BrowseIds.library);
    expect(tabs.map((i) => i.id), contains(BrowseIds.downloads));

    final items = await handler.getChildren(BrowseIds.downloads);
    expect(items.map((i) => i.id), [
      'DOWNLOADS_PLAY',
      'DOWNLOADS_SHUFFLE',
      'DOWNLOADS_TRACK_0',
      'DOWNLOADS_TRACK_1',
    ]);

    // La source est le fichier du téléphone, pas une URL de flux.
    final item = await handler.getMediaItem('DOWNLOADS_TRACK_1');
    expect(item?.title, 'Autre local');
    expect(item?.extras?['songId'], 2);
  });

  test('rien de téléchargé : pas d\'entrée Téléchargements', () async {
    final handler = _handler(withDownloads: false);
    final tabs = await handler.getChildren(BrowseIds.library);
    expect(tabs.map((i) => i.id), isNot(contains(BrowseIds.downloads)));
  });

  test('un dépôt non lié vaut un échec, pas une liste vide', () async {
    // Radios et playlists n'ont pas de dépôt tant que la session n'est pas
    // restaurée : elles renvoyaient un écran vide définitif.
    final handler = _handler();
    handler.repository = _Repository();

    final radios = await handler.getChildren(BrowseIds.radios);
    expect(radios.first.id, BrowseIds.retry(BrowseIds.radios));

    final listes = await handler.getChildren(BrowseIds.playlists);
    expect(listes.first.id, BrowseIds.retry(BrowseIds.playlists));
  });

  test('« Réessayer » recharge la catégorie quand le réseau est revenu',
      () async {
    final handler = _handler();
    final repo = _Repository();
    handler.repository = repo;
    var sessionReprise = 0;
    handler.onRetrySession = () async {
      sessionReprise++;
      repo.online = true; // le réseau est revenu entre-temps
    };

    final items = await handler.getChildren(
      BrowseIds.retry(BrowseIds.albums),
    );

    expect(sessionReprise, 1);
    expect(items.map((i) => i.title), ['Un album']);
  });

  test('« Réessayer » toujours hors ligne repropose le repli', () async {
    final handler = _handler();
    handler.repository = _Repository();

    final items = await handler.getChildren(BrowseIds.retry(BrowseIds.albums));

    expect(items.first.id, BrowseIds.retry(BrowseIds.albums));
  });

  test('la catégorie se recharge toute seule au retour du réseau', () async {
    final handler = _handler();
    final repo = _Repository();
    handler.repository = repo;

    // Premier passage hors ligne : repli + réessai programmé.
    await handler.getChildren(BrowseIds.albums);
    expect(handler.aaLog.any((l) => l.contains('ERREUR getChildren')), isTrue);

    repo.online = true;
    // Laisse la boucle de réessai faire son tour.
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (handler.aaLog.any((l) => l.contains('réessai ALBUMS réussi'))) break;
    }
    expect(
      handler.aaLog.any((l) => l.contains('réessai ALBUMS réussi')),
      isTrue,
      reason: 'la catégorie doit se recharger sans que l\'utilisateur agisse',
    );

    final items = await handler.getChildren(BrowseIds.albums);
    expect(items.map((i) => i.title), ['Un album']);
  });

  test('la recherche hors ligne rend les titres téléchargés', () async {
    final handler = _handler();
    handler.repository = _Repository();

    final results = await handler.search('local');
    expect(results.map((i) => i.id), ['DOWNLOADS_TRACK_0', 'DOWNLOADS_TRACK_1']);

    expect(await handler.search('introuvable'), isEmpty);
  });
}
