// Les effets qui font qu'un jeu se joue (idée #77) : appui qui répond,
// secousse à l'erreur, étincelles à la réussite, score qui saute.
//
// Ce qui compte ici : un effet ne doit JAMAIS retenir une manche. Le contenu
// est là avant, pendant et après l'animation — un joueur qui tape pendant une
// secousse doit être entendu.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/screens/games/game_fx.dart';
import 'package:gullify/theme.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: gullifyThemeFor(GullifyAccent.indigo, dark: false),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('un élément s\'enfonce sous le doigt et rend la main', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        PressPop(
          onTap: () => taps++,
          child: const SizedBox(width: 120, height: 60, child: Text('Jouer')),
        ),
      ),
    );

    double scale() =>
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
    expect(scale(), 1);

    final gesture = await tester.startGesture(tester.getCenter(find.text('Jouer')));
    await tester.pump();
    expect(scale(), lessThan(1));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(scale(), 1);
    expect(taps, 1);
  });

  testWidgets('sans action, rien ne s\'enfonce', (tester) async {
    await tester.pumpWidget(_wrap(const PressPop(child: Text('Figé'))));
    final gesture = await tester.startGesture(tester.getCenter(find.text('Figé')));
    await tester.pump();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    await gesture.up();
  });

  testWidgets('la secousse part à l\'erreur, et laisse le contenu en place', (
    tester,
  ) async {
    Offset shift() {
      final box = tester.renderObject<RenderBox>(find.text('Raté'));
      return box.localToGlobal(Offset.zero);
    }

    await tester.pumpWidget(
      _wrap(const ShakeBox(trigger: 0, child: Text('Raté'))),
    );
    final rest = shift();

    await tester.pumpWidget(
      _wrap(const ShakeBox(trigger: 1, child: Text('Raté'))),
    );
    await tester.pump(const Duration(milliseconds: 80));
    // Ça bouge…
    expect(shift().dx, isNot(closeTo(rest.dx, 0.5)));
    // … le texte reste lisible et cliquable pendant ce temps.
    expect(find.text('Raté'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(shift().dx, closeTo(rest.dx, 0.5));
  });

  testWidgets('les étincelles ne partent qu\'à la réussite, et s\'éteignent', (
    tester,
  ) async {
    // Le décor de l'écran peint déjà des choses : ce qu'on compte, c'est ce
    // que la fête ajoute par-dessus.
    int painters() => find.byType(CustomPaint).evaluate().length;

    await tester.pumpWidget(
      _wrap(const Celebration(trigger: 0, child: Text('Manche'))),
    );
    final rest = painters();

    await tester.pumpWidget(
      _wrap(const Celebration(trigger: 1, child: Text('Manche'))),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(painters(), rest + 1);

    await tester.pumpAndSettle();
    expect(painters(), rest);
    // Les étincelles n'ont jamais volé le doigt du joueur.
    expect(
      tester
          .widgetList<IgnorePointer>(
            find.descendant(
              of: find.byType(Celebration),
              matching: find.byType(IgnorePointer),
            ),
          )
          .any((w) => w.ignoring),
      isTrue,
    );
  });

  testWidgets('le score saute quand il change, et affiche la bonne valeur', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const PoppingNumber(text: '30')));
    expect(find.text('30'), findsOneWidget);

    await tester.pumpWidget(_wrap(const PoppingNumber(text: '95')));
    await tester.pump(const Duration(milliseconds: 160));
    final popped = tester
        .widget<Transform>(find.ancestor(
          of: find.text('95'),
          matching: find.byType(Transform),
        ))
        .transform
        .getMaxScaleOnAxis();
    expect(popped, greaterThan(1));

    await tester.pumpAndSettle();
    expect(find.text('95'), findsOneWidget);
  });

  testWidgets('le verdict annonce la couleur', (tester) async {
    await tester.pumpWidget(
      _wrap(const GameVerdict(correct: true, text: 'Bien vu !')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bien vu !'), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.check_circle_rounded)).color,
      gameGood,
    );

    await tester.pumpWidget(
      _wrap(const GameVerdict(correct: false, text: 'Raté')),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Icon>(find.byIcon(Icons.cancel_rounded)).color,
      gameBad,
    );
  });

  testWidgets('une zone de dépôt éteinte ne prend pas la carte', (
    tester,
  ) async {
    var drops = 0;
    await tester.pumpWidget(
      _wrap(GlowDropZone(enabled: false, onTap: () => drops++)),
    );
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    expect(drops, 0);

    await tester.pumpWidget(
      _wrap(GlowDropZone(enabled: true, onTap: () => drops++)),
    );
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    expect(drops, 1);
  });

  testWidgets('rien ne tourne quand rien ne joue', (tester) async {
    // Un disque et une onde à l'arrêt ne doivent pas animer en boucle :
    // c'est ce qui permet à une scène de se stabiliser (et à la batterie de
    // tenir quand l'extrait est en pause).
    await tester.pumpWidget(
      _wrap(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MysteryDisc(playing: false, size: 100),
            SoundWave(playing: false),
            BeatPulse(playing: false, child: Text('immobile')),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('immobile'), findsOneWidget);
  });

  testWidgets('le chrono en anneau garde son contenu lisible', (tester) async {
    await tester.pumpWidget(
      _wrap(const CountdownRing(ratio: 0.1, child: Text('3 s'))),
    );
    // Sous le quart du temps l'anneau bat : la scène ne se stabilise plus,
    // on ne l'attend donc pas.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('3 s'), findsOneWidget);
  });
}
