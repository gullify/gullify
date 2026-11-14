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
  String? _envoi;

  Future<void> _choisir(Appareil? a) async {
    final cible = ref.read(cibleProvider.notifier);
    final messager = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    if (a == null) {
      await cible.revenir();
      nav.pop();
      return;
    }
    setState(() => _envoi = a.cle);
    try {
      await cible.envoyer(a);
      nav.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _envoi = null);
      messager.showSnackBar(
        SnackBar(
          content: Text(
            e is StateError ? e.message : '${a.nom} n\'a pas pu jouer la musique.',
          ),
        ),
      );
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

    Widget ligne({
      required IconData icone,
      required String nom,
      required String detail,
      required bool choisi,
      bool actif = true,
      String? cle,
      VoidCallback? onTap,
    }) {
      final enCours = cle != null && _envoi == cle;
      return Opacity(
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
          trailing: enCours
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : choisi
              ? Icon(Icons.check, color: scheme.primary)
              : null,
          onTap: actif && _envoi == null ? onTap : null,
        ),
      );
    }

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

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
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
                'Les GulliFY et GulliOS sur ce Wi-Fi.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
            ligne(
              icone: Icons.smartphone,
              nom: 'Ce téléphone',
              detail: cible == null ? 'Le son sort d\'ici' : 'Revenir ici',
              choisi: cible == null,
              onTap: cible == null ? null : () => _choisir(null),
            ),
            if (teles.isNotEmpty) groupe('Télé'),
            for (final a in teles)
              ligne(
                icone: icone(a),
                nom: a.nom,
                detail: a.description,
                choisi: cible?.appareil.cle == a.cle,
                actif: a.dispo,
                cle: a.cle,
                onTap: () => _choisir(a),
              ),
            if (gullios.isNotEmpty) groupe('GulliOS'),
            for (final a in gullios)
              ligne(
                icone: icone(a),
                nom: a.nom,
                detail: a.description,
                choisi: cible?.appareil.cle == a.cle,
                actif: a.dispo,
                cle: a.cle,
                onTap: () => _choisir(a),
              ),
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
          ],
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
                          a.genre == 'tv' ? Icons.tv : Icons.desktop_windows_outlined,
                          color: scheme.onPrimary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Joue sur ${a.nom}',
                                style: TextStyle(
                                  color: scheme.onPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                a.genre == 'tv'
                                    ? 'Le son sort de la télé'
                                    : 'Le son sort de ses enceintes',
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
              if (e.volume != null)
                _Volume(
                  valeur: e.volume!,
                  onChange: (v) => cmd.commande('volume', v),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
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
