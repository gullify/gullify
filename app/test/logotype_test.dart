import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/widgets/brand_image.dart';
import 'package:gullify/widgets/wordmark.dart';

/// Le logotype de la gamme s'écrit dans la police du système — Segoe UI Black
/// sur Windows, que le moteur de rendu web ne peut pas atteindre et qu'on n'a
/// pas le droit d'embarquer. Le mot « GulliFY » est donc une image, capturée
/// une fois là où le site s'affiche, en deux calques teintables. Les entités
/// qui n'ont pas encore leur image gardent le texte, aux réglages du logotype.
void main() {
  setUp(() => BrandImage.decodeALaTaille = false);
  tearDown(() => BrandImage.decodeALaTaille = kIsWeb);

  Future<void> poser(WidgetTester tester, Widget enfant) => tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'HankenGrotesk'),
      home: Scaffold(body: Center(child: enfant)),
    ),
  );

  List<ColorFiltered> calques(WidgetTester tester) =>
      tester.widgetList<ColorFiltered>(find.byType(ColorFiltered)).toList();

  testWidgets('le nom de la marque est dessiné, pas composé', (tester) async {
    await poser(
      tester,
      const GulliWordmark(
        style: TextStyle(fontSize: 40, color: Color(0xFFEEEEEE)),
      ),
    );

    final images = tester.widgetList<BrandImage>(find.byType(BrandImage));
    expect(
      images.map((i) => i.asset),
      ['assets/icon/wordmark_nom.png', 'assets/icon/wordmark_fy.png'],
      reason: 'deux calques : le nom, puis le suffixe par-dessus',
    );
    // 1232 × 303 pour une police de 400 : le rapport relie la taille demandée
    // aux pixels dessinés.
    expect(images.first.height, closeTo(40 * 303 / 400, 0.001));
    expect(images.first.width, closeTo(40 * 1232 / 400, 0.001));
  });

  testWidgets('le nom suit le texte, le suffixe suit l\'entité', (
    tester,
  ) async {
    await poser(
      tester,
      const GulliWordmark(
        style: TextStyle(fontSize: 40, color: Color(0xFFEEEEEE)),
      ),
    );

    final teintes = calques(tester);
    expect(teintes.length, 2);
    expect(
      teintes[0].colorFilter,
      const ColorFilter.mode(Color(0xFFEEEEEE), BlendMode.srcIn),
      reason: 'le nom prend la couleur du texte, clair ou sombre',
    );
    expect(
      teintes[1].colorFilter,
      ColorFilter.mode(GulliProduct.fy.color, BlendMode.srcIn),
      reason: 'le suffixe garde le vert de la marque',
    );
  });

  testWidgets('sans image, l\'entité garde le texte et ses réglages', (
    tester,
  ) async {
    // GulliTV et GulliVR n'ont pas encore leur capture : elles s'écrivent, à
    // l'approche (-0,03 em) et à la graisse (800) de la feuille de style des
    // trois sites, jamais dans la police de l'app.
    await poser(
      tester,
      const GulliWordmark(
        product: GulliProduct.tv,
        style: TextStyle(
          fontFamily: 'HankenGrotesk',
          fontSize: 40,
          fontWeight: FontWeight.w400,
          letterSpacing: 2,
        ),
      ),
    );

    final style = tester.widget<Text>(find.byType(Text).first).style!;
    expect(style.fontWeight, FontWeight.w800);
    expect(style.letterSpacing, closeTo(40 * -0.03, 0.0001));
    expect(style.fontFamily, isNot('HankenGrotesk'));
    expect(style.fontFamilyFallback, contains('Segoe UI'));
  });
}
