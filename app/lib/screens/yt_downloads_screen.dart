import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/yt_downloads_repository.dart';
import '../state/yt_downloads.dart';
import '../widgets/artwork.dart';

/// Ajout de musique depuis YouTube Music : recherche d'albums +
/// suivi de la file de téléchargement du serveur (yt-dlp).
class YtDownloadsScreen extends ConsumerStatefulWidget {
  const YtDownloadsScreen({super.key});

  @override
  ConsumerState<YtDownloadsScreen> createState() => _YtDownloadsScreenState();
}

class _YtDownloadsScreenState extends ConsumerState<YtDownloadsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      ref.read(ytSearchQueryProvider.notifier).set(value);
    });
  }

  Future<void> _confirmDownload(YtAlbum album) async {
    final messenger = ScaffoldMessenger.of(context);
    // Résolution du browseId en playlist téléchargeable.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    YtResolvedAlbum resolved;
    try {
      resolved = await ref
          .read(ytDownloadsRepositoryProvider)
          .resolveAlbum(album.browseId);
    } catch (e) {
      if (mounted) Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text("Impossible de résoudre l'album : $e")),
      );
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(resolved.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(resolved.artist),
            const SizedBox(height: 4),
            Text(
              [
                if (resolved.year.isNotEmpty) resolved.year,
                '${resolved.trackCount} piste${resolved.trackCount > 1 ? 's' : ''}',
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            const Text(
              'Le serveur télécharge cet album puis l\'ajoute '
              'à la bibliothèque.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.download),
            label: const Text('Télécharger'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await ref.read(ytQueueProvider.notifier).start(resolved);
      messenger.showSnackBar(
        SnackBar(content: Text('Téléchargement démarré : ${resolved.title}')),
      );
      _tabs.animateTo(1);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Échec du démarrage : $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajouter de la musique'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.search), text: 'YouTube Music'),
            Tab(icon: Icon(Icons.downloading), text: 'Téléchargements'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _SearchTab(onChanged: _onChanged, onAlbumTap: _confirmDownload),
          const _QueueTab(),
        ],
      ),
    );
  }
}

class _SearchTab extends ConsumerWidget {
  const _SearchTab({required this.onChanged, required this.onAlbumTap});

  final ValueChanged<String> onChanged;
  final ValueChanged<YtAlbum> onAlbumTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(ytSearchQueryProvider);
    final results = ref.watch(ytSearchResultsProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            onChanged: onChanged,
            decoration: const InputDecoration(
              hintText: 'Artiste, album…',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: query.length < 2
              ? const Center(
                  child: Text('Recherchez un album sur YouTube Music'),
                )
              : results.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Erreur : $e')),
                  data: (albums) => albums.isEmpty
                      ? const Center(child: Text('Aucun album trouvé'))
                      : ListView.builder(
                          itemCount: albums.length,
                          itemBuilder: (context, i) {
                            final a = albums[i];
                            return ListTile(
                              leading: Artwork(url: a.thumbnail, size: 48),
                              title: Text(a.title),
                              subtitle: Text(
                                [
                                  a.artist,
                                  if (a.year.isNotEmpty) a.year,
                                ].join(' · '),
                              ),
                              trailing: const Icon(Icons.download_outlined),
                              onTap: () => onAlbumTap(a),
                            );
                          },
                        ),
                ),
        ),
      ],
    );
  }
}

class _QueueTab extends ConsumerWidget {
  const _QueueTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(ytQueueProvider);

    return RefreshIndicator(
      onRefresh: () => ref.read(ytQueueProvider.notifier).refresh(),
      child: queue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (items) => items.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('Aucun téléchargement')),
                ],
              )
            : ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, i) => _DownloadTile(items[i]),
              ),
      ),
    );
  }
}

class _DownloadTile extends ConsumerWidget {
  const _DownloadTile(this.d);

  final ServerDownload d;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final notifier = ref.read(ytQueueProvider.notifier);

    final (icon, color) = switch (d.status) {
      'completed' => (Icons.check_circle, scheme.primary),
      'error' => (Icons.error, scheme.error),
      'cancelled' => (Icons.cancel, scheme.outline),
      'queued' => (Icons.schedule, scheme.outline),
      _ => (Icons.downloading, scheme.primary),
    };

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text('${d.artist} — ${d.album}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(d.message, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (d.isActive) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: d.progress > 0 ? d.progress / 100 : null,
            ),
          ],
        ],
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (action) => switch (action) {
          'cancel' => notifier.cancel(d.id),
          'retry' => notifier.retry(d.id),
          _ => notifier.delete(d.id),
        },
        itemBuilder: (_) => [
          if (d.isActive)
            const PopupMenuItem(value: 'cancel', child: Text('Annuler')),
          if (d.isError || d.isCancelled)
            const PopupMenuItem(value: 'retry', child: Text('Réessayer')),
          if (!d.isActive)
            const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
        ],
      ),
    );
  }
}
