import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/player.dart';

/// Journal des événements de lecture (pauses, erreurs de flux, interruptions
/// audio, mise en tampon, passages en veille). Permet de comprendre pourquoi
/// la musique s'arrête parfois écran éteint, sans brancher d'ordinateur :
/// quand ça arrive, revenir ici et lire (ou copier) les dernières lignes.
class PlaybackDiagnosticScreen extends ConsumerStatefulWidget {
  const PlaybackDiagnosticScreen({super.key});

  @override
  ConsumerState<PlaybackDiagnosticScreen> createState() =>
      _PlaybackDiagnosticScreenState();
}

class _PlaybackDiagnosticScreenState
    extends ConsumerState<PlaybackDiagnosticScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Rafraîchit le journal tant que l'écran est ouvert.
    _timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final handler = ref.read(audioHandlerProvider);
    final log = handler.playbackLog;
    final snapshot = handler.diagnosticSnapshot();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostic de lecture'),
        actions: [
          IconButton(
            tooltip: 'Rafraîchir',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
          IconButton(
            tooltip: 'Copier',
            icon: const Icon(Icons.copy_all),
            onPressed: log.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: log.join('\n')));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Journal copié')),
                    );
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          // État courant du lecteur : le journal ci-dessous ne montre que les
          // *changements*, cet en-tête dit ce que fait la lecture à l'instant t.
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'État actuel',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                for (final (label, value) in snapshot)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1.5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 84,
                          child: Text(
                            label,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            value,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Quand la musique s\'arrête toute seule écran éteint, reviens '
              'ici : les dernières lignes montrent ce qui s\'est passé juste '
              'avant (pause, erreur de flux, interruption audio, mise en '
              'veille). Un « — démarrage de l\'app — » veut dire qu\'Android a '
              'tué puis relancé l\'app. Copie-les et envoie-les à Claude.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
          ),
          const Divider(height: 16),
          Expanded(
            child: log.isEmpty
                ? Center(
                    child: Text(
                      'Aucun événement enregistré.\n'
                      'Lance une lecture puis reviens.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: log.length,
                    itemBuilder: (context, i) {
                      final line = log[i];
                      final isError = line.contains('ERREUR') ||
                          line.contains('indisponible');
                      final isNotable = line.contains('interruption') ||
                          line.contains('débranchée') ||
                          line.contains('démarrage') ||
                          line.contains('détaché') ||
                          line.contains('⏸') ||
                          line.contains('tampon');
                      final Color color;
                      if (isError) {
                        color = scheme.error;
                      } else if (isNotable) {
                        color = scheme.primary;
                      } else {
                        color = scheme.onSurface;
                      }
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                          line,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.3,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ],
                            color: color,
                            fontWeight: isError
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
