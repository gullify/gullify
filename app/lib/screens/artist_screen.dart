import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/library_repository.dart';
import '../api/yt_downloads_repository.dart';
import '../models/artist.dart';
import '../state/genre_medley.dart';
import '../state/library.dart';
import '../state/player.dart';
import '../state/pour_toi.dart';
import '../state/yt_downloads.dart';
import '../widgets/artwork.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/detail_hero.dart';
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
              genre: _etiquette(d.artist),
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
          PrimaryActionSlot(
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

/// Artistes similaires : carrousel d'avatars ronds. Ils viennent du serveur
/// (Last.fm quand il a une clé, sinon YouTube Music) ; un serveur d'avant
/// la 1.16.0 n'en sait rien, l'app demande alors à YouTube Music. Un
/// artiste déjà dans la bibliothèque ouvre sa fiche ; les autres, une
/// recherche pour l'écouter ou le télécharger.
class _SimilarArtists extends ConsumerWidget {
  const _SimilarArtists({required this.name});

  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serveur = ref.watch(prochesArtisteProvider(name));
    // Le serveur n'a rien (ou ne sait pas) : YouTube Music, depuis l'app.
    final repli = serveur.hasError || (serveur.hasValue && serveur.value!.isEmpty);
    final List<(String, String?, int?)>? artistes = repli
        ? ref
              .watch(relatedArtistsProvider(name))
              .value
              ?.map(
                (a) => (a.name, a.thumbnail.isEmpty ? null : a.thumbnail, null),
              )
              .toList()
        : serveur.value?.map((b) => (b.nom, b.image, b.artistId)).toList();
    if (artistes == null || artistes.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Artistes similaires'),
        SizedBox(
          height: 160,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            itemCount: artistes.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) {
              final (nom, image, artistId) = artistes[i];
              return SizedBox(
                width: 92,
                child: InkWell(
                  borderRadius: BorderRadius.circular(46),
                  onTap: () {
                    if (artistId != null) {
                      context.push('/artist/$artistId');
                    } else {
                      ref.read(searchQueryProvider.notifier).set(nom);
                      context.go('/search');
                    }
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
                          url: image,
                          size: 88,
                          borderRadius: 44,
                          icon: Icons.person,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        nom,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      Text(
                        artistId != null ? 'Dans ta biblio' : 'À découvrir',
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
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
            subtitle: _etiquette(d.artist) != null
                ? Text(_etiquette(d.artist)!)
                : null,
            onTap: () {
              Navigator.pop(sheetContext);
              _setGenreDialog(
                context,
                d.artist.id,
                _genresDe(d.artist),
                origine: d.artist.origine,
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

/// Ce que rend le dialogue : les genres choisis (le principal en tête), l'origine,
/// et s'il faut enchaîner sur l'artiste suivant qui n'a pas de genre.
class _GenreChoice {
  const _GenreChoice(
    this.genres, {
    this.origine,
    this.origineChanged = false,
    this.next = false,
  });

  final List<String> genres;
  final String? origine;

  /// L'origine n'est envoyée que si on l'a touchée : la poser marque le
  /// choix comme fait à la main, et le scan ne la corrigerait plus.
  final bool origineChanged;
  final bool next;
}

/// Les genres d'un artiste, le principal compris même d'un serveur d'avant.
List<String> _genresDe(Artist a) =>
    a.genres.isNotEmpty ? a.genres : [?a.genre];

/// Ce qui se lit sous le nom d'un artiste : ses genres, puis d'où il vient.
String? _etiquette(Artist a) {
  final parts = [
    if (_genresDe(a).isNotEmpty) _genresDe(a).join(', '),
    if ((a.origine ?? '').isNotEmpty) a.origine!,
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Dialogue « Définir le genre » : la suggestion des catalogues (Last.fm
/// d'abord), les genres principaux à choisir d'un tap — jusqu'à trois, le
/// premier choisi est le principal —, l'origine (Québec, France…), un champ
/// libre pour ce qui n'y rentre pas, et, le temps de se décider, un medley de
/// l'artiste qui part tout seul.
///
/// Le dialogue ne fait que choisir : c'est ici qu'on enregistre, et qu'on
/// rouvre le choix sur l'artiste suivant quand on a demandé à enchaîner
/// (ranger une bibliothèque se fait par séries, et rouvrir le dialogue sur
/// place évite l'aller-retour par la bibliothèque).
Future<void> _setGenreDialog(
  BuildContext context,
  int artistId,
  List<String> current, {
  String? origine,
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
      origine: origine,
      artistName: artistName,
    ),
  );
  if (choice == null) return; // Annulé : rien à enregistrer.
  final genres = choice.genres;

  try {
    await container
        .read(libraryRepositoryProvider)
        .setArtistGenres(
          artistId,
          genres,
          origine: choice.origine,
          withOrigine: choice.origineChanged,
        );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Échec : $e')));
    return;
  }
  container.invalidate(artistDetailProvider(artistId));
  container.invalidate(genresProvider);
  container.invalidate(originesProvider);
  container.invalidate(artistsProvider);
  container.invalidate(untaggedArtistsProvider);

  // Retirer un genre n'ouvre pas de série : on vient au contraire d'ajouter
  // un artiste à ranger.
  if (genres.isEmpty) {
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
  await _setGenreDialog(context, next.id, const [], artistName: next.name);
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

/// Trois genres au plus : au-delà, un artiste n'est plus rangé, il est partout.
const _maxGenres = 3;

/// Des boutons serrés : le dialogue en compte jusqu'à quatre, et « Enregistrer
/// et suivant » est long à lui seul.
class _GenreDialog extends ConsumerStatefulWidget {
  const _GenreDialog({
    required this.artistId,
    required this.current,
    this.origine,
    this.artistName,
  });

  final int artistId;
  final List<String> current;
  final String? origine;

  /// Affiché en titre : en enchaînant d'un artiste au suivant, le dialogue
  /// est tout ce qui dit qui l'on range.
  final String? artistName;

  @override
  ConsumerState<_GenreDialog> createState() => _GenreDialogState();
}

class _GenreDialogState extends ConsumerState<_GenreDialog> {
  /// Les genres choisis, dans l'ordre : le premier est le principal.
  late final List<String> _selected = [...widget.current];
  late String? _origine = widget.origine;
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

  /// Taper un genre l'ajoute (à la suite) ou le retire ; plein, le plus
  /// récent des secondaires laisse sa place.
  void _toggle(String genre) => setState(() {
    if (_selected.remove(genre)) return;
    if (_selected.length >= _maxGenres) _selected.removeLast();
    _selected.add(genre);
  });

  /// La suggestion d'un tap : ses genres remplacent la sélection, et son
  /// origine s'y joint si rien n'était choisi.
  void _takeSuggestion(GenreSuggestion s) => setState(() {
    _selected
      ..clear()
      ..addAll(s.allGenres.take(_maxGenres));
    _customCtrl.clear();
    if (_origine == null && s.origine != null) _origine = s.origine;
  });

  /// Le dialogue rend le choix et se ferme : l'enregistrement, lui, se
  /// poursuit chez l'appelant — le serveur répond souvent bien après, et
  /// `ref` appartiendrait alors à un widget démonté (« Using "ref" when a
  /// widget is about to or has been unmounted is unsafe »).
  void _save(List<String> genres, {bool next = false}) => Navigator.pop(
    context,
    _GenreChoice(
      genres,
      origine: _origine,
      origineChanged: _origine != widget.origine,
      next: next,
    ),
  );

  /// Les genres à enregistrer : les tuiles choisies, puis ce qu'on a tapé à
  /// la main (en principal s'il n'y a rien d'autre).
  List<String> get _chosen {
    final custom = _customCtrl.text.trim();
    return [
      ..._selected,
      if (custom.isNotEmpty && !_selected.contains(custom)) custom,
    ].take(_maxGenres).toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Les genres proposés par le serveur (liste principale + ceux ajoutés à
    // la main), plus ceux que la bibliothèque contient déjà sans qu'ils en
    // fassent partie (un genre saisi au champ libre, par exemple).
    final tax = ref.watch(genreTaxonomyProvider).value;
    final taxonomy = tax?.genres ?? const <String>[];
    final extras = [
      for (final g in ref.watch(genresProvider).value ?? [])
        if (g.name.isNotEmpty && !taxonomy.contains(g.name)) g.name,
    ]..sort();
    final choices = [...taxonomy, ...extras];
    // Les origines de la liste, plus celle de l'artiste si elle n'y est pas.
    final origines = [
      ...?tax?.origines,
      if (_origine != null && !(tax?.origines.contains(_origine) ?? false))
        _origine!,
    ];
    final faint = TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant);

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
              onPick: _takeSuggestion,
            ),
            const SizedBox(height: 8),
            _MedleyButton(artistId: widget.artistId),
            const Divider(height: 18),
            if (choices.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('Genres indisponibles pour le moment.'),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Jusqu\'à $_maxGenres genres · le premier choisi est le '
                  'principal',
                  style: faint,
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final g in choices)
                        _GenreChip(
                          label: g,
                          selected: _selected.contains(g),
                          principal: _selected.isNotEmpty &&
                              _selected.first == g,
                          onTap: () => _toggle(g),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (origines.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Origine', style: faint),
              const SizedBox(height: 4),
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final o in origines)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: _GenreChip(
                          label: o,
                          selected: _origine == o,
                          onTap: () => setState(
                            () => _origine = _origine == o ? null : o,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 6),
            TextField(
              controller: _customCtrl,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Autre genre',
                hintText: 'Si aucun ne convient…',
              ),
            ),
          ],
        ),
      ),
      // Quatre boutons tiennent mal sur une ligne : on les serre. Ce qui
      // dépasse, l'OverflowBar le range en colonne.
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      actions: [
        if (widget.current.isNotEmpty)
          TextButton(
            style: compactDialogAction,
            onPressed: () => _save(const []),
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
/// normale, elles remplissaient le dialogue à elles seules. Le genre
/// principal porte une étoile.
class _GenreChip extends StatelessWidget {
  const _GenreChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.principal = false,
  });

  final String label;
  final bool selected;
  final bool principal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      // Sans crochet : le genre choisi se reconnaît à sa couleur, le
      // principal à son étoile, et chaque tuile garde sa place pour le nom
      // qu'elle porte.
      showCheckmark: false,
      avatar: principal
          ? Icon(Icons.star_rounded, size: 14, color: scheme.onPrimary)
          : null,
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

/// La suggestion des catalogues, en tête du dialogue : des genres à prendre
/// d'un tap, l'origine, d'où ça vient, et les étiquettes qui l'ont dicté.
/// Elle ne choisit jamais à la place — elle propose, et se tait quand elle
/// n'a rien de sûr.
class _Suggestion extends ConsumerWidget {
  const _Suggestion({
    required this.artistId,
    required this.selected,
    required this.onPick,
  });

  final int artistId;
  final List<String> selected;
  final ValueChanged<GenreSuggestion> onPick;

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
        final genres = s.allGenres;
        if (genres.isEmpty && s.origine == null) {
          return Text(
            s.tags.isEmpty
                ? 'Aucun catalogue ne dit rien de cet artiste'
                : 'Rien de net dans les catalogues (${s.tags.take(3).join(', ')})',
            style: faint,
          );
        }
        final source = s.sourceLabel;
        final pris = genres.isNotEmpty &&
            genres.length == selected.length &&
            [for (var i = 0; i < genres.length; i++) genres[i] == selected[i]]
                .every((x) => x);
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
                // Un seul tap prend tout : les genres dans l'ordre, et
                // l'origine.
                _GenreChip(
                  label: [
                    if (genres.isNotEmpty) genres.join(' + '),
                    ?s.origine,
                  ].join(' · '),
                  selected: pris,
                  onTap: () => onPick(s),
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

/// En-tête d'artiste : nom, genre et nombre d'albums, posés sur son image. La
/// mise en page — plein cadre au téléphone, portrait à côté du nom sur grand
/// écran — est celle de [DetailHero], partagée avec la fiche album.
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

    return DetailHero(
      imageUrl: imageUrl,
      icon: Icons.person,
      roundCover: true,
      onMenu: onMenu,
      info: Column(
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
    );
  }
}
