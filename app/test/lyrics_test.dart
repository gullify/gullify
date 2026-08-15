// Une phrase de paroles trop longue n'est plus tranchée par des « … »
// (idée #100) : elle passe d'abord sur deux lignes, puis rétrécit si deux
// lignes ne suffisent pas. La hauteur réservée dans la liste suit, sinon les
// phrases se chevaucheraient.
//
// La police des tests rend chaque caractère carré (1 em de large) : les
// longueurs ci-dessous sont donc choisies en caractères, pas au jugé.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/state/player.dart';
import 'package:gullify/widgets/lyrics_sheet.dart';

/// Tient sur une ligne partout.
const _court = 'Oh oh';
const _courtBis = 'La la';
const _courtTer = 'Hey hey';

/// 21 caractères : deux lignes à 300 px de large, sans rétrécir.
const _deuxLignes = 'Je pense encore a toi';

/// 20 caractères : ne tient pas en deux lignes dans une feuille étroite.
const _tropLong = 'Tout va bien ce soir';

/// Paroles horodatées : il en faut au moins quatre pour que la vue passe en
/// mode défilant, celui qui mesure les phrases.
String _lrc(List<String> lines) => [
  for (var i = 0; i < lines.length; i++)
    '[00:${(i * 5).toString().padLeft(2, '0')}.00] ${lines[i]}',
].join('\n');

Widget _host(String text, {double width = 300}) => ProviderScope(
  overrides: [
    positionProvider.overrideWith((ref) => Stream.value(Duration.zero)),
  ],
  child: MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: width,
        height: 400,
        child: LyricsView(text: text, controller: ScrollController()),
      ),
    ),
  ),
);

/// Taille de police réellement rendue pour une phrase donnée.
double _fontSizeOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!.fontSize!;

void main() {
  group('fitLyricsLine', () {
    test('une phrase courte garde sa taille', () {
      final fit = fitLyricsLine(_court, maxWidth: 300);
      expect(fit.scale, 1.0);
      expect(fit.extent, greaterThanOrEqualTo(44.0));
    });

    test('une phrase longue passe sur deux lignes avant de rétrécir', () {
      final court = fitLyricsLine(_court, maxWidth: 300);
      final long = fitLyricsLine(_deuxLignes, maxWidth: 300);
      expect(long.scale, 1.0, reason: 'deux lignes suffisent : pas de zoom');
      expect(
        long.extent,
        greaterThan(court.extent),
        reason: 'la deuxième ligne doit être réservée dans la liste',
      );
    });

    test('une phrase interminable rétrécit, sans descendre sous 60 %', () {
      final fit = fitLyricsLine(_tropLong, maxWidth: 150);
      expect(fit.scale, lessThan(1.0));
      expect(fit.scale, greaterThanOrEqualTo(0.6));
      expect(fit.extent, greaterThanOrEqualTo(44.0));
    });

    test('une largeur nulle ne fait pas boucler la mesure', () {
      final fit = fitLyricsLine(_tropLong, maxWidth: 0);
      expect(fit.scale, 1.0);
      expect(fit.extent, 44.0);
    });

    test('la taille de texte du système est prise en compte', () {
      final normal = fitLyricsLine(_court, maxWidth: 300);
      final gros = fitLyricsLine(
        _court,
        maxWidth: 300,
        textScaler: const TextScaler.linear(1.6),
      );
      expect(gros.extent, greaterThan(normal.extent));
    });
  });

  group('LyricsView', () {
    testWidgets('une phrase peut occuper deux lignes', (tester) async {
      await tester.pumpWidget(
        _host(_lrc([_deuxLignes, _court, _courtBis, _courtTer])),
      );
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(find.text(_deuxLignes));
      expect(text.maxLines, 2);
      expect(text.textAlign, TextAlign.center);
      // Deux lignes suffisent : la phrase chantée garde ses 18 pt.
      expect(text.style!.fontSize, 18.0);
      expect(_fontSizeOf(tester, _court), 15.0);
    });

    testWidgets('seule la phrase trop longue rétrécit', (tester) async {
      await tester.pumpWidget(
        _host(_lrc([_court, _tropLong, _courtBis, _courtTer]), width: 200),
      );
      await tester.pumpAndSettle();

      final petite = _fontSizeOf(tester, _tropLong);
      expect(petite, lessThan(15.0));
      expect(petite, greaterThanOrEqualTo(15.0 * 0.6));
      // Ses voisines, elles, ne bougent pas.
      expect(_fontSizeOf(tester, _courtBis), 15.0);
      expect(_fontSizeOf(tester, _court), 18.0, reason: 'la phrase chantée');
    });

    testWidgets('la place réservée suit la phrase qui déborde', (tester) async {
      await tester.pumpWidget(
        _host(_lrc([_court, _deuxLignes, _courtBis, _courtTer])),
      );
      await tester.pumpAndSettle();

      final courte = tester.getRect(find.text(_court));
      final longue = tester.getRect(find.text(_deuxLignes));
      final suivante = tester.getRect(find.text(_courtBis));
      expect(longue.height, greaterThan(courte.height));
      expect(
        suivante.top,
        greaterThanOrEqualTo(longue.bottom),
        reason: 'la phrase suivante ne doit pas chevaucher les deux lignes',
      );
    });
  });
}
