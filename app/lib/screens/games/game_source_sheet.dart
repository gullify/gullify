import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/game_source.dart';
import '../../state/library.dart';
import '../../state/playlists.dart';
import '../../widgets/glass_box.dart';
import '../../widgets/glass_kit.dart';
import 'game_kit.dart';

/// Choix du vivier des jeux : toute la bibliothèque, un ou plusieurs genres,
/// une ou plusieurs playlists, ou les favoris.
///
/// Rend le réglage retenu, ou `null` si la feuille a été refermée sans rien
/// valider — l'appelant ne change alors rien.
///
/// [subtitle] remplace la phrase d'explication : le même choix sert au réveil
/// matinal (idée #81), qui n'a rien à voir avec les jeux.
Future<GameSource?> showGameSourceSheet(
  BuildContext context,
  GameSource current, {
  String? subtitle,
}) => showModalBottomSheet<GameSource>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (context) => _GameSourceSheet(initial: current, subtitle: subtitle),
);

/// La tuile de réglage qui ouvre la feuille et montre le vivier retenu.
class GameSourceTile extends ConsumerWidget {
  const GameSourceTile({
    super.key,
    required this.source,
    required this.onChanged,
    this.label = 'Les jeux piochent dans',
    this.subtitle,
  });

  final GameSource source;
  final ValueChanged<GameSource> onChanged;

  /// Ce que la tuile annonce au-dessus du vivier retenu.
  final String label;

  /// Explication passée à la feuille de choix.
  final String? subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return GlassBox(
      radius: 18,
      blur: false,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () async {
          final picked = await showGameSourceSheet(
            context,
            source,
            subtitle: subtitle,
          );
          if (picked != null) onChanged(picked);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
          child: Row(
            children: [
              Icon(gameSourceIcon(source), color: scheme.primary, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      source.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.tune_rounded, color: scheme.onSurfaceVariant, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// L'icône qui représente un vivier (tuile de réglage, en-tête des jeux).
IconData gameSourceIcon(GameSource source) => switch (source.effectiveMode) {
  GameSourceMode.all => Icons.library_music_rounded,
  GameSourceMode.genres => Icons.category_rounded,
  GameSourceMode.playlists => Icons.queue_music_rounded,
  GameSourceMode.favorites => Icons.favorite_rounded,
};

class _GameSourceSheet extends ConsumerStatefulWidget {
  const _GameSourceSheet({required this.initial, this.subtitle});

  final GameSource initial;
  final String? subtitle;

  @override
  ConsumerState<_GameSourceSheet> createState() => _GameSourceSheetState();
}

class _GameSourceSheetState extends ConsumerState<_GameSourceSheet> {
  late GameSourceMode _mode = widget.initial.effectiveMode;
  late final Set<String> _genres = {...widget.initial.genres};
  late final Map<int, String> _playlists = {
    for (final p in widget.initial.playlists) p.id: p.name,
  };

  GameSource get _source => GameSource(
    mode: _mode,
    genres: _genres.toList(),
    playlists: [
      for (final e in _playlists.entries)
        GameSourcePlaylist(id: e.key, name: e.value),
    ],
  );

  /// Une sélection vide n'a pas de sens : on n'accepte pas de valider tant
  /// qu'aucun genre (ou aucune playlist) n'est coché.
  bool get _valid => switch (_mode) {
    GameSourceMode.genres => _genres.isNotEmpty,
    GameSourceMode.playlists => _playlists.isNotEmpty,
    _ => true,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        0,
        12,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: GlassBox(
          radius: 26,
          blur: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: scheme.onSurfaceVariant.withValues(
                            alpha: 0.35,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Où piocher ?',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.subtitle ??
                          'Le même vivier sert à tous les jeux, seul comme à '
                              'plusieurs.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  children: [
                    GamePickTile(
                      icon: Icons.library_music_rounded,
                      title: 'Toute la bibliothèque',
                      subtitle: 'Tout ce que le serveur connaît.',
                      selected: _mode == GameSourceMode.all,
                      onTap: () => setState(() => _mode = GameSourceMode.all),
                    ),
                    const SizedBox(height: 8),
                    GamePickTile(
                      icon: Icons.category_rounded,
                      title: 'Un ou plusieurs genres',
                      subtitle: _genres.isEmpty
                          ? 'Rock, jazz, électro… au choix.'
                          : _genres.join(', '),
                      selected: _mode == GameSourceMode.genres,
                      onTap: () =>
                          setState(() => _mode = GameSourceMode.genres),
                    ),
                    if (_mode == GameSourceMode.genres) _genrePicker(),
                    const SizedBox(height: 8),
                    GamePickTile(
                      icon: Icons.queue_music_rounded,
                      title: 'Une ou plusieurs playlists',
                      subtitle: _playlists.isEmpty
                          ? 'Ne jouer que ce que tu as rangé.'
                          : _playlists.values.join(', '),
                      selected: _mode == GameSourceMode.playlists,
                      onTap: () =>
                          setState(() => _mode = GameSourceMode.playlists),
                    ),
                    if (_mode == GameSourceMode.playlists) _playlistPicker(),
                    const SizedBox(height: 8),
                    GamePickTile(
                      icon: Icons.favorite_rounded,
                      title: 'Mes favoris',
                      subtitle: 'Les titres que tu as mis en cœur.',
                      selected: _mode == GameSourceMode.favorites,
                      onTap: () =>
                          setState(() => _mode = GameSourceMode.favorites),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                child: AccentPlayButton(
                  label: 'Valider',
                  icon: Icons.check_rounded,
                  expand: true,
                  onPressed: _valid
                      ? () => Navigator.of(context).pop(_source)
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Les genres de la bibliothèque, en pastilles cochables.
  Widget _genrePicker() => _picker(
    ref.watch(genresProvider),
    empty: 'Aucun genre renseigné dans ta bibliothèque.',
    builder: (genres) => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final genre in genres)
          FilterChip(
            label: Text(genre.name),
            selected: _genres.contains(genre.name),
            onSelected: (on) => setState(() {
              on ? _genres.add(genre.name) : _genres.remove(genre.name);
            }),
          ),
      ],
    ),
  );

  /// Les playlists, en cases à cocher (le nom est retenu avec l'identifiant :
  /// il sert à afficher le réglage sans recharger la liste).
  Widget _playlistPicker() => _picker(
    ref.watch(playlistsProvider),
    empty: 'Tu n\'as pas encore de playlist.',
    builder: (playlists) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final playlist in playlists)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _playlists.containsKey(playlist.id),
            title: Text(
              playlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14.5),
            ),
            subtitle: Text('${playlist.songCount} titres'),
            onChanged: (on) => setState(() {
              on == true
                  ? _playlists[playlist.id] = playlist.name
                  : _playlists.remove(playlist.id);
            }),
          ),
      ],
    ),
  );

  /// Coque commune aux deux sélecteurs : chargement, erreur, liste vide.
  Widget _picker<T>(
    AsyncValue<List<T>> value, {
    required String empty,
    required Widget Function(List<T>) builder,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 2),
      child: value.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(10),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        error: (_, _) => Text(
          'Liste indisponible pour le moment.',
          style: TextStyle(fontSize: 13, color: scheme.error),
        ),
        data: (items) => items.isEmpty
            ? Text(
                empty,
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                ),
              )
            : builder(items),
      ),
    );
  }
}
