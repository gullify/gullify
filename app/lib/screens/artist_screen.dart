import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/library_repository.dart';
import '../api/yt_downloads_repository.dart';
import '../state/genre_medley.dart';
import '../state/library.dart';
import '../state/player.dart';
import '../state/yt_downloads.dart';
import '../widgets/artwork.dart';
import '../widgets/glass_kit.dart';
import '../widgets/image_choice_dialog.dart';
import 'shell_screen.dart';
import '../widgets/share_sheet.dart';
import '../widgets/song_menu.dart';
import '../widgets/song_tile.dart';

class ArtistScreen extends ConsumerWidget {
  const ArtistScreen({super.key, required this.artistId});

  final int artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(artistDetailProvider(artistId));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      bottomNavigationBar: const DetailDock(),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (d) => ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            // En-tête : image de l'artiste plein cadre, fondu vers le fond,
            // nom en surimpression, retour en rond de verre.
            _ArtistHeader(
              imageUrl: d.artist.imageUrl,
              name: d.artist.name,
              albumCount: d.albums.length,
              genre: d.artist.genre,
              onMenu: () => _artistMenu(context, ref, d),
            ),
            const SizedBox(height: 16),
            _ArtistPlayBar(detail: d),
            if (d.albums.isNotEmpty) ...[
              const SectionTitle('Albums'),
              SizedBox(
                height: 216,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                  itemCount: d.albums.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 13),
                  itemBuilder: (context, i) {
                    final album = d.albums[i];
                    return InkWell(
                      onTap: () => context.push('/album/${album.id}'),
                      borderRadius: BorderRadius.circular(20),
                      child: SizedBox(
                        width: 140,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x40141932),
                                    blurRadius: 26,
                                    offset: Offset(0, 14),
                                  ),
                                ],
                              ),
                              child: Artwork(
                                url: album.artworkUrl,
                                size: 140,
                                borderRadius: 20,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              album.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                            if (album.year != null)
                              Text(
                                '${album.year}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            if (d.topTracks.isNotEmpty) ...[
              const SectionTitle('Titres populaires'),
              const SizedBox(height: 6),
              for (final (i, track) in d.topTracks.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: SongTile(
                    song: track,
                    showArtwork: false,
                    leadingNumber: i + 1,
                    subtitle: track.albumName,
                    onTap: () => ref
                        .read(playerActionsProvider)
                        .playSongs(d.topTracks, startIndex: i),
                    onLongPress: () => showSongMenu(context, track),
                  ),
                ),
            ],
            _YtSuggestions(detail: d),
            _SimilarArtists(name: d.artist.name),
            _ArtistExtras(name: d.artist.name),
          ],
        ),
      ),
    );
  }
}

/// Albums YouTube Music non possédés, téléchargeables en un tap.
class _YtSuggestions extends ConsumerWidget {
  const _YtSuggestions({required this.detail});

  final ArtistDetail detail;

  String _normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'\s*\((deluxe|remaster(ed)?|edition)[^)]*\)'), '')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  Future<void> _download(
    BuildContext context,
    WidgetRef ref,
    YtAlbum album,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
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
      if (context.mounted) Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text('Erreur : $e')));
      return;
    }
    if (!context.mounted) return;
    Navigator.pop(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(resolved.title),
        content: Text(
          '${resolved.artist} · ${resolved.trackCount} pistes\n\n'
          'Télécharger cet album dans votre bibliothèque ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Télécharger'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(ytQueueProvider.notifier).start(resolved);
      messenger.showSnackBar(
        SnackBar(content: Text('Téléchargement démarré : ${resolved.title}')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Échec : $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(ytArtistAlbumsProvider(detail.artist.name));
    final owned = {for (final a in detail.albums) _normalize(a.name)};
    final artistKey = _normalize(detail.artist.name);

    return suggestions.maybeWhen(
      data: (albums) {
        final missing = albums
            .where((a) =>
                _normalize(a.artist) == artistKey &&
                !owned.contains(_normalize(a.title)))
            .toList();
        if (missing.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                'À découvrir sur YouTube Music',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: missing.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final a = missing[i];
                  return InkWell(
                    onTap: () => _download(context, ref, a),
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 120,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(
                            children: [
                              Artwork(url: a.thumbnail, size: 120),
                              Positioned(
                                right: 4,
                                bottom: 4,
                                child: CircleAvatar(
                                  radius: 14,
                                  backgroundColor:
                                      Theme.of(context).colorScheme.primary,
                                  child: Icon(
                                    Icons.download,
                                    size: 16,
                                    color:
                                        Theme.of(context).colorScheme.onPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            a.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

/// Bio (Last.fm) et actualités (Google News) — meilleur effort.
class _ArtistExtras extends ConsumerWidget {
  const _ArtistExtras({required this.name});

  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extras = ref.watch(artistExtrasProvider(name));
    final scheme = Theme.of(context).colorScheme;

    return extras.maybeWhen(
      data: (e) {
        if (e.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (e.bio != null && e.bio!.trim().isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'À propos',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _ExpandableText(e.bio!.trim()),
              ),
            ],
            if (e.articles.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text(
                  'Actualités',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              for (final article in e.articles)
                ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: Text(
                    article.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    article.source,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  onTap: () => launchUrl(
                    Uri.parse(article.url),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
            ],
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _ExpandableText extends StatefulWidget {
  const _ExpandableText(this.text);

  final String text;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.text,
            maxLines: _expanded ? null : 4,
            overflow: _expanded ? null : TextOverflow.ellipsis,
            style: const TextStyle(height: 1.5),
          ),
          Text(
            _expanded ? 'Réduire' : 'Lire plus',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// « Tout lire » / « Aléatoire » : toutes les chansons de l'artiste,
/// dans l'ordre des albums ou mélangées.
class _ArtistPlayBar extends ConsumerStatefulWidget {
  const _ArtistPlayBar({required this.detail});

  final ArtistDetail detail;

  @override
  ConsumerState<_ArtistPlayBar> createState() => _ArtistPlayBarState();
}

class _ArtistPlayBarState extends ConsumerState<_ArtistPlayBar> {
  bool _busy = false;

  Future<void> _playAll({required bool shuffle}) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = ref.read(libraryRepositoryProvider);
      final details = await Future.wait([
        for (final a in widget.detail.albums) repo.albumDetail(a.id),
      ]);
      final songs = [for (final det in details) ...det.songs];
      if (songs.isEmpty) return;
      if (shuffle) songs.shuffle();
      await ref.read(playerActionsProvider).playSongs(songs);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.detail.albums.isEmpty) return const SizedBox.shrink();
    // Rangée d'action alignée : « Tout lire » pleine largeur + aléatoire.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: _busy
                ? const SizedBox(
                    height: 52,
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : AccentPlayButton(
                    label: 'Tout lire',
                    onPressed: () => _playAll(shuffle: false),
                  ),
          ),
          const SizedBox(width: 12),
          GlassIconButton(
            icon: Icons.shuffle,
            tooltip: 'Tout lire aléatoirement',
            size: 52,
            onPressed: _busy ? null : () => _playAll(shuffle: true),
          ),
        ],
      ),
    );
  }
}

/// Artistes similaires (YouTube Music) : carrousel d'avatars ronds. Un tap
/// lance une recherche sur ce nom pour l'explorer / télécharger.
class _SimilarArtists extends ConsumerWidget {
  const _SimilarArtists({required this.name});

  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final related = ref.watch(relatedArtistsProvider(name));
    return related.maybeWhen(
      data: (artists) {
        if (artists.isEmpty) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('Artistes similaires'),
            SizedBox(
              height: 148,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                itemCount: artists.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, i) {
                  final a = artists[i];
                  return SizedBox(
                    width: 92,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(46),
                      onTap: () {
                        ref.read(searchQueryProvider.notifier).set(a.name);
                        context.go('/search');
                      },
                      child: Column(
                        children: [
                          DecoratedBox(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0x33000000),
                                  blurRadius: 14,
                                  offset: Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Artwork(
                              url: a.thumbnail.isEmpty ? null : a.thumbnail,
                              size: 88,
                              borderRadius: 44,
                              icon: Icons.person,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            a.name,
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

/// Menu d'un artiste : partage éphémère, genre, photo, suppression définitive
/// (fichiers + base).
void _artistMenu(BuildContext context, WidgetRef ref, ArtistDetail d) {
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.ios_share_rounded),
            title: const Text("Partager l'artiste"),
            subtitle: const Text('Lien d\'écoute valable 24 h'),
            onTap: () {
              Navigator.pop(sheetContext);
              showShareSheet(context, ShareTarget.artist(d.artist));
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.label_outline),
            title: const Text('Définir le genre'),
            subtitle: d.artist.genre != null && d.artist.genre!.isNotEmpty
                ? Text(d.artist.genre!)
                : null,
            onTap: () {
              Navigator.pop(sheetContext);
              _setGenreDialog(
                context,
                d.artist.id,
                d.artist.genre,
                artistName: d.artist.name,
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text("Changer l'image"),
            subtitle: const Text('Proposition, lien ou photo du téléphone'),
            onTap: () {
              Navigator.pop(sheetContext);
              _artistImageDialog(context, d.artist.id, d.artist.name);
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.delete_outline,
                color: Theme.of(sheetContext).colorScheme.error),
            title: Text(
              "Supprimer l'artiste",
              style:
                  TextStyle(color: Theme.of(sheetContext).colorScheme.error),
            ),
            subtitle: const Text('Tous ses albums et titres'),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(sheetContext);
              final ok = await confirmDelete(
                context,
                'Supprimer « ${d.artist.name} » ?',
                'Tous les albums et titres de cet artiste seront effacés du '
                    'serveur. Action irréversible.',
              );
              if (ok != true) return;
              try {
                await ref
                    .read(libraryRepositoryProvider)
                    .deleteArtist(d.artist.id);
                invalidateLibrary(ref);
                if (context.mounted) {
                  context.go('/library');
                  messenger.showSnackBar(
                    SnackBar(content: Text('« ${d.artist.name} » supprimé')),
                  );
                }
              } catch (e) {
                messenger.showSnackBar(SnackBar(content: Text('Échec : $e')));
              }
            },
          ),
        ],
      ),
    ),
  );
}

/// Ce que rend le dialogue : le genre choisi, et s'il faut enchaîner sur
/// l'artiste suivant qui n'a pas de genre.
class _GenreChoice {
  const _GenreChoice(this.genre, {this.next = false});

  final String genre;
  final bool next;
}

/// Dialogue « Définir le genre » : une suggestion tirée de MusicBrainz, les
/// genres principaux à choisir d'un tap, un champ libre pour ce qui n'y rentre
/// pas — et, le temps de se décider, un medley de l'artiste qui part tout seul.
///
/// Le dialogue ne fait que choisir : c'est ici qu'on enregistre, et qu'on
/// rouvre le choix sur l'artiste suivant quand on a demandé à enchaîner
/// (ranger une bibliothèque se fait par séries, et rouvrir le dialogue sur
/// place évite l'aller-retour par la bibliothèque).
Future<void> _setGenreDialog(
  BuildContext context,
  int artistId,
  String? current, {
  String? artistName,
}) async {
  // Tout ce dont la suite a besoin se saisit AVANT l'attente : passé la
  // fermeture du dialogue, la fiche peut avoir disparu — le messager et le
  // conteneur, eux, lui survivent.
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);

  final choice = await showDialog<_GenreChoice>(
    context: context,
    builder: (_) => _GenreDialog(
      artistId: artistId,
      current: current,
      artistName: artistName,
    ),
  );
  if (choice == null) return; // Annulé : rien à enregistrer.
  final genre = choice.genre;

  try {
    await container
        .read(libraryRepositoryProvider)
        .setArtistGenre(artistId, genre);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Échec : $e')));
    return;
  }
  container.invalidate(artistDetailProvider(artistId));
  container.invalidate(genresProvider);
  container.invalidate(artistsProvider);
  container.invalidate(untaggedArtistsProvider);

  // Retirer un genre n'ouvre pas de série : on vient au contraire d'ajouter
  // un artiste à ranger.
  if (genre.isEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text('Genre retiré')));
    return;
  }

  // « Enregistrer » s'arrête là : on n'enchaîne que si on l'a demandé.
  if (!choice.next) {
    messenger.showSnackBar(const SnackBar(content: Text('Genre mis à jour')));
    return;
  }

  final untagged = await _untaggedArtists(container);
  final next = untagged?.next(exceptId: artistId);
  if (next == null || !context.mounted) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          // Sans liste (réseau), on ne prétend pas que tout est rangé.
          untagged == null || next != null
              ? 'Genre mis à jour'
              : 'Genre mis à jour · plus aucun artiste sans genre',
        ),
      ),
    );
    return;
  }

  // La série continue d'elle-même : le dialogue rouvre sur le suivant, qui
  // dit son nom en titre.
  await _setGenreDialog(context, next.id, null, artistName: next.name);
}

/// Les artistes sans genre, ou null si le serveur n'a pas répondu — le genre
/// est enregistré, une proposition qui manque ne vaut pas une erreur en
/// travers de l'écran.
Future<UntaggedArtists?> _untaggedArtists(ProviderContainer container) async {
  try {
    return await container.read(untaggedArtistsProvider.future);
  } catch (_) {
    return null;
  }
}

/// Des boutons serrés : le dialogue en compte jusqu'à quatre, et « Enregistrer
/// et suivant » est long à lui seul.
class _GenreDialog extends ConsumerStatefulWidget {
  const _GenreDialog({
    required this.artistId,
    required this.current,
    this.artistName,
  });

  final int artistId;
  final String? current;

  /// Affiché en titre : en enchaînant d'un artiste au suivant, le dialogue
  /// est tout ce qui dit qui l'on range.
  final String? artistName;

  @override
  ConsumerState<_GenreDialog> createState() => _GenreDialogState();
}

class _GenreDialogState extends ConsumerState<_GenreDialog> {
  late String? _selected = widget.current;
  final _customCtrl = TextEditingController();

  /// Saisi à l'ouverture, jamais plus tard : passé la fermeture, `ref`
  /// appartient à un widget démonté (« Using "ref" when a widget is about to
  /// or has been unmounted is unsafe ») — et il faut pourtant couper le
  /// medley.
  late final MedleyPlayer _medley;

  @override
  void initState() {
    super.initState();
    _medley = ref.read(medleyPlayerProvider.notifier);
    // Le medley part tout seul : entendre l'artiste est ce qui aide le plus à
    // le ranger, et le demander à chaque fois faisait un tap de trop sur une
    // série entière (idée #56). Une microtâche : toucher à un provider en
    // plein initState, Riverpod n'en veut pas.
    scheduleMicrotask(() => _medley.start(widget.artistId));
  }

  @override
  void dispose() {
    // Riverpod refuse qu'on touche à un provider pendant un cycle de vie du
    // widget : le medley se coupe juste après la fermeture. Une microtâche,
    // et non un Future — une minuterie en suspens ferait échouer les tests
    // qui démontent l'arbre, et le son doit s'arrêter au plus vite.
    //
    // Et seulement le sien : en enchaînant sur l'artiste suivant, ce dialogue
    // se défait après que le suivant a lancé le sien.
    scheduleMicrotask(() => _medley.stopFor(widget.artistId));
    _customCtrl.dispose();
    super.dispose();
  }

  /// Le dialogue rend le genre choisi et se ferme : l'enregistrement, lui,
  /// se poursuit chez l'appelant — le serveur répond souvent bien après, et
  /// `ref` appartiendrait alors à un widget démonté (« Using "ref" when a
  /// widget is about to or has been unmounted is unsafe »).
  void _save(String genre, {bool next = false}) =>
      Navigator.pop(context, _GenreChoice(genre, next: next));

  /// Le genre à enregistrer : ce qu'on a tapé à la main s'il y en a, sinon la
  /// tuile choisie.
  String get _chosen {
    final custom = _customCtrl.text.trim();
    return custom.isNotEmpty ? custom : (_selected ?? '');
  }

  @override
  Widget build(BuildContext context) {
    // Les genres proposés par le serveur (liste principale + ceux ajoutés à
    // la main), plus ceux que la bibliothèque contient déjà sans qu'ils en
    // fassent partie (un genre saisi au champ libre, par exemple).
    final taxonomy =
        ref.watch(genreTaxonomyProvider).value?.genres ?? const <String>[];
    final extras = [
      for (final g in ref.watch(genresProvider).value ?? [])
        if (g.name.isNotEmpty && !taxonomy.contains(g.name)) g.name,
    ]..sort();
    final choices = [...taxonomy, ...extras];

    // Ce qui aide à choisir (la suggestion, le medley) se tient en haut ; les
    // tuiles, elles seules, défilent. Sans ça, une trentaine de genres
    // repoussaient le champ libre et le medley hors de l'écran (idée #54).
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      title: Text(
        widget.artistName == null
            ? 'Genre de l\'artiste'
            : 'Genre de « ${widget.artistName} »',
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _Suggestion(
              artistId: widget.artistId,
              selected: _selected,
              onPick: (genre) => setState(() {
                _selected = genre;
                _customCtrl.clear();
              }),
            ),
            const SizedBox(height: 8),
            _MedleyButton(artistId: widget.artistId),
            const Divider(height: 18),
            if (choices.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('Genres indisponibles pour le moment.'),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final g in choices)
                        _GenreChip(
                          label: g,
                          selected: _selected == g,
                          onTap: () => setState(
                            () => _selected = _selected == g ? null : g,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 10),
            TextField(
              controller: _customCtrl,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Autre genre',
                hintText: 'Si aucun ne convient…',
              ),
              onChanged: (v) {
                // Saisir un genre à la main écarte la sélection.
                if (v.trim().isNotEmpty && _selected != null) {
                  setState(() => _selected = null);
                }
              },
            ),
          ],
        ),
      ),
      // Quatre boutons tiennent mal sur une ligne : on les serre. Ce qui
      // dépasse, l'OverflowBar le range en colonne.
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      actions: [
        if ((widget.current ?? '').isNotEmpty)
          TextButton(
            style: compactDialogAction,
            onPressed: () => _save(''),
            child: const Text('Retirer'),
          ),
        TextButton(
          style: compactDialogAction,
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        TextButton(
          style: compactDialogAction,
          onPressed: () => _save(_chosen),
          child: const Text('Enregistrer'),
        ),
        // Ranger se fait par séries : enregistrer et passer au suivant d'un
        // seul tap, sans repasser par une proposition à attraper (idée #56).
        FilledButton(
          style: compactDialogAction,
          onPressed: () => _save(_chosen, next: true),
          child: const Text('Enregistrer et suivant'),
        ),
      ],
    );
  }
}

/// Une tuile de genre, en petit. La liste en compte une trentaine : à taille
/// normale, elles remplissaient le dialogue à elles seules.
class _GenreChip extends StatelessWidget {
  const _GenreChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      // Sans crochet ni pastille : le genre choisi se reconnaît à sa couleur,
      // et chaque tuile garde sa place pour le nom qu'elle porte.
      showCheckmark: false,
      selectedColor: scheme.primary,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: selected ? scheme.onPrimary : null,
      ),
      labelPadding: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

/// La suggestion des catalogues, en tête du dialogue : un genre à prendre d'un
/// tap, d'où il vient, et les étiquettes qui l'ont dicté. Elle ne choisit
/// jamais à la place — elle propose, et se tait quand elle n'a rien de sûr.
class _Suggestion extends ConsumerWidget {
  const _Suggestion({
    required this.artistId,
    required this.selected,
    required this.onPick,
  });

  final int artistId;
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final suggestion = ref.watch(genreSuggestionProvider(artistId));
    final faint = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);

    return suggestion.when(
      loading: () => Row(
        children: [
          const SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text('Recherche d\'une suggestion…', style: faint),
        ],
      ),
      // Une suggestion qui manque n'est pas une panne : le dialogue marche
      // très bien sans, on n'affiche pas d'erreur en travers.
      error: (_, _) => Text('Suggestion indisponible', style: faint),
      data: (s) {
        if (s.genre == null) {
          return Text(
            s.tags.isEmpty
                ? 'Aucun catalogue ne dit rien de cet artiste'
                : 'Rien de net dans les catalogues (${s.tags.take(3).join(', ')})',
            style: faint,
          );
        }
        final source = s.sourceLabel;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Le titre et la tuile sur une même ligne : la suggestion tient en
            // deux lignes, et les tuiles gardent la place qu'elles réclament.
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, size: 15, color: scheme.primary),
                    const SizedBox(width: 5),
                    Text(
                      'Suggestion',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
                _GenreChip(
                  label: s.genre!,
                  selected: selected == s.genre,
                  onTap: () => onPick(s.genre!),
                ),
              ],
            ),
            if (source != null) ...[
              const SizedBox(height: 3),
              Text(
                s.tags.isEmpty
                    ? 'd\'après $source'
                    : 'd\'après $source : ${s.tags.take(4).join(', ')}',
                style: faint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Le medley : quelques extraits pris sur plusieurs albums, en fondu, pendant
/// qu'on hésite. Il tourne en boucle et s'arrête tout seul à la fermeture du
/// dialogue.
class _MedleyButton extends ConsumerWidget {
  const _MedleyButton({required this.artistId});

  final int artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final medley = ref.watch(medleyPlayerProvider);
    final song = medley.current;
    final faint = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);

    // Tout sur une ligne : ce qui joue se lit à côté du bouton, et le dialogue
    // ne s'allonge pas d'une rangée dès que le medley démarre.
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: () =>
              ref.read(medleyPlayerProvider.notifier).toggle(artistId),
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          icon: Icon(
            medley.active ? Icons.stop_circle_outlined : Icons.graphic_eq,
            size: 17,
          ),
          label: Text(medley.active ? 'Arrêter le medley' : 'Écouter un medley'),
        ),
        const SizedBox(width: 8),
        if (medley.error)
          Expanded(
            child: Text('Rien à faire écouter', style: faint, maxLines: 1),
          )
        else if (song != null)
          Expanded(
            child: Row(
              children: [
                EqBars(color: scheme.primary, height: 12),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${song.title}  (${medley.index}/${medley.total})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: faint,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Dialogue « Changer l'image » (idée #78), et ce qu'il faut faire après :
/// la fiche et la bibliothèque reprennent l'URL neuve — elle porte la date de
/// la photo, sans quoi le cache d'images de l'app continuerait d'afficher
/// l'ancienne et le changement n'aurait l'air de rien.
Future<void> _artistImageDialog(
  BuildContext context,
  int artistId,
  String artistName,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final repo = container.read(libraryRepositoryProvider);

  final done = await showDialog<String>(
    context: context,
    // Les propositions portent le nom que le service leur donne, et le nom
    // cherché se change : la reconnaissance automatique tombe parfois sur un
    // homonyme, et c'est le seul moyen de lui dire de quel artiste il s'agit.
    builder: (_) => ImageChoiceDialog(
      title: 'Image de « $artistName »',
      searchLabel: 'Chercher un artiste',
      initialQuery: artistName,
      round: true,
      placeholderIcon: Icons.person,
      emptyMessage: 'Aucune photo trouvée sous ce nom.',
      doneMessage: 'Image mise à jour',
      resetLabel: 'Image automatique',
      resetMessage: 'Image automatique rétablie',
      onSearch: (q) async => [
        for (final c in await repo.artistImageCandidates(artistId, query: q))
          ImageCandidate(
            thumbnail: c.thumbnail,
            label: c.name,
            source: c.source,
          ),
      ],
      onUrl: (url) => repo.setArtistImageFromUrl(artistId, url),
      onFile: (path) => repo.uploadArtistImage(artistId, path),
      onReset: () => repo.resetArtistImage(artistId),
    ),
  );
  if (done == null) return; // Refermé sans rien changer.

  container.invalidate(artistDetailProvider(artistId));
  container.invalidate(artistsProvider);
  messenger.showSnackBar(SnackBar(content: Text(done)));
}

/// En-tête d'artiste : image plein cadre qui se fond dans le fond de l'app,
/// nom en surimpression bas-gauche, bouton retour en verre.
class _ArtistHeader extends StatelessWidget {
  const _ArtistHeader({
    required this.imageUrl,
    required this.name,
    required this.albumCount,
    required this.genre,
    required this.onMenu,
  });

  final String? imageUrl;
  final String name;
  final int albumCount;
  final String? genre;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final topInset = MediaQuery.paddingOf(context).top;

    return SizedBox(
      height: 440,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // L'image se DISSOUT en transparence vers le bas (ShaderMask) :
          // le vrai dégradé de fond de l'app transparaît en continu, sans
          // couleur intermédiaire ni couture.
          ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.5, 1.0],
              colors: [Colors.white, Colors.white, Colors.transparent],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: Artwork(url: imageUrl, borderRadius: 0, icon: Icons.person),
          ),
          // Voile sombre discret en haut pour la lisibilité du bouton retour.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topInset + 70,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x33000000), Color(0x00000000)],
                ),
              ),
            ),
          ),
          Positioned(
            left: 14,
            top: topInset + 8,
            child: GlassIconButton(
              icon: Icons.chevron_left,
              tooltip: 'Retour',
              onPressed: () => context.pop(),
            ),
          ),
          Positioned(
            right: 14,
            top: topInset + 8,
            child: GlassIconButton(
              icon: Icons.more_vert,
              tooltip: 'Options',
              onPressed: onMenu,
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    height: 1.02,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (genre != null && genre!.isNotEmpty) genre!,
                    '$albumCount album${albumCount > 1 ? 's' : ''}',
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
