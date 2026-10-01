import 'dart:ui' as ui;
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/widgets/artwork.dart';

void main() {
  group('carree — quelle adresse demander', () {
    test('demande au serveur un carré au palier supérieur', () {
      expect(carree('https://m.gullify.app/serve_image.php?album_id=7', 132),
          'https://m.gullify.app/serve_image.php?album_id=7&size=256');
      expect(carree('/serve_image.php?album_id=7', 128),
          '/serve_image.php?album_id=7&size=128');
      expect(carree('/serve_image.php?album_id=7', 129),
          '/serve_image.php?album_id=7&size=256');
    });

    test('plafonne au plus grand palier', () {
      expect(carree('/serve_image.php?album_id=7', 4000),
          '/serve_image.php?album_id=7&size=1024');
    });

    test('sans taille connue, la source telle quelle', () {
      // La grande pochette du lecteur et les tuiles d'une grille : c'est
      // `BoxFit.cover` qui recadre, à l'écran.
      expect(carree('/serve_image.php?album_id=7', null),
          '/serve_image.php?album_id=7');
    });

    test('une vignette externe ne comprend pas « size »', () {
      const yt = 'https://i.ytimg.com/vi/abc/hqdefault.jpg';
      expect(carree(yt, 132), yt);
    });

    test('une adresse déjà dimensionnée (téléviseur) passe intacte', () {
      const tv = '/serve_image.php?album_id=7&size=512';
      expect(carree(tv, 132), tv);
    });

    test('rien à demander sans adresse', () {
      expect(carree(null, 132), isNull);
    });
  });

  group('le décodage garde les proportions', () {
    // Ce que fait vraiment le décodeur, mesuré — c'est la prémisse de tout le
    // correctif. Si quelqu'un remet une hauteur à côté de la largeur, une
    // pochette qui n'est pas carrée redevient un carré écrasé, et les bandes
    // peintes dans l'image réapparaissent sur Android.
    late Uint8List octets; // une image 800×450, la forme exacte du défaut

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      octets = File('test/fixtures/pochette_16_9.png').readAsBytesSync();
    });

    Future<ui.Image> decode({required int largeur, int? hauteur}) async {
      final codec = await ui.instantiateImageCodec(octets,
          targetWidth: largeur, targetHeight: hauteur);
      return (await codec.getNextFrame()).image;
    }

    test('largeur seule : les proportions 16:9 sont gardées', () async {
      final image = await decode(largeur: 132);
      expect(image.width, 132);
      expect(image.height, 74); // 132 × 450/800
      image.dispose();
    });

    test('largeur ET hauteur : l\'image est écrasée en carré', () async {
      final image = await decode(largeur: 132, hauteur: 132);
      expect(image.width, 132);
      expect(image.height, 132); // les proportions sont perdues
      image.dispose();
    });
  });
}
