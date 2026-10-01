import 'dart:ui' as ui;
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/widgets/artwork.dart';

void main() {
  group('carree — quelle adresse demander', () {
    test('une vignette : le serveur la recadre, au palier supérieur', () {
      expect(carree('https://m.gullify.app/serve_image.php?album_id=7', 44, 3),
          'https://m.gullify.app/serve_image.php?album_id=7&size=256');
      expect(carree('/serve_image.php?album_id=7', 64, 2),
          '/serve_image.php?album_id=7&size=128');
      expect(carree('/serve_image.php?album_id=7', 64, 2.1),
          '/serve_image.php?album_id=7&size=256');
    });

    test('au-delà de la vignette, la source entière', () {
      // Le grand portrait d'une fiche : une image réduite par le serveur puis
      // redessinée à l'écran a traversé deux rééchantillonnages, et ça se voit.
      expect(carree('/serve_image.php?artist_id=7', 200, 1),
          '/serve_image.php?artist_id=7');
      expect(carree('/serve_image.php?album_id=7', 140, 3),
          '/serve_image.php?album_id=7');
    });

    test('plafonne au plus grand palier', () {
      expect(carree('/serve_image.php?album_id=7', 96, 12),
          '/serve_image.php?album_id=7&size=1024');
    });

    test('sans taille connue, la source telle quelle', () {
      // Les tuiles d'une grille et la pochette du lecteur : c'est
      // `BoxFit.cover` qui recadre, à l'écran.
      expect(carree('/serve_image.php?album_id=7', null, 3),
          '/serve_image.php?album_id=7');
    });

    test('une vignette externe ne comprend pas « size »', () {
      const yt = 'https://i.ytimg.com/vi/abc/hqdefault.jpg';
      expect(carree(yt, 48, 3), yt);
    });

    test('une adresse déjà dimensionnée (téléviseur) passe intacte', () {
      const tv = '/serve_image.php?album_id=7&size=512';
      expect(carree(tv, 48, 3), tv);
    });

    test('rien à demander sans adresse', () {
      expect(carree(null, 48, 3), isNull);
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
