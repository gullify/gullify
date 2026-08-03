import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/videos_repository.dart';
import '../state/videos.dart';
import '../widgets/glass_box.dart';

/// Onglet « Vidéos » : chercher des clips, des concerts et des lives sur
/// YouTube, les regarder tout de suite (le serveur relaie le flux) ou les
/// télécharger sur le serveur pour les revoir en pleine qualité.
class VideosScreen extends ConsumerStatefulWidget {
  const VideosScreen({super.key});

  @override
  ConsumerState<VideosScreen> createState() => _VideosScreenState();
}

class _VideosScreenState extends ConsumerState<VideosScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: ref.read(videoSearchQueryProvider),
  );
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) ref.read(videoSearchQueryProvider.notifier).set(value);
    });
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    ref.read(videoSearchQueryProvider.notifier).set('');
  }

  void _watch(String id, String title) =>
      context.push('/videos/watch/$id?title=${Uri.encodeComponent(title)}');

  Future<void> _download(VideoResult video) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(videosRepositoryProvider).download(video);
      ref.invalidate(videoLibraryProvider);
      messenger.showSnackBar(
        SnackBar(content: Text('Téléchargement lancé : ${video.title}')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Échec : $e')));
    }
  }

  Future<void> _delete(ServerVideo video) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer la vidéo ?'),
        content: Text(
          '« ${video.title} » sera effacée du serveur. Elle restera '
          'consultable en direct depuis YouTube.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(videosRepositoryProvider).delete(video.id);
      ref.invalidate(videoLibraryProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Échec : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final query = ref.watch(videoSearchQueryProvider);
    final library = ref.watch(videoLibraryProvider);
    final onServer = {
      for (final v in library.value ?? const <ServerVideo>[]) v.id: v,
    };

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom + 110,
          ),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 2),
              child: Text(
                'Vidéos',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  height: 1.02,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                'Clips, concerts et lives — à regarder tout de suite ou à '
                'garder sur le serveur.',
                style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _VideoSearchField(
                controller: _controller,
                hasQuery: query.isNotEmpty,
                onChanged: _onChanged,
                onClear: _clear,
              ),
            ),
            if (query.length >= 2)
              ..._results(onServer)
            else
              ..._library(library),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────── Résultats YouTube ───────────────────────────

  List<Widget> _results(Map<String, ServerVideo> onServer) {
    final results = ref.watch(videoSearchProvider);
    return [
      const _Header('Sur YouTube'),
      ...results.when(
        loading: () => const [_Loading()],
        error: (e, _) => [_Message('Recherche impossible : $e')],
        data: (list) => list.isEmpty
            ? const [_Message('Aucune vidéo trouvée')]
            : [
                for (final v in list)
                  _VideoCard(
                    title: v.title,
                    subtitle: v.channel,
                    thumbnail: v.thumbnail,
                    duration: v.duration,
                    live: v.live,
                    onTap: () => _watch(v.id, v.title),
                    trailing: switch (onServer[v.id]?.status) {
                      VideoStatus.ready => Icon(
                        Icons.download_done_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      VideoStatus.downloading => const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      _ => IconButton(
                        tooltip: 'Télécharger sur le serveur',
                        icon: const Icon(Icons.download_outlined),
                        onPressed: () => _download(v),
                      ),
                    },
                  ),
              ],
      ),
    ];
  }

  // ────────────────────────── Vidéothèque serveur ──────────────────────────

  List<Widget> _library(AsyncValue<List<ServerVideo>> library) => [
    const _Header('Sur le serveur'),
    ...library.when(
      loading: () => const [_Loading()],
      error: (e, _) => [_Message('Vidéothèque indisponible : $e')],
      data: (list) => list.isEmpty
          ? const [
              _Message(
                'Aucune vidéo téléchargée.\n'
                'Cherche un clip ou un concert ci-dessus : tu peux le '
                'regarder directement, ou le garder ici en pleine qualité.',
              ),
            ]
          : [
              for (final v in list)
                _VideoCard(
                  title: v.title,
                  subtitle: [
                    if (v.channel.isNotEmpty) v.channel,
                    if (v.isReady && v.size > 0)
                      '${(v.size / (1024 * 1024)).round()} Mo',
                    if (v.status == VideoStatus.downloading)
                      'Téléchargement ${v.progress} %',
                    if (v.status == VideoStatus.error)
                      'Échec du téléchargement',
                  ].join(' · '),
                  thumbnail: v.thumbnail,
                  duration: v.duration,
                  live: false,
                  progress: v.status == VideoStatus.downloading
                      ? v.progress / 100
                      : null,
                  onTap: () => _watch(v.id, v.title),
                  trailing: IconButton(
                    tooltip: 'Supprimer du serveur',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(v),
                  ),
                ),
            ],
    ),
  ];
}

/// Champ de recherche en verre, même langage que l'onglet Recherche.
class _VideoSearchField extends StatelessWidget {
  const _VideoSearchField({
    required this.controller,
    required this.hasQuery,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final bool hasQuery;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassBox(
      radius: 18,
      blur: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Row(
          children: [
            Icon(Icons.search, size: 22, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                decoration: const InputDecoration(
                  hintText: 'Un clip, un concert, un live…',
                  filled: false,
                  isDense: true,
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            if (hasQuery)
              IconButton(
                tooltip: 'Effacer',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: Icon(
                  Icons.close,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                onPressed: onClear,
              ),
          ],
        ),
      ),
    );
  }
}

/// Carte vidéo : vignette 16/9 avec pastille de durée, titre, sous-titre.
class _VideoCard extends StatelessWidget {
  const _VideoCard({
    required this.title,
    required this.subtitle,
    required this.thumbnail,
    required this.duration,
    required this.live,
    required this.onTap,
    required this.trailing,
    this.progress,
  });

  final String title;
  final String subtitle;
  final String thumbnail;
  final Duration duration;
  final bool live;
  final VoidCallback onTap;
  final Widget trailing;

  /// Avancement d'un téléchargement en cours (0-1), sinon `null`.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: GlassBox(
        radius: 20,
        blur: false,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                _Thumbnail(url: thumbnail, duration: duration, live: live),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (progress != null) ...[
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.url,
    required this.duration,
    required this.live,
  });

  final String url;
  final Duration duration;
  final bool live;

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      color: Colors.black.withValues(alpha: 0.35),
      child: Icon(
        Icons.movie_rounded,
        color: Colors.white.withValues(alpha: 0.5),
        size: 26,
      ),
    );
    return SizedBox(
      width: 124,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (url.isEmpty)
                placeholder
              else
                CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => placeholder,
                  errorWidget: (_, _, _) => placeholder,
                ),
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: live
                        ? scheme.error.withValues(alpha: 0.9)
                        : Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    live
                        ? 'EN DIRECT'
                        : duration > Duration.zero
                        ? _fmt(duration)
                        : '—',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
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

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
      ),
    ),
  );
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 28),
    child: Center(child: CircularProgressIndicator()),
  );
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 13.5,
        height: 1.35,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
