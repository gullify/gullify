import 'dart:typed_data';

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

  test('vraies réponses mDNS de deux GulliOS (avahi, réponse directe)', () {
    Uint8List hex(String h) => Uint8List.fromList([
      for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16),
    ]);
    final vus = <String, Appareil>{};
    for (final (ip, h) in const [
    ('192.168.4.141', '0000840000010005000000000f5f67756c6c6966792d65636f757465045f746370056c6f63616c00000c8001c00c000c00010000000a0009066d6169736f6ec00cc038001000010000000a001203763d310d67656e72653d67756c6c696f73c038002100010000000a000f00000000bad6066d6169736f6ec021c071001c00010000000a0010fe80000000000000229d233c7d7b33b8c071000100010000000a0004c0a8048d'),
    ('192.168.4.12', '0000840000010005000000000f5f67756c6c6966792d65636f757465045f746370056c6f63616c00000c8001c00c000c00010000000a00110e67756c6c696f732d6d6178696d65c00cc038001000010000000a001203763d310d67656e72653d67756c6c696f73c038002100010000000a001700000000bad60e67756c6c696f732d6d6178696d65c021c079001c00010000000a0010fe800000000000001e7d548e8829da6cc079000100010000000a0004c0a8040c'),
    ]) {
      for (final a in lireReponseMdns(hex(h), ip)) {
        vus[a.cle] = a;
      }
    }
    expect(vus.keys.toSet(), {'maison', 'gullios-maxime'});
    expect(vus['gullios-maxime']!.hote, '192.168.4.12');
    expect(vus['gullios-maxime']!.port, 47830);
    expect(vus['maison']!.genre, 'gullios');
  });

  test('la question mDNS demande une réponse directe', () {
    final q = questionMdns(kEcouteType);
    expect(q.sublist(q.length - 4), [0, 12, 0x80, 1]);
    expect(lireReponseMdns(Uint8List.fromList([1, 2, 3]), '1.2.3.4'), isEmpty);
  });
}
