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

    return ClipRRect(
      borderRadius: BorderRadius.circular(retro ? 0 : borderRadius),
      child: url == null
          ? SizedBox(width: size, height: size, child: placeholder)
          : CachedNetworkImage(
              imageUrl: url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (_, _) => placeholder,
              errorWidget: (_, _, _) => placeholder,
            ),
    );
  }
}
