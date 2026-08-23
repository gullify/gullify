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
import 'package:gullify/api/library_repository.dart';
import 'package:gullify/api/party_repository.dart';
import 'package:gullify/api/radio_repository.dart';
import 'package:gullify/models/album.dart';
import 'package:gullify/models/artist.dart';
import 'package:gullify/models/song.dart';
import 'package:gullify/screens/tv/tv_album_screen.dart';
import 'package:gullify/screens/tv/tv_kit.dart';
import 'package:gullify/screens/tv/tv_now_playing_screen.dart';
import 'package:gullify/screens/tv/tv_shell.dart';
import 'package:gullify/screens/tv/tv_update.dart';
import 'package:gullify/state/app_update.dart';
import 'package:gullify/state/favorites.dart';
import 'package:gullify/state/library.dart';
import 'package:gullify/state/party.dart';
import 'package:gullify/state/player.dart';
import 'package:gullify/state/radio.dart';
import 'package:gullify/state/tv.dart';
import 'package:gullify/theme.dart';

const _songs = [
  Song(id: 1, title: 'Ruby Soho', filePath: 'a.mp3', duration: 158,
      artistName: 'Rancid', albumName: 'Wolves', trackNumber: 1),
  Song(id: 2, title: 'Time Bomb', filePath: 'b.mp3', duration: 146,
      artistName: 'Rancid', albumName: 'Wolves', trackNumber: 2),
  Song(id: 3, title: 'Drain the Blood', filePath: 'c.mp3', duration: 187,
      artistName: 'The Distillers', albumName: 'Coral Fang', trackNumber: 3),
];

const _wolves =
    Album(id: 1, name: 'Wolves', year: 1995, artistId: 1, artistName: 'Rancid');

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
  RadioStation(id: 'r1', name: 'CISM', streamUrl: 'http://x/1', genres: ['Indé']),
  RadioStation(id: 'r2', name: 'CKOI', streamUrl: 'http://x/2'),
];

class _FakePlayerActions extends Fake implements PlayerActions {}

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
      'id': 1, 'name': 'Salon', 'isHost': true, 'score': 130, 'lives': 3,
      'answered': true, 'correct': null, 'gained': null, 'timeline': null,
    },
    {
      'id': 2, 'name': 'Léa', 'isHost': false, 'score': 210, 'lives': 2,
      'answered': false, 'correct': null, 'gained': null, 'timeline': null,
    },
  ],
  'round': round,
};

PartyState _party(Map<String, dynamic> json) =>
    PartyState.fromJson(json, (u) => u);

Widget _wrap(
  Widget child, {
  MediaItem? item,
  PartySession? party,
  AppUpdateState? update,
  bool tv = true,
}) => ProviderScope(
  overrides: [
    if (update != null)
      appUpdateProvider.overrideWith(() => _FixedUpdate(update)),
    tvDetectedProvider.overrideWithValue(tv),
    tvForceInitialProvider.overrideWithValue(TvForce.auto),
    playerActionsProvider.overrideWithValue(_FakePlayerActions()),
    currentMediaItemProvider.overrideWith((ref) => Stream<MediaItem?>.value(item)),
    playbackStateProvider
        .overrideWith((ref) => Stream.value(PlaybackState(playing: item != null))),
    positionProvider
        .overrideWith((ref) => Stream.value(const Duration(seconds: 61))),
    queueProvider.overrideWith(
      (ref) => Stream.value(item == null ? const <MediaItem>[] : [item]),
    ),
    recentAlbumsProvider.overrideWith((ref) async => _albums),
    albumsProvider.overrideWith((ref) async => _albums),
    popularSongsProvider.overrideWith((ref) async => _songs),
    artistsProvider.overrideWith((ref) async => _artists),
    allFavoritesProvider.overrideWith((ref) async => _songs),
    radioStationsProvider.overrideWith((ref) async => _stations),
    searchResultsProvider.overrideWith((ref) async => const SearchResults()),
    albumDetailProvider(1).overrideWith(
      (ref) async => const AlbumDetail(album: _wolves, songs: _songs),
    ),
    if (party != null)
      partyProvider.overrideWith(() => _FixedParty(party)),
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

  group('ce qui bloquait sur la vraie télé', () {
    testWidgets('la croix sort d\'un champ de saisie', (tester) async {
      await _tvScreen(tester);
      final field = FocusNode();
      final below = FocusNode();
      addTearDown(field.dispose);
      addTearDown(below.dispose);
      await tester.pumpWidget(
        _wrap(
          Scaffold(
            body: Column(
              children: [
                TvFieldEscape(
                  child: TextField(focusNode: field, autofocus: true),
                ),
                TvPill(
                  label: 'Se connecter',
                  focusNode: below,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(field.hasPrimaryFocus, isTrue);
      // Sans l'échappement, la flèche du bas déplacerait le curseur dans le
      // texte et le focus ne quitterait jamais le champ.
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(below.hasPrimaryFocus, isTrue, reason: 'le focus doit sortir du champ');
    });

    testWidgets('un champ non-TV garde son comportement', (tester) async {
      await _tvScreen(tester);
      final field = FocusNode();
      addTearDown(field.dispose);
      await tester.pumpWidget(
        _wrap(
          Scaffold(
            body: Column(
              children: [
                TvFieldEscape(
                  enabled: false,
                  child: TextField(focusNode: field, autofocus: true),
                ),
                TvPill(label: 'Se connecter', onPressed: () {}),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(field.hasPrimaryFocus, isTrue, reason: 'sur téléphone, rien ne change');
    });

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
            currentMediaItemProvider
                .overrideWith((ref) => Stream<MediaItem?>.value(null)),
            playbackStateProvider
                .overrideWith((ref) => Stream.value(PlaybackState())),
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

  group('les jeux à plusieurs, la télé en hôte', () {
    testWidgets('le salon montre le code et le lien', (tester) async {
      await _tvScreen(tester);
      await tester.pumpWidget(
        _wrap(
          TvShell(initialTab: TvTab.games),
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
          TvShell(initialTab: TvTab.games),
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
          TvShell(initialTab: TvTab.games),
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
