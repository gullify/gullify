import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/pour_toi_repository.dart';
import '../state/library.dart';
import '../state/player.dart';
import '../state/pour_toi.dart';
import 'album_card.dart' show kArtShadow;
import 'artwork.dart';

/// « Pour toi » sur l'accueil : les mix, les découvertes de la semaine, ce qui
/// tourne en boucle, les perles oubliées, le mix du moment — puis les
/// artistes à découvrir hors de la bibliothèque. Tout se calcule la nuit sur
/// le serveur ; un serveur d'avant (sans Pour toi) ne montre rien.
class PourToiSection extends ConsumerWidget {
  const PourToiSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accueil = ref.watch(pourToiAccueilProvider);
    // En erreur, isLoading peut rester vrai pendant la reprise : on regarde
    // hasError d'abord.
    if (accueil.hasError || !accueil.hasValue) return const SizedBox.shrink();
    final rayons = accueil.value!.rayons;
    final listes = [
      for (final r in rayons)
        if (r.type != 'ailleurs') r,
    ];
    final ailleurs = [
      for (final r in rayons)
        if (r.type == 'ailleurs') r,
    ];
    if (listes.isEmpty && ailleurs.isEmpty) return const _PourToiVide();
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Pour toi',
                  style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: () => context.push('/gouts'),
                icon: Icon(
                  Icons.insights_outlined,
                  size: 18,
                  color: scheme.primary,
                ),
                label: const Text('Tes goûts'),
              ),
            ],
          ),
        ),
        if (listes.isNotEmpty)
          SizedBox(
            height: 236,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              itemCount: listes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 13),
              itemBuilder: (context, i) => RayonCard(rayon: listes[i]),
            ),
          ),
        for (final r in ailleurs) _AilleursRow(rayon: r),
      ],
    );
  }
}

/// Avant la première écoute : dire ce qui va venir plutôt que rien.
class _PourToiVide extends StatelessWidget {
  const _PourToiVide();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(
        children: [
          Icon(Icons.auto_awesome_outlined, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Écoute quelques albums : tes mix et tes découvertes arrivent ici.',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

IconData rayonIcon(String type) => switch (type) {
  'decouvertes' => Icons.explore_outlined,
  'boucle' => Icons.repeat,
  'oubliees' => Icons.history,
  'moment' => Icons.schedule,
  _ => Icons.graphic_eq,
};

/// La vignette d'un rayon : quatre pochettes en mosaïque, un bouton de
/// lecture (lancer sans ouvrir), le titre et ses artistes.
class RayonCard extends ConsumerStatefulWidget {
  const RayonCard({super.key, required this.rayon, this.size = 150});

  final Rayon rayon;
  final double size;

  @override
  ConsumerState<RayonCard> createState() => _RayonCardState();
}

class _RayonCardState extends ConsumerState<RayonCard> {
  bool _busy = false;

  Future<void> _play() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final detail = await ref.read(rayonProvider(widget.rayon.id).future);
      if (detail.titres.isEmpty) return;
      await ref
          .read(playerActionsProvider)
          .playRecos(melangerPourLancer(detail.titres));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Échec : $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.rayon;
    final scheme = Theme.of(context).colorScheme;
    final size = widget.size;
    return SizedBox(
      width: size,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.push('/pour-toi/${r.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [kArtShadow],
                  ),
                  child: RayonMosaic(rayon: r, size: size),
                ),
                Positioned(
                  left: 10,
                  top: 10,
                  child: _Badge(icon: rayonIcon(r.type), numero: r.numero),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Material(
                    color: scheme.primary,
                    shape: const CircleBorder(),
                    elevation: 3,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _busy ? null : _play,
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: _busy
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: scheme.onPrimary,
                                  ),
                                )
                              : Icon(
                                  Icons.play_arrow_rounded,
                                  color: scheme.onPrimary,
                                  semanticLabel: 'Lire ${r.titre} en aléatoire',
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              r.titre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (r.sousTitre != null)
              Text(
                r.sousTitre!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, this.numero});

  final IconData icon;
  final int? numero;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: scheme.primary),
            if (numero != null) ...[
              const SizedBox(width: 3),
              Text(
                '$numero',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Quatre pochettes en carré (une seule si le rayon n'en a qu'une).
class RayonMosaic extends StatelessWidget {
  const RayonMosaic({super.key, required this.rayon, required this.size});

  final Rayon rayon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final urls = rayon.apercu;
    final half = size / 2;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        width: size,
        height: size,
        child: urls.length < 4
            ? Artwork(
                url: urls.isEmpty ? null : urls.first,
                size: size,
                borderRadius: 0,
                icon: rayonIcon(rayon.type),
              )
            : Wrap(
                children: [
                  for (final u in urls.take(4))
                    Artwork(url: u, size: half, borderRadius: 0),
                ],
              ),
      ),
    );
  }
}

/// « À découvrir ailleurs » : des artistes absents de la bibliothèque. Un
/// toucher les cherche (ici ou sur YouTube) pour les écouter et les
/// télécharger.
class _AilleursRow extends ConsumerWidget {
  const _AilleursRow({required this.rayon});

  final Rayon rayon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Text(
            rayon.titre,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
        ),
        if (rayon.sousTitre != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 1, 20, 0),
            child: Text(
              rayon.sousTitre!,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
        SizedBox(
          height: 172,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
            itemCount: rayon.artistes.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) {
              final a = rayon.artistes[i];
              return SizedBox(
                width: 112,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    ref.read(searchQueryProvider.notifier).set(a.nom);
                    context.go('/search');
                  },
                  child: Column(
                    children: [
                      Artwork(
                        url: a.image,
                        size: 84,
                        borderRadius: 42,
                        icon: Icons.person,
                      ),
                      const SizedBox(height: 7),
                      Text(
                        a.nom,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        a.pourquoi,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.15,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
