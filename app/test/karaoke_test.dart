// Mode karaoké (idée #63) : le serveur rend une version « voix atténuée » du
// titre, et l'app n'y bascule qu'une fois le rendu prêt — jamais avant, sinon
// on entendrait la version d'origine en croyant le mode actif.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/api_client.dart';
import 'package:gullify/api/library_repository.dart';
import 'package:gullify/audio/audio_handler.dart';
import 'package:gullify/state/karaoke.dart';
import 'package:gullify/state/library.dart';
import 'package:gullify/state/player.dart';

const _path = 'Artiste/Album/03 - Titre.mp3';

/// Serveur de papier : rend les états demandés dans l'ordre, le dernier
/// valant pour tous les appels suivants.
class _FakeRepo extends Fake implements LibraryRepository {
  _FakeRepo(this.answers);

  final List<KaraokeStatus> answers;
  final List<String> asked = [];
  int _call = 0;

  @override
  Future<KaraokeStatus> prepareKaraoke(String filePath) async {
    asked.add(filePath);
    final i = _call < answers.length - 1 ? _call++ : answers.length - 1;
    return answers[i];
  }
}

class _ThrowingRepo extends Fake implements LibraryRepository {
  @override
  Future<KaraokeStatus> prepareKaraoke(String filePath) async =>
      throw ApiException('network', 'injoignable');
}

/// Lecteur de papier : on ne veut que savoir s'il a basculé, pas faire tourner
/// ExoPlayer dans un test.
class _FakeHandler extends Fake implements GullifyAudioHandler {
  final List<bool> switches = [];

  @override
  Future<void> setKaraoke(bool on) async => switches.add(on);
}

KaraokeStatus _status(KaraokeState state, [String? reason]) =>
    KaraokeStatus(state: state, reason: reason);

({ProviderContainer container, _FakeHandler handler}) _bench(
  LibraryRepository repo,
) {
  final handler = _FakeHandler();
  final container = ProviderContainer(
    overrides: [
      libraryRepositoryProvider.overrideWithValue(repo),
      audioHandlerProvider.overrideWithValue(handler),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, handler: handler);
}

void main() {
  test('l\'URL karaoké est celle du flux, avec son drapeau', () {
    final repo = LibraryRepository(ApiClient(serverUrl: 'gullify.example.com'));
    expect(
      repo.streamUrlForPath('a b/c.mp3'),
      'https://gullify.example.com/stream.php?path=a+b%2Fc.mp3',
    );
    expect(
      repo.streamUrlForPath('a b/c.mp3', karaoke: true),
      'https://gullify.example.com/stream.php?path=a+b%2Fc.mp3&karaoke=1',
    );
  });

  test('le rendu prêt fait basculer le lecteur', () async {
    final repo = _FakeRepo([_status(KaraokeState.ready)]);
    final bench = _bench(repo);

    await bench.container.read(karaokeProvider.notifier).toggle(_path);

    expect(bench.container.read(karaokeProvider).phase, KaraokePhase.on);
    expect(bench.handler.switches, [true]);
    expect(repo.asked, [_path]);
  });

  test('on attend la fin du rendu avant de basculer', () async {
    final repo = _FakeRepo([
      _status(KaraokeState.rendering),
      _status(KaraokeState.rendering),
      _status(KaraokeState.ready),
    ]);
    final bench = _bench(repo);

    final done = bench.container.read(karaokeProvider.notifier).toggle(_path);
    // Le temps du rendu, le mode est « en préparation » — et le lecteur n'a
    // surtout pas encore changé de source.
    expect(bench.container.read(karaokeProvider).busy, isTrue);
    expect(bench.handler.switches, isEmpty);

    await done;
    expect(bench.container.read(karaokeProvider).phase, KaraokePhase.on);
    expect(bench.handler.switches, [true]);
    expect(repo.asked.length, 3);
  });

  test('un titre trop centré est refusé, avec son explication', () async {
    final repo = _FakeRepo([_status(KaraokeState.unavailable, 'mono')]);
    final bench = _bench(repo);

    await bench.container.read(karaokeProvider.notifier).toggle(_path);

    final state = bench.container.read(karaokeProvider);
    expect(state.phase, KaraokePhase.unavailable);
    expect(state.active, isFalse);
    expect(bench.handler.switches, isEmpty);
    expect(KaraokeNotifier.explain(state.reason), contains('mixé trop au'));
  });

  test('serveur injoignable : le mode ne s\'active pas', () async {
    final bench = _bench(_ThrowingRepo());

    await bench.container.read(karaokeProvider.notifier).toggle(_path);

    expect(bench.container.read(karaokeProvider).phase,
        KaraokePhase.unavailable);
    expect(bench.handler.switches, isEmpty);
  });

  test('rebasculer coupe le mode et repasse au flux d\'origine', () async {
    final repo = _FakeRepo([_status(KaraokeState.ready)]);
    final bench = _bench(repo);
    final notifier = bench.container.read(karaokeProvider.notifier);

    await notifier.toggle(_path);
    await notifier.toggle(_path);

    expect(bench.container.read(karaokeProvider).phase, KaraokePhase.off);
    expect(bench.handler.switches, [true, false]);
  });

  test('sans chemin de fichier (radio), le bouton ne fait rien', () async {
    final repo = _FakeRepo([_status(KaraokeState.ready)]);
    final bench = _bench(repo);

    await bench.container.read(karaokeProvider.notifier).toggle(null);

    expect(bench.container.read(karaokeProvider).phase, KaraokePhase.off);
    expect(repo.asked, isEmpty);
    expect(bench.handler.switches, isEmpty);
  });
}
