import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/ecoute/ecoute.dart';

void main() {
  test('état distant lu depuis /etat (GulliOS)', () {
    final e = EtatDistant.fromJson({
      'v': 1, 'nom': 'gullios-fred', 'genre': 'poste', 'de': 'Maxime',
      'file': [
        {'titre': 'A', 'artiste': 'X', 'url': 'https://m/a'},
        {'titre': 'B', 'artiste': 'X', 'url': 'https://m/b'},
      ],
      'index': 1, 'position': 12.5, 'duree': 187.2, 'pause': false, 'volume': 40, 'actif': true,
    });
    expect(e.titre?['titre'], 'B');
    expect(e.position, const Duration(milliseconds: 12500));
    expect(e.volume, 40);
    expect(e.pause, isFalse);
  });

  test('un appareil inactif n\'a pas de titre ; la télé n\'a pas de volume', () {
    final e = EtatDistant.fromJson({'genre': 'tv', 'actif': false, 'index': -1, 'file': [], 'volume': null});
    expect(e.titre, isNull);
    expect(e.volume, isNull);
  });

  test('adresse IPv6 entre crochets', () {
    const a = Appareil(cle: 'x', nom: 'x', hote: 'fe80::1', port: 47830);
    expect(a.base, 'http://[fe80::1]:47830');
    expect(a.description, 'Ne répond pas');
    expect(a.avec(genre: 'poste', dispo: true).description, 'Poste GulliOS');
  });
}
