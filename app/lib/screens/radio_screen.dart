import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/radio_repository.dart';
import '../state/player.dart';
import '../state/radio.dart';
import '../widgets/artwork.dart';
import '../widgets/glass_kit.dart';
import '../widgets/mascot_empty.dart';

/// Onglet « Radio » : liste des web radios (lecture au tap, favoris),
/// ajout / édition / suppression des stations personnalisées, et mode de
/// sélection multiple pour supprimer plusieurs stations d'un coup.
class RadioScreen extends ConsumerStatefulWidget {
  const RadioScreen({super.key});

  @override
  ConsumerState<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends ConsumerState<RadioScreen> {
  bool _selecting = false;
  final Set<String> _selected = {};

  void _exitSelection() => setState(() {
        _selecting = false;
        _selected.clear();
      });

  void _toggle(String id) => setState(() {
        _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
      });

  Future<void> _deleteSelected() async {
    final ids = _selected.toList();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await _confirm(
      'Supprimer ${ids.length} station${ids.length > 1 ? 's' : ''} ?',
      'Les stations personnalisées sont supprimées, celles du catalogue '
          'sont masquées.',
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
    final ok = await _confirm(
      'Supprimer « ${s.name} » ?',
      s.isCustom ? null : 'Station du catalogue : elle sera masquée.',
    );
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

  void _rowMenu(RadioStation s) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (s.isCustom)
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
              title: Text(s.isCustom ? 'Supprimer' : 'Masquer'),
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

  @override
  Widget build(BuildContext context) {
    final stations = ref.watch(radioStationsProvider);
    final currentId = ref.watch(currentMediaItemProvider).value?.id;

    return Scaffold(
      floatingActionButton: _selecting && _selected.isNotEmpty
          ? FloatingActionButton.extended(
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
                    if (_selecting)
                      GlassIconButton(
                        icon: Icons.close,
                        tooltip: 'Terminer',
                        size: 42,
                        onPressed: _exitSelection,
                      )
                    else ...[
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
                    ],
                  ],
                ),
              ),
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
                  final sorted = [...list]
                    ..sort((a, b) {
                      if (a.favorite != b.favorite) {
                        return a.favorite ? -1 : 1;
                      }
                      return a.name
                          .toLowerCase()
                          .compareTo(b.name.toLowerCase());
                    });
                  return [
                    for (final s in sorted)
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
