import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/pour_toi_repository.dart';
import '../state/player.dart';
import '../state/pour_toi.dart';
import '../widgets/pour_toi_section.dart';
import '../widgets/song_menu.dart';
import '../widgets/song_tile.dart';

/// Un rayon « Pour toi » ouvert : mix, découvertes de la semaine, en boucle…
/// « Tout lire » et « Aléatoire » en tête ; sous chaque titre, pourquoi il
/// est là quand on le sait.
class RayonScreen extends ConsumerWidget {
  const RayonScreen({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(rayonProvider(id));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(detail.value?.rayon.titre ?? 'Pour toi')),
      body: detail.hasError
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Ce rayon a été renouvelé. Retourne à l\'accueil pour voir le nouveau.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            )
          : !detail.hasValue
          ? const Center(child: CircularProgressIndicator())
          : _Contenu(detail: detail.value!),
    );
  }
}

class _Contenu extends ConsumerWidget {
  const _Contenu({required this.detail});

  final RayonDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final r = detail.rayon;
    final titres = detail.titres;
    final minutes = titres.fold<int>(0, (s, t) => s + t.song.duration) ~/ 60;
    final actions = ref.read(playerActionsProvider);

    return ListView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + 24,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              RayonMosaic(rayon: r, size: 128),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.titre,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (r.sousTitre != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        r.sousTitre!,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      '${titres.length} titres · $minutes min',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: titres.isEmpty
                      ? null
                      : () => actions.playRecos(titres),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Tout lire'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: titres.isEmpty
                      ? null
                      : () => actions.playRecos([...titres]..shuffle()),
                  icon: const Icon(Icons.shuffle),
                  label: const Text('Aléatoire'),
                ),
              ),
            ],
          ),
        ),
        for (final (i, t) in titres.indexed)
          SongTile(
            song: t.song,
            subtitle: t.raison == null
                ? null
                : '${t.song.artistName ?? ''} · ${t.raison}',
            onTap: () => actions.playRecos(titres, startIndex: i),
            onLongPress: () => showSongMenu(context, t.song),
          ),
      ],
    );
  }
}
