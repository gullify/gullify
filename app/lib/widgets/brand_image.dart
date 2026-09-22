import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/widgets.dart';

/// Les dimensions natives des images de marque.
///
/// Elles sont écrites ici pour deux raisons : décider si le décodage à la
/// taille d'affichage est un gain (il ne l'est que s'il RÉDUIT — agrandir au
/// décodage ne crée pas de détail, il étire du flou), et le savoir sans avoir
/// à charger l'image une première fois pour la mesurer.
///
/// Si une de ces images est remplacée par une version plus grande, la valeur
/// doit suivre : sous-estimée, on perd le bénéfice ; surestimée, on décode
/// plus gros que la source.
const Map<String, Size> _naturelles = {
  'assets/icon/mascot.png': Size(324, 324),
  'assets/icon/mark.png': Size(212, 302),
  'assets/icon/logo.png': Size(324, 324),
};

/// Une image de marque — le goéland, le signe, le logo — décodée à la taille
/// où elle sera vue quand la plateforme le demande.
///
/// **Le défaut.** Sur le web, à un pixel par point, réduire l'image au moment
/// du dessin la crénelle : les branches des lunettes et les fils du casque se
/// cassent en marches d'escalier. `FilterQuality` n'y change rien — mesuré sur
/// une compilation web réelle, la mascotte à 96 px donnait un laplacien de
/// 0,053 sans filtre et 0,055 en `medium`, soit le même crénelage.
///
/// **Le piège.** Décoder à la taille EXACTE de l'affichage supprime bien le
/// crénelage, mais ramollit le dessin dès que l'écran est dense : à 1,25 et
/// 1,5 pixel par point — les mises à l'échelle de Windows — la huppe devient
/// une tache et les lunettes perdent leur pont. Le rééchantillonneur du
/// décodeur est plus grossier que celui du moteur de rendu.
///
/// **La règle retenue.** Décoder à DEUX fois la taille d'affichage : le moteur
/// reçoit de quoi travailler et sa réduction de 2 pour 1 (celle qu'il fait
/// bien) rend net à toutes les densités. Au-delà de la source, on ne demande
/// rien et l'image suit son chemin habituel.
///
/// **Pourquoi seulement le web.** Sur le moteur natif (Android, et les images
/// de référence des essais), la réduction au dessin passe par les mipmaps et
/// rend déjà bien : le même logo mesure 0,4957 avant et 0,4943 après, c'est un
/// match nul. Changer là où rien ne cloche ne ferait que déplacer le risque.
///
/// **Comment.** `cacheHeight` fait rééchantillonner l'image par le décodeur ;
/// le dessin se fait ensuite à l'échelle 1, où il n'y a plus rien à perdre.
/// Seule la hauteur est donnée : la largeur suit le rapport de l'image, sans
/// risque de la déformer d'un pixel.
class BrandImage extends StatelessWidget {
  const BrandImage(
    this.asset, {
    super.key,
    required this.width,
    required this.height,
  });

  /// Le chemin de l'image, tel qu'il figure dans `pubspec.yaml`.
  final String asset;

  /// La taille à l'écran, en pixels logiques.
  final double width;
  final double height;

  /// Vrai là où la réduction au dessin crénelle. Les essais la basculent pour
  /// vérifier les deux comportements sans compiler pour le web.
  @visibleForTesting
  static bool decodeALaTaille = kIsWeb;

  /// Combien de fois la taille d'affichage on demande au décodeur. Un seul
  /// (taille exacte) ramollit le dessin sur les écrans denses ; deux laisse au
  /// moteur la réduction qu'il réussit.
  static const _sureffet = 2;

  @override
  Widget build(BuildContext context) {
    final naturelle = _naturelles[asset];
    // Deux fois la taille réelle à l'écran : de quoi suréchantillonner.
    final voulue = (height * MediaQuery.devicePixelRatioOf(context) * _sureffet)
        .round();

    // Rien à gagner hors du web, si l'on ne connaît pas la source, ou si
    // l'affichage demande déjà plus de pixels qu'elle n'en a.
    final cache =
        (!decodeALaTaille || naturelle == null || voulue >= naturelle.height)
        ? null
        : voulue;

    return Image.asset(
      asset,
      width: width,
      height: height,
      cacheHeight: cache,
      // Pour le reste : les écrans dont le rapport de pixels n'est pas entier,
      // et le cas où l'image est agrandie faute de source plus grande.
      filterQuality: FilterQuality.medium,
    );
  }
}
