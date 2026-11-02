// Pour toi : lecture des réponses de `pour-toi.php` et rendu de la section de
// l'accueil (rayons, artistes d'ailleurs, ancien serveur muet).
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gullify/api/api_client.dart';
import 'package:gullify/api/library_repository.dart';
import 'package:gullify/api/pour_toi_repository.dart';
import 'package:gullify/models/song.dart';
import 'package:gullify/state/pour_toi.dart';
import 'package:gullify/theme.dart';
import 'package:gullify/widgets/pour_toi_section.dart';

/// Un client qui répond ce qu'on lui donne, et note ce qu'on lui demande.
class _FakeClient extends ApiClient {
  _FakeClient(this.reponses) : super(serverUrl: 'https://maison.test');

  final Map<String, dynamic> reponses;
  final demandes = <Map<String, dynamic>>[];

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    demandes.add({...?query});
    return reponses[query?['action']];
  }
}

const _titre = {
  'id': 12,
  'title': 'Tokébakicitte',
  'trackNumber': 3,
  'duration': 201,
  'filePath': 'Jérôme 50/Tokébakicitte.mp3',
  'albumId': 4,
  'albumName': 'Jérôme 50',
  'artworkUrl': 'serve_image.php?album_id=4',
  'artistId': 7,
  'artistName': 'Jérôme 50',
  'raison': 'Du même artiste',
  'origin': 'auto:artiste',
};

PourToiRepository _repo(_FakeClient c) =>
    PourToiRepository(c, LibraryRepository(c));

void main() {
  group('lecture des réponses', () {
    test(
      'la suite garde l\'origine et la raison, pochette en adresse complète',
      () async {
        final c = _FakeClient({
          'suite': {
            'titres': [_titre],
          },
        });
        final recos = await _repo(c).suite(graines: [1, 2], exclus: [1, 2, 3]);
        expect(recos, hasLength(1));
        expect(recos.first.song.title, 'Tokébakicitte');
        expect(recos.first.origin, 'auto:artiste');
        expect(recos.first.raison, 'Du même artiste');
        expect(recos.first.song.artworkUrl, startsWith('https://maison.test/'));
        expect(c.demandes.single['graines'], '1,2');
        expect(c.demandes.single['famille'], 'auto');
      },
    );

    test('l\'accueil envoie le fuseau du téléphone', () async {
      final c = _FakeClient({
        'accueil': {
          'rayons': [
            {
              'id': 5,
              'type': 'mix',
              'titre': 'Mix Punk rock',
              'sousTitre': 'NOFX, Reset et d\'autres',
              'nombre': 40,
              'apercu': ['serve_image.php?album_id=1'],
              'numero': 1,
            },
          ],
          'analyseLe': '2026-11-02 08:40:00',
        },
      });
      final a = await _repo(c).accueil();
      expect(a.rayons.single.titre, 'Mix Punk rock');
      expect(a.rayons.single.apercu.single, startsWith('https://'));
      expect(
        c.demandes.single['decalage'],
        DateTime.now().timeZoneOffset.inMinutes,
      );
    });

    test('un artiste d\'ailleurs dit pourquoi il est là', () {
      const deux = RecoArtiste(nom: 'Sum 41', parce: ['Reset', 'Yellowcard']);
      expect(deux.pourquoi, 'Parce que tu aimes Reset et Yellowcard');
      const ia = RecoArtiste(
        nom: 'X',
        parce: ['Y'],
        phrase: 'Du punk qui sourit.',
      );
      expect(ia.pourquoi, 'Du punk qui sourit.');
      const rien = RecoArtiste(nom: 'Z');
      expect(rien.pourquoi, 'Proche de tes goûts');
    });

    test(
      'une liste Pour toi se lance mélangée, sans artiste deux fois de suite',
      () {
        RecoSong r(int id, String artiste) => RecoSong(
          song: Song(
            id: id,
            title: 't$id',
            filePath: '$id.mp3',
            artistName: artiste,
          ),
        );
        final titres = [
          for (var i = 0; i < 12; i++) r(i, ['A', 'B', 'C'][i % 3]),
        ];
        final ordres = <String>{};
        for (var essai = 0; essai < 20; essai++) {
          final m = melangerPourLancer(titres, hasard: Random(essai));
          expect(
            m.map((x) => x.song.id).toSet(),
            titres.map((x) => x.song.id).toSet(),
          );
          for (var k = 1; k < m.length; k++) {
            expect(m[k].song.artistName, isNot(m[k - 1].song.artistName));
          }
          ordres.add(m.map((x) => x.song.id).join(','));
        }
        // Pas deux trajets pareils.
        expect(ordres.length, greaterThan(15));
        // Le titre touché joue d'abord.
        final touche = titres[7];
        expect(melangerPourLancer(titres, premier: touche).first, touche);
      },
    );

    test('le profil se lit même incomplet', () {
      const p = GoutsProfil({'portrait': 'Ton cœur penche vers le punk.'});
      expect(p.portrait, startsWith('Ton cœur'));
      expect(p.etiquettes, isEmpty);
      expect(p.aventure, 0.35);
      expect(p.heures, isEmpty);
    });
  });

  group('section de l\'accueil', () {
    Future<void> pump(
      WidgetTester tester,
      Future<PourToiAccueil> Function() f,
    ) async {
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [pourToiAccueilProvider.overrideWith((ref) => f())],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(
              body: SingleChildScrollView(child: PourToiSection()),
            ),
          ),
          GoRoute(path: '/gouts', builder: (_, _) => const Text('page goûts')),
          GoRoute(
            path: '/pour-toi/:id',
            builder: (_, s) => Text('rayon ${s.pathParameters['id']}'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: gullifyThemeFor(GullifyAccent.indigo, dark: false),
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('les rayons et les artistes d\'ailleurs', (tester) async {
      await pump(
        tester,
        () async => const PourToiAccueil(
          rayons: [
            Rayon(
              id: 5,
              type: 'mix',
              titre: 'Mix Punk rock',
              sousTitre: 'NOFX et Reset',
              nombre: 40,
              numero: 1,
            ),
            Rayon(
              id: 6,
              type: 'decouvertes',
              titre: 'Découvertes de la semaine',
              nombre: 29,
            ),
            Rayon(
              id: 7,
              type: 'ailleurs',
              titre: 'À découvrir ailleurs',
              artistes: [
                RecoArtiste(nom: 'Sum 41', parce: ['Reset']),
              ],
            ),
          ],
        ),
      );
      expect(find.text('Pour toi'), findsOneWidget);
      expect(find.text('Mix Punk rock'), findsOneWidget);
      expect(find.text('Découvertes de la semaine'), findsOneWidget);
      expect(find.text('Sum 41'), findsOneWidget);
      expect(find.text('Parce que tu aimes Reset'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Lire Mix Punk rock en aléatoire'),
        findsOneWidget,
      );

      await tester.tap(find.text('Mix Punk rock'));
      await tester.pumpAndSettle();
      expect(find.text('rayon 5'), findsOneWidget);
    });

    testWidgets('« Tes goûts » ouvre le portrait', (tester) async {
      await pump(
        tester,
        () async => const PourToiAccueil(
          rayons: [Rayon(id: 5, type: 'mix', titre: 'Mix Ska', nombre: 30)],
        ),
      );
      await tester.tap(find.text('Tes goûts'));
      await tester.pumpAndSettle();
      expect(find.text('page goûts'), findsOneWidget);
    });

    testWidgets('pas encore d\'écoutes : on dit ce qui va venir', (
      tester,
    ) async {
      await pump(tester, () async => const PourToiAccueil(rayons: []));
      expect(
        find.textContaining('tes mix et tes découvertes arrivent ici'),
        findsOneWidget,
      );
    });

    testWidgets('un serveur d\'avant Pour toi : rien du tout', (tester) async {
      await pump(tester, () async => throw ApiException('unknown', '404'));
      expect(find.text('Pour toi'), findsNothing);
    });
  });
}
