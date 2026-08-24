import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/yt_downloads_repository.dart';
import '../../state/library.dart';
import '../../state/player.dart';
import '../../state/yt_downloads.dart';
import 'tv_download.dart';
import 'tv_kit.dart';
import 'tv_text_entry.dart';

/// La recherche, avec le clavier de Google.
///
/// Le champ est un simple élément focalisable tant qu'on n'écrit pas : « OK »
/// ouvre le clavier du système (celui de la télé, avec sa dictée vocale), et
/// dès qu'il se referme la croix directionnelle repart vers les résultats.
/// C'est le même mécanisme que sur les écrans de connexion — voir
/// [TvImeField], qui explique pourquoi un champ de texte ne doit jamais
/// garder le focus sur un téléviseur.
///
/// Comme sur téléphone, la recherche ne s'arrête pas à la bibliothèque : les
/// albums et titres trouvés sur YouTube apparaissent en dessous, et se
/// téléchargent sur le serveur d'un appui. Champ vide, ce sont les nouveautés
/// de YouTube qui s'affichent — de quoi partir de quelque part.
///
/// Pas de bouton « chercher » : les résultats suivent la saisie.
class TvSearchPage extends ConsumerStatefulWidget {
  const TvSearchPage({super.key});

  @override
  ConsumerState<TvSearchPage> createState() => _TvSearchPageState();
}

class _TvSearchPageState extends ConsumerState<TvSearchPage> {
  final _field = TextEditingController();

  /// Ce qu'on s'apprête à télécharger, le temps de la confirmation.
  TvDownloadTarget? _target;
  YtDuplicate? _duplicate;
  bool _busy = false;
  String? _error;

  String get _query => _field.text;

  @override
  void initState() {
    super.initState();
    // Les résultats suivent la saisie : pas de bouton « chercher » à aller
    // viser après chaque mot.
    _field.addListener(() {
      if (mounted) setState(() {});
      ref.read(searchQueryProvider.notifier).set(_field.text);
    });
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  /// Demande d'abord au serveur s'il a déjà ça, puis propose.
  Future<void> _ask(TvDownloadTarget target) async {
    setState(() {
      _target = target;
      _duplicate = null;
      _error = null;
    });
    final repo = ref.read(ytDownloadsRepositoryProvider);
    final duplicate = switch (target) {
      TvAlbumTarget(:final album) => await repo.checkDuplicate(
        artist: album.artist,
        album: album.title,
      ),
      TvSongTarget(:final song) => await repo.checkDuplicate(
        artist: song.artist,
        album: tvSongAlbum(song),
        url: song.watchUrl,
        title: song.title,
      ),
    };
    if (mounted && _target == target) setState(() => _duplicate = duplicate);
  }

  Future<void> _confirm() async {
    final target = _target;
    if (target == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await tvStartDownload(ref, target, force: _duplicate != null);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      if (error == null) _target = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final results = ref.watch(searchResultsProvider);

    return Stack(
      children: [
        TvScaffold(
          title: 'Recherche',
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 560, child: _keyboard(scheme)),
              const SizedBox(width: 70),
              Expanded(
                child: _query.trim().length < 2
                    ? _NewReleases(onDownload: _ask)
                    : results.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (e, _) => TvEmpty(
                          message: 'Recherche impossible',
                          hint: '$e',
                          icon: Icons.cloud_off_rounded,
                        ),
                        data: (r) => r.isEmpty
                            ? TvEmpty(
                                message: 'Rien pour « $_query »',
                                hint: 'Essaie moins de lettres.',
                                icon: Icons.search_off_rounded,
                              )
                            : ListView(
                                padding: const EdgeInsets.only(bottom: 40),
                                children: [
                                  if (r.artists.isNotEmpty)
                                    TvShelf(
                                      label: 'Artistes',
                                      itemCount: r.artists.length,
                                      height: 300,
                                      itemBuilder: (context, i, onFocus) => TvCard(
                                        title: r.artists[i].name,
                                        subtitle:
                                            '${r.artists[i].albumCount} albums',
                                        size: 200,
                                        round: true,
                                        icon: Icons.person_rounded,
                                        artwork: TvArtwork(
                                          url: r.artists[i].imageUrl,
                                          borderRadius: 0,
                                        ),
                                        onFocusChange: (f) {
                                          if (f) onFocus();
                                        },
                                        onPressed: () => context.push(
                                          '/tv/artist/${r.artists[i].id}',
                                        ),
                                      ),
                                    ),
                                  if (r.albums.isNotEmpty) ...[
                                    const SizedBox(height: 34),
                                    TvShelf(
                                      label: 'Albums',
                                      itemCount: r.albums.length,
                                      height: 300,
                                      itemBuilder: (context, i, onFocus) =>
                                          TvCard(
                                            title: r.albums[i].name,
                                            subtitle: r.albums[i].artistName,
                                            size: 200,
                                            artwork: TvArtwork(
                                              url: r.albums[i].artworkUrl,
                                              borderRadius: 0,
                                            ),
                                            onFocusChange: (f) {
                                              if (f) onFocus();
                                            },
                                            onPressed: () => context.push(
                                              '/tv/album/${r.albums[i].id}',
                                            ),
                                          ),
                                    ),
                                  ],
                                  if (r.songs.isNotEmpty) ...[
                                    const SizedBox(height: 34),
                                    const TvShelfLabel('Titres'),
                                    for (var i = 0; i < r.songs.length; i++)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 6,
                                        ),
                                        child: TvTrackTile(
                                          index: i + 1,
                                          title: r.songs[i].title,
                                          subtitle: r.songs[i].artistName,
                                          onPressed: () async {
                                            await ref
                                                .read(playerActionsProvider)
                                                .playSongs(
                                                  r.songs,
                                                  startIndex: i,
                                                );
                                            if (context.mounted) {
                                              context.push('/tv/playing');
                                            }
                                          },
                                        ),
                                      ),
                                  ],
                                  // La bibliothèque d'abord, YouTube ensuite :
                                  // on cherche presque toujours ce qu'on a déjà.
                                  _YtResults(query: _query, onDownload: _ask),
                                ],
                              ),
                      ),
              ),
            ],
          ),
        ),
        if (_target != null)
          TvDownloadConfirm(
            title: switch (_target!) {
              TvAlbumTarget(:final album) => album.title,
              TvSongTarget(:final song) => song.title,
            },
            subtitle: switch (_target!) {
              TvAlbumTarget(:final album) => album.artist,
              TvSongTarget(:final song) => song.artist,
            },
            details: switch (_target!) {
              TvAlbumTarget(:final album) => album.year,
              TvSongTarget(:final song) => song.duration,
            },
            duplicate: _duplicate,
            busy: _busy,
            error: _error,
            onConfirm: _confirm,
            onCancel: () => setState(() {
              _target = null;
              _error = null;
            }),
          ),
      ],
    );
  }

  Widget _keyboard(ColorScheme scheme) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      TvImeField(
        label: 'RECHERCHER',
        controller: _field,
        autofocus: true,
        hint: 'Appuie sur OK',
      ),
      const SizedBox(height: 20),
      Text(
        'Le clavier de la télé s\'ouvre sur OK — la dictée vocale de la '
        'télécommande y marche aussi. Les résultats suivent la saisie.',
        style: TextStyle(
          fontSize: tvMinText,
          height: 1.4,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
        ),
      ),
      if (_query.isNotEmpty) ...[
        const SizedBox(height: 20),
        TvPill(
          label: 'Effacer',
          icon: Icons.backspace_outlined,
          accent: false,
          expand: true,
          onPressed: _field.clear,
        ),
      ],
    ],
  );
}

/// Les nouveautés de YouTube, quand on n'a encore rien tapé.
class _NewReleases extends ConsumerWidget {
  const _NewReleases({required this.onDownload});

  final ValueChanged<TvDownloadTarget> onDownload;

  static const _placeholder = TvEmpty(
    message: 'Que cherches-tu ?',
    hint: 'Deux lettres suffisent — les résultats suivent la saisie.',
    icon: Icons.search_rounded,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final releases = ref.watch(ytNewReleasesProvider);
    return releases.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _placeholder,
      data: (albums) => albums.isEmpty
          ? _placeholder
          : ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                Text(
                  'Sorties récentes des artistes que tu écoutes. Appuie sur '
                  'OK pour en télécharger une sur ton serveur.',
                  style: TextStyle(
                    fontSize: tvMinText,
                    height: 1.4,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                _YtAlbumShelf(
                  label: 'Nouveautés sur YouTube',
                  albums: albums,
                  onDownload: onDownload,
                ),
              ],
            ),
    );
  }
}

/// Ce que YouTube propose pour la recherche en cours.
class _YtResults extends ConsumerWidget {
  const _YtResults({required this.query, required this.onDownload});

  final String query;
  final ValueChanged<TvDownloadTarget> onDownload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final albumList =
        ref.watch(ytAlbumSearchProvider(query)).value ?? const <YtAlbum>[];
    final songList =
        ref.watch(ytSongSearchProvider(query)).value ?? const <YtSong>[];
    if (albumList.isEmpty && songList.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 40),
        Text(
          'SUR YOUTUBE — À TÉLÉCHARGER',
          style: TextStyle(
            fontSize: tvMinText,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.6,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: 16),
        if (albumList.isNotEmpty)
          _YtAlbumShelf(
            label: 'Albums',
            albums: albumList,
            onDownload: onDownload,
          ),
        if (songList.isNotEmpty) ...[
          const SizedBox(height: 26),
          const TvShelfLabel('Titres'),
          for (var i = 0; i < songList.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: TvTrackTile(
                index: i + 1,
                title: songList[i].title,
                subtitle: [
                  songList[i].artist,
                  if (songList[i].inLibrary) 'déjà dans ta bibliothèque',
                ].where((s) => s.isNotEmpty).join(' · '),
                duration: songList[i].duration,
                onPressed: () => onDownload(TvSongTarget(songList[i])),
              ),
            ),
        ],
      ],
    );
  }
}

class _YtAlbumShelf extends StatelessWidget {
  const _YtAlbumShelf({
    required this.label,
    required this.albums,
    required this.onDownload,
  });

  final String label;
  final List<YtAlbum> albums;
  final ValueChanged<TvDownloadTarget> onDownload;

  @override
  Widget build(BuildContext context) {
    final shown = albums.take(20).toList();
    return TvShelf(
      label: label,
      height: 320,
      itemCount: shown.length,
      itemBuilder: (context, i, onFocus) => TvCard(
        title: shown[i].title,
        subtitle: [
          shown[i].artist,
          if (shown[i].inLibrary) 'déjà là',
        ].where((s) => s.isNotEmpty).join(' · '),
        size: 220,
        icon: Icons.cloud_download_rounded,
        artwork: shown[i].thumbnail.isEmpty
            ? null
            : Image.network(
                shown[i].thumbnail,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
        onFocusChange: (f) {
          if (f) onFocus();
        },
        onPressed: () => onDownload(TvAlbumTarget(shown[i])),
      ),
    );
  }
}
