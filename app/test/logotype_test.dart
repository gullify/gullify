import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/widgets/wordmark.dart';

/// Le logotype de la gamme — GulliFY, GulliTV, GulliVR — s'écrit dans la police
/// de l'appareil, comme sur les trois sites (`--police-logo`). Le reste de
/// l'app garde HankenGrotesk ; c'est la seule exception, et elle doit tenir
/// même quand l'appelant impose un style.
void main() {
  // Les essais tournent hors du web : on bascule le drapeau pour vérifier les
  // deux chemins, celui de la police du système et celui de la police
  // embarquée.
  setUp(() => logotypeEmbarque = false);
  tearDown(() => logotypeEmbarque = kIsWeb);

  TextStyle styleDuNom(WidgetTester tester) {
    // `Text.rich` porte le style du mot entier sur le widget, pas sur le span :
    // le span n'a que la couleur du suffixe.
    return tester.widget<Text>(find.byType(Text).first).style!;
  }

  Future<void> poser(WidgetTester tester, Widget enfant) => tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'HankenGrotesk'),
      home: Scaffold(body: enfant),
    ),
  );

  testWidgets('le nom ne s\'écrit pas dans la police de l\'app', (
    tester,
  ) async {
    await poser(tester, const GulliWordmark());

    final style = styleDuNom(tester);
    expect(
      style.fontFamily,
      isNot('HankenGrotesk'),
      reason: 'le logotype suit l\'appareil, pas le thème',
    );
    expect(style.fontFamily, '-apple-system');
    expect(style.fontFamilyFallback, contains('Segoe UI'));
    expect(style.fontFamilyFallback, contains('Roboto'));
  });

  testWidgets('la graisse et l\'approche du logotype ne se négocient pas', (
    tester,
  ) async {
    // Les valeurs viennent de la feuille de style des trois sites : -0,03 em
    // et 800. Un appelant règle la taille et la couleur ; s'il tente le reste,
    // le logotype ne le suit pas — sans quoi le même logo n'aurait pas deux
    // fois la même allure dans l'app.
    await poser(
      tester,
      const GulliWordmark(
        style: TextStyle(
          fontFamily: 'HankenGrotesk',
          fontSize: 40,
          fontWeight: FontWeight.w400,
          letterSpacing: 2,
          color: Color(0xFF123456),
        ),
      ),
    );

    final style = styleDuNom(tester);
    expect(style.fontWeight, FontWeight.w800);
    expect(style.letterSpacing, closeTo(40 * -0.03, 0.0001));
    expect(style.fontFamily, '-apple-system');
    expect(
      style.color,
      const Color(0xFF123456),
      reason: 'la couleur reste à l\'appelant',
    );
  });

  testWidgets('sur le web, la police embarquée prend le relais', (
    tester,
  ) async {
    // Le moteur de rendu web ne peut pas atteindre les polices de la machine :
    // il prendrait la sienne, qui ne ressemble pas à celle du site affiché à
    // côté. Inter tient la place, la pile système reste en repli.
    logotypeEmbarque = true;
    await poser(tester, const GulliWordmark());

    final style = styleDuNom(tester);
    expect(style.fontFamily, 'LogoSans');
    expect(style.fontFamilyFallback, contains('Segoe UI'));
    expect(style.fontFamily, isNot('HankenGrotesk'));
  });
}
