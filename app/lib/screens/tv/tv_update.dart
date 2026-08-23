import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_update.dart';
import 'tv_kit.dart';

/// Les mises à jour, sur le téléviseur.
///
/// À poser dans un `Positioned.fill` : ce widget se dimensionne tout seul et
/// ne doit pas être un enfant libre d'un `Stack`, qui se réduirait alors à sa
/// taille quand il n'y a rien à annoncer.
///
/// Sur téléphone on va chercher la mise à jour dans les réglages ; devant une
/// télé, personne n'ira. L'app vérifie donc d'elle-même — au démarrage et à
/// chaque retour au premier plan — et propose la mise à jour en grand, sur
/// place. Tout le mécanisme (manifeste, téléchargement, installeur système)
/// est celui de l'app mobile : seule la présentation change.
class TvUpdateOverlay extends ConsumerStatefulWidget {
  const TvUpdateOverlay({super.key});

  @override
  ConsumerState<TvUpdateOverlay> createState() => _TvUpdateOverlayState();
}

class _TvUpdateOverlayState extends ConsumerState<TvUpdateOverlay>
    with WidgetsBindingObserver {
  /// Mise à jour écartée pour cette session : on ne la repropose pas à
  /// chaque retour au premier plan.
  int? _snoozed;

  /// Première vérification, différée. Gardée pour être annulée : un minuteur
  /// qui survit à l'écran retomberait sur un état démonté.
  Timer? _firstCheck;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Un peu après l'ouverture : le premier affichage de l'accueil passe
    // avant une requête réseau qui ne presse pas.
    _firstCheck = Timer(const Duration(seconds: 3), _check);
  }

  @override
  void dispose() {
    _firstCheck?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Une box de salon reste allumée des jours : le retour au premier plan
    // est le seul moment fiable pour reprendre la vérification.
    if (state == AppLifecycleState.resumed) _check();
  }

  void _check() {
    if (!mounted) return;
    final status = ref.read(appUpdateProvider).status;
    // Ne jamais couper un téléchargement en cours pour aller revérifier.
    if (status == UpdateStatus.downloading ||
        status == UpdateStatus.readyToInstall) {
      return;
    }
    ref.read(appUpdateProvider.notifier).check(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final update = ref.watch(appUpdateProvider);
    final version = update.available?.versionCode;

    final show = switch (update.status) {
      UpdateStatus.available => version != _snoozed,
      UpdateStatus.downloading ||
      UpdateStatus.readyToInstall ||
      UpdateStatus.error => true,
      _ => false,
    };
    if (!show) return const SizedBox.shrink();

    return SizedBox.expand(
      child: ColoredBox(
        color: const Color(0xD9070810),
        child: Center(
          child: SizedBox(
            width: 900,
            child: TvGlass(
              padding: const EdgeInsets.fromLTRB(50, 44, 50, 40),
              child: _Panel(
                update: update,
                onLater: () => setState(() => _snoozed = version),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Panel extends ConsumerWidget {
  const _Panel({required this.update, required this.onLater});

  final AppUpdateState update;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final notifier = ref.read(appUpdateProvider.notifier);
    final info = update.available;

    Widget heading(String text) => Text(
      text,
      style: const TextStyle(
        fontSize: 46,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.3,
        height: 1.05,
      ),
    );

    switch (update.status) {
      case UpdateStatus.downloading:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            heading('Téléchargement…'),
            const SizedBox(height: 26),
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: LinearProgressIndicator(
                value: update.progress,
                minHeight: 12,
                backgroundColor: scheme.onSurface.withValues(alpha: 0.1),
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              update.progress == null
                  ? 'En cours…'
                  : '${(update.progress! * 100).round()} %',
              style: TextStyle(fontSize: 26, color: scheme.onSurfaceVariant),
            ),
          ],
        );

      case UpdateStatus.readyToInstall:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            heading('Installation'),
            const SizedBox(height: 18),
            Text(
              'Android va demander l\'autorisation d\'installer une app depuis '
              'Gullify. Accepte avec la touche OK — c\'est une seule fois.',
              style: TextStyle(
                fontSize: 26,
                height: 1.4,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 30),
            Wrap(
              spacing: 16,
              runSpacing: 14,
              children: [
                TvPill(
                  label: 'Relancer l\'installation',
                  icon: Icons.download_done_rounded,
                  autofocus: true,
                  onPressed: notifier.install,
                ),
                TvPill(
                  label: 'Plus tard',
                  accent: false,
                  onPressed: onLater,
                ),
              ],
            ),
          ],
        );

      case UpdateStatus.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            heading('Mise à jour impossible'),
            const SizedBox(height: 16),
            Text(
              update.message ?? 'Réessaie plus tard.',
              style: TextStyle(
                fontSize: 24,
                height: 1.4,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 30),
            Wrap(
              spacing: 16,
              runSpacing: 14,
              children: [
                TvPill(
                  label: 'Réessayer',
                  icon: Icons.refresh_rounded,
                  autofocus: true,
                  onPressed: () => notifier.check(),
                ),
                TvPill(
                  label: 'Fermer',
                  accent: false,
                  onPressed: () {
                    notifier.dismiss();
                    onLater();
                  },
                ),
              ],
            ),
          ],
        );

      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'NOUVELLE VERSION',
              style: TextStyle(
                fontSize: tvMinText,
                fontWeight: FontWeight.w700,
                letterSpacing: 3,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 14),
            heading('Gullify ${info?.versionName ?? ''}'),
            if (update.currentVersion.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Tu es en ${update.currentVersion}',
                  style: TextStyle(
                    fontSize: 24,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ),
            if (info?.changelog != null && info!.changelog!.isNotEmpty) ...[
              const SizedBox(height: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: SingleChildScrollView(
                  child: Text(
                    info.changelog!,
                    style: TextStyle(
                      fontSize: 26,
                      height: 1.45,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 34),
            Wrap(
              spacing: 16,
              runSpacing: 14,
              children: [
                TvPill(
                  label: 'Mettre à jour',
                  icon: Icons.system_update_alt_rounded,
                  autofocus: true,
                  onPressed: notifier.downloadAndInstall,
                ),
                TvPill(
                  label: 'Plus tard',
                  accent: false,
                  onPressed: () {
                    notifier.dismiss();
                    onLater();
                  },
                ),
              ],
            ),
          ],
        );
    }
  }
}
