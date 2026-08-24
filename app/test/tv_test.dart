// L'interface Google TV.
//
// Une app de téléviseur se casse autrement qu'une app de téléphone : ce n'est
// pas le tactile qui lâche, c'est le focus. Ces tests vérifient donc surtout
// que la croix directionnelle mène quelque part — et que les cinq écrans
// tiennent dans un 1920 × 1080 sans rien rogner.
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/api_client.dart';
import 'package:gullify/api/library_repository.dart';
import 'package:gullify/api/party_repository.dart';
import 'package:gullify/api/radio_repository.dart';
import 'package:gullify/models/album.dart';
import 'package:gullify/models/artist.dart';
import 'package:gullify/models/song.dart';
import 'package:gullify/screens/tv/tv_album_screen.dart';
import 'package:gullify/screens/tv/tv_connect_screens.dart';
import 'package:gullify/screens/tv/tv_kit.dart';
import 'package:gullify/screens/tv/tv_now_playing_screen.dart';
import 'package:gullify/screens/tv/tv_party_page.dart';
import 'package:gullify/screens/tv/tv_home_page.dart';
import 'package:gullify/screens/tv/tv_search_page.dart';
import 'package:gullify/screens/tv/tv_shell.dart';
import 'package:gullify/screens/tv/tv_update.dart';
import 'package:gullify/state/app_update.dart';
import 'package:gullify/state/auth.dart';
import 'package:gullify/models/game_track.dart';
import 'package:gullify/screens/tv/tv_solo_game_screen.dart';
import 'package:gullify/api/playlist_repository.dart';
import 'package:gullify/api/yt_downloads_repository.dart';
import 'package:gullify/state/discover.dart';
import 'package:gullify/state/favorites.dart';
import 'package:gullify/state/playlists.dart';
import 'package:gullify/state/yt_downloads.dart';
import 'package:gullify/state/games.dart';
import 'package:gullify/state/library.dart';
import 'package:gullify/state/party.dart';
import 'package:gullify/state/player.dart';
import 'package:gullify/state/radio.dart';
import 'package:gullify/state/tv.dart';
import 'package:gullify/theme.dart';

const _songs = [
  Song(
    id: 1,
    title: 'Ruby Soho',
    filePath: 'a.mp3',
    duration: 158,
    artistName: 'Rancid',
    albumName: 'Wolves',
    trackNumber: 1,
  ),
  Song(
    id: 2,
    title: 'Time Bomb',
    filePath: 'b.mp3',
    duration: 146,
    artistName: 'Rancid',
    albumName: 'Wolves',
    trackNumber: 2,
  ),
  Song(
    id: 3,
    title: 'Drain the Blood',
    filePath: 'c.mp3',
    duration: 187,
    artistName: 'The Distillers',
    albumName: 'Coral Fang',
    trackNumber: 3,
  ),
];

const _wolves = Album(
  id: 1,
  name: 'Wolves',
  year: 1995,
  artistId: 1,
  artistName: 'Rancid',
);

const _albums = [
  _wolves,
  Album(id: 2, name: 'Coral Fang', year: 2003, artistName: 'The Distillers'),
  Album(id: 3, name: 'La Grand-Messe', year: 2004, artistName: 'Cowboys'),
  Album(id: 4, name: 'Random Life', year: 2001, artistName: 'Subb'),
  Album(id: 5, name: 'Indestructible', year: 2003, artistName: 'Rancid'),
  Album(id: 6, name: 'Commit This', year: 2005, artistName: 'MCS'),
  Album(id: 7, name: 'Sing the Sorrow', year: 2003, artistName: 'AFI'),
];

const _artists = [
  Artist(id: 1, name: 'Rancid', albumCount: 6, songCount: 78),
  Artist(id: 2, name: 'The Distillers', albumCount: 3, songCount: 34),
  Artist(id: 3, name: 'Les Cowboys Fringants', albumCount: 8, songCount: 96),
];

const _stations = [
  RadioStation(
    id: 'r1',
    name: 'CISM',
    streamUrl: 'http://x/1',
    genres: ['Indé'],
  ),
  RadioStation(id: 'r2', name: 'CKOI', streamUrl: 'http://x/2'),
];

class _FakePlayerActions extends Fake implements PlayerActions {}

/// Favoris figés : le vrai notifier interroge le serveur.
class _FixedFavorites extends FavoriteIds {
  @override
  Future<Set<int>> build() async => const {};
}

/// Les jeux ne demandent au dépôt que l'URL de lecture d'un extrait.
class _FakeLibrary extends Fake implements LibraryRepository {
  @override
  String streamUrl(Song song) => 'https://example.test/${song.id}.mp3';
}

final _blindPool = [
  for (var i = 1; i <= 12; i++)
    Song(
      id: i,
      title: 'Titre $i',
      filePath: '$i.mp3',
      duration: 180 + i,
      albumName: 'Album \$i',
      artistName: 'Artiste \$i',
    ),
];

const _genres = [
  GenreCount('Punk', 4, albumCount: 9),
  GenreCount('Ska', 2, albumCount: 3),
];

const _playlists = [
  Playlist(id: 1, name: 'Défricheur', songCount: 12),
  Playlist(id: 2, name: 'Road trip', songCount: 40),
];

final _gameAlbums = [
  for (var i = 1; i <= 12; i++)
    Album(
      id: i,
      name: 'Album $i',
      year: 1970 + i * 3,
      artistName: 'Artiste $i',
    ),
];

final _gameTracks = [
  for (var i = 1; i <= 12; i++)
    GameTrack(song: _blindPool[i - 1], year: 1970 + i * 3),
];

final _discovery = [
  for (var i = 1; i <= 12; i++)
    DiscoveryTrack(song: _blindPool[i - 1], year: 1970 + i * 3),
];

/// Auth figée : le vrai contrôleur relit le trousseau et interroge le serveur.
class _FixedAuth extends AuthController {
  _FixedAuth(this.value);

  final AuthState value;

  @override
  AuthState build() => value;
}

/// Mise à jour figée : le vrai notifier interroge le réseau et le paquet
/// installé, dont aucun n'existe en test.
class _FixedUpdate extends AppUpdateNotifier {
  _FixedUpdate(this.value);

  final AppUpdateState value;

  @override
  AppUpdateState build() => value;

  @override
  Future<void> check({bool silent = false}) async {}
}

/// Partie figée : le vrai contrôleur sonderait le serveur en boucle.
class _FixedParty extends PartyController {
  _FixedParty(this.session);

  final PartySession session;

  @override
  PartySession build() => session;

  @override
  Future<bool> create({
    required String game,
    required String audioMode,
    Object? source,
  }) async => true;

  @override
  Future<void> refresh() async {}

  @override
  Future<void> start() async {}

  @override
  Future<void> close() async {}
}

Map<String, dynamic> _partyJson({
  required String status,
  required String phase,
  Map<String, dynamic>? round,
  String game = 'blind',
}) => {
  'code': 'K7M2',
  'game': game,
  'audioMode': 'host',
  'status': status,
  'phase': phase,
  'version': 3,
  'serverNow': 1000000,
  'phaseAt': 995000,
  'roundMs': 20000,
  'revealMs': 4500,
  'roundIndex': 2,
  'roundCount': 10,
  'turnPlayerId': null,
  'maxPlayers': 12,
  'me': {'id': 1, 'name': 'Salon', 'isHost': true},
  'players': [
    {
      'id': 1,
      'name': 'Salon',
      'isHost': true,
      'score': 130,
      'lives': 3,
      'answered': true,
      'correct': null,
      'gained': null,
      'timeline': null,
    },
    {
      'id': 2,
      'name': 'Léa',
      'isHost': false,
      'score': 210,
      'lives': 2,
      'answered': false,
      'correct': null,
      'gained': null,
      'timeline': null,
    },
  ],
  'round': round,
};

PartyState _party(Map<String, dynamic> json) =>
    PartyState.fromJson(json, (u) => u);

/// Requête figée : le champ de recherche la relit à l'ouverture.
class _FixedQuery extends SearchQuery {
  _FixedQuery(this.value);

  final String value;

  @override
  String build() => value;
}

/// Le titre porté par la carte actuellement visée.
String? _focusedCardTitle(WidgetTester tester) {
  final node = FocusManager.instance.primaryFocus;
  if (node?.context == null) return null;
  final card = find.descendant(
    of: find.byWidget(node!.context!.widget),
    matching: find.byType(TvCard),
  );
  if (tester.widgetList<TvCard>(card).isEmpty) {
    // Le nœud visé vit *dans* la carte : on remonte plutôt que de descendre.
    TvCard? found;
    node.context!.visitAncestorElements((el) {
      if (el.widget is TvCard) {
        found = el.widget as TvCard;
        return false;
      }
      return true;
    });
    return found?.title;
  }
  return tester.widgetList<TvCard>(card).first.title;
}

Widget _wrap(
  Widget child, {
  MediaItem? item,
  PartySession? party,
  AppUpdateState? update,
  String? lyrics,
  DiscoverArtist? discovery,
  String? query,
  Duration position = const Duration(seconds: 61),
  bool tv = true,
}) => ProviderScope(
  overrides: [
    lyricsProvider('a.mp3').overrideWith((ref) async => lyrics),
    if (update != null)
      appUpdateProvider.overrideWith(() => _FixedUpdate(update)),
    tvDetectedProvider.overrideWithValue(tv),
    tvForceInitialProvider.overrideWithValue(TvForce.auto),
    playerActionsProvider.overrideWithValue(_FakePlayerActions()),
    currentMediaItemProvider.overrideWith(
      (ref) => Stream<MediaItem?>.value(item),
    ),
    playbackStateProvider.overrideWith(
      (ref) => Stream.value(PlaybackState(playing: item != null)),
    ),
    positionProvider.overrideWith((ref) => Stream.value(position)),
    queueProvider.overrideWith(
      (ref) => Stream.value(item == null ? const <MediaItem>[] : [item]),
    ),
    recentAlbumsProvider.overrideWith((ref) async => _albums),
    albumsProvider.overrideWith((ref) async => _albums),
    popularSongsProvider.overrideWith((ref) async => _songs),
    artistsProvider.overrideWith((ref) async => _artists),
    allFavoritesProvider.overrideWith((ref) async => _songs),
    favoriteIdsProvider.overrideWith(_FixedFavorites.new),
    radioStationsProvider.overrideWith((ref) async => _stations),
    searchResultsProvider.overrideWith((ref) async => const SearchResults()),
    genresProvider.overrideWith((ref) async => _genres),
    playlistsProvider.overrideWith((ref) async => _playlists),
    discoverArtistProvider.overrideWith((ref) async => discovery),
    if (query != null)
      searchQueryProvider.overrideWith(() => _FixedQuery(query)),
    ytNewReleasesProvider.overrideWith((ref) async => <YtAlbum>[]),
    // Sans quoi la vraie recherche YouTube part sur le réseau et laisse un
    // minuteur en suspens à la fin du test.
    ytAlbumSearchProvider.overrideWith((ref, q) async => <YtAlbum>[]),
    ytSongSearchProvider.overrideWith((ref, q) async => <YtSong>[]),
    blindPoolProvider.overrideWith((ref) async => _blindPool),
    gamePoolProvider.overrideWith(
      // La pochette mystère exige huit albums pochettés : le catalogue de la
      // bibliothèque du harnais en compte moins.
      (ref) async => GamePool(tracks: _gameTracks, albums: _gameAlbums),
    ),
    discoveryTracksProvider.overrideWith((ref) async => _discovery),
    libraryRepositoryProvider.overrideWithValue(_FakeLibrary()),
    albumDetailProvider(1).overrideWith(
      (ref) async => const AlbumDetail(album: _wolves, songs: _songs),
    ),
    if (party != null) partyProvider.overrideWith(() => _FixedParty(party)),
  ],
  child: MaterialApp(
    theme: gullifyThemeFor(GullifyAccent.indigo, dark: true),
    home: child,
  ),
);

/// Un téléviseur 1080p, en points logiques.
Future<void> _tvScreen(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1920, 1080));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

/// Le contenu agrandi d'une vignette : ce que porte l'AnimatedScale, et donc
/// ce qui déborde quand la place manque.
Finder _scaledContent(Finder within) => find
    .descendant(
      of: find
          .descendant(of: within, matching: find.byType(AnimatedScale))
          .first,
      matching: find.byType(Column),
    )
    .first;

/// Vrai quand l'élément qui a le focus se trouve à l'intérieur d'un widget
/// du type donné.
bool _focusInside(Type type) {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  var found = false;
  ctx.visitAncestorElements((e) {
    if (e.widget.runtimeType == type) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// Laisse un jeu charger son vivier sans faire courir son chrono : une
/// manche dure quinze secondes, et `pumpAndSettle` les consommerait toutes
/// avant la première vérification.
Future<void> _settleGame(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

void main() {
  group('quelle interface servir', () {
    test('sans forçage, Android décide', () {
      for (final detected in [true, false]) {
        final c = ProviderContainer(
          overrides: [
            tvDetectedProvider.overrideWithValue(detected),
            tvForceInitialProvider.overrideWithValue(TvForce.auto),
          ],
        );
        addTearDown(c.dispose);
        expect(c.read(tvModeProvider), detected);
        expect(c.read(tvModeProvider.notifier).isAutomatic, isTrue);
      }
    });

    test('le forçage l\'emporte, dans les deux sens', () {
      final c = ProviderContainer(
        overrides: [
          tvDetectedProvider.overrideWithValue(false),
          tvForceInitialProvider.overrideWithValue(TvForce.tv),
        ],
      );
      addTearDown(c.dispose);
      // Un téléphone qui se fait passer pour une télé : c'est tout l'intérêt
      // du réglage, essayer l'interface sans téléviseur sous la main.
      expect(c.read(tvModeProvider), isTrue);
      expect(c.read(tvModeProvider.notifier).isAutomatic, isFalse);

      final tv = ProviderContainer(
        overrides: [
          tvDetectedProvider.overrideWithValue(true),
          tvForceInitialProvider.overrideWithValue(TvForce.handheld),
        ],
      );
      addTearDown(tv.dispose);
      expect(tv.read(tvModeProvider), isFalse);
    });
  });

  group('le focus, seul curseur de la télécommande', () {
    testWidgets('« OK » active l\'élément visé', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(
        _wrap(
          Center(
            child: TvFocusable(
              autofocus: true,
              onPressed: () => pressed++,
              builder: (context, focused) =>
                  SizedBox(width: 200, height: 80, child: Text('$focused')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _press(tester, LogicalKeyboardKey.enter);
      expect(pressed, 1);
      // La barre d'espace d'un clavier USB doit valoir « OK » elle aussi.
      await _press(tester, LogicalKeyboardKey.space);
      expect(pressed, 2);
    });

    testWidgets('la croix parcourt une rangée', (tester) async {
      await _tvScreen(tester);
      final visited = <int>[];
      await tester.pumpWidget(
        _wrap(
          Scaffold(
            body: TvShelf(
              label: 'Albums',
              itemCount: 6,
              itemBuilder: (context, i, onFocus) => TvCard(
                title: 'Album $i',
                autofocus: i == 0,
                onFocusChange: (f) {
                  if (f) {
                    visited.add(i);
                    onFocus();
                  }
                },
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(visited, [0]);
      await _press(tester, LogicalKeyboardKey.arrowRight);
      await _press(tester, LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      // Deux appuis à droite = deux cartes plus loin, sans saut ni retour.
      expect(visited, [0, 1, 2]);
    });
  });

  group('la coque', () {
    testWidgets('le rail ne s\'ouvre qu\'en recevant le focus', (tester) async {
      await _tvScreen(tester);
      await tester.pumpWidget(_wrap(const TvShell()));
      await tester.pumpAndSettle();

      // Au repos, les libellés restent cachés : le rail n'est qu'une bande
      // d'icônes, la place est à la musique.
      expect(find.text('Bibliothèque'), findsNothing);
      expect(find.text('Réglages'), findsNothing);

      // Aller à gauche depuis le contenu ouvre le tiroir.
      await _press(tester, LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.text('Bibliothèque'), findsOneWidget);
      expect(find.text('Réglages'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('replié, les icônes sont dans l\'axe du logo', (tester) async {
      await _tvScreen(tester);
      await tester.pumpWidget(_wrap(const TvShell()));
      await tester.pumpAndSettle();

      final logo = tester.getRect(find.byType(Image).first);
      final icon = tester.getRect(find.byIcon(TvTab.home.icon));
      expect(
        icon.center.dx,
        closeTo(logo.center.dx, 1),
        reason: 'les icônes doivent tomber sous le logo, pas à côté',
      );
    });

    testWidgets('choisir une destination change de page', (tester) async {
      await _tvScreen(tester);
      await tester.pumpWidget(_wrap(const TvShell()));
      await tester.pumpAndSettle();

      await _press(tester, LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Radio'));
      await tester.pumpAndSettle();

      expect(find.text('CISM'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('les écrans tiennent dans un 1920 × 1080', () {
    for (final (name, tab) in <(String, TvTab)>[
      ('accueil', TvTab.home),
      ('bibliothèque', TvTab.library),
      ('recherche', TvTab.search),
      ('favoris', TvTab.favorites),
      ('radio', TvTab.radio),
      ('jeux', TvTab.games),
    ]) {
      testWidgets(name, (tester) async {
        await _tvScreen(tester);
        await tester.pumpWidget(_wrap(TvShell(initialTab: tab)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('album', (tester) async {
      await _tvScreen(tester);
      await tester.pumpWidget(_wrap(const TvAlbumScreen(albumId: 1)));
      await tester.pumpAndSettle();
      expect(find.text('Wolves'), findsOneWidget);
      expect(find.text('Ruby Soho'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lecture en cours', (tester) async {
      await _tvScreen(tester);
      await tester.pumpWidget(
        _wrap(
          const TvNowPlayingScreen(),
          item: MediaItem(
            id: '1',
            title: 'Ruby Soho',
            artist: 'Rancid',
            album: 'Wolves',
            duration: Duration(seconds: 158),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ruby Soho'), findsOneWidget);
      expect(find.text('Pause'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lecture en cours, file vide', (tester) async {
      await _tvScreen(tester);
      await tester.pumpWidget(_wrap(const TvNowPlayingScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Rien en lecture'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('entrer dans une rangée', () {
    testWidgets('depuis la bannière, on atterrit sur la première carte', (
      tester,
    ) async {
      await _tvScreen(tester);
      await tester.pumpWidget(_wrap(const TvShell()));
      await tester.pump(const Duration(milliseconds: 400));

      // La bannière commence après la pochette : la carte la plus proche
      // géométriquement est la deuxième, et c'est là qu'on atterrissait.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        _focusedCardTitle(tester),
        _albums.first.name,
        reason: 'la descente doit viser la première carte de la rangée',
      );
    });

    testWidgets('en revenant, on retrouve la carte quittée', (tester) async {
      await _tvScreen(tester);
      await tester.pumpWidget(_wrap(const TvShell()));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 400));
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump(const Duration(milliseconds: 400));
      }
      final quittee = _focusedCardTitle(tester);
      expect(quittee, _albums[3].name);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump(const Duration(milliseconds: 400));

      expect(_focusedCardTitle(tester), quittee);
    });
  });

  group('la recherche sur la télé', () {
    testWidgets('YouTube apparaît même quand la bibliothèque n\'a rien', (
      tester,
    ) async {
      await _tvScreen(tester);
      await tester.pumpWidget(_wrap(const TvSearchPage(), query: 'Belvedere'));
      await tester.pump(const Duration(milliseconds: 400));

      // La section YouTube vivait dans la branche « il y a des résultats
      // locaux » : elle disparaissait précisément quand elle sert, pour un
      // artiste qu'on ne possède pas encore.
      expect(find.text('SUR YOUTUBE — À TÉLÉCHARGER'), findsOneWidget);
      expect(find.textContaining('Rien dans ta bibliothèque'), findsOneWidget);
    });
  });

  group('remonter une page', () {
    testWidgets('rend le haut de la page, pas seulement le dernier bouton', (
      tester,
    ) async {
      await _tvScreen(tester);
      await tester.pumpWidget(_wrap(const TvShell()));
      await tester.pump(const Duration(milliseconds: 400));

      final liste = find.byType(Scrollable).first;
      final position = tester.state<ScrollableState>(liste).position;

      // Descendre jusqu'en bas de l'accueil, rangée par rangée.
      for (var i = 0; i < 8; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(position.pixels, greaterThan(200));

      // Puis tout remonter. Sans dégagement, le défilement s'arrête au
      // dernier élément visable et la bannière reste hors champ à jamais.
      for (var i = 0; i < 12; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(position.pixels, position.minScrollExtent);
    });
  });

  group('l\'artiste à découvrir', () {
    testWidgets('passe avant les rangées, et « Le chercher » ouvre la '
        'recherche', (tester) async {
      await _tvScreen(tester);
      await tester.pumpWidget(
        _wrap(
          const TvShell(),
          discovery: const DiscoverArtist(
            artist: YtArtist(
              name: 'Les Trois Accords',
              browseId: 'X',
              thumbnail: '',
            ),
            becauseOf: 'Rancid',
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Au-dessus des rangées : sans avoir à faire défiler, la découverte
      // est déjà plus haut que « Derniers ajouts ».
      final decouverte = tester.getTopLeft(find.text('À DÉCOUVRIR')).dy;
      final rangee = tester.getTopLeft(find.text('Derniers ajouts')).dy;
      expect(decouverte, lessThan(rangee));

      // Un bandeau, pas un demi-écran : il court d'un bord à l'autre de la
      // page, sinon il redouble la silhouette de la bannière au-dessus.
      final bandeau = tester.getRect(
        find
            .ancestor(
              of: find.text('À DÉCOUVRIR'),
              matching: find.byType(Container),
            )
            .first,
      );
      final page = tester.getRect(find.byType(TvHomePage));
      expect(bandeau.left, lessThan(page.left + 40));
      expect(bandeau.right, greaterThan(page.right - 140));
      // Et les commandes vivent à l'autre bout, pas collées au texte.
      expect(
        tester.getRect(find.text('Le chercher')).center.dx,
        greaterThan(bandeau.center.dx),
      );

      await tester.tap(find.text('Le chercher'));
      await tester.pump(const Duration(milliseconds: 400));
      // La recherche est un onglet de la coque : c'est elle qui doit être à
      // l'écran, pas un second accueil empilé par-dessus.
      expect(find.byType(TvSearchPage), findsOneWidget);
      expect(find.text('Derniers ajouts'), findsNothing);
      // Et le nom doit être dans le champ : changer d'onglet sans le porter
      // laissait la page sur ses nouveautés, sans rien chercher.
      expect(find.text('Les Trois Accords'), findsWidgets);
    });
  });

  group('la fiche d\'un artiste', () {
    test('le nombre de titres vient de totalSongs, pas de la fiche', () {
      // Le serveur met le compte à côté de l'artiste (`totalSongs`) et non
      // dedans : sans report, l'app affichait « 0 titres » pour tout le monde.
      final repo = LibraryRepository(
        ApiClient(serverUrl: 'https://exemple.test/'),
      );
      final detail = repo.decodeArtistDetail(const {
        'artist': {'id': 5946, 'name': '1755', 'genre': 'Acadien'},
        'albums': [
          {'id': 1, 'name': 'Album A'},
          {'id': 2, 'name': 'Album B'},
          {'id': 3, 'name': 'Album C'},
        ],
        'topTracks': <Map<String, dynamic>>[],
        'totalSongs': 53,
      }, 5946);
      expect(detail.artist.songCount, 53);
      expect(detail.artist.albumCount, 3);
      expect(detail.albums, hasLength(3));
    });
  });

  group('l\'élément visé a la place de grandir', () {
    testWidgets('en tête de rangée, rien n\'est rogné', (tester) async {
      await _tvScreen(tester);
      await tester.pumpWidget(
        _wrap(
          Scaffold(
            body: TvShelf(
              label: 'Albums',
              itemCount: 6,
              itemBuilder: (context, i, onFocus) => TvCard(
                title: 'Album $i',
                autofocus: i == 0,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      // L'agrandissement est animé : il faut le laisser arriver au bout.
      await tester.pumpAndSettle();

      final list = tester.getRect(find.byType(ListView));
      // On mesure le CONTENU de la vignette, pas sa boîte de mise en page :
      // c'est lui qui porte l'agrandissement, la boîte, elle, ne bouge pas.
      final first = tester.getRect(_scaledContent(find.byType(ListView)));
      expect(
        first.left,
        greaterThanOrEqualTo(list.left),
        reason: 'la première vignette dépasse à gauche, donc se fait couper',
      );
      expect(first.top, greaterThanOrEqualTo(list.top));
      expect(first.bottom, lessThanOrEqualTo(list.bottom));
    });

    testWidgets('dans une grille non plus', (tester) async {
      await _tvScreen(tester);
      await tester.pumpWidget(_wrap(const TvShell(initialTab: TvTab.library)));
      await tester.pumpAndSettle();

      final grid = tester.getRect(find.byType(GridView));
      final first = tester.getRect(_scaledContent(find.byType(GridView)));
      expect(
        first.left,
        greaterThanOrEqualTo(grid.left),
        reason: 'la vignette de la première colonne se fait couper',
      );
      expect(first.top, greaterThanOrEqualTo(grid.top));
    });
  });

  group('la taille du dessin', () {
    testWidgets('une toile de 1920 se réduit à l\'écran réel', (tester) async {
      // Un téléviseur 1080p ne rapporte pas 1920 points logiques mais 960 :
      // sa densité vaut 2. Sans mise à l'échelle, tout s'affichait deux fois
      // trop grand — c'est ce qui débordait de l'écran.
      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: TvCanvas(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 1920, height: 200, child: Placeholder()),
            ),
          ),
        ),
      );
      await tester.pump();

      // Composé en 1920, rendu en 960 : la moitié, exactement.
      final painted = tester.getSize(find.byType(Placeholder));
      expect(painted.width, TvCanvas.design);
      final rect = tester.getRect(find.byType(Placeholder));
      expect(rect.width, closeTo(960, 0.5));
      expect(rect.height, closeTo(100, 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('sur un écran déjà en 1920, rien ne bouge', (tester) async {
      await _tvScreen(tester);
      await tester.pumpWidget(
        const MaterialApp(
          home: TvCanvas(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 1920, height: 200, child: Placeholder()),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.getRect(find.byType(Placeholder)).width,
        closeTo(1920, 0.5),
      );
    });
  });

  group('la saisie, avec le clavier de Google', () {
    Widget connect(Widget child) => ProviderScope(
      overrides: [
        tvDetectedProvider.overrideWithValue(true),
        tvForceInitialProvider.overrideWithValue(TvForce.auto),
        authProvider.overrideWith(
          () => _FixedAuth(
            const AuthState(
              status: AuthStatus.needsLogin,
              serverUrl: 'https://gullify.app',
            ),
          ),
        ),
      ],
      child: MaterialApp(
        theme: gullifyThemeFor(GullifyAccent.indigo, dark: true),
        home: child,
      ),
    );

    testWidgets('la saisie passe par le champ natif d\'Android', (
      tester,
    ) async {
      await _tvScreen(tester);
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('gullify/textinput'),
        (call) async {
          calls.add(call);
          return 'https://exemple.test';
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('gullify/textinput'),
          null,
        ),
      );

      await tester.pumpWidget(connect(const TvServerScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ADRESSE DU SERVEUR'));
      await tester.pumpAndSettle();

      // C'est là tout le remède : le texte est saisi par une vraie vue
      // Android, la seule à qui le système confie la croix directionnelle.
      expect(calls.single.method, 'prompt');
      expect(calls.single.arguments['value'], 'https://');
      expect(find.text('https://exemple.test'), findsOneWidget);
    });

    testWidgets('au repos, aucun champ de texte ne retient la croix', (
      tester,
    ) async {
      await _tvScreen(tester);
      await tester.pumpWidget(connect(const TvServerScreen()));
      await tester.pumpAndSettle();

      // C'est TOUT le principe : tant qu'on ne demande pas à écrire, il n'y a
      // pas de champ de texte à l'écran — donc rien qui puisse avaler les
      // flèches.
      expect(find.byType(EditableText), findsNothing);
      expect(find.text('https://'), findsOneWidget);

      // Et la croix descend normalement vers le bouton.
      final before = FocusManager.instance.primaryFocus;
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, isNot(same(before)));
    });

    testWidgets('valider sans adresse le dit, au lieu de ne rien faire', (
      tester,
    ) async {
      await _tvScreen(tester);
      await tester.pumpWidget(connect(const TvServerScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TvPill, 'Se connecter').first);
      await tester.pump();
      expect(find.text('Saisis l\'adresse de ton serveur.'), findsOneWidget);
    });

    testWidgets('la page identifiants tient sans écraser l\'écran', (
      tester,
    ) async {
      // Vraies dimensions d'un téléviseur 1080p, tel qu'Android les rapporte.
      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(connect(const TvCanvas(child: TvLoginScreen())));
      await tester.pumpAndSettle();

      // Deux champs, un bouton, la mascotte et le titre : le tout doit
      // occuper une part raisonnable de l'écran, pas le remplir.
      final title = tester.getRect(find.text('Connexion'));
      final submit = tester.getRect(
        find.widgetWithText(TvPill, 'Se connecter').first,
      );
      final used = submit.bottom - title.top;
      expect(used, lessThan(340), reason: 'formulaire trop haut pour 540 px');
      // Un titre de 32 sur la toile : 16 px réels de haut, pas davantage.
      expect(title.height, lessThan(30));
      // Et la colonne reste étroite : un formulaire ne s'étale pas sur toute
      // la largeur d'un téléviseur.
      expect(submit.width, lessThan(300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('se connecter sans identifiants le dit', (tester) async {
      await _tvScreen(tester);
      await tester.pumpWidget(connect(const TvLoginScreen()));
      await tester.pumpAndSettle();
      final submit = find.widgetWithText(TvPill, 'Se connecter').first;
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pump();
      expect(
        find.text('Il faut un nom d\'utilisateur et un mot de passe.'),
        findsOneWidget,
      );
    });
  });

  group('ce qui bloquait sur la vraie télé', () {
    testWidgets('l\'accueil vise toujours quelque chose', (tester) async {
      await _tvScreen(tester);
      // Bibliothèque vide et rien en lecture : l'état exact d'un premier
      // démarrage, juste après la connexion.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tvDetectedProvider.overrideWithValue(true),
            tvForceInitialProvider.overrideWithValue(TvForce.auto),
            playerActionsProvider.overrideWithValue(_FakePlayerActions()),
            currentMediaItemProvider.overrideWith(
              (ref) => Stream<MediaItem?>.value(null),
            ),
            playbackStateProvider.overrideWith(
              (ref) => Stream.value(PlaybackState()),
            ),
            recentAlbumsProvider.overrideWith((ref) async => <Album>[]),
            popularSongsProvider.overrideWith((ref) async => <Song>[]),
            artistsProvider.overrideWith((ref) async => <Artist>[]),
            allFavoritesProvider.overrideWith((ref) async => <Song>[]),
          ],
          child: MaterialApp(
            theme: gullifyThemeFor(GullifyAccent.indigo, dark: true),
            home: const TvShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.context,
        isNotNull,
        reason: 'sans nœud visé, la télécommande ne répond à rien',
      );
      expect(tester.takeException(), isNull);
    });

    test('les pochettes sont demandées à la taille affichée', () {
      // La source fait souvent 1400 px : la demander telle quelle pour une
      // vignette de 250 px est ce qui saturait la mémoire du boîtier.
      expect(
        TvArtwork.sized('serve_image.php?album_id=1', 250, 1),
        'serve_image.php?album_id=1&size=256',
      );
      expect(
        TvArtwork.sized('serve_image.php?album_id=1', 440, 2),
        'serve_image.php?album_id=1&size=1024',
      );
      // Ce qui ne vient pas du serveur d'images n'est pas touché.
      expect(
        TvArtwork.sized('https://ailleurs.test/x.jpg', 250, 1),
        'https://ailleurs.test/x.jpg',
      );
      expect(TvArtwork.sized(null, 250, 1), isNull);
    });
  });

  group('« Retour » ne doit pas faire sortir par erreur', () {
    /// Ce que l'app demande à Android quand elle veut vraiment se fermer.
    List<MethodCall> watchExit(WidgetTester tester) {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemNavigator.pop') calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      return calls;
    }

    testWidgets('le premier appui prévient, le second quitte', (tester) async {
      await _tvScreen(tester);
      final exits = watchExit(tester);
      await tester.pumpWidget(_wrap(const TvShell()));
      await tester.pumpAndSettle();

      // Premier appui : le menu se déploie.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Bibliothèque'), findsOneWidget);
      expect(exits, isEmpty);

      // Deuxième : l'avertissement.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        find.text('Appuie encore sur Retour pour quitter Gullify'),
        findsOneWidget,
      );
      expect(exits, isEmpty, reason: 'un geste distrait ne doit rien fermer');

      // Troisième seulement : la sortie.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(exits, hasLength(1));
    });

    testWidgets('passé le délai, il faut recommencer', (tester) async {
      await _tvScreen(tester);
      final exits = watchExit(tester);
      await tester.pumpWidget(_wrap(const TvShell()));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      // Trois secondes plus tard, l'avertissement a disparu : un appui isolé
      // ne doit pas rester « armé » indéfiniment.
      await tester.pump(const Duration(seconds: 4));
      expect(
        find.text('Appuie encore sur Retour pour quitter Gullify'),
        findsNothing,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(exits, isEmpty);
    });

    testWidgets('depuis une page, « Retour » déploie le menu', (tester) async {
      await _tvScreen(tester);
      final exits = watchExit(tester);
      await tester.pumpWidget(_wrap(const TvShell()));
      await tester.pumpAndSettle();
      expect(find.text('Bibliothèque'), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Ce qu'on cherche neuf fois sur dix en appuyant : le menu.
      expect(find.text('Bibliothèque'), findsOneWidget);
      expect(exits, isEmpty);
      expect(
        find.text('Appuie encore sur Retour pour quitter Gullify'),
        findsNothing,
      );
    });

    testWidgets('une mise à jour ouverte, « Retour » la referme', (
      tester,
    ) async {
      await _tvScreen(tester);
      final exits = watchExit(tester);
      await tester.pumpWidget(
        _wrap(
          const TvShell(),
          update: const AppUpdateState(
            status: UpdateStatus.available,
            available: UpdateInfo(
              versionCode: 200,
              versionName: '4.0.0',
              downloadUrl: 'https://example.test/g.apk',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mettre à jour'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Mettre à jour'), findsNothing);
      expect(exits, isEmpty);
    });
  });

  group('ce qui doit rester hors d\'atteinte', () {
    testWidgets('une mise à jour prend la main : le fond ne se vise plus', (
      tester,
    ) async {
      await _tvScreen(tester);
      await tester.pumpWidget(
        _wrap(
          const TvShell(),
          update: const AppUpdateState(
            status: UpdateStatus.available,
            available: UpdateInfo(
              versionCode: 200,
              versionName: '4.0.0',
              downloadUrl: 'https://example.test/g.apk',
            ),
            currentVersion: '3.45.0',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mettre à jour'), findsOneWidget);
      expect(
        _focusInside(TvUpdateOverlay),
        isTrue,
        reason: 'le panneau doit tenir le focus dès son ouverture',
      );

      // Et la croix ne doit pas pouvoir redescendre dans la page derrière.
      for (final key in [
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowRight,
      ]) {
        await _press(tester, key);
        await tester.pumpAndSettle();
        expect(
          _focusInside(TvUpdateOverlay),
          isTrue,
          reason: 'la croix est sortie du panneau vers l\'arrière-plan',
        );
      }
    });

    testWidgets('le menu se parcourt de bout en bout sans s\'échapper', (
      tester,
    ) async {
      await _tvScreen(tester);
      await tester.pumpWidget(_wrap(const TvShell()));
      await tester.pumpAndSettle();

      await _press(tester, LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      bool inRail() {
        final ctx = FocusManager.instance.primaryFocus?.context;
        var found = false;
        ctx?.visitAncestorElements((e) {
          if (e.widget.runtimeType.toString() == '_Rail') found = true;
          return !found;
        });
        return found;
      }

      expect(inRail(), isTrue);
      // Six destinations plus les réglages : on doit pouvoir descendre
      // jusqu'en bas sans jamais retomber dans la page derrière.
      for (var i = 0; i < TvTab.values.length + 1; i++) {
        await _press(tester, LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(inRail(), isTrue, reason: 'sorti du menu après \$i descentes');
      }
      expect(find.text('Réglages'), findsOneWidget);

      // Et la flèche droite en sort, une fois pour toutes.
      await _press(tester, LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(inRail(), isFalse);
    });

    testWidgets('choisir un onglet referme le rail et rend la main', (
      tester,
    ) async {
      await _tvScreen(tester);
      await tester.pumpWidget(_wrap(const TvShell()));
      await tester.pumpAndSettle();

      await _press(tester, LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.text('Jeux'), findsOneWidget);

      await tester.tap(find.text('Jeux'));
      await tester.pumpAndSettle();

      // Le rail se referme, et le focus est passé dans la page : sinon on
      // monte et descend dans le menu sans jamais pouvoir rien choisir.
      expect(find.text('Bibliothèque'), findsNothing);
      expect(_focusInside(TvShell) && !_focusInside(TvUpdateOverlay), isTrue);
      final focused = FocusManager.instance.primaryFocus?.context;
      var inRail = false;
      focused?.visitAncestorElements((e) {
        if (e.widget.runtimeType.toString() == '_Rail') inRail = true;
        return !inRail;
      });
      expect(inRail, isFalse, reason: 'le focus est resté dans le menu');
    });
  });

  group('les mises à jour, depuis la télé', () {
    const info = UpdateInfo(
      versionCode: 200,
      versionName: '4.0.0',
      downloadUrl: 'https://example.test/gullify.apk',
      changelog: 'Une nouveauté épatante.',
    );

    testWidgets('rien à signaler : aucun bandeau', (tester) async {
      await _tvScreen(tester);
      await tester.pumpWidget(
        _wrap(
          const TvUpdateOverlay(),
          update: const AppUpdateState(status: UpdateStatus.upToDate),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TvPill), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('une version disponible se propose en grand', (tester) async {
      await _tvScreen(tester);
      await tester.pumpWidget(
        _wrap(
          const TvUpdateOverlay(),
          update: const AppUpdateState(
            status: UpdateStatus.available,
            available: info,
            currentVersion: '3.38.0',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Gullify 4.0.0'), findsOneWidget);
      expect(find.text('Tu es en 3.38.0'), findsOneWidget);
      expect(find.text('Une nouveauté épatante.'), findsOneWidget);
      expect(find.text('Mettre à jour'), findsOneWidget);
      expect(find.text('Plus tard'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('le téléchargement montre sa progression', (tester) async {
      await _tvScreen(tester);
      await tester.pumpWidget(
        _wrap(
          const TvUpdateOverlay(),
          update: const AppUpdateState(
            status: UpdateStatus.downloading,
            available: info,
            progress: 0.42,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Téléchargement…'), findsOneWidget);
      expect(find.text('42 %'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('l\'installation explique l\'écran d\'Android', (tester) async {
      await _tvScreen(tester);
      await tester.pumpWidget(
        _wrap(
          const TvUpdateOverlay(),
          update: const AppUpdateState(
            status: UpdateStatus.readyToInstall,
            available: info,
            apkPath: '/tmp/x.apk',
          ),
        ),
      );
      await tester.pumpAndSettle();
      // La permission « sources inconnues » est le seul moment où l'écran
      // sort de Gullify : il faut le dire, sinon on croit que ça a planté.
      expect(find.textContaining('autorisation'), findsOneWidget);
      expect(find.text('Relancer l\'installation'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // C'est là qu'on restait coincé : une installation refusée par Android
    // laissait le panneau planté, sans « Plus tard » ni « Retour » qui
    // tienne, et toute l'app devenait inatteignable.
    for (final status in [
      UpdateStatus.available,
      UpdateStatus.readyToInstall,
      UpdateStatus.error,
    ]) {
      testWidgets('« Plus tard » referme le panneau depuis ${status.name}', (
        tester,
      ) async {
        await _tvScreen(tester);
        await tester.pumpWidget(
          _wrap(
            const TvShell(),
            update: AppUpdateState(
              status: status,
              available: info,
              apkPath: '/tmp/x.apk',
              message: 'Échec du téléchargement',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TvPill, 'Plus tard'), findsOneWidget);

        await tester.tap(find.widgetWithText(TvPill, 'Plus tard'));
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(TvPill, 'Plus tard'),
          findsNothing,
          reason: 'le panneau doit se refermer',
        );
      });
    }

    testWidgets('un échec se dit et se réessaie', (tester) async {
      await _tvScreen(tester);
      await tester.pumpWidget(
        _wrap(
          const TvUpdateOverlay(),
          update: const AppUpdateState(
            status: UpdateStatus.error,
            message: 'Échec du téléchargement : connectionTimeout',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mise à jour impossible'), findsOneWidget);
      expect(
        find.text('Échec du téléchargement : connectionTimeout'),
        findsOneWidget,
      );
      expect(find.text('Réessayer'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('la bibliothèque, au complet', () {
    testWidgets('quatre familles, dont les genres et les playlists', (
      tester,
    ) async {
      await _tvScreen(tester);
      await tester.pumpWidget(_wrap(const TvShell(initialTab: TvTab.library)));
      await tester.pumpAndSettle();

      for (final label in ['Albums', 'Artistes', 'Genres', 'Playlists']) {
        expect(find.widgetWithText(TvPill, label), findsOneWidget);
      }

      await tester.tap(find.widgetWithText(TvPill, 'Genres'));
      await tester.pumpAndSettle();
      expect(find.text('Punk'), findsOneWidget);

      await tester.tap(find.widgetWithText(TvPill, 'Playlists'));
      await tester.pumpAndSettle();
      expect(find.text('Road trip'), findsOneWidget);
      expect(find.text('40 titres'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('les paroles sur la télé', () {
    const lrc = '''
[00:00.00] Première ligne
[00:05.00] Deuxième ligne
[00:10.00] Troisième ligne
[00:15.00] Quatrième ligne
[00:20.00] Cinquième ligne
''';

    Widget player({String? lyrics, Duration at = Duration.zero}) => _wrap(
      const TvCanvas(child: TvNowPlayingScreen()),
      item: const MediaItem(
        id: '1',
        title: 'Ruby Soho',
        artist: 'Rancid',
        duration: Duration(seconds: 158),
        extras: {'filePath': 'a.mp3', 'songId': 1},
      ),
      position: at,
      lyrics: lyrics,
    );

    testWidgets('le bouton Paroles ouvre le panneau', (tester) async {
      await _tvScreen(tester);
      await tester.pumpWidget(player(lyrics: lrc));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TvPill, 'Paroles'));
      await tester.pumpAndSettle();
      expect(find.text('Deuxième ligne'), findsOneWidget);
    });

    testWidgets('la ligne en cours suit la lecture, en surbrillance', (
      tester,
    ) async {
      await _tvScreen(tester);
      // Douze secondes de lecture : on en est à la troisième ligne.
      await tester.pumpWidget(
        player(lyrics: lrc, at: const Duration(seconds: 12)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TvPill, 'Paroles'));
      await tester.pumpAndSettle();

      final scheme = gullifyThemeFor(
        GullifyAccent.indigo,
        dark: true,
      ).colorScheme;
      final current = tester.widget<Text>(find.text('Troisième ligne'));
      final other = tester.widget<Text>(find.text('Première ligne'));
      expect(
        current.style?.color,
        scheme.primary,
        reason: 'la phrase en cours doit ressortir',
      );
      expect(current.style?.fontWeight, FontWeight.w700);
      expect(other.style?.color, isNot(scheme.primary));
      // …et elle est écrite plus grand que les autres.
      expect(current.style!.fontSize!, greaterThan(other.style!.fontSize!));
    });

    testWidgets('sans paroles, le panneau le dit', (tester) async {
      await _tvScreen(tester);
      await tester.pumpWidget(player());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TvPill, 'Paroles'));
      await tester.pumpAndSettle();
      expect(find.text('Pas de paroles pour ce titre'), findsOneWidget);
    });

    testWidgets('le lecteur propose les favoris, et dit l\'état', (
      tester,
    ) async {
      await _tvScreen(tester);
      await tester.pumpWidget(player());
      await tester.pumpAndSettle();
      // Le libellé annonce l'état AVANT l'appui : un cœur plein veut dire
      // « déjà dans tes favoris », pas « appuie pour l'y mettre ».
      expect(
        find.widgetWithText(TvPill, 'Ajouter aux favoris'),
        findsOneWidget,
      );
    });

    testWidgets('une radio n\'a ni favori ni paroles', (tester) async {
      await _tvScreen(tester);
      await tester.pumpWidget(
        _wrap(
          const TvCanvas(child: TvNowPlayingScreen()),
          item: const MediaItem(id: 'r', title: 'CISM', artist: 'Radio'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TvPill, 'Paroles'), findsNothing);
      expect(find.widgetWithText(TvPill, 'Ajouter aux favoris'), findsNothing);
    });
  });

  group('jouer seul sur la télé', () {
    testWidgets('l\'onglet Jeux propose les cinq jeux et le multijoueur', (
      tester,
    ) async {
      await _tvScreen(tester);
      await tester.pumpWidget(_wrap(const TvShell(initialTab: TvTab.games)));
      await tester.pumpAndSettle();

      expect(find.text('Jouer à plusieurs'), findsOneWidget);
      for (final game in kGames) {
        expect(
          find.text(game.name),
          findsOneWidget,
          reason: '${game.name} manque au catalogue',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('le blind test se joue et se répond à la croix', (
      tester,
    ) async {
      await _tvScreen(tester);
      await tester.pumpWidget(
        _wrap(const TvCanvas(child: TvSoloGameScreen(gameId: 'blind'))),
      );
      await _settleGame(tester);

      expect(find.text('Quel est ce titre ?'), findsOneWidget);
      expect(find.text('1/10'), findsOneWidget);
      // Quatre propositions, toutes visables.
      expect(find.byType(TvFocusable), findsAtLeast(4));
      expect(tester.takeException(), isNull);
    });

    testWidgets('le duel présente deux albums datés', (tester) async {
      await _tvScreen(tester);
      await tester.pumpWidget(
        _wrap(const TvCanvas(child: TvSoloGameScreen(gameId: 'duel'))),
      );
      await _settleGame(tester);
      expect(find.text('Lequel est le plus ancien ?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('le chrono ouvre sa frise avec ses trous', (tester) async {
      await _tvScreen(tester);
      await tester.pumpWidget(
        _wrap(const TvCanvas(child: TvSoloGameScreen(gameId: 'chrono'))),
      );
      await _settleGame(tester);
      expect(find.text('Où se place ce titre ?'), findsOneWidget);
      // Une carte de départ, donc deux trous : avant et après.
      expect(find.byIcon(Icons.add_rounded), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('la pochette mystère démarre floutée', (tester) async {
      await _tvScreen(tester);
      await tester.pumpWidget(
        _wrap(const TvCanvas(child: TvSoloGameScreen(gameId: 'cover'))),
      );
      await _settleGame(tester);
      expect(find.text('Quel est cet album ?'), findsOneWidget);
      expect(find.byType(ImageFiltered), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un jeu inconnu ne casse rien', (tester) async {
      await _tvScreen(tester);
      await tester.pumpWidget(
        _wrap(const TvCanvas(child: TvSoloGameScreen(gameId: 'pouet'))),
      );
      await _settleGame(tester);
      expect(find.text('Jeu inconnu'), findsOneWidget);
    });
  });

  group('les jeux à plusieurs, la télé en hôte', () {
    testWidgets('le salon montre le code et le lien', (tester) async {
      await _tvScreen(tester);
      await tester.pumpWidget(
        _wrap(
          const TvPartyPage(),
          party: PartySession(
            code: 'K7M2',
            token: 't',
            shareUrl: 'https://gullify.app/j/K7M2',
            state: _party(_partyJson(status: 'lobby', phase: 'lobby')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('K7M2'), findsOneWidget);
      expect(find.text('gullify.app/j/K7M2'), findsOneWidget);
      expect(find.text('Léa'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('en manche, la bonne réponse reste cachée', (tester) async {
      await _tvScreen(tester);
      await tester.pumpWidget(
        _wrap(
          const TvPartyPage(),
          party: PartySession(
            code: 'K7M2',
            token: 't',
            state: _party(
              _partyJson(
                status: 'playing',
                phase: 'guessing',
                round: {
                  'i': 2,
                  'kind': 'blind',
                  'myAnswer': null,
                  'options': [
                    {'id': '11', 'title': 'Ruby Soho', 'subtitle': 'Rancid'},
                    {'id': '12', 'title': 'Time Bomb', 'subtitle': 'Rancid'},
                    {'id': '13', 'title': 'Sac à main', 'subtitle': 'Cowboys'},
                    {'id': '14', 'title': 'Pet sauce', 'subtitle': 'Subb'},
                  ],
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Quel est ce titre ?'), findsOneWidget);
      expect(find.text('Manche 3 sur 10'), findsOneWidget);
      // Le tableau d'affichage, et rien de plus : personne ne répond ici.
      expect(find.text('1 sur 2 ont répondu'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('à la fin, le classement', (tester) async {
      await _tvScreen(tester);
      await tester.pumpWidget(
        _wrap(
          const TvPartyPage(),
          party: PartySession(
            code: 'K7M2',
            token: 't',
            state: _party(_partyJson(status: 'finished', phase: 'finished')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Léa gagne !'), findsOneWidget);
      expect(find.text('210 points'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
