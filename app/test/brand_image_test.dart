import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/widgets/brand_image.dart';
import 'package:gullify/widgets/wordmark.dart';

/// Le goéland passait de 324 px de source à 96 px à l'écran par une réduction
/// au dessin, que le web crénelle. Ces essais vérifient qu'il est désormais
/// décodé à la taille où on le voit — et qu'on ne l'agrandit jamais au
/// décodage, ce qui serait le défaut inverse.
void main() {
  // Les essais tournent sur la machine virtuelle, où `kIsWeb` est faux : on
  // bascule le drapeau pour vérifier les deux comportements.
  setUp(() => BrandImage.decodeALaTaille = true);
  tearDown(() => BrandImage.decodeALaTaille = kIsWeb);

  /// Le provider de la première image trouvée, dépouillé de ses habillages.
  ImageProvider imageDe(WidgetTester tester) =>
      tester.widget<Image>(find.byType(Image).first).image;

  Future<void> poser(
    WidgetTester tester,
    Widget enfant, {
    required double ratio,
  }) {
    return tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(devicePixelRatio: ratio),
        child: Directionality(textDirection: TextDirection.ltr, child: enfant),
      ),
    );
  }

  testWidgets('la mascotte est décodée à la taille où elle est vue', (
    tester,
  ) async {
    await poser(
      tester,
      const BrandImage('assets/icon/mascot.png', width: 96, height: 96),
      ratio: 2,
    );

    final provider = imageDe(tester);
    expect(
      provider,
      isA<ResizeImage>(),
      reason:
          'sans redimensionnement au décodage, le web crénelle la réduction',
    );
    expect(
      (provider as ResizeImage).height,
      192,
      reason: '96 px logiques sur un écran à 2 pixels par point',
    );
  });

  testWidgets(
    'sur un écran très dense, on ne décode pas plus gros que la source',
    (tester) async {
      // 96 × 4 = 384, au-delà des 324 px de mascot.png : demander 384 au décodeur
      // ne créerait pas de détail, cela ne ferait qu'agrandir du flou.
      await poser(
        tester,
        const BrandImage('assets/icon/mascot.png', width: 96, height: 96),
        ratio: 4,
      );

      expect(imageDe(tester), isA<AssetImage>());
    },
  );

  testWidgets('le signe du logo suit la même règle', (tester) async {
    await poser(tester, const GulliLogo(fontSize: 38), ratio: 2);

    final provider = imageDe(tester);
    expect(provider, isA<ResizeImage>());
    // 38 × 1,74 = 66,12 pixels logiques de haut, soit 132 pixels réels.
    expect((provider as ResizeImage).height, 132);
  });

  testWidgets('hors du web, le rendu ne change pas', (tester) async {
    // Sur le moteur natif la réduction au dessin rend déjà bien (mesuré) :
    // l'image garde son chemin habituel, et les images de référence des
    // essais ne bougent pas.
    BrandImage.decodeALaTaille = false;
    await poser(
      tester,
      const BrandImage('assets/icon/mascot.png', width: 96, height: 96),
      ratio: 2,
    );

    expect(imageDe(tester), isA<AssetImage>());
  });
}
