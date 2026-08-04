import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/artist.dart';
import 'artwork.dart';

/// Rangée d'artiste (design) : avatar rond 54 + ombre, nom 15.5/700,
/// « N albums » 12.5 gris, chevron.
class ArtistRow extends StatelessWidget {
  const ArtistRow({super.key, required this.artist});

  final Artist artist;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push('/artist/${artist.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x29000000),
                    blurRadius: 12,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Artwork(
                url: artist.imageUrl,
                size: 54,
                borderRadius: 27,
                icon: Icons.person,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${artist.albumCount} album'
                    '${artist.albumCount > 1 ? 's' : ''}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 24, color: Color(0xFFB6BAC1)),
          ],
        ),
      ),
    );
  }
}
