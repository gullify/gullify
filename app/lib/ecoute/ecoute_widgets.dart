import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../widgets/artwork.dart';
import 'ecoute.dart';

/// Le bouton du lecteur (rangée du bas) : ouvre « Écouter sur… ». Il prend la
/// couleur de l'app quand la musique joue ailleurs. Pas sur le web : un
/// navigateur ne voit pas le Wi-Fi.
class EcouterSurButton extends ConsumerWidget {
  const EcouterSurButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb) return const SizedBox.shrink();
    final ailleurs = ref.watch(cibleProvider) != null;
    return IconButton(
      icon: Icon(
        ailleurs ? Icons.speaker_group : Icons.speaker_group_outlined,
        color: ailleurs ? Theme.of(context).colorScheme.primary : null,
      ),
      tooltip: 'Écouter sur…',
      onPressed: () => showEcouterSur(context),
    );
  }
}

Future<void> showEcouterSur(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => const _ListeAppareils(),
);

class _ListeAppareils extends ConsumerStatefulWidget {
  const _ListeAppareils();

  @override
  ConsumerState<_ListeAppareils> createState() => _ListeAppareilsState();
}

class _ListeAppareilsState extends ConsumerState<_ListeAppareils> {
  /// Les appareils cochés (clés). Au départ : ceux qui jouent déjà.
  late final Set<String> _coches = {
    for (final a in ref.read(cibleProvider)?.appareils ?? const <Appareil>[]) a.cle,
  };

  /// Dans l'ordre où on les a cochés : le premier mène le groupe.
  late final List<String> _ordre = _coches.toList();
  bool _envoi = false;

  void _basculer(Appareil a) => setState(() {
    if (_coches.remove(a.cle)) {
      _ordre.remove(a.cle);
    } else {
      _coches.add(a.cle);
      _ordre.add(a.cle);
    }
  });

  Future<void> _revenir() async {
    final nav = Navigator.of(context);
    await ref.read(cibleProvider.notifier).revenir();
    nav.pop();
  }

  Future<void> _jouer(List<Appareil> appareils) async {
    final cible = ref.read(cibleProvider.notifier);
    final messager = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final choisis = [
      for (final cle in _ordre)
        ?appareils.where((a) => a.cle == cle).firstOrNull ??
            ref.read(cibleProvider)?.appareils.where((a) => a.cle == cle).firstOrNull,
    ];
    if (choisis.isEmpty) return;
    setState(() => _envoi = true);
    try {
      await cible.envoyer(choisis);
      nav.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _envoi = false);
      messager.showSnackBar(
        SnackBar(
          content: Text(
            e is StateError ? e.message : 'La musique n\'a pas pu partir.',
          ),
        ),
      );
      if (ref.read(cibleProvider) != null) nav.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final appareils = ref.watch(appareilsProvider);
    final cible = ref.watch(cibleProvider);
    final teles = [for (final a in appareils) if (a.genre == 'tv') a];
    final gullios = [for (final a in appareils) if (a.genre != 'tv') a]
      ..sort((x, y) => (y.dispo ? 1 : 0) - (x.dispo ? 1 : 0));
    final groupeActuel = {for (final a in cible?.appareils ?? const <Appareil>[]) a.cle};
    final inchange = cible != null &&
        _coches.length == groupeActuel.length &&
        _coches.containsAll(groupeActuel);

    Widget ligne({
      required IconData icone,
      required String nom,
      required String detail,
      required bool choisi,
      bool actif = true,
      VoidCallback? onTap,
    }) => Opacity(
      opacity: actif ? 1 : 0.45,
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: choisi ? scheme.primary : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icone, color: choisi ? scheme.onPrimary : scheme.onSurface),
        ),
        title: Text(
          nom,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: choisi ? scheme.primary : null,
          ),
        ),
        subtitle: Text(detail),
        trailing: Checkbox(
          value: choisi,
          onChanged: actif && !_envoi && onTap != null ? (_) => onTap() : null,
        ),
        onTap: actif && !_envoi ? onTap : null,
      ),
    );

    Widget groupe(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 2),
      child: Text(
        t.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );

    IconData icone(Appareil a) => switch (a.genre) {
      'tv' => Icons.tv,
      'serveur' => Icons.dns_outlined,
      _ => Icons.desktop_windows_outlined,
    };

    Widget appareil(Appareil a) => ligne(
      icone: icone(a),
      nom: a.nom,
      detail: a.description,
      choisi: _coches.contains(a.cle),
      actif: a.dispo || groupeActuel.contains(a.cle),
      onTap: () => _basculer(a),
    );

    final n = _coches.length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
                child: Text(
                  'Écouter sur…',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Coche un ou plusieurs appareils de ce Wi-Fi.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
              ligne(
                icone: Icons.smartphone,
                nom: 'Ce téléphone',
                detail: cible == null ? 'Le son sort d\'ici' : 'Ramener la musique ici',
                choisi: cible == null && n == 0,
                onTap: cible == null
                    ? () => setState(() {
                        _coches.clear();
                        _ordre.clear();
                      })
                    : _revenir,
              ),
              if (teles.isNotEmpty) groupe('Télé'),
              for (final a in teles) appareil(a),
              if (gullios.isNotEmpty) groupe('GulliOS'),
              for (final a in gullios) appareil(a),
              if (appareils.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Recherche sur le Wi-Fi… (une télé doit avoir GulliFY ouvert)',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: n == 0 || _envoi || inchange
                        ? null
                        : () => _jouer(appareils),
                    child: _envoi
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            n == 0
                                ? 'Coche au moins un appareil'
                                : inchange
                                ? 'Joue déjà sur ${n == 1 ? 'cet appareil' : 'ces $n appareils'}'
                                : 'Jouer sur $n appareil${n > 1 ? 's' : ''}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Le lecteur quand la musique joue ailleurs : le téléphone est la
/// télécommande (pause, suivant, position, volume de l'appareil).
class TelecommandeScreen extends ConsumerWidget {
  const TelecommandeScreen({super.key});

  static String _mmss(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cible = ref.watch(cibleProvider);
    if (cible == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final e = cible.etat;
    final t = e.titre;
    final cmd = ref.read(cibleProvider.notifier);
    final duree = e.duree.inMilliseconds;
    final avance = duree > 0
        ? (e.position.inMilliseconds / duree).clamp(0.0, 1.0)
        : 0.0;
    final a = cible.appareil;
    final plusieurs = cible.membres.length > 1;
    final noms = [for (final m in cible.membres) m.appareil.nom].join(' · ');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down, size: 32),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 300),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Artwork(
                        url: t?['pochette'] as String?,
                        borderRadius: 28,
                        icon: Icons.music_note,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Material(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => showEcouterSur(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Icon(
                          plusieurs
                              ? Icons.speaker_group
                              : a.genre == 'tv'
                              ? Icons.tv
                              : Icons.desktop_windows_outlined,
                          color: scheme.onPrimary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                plusieurs
                                    ? 'Joue sur ${cible.membres.length} appareils'
                                    : 'Joue sur ${a.nom}',
                                style: TextStyle(
                                  color: scheme.onPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                plusieurs
                                    ? noms
                                    : a.genre == 'tv'
                                    ? 'Le son sort de la télé'
                                    : 'Le son sort de ses enceintes',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: scheme.onPrimary.withValues(alpha: 0.85),
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: scheme.onPrimary),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (t?['titre'] as String?) ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    Text(
                      (t?['artiste'] as String?) ?? '',
                      style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Slider(
                value: avance,
                onChanged: duree > 0 ? (_) {} : null,
                onChangeEnd: duree > 0
                    ? (v) => cmd.commande('chercher', v * duree / 1000)
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_mmss(e.position), style: const TextStyle(fontSize: 12)),
                    Text(_mmss(e.duree), style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    iconSize: 36,
                    icon: const Icon(Icons.skip_previous),
                    tooltip: 'Titre précédent',
                    onPressed: () => cmd.commande('precedent'),
                  ),
                  IconButton(
                    iconSize: 72,
                    color: scheme.primary,
                    icon: Icon(
                      e.pause ? Icons.play_circle_fill : Icons.pause_circle_filled,
                    ),
                    tooltip: e.pause ? 'Lecture' : 'Pause',
                    onPressed: () => cmd.commande(e.pause ? 'reprendre' : 'pause'),
                  ),
                  IconButton(
                    iconSize: 36,
                    icon: const Icon(Icons.skip_next),
                    tooltip: 'Titre suivant',
                    onPressed: () => cmd.commande('suivant'),
                  ),
                ],
              ),
              if (!plusieurs && e.volume != null)
                _Volume(
                  valeur: e.volume!,
                  onChange: (v) => cmd.commande('volume', v),
                ),
              if (plusieurs) _VolumesGroupe(cible: cible),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// Plusieurs appareils : « Tous », puis une ligne par appareil (✕ le retire
/// du groupe ; la télé garde le volume de sa télécommande).
class _VolumesGroupe extends ConsumerWidget {
  const _VolumesGroupe({required this.cible});

  final Cible cible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final cmd = ref.read(cibleProvider.notifier);
    final reglables = [for (final m in cible.membres) if (m.etat.volume != null) m.etat.volume!];
    Widget nom(String t, {Color? couleur}) => SizedBox(
      width: 112,
      child: Text(
        t,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: couleur),
      ),
    );
    return Column(
      children: [
        if (reglables.isNotEmpty)
          Row(
            children: [
              nom('Tous', couleur: scheme.primary),
              Expanded(
                child: _Glissiere(
                  valeur: reglables.reduce((x, y) => x + y) / reglables.length,
                  onChange: (v) => cmd.commande('volume', v),
                ),
              ),
              const SizedBox(width: 40),
            ],
          ),
        for (final m in cible.membres)
          Row(
            children: [
              nom(m.appareil.nom),
              Expanded(
                child: m.etat.volume == null
                    ? Text(
                        'volume à sa télécommande',
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      )
                    : _Glissiere(
                        valeur: m.etat.volume!,
                        onChange: (v) => cmd.volume(m.appareil, v),
                      ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Retirer ${m.appareil.nom} du groupe',
                onPressed: () => cmd.retirer(m.appareil),
              ),
            ],
          ),
      ],
    );
  }
}

/// Une glissière de volume (0 à 100), envoyée au lâcher.
class _Glissiere extends StatefulWidget {
  const _Glissiere({required this.valeur, required this.onChange});

  final double valeur;
  final ValueChanged<double> onChange;

  @override
  State<_Glissiere> createState() => _GlissiereState();
}

class _GlissiereState extends State<_Glissiere> {
  double? _glisse;

  @override
  Widget build(BuildContext context) => Slider(
    value: (_glisse ?? widget.valeur).clamp(0, 100),
    max: 100,
    onChanged: (v) => setState(() => _glisse = v),
    onChangeEnd: (v) {
      setState(() => _glisse = null);
      widget.onChange(v.roundToDouble());
    },
  );
}

/// Le volume de l'appareil : on le règle en glissant, envoyé au lâcher.
class _Volume extends StatefulWidget {
  const _Volume({required this.valeur, required this.onChange});

  final double valeur;
  final ValueChanged<double> onChange;

  @override
  State<_Volume> createState() => _VolumeState();
}

class _VolumeState extends State<_Volume> {
  double? _glisse;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.volume_down),
      Expanded(
        child: Slider(
          value: (_glisse ?? widget.valeur).clamp(0, 100),
          max: 100,
          onChanged: (v) => setState(() => _glisse = v),
          onChangeEnd: (v) {
            setState(() => _glisse = null);
            widget.onChange(v.roundToDouble());
          },
        ),
      ),
      const Icon(Icons.volume_up),
    ],
  );
}
