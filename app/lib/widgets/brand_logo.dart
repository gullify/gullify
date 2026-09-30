import 'package:flutter/material.dart';

import '../theme.dart';

/// Les marques des deux maisons où Gullify va chercher de la musique — les
/// VRAIS logos, pas une icône Material qui y ressemble de loin (idée #120).
///
/// Elles sont TRACÉES, pas embarquées en image : à 20 px une jaquette de
/// marque réduite crénelle (c'est tout le propos de `brand_image.dart`), et
/// un tracé, lui, reste net à n'importe quelle taille — sur un téléphone
/// comme sur un téléviseur. La géométrie et les couleurs sont relevées sur
/// les fichiers officiels des deux maisons :
///
///  * YouTube Music — cercle rouge #FF0000 de rayon 88 dans une boîte de
///    176, anneau blanc de 4 au rayon 44, triangle blanc (72,65)-(111,87)-
///    (72,111). Le triangle n'est PAS centré dans l'anneau dans le fichier
///    d'origine : il penche à gauche, et on le garde tel quel.
///  * Bandcamp — l'aqua #1DA0C3 et le parallélogramme blanc, 1,702 de large
///    pour 1 de haut, dont chaque arête horizontale couvre 68,2 % de la
///    largeur et se décale de 31,8 % en montant.
///
/// Chaque logo se dessine complet, fond compris : c'est ainsi que les deux
/// maisons le posent sur un fond quelconque (Bandcamp appelle ça son
/// « button » : sa couleur pleine, sa marque en blanc). Une pastille teintée
/// avec la marque de la même couleur dessus ne se verrait pas.

/// Le logo de YouTube Music : disque rouge, anneau et triangle blancs.
class YouTubeMusicLogo extends StatelessWidget {
  const YouTubeMusicLogo({super.key, this.size = 38});

  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: const _YouTubeMusicPainter(),
      );
}

class _YouTubeMusicPainter extends CustomPainter {
  const _YouTubeMusicPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Le fichier officiel vit dans une boîte de 176 : tout est à l'échelle.
    final k = size.shortestSide / 176;
    final center = Offset(88 * k, 88 * k);
    canvas.drawCircle(center, 88 * k, Paint()..color = youtubeMusicRed);
    canvas.drawCircle(
      center,
      44 * k,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 * k,
    );
    canvas.drawPath(
      Path()
        ..moveTo(72 * k, 65 * k)
        ..lineTo(111 * k, 87 * k)
        ..lineTo(72 * k, 111 * k)
        ..close(),
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_YouTubeMusicPainter oldDelegate) => false;
}

/// Le logo de Bandcamp : sa plaque aqua, son parallélogramme blanc.
class BandcampLogo extends StatelessWidget {
  const BandcampLogo({super.key, this.size = 38, this.radius = 12});

  final double size;

  /// Arrondi de la plaque : 12 comme les autres pastilles de l'app.
  final double radius;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _BandcampPainter(radius),
      );
}

class _BandcampPainter extends CustomPainter {
  const _BandcampPainter(this.radius);

  final double radius;

  /// Part de la largeur couverte par une arête horizontale du parallélogramme,
  /// et décalage de l'arête du haut — les deux se complètent à 1.
  static const _run = 0.68167;
  static const _skew = 1 - _run;

  /// Rapport largeur/hauteur de la marque dans le fichier officiel.
  static const _ratio = 1.702;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(radius),
      ),
      Paint()..color = bandcampBlue,
    );
    // La marque occupe 60 % de la plaque, centrée — la proportion des
    // « buttons » officiels.
    final w = size.width * 0.60;
    final h = w / _ratio;
    final left = (size.width - w) / 2;
    final top = (size.height - h) / 2;
    canvas.drawPath(
      Path()
        ..moveTo(left, top + h)
        ..lineTo(left + w * _run, top + h)
        ..lineTo(left + w, top)
        ..lineTo(left + w * _skew, top)
        ..close(),
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_BandcampPainter oldDelegate) =>
      oldDelegate.radius != radius;
}
