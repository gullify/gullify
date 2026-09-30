// Les graphiques des statistiques (idée #120). Ce qui se vérifie ici, c'est ce
// qu'un golden ne dit pas : que les graduations tombent sur des chiffres
// ronds, que la queue des genres se replie sur « Autres » au lieu de recycler
// une couleur, et qu'on peut lire n'importe quelle valeur au doigt. Les deux
// rendus de contrôle, eux, montrent le reste.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/stats_repository.dart';
import 'package:gullify/screens/stats_screen.dart';
import 'package:gullify/state/stats.dart';
import 'package:gullify/theme.dart';
import 'package:gullify/widgets/stats_chart.dart';

/// Trente jours d'écoutes, un sommet au milieu et des trous : de quoi voir la
/// courbe monter, redescendre et toucher la ligne de base.
const _daily = [
  3, 5, 2, 0, 6, 9, 4, 7, 11, 8, //
  6, 0, 2, 14, 17, 12, 9, 5, 3, 7,
  8, 10, 6, 4, 0, 2, 9, 13, 11, 6,
];

const _hourly = [
  0, 0, 0, 0, 0, 1, 2, 5, 9, 12, //
  8, 6, 7, 4, 3, 5, 8, 14, 19, 16,
  11, 7, 3, 1,
];

const _weekday = [4, 9, 2, 7, 5, 8, 7];

const _genres = [
  StatsGenre(label: 'Rock', count: 24, color: '#FF6384'),
  StatsGenre(label: 'Électro', count: 18, color: '#36A2EB'),
  StatsGenre(label: 'Hip-hop', count: 14, color: '#FFCE56'),
  StatsGenre(label: 'Jazz', count: 9, color: '#4BC0C0'),
  StatsGenre(label: 'Classique', count: 7, color: '#9966FF'),
  StatsGenre(label: 'Folk', count: 5, color: '#FF9F40'),
  // Au-delà du sixième, la queue n'a plus droit à une teinte : ces trois-là
  // doivent se retrouver sous « Autres » (3 + 2 + 1 = 6).
  StatsGenre(label: 'Reggae', count: 3, color: '#FF6384'),
  StatsGenre(label: 'Metal', count: 2, color: '#C9CBCF'),
  StatsGenre(label: 'Blues', count: 1, color: '#7BC8A4'),
];

ListeningStats _stats({
  List<int> daily = _daily,
  List<StatsGenre> genres = _genres,
}) => ListeningStats(
  general: const StatsGeneral(
    totalPlays: 212,
    totalListenTimeFormatted: '14 h',
    uniqueSongsPlayed: 96,
    completionRate: 78,
    totalSkips: 11,
    avgDurationFormatted: '3 min',
  ),
  topSongs: const [
    StatsTopSong(
      title: 'Première chanson',
      artistName: 'Artiste Test',
      albumId: 1,
      playCount: 21,
      artworkUrl: '',
    ),
  ],
  topArtists: const [
    StatsTopArtist(id: 1, name: 'Artiste Test', playCount: 48, imageUrl: ''),
  ],
  topAlbums: const [],
  dailyPlays: StatsChart(
    labels: [for (var i = 0; i < daily.length; i++) '${i + 1}/09'],
    data: daily,
  ),
  hourly: const StatsChart(
    labels: [
      '0h', '1h', '2h', '3h', '4h', '5h', '6h', '7h', //
      '8h', '9h', '10h', '11h', '12h', '13h', '14h', '15h',
      '16h', '17h', '18h', '19h', '20h', '21h', '22h', '23h',
    ],
    data: _hourly,
  ),
  weekday: const StatsChart(
    labels: ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'],
    data: _weekday,
  ),
  genres: genres,
  recentPlays: const [],
);

Future<void> _pumpStats(
  WidgetTester tester, {
  ListeningStats? stats,
  bool dark = false,
}) async {
  tester.view.physicalSize = const Size(412, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        statsProvider.overrideWith((ref) async => stats ?? _stats()),
      ],
      child: MaterialApp(
        theme: gullifyThemeFor(GullifyAccent.vert, dark: dark),
        home: Builder(
          // Comme main.dart : le dégradé global passe sous les écrans, qui
          // sont transparents. Sans lui, les cartes translucides se
          // peindraient sur du blanc et le rendu de contrôle mentirait.
          builder: (context) => DecoratedBox(
            decoration: BoxDecoration(
              gradient: Theme.of(context)
                  .extension<GullifySurfaces>()
                  ?.background,
            ),
            child: const KeyedSubtree(
              key: Key('stats-root'),
              child: StatsScreen(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  group('niceCeil', () {
    test('les petites séries gardent leur maximum', () {
      expect(niceCeil(0), 1);
      expect(niceCeil(1), 1);
      expect(niceCeil(5), 5);
    });

    test('au-delà, la graduation tombe sur un chiffre rond', () {
      expect(niceCeil(7), 10);
      expect(niceCeil(17), 20);
      expect(niceCeil(37), 50);
      expect(niceCeil(120), 200);
      expect(niceCeil(640), 1000);
    });
  });

  testWidgets('la queue des genres se replie sur « Autres »', (tester) async {
    await _pumpStats(tester);

    expect(find.text('Rock'), findsOneWidget);
    expect(find.text('Folk'), findsOneWidget);
    // Les trois derniers ne s'écrivent plus : ils sont dans la queue.
    expect(find.text('Reggae'), findsNothing);
    expect(find.text('Blues'), findsNothing);
    expect(find.text('Autres'), findsOneWidget);
    // 3 + 2 + 1 sur 83 artistes classés, soit 7 %.
    expect(find.text('6 · 7 %'), findsOneWidget);
    expect(find.text('9 genres'), findsOneWidget);
  });

  testWidgets('sans queue, tous les genres gardent leur nom', (tester) async {
    await _pumpStats(tester, stats: _stats(genres: _genres.take(4).toList()));

    expect(find.text('Jazz'), findsOneWidget);
    expect(find.text('Autres'), findsNothing);
  });

  testWidgets('sans rien de touché, l\'en-tête donne le total', (tester) async {
    await _pumpStats(tester);

    // 4 + 9 + 2 + 7 + 5 + 8 + 7.
    expect(find.text('42 écoutes'), findsOneWidget);
  });

  testWidgets('toucher une barre écrit sa valeur dans l\'en-tête', (
    tester,
  ) async {
    await _pumpStats(tester);

    // Le dernier histogramme est « Par jour » : sept cases après la
    // gouttière des graduations. On touche la première.
    final chart = find.byType(StatsBarChart).last;
    final box = tester.getRect(chart);
    final slot = (box.width - kStatsGutter) / 7;
    await tester.tapAt(
      Offset(box.left + kStatsGutter + slot / 2, box.top + 40),
    );
    await tester.pump();

    expect(find.text('Lun · 4 écoutes'), findsOneWidget);
    expect(find.text('42 écoutes'), findsNothing);

    // Retouchée, la valeur se retire et le total revient.
    await tester.tapAt(
      Offset(box.left + kStatsGutter + slot / 2, box.top + 40),
    );
    await tester.pump();
    expect(find.text('42 écoutes'), findsOneWidget);
  });

  testWidgets('toucher la courbe écrit le jour touché', (tester) async {
    await _pumpStats(tester);

    final chart = find.byType(StatsTrendChart);
    final box = tester.getRect(chart);
    final slot = (box.width - kStatsGutter) / _daily.length;
    // La quatorzième case : le sommet de la série (14 écoutes).
    await tester.tapAt(
      Offset(box.left + kStatsGutter + slot * 13.5, box.top + 40),
    );
    await tester.pump();

    expect(find.text('14/09 · 14 écoutes'), findsOneWidget);
  });

  testWidgets('une série d\'un seul jour ne fait pas tomber la courbe', (
    tester,
  ) async {
    await _pumpStats(tester, stats: _stats(daily: const [3]));

    expect(find.byType(StatsTrendChart), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('les statistiques se rendent en clair', (tester) async {
    await _pumpStats(tester);
    await expectLater(
      find.byKey(const Key('stats-root')),
      matchesGoldenFile('goldens/stats_screen.png'),
    );
  });

  testWidgets('les statistiques se rendent en sombre', (tester) async {
    await _pumpStats(tester, dark: true);
    await expectLater(
      find.byKey(const Key('stats-root')),
      matchesGoldenFile('goldens/stats_screen_dark.png'),
    );
  });
}
