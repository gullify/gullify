import 'package:flutter/material.dart';

import 'artwork.dart';

/// Vignette d'un genre : mosaïque 2×2 des pochettes quand il y en a assez,
/// une seule pochette sinon, et le dégradé neutre d'[Artwork] quand le
/// genre n'en a aucune.
class GenreMosaic extends StatelessWidget {
  const GenreMosaic({
    super.key,
    required this.urls,
    this.size,
    this.radius = 20,
  });

  final List<String> urls;
  final double? size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (urls.length < 4) {
      return Artwork(
        url: urls.isEmpty ? null : urls.first,
        size: size,
        borderRadius: radius,
        icon: Icons.label_outline,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: Column(
          children: [
            for (final row in [urls.sublist(0, 2), urls.sublist(2, 4)])
              Expanded(
                child: Row(
                  children: [
                    for (final url in row)
                      Expanded(child: Artwork(url: url, borderRadius: 0)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
