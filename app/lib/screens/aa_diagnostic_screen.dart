import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/player.dart';

/// Journal des événements Android Auto (racine, catégories, liaison des
/// dépôts, erreurs). Permet de diagnostiquer « Aucune sélection » après un
/// trajet, sans ordinateur : on lit le journal ici.
class AaDiagnosticScreen extends ConsumerStatefulWidget {
  const AaDiagnosticScreen({super.key});

  @override
  ConsumerState<AaDiagnosticScreen> createState() => _AaDiagnosticScreenState();
}

class _AaDiagnosticScreenState extends ConsumerState<AaDiagnosticScreen> {
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
    final log = ref.read(audioHandlerProvider).aaLog;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostic Android Auto'),
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
              'Après un trajet où Android Auto affiche « Aucune sélection », '
              'reviens ici : les dernières lignes montrent ce qui s\'est '
              'passé. Copie-les et envoie-les à Claude.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
          ),
          const Divider(height: 16),
          Expanded(
            child: log.isEmpty
                ? Center(
                    child: Text(
                      'Aucun événement enregistré.\n'
                      'Connecte-toi à Android Auto puis reviens.',
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
                          line.contains('TOUJOURS absent') ||
                          line.contains('pas de repository');
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
                            color: isError ? scheme.error : scheme.onSurface,
                            fontWeight:
                                isError ? FontWeight.w700 : FontWeight.w400,
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
