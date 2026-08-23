import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/library.dart';
import '../../state/player.dart';
import 'tv_kit.dart';

/// La recherche au clavier à l'écran.
///
/// Une télécommande n'a pas de clavier : chaque lettre coûte plusieurs appuis.
/// D'où deux partis pris — une grille **alphabétique** (on cherche une lettre
/// des yeux, on ne tape pas au toucher) et **six colonnes** plutôt que dix
/// (traverser un QWERTY demanderait deux fois plus de trajet). Et pas de
/// bouton « chercher » : les résultats suivent chaque lettre.
class TvSearchPage extends ConsumerStatefulWidget {
  const TvSearchPage({super.key});

  @override
  ConsumerState<TvSearchPage> createState() => _TvSearchPageState();
}

class _TvSearchPageState extends ConsumerState<TvSearchPage> {
  static const _letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  String _query = '';

  void _type(String c) => _set(_query + c);
  void _backspace() =>
      _set(_query.isEmpty ? '' : _query.substring(0, _query.length - 1));

  void _set(String q) {
    setState(() => _query = q);
    ref.read(searchQueryProvider.notifier).set(q);
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
    children: [
      TvGlass(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 32, color: scheme.primary),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                _query.isEmpty ? 'Tape ton mot' : _query.toLowerCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w700,
                  color: _query.isEmpty
                      ? scheme.onSurfaceVariant.withValues(alpha: 0.6)
                      : scheme.onSurface,
                ),
              ),
            ),
            if (_query.isNotEmpty)
              Container(
                width: 3,
                height: 38,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 26),
      GridView.count(
        crossAxisCount: 6,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        children: [
          for (var i = 0; i < _letters.length; i++)
            _Key(
              label: _letters[i],
              autofocus: i == 0,
              onPressed: () => _type(_letters[i]),
            ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: _Key(
              label: 'espace',
              small: true,
              onPressed: () => _type(' '),
              height: 80,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _Key(
              label: 'effacer',
              small: true,
              icon: Icons.backspace_outlined,
              onPressed: _backspace,
              height: 80,
            ),
          ),
        ],
      ),
    ],
  );
}

class _Key extends StatelessWidget {
  const _Key({
    required this.label,
    required this.onPressed,
    this.small = false,
    this.icon,
    this.autofocus = false,
    this.height,
  });

  final String label;
  final VoidCallback onPressed;
  final bool small;
  final IconData? icon;
  final bool autofocus;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TvFocusable(
      onPressed: onPressed,
      autofocus: autofocus,
      scale: 1.08,
      builder: (context, focused) => Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: focused
              ? scheme.primary
              : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(18),
          border: focused
              ? tvFocusBorder(scheme.primary)
              : Border.all(color: Colors.white.withValues(alpha: 0.15)),
          boxShadow: focused ? tvFocusGlow(scheme.primary, spread: 4) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 24,
                color: focused ? Colors.white : scheme.onSurface,
              ),
              const SizedBox(width: 10),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: small ? 24 : 34,
                fontWeight: FontWeight.w700,
                color: focused ? Colors.white : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
