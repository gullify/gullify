import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.url,
    this.size,
    this.borderRadius = 10,
    this.icon = Icons.album,
  });

  final String? url;
  final double? size;
  final double borderRadius;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            gullifyAmber.withValues(alpha: 0.25),
            Colors.black.withValues(alpha: 0.6),
          ],
        ),
      ),
      child: Icon(
        icon,
        size: (size ?? 48) * 0.45,
        color: Colors.white.withValues(alpha: 0.5),
      ),
    );

    // Rétro Winamp (idée #82) : les pochettes se carrent, comme tout le
    // reste du châssis. Un seul endroit à changer pour toute l'app.
    final retro =
        Theme.of(context).extension<GullifySurfaces>()?.retro ?? false;

    // Décodage borné à ce qui est réellement affiché.
    //
    // `serve_image.php` rend la pochette SOURCE, souvent en 1400 px et plus :
    // sans cette borne, une vignette de 56 px occupait quand même ~8 Mo en
    // mémoire une fois décodée. Sur un téléphone ça passait ; sur un boîtier
    // Google TV, un écran d'accueil plein de pochettes épuisait la mémoire et
    // l'app finissait par se faire tuer. On décode donc à la taille affichée,
    // au facteur de pixels près pour rester net.
    //
    // Une seule dimension, la largeur : avec les deux, le décodeur rend
    // EXACTEMENT ce carré et écrase l'image au passage. Bon nombre de
    // pochettes n'en sont pas une — les vignettes trouvées sur le web
    // arrivent en 16:9, la pochette carrée au milieu et des bandes de
    // couleur peintes de chaque côté. Écrasées, elles montraient ces bandes
    // (« un rectangle pas assez large avec un fond des deux côtés ») alors
    // que le web, qui ignore ces bornes, les recadrait proprement. Avec la
    // largeur seule, les proportions sont gardées et `BoxFit.cover` fait
    // son travail : on ne voit que le centre, c'est-à-dire la pochette.
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final decode = size == null ? null : (size! * dpr).round();

    // Mieux que recadrer après coup : demander la pochette déjà carrée. Le
    // serveur sait le faire et garde une copie par palier — ce sont les
    // mêmes paliers que le téléviseur, donc les mêmes fichiers.
    final adresse = carree(url, size, dpr);

    // Mode « dossier local » (idée #114) : la pochette a été extraite du
    // fichier audio et vit sur le disque de l'app — un chemin, pas une adresse.
    // Rien à mettre en cache réseau, mais le même plafond de décodage.
    final local = url != null && url!.startsWith('/');

    return ClipRRect(
      borderRadius: BorderRadius.circular(retro ? 0 : borderRadius),
      child: url == null
          ? SizedBox(width: size, height: size, child: placeholder)
          : local
              ? Image.file(
                  File(url!),
                  width: size,
                  height: size,
                  cacheWidth: decode,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => placeholder,
                )
              : CachedNetworkImage(
                  imageUrl: adresse!,
                  width: size,
                  height: size,
                  memCacheWidth: decode,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => placeholder,
                  errorWidget: (_, _, _) => placeholder,
                ),
    );
  }
}

/// Paliers de taille demandés au serveur, qui en garde une copie (il plafonne
/// lui-même à 1024). Les mêmes que ceux du téléviseur : une pochette déjà
/// réduite pour l'écran d'accueil du salon sert aussi la vignette du
/// téléphone, sans fabriquer un fichier par taille de vignette.
const _paliers = [128, 256, 384, 512, 768, 1024];

/// Au-delà de cette taille d'affichage, on prend la source.
///
/// Réduire sert aux vignettes : une liste de cent pastilles de 48 points ne
/// doit pas faire voyager cent images de 800 px. Mais le grand portrait en
/// tête d'une fiche se REGARDE, et une image réduite par le serveur puis
/// redessinée à l'écran a traversé deux rééchantillonnages au lieu d'un — ce
/// qui se voit tout de suite, surtout sur le web, qui prenait la source
/// entière jusqu'ici. Il n'y en a qu'une par page : qu'elle vienne entière.
const _vignetteMax = 96.0;

/// L'adresse à demander : la pochette recadrée en carré quand le serveur sait
/// le faire, la source telle quelle sinon.
///
/// Quatre cas prennent la source. Sans taille connue (la grande pochette du
/// lecteur, les tuiles d'une grille) il n'y a pas de palier à choisir, et
/// `BoxFit.cover` suffit à l'écran. Au-dessus de [_vignetteMax], réduire
/// coûterait plus de netteté qu'il ne fait gagner d'octets. Une vignette
/// externe — logo de radio, image Deezer, miniature YouTube — ne comprend
/// pas `size`. Et une adresse déjà pourvue d'un `size` vient du téléviseur,
/// qui a déjà choisi.
String? carree(String? url, double? size, double dpr) {
  if (url == null || size == null || size > _vignetteMax) return url;
  if (!url.contains('serve_image.php')) return url;
  if (url.contains('size=')) return url;
  final besoin = (size * dpr).round();
  final cote = _paliers.firstWhere((p) => p >= besoin, orElse: () => 1024);
  return '$url${url.contains('?') ? '&' : '?'}size=$cote';
}
