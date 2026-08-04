import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/album.dart';
import 'artwork.dart';

/// Ombre portée des pochettes du design : 0 14px 26px -10px rgba(20,25,50,.35).
const kArtShadow = BoxShadow(
  color: Color(0x59141932),
  blurRadius: 26,
  offset: Offset(0, 14),
  spreadRadius: -10,
);

/// Carte d'album des grilles (bibliothèque, genre) : pochette carrée
/// radius 20 + ombre, nom 14/700, « artiste · année » 12 gris.
class AlbumGridCard extends StatelessWidget {
  const AlbumGridCard({super.key, required this.album});

  final Album album;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = [
      if (album.artistName != null) album.artistName!,
      if (album.year != null) '${album.year}',
    ].join(' · ');

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => context.push('/album/${album.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [kArtShadow],
              ),
              child: Artwork(url: album.artworkUrl, borderRadius: 20),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            album.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

/// Carte d'album des carrousels (design) : pochette carrée arrondie avec
/// ombre portée, nom 13.5/700, artiste 12 gris.
class AlbumCard extends StatelessWidget {
  const AlbumCard({
    super.key,
    required this.album,
    this.size = 134,
    this.radius = 22,
  });

  final Album album;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      child: InkWell(
        onTap: () => context.push('/album/${album.id}'),
        borderRadius: BorderRadius.circular(radius),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                boxShadow: const [kArtShadow],
              ),
              child: Artwork(
                url: album.artworkUrl,
                size: size,
                borderRadius: radius,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              album.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
            if (album.artistName != null)
              Text(
                album.artistName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
