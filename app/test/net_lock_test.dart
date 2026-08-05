import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/audio/net_lock.dart';

/// Le verrou réseau natif est unique pour toute l'app, mais plusieurs lecteurs
/// peuvent jouer en même temps (un extrait de manche et un message du
/// talkie-walkie, par exemple). On vérifie ici qu'aucun d'eux ne relâche le
/// verrou d'un autre.
void main() {
  setUp(resetNetworkLockForTest);

  test('une prise ne compte qu\'une fois, quoi qu\'on lui répète', () {
    final hold = NetworkLockHold();
    hold.hold(true);
    hold.hold(true);
    expect(networkLockHolders, 1);
    expect(hold.held, isTrue);

    hold.hold(false);
    hold.hold(false);
    expect(networkLockHolders, 0);
    expect(hold.held, isFalse);
  });

  test('le verrou tient tant qu\'un lecteur joue encore', () {
    final music = NetworkLockHold();
    final voice = NetworkLockHold();

    music.hold(true);
    voice.hold(true);
    expect(networkLockHolders, 2);

    // Le message se termine : la musique, elle, joue toujours.
    voice.hold(false);
    expect(networkLockHolders, 1);
    expect(music.held, isTrue);

    music.hold(false);
    expect(networkLockHolders, 0);
  });

  test('un lecteur qui n\'a jamais joué ne relâche rien', () {
    final music = NetworkLockHold();
    final idle = NetworkLockHold();

    music.hold(true);
    idle.hold(false);
    expect(networkLockHolders, 1);
  });
}
