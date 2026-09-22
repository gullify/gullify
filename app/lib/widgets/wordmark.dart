import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
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

/// La pile de polices du LOGOTYPE — la même que les sites de la gamme
/// (`--police-logo` dans leur base.css) : celle de l'appareil, pas celle de
/// l'app.
///
/// C'est une décision de gamme : GulliFY, GulliTV et GulliVR écrivent leur nom
/// dans la police du système, très grasse et resserrée. Le reste de l'app
/// garde HankenGrotesk ; seul le nom de la marque s'en écarte, pour être le
/// même ici et sur gullify.app.
///
/// Sur Android, sur iPhone et sur le téléviseur, c'est bien la police du
/// système — le nom s'y écrit exactement comme sur gullify.app.
///
/// **Sur le web, c'est impossible** : le moteur de rendu dessine le texte
/// lui-même et n'a pas accès aux polices installées sur la machine. Laissé à
/// lui-même il prend la sienne (Roboto), qui ne ressemble pas à ce que le site
/// affiche à côté, dans le même navigateur.
///
/// Sur Windows, cette pile donne **Segoe UI Bold** — police Microsoft, qu'on
/// n'a pas le droit de redistribuer. On embarque donc la plus proche qui soit
/// libre : Open Sans, de la même famille humaniste, figée à la graisse du
/// logotype et réduite à l'alphabet — 12 Ko.
const _policeLogo = <String>[
  '-apple-system',
  'BlinkMacSystemFont',
  'Segoe UI',
  'Roboto',
  'Helvetica Neue',
  'Arial',
];

/// La police embarquée qui remplace la pile système là où elle est hors
/// d'atteinte. Les essais la basculent pour vérifier les deux chemins.
@visibleForTesting
bool logotypeEmbarque = kIsWeb;

/// La famille à demander, et sa suite de repli.
({String famille, List<String> repli}) _familleDuLogotype() => logotypeEmbarque
    ? (famille: 'LogoSans', repli: _policeLogo)
    : (famille: _policeLogo.first, repli: _policeLogo.sublist(1));

/// Les deux réglages du logotype, repris de la feuille de style des trois
/// sites (`.marque`) : approche **-0,03 em** et graisse **800**. Ils sont
/// imposés ici plutôt que laissés à chaque appelant — c'est ce qui fait qu'un
/// logo reste le même logo d'un écran à l'autre.
const _approcheLogo = -0.03;
const _graisseLogo = FontWeight.w800;

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
    final police = _familleDuLogotype();
    // L'approche se compte en em : il faut donc la taille réellement appliquée,
    // celle du style reçu ou, à défaut, celle du texte ambiant.
    final taille =
        style?.fontSize ?? DefaultTextStyle.of(context).style.fontSize ?? 14.0;
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
      // La police du logotype passe APRÈS le style reçu : un appelant règle la
      // graisse, l'approche et la couleur — jamais la famille.
      style: (style ?? const TextStyle()).copyWith(
        fontFamily: police.famille,
        fontFamilyFallback: police.repli,
        // Graisse et approche du logotype : l'appelant règle la taille et la
        // couleur, le reste appartient à la marque.
        fontWeight: _graisseLogo,
        letterSpacing: taille * _approcheLogo,
      ),
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
