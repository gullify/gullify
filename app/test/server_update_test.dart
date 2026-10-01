import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/update_repository.dart';
import 'package:gullify/state/server_update.dart';

/// Un serveur qui ne répond pas : exactement ce qui arrive pendant les
/// quelques secondes où il se fait remplacer.
class _ServeurMuet implements UpdateRepository {
  @override
  Future<ServerUpdate> etat() => Future.error(Exception('connection refused'));

  @override
  Future<void> lancer({String action = 'maj'}) async {}
}

class _ServeurQuiRepond implements UpdateRepository {
  @override
  Future<ServerUpdate> etat() async => ServerUpdate.fromJson(const {
    'installee': '3.73.0',
    'disponible': '3.73.0',
    'aJour': true,
    'possible': true,
    'enCours': false,
    'journal': ['Mise en place...', 'fini'],
  });

  @override
  Future<void> lancer({String action = 'maj'}) async {}
}

void main() {
  ProviderContainer bac(UpdateRepository repo) {
    final container = ProviderContainer(
      overrides: [updateRepositoryProvider.overrideWithValue(repo)],
      // Sans ça, un provider en panne laisse un minuteur de reprise en vol et
      // le test ne se termine pas.
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    return container;
  }

  test('un serveur muet est une réponse, pas une panne', () async {
    // C'est tout le défaut du 2026-10-01 : le serveur disparaissait le temps
    // d'être remplacé, le provider tombait en panne, Riverpod le reprenait
    // avec un délai qui doublait — et la carte restait figée sur
    // « Récupération du code… » alors que tout était fini depuis longtemps.
    final etat = await bac(_ServeurMuet()).read(serverUpdateProvider.future);

    expect(etat.joignable, isFalse);
    expect(etat.enCours, isFalse);
    expect(etat.possible, isFalse);
    expect(etat.journal, isEmpty);
  });

  test('un serveur qui répond est joignable, et se lit', () async {
    final etat =
        await bac(_ServeurQuiRepond()).read(serverUpdateProvider.future);

    expect(etat.joignable, isTrue);
    expect(etat.installee, '3.73.0');
    expect(etat.aJour, isTrue);
    expect(etat.possible, isTrue);
    expect(etat.offerte, isFalse); // à jour : rien à proposer
  });

  test('ne pas savoir n\'est pas être à jour', () {
    final etat = ServerUpdate.fromJson(const {
      'installee': '3.73.0',
      'disponible': null,
      'aJour': null,
      'possible': true,
      'enCours': false,
      'journal': <String>[],
    });

    expect(etat.aJour, isNull);
    expect(etat.offerte, isFalse);
    expect(etat.joignable, isTrue); // il a répondu, c'est le dépôt qui se tait
  });
}
