import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/player.dart';
import '../../state/radio.dart';
import '../../widgets/artwork.dart';
import 'tv_kit.dart';

/// Les radios : une grille de logos, un appui pour lancer le flux.
///
/// Rien d'autre à faire ici — une radio n'a ni piste ni file d'attente, donc
/// pas de page de détail : on choisit, ça joue, on passe à l'écran de lecture.
class TvRadioPage extends ConsumerWidget {
  const TvRadioPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stations = ref.watch(radioStationsProvider);

    return TvScaffold(
      title: 'Radio',
      child: stations.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => TvEmpty(
          message: 'Radios injoignables',
          hint: '$e',
          icon: Icons.cloud_off_rounded,
        ),
        data: (list) => list.isEmpty
            ? const TvEmpty(
                message: 'Aucune radio enregistrée',
                hint:
                    'Ajoute tes stations depuis l\'app mobile : elles '
                    'apparaîtront ici aussitôt.',
                icon: Icons.radio_rounded,
              )
            : LayoutBuilder(
                builder: (context, box) {
                  const columns = 5;
                  const gap = 26.0;
                  final cell = (box.maxWidth - gap * (columns - 1)) / columns;
                  return GridView.builder(
                    padding: const EdgeInsets.only(top: 8, bottom: 40),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 34,
                      crossAxisSpacing: gap,
                      childAspectRatio: cell / (cell + 84),
                    ),
                    itemCount: list.length,
                    itemBuilder: (context, i) => TvCard(
                      title: list[i].name,
                      subtitle: list[i].genres.isEmpty
                          ? list[i].country
                          : list[i].genres.first,
                      size: cell,
                      autofocus: i == 0,
                      icon: Icons.radio_rounded,
                      artwork: Artwork(url: list[i].logo, borderRadius: 0),
                      onPressed: () async {
                        await ref
                            .read(playerActionsProvider)
                            .playRadio(
                              url: list[i].streamUrl,
                              title: list[i].name,
                              logo: list[i].logo,
                            );
                        if (context.mounted) context.push('/tv/playing');
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}
