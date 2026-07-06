import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/library_repository.dart';
import '../state/library.dart';

/// Scan de la bibliothèque : re-scanne le dossier musique du serveur pour
/// détecter les nouveaux artistes / albums / titres, et détecte
/// automatiquement les genres manquants. Accessible depuis
/// Paramètres → Bibliothèque.
class LibraryScanScreen extends ConsumerStatefulWidget {
  const LibraryScanScreen({super.key});

  @override
  ConsumerState<LibraryScanScreen> createState() => _LibraryScanScreenState();
}

class _LibraryScanScreenState extends ConsumerState<LibraryScanScreen> {
  Timer? _timer;
  ScanStatus? _scan;
  GenreScanStatus? _genre;
  bool _loading = true;

  // Pour rafraîchir la bibliothèque / snackbar une seule fois à la fin.
  bool _wasScanning = false;
  bool _wasGenreScanning = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refresh(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final repo = ref.read(libraryRepositoryProvider);
    try {
      final results = await Future.wait([
        repo.scanStatus(),
        repo.genreScanStatus(),
      ]);
      if (!mounted) return;
      final scan = results[0] as ScanStatus;
      final genre = results[1] as GenreScanStatus;

      // Fin de scan bibliothèque → rafraîchir les listes.
      if (_wasScanning && !scan.scanning) {
        ref.invalidate(artistsProvider);
        ref.invalidate(albumsProvider);
        ref.invalidate(recentAlbumsProvider);
        ref.invalidate(genresProvider);
        _snack('Bibliothèque à jour');
      }
      // Fin de détection de genres → rafraîchir genres + artistes.
      if (_wasGenreScanning && !genre.scanning) {
        ref.invalidate(genresProvider);
        ref.invalidate(artistsProvider);
        _snack('Détection des genres terminée');
      }

      setState(() {
        _scan = scan;
        _genre = genre;
        _loading = false;
        _wasScanning = scan.scanning;
        _wasGenreScanning = genre.scanning;
      });
    } catch (_) {
      // Réseau instable : on réessaiera au prochain tick.
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() action, String started) async {
    try {
      await action();
      _snack(started);
      await _refresh();
    } catch (e) {
      _snack('Échec : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(libraryRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Scanner la bibliothèque')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _LibraryScanCard(
                  status: _scan,
                  onFullScan: () => _run(repo.forceScan, 'Scan complet lancé'),
                  onFastScan: () => _run(repo.fastScan, 'Scan rapide lancé'),
                ),
                const SizedBox(height: 16),
                _GenreScanCard(
                  status: _genre,
                  onScan: () => _run(repo.genreScan, 'Détection des genres lancée'),
                ),
              ],
            ),
    );
  }
}

/// Carte « Scan de la bibliothèque ».
class _LibraryScanCard extends StatelessWidget {
  const _LibraryScanCard({
    required this.status,
    required this.onFullScan,
    required this.onFastScan,
  });

  final ScanStatus? status;
  final VoidCallback onFullScan;
  final VoidCallback onFastScan;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scanning = status?.scanning ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.library_music_outlined, color: scheme.primary),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Scan de la bibliothèque',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Détecte les nouveaux artistes, albums et titres ajoutés sur '
              'le serveur, et régénère les pochettes.',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (scanning)
              const Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  SizedBox(width: 12),
                  Text('Scan en cours…'),
                ],
              )
            else ...[
              Text(
                'Dernier scan : ${_formatLast(status?.lastUpdateAt)}',
                style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: onFullScan,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Scan complet'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: onFastScan,
                    child: const Text('Rapide'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Carte « Détection automatique des genres ».
class _GenreScanCard extends StatelessWidget {
  const _GenreScanCard({required this.status, required this.onScan});

  final GenreScanStatus? status;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scanning = status?.scanning ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.label_outline, color: scheme.primary),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Détection des genres',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Attribue automatiquement un genre aux artistes qui n\'en ont '
              'pas encore (via MusicBrainz).',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (scanning) ...[
              LinearProgressIndicator(
                value: (status?.total ?? 0) > 0
                    ? (status!.percent / 100).clamp(0.0, 1.0)
                    : null,
              ),
              const SizedBox(height: 8),
              Text(
                status!.currentArtist.isEmpty
                    ? 'Analyse en cours… ${status!.processed}/${status!.total}'
                    : '${status!.processed}/${status!.total} — '
                        '${status!.currentArtist}',
                style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
            ] else
              FilledButton.icon(
                onPressed: onScan,
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Détecter les genres'),
              ),
          ],
        ),
      ),
    );
  }
}

String _formatLast(DateTime? at) {
  if (at == null) return 'jamais';
  final now = DateTime.now();
  final diff = now.difference(at);
  if (diff.inMinutes < 1) return 'à l\'instant';
  if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
  final d = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}
