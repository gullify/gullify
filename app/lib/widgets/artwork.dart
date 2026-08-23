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
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final decode = size == null ? null : (size! * dpr).round();

    return ClipRRect(
      borderRadius: BorderRadius.circular(retro ? 0 : borderRadius),
      child: url == null
          ? SizedBox(width: size, height: size, child: placeholder)
          : CachedNetworkImage(
              imageUrl: url!,
              width: size,
              height: size,
              memCacheWidth: decode,
              memCacheHeight: decode,
              fit: BoxFit.cover,
              placeholder: (_, _) => placeholder,
              errorWidget: (_, _, _) => placeholder,
            ),
    );
  }
}
