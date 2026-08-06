// Rendu de contrôle de l'état vide (mascotte gravée en médaillon) sur les deux
// bases du thème : c'est un écran qu'on ne voit qu'au moment où il n'y a rien
// à montrer — sans golden, une régression y passe inaperçue longtemps.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/theme.dart';
import 'package:gullify/widgets/mascot_empty.dart';

Widget _wrap({required bool dark}) {
  final theme = gullifyThemeFor(GullifyAccent.indigo, dark: dark);
  return MaterialApp(
    theme: theme,
    home: Builder(
      builder: (context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: Theme.of(context).extension<GullifySurfaces>()!.background,
        ),
        child: const Scaffold(
          backgroundColor: Colors.transparent,
          body: MascotEmpty(
            message: 'Aucune notification',
            hint: 'Claude vous préviendra ici.',
          ),
        ),
      ),
    ),
  );
}

/// Pompe l'écran en laissant le PNG de la mascotte se décoder : sans
/// `runAsync` + `precacheImage`, l'image reste vide dans le golden.
Future<void> _pump(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(412, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(() async {
    await tester.pumpWidget(app);
    await precacheImage(
      const AssetImage('assets/icon/mascot.png'),
      tester.element(find.byType(MascotEmpty)),
    );
  });
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('état vide — base sombre', (tester) async {
    await _pump(tester, _wrap(dark: true));
    await expectLater(
      find.byType(MascotEmpty),
      matchesGoldenFile('goldens/empty_state_dark.png'),
    );
  });

  testWidgets('état vide — base claire', (tester) async {
    await _pump(tester, _wrap(dark: false));
    await expectLater(
      find.byType(MascotEmpty),
      matchesGoldenFile('goldens/empty_state_light.png'),
    );
  });
}
