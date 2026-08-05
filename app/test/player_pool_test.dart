// Les lecteurs de l'app ne sont plus « chacun le sien » : la pré-écoute, le
// medley, les manches de jeu et les messages des parties empruntent le même
// petit tas de lecteurs et le rendent en se taisant (idée #58).
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/audio/tuned_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(resetPlayerReserveForTest);
  tearDown(resetPlayerReserveForTest);

  test('un lecteur rendu est reprêté au suivant, pas jeté', () async {
    final medley = leaseGullifyPlayer(use: PlayerUse.snippet);
    final player = medley.player;
    expect(leasedPlayerCount, 1);

    await medley.give();
    expect(leasedPlayerCount, 0);
    expect(idlePlayerCount(PlayerUse.snippet), 1);

    final manche = leaseGullifyPlayer(use: PlayerUse.snippet);
    expect(identical(manche.player, player), isTrue);
    expect(idlePlayerCount(PlayerUse.snippet), 0);
    await manche.give();
  });

  test('deux emprunts en même temps font deux lecteurs distincts', () async {
    // Le fondu enchaîné du medley : deux extraits s'entendent à la fois.
    final un = leaseGullifyPlayer(use: PlayerUse.snippet);
    final deux = leaseGullifyPlayer(use: PlayerUse.snippet);
    expect(identical(un.player, deux.player), isFalse);
    expect(leasedPlayerCount, 2);

    await un.give();
    await deux.give();
    expect(idlePlayerCount(PlayerUse.snippet), 2);
  });

  test('un lecteur rendu revient à plein volume', () async {
    // Un medley rend son lecteur juste après l'avoir fondu à zéro : la manche
    // suivante serait muette si la réserve le prêtait tel quel.
    final medley = leaseGullifyPlayer(use: PlayerUse.snippet);
    await medley.player.setVolume(0);
    await medley.give();

    final manche = leaseGullifyPlayer(use: PlayerUse.snippet);
    expect(manche.player.volume, 1);
    await manche.give();
  });

  test('les profils ne se mélangent pas', () async {
    // Un extrait et un morceau entier n'ont pas le même tampon : la pré-écoute
    // ne doit pas hériter du lecteur d'une manche de jeu.
    final manche = leaseGullifyPlayer(use: PlayerUse.snippet);
    final extrait = manche.player;
    await manche.give();

    final preecoute = leaseGullifyPlayer(use: PlayerUse.streaming);
    expect(identical(preecoute.player, extrait), isFalse);
    expect(idlePlayerCount(PlayerUse.snippet), 1);
    await preecoute.give();
  });

  test('rendre deux fois ne remet pas le même lecteur deux fois', () async {
    // Beaucoup d'emprunteurs rendent à l'arrêt *et* à leur disparition.
    final lease = leaseGullifyPlayer(use: PlayerUse.snippet);
    await lease.give();
    expect(lease.held, isFalse);
    await lease.give();

    expect(idlePlayerCount(PlayerUse.snippet), 1);
    expect(leasedPlayerCount, 0);
  });

  test('la réserve ne gonfle pas indéfiniment', () async {
    // Au-delà de ce qu'on entend à la fois, garder des lecteurs au chaud ne sert
    // à rien : les surnuméraires sont éteints pour de bon.
    final leases = [
      for (var i = 0; i < 4; i++) leaseGullifyPlayer(use: PlayerUse.snippet),
    ];
    for (final lease in leases) {
      await lease.give();
    }
    expect(idlePlayerCount(PlayerUse.snippet), 2);
  });
}
