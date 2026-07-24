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
    final log = ref.read(audioHandlerProvider).playbackLog;
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Quand la musique s\'arrête toute seule écran éteint, reviens '
              'ici : les dernières lignes montrent ce qui s\'est passé juste '
              'avant (pause, erreur de flux, interruption audio, mise en '
              'veille). Copie-les et envoie-les à Claude.',
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
