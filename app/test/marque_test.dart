// La marque : GulliFY, et la gamme Gulli.
//
// « Gulli » ne bouge pas — c'est le nom de la maison. Seul le suffixe porte la
// couleur de l'entité : vert pour le lecteur audio (le fond de l'icône), rouge
// pour l'IPTV, mauve pour la réalité virtuelle.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/theme.dart';
import 'package:gullify/widgets/wordmark.dart';

void main() {
  group('le logo', () {
    testWidgets(
      '« Gulli » dans la couleur du texte, le suffixe dans la sienne',
      (tester) async {
        // GulliFY est dessiné (voir logotype_test) ; le nom écrit reste pour les
        // entités qui n'ont pas encore leur image, et la règle de couleur y est
        // la même : « Gulli » suit le texte, le suffixe porte l'entité.
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: GulliWordmark(
                product: GulliProduct.tv,
                style: TextStyle(color: Color(0xFF111111)),
              ),
            ),
          ),
        );

        final rendu = tester.widget<Text>(find.byType(Text));
        final morceaux = (rendu.textSpan! as TextSpan).children!
            .cast<TextSpan>();
        expect(morceaux.map((s) => s.text).join(), 'GulliTV');
        expect(
          morceaux.first.style?.color,
          isNull,
          reason: '« Gulli » suit la couleur ambiante',
        );
        expect(morceaux.last.style?.color, GulliProduct.tv.color);
      },
    );

    test('une couleur par entité de la gamme', () {
      expect(GulliProduct.fy.name, 'GulliFY');
      expect(GulliProduct.fy.color, gullifyGreen);
      expect(GulliProduct.tv.name, 'GulliTV');
      expect(GulliProduct.tv.color, const Color(0xFFFF0000));
      expect(GulliProduct.vr.name, 'GulliVR');
      expect(GulliProduct.vr.color, const Color(0xFF8B5CF6));
    });
  });

  group("le vert de la marque", () {
    test('est celui déclaré comme fond de l\'icône', () {
      // Trois fichiers doivent dire la même couleur : si l'un bouge sans les
      // autres, le logo cesse de reprendre le fond de son icône.
      final hex = gullifyGreen.toARGB32().toRadixString(16).substring(2);
      expect(
        File('pubspec.yaml').readAsStringSync(),
        contains('adaptive_icon_background: "#${hex.toUpperCase()}"'),
      );
      expect(
        File('android/app/src/main/res/values/colors.xml').readAsStringSync(),
        contains('"ic_launcher_background">#${hex.toUpperCase()}<'),
      );
    });

    test('est l\'accent par défaut, et proposé dans l\'apparence', () {
      expect(GullifyAccent.values.first, GullifyAccent.vert);
      expect(GullifyAccent.vert.color, gullifyGreen);
    });
  });

  group('le nom affiché', () {
    test('GulliFY sur Android, iOS et le web', () {
      expect(
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        contains('android:label="GulliFY"'),
      );
      expect(
        File('ios/Runner/Info.plist').readAsStringSync(),
        contains('<key>CFBundleDisplayName</key>\n\t<string>GulliFY</string>'),
      );
      final manifeste = jsonDecode(
        File('web/manifest.json').readAsStringSync(),
      );
      expect(manifeste['name'], 'GulliFY');
      expect(manifeste['short_name'], 'GulliFY');
      expect(
        File('web/index.html').readAsStringSync(),
        contains('<title>GulliFY</title>'),
      );
    });

    test('mais le serveur s\'annonce toujours « Gullify »', () {
      // La poignée de main de ping.php. L'app compare cette valeur exacte :
      // la renommer d'un seul côté empêcherait toute connexion.
      expect(
        File('lib/state/auth.dart').readAsStringSync(),
        contains("data['server'] != 'Gullify'"),
      );
      expect(
        File('../public/api/v2/ping.php').readAsStringSync(),
        contains("'server'     => 'Gullify'"),
      );
    });
  });
}
