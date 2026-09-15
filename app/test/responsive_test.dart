// La même app à toutes les tailles, qui se réorganise — comme YouTube Music
// entre son app mobile et son site, dont on s'inspire sans le copier.
//
// Au téléphone rien ne change : dock en bas, mini-lecteur au-dessus. Sur
// tablette, la navigation passe sur le côté en rail ; sur grand écran, en
// barre latérale complète avec les playlists. Dans les deux cas le contenu
// prend toute la largeur, la lecture passe dans une barre en bas de la
// fenêtre, et les lignes de titres étalent l'interprète et l'album en
// colonnes.
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gullify/api/playlist_repository.dart';
import 'package:gullify/models/song.dart';
import 'package:gullify/screens/now_playing_screen.dart';
import 'package:gullify/screens/shell_screen.dart';
import 'package:gullify/state/favorites.dart';
import 'package:gullify/state/player.dart';
import 'package:gullify/state/playlists.dart';
import 'package:gullify/theme.dart';
import 'package:gullify/widgets/adaptive_layout.dart';
import 'package:gullify/widgets/artwork.dart';
import 'package:gullify/widgets/chords_sheet.dart';
import 'package:gullify/widgets/detail_hero.dart';
import 'package:gullify/widgets/mini_player.dart';
import 'package:gullify/widgets/glass_box.dart';
import 'package:gullify/widgets/player_bar.dart';
import 'package:gullify/widgets/queue_list.dart';
import 'package:gullify/widgets/song_tile.dart';

const _telephone = Size(412, 892);
const _telephoneCouche = Size(892, 412);
const _tablette = Size(1024, 768);
const _pc = Size(1440, 900);
const _grandEcran = Size(1920, 1080);

const _titre = MediaItem(
  id: '1',
  title: 'Ruby Soho',
  artist: 'Rancid',
  duration: Duration(seconds: 158),
  extras: {'songId': 1},
);

const _chanson = Song(
  id: 1,
  title: 'Ruby Soho',
  filePath: 'a.mp3',
  duration: 158,
  artistName: 'Rancid',
  albumName: 'And Out Come the Wolves',
);

class _FakeActions extends Fake implements PlayerActions {}

class _NoFavorites extends FavoriteIds {
  @override
  Future<Set<int>> build() async => <int>{};
}

Future<void> _taille(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _app(
  Widget child, {
  MediaItem? item,
  List<MediaItem> queue = const [],
  TargetPlatform? platform,
}) => ProviderScope(
  overrides: [
    queueProvider.overrideWith((ref) => Stream.value(queue)),
    currentMediaItemProvider.overrideWith((ref) => Stream.value(item)),
    playbackStateProvider.overrideWith(
      (ref) => Stream.value(PlaybackState(playing: item != null)),
    ),
    positionProvider.overrideWith(
      (ref) => Stream.value(const Duration(seconds: 42)),
    ),
    playerActionsProvider.overrideWithValue(_FakeActions()),
    favoriteIdsProvider.overrideWith(_NoFavorites.new),
    playlistsProvider.overrideWith(
      (ref) async => const [
        Playlist(id: 7, name: 'Route de nuit', songCount: 18),
        Playlist(id: 8, name: 'Matins calmes', songCount: 31),
      ],
    ),
  ],
  child: MaterialApp(
    theme: gullifyThemeFor(
      GullifyAccent.indigo,
      dark: false,
    ).copyWith(platform: platform),
    home: child,
  ),
);

void main() {
  group('dock, rail ou barre latérale', () {
    NavLayout disposition(
      Size window, {
      bool tv = false,
      bool connecte = true,
    }) => navLayoutFor(window: window, tv: tv, authenticated: connecte);

    test('le téléphone garde son dock, même couché', () {
      expect(disposition(_telephone), NavLayout.dock);
      expect(
        disposition(_telephoneCouche),
        NavLayout.dock,
        reason:
            'assez large, mais sept destinations empilées n\'y tiennent '
            'pas en hauteur',
      );
    });

    test('la tablette passe au rail, le grand écran à la barre latérale', () {
      expect(disposition(_tablette), NavLayout.rail);
      expect(disposition(_pc), NavLayout.sidebar);
      expect(disposition(_grandEcran), NavLayout.sidebar);
    });

    test('ni la télé, ni l\'écran de connexion', () {
      expect(disposition(_grandEcran, tv: true), NavLayout.dock);
      expect(disposition(_grandEcran, connecte: false), NavLayout.dock);
    });
  });

  group('HubDock', () {
    testWidgets('sans rail, il porte la navigation', (tester) async {
      await _taille(tester, _pc);
      await tester.pumpWidget(
        _app(
          Scaffold(
            bottomNavigationBar: HubDock(currentIndex: 0, onSelect: (_) {}),
          ),
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    });

    testWidgets('avec le rail, il s\'efface — jamais les deux', (tester) async {
      await _taille(tester, _pc);
      await tester.pumpWidget(
        _app(
          SideNavigationScope(
            visible: true,
            child: Scaffold(
              bottomNavigationBar: HubDock(currentIndex: 0, onSelect: (_) {}),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byIcon(Icons.home_rounded),
        findsNothing,
        reason:
            'navigation sur le côté, lecture en bas de la fenêtre : le '
            'dock n\'a plus rien à porter',
      );
    });
  });

  group('HubRail', () {
    testWidgets('porte les sept destinations, nommées', (tester) async {
      await _taille(tester, _pc);
      final choisis = <int>[];
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Row(
              children: [
                HubRail(currentIndex: 1, onSelect: choisis.add),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // Au-dessus du navigateur il n'y a pas d'infobulle : chaque destination
      // porte son nom.
      for (final nom in [
        'Bibliothèque',
        'Recherche',
        'Radio',
        'Favoris',
        'Jeux',
        'Vidéos',
      ]) {
        expect(find.text(nom), findsOneWidget, reason: '$nom manque au rail');
      }

      await tester.tap(find.text('Radio'));
      await tester.tap(find.byIcon(Icons.home_rounded));
      expect(choisis, [3, 0]);
    });

    testWidgets('dans l\'ordre des onglets', (tester) async {
      await _taille(tester, _pc);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Row(children: [HubRail(currentIndex: 0, onSelect: (_) {})]),
          ),
        ),
      );
      await tester.pump();
      double y(String t) => tester.getTopLeft(find.text(t)).dy;
      expect(y('Bibliothèque'), lessThan(y('Recherche')));
      expect(y('Recherche'), lessThan(y('Radio')));
      expect(y('Favoris'), lessThan(y('Jeux')));
      expect(y('Jeux'), lessThan(y('Vidéos')));
    });
  });

  group('DetailDock.indexForPath', () {
    test('un onglet s\'allume, une fiche n\'allume rien', () {
      expect(DetailDock.indexForPath('/'), 0);
      expect(DetailDock.indexForPath('/library'), 1);
      expect(DetailDock.indexForPath('/videos'), 6);
      expect(
        DetailDock.indexForPath('/album/12'),
        -1,
        reason: 'une page de détail n\'appartient à aucun onglet',
      );
      expect(
        DetailDock.indexForPath('/radiologie'),
        -1,
        reason: 'un préfixe de nom n\'est pas un sous-chemin',
      );
    });
  });

  group('le dock du téléphone couché', () {
    // En paysage, le téléphone réserve une marge du côté de sa caméra. Le
    // mini-lecteur l'ignorait et débordait sous l'encoche, 50 px plus large
    // que le menu et la page.
    testWidgets('le mini-lecteur respecte l\'encoche, comme le menu', (
      tester,
    ) async {
      await _taille(tester, _telephoneCouche);
      tester.view.padding = const FakeViewPadding(left: 48);
      tester.view.viewPadding = const FakeViewPadding(left: 48);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: const SafeArea(child: SizedBox.expand(key: Key('page'))),
            bottomNavigationBar: HubDock(currentIndex: 0, onSelect: (_) {}),
          ),
          item: _titre,
        ),
      );
      await tester.pump();
      await tester.pump();

      final verre = find.byType(GlassBox);
      final mini = tester.getRect(
        find.descendant(of: find.byType(MiniPlayer), matching: verre).first,
      );
      final menu = tester.getRect(verre.last);
      final page = tester.getRect(find.byKey(const Key('page')));

      expect(
        mini.left,
        greaterThanOrEqualTo(page.left),
        reason: 'pas sous l\'encoche',
      );
      expect(
        (mini.left - menu.left).abs(),
        lessThanOrEqualTo(2),
        reason: 'aligné sur le menu, à l\'écart près qu\'on a en portrait',
      );
    });
  });

  group('HubSidebar', () {
    testWidgets('les destinations avec leur nom, et les playlists', (
      tester,
    ) async {
      await _taille(tester, _grandEcran);
      final chemins = <String>[];
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Row(
              children: [
                HubSidebar(currentPath: '/library', onNavigate: chemins.add),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      for (final nom in ['Accueil', 'Bibliothèque', 'Vidéos', 'Paramètres']) {
        expect(find.text(nom), findsOneWidget, reason: '$nom manque');
      }
      expect(find.text('Route de nuit'), findsOneWidget);
      expect(find.text('18'), findsOneWidget, reason: 'le nombre de titres');

      await tester.tap(find.text('Radio'));
      await tester.tap(find.text('Route de nuit'));
      await tester.tap(find.text('Paramètres'));
      expect(chemins, [
        '/radio',
        '/playlist/7?name=Route+de+nuit',
        '/settings',
      ]);
    });
  });

  group('PlayerBar', () {
    // La barre vit au-dessus du navigateur, là où il n'y a pas d'`Overlay`.
    // Un `Slider` y construisait un `OverlayPortal` en erreur — en production,
    // un rectangle gris à la place de la progression. Poser la barre dans une
    // page ordinaire, comme le faisaient les autres tests, cachait le défaut.
    testWidgets('au-dessus du navigateur, sans Overlay, rien ne casse', (
      tester,
    ) async {
      await _taille(tester, _grandEcran);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentMediaItemProvider.overrideWith(
              (ref) => Stream.value(_titre),
            ),
            playbackStateProvider.overrideWith(
              (ref) => Stream.value(PlaybackState(playing: true)),
            ),
            positionProvider.overrideWith(
              (ref) => Stream.value(const Duration(seconds: 42)),
            ),
            playerActionsProvider.overrideWithValue(_FakeActions()),
            favoriteIdsProvider.overrideWith(_NoFavorites.new),
          ],
          child: MaterialApp(
            theme: gullifyThemeFor(GullifyAccent.indigo, dark: false),
            // Comme main.dart : la barre à côté du navigateur, pas dedans.
            builder: (context, child) => Column(
              children: [
                Expanded(child: child!),
                PlayerBar(onToggleExpanded: () {}),
              ],
            ),
            home: const Scaffold(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Ruby Soho'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Progression dans le titre'),
        findsOneWidget,
      );
    });

    testWidgets('rien en lecture : pas de barre vide', (tester) async {
      await _taille(tester, _grandEcran);
      await tester.pumpWidget(
        _app(Scaffold(body: PlayerBar(onToggleExpanded: () {}))),
      );
      await tester.pump();
      expect(find.bySemanticsLabel('Progression dans le titre'), findsNothing);
      expect(tester.getSize(find.byType(PlayerBar)).height, 0);
    });

    testWidgets('le titre, les commandes et la progression', (tester) async {
      await _taille(tester, _grandEcran);
      var ouvert = 0;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: PlayerBar(onToggleExpanded: () => ouvert++),
            ),
          ),
          item: _titre,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Ruby Soho'), findsOneWidget);
      expect(find.text('Rancid'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Progression dans le titre'),
        findsOneWidget,
        reason: 'on s\'y place',
      );
      expect(find.text('0:42'), findsOneWidget);
      expect(find.text('2:38'), findsOneWidget);

      await tester.tap(find.text('Ruby Soho'));
      expect(ouvert, 1, reason: 'le titre ouvre le lecteur complet');
    });

    testWidgets('une radio en direct le dit, sans barre', (tester) async {
      await _taille(tester, _grandEcran);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: PlayerBar(onToggleExpanded: () {}),
            ),
          ),
          item: const MediaItem(id: 'r', title: 'CISM', artist: 'Radio'),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('EN DIRECT'), findsOneWidget);
      expect(find.bySemanticsLabel('Progression dans le titre'), findsNothing);
    });
  });

  group('SongTile', () {
    Widget ligne(SongTile tile) =>
        _app(Scaffold(body: ListView(children: [tile])));

    testWidgets('au téléphone, l\'interprète sous le titre', (tester) async {
      await _taille(tester, _telephone);
      await tester.pumpWidget(ligne(SongTile(song: _chanson, onTap: () {})));
      await tester.pump();
      final titre = tester.getTopLeft(find.text('Ruby Soho'));
      final interprete = tester.getTopLeft(find.text('Rancid'));
      expect(interprete.dy, greaterThan(titre.dy), reason: 'en dessous');
      expect(find.text('And Out Come the Wolves'), findsNothing);
    });

    testWidgets('sur grand écran, interprète et album en colonnes', (
      tester,
    ) async {
      await _taille(tester, _grandEcran);
      await tester.pumpWidget(ligne(SongTile(song: _chanson, onTap: () {})));
      await tester.pump();
      final titre = tester.getTopLeft(find.text('Ruby Soho'));
      final interprete = tester.getTopLeft(find.text('Rancid'));
      final album = tester.getTopLeft(find.text('And Out Come the Wolves'));
      expect(interprete.dx, greaterThan(titre.dx + 300), reason: 'sa colonne');
      expect(album.dx, greaterThan(interprete.dx), reason: 'puis l\'album');
      expect(
        (interprete.dy - titre.dy).abs(),
        lessThan(20),
        reason: 'sur la même ligne que le titre',
      );
    });

    testWidgets('la recherche : « interprète · album » au téléphone, '
        'sans doublon sur grand écran', (tester) async {
      await _taille(tester, _telephone);
      await tester.pumpWidget(
        ligne(SongTile(song: _chanson, onTap: () {}, albumInSubtitle: true)),
      );
      await tester.pump();
      expect(find.text('Rancid · And Out Come the Wolves'), findsOneWidget);

      await _taille(tester, _grandEcran);
      await tester.pumpWidget(
        ligne(SongTile(song: _chanson, onTap: () {}, albumInSubtitle: true)),
      );
      await tester.pump();
      expect(
        find.text('And Out Come the Wolves'),
        findsOneWidget,
        reason: 'l\'album une seule fois, dans sa colonne',
      );
      expect(find.text('Rancid · And Out Come the Wolves'), findsNothing);
    });

    testWidgets('un sous-titre imposé garde la main : pas de colonne en plus', (
      tester,
    ) async {
      await _taille(tester, _grandEcran);
      await tester.pumpWidget(
        ligne(
          SongTile(
            song: _chanson,
            onTap: () {},
            subtitle: 'Rancid · And Out Come the Wolves',
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Rancid · And Out Come the Wolves'), findsOneWidget);
      expect(
        find.text('And Out Come the Wolves'),
        findsNothing,
        reason:
            'l\'appelant a déjà mis l\'album dans son sous-titre : une '
            'colonne le montrerait deux fois',
      );
    });

    testWidgets('la page d\'un album ne répète pas l\'album', (tester) async {
      await _taille(tester, _grandEcran);
      await tester.pumpWidget(
        ligne(
          SongTile(
            song: _chanson,
            onTap: () {},
            showArtist: false,
            showAlbum: false,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Rancid'), findsNothing);
      expect(find.text('And Out Come the Wolves'), findsNothing);
    });
  });

  group('le lecteur ouvert sur grand écran', () {
    const suivant = MediaItem(
      id: '2',
      title: 'Time Bomb',
      artist: 'Rancid',
      duration: Duration(seconds: 145),
      extras: {'songId': 2},
    );

    testWidgets('la barre bascule entre ouvrir et réduire', (tester) async {
      await _taille(tester, _grandEcran);
      Future<void> barre({required bool ouvert}) async {
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: PlayerBar(expanded: ouvert, onToggleExpanded: () {}),
              ),
            ),
            item: _titre,
          ),
        );
        await tester.pump();
        await tester.pump();
      }

      await barre(ouvert: false);
      expect(find.bySemanticsLabel('Ouvrir le lecteur'), findsOneWidget);
      await barre(ouvert: true);
      expect(find.bySemanticsLabel('Réduire le lecteur'), findsOneWidget);
    });

    // Comme le vrai lecteur : il s'ouvre par-dessus une page, une fois le
    // titre en cours connu. Construit avant, il se refermerait aussitôt.
    Future<void> ouvrirLecteur(
      WidgetTester tester, {
      required bool cote,
      required List<MediaItem> file,
    }) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const Scaffold()),
          GoRoute(
            path: '/now-playing',
            builder: (_, _) => const NowPlayingScreen(),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentMediaItemProvider.overrideWith(
              (ref) => Stream.value(_titre),
            ),
            playbackStateProvider.overrideWith(
              (ref) => Stream.value(PlaybackState(playing: true)),
            ),
            positionProvider.overrideWith(
              (ref) => Stream.value(const Duration(seconds: 42)),
            ),
            queueProvider.overrideWith((ref) => Stream.value(file)),
            playerActionsProvider.overrideWithValue(_FakeActions()),
            favoriteIdsProvider.overrideWith(_NoFavorites.new),
          ],
          child: Consumer(
            builder: (context, ref, child) {
              ref.watch(currentMediaItemProvider);
              return child!;
            },
            child: SideNavigationScope(
              visible: cote,
              child: MaterialApp.router(
                theme: gullifyThemeFor(GullifyAccent.indigo, dark: false),
                routerConfig: router,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      router.push('/now-playing');
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('la pochette à gauche, la file et les paroles à droite — '
        'sans les commandes, qui restent dans la barre', (tester) async {
      await _taille(tester, _grandEcran);
      await ouvrirLecteur(tester, cote: true, file: const [_titre, suivant]);

      expect(find.text('À suivre'), findsOneWidget);
      expect(find.text('Paroles'), findsOneWidget);
      expect(
        find.text('Time Bomb'),
        findsOneWidget,
        reason: 'la file est visible sans rien ouvrir',
      );
      expect(
        find.byIcon(Icons.pause_circle_filled),
        findsNothing,
        reason: 'lecture et pause sont dans la barre du bas, pas en double',
      );
      expect(
        tester.getCenter(find.text('Time Bomb')).dx,
        greaterThan(960),
        reason: 'la liste est à droite',
      );
    });

    testWidgets('au téléphone, le lecteur garde ses commandes', (tester) async {
      await _taille(tester, _telephone);
      await ouvrirLecteur(tester, cote: false, file: const [_titre]);
      expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);
      expect(find.text('À suivre'), findsNothing);
    });
  });

  group('QueueList', () {
    const file = [
      MediaItem(id: 'a', title: 'Un'),
      MediaItem(id: 'b', title: 'Deux'),
      MediaItem(id: 'c', title: 'Trois'),
    ];

    testWidgets('sur ordinateur, une poignée par titre — pas deux', (
      tester,
    ) async {
      await _taille(tester, _grandEcran);
      await tester.pumpWidget(
        _app(
          const Scaffold(body: QueueList()),
          queue: file,
          platform: TargetPlatform.windows,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.drag_handle), findsNWidgets(file.length));
    });
  });

  group('la feuille des accords', () {
    Future<double> largeur(WidgetTester tester, Size taille) async {
      await _taille(tester, taille);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showChordsSheet(context, null),
                child: const Text('accords'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('accords'));
      await tester.pumpAndSettle();
      // La surface visible, et non le widget BottomSheet : Flutter y pose le
      // plafond de largeur À L'INTÉRIEUR, dans un Align pleine largeur. Mesurer
      // l'enveloppe donnait toujours toute la largeur, plafond ou pas.
      return tester
          .getSize(
            find
                .descendant(
                  of: find.byType(BottomSheet),
                  matching: find.byType(Material),
                )
                .first,
          )
          .width;
    }

    testWidgets('sur grand écran, toute la largeur — pas une bande au milieu', (
      tester,
    ) async {
      expect(await largeur(tester, _grandEcran), _grandEcran.width);
    });

    testWidgets('au téléphone, comme avant', (tester) async {
      expect(await largeur(tester, _telephone), _telephone.width);
    });
  });

  group('DetailHero', () {
    Widget hero() => _app(
      Scaffold(
        body: DetailHero(
          imageUrl: null,
          onMenu: () {},
          info: const Text('Titre'),
        ),
      ),
    );

    testWidgets('au téléphone, l\'image plein cadre — pas de vignette', (
      tester,
    ) async {
      await _taille(tester, _telephone);
      await tester.pumpWidget(hero());
      expect(
        find.byWidgetPredicate((w) => w is Artwork && w.size == 200),
        findsNothing,
      );
      expect(tester.getSize(find.byType(DetailHero)).height, 440);
    });

    testWidgets('sur grand écran, la pochette revient à côté du titre', (
      tester,
    ) async {
      await _taille(tester, _pc);
      await tester.pumpWidget(hero());
      final vignette = find.byWidgetPredicate(
        (w) => w is Artwork && w.size == 200,
      );
      expect(vignette, findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Titre')).dx,
        greaterThan(tester.getTopRight(vignette).dx),
        reason: 'le titre est à droite de la pochette',
      );
      expect(tester.getSize(find.byType(DetailHero)).height, 320);
    });
  });

  group('PrimaryActionSlot', () {
    Widget rangee() => _app(
      const Scaffold(
        body: Row(
          children: [
            PrimaryActionSlot(child: SizedBox(height: 50, key: Key('b'))),
            SizedBox(width: 50),
          ],
        ),
      ),
    );

    testWidgets('au téléphone, toute la largeur', (tester) async {
      await _taille(tester, _telephone);
      await tester.pumpWidget(rangee());
      expect(tester.getSize(find.byKey(const Key('b'))).width, 412 - 50);
    });

    testWidgets('sur grand écran, une largeur de bouton', (tester) async {
      await _taille(tester, _pc);
      await tester.pumpWidget(rangee());
      expect(tester.getSize(find.byKey(const Key('b'))).width, 300);
    });
  });
}
