// Idée #90 : le tampon d'avance. Ce qui se vérifie ici, c'est ce qui décide —
// quels titres sont pris d'avance, et lesquels s'effacent quand la place
// réservée est pleine. Le reste (la descente elle-même) demande un réseau.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/audio/prefetch.dart';

List<int> _straight(int length) => [for (var i = 0; i < length; i++) i];

BufferedFile _file(int id, {int size = 10, int minutes = 0}) => BufferedFile(
      songId: id,
      path: '/tmp/$id.mp3',
      size: size,
      at: DateTime(2026, 1, 1).add(Duration(minutes: minutes)),
    );

void main() {
  group('les titres pris d\'avance', () {
    test('sont les suivants de la file, jamais celui qui joue', () {
      expect(
        bufferTargets(order: _straight(10), current: 3, ahead: 3),
        [4, 5, 6],
      );
    });

    test('s\'arrêtent au bout de la file', () {
      expect(bufferTargets(order: _straight(5), current: 3, ahead: 3), [4]);
      expect(bufferTargets(order: _straight(5), current: 4, ahead: 3), isEmpty);
    });

    test('repartent au début quand la file tourne en boucle', () {
      expect(
        bufferTargets(order: _straight(5), current: 3, ahead: 3, loop: true),
        [4, 0, 1],
      );
    });

    test('ne reprennent jamais le titre en cours, même en boucle', () {
      final targets =
          bufferTargets(order: _straight(3), current: 1, ahead: 10, loop: true);
      expect(targets, [2, 0]);
    });

    test('suivent le tirage aléatoire, pas l\'ordre de la file', () {
      // Le lecteur enchaîne 4, 1, 3, 0, 2 : après le 1, ce qui arrive c'est le
      // 3 puis le 0 — pas le 2 ni le 3 de l'ordre d'affichage.
      expect(
        bufferTargets(order: const [4, 1, 3, 0, 2], current: 1, ahead: 2),
        [3, 0],
      );
    });

    test('« toute la file » prend tout le reste', () {
      expect(
        bufferTargets(order: _straight(4), current: 0, ahead: kBufferAll),
        [1, 2, 3],
      );
    });

    test('éteint, ne prend rien', () {
      expect(bufferTargets(order: _straight(10), current: 0, ahead: 0), isEmpty);
    });

    test('sautent ce que le lecteur ne saura pas basculer, et vont plus loin',
        () {
      // Le lecteur enchaîne 5, 0, 6, 1, 7 : seuls les titres placés après le 5
      // dans la file savent changer de source. On saute le 0 et le 1, et on va
      // chercher le 7 pour tenir les trois titres d'avance.
      expect(
        bufferTargets(
          order: const [5, 0, 6, 1, 7, 2, 8],
          current: 5,
          ahead: 3,
          usable: (i) => i > 5,
        ),
        [6, 7, 8],
      );
    });

    test('ne prennent rien sur une file vide ou un index inconnu', () {
      expect(bufferTargets(order: const [], current: 0, ahead: 3), isEmpty);
      expect(bufferTargets(order: _straight(3), current: 7, ahead: 3), isEmpty);
    });
  });

  group('ce qui s\'efface du tampon', () {
    test('rien tant qu\'on tient dans la place réservée', () {
      expect(
        bufferEviction(
          files: [_file(1), _file(2)],
          maxBytes: 100,
        ),
        isEmpty,
      );
    });

    test('les plus vieux d\'abord, jusqu\'à repasser sous le plafond', () {
      final doomed = bufferEviction(
        files: [
          _file(1, minutes: 30),
          _file(2, minutes: 0),
          _file(3, minutes: 10),
        ],
        maxBytes: 15,
      );
      expect(doomed, [2, 3]);
    });

    test('jamais un titre de la file en cours', () {
      final doomed = bufferEviction(
        files: [_file(1, minutes: 0), _file(2, minutes: 10)],
        maxBytes: 5,
        keep: {1},
      );
      expect(doomed, [2]);
    });

    test('déborde plutôt que de couper la musique', () {
      // Toute la file est à l'abri : rien à effacer, même au-dessus du
      // plafond. Le tampon cessera simplement de descendre.
      expect(
        bufferEviction(
          files: [_file(1), _file(2)],
          maxBytes: 5,
          keep: {1, 2},
        ),
        isEmpty,
      );
    });
  });

  group('le dossier du tampon', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('gullify_buffer'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('retrouve ce qui est déjà descendu, et le sert au lecteur', () async {
      File('${dir.path}/42.mp3').writeAsBytesSync(List.filled(2048, 0));
      final buffer = PlaybackBuffer();
      await buffer.useDirectoryForTest(dir);

      expect(buffer.count, 1);
      expect(buffer.bytes, 2048);
      expect(buffer.pathFor(42), '${dir.path}/42.mp3');
      expect(buffer.pathFor(43), isNull);
    });

    test('ramasse les descentes interrompues', () async {
      File('${dir.path}/7.mp3.part').writeAsBytesSync(List.filled(10, 0));
      final buffer = PlaybackBuffer();
      await buffer.useDirectoryForTest(dir);

      expect(buffer.count, 0);
      expect(File('${dir.path}/7.mp3.part').existsSync(), isFalse);
    });

    test('ne sert pas un fichier disparu sous lui', () async {
      final file = File('${dir.path}/9.mp3')..writeAsBytesSync([1, 2, 3]);
      final buffer = PlaybackBuffer();
      await buffer.useDirectoryForTest(dir);
      expect(buffer.pathFor(9), isNotNull);

      file.deleteSync();
      expect(buffer.pathFor(9), isNull);
      expect(buffer.count, 0);
    });

    test('se vide sur demande', () async {
      File('${dir.path}/1.mp3').writeAsBytesSync([1]);
      File('${dir.path}/2.mp3').writeAsBytesSync([2]);
      final buffer = PlaybackBuffer();
      await buffer.useDirectoryForTest(dir);
      expect(buffer.count, 2);

      await buffer.clear();
      expect(buffer.count, 0);
      expect(buffer.bytes, 0);
      expect(dir.listSync(), isEmpty);
    });
  });

  test('l\'avance s\'écrit comme l\'écran l\'affiche', () {
    expect(formatBufferAhead(0), 'Désactivé');
    expect(formatBufferAhead(1), '1 titre d\'avance');
    expect(formatBufferAhead(3), '3 titres d\'avance');
    expect(formatBufferAhead(kBufferAll), 'Toute la file');
  });
}
