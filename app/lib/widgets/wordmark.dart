import 'package:flutter/widgets.dart';

import '../theme.dart' show gullifyGreen;

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
