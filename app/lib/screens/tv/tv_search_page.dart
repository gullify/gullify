import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/library.dart';
import '../../state/player.dart';
import 'tv_kit.dart';
import 'tv_text_entry.dart';

/// La recherche, avec le clavier de Google.
///
/// Le champ est un simple élément focalisable tant qu'on n'écrit pas : « OK »
/// ouvre le clavier du système (celui de la télé, avec sa dictée vocale), et
/// dès qu'il se referme la croix directionnelle repart vers les résultats.
/// C'est le même mécanisme que sur les écrans de connexion — voir
/// [TvImeField], qui explique pourquoi un champ de texte ne doit jamais
/// garder le focus sur un téléviseur.
///
/// Pas de bouton « chercher » : les résultats suivent la saisie.
class TvSearchPage extends ConsumerStatefulWidget {
  const TvSearchPage({super.key});

  @override
  ConsumerState<TvSearchPage> createState() => _TvSearchPageState();
}

class _TvSearchPageState extends ConsumerState<TvSearchPage> {
  final _field = TextEditingController();

  String get _query => _field.text;

  @override
  void initState() {
    super.initState();
    // Les résultats suivent la saisie : pas de bouton « chercher » à aller
    // viser après chaque mot.
    _field.addListener(() {
      if (mounted) setState(() {});
      ref.read(searchQueryProvider.notifier).set(_field.text);
    });
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final results = ref.watch(searchResultsProvider);

    return TvScaffold(
      title: 'Recherche',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 560, child: _keyboard(scheme)),
          const SizedBox(width: 70),
          Expanded(
            child: _query.trim().length < 2
                ? const TvEmpty(
                    message: 'Que cherches-tu ?',
                    hint:
                        'Deux lettres suffisent. Les résultats se mettent à '
                        'jour à chaque touche.',
                    icon: Icons.search_rounded,
                  )
                : results.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => TvEmpty(
                      message: 'Recherche impossible',
                      hint: '$e',
                      icon: Icons.cloud_off_rounded,
                    ),
                    data: (r) => r.isEmpty
                        ? TvEmpty(
                            message: 'Rien pour « $_query »',
                            hint: 'Essaie moins de lettres.',
                            icon: Icons.search_off_rounded,
                          )
                        : ListView(
                            padding: const EdgeInsets.only(bottom: 40),
                            children: [
                              if (r.artists.isNotEmpty)
                                TvShelf(
                                  label: 'Artistes',
                                  itemCount: r.artists.length,
                                  height: 300,
                                  itemBuilder: (context, i, onFocus) => TvCard(
                                    title: r.artists[i].name,
                                    subtitle:
                                        '${r.artists[i].albumCount} albums',
                                    size: 200,
                                    round: true,
                                    icon: Icons.person_rounded,
                                    artwork: TvArtwork(
                                      url: r.artists[i].imageUrl,
                                      borderRadius: 0,
                                    ),
                                    onFocusChange: (f) {
                                      if (f) onFocus();
                                    },
                                    onPressed: () => context.push(
                                      '/tv/artist/${r.artists[i].id}',
                                    ),
                                  ),
                                ),
                              if (r.albums.isNotEmpty) ...[
                                const SizedBox(height: 34),
                                TvShelf(
                                  label: 'Albums',
                                  itemCount: r.albums.length,
                                  height: 300,
                                  itemBuilder: (context, i, onFocus) => TvCard(
                                    title: r.albums[i].name,
                                    subtitle: r.albums[i].artistName,
                                    size: 200,
                                    artwork: TvArtwork(
                                      url: r.albums[i].artworkUrl,
                                      borderRadius: 0,
                                    ),
                                    onFocusChange: (f) {
                                      if (f) onFocus();
                                    },
                                    onPressed: () => context.push(
                                      '/tv/album/${r.albums[i].id}',
                                    ),
                                  ),
                                ),
                              ],
                              if (r.songs.isNotEmpty) ...[
                                const SizedBox(height: 34),
                                const TvShelfLabel('Titres'),
                                for (var i = 0; i < r.songs.length; i++)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: TvTrackTile(
                                      index: i + 1,
                                      title: r.songs[i].title,
                                      subtitle: r.songs[i].artistName,
                                      onPressed: () async {
                                        await ref
                                            .read(playerActionsProvider)
                                            .playSongs(r.songs, startIndex: i);
                                        if (context.mounted) {
                                          context.push('/tv/playing');
                                        }
                                      },
                                    ),
                                  ),
                              ],
                            ],
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _keyboard(ColorScheme scheme) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      TvImeField(
        label: 'RECHERCHER',
        controller: _field,
        autofocus: true,
        hint: 'Appuie sur OK',
      ),
      const SizedBox(height: 20),
      Text(
        'Le clavier de la télé s\'ouvre sur OK — la dictée vocale de la '
        'télécommande y marche aussi. Les résultats suivent la saisie.',
        style: TextStyle(
          fontSize: tvMinText,
          height: 1.4,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
        ),
      ),
      if (_query.isNotEmpty) ...[
        const SizedBox(height: 20),
        TvPill(
          label: 'Effacer',
          icon: Icons.backspace_outlined,
          accent: false,
          expand: true,
          onPressed: _field.clear,
        ),
      ],
    ],
  );
}
