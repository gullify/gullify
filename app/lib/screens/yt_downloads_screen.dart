import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/yt_downloads_repository.dart';
import '../state/yt_downloads.dart';
import '../widgets/artwork.dart';
import '../widgets/download_confirm.dart';

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

  Future<void> _downloadLink(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    // Un même lien déjà en file ne se relance pas.
    final duplicate = await ref
        .read(ytDownloadsRepositoryProvider)
        .checkDuplicate(url: url);
    if (!mounted) return;

    final ok = await showDownloadConfirm(
      context,
      title: 'Télécharger ce lien',
      subtitle: url,
      body: 'Le serveur télécharge ce lien (piste, album ou playlist) '
          'puis l\'ajoute à la bibliothèque. Le nom de l\'artiste et de '
          'l\'album est détecté automatiquement.',
      duplicate: duplicate,
    );
    if (!ok || !mounted) return;

    try {
      await ref
          .read(ytQueueProvider.notifier)
          .startUrl(url, force: duplicate != null);
      messenger.showSnackBar(
        const SnackBar(content: Text('Téléchargement démarré')),
      );
      _tabs.animateTo(1);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Échec du démarrage : $e')),
      );
    }
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
    // Déjà dans la bibliothèque ou déjà en file ? On le dit avant de proposer.
    final duplicate = await ref
        .read(ytDownloadsRepositoryProvider)
        .checkDuplicate(
          artist: resolved.artist,
          album: resolved.title,
          url: resolved.playlistUrl,
        );
    if (!mounted) return;
    Navigator.pop(context);

    final ok = await showDownloadConfirm(
      context,
      title: resolved.title,
      subtitle: resolved.artist,
      details: [
        if (resolved.year.isNotEmpty) resolved.year,
        '${resolved.trackCount} piste${resolved.trackCount > 1 ? 's' : ''}',
      ].join(' · '),
      body: 'Le serveur télécharge cet album puis l\'ajoute '
          'à la bibliothèque.',
      duplicate: duplicate,
    );
    if (!ok || !mounted) return;

    try {
      await ref
          .read(ytQueueProvider.notifier)
          .start(resolved, force: duplicate != null);
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
          _SearchTab(
            onChanged: _onChanged,
            onAlbumTap: _confirmDownload,
            onLinkTap: _downloadLink,
          ),
          const _QueueTab(),
        ],
      ),
    );
  }
}

/// Vrai si [s] ressemble à un lien YouTube / YouTube Music collé.
bool _looksLikeYtUrl(String s) {
  final t = s.trim();
  return t.startsWith('http') &&
      (t.contains('youtube.com') || t.contains('youtu.be'));
}

class _SearchTab extends ConsumerWidget {
  const _SearchTab({
    required this.onChanged,
    required this.onAlbumTap,
    required this.onLinkTap,
  });

  final ValueChanged<String> onChanged;
  final ValueChanged<YtAlbum> onAlbumTap;
  final ValueChanged<String> onLinkTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(ytSearchQueryProvider);
    final isLink = _looksLikeYtUrl(query);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            onChanged: onChanged,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: 'Artiste, album ou lien YouTube…',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: isLink
              ? _LinkResult(url: query, onLinkTap: onLinkTap)
              : query.length < 2
                  ? const Center(
                      child: Text(
                        'Recherchez un album sur YouTube Music,\n'
                        'ou collez un lien YouTube',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : _AlbumResults(onAlbumTap: onAlbumTap),
        ),
      ],
    );
  }
}

/// Carte proposant de télécharger directement un lien collé.
class _LinkResult extends StatelessWidget {
  const _LinkResult({required this.url, required this.onLinkTap});

  final String url;
  final ValueChanged<String> onLinkTap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.link),
            title: const Text('Télécharger depuis ce lien'),
            subtitle: Text(url, maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.download_outlined),
            onTap: () => onLinkTap(url),
          ),
        ),
      ],
    );
  }
}

/// Liste des albums trouvés, avec un bouton « Charger plus ».
class _AlbumResults extends ConsumerWidget {
  const _AlbumResults({required this.onAlbumTap});

  final ValueChanged<YtAlbum> onAlbumTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(ytSearchResultsProvider);
    final limit = ref.watch(ytSearchLimitProvider);
    final albums = results.value;

    // Premier chargement (aucun résultat encore connu).
    if (albums == null) {
      return results.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (_) => const SizedBox.shrink(),
      );
    }
    if (albums.isEmpty) {
      return const Center(child: Text('Aucun album trouvé'));
    }

    final loadingMore = results.isLoading;
    // On propose « Charger plus » tant que le serveur a renvoyé une page pleine
    // (donc potentiellement d'autres résultats) et qu'on n'a pas atteint le max.
    final canLoadMore = albums.length >= limit && limit < 50;

    return ListView.builder(
      itemCount: albums.length + 1,
      itemBuilder: (context, i) {
        if (i == albums.length) {
          if (loadingMore) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (!canLoadMore) return const SizedBox(height: 8);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: OutlinedButton.icon(
              onPressed: () =>
                  ref.read(ytSearchLimitProvider.notifier).more(),
              icon: const Icon(Icons.expand_more),
              label: const Text('Charger plus'),
            ),
          );
        }
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
          // Déjà téléchargé : la pastille remplace la flèche, on n'invite
          // plus à le reprendre.
          trailing: a.inLibrary
              ? const InLibraryBadge()
              : const Icon(Icons.download_outlined),
          onTap: () => onAlbumTap(a),
        );
      },
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
