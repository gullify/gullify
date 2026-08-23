import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/tv_log.dart';

/// Le journal du téléviseur, relu après coup.
///
/// Volontairement dans les écrans tactiles : on vient le lire depuis un
/// téléphone, ou à la télécommande via Paramètres, et surtout **après** un
/// plantage — donc quand l'interface TV n'est plus à l'écran.
class TvLogScreen extends StatefulWidget {
  const TvLogScreen({super.key});

  @override
  State<TvLogScreen> createState() => _TvLogScreenState();
}

class _TvLogScreenState extends State<TvLogScreen> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lines = TvLog.lines;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Journal du téléviseur'),
        actions: [
          IconButton(
            tooltip: 'Copier',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: lines.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: lines.join('\n')));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Journal copié')),
                    );
                  },
          ),
          IconButton(
            tooltip: 'Effacer',
            icon: const Icon(Icons.delete_outline),
            onPressed: lines.isEmpty
                ? null
                : () async {
                    await TvLog.clear();
                    if (context.mounted) setState(() {});
                  },
          ),
        ],
      ),
      body: lines.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Rien pour l\'instant.\n\nCe journal se remplit sur '
                  'téléviseur : le fil des écrans et les erreurs, gardés sur '
                  'le disque pour survivre à un plantage.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: lines.length,
              itemBuilder: (context, i) {
                final error = lines[i].contains('ERREUR');
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: SelectableText(
                    lines[i],
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      height: 1.35,
                      color: error ? scheme.error : scheme.onSurface,
                      fontWeight: error ? FontWeight.w700 : null,
                    ),
                  ),
                );
              },
            ),
    );
  }
}
