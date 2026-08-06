// Gestes du mini-lecteur (idée #66) : vers le haut il ouvre le lecteur
// complet, vers le bas il ferme le lecteur — et la fermeture reste annulable,
// parce qu'un balayage part parfois tout seul.
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gullify/state/player.dart';
import 'package:gullify/widgets/mini_player.dart';

const _item = MediaItem(
  id: 'stream-1',
  title: 'Première chanson',
  artist: 'Artiste Test',
  duration: Duration(seconds: 215),
);

const _closed = (
  queue: [_item],
  index: 0,
  position: Duration(seconds: 42),
);

/// Enregistre ce que le mini-lecteur demande au lecteur, sans lecteur.
class _RecordingActions extends Fake implements PlayerActions {
  int dismissed = 0;
  int skipped = 0;
  ({List<MediaItem> queue, int index, Duration position})? restored;

  @override
  Future<void> next() async => skipped++;

  @override
  Future<void> previous() async => skipped++;

  @override
  Future<({List<MediaItem> queue, int index, Duration position})>
      dismiss() async {
    dismissed++;
    return _closed;
  }

  @override
  Future<void> restoreQueue(
    List<MediaItem> items, {
    int index = 0,
    Duration position = Duration.zero,
  }) async {
    restored = (queue: items, index: index, position: position);
  }
}

Future<_RecordingActions> _pumpMini(WidgetTester tester) async {
  final actions = _RecordingActions();
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(
          body: Center(child: Text('page:accueil')),
          bottomNavigationBar: MiniPlayer(),
        ),
      ),
      GoRoute(
        path: '/now-playing',
        builder: (_, _) => const Scaffold(
          body: Center(child: Text('page:lecteur')),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playerActionsProvider.overrideWithValue(actions),
        currentMediaItemProvider
            .overrideWith((ref) => Stream<MediaItem?>.value(_item)),
        playbackStateProvider
            .overrideWith((ref) => Stream.value(PlaybackState())),
        positionProvider.overrideWith((ref) => Stream.value(Duration.zero)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return actions;
}

/// Un balayage franc : `fling` donne la vitesse que guettent les gestes.
Future<void> _fling(WidgetTester tester, Offset direction) async {
  await tester.fling(find.text('Première chanson'), direction, 1200);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('vers le haut, le lecteur complet s\'ouvre', (tester) async {
    final actions = await _pumpMini(tester);

    await _fling(tester, const Offset(0, -160));

    expect(find.text('page:lecteur'), findsOneWidget);
    expect(actions.dismissed, 0);
  });

  testWidgets('vers le bas, le lecteur se ferme — et ça s\'annule',
      (tester) async {
    final actions = await _pumpMini(tester);

    await _fling(tester, const Offset(0, 160));

    expect(actions.dismissed, 1);
    // On n'a pas quitté la page en cours pour autant.
    expect(find.text('page:accueil'), findsOneWidget);

    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    expect(actions.restored?.queue, [_item]);
    expect(actions.restored?.position, const Duration(seconds: 42));
  });

  testWidgets('le balayage horizontal reste un changement de piste',
      (tester) async {
    final actions = await _pumpMini(tester);

    await _fling(tester, const Offset(-200, 0));

    expect(actions.skipped, 1);
    expect(actions.dismissed, 0);
    expect(find.text('page:accueil'), findsOneWidget);
  });
}
