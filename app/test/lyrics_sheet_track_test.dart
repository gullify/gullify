// La feuille « Paroles » du lecteur suit le titre en cours.
//
// Elle recevait le chemin du fichier à l'ouverture et le gardait : la
// chanson changeait, la feuille restait sur les paroles du titre par lequel
// on l'avait ouverte. Le même défaut que sur la télé (idée : panneau des
// paroles), corrigé de la même façon — c'est la feuille qui relit le titre,
// on ne le lui passe plus.
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/state/library.dart';
import 'package:gullify/state/player.dart';
import 'package:gullify/widgets/lyrics_sheet.dart';

const _premier = MediaItem(
  id: '1',
  title: 'Ruby Soho',
  artist: 'Rancid',
  duration: Duration(seconds: 158),
  extras: {'filePath': 'a.mp3', 'songId': 1},
);

const _second = MediaItem(
  id: '2',
  title: 'Time Bomb',
  artist: 'Rancid',
  duration: Duration(seconds: 145),
  extras: {'filePath': 'b.mp3', 'songId': 2},
);

/// Quatre phrases horodatées au moins : en deçà, la vue les traite comme un
/// texte simple et n'en fait pas des lignes distinctes.
String _lrc(List<String> lignes) => [
  for (var i = 0; i < lignes.length; i++)
    '[00:${(i * 5).toString().padLeft(2, '0')}.00] ${lignes[i]}',
].join('\n');

final _parolesA = _lrc(['Alpha un', 'Alpha deux', 'Alpha trois', 'Alpha quatre']);
final _parolesB = _lrc(['Beta un', 'Beta deux', 'Beta trois', 'Beta quatre']);

void main() {
  testWidgets('la feuille suit le titre suivant', (tester) async {
    final file = StreamController<MediaItem?>.broadcast();
    addTearDown(file.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentMediaItemProvider.overrideWith((ref) => file.stream),
          positionProvider.overrideWith((ref) => Stream.value(Duration.zero)),
          lyricsProvider('a.mp3').overrideWith((ref) async => _parolesA),
          lyricsProvider('b.mp3').overrideWith((ref) async => _parolesB),
        ],
        child: Consumer(
          builder: (context, ref, child) {
            ref.watch(currentMediaItemProvider);
            return child!;
          },
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showLyricsSheet(context),
                  child: const Text('ouvrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    file.add(_premier);
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('ouvrir'));
    // La feuille s'ouvre en glissant : on la laisse arriver, puis les
    // paroles. Pas de pumpAndSettle — l'indicateur de chargement tourne sans
    // jamais se poser.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Alpha deux'), findsOneWidget);

    // La file avance, la feuille reste ouverte.
    file.add(_second);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
      find.text('Beta deux'),
      findsOneWidget,
      reason: 'les paroles du nouveau titre doivent remplacer les anciennes',
    );
    expect(
      find.text('Alpha deux'),
      findsNothing,
      reason: 'les paroles du titre précédent ne doivent plus être là',
    );
  });
}
