import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/widgets/wordmark.dart';

/// Le logotype de la gamme — GulliFY, GulliTV, GulliVR — s'écrit dans la police
/// de l'appareil, comme sur les trois sites (`--police-logo`). Le reste de
/// l'app garde HankenGrotesk ; c'est la seule exception, et elle doit tenir
/// même quand l'appelant impose un style.
void main() {
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

  testWidgets('un style d\'appelant règle la graisse, pas la famille', (
    tester,
  ) async {
    await poser(
      tester,
      const GulliWordmark(
        style: TextStyle(
          fontFamily: 'HankenGrotesk',
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
        ),
      ),
    );

    final style = styleDuNom(tester);
    expect(style.fontWeight, FontWeight.w800);
    expect(style.letterSpacing, -0.8);
    expect(style.fontFamily, '-apple-system');
  });
}
