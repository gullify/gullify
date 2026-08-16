// Android Auto demande au démarrage une racine à part, « recent », et y attend
// UN élément jouable : ce qu'on écoutait en dernier. Gullify y répondait une
// liste vide — d'où l'« Impossible de charger votre sélection » qui revenait
// sur l'écran d'accueil de la voiture (idée #103).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/audio/audio_handler.dart';
import 'package:gullify/audio/resume_store.dart';
import 'package:gullify/models/song.dart';

Song _song(int id, String title) => Song(
      id: id,
      title: title,
      filePath: '/musique/$id.mp3',
      artistName: 'Un artiste',
      albumName: 'Un album',
      duration: 200,
    );

GullifyAudioHandler _handler(Directory dir) {
  final handler = GullifyAudioHandler();
  addTearDown(handler.player.dispose);
  handler.resume.useDirectoryForTest(dir);
  return handler;
}

Directory _tempDir() {
  final dir = Directory.systemTemp.createTempSync('gullify_resume');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

/// Une écoute précédente, écrite sur le disque comme l'aurait fait l'app avant
/// que le système ne la tue.
Future<Directory> _lastListen(
  List<Song> songs, {
  required int index,
  Duration position = Duration.zero,
}) async {
  final dir = _tempDir();
  final store = ResumeStore()..useDirectoryForTest(dir);
  await store.remember(songs, index: index);
  if (position > Duration.zero) {
    await store.rememberPosition(position, songId: songs[index].id);
  }
  return dir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('la racine de reprise ne renvoie jamais une liste vide', () async {
    // Rien n'a encore été écouté : il faut malgré tout de quoi lancer la
    // musique, sinon Android Auto affiche son erreur.
    final items = await _handler(_tempDir()).getChildren(BrowseIds.resumeRoot);

    expect(items, hasLength(1));
    expect(items.single.playable, isTrue);
  });

  test('elle propose le dernier titre écouté, là où on l\'a laissé', () async {
    final dir = await _lastListen(
      [_song(1, 'Premier'), _song(2, 'Deuxième')],
      index: 1,
      position: const Duration(seconds: 42),
    );

    final items = await _handler(dir).getChildren(BrowseIds.resumeRoot);

    expect(items, hasLength(1));
    final item = items.single;
    expect(item.id, BrowseIds.resume);
    expect(item.title, 'Deuxième');
    expect(item.artist, 'Un artiste');
    expect(item.playable, isTrue);
    // Reprise entamée : Android Auto affiche la barre de progression.
    expect(item.extras?['android.media.extra.PLAYBACK_STATUS'], 1);
    expect(
      item.extras?['androidx.media.MediaItem.Extras.COMPLETION_PERCENTAGE'],
      closeTo(42 / 200, 0.001),
    );
  });

  test('la fiche de la vignette de reprise se décrit sans session', () async {
    final dir = await _lastListen([_song(3, 'Un titre')], index: 0);

    final item = await _handler(dir).getMediaItem(BrowseIds.resume);

    expect(item, isNotNull);
    expect(item!.id, BrowseIds.resume);
    expect(item.title, 'Un titre');
  });

  test('la file retenue tient dans une fenêtre autour du titre joué', () async {
    final songs = [for (var i = 0; i < 900; i++) _song(i, 'Titre $i')];
    final dir = await _lastListen(songs, index: 500);

    // Relu depuis le disque, comme après un redémarrage de l'app.
    final point = await (ResumeStore()..useDirectoryForTest(dir)).load();

    expect(point, isNotNull);
    expect(point!.songs.length, lessThanOrEqualTo(200));
    // Et c'est bien le titre lancé qui est pointé, malgré la fenêtre.
    expect(point.song.title, 'Titre 500');
    // De quoi revenir en arrière après la reprise.
    expect(point.index, greaterThan(0));
  });

  test('un lecteur au repos n\'efface pas la position retenue', () async {
    final dir = await _lastListen(
      [_song(1, 'Premier')],
      index: 0,
      position: const Duration(seconds: 42),
    );
    final store = ResumeStore()..useDirectoryForTest(dir);
    await store.load();

    // L'app qui démarre : un lecteur vide, sans piste courante.
    await store.rememberPosition(Duration.zero, songId: null);
    // Et une autre piste que celle qu'on avait retenue.
    await store.rememberPosition(const Duration(seconds: 90), songId: 7);

    expect((await store.load())!.position, const Duration(seconds: 42));
  });

  test('un changement de piste suit la file déjà retenue', () async {
    final store = ResumeStore()..useDirectoryForTest(_tempDir());
    await store.remember([_song(1, 'Premier'), _song(2, 'Deuxième')], index: 0);

    await store.rememberCurrent(2);

    expect((await store.load())!.song.title, 'Deuxième');
  });
}
