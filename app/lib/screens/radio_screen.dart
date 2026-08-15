import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/radio_repository.dart';
import '../state/player.dart';
import '../state/radio.dart';
import '../widgets/artwork.dart';
import '../widgets/glass_box.dart';
import '../widgets/glass_kit.dart';
import '../widgets/mascot_empty.dart';

/// Onglet « Radio » : liste des web radios (lecture au tap, favoris),
/// ajout / édition / suppression des stations, et mode de sélection multiple
/// pour en supprimer plusieurs d'un coup.
///
/// Il n'y a plus de catalogue public : la liste est entièrement celle de
/// l'utilisateur (idée #97). Radio Browser n'est plus qu'une source d'import,
/// transférée chez lui une fois, puis reprise à la demande depuis le menu.
class RadioScreen extends ConsumerStatefulWidget {
  const RadioScreen({super.key});

  @override
  ConsumerState<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends ConsumerState<RadioScreen> {
  bool _selecting = false;
  final Set<String> _selected = {};
  String _search = '';
  String? _genre; // null = tous les genres

  void _exitSelection() => setState(() {
        _selecting = false;
        _selected.clear();
      });

  void _toggle(String id) => setState(() {
        _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
      });

  /// Tout cocher — ou tout décocher si la liste affichée l'est déjà. Porte sur
  /// ce qui est visible : filtrer par genre puis « tout sélectionner » est la
  /// façon rapide d'épurer.
  void _toggleAll(List<RadioStation> visible) => setState(() {
        final ids = visible.map((s) => s.id);
        if (ids.every(_selected.contains)) {
          _selected.removeAll(ids);
        } else {
          _selected.addAll(ids);
        }
      });

  Future<void> _deleteSelected() async {
    final ids = _selected.toList();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await _confirm(
      'Supprimer ${ids.length} station${ids.length > 1 ? 's' : ''} ?',
      'C\'est ta liste : elles la quittent pour de bon.',
    );
    if (ok != true) return;
    try {
      await ref.read(radioRepositoryProvider).removeBulk(ids);
      ref.invalidate(radioStationsProvider);
      _exitSelection();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Échec : $e')));
    }
  }

  Future<void> _deleteOne(RadioStation s) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await _confirm('Supprimer « ${s.name} » ?', null);
    if (ok != true) return;
    try {
      await ref.read(radioRepositoryProvider).remove(s.id);
      ref.invalidate(radioStationsProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Échec : $e')));
    }
  }

  Future<bool?> _confirm(String title, String? message) => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: message != null ? Text(message) : null,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Supprimer'),
            ),
          ],
        ),
      );

  /// Reprend le catalogue Radio Browser dans sa liste. Ce qu'il a déjà n'est
  /// pas dupliqué, et ce qu'il importe lui appartient comme le reste.
  Future<void> _importCatalog() async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Importer le catalogue ?'),
        content: const Text(
          'Les stations canadiennes de Radio Browser rejoignent ta liste. '
          'Celles que tu as déjà ne seront pas dupliquées.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Importer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('Import du catalogue en cours…')),
    );
    try {
      final n = await ref.read(radioRepositoryProvider).importCatalog();
      ref.invalidate(radioStationsProvider);
      messenger.showSnackBar(SnackBar(
        content: Text(n == 0
            ? 'Rien de nouveau à importer'
            : '$n station${n > 1 ? 's' : ''} ajoutée${n > 1 ? 's' : ''} à ta '
                'liste'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Échec : $e')));
    }
  }

  /// Menu « … » : réglages de la liste plutôt que d'une station.
  void _listMenu() {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.public),
              title: const Text('Importer le catalogue Radio Browser'),
              subtitle: const Text(
                'Reprend les stations canadiennes dans ta liste, sans '
                'doublon.',
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _importCatalog();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _rowMenu(RadioStation s) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Modifier'),
              onTap: () {
                Navigator.pop(context);
                context.push('/radio/edit', extra: s);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Supprimer'),
              onTap: () {
                Navigator.pop(context);
                _deleteOne(s);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Recherche + filtre de genre appliqués, favoris en tête puis par nom.
  List<RadioStation> _visible(List<RadioStation> list) {
    final q = _search.trim().toLowerCase();
    final out = list.where((s) {
      final matchName = q.isEmpty || s.name.toLowerCase().contains(q);
      final matchGenre = _genre == null ||
          s.genres.any((g) => g.toLowerCase() == _genre!.toLowerCase());
      return matchName && matchGenre;
    }).toList();
    out.sort((a, b) {
      if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final stations = ref.watch(radioStationsProvider);
    final currentId = ref.watch(currentMediaItemProvider).value?.id;

    // Genres distincts présents dans les stations (pour le filtre).
    final allGenres = <String>{
      for (final s in stations.value ?? const <RadioStation>[])
        ...s.genres.where((g) => g.trim().isNotEmpty),
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    // Ce que la recherche et le filtre laissent voir : c'est là-dessus que
    // « tout sélectionner » travaille.
    final visible = _visible(stations.value ?? const []);
    final allPicked =
        visible.isNotEmpty && visible.every((s) => _selected.contains(s.id));

    return Scaffold(
      floatingActionButton: _selecting && _selected.isNotEmpty
          ? FloatingActionButton.extended(
              heroTag: 'radio-delete',
              onPressed: _deleteSelected,
              icon: const Icon(Icons.delete),
              label: Text('Supprimer (${_selected.length})'),
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(radioStationsProvider.future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 90,
            ),
            children: [
              // En-tête : titre + actions (ajout / sélection).
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 14, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selecting
                            ? '${_selected.length} sélectionnée'
                                '${_selected.length > 1 ? 's' : ''}'
                            : 'Radio',
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                          height: 1.02,
                        ),
                      ),
                    ),
                    if (_selecting) ...[
                      GlassIconButton(
                        icon: allPicked
                            ? Icons.deselect_rounded
                            : Icons.select_all_rounded,
                        tooltip: allPicked
                            ? 'Tout désélectionner'
                            : 'Tout sélectionner',
                        size: 42,
                        onPressed: visible.isEmpty
                            ? null
                            : () => _toggleAll(visible),
                      ),
                      const SizedBox(width: 8),
                      GlassIconButton(
                        icon: Icons.close,
                        tooltip: 'Terminer',
                        size: 42,
                        onPressed: _exitSelection,
                      ),
                    ] else ...[
                      GlassIconButton(
                        icon: Icons.checklist_rounded,
                        tooltip: 'Sélectionner',
                        size: 42,
                        onPressed: () => setState(() => _selecting = true),
                      ),
                      const SizedBox(width: 8),
                      GlassIconButton(
                        icon: Icons.add,
                        tooltip: 'Ajouter une radio',
                        size: 42,
                        onPressed: () => context.push('/radio/edit'),
                      ),
                      const SizedBox(width: 8),
                      GlassIconButton(
                        icon: Icons.more_horiz,
                        tooltip: 'Réglages de la liste',
                        size: 42,
                        onPressed: _listMenu,
                      ),
                    ],
                  ],
                ),
              ),
              // Recherche par nom.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                child: GlassBox(
                  radius: 16,
                  blur: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Icon(Icons.search,
                            size: 22,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            onChanged: (v) => setState(() => _search = v),
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w500),
                            decoration: const InputDecoration(
                              hintText: 'Rechercher une radio…',
                              isDense: true,
                              border: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding:
                                  EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        if (_search.isNotEmpty)
                          GestureDetector(
                            onTap: () => setState(() => _search = ''),
                            child: Icon(Icons.close,
                                size: 20,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              // Filtre par genre.
              if (allGenres.isNotEmpty)
                SizedBox(
                  height: 42,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: ChoiceChip(
                          label: const Text('Tous'),
                          selected: _genre == null,
                          onSelected: (_) => setState(() => _genre = null),
                        ),
                      ),
                      for (final g in allGenres)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: ChoiceChip(
                            label: Text(g),
                            selected: _genre == g,
                            onSelected: (_) => setState(() => _genre = g),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              ...stations.when(
                loading: () => const [
                  Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
                error: (e, _) => [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Center(child: Text('Erreur: $e')),
                  ),
                ],
                data: (list) {
                  if (list.isEmpty) {
                    return const [
                      Padding(
                        padding: EdgeInsets.all(20),
                        child: MascotEmpty(
                          message: 'Aucune station',
                          hint: 'Ajoute une web radio avec le bouton +.',
                        ),
                      ),
                    ];
                  }
                  if (visible.isEmpty) {
                    return const [
                      Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('Aucune station trouvée')),
                      ),
                    ];
                  }
                  return [
                    for (final s in visible)
                      _StationRow(
                        station: s,
                        currentId: currentId,
                        selecting: _selecting,
                        selected: _selected.contains(s.id),
                        onSelectToggle: () => _toggle(s.id),
                        onMenu: () => _rowMenu(s),
                      ),
                  ];
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rangée de station : logo 46 r12, nom (accent si en cours), favori.
/// En mode sélection : pastille de coche; sinon appui long = menu.
class _StationRow extends ConsumerWidget {
  const _StationRow({
    required this.station,
    required this.currentId,
    required this.selecting,
    required this.selected,
    required this.onSelectToggle,
    required this.onMenu,
  });

  final RadioStation station;
  final String? currentId;
  final bool selecting;
  final bool selected;
  final VoidCallback onSelectToggle;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isPlaying = currentId == station.streamUrl;
    final subtitle = [
      if (station.country != null && station.country!.isNotEmpty)
        station.country!,
      if (station.genres.isNotEmpty) station.genres.take(2).join(', '),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: selecting
            ? onSelectToggle
            : () => ref.read(playerActionsProvider).playRadio(
                  url: station.streamUrl,
                  title: station.name,
                  logo: station.logo,
                ),
        onLongPress: selecting ? null : onMenu,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              if (selecting)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: selected ? scheme.primary : scheme.outline,
                  ),
                ),
              Artwork(
                url: station.logo,
                size: 46,
                borderRadius: 12,
                icon: Icons.radio,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      station.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: isPlaying ? scheme.primary : null,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (!selecting)
                IconButton(
                  tooltip: 'Favori',
                  icon: Icon(
                    station.favorite ? Icons.favorite : Icons.favorite_border,
                    color: station.favorite ? scheme.primary : scheme.outline,
                  ),
                  onPressed: () async {
                    await ref
                        .read(radioRepositoryProvider)
                        .toggleFavorite(station.id);
                    ref.invalidate(radioStationsProvider);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
