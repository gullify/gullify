import 'package:flutter/widgets.dart';

import '../theme.dart' show gullifyGreen;
import 'brand_image.dart';

/// La gamme Gulli : un même nom, une couleur par entité.
///
/// « Gulli » ne change pas — c'est le nom de la maison. Seul le suffixe porte
/// la couleur de l'entité : le vert de l'icône pour le lecteur audio, le rouge
/// de la télévision pour l'IPTV, le mauve pour la réalité virtuelle.
enum GulliProduct {
  /// Le lecteur audio — cette app. Le vert du fond de l'icône.
  fy('FY', gullifyGreen),

  /// Le lecteur IPTV, à venir. Rouge, comme la télévision.
  tv('TV', Color(0xFFFF0000)),

  /// Le lecteur pour casque, à venir. Mauve.
  vr('VR', Color(0xFF8B5CF6));

  const GulliProduct(this.suffix, this.color);

  /// Les deux lettres qui suivent « Gulli ».
  final String suffix;

  /// La couleur de ces deux lettres, dans le logo.
  final Color color;

  /// Le nom entier, d'un seul tenant (titres de fenêtre, métadonnées).
  String get name => 'Gulli$suffix';
}

/// Le nom écrit comme un logo : « Gulli » dans la couleur du texte ambiant,
/// le suffixe de l'entité dans la sienne.
///
/// Partout où le nom s'affiche en tant que marque — accueil, connexion, barre
/// latérale, téléviseur. Ailleurs (une phrase qui parle de l'app, les
/// métadonnées d'une notification), c'est du texte ordinaire.
class GulliWordmark extends StatelessWidget {
  const GulliWordmark({
    super.key,
    this.product = GulliProduct.fy,
    this.style,
    this.textAlign,
    this.maxLines = 1,
  });

  final GulliProduct product;

  /// Le style du mot entier. Le suffixe n'en reprend que la couleur.
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'Gulli'),
          TextSpan(
            text: product.suffix,
            style: TextStyle(color: product.color),
          ),
        ],
      ),
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}

/// Le logo complet : le signe et le nom, dans les proportions de la gamme.
///
/// Elles viennent du site de GulliVR : le signe fait **1,74 fois** la taille
/// du texte, et s'en écarte de 0,3 — le même rapport sur téléphone que sur
/// ordinateur, chez eux comme ici.
///
/// L'en-tête de l'accueil montrait un signe deux fois trop petit (0,83) pour
/// deux raisons cumulées : un cadre de 46 px, et une image (`mascot.png`) dont
/// 44 % n'est que de la marge transparente — l'oie n'y rendait que 31 px. Le
/// signe employé ici est détouré : sa taille est celle qu'on voit.
class GulliLogo extends StatelessWidget {
  const GulliLogo({
    super.key,
    this.product = GulliProduct.fy,
    required this.fontSize,
    this.style,
  });

  final GulliProduct product;

  /// La taille du nom. Le signe et l'écart s'en déduisent.
  final double fontSize;

  /// Le style du nom, hors taille (graisse, approche, couleur).
  final TextStyle? style;

  /// Hauteur du signe, en multiples de la taille du texte.
  static const _signe = 1.74;

  /// Écart entre le signe et le nom, en multiples de la taille du texte.
  static const _ecart = 0.3;

  /// Largeur du signe rapportée à sa hauteur (`mark.png` : 212 × 302). Donnée
  /// ici pour que la place du signe soit connue avant même que l'image soit
  /// chargée — sans quoi le nom sauterait au premier affichage.
  static const _rapport = 0.702;

  @override
  Widget build(BuildContext context) {
    final hauteur = fontSize * _signe;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // L'image fait 302 px de haut pour une soixantaine à l'écran :
        // `BrandImage` la fait décoder à sa taille d'affichage, sans quoi la
        // réduction casse les branches des lunettes (surtout sur le web).
        BrandImage(
          'assets/icon/mark.png',
          width: hauteur * _rapport,
          height: hauteur,
        ),
        SizedBox(width: fontSize * _ecart),
        Flexible(
          child: GulliWordmark(
            product: product,
            style: (style ?? const TextStyle()).copyWith(fontSize: fontSize),
          ),
        ),
      ],
    );
  }
}
