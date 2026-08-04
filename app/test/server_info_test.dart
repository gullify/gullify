// Infos du serveur : lecture de l'enveloppe v2 et rendu de l'écran
// (Paramètres → Infos du serveur).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/server_info_repository.dart';
import 'package:gullify/screens/server_info_screen.dart';
import 'package:gullify/state/auth.dart';
import 'package:gullify/state/server_info.dart';
import 'package:gullify/theme.dart';

/// Réponse réelle de `/api/v2/server-info.php` (valeurs du serveur de test).
const _payload = <String, dynamic>{
  'disks': [
    {
      'label': 'Musique et données',
      'path': '/music',
      'total': 248505155584,
      'free': 24299745280,
      'used': 224205410304,
    },
  ],
  'music': {
    'bytes': 183279523976,
    'computedAt': 1785809915,
    'path': '/music',
  },
  'data': {'bytes': 809055315, 'computedAt': 1785809916, 'path': '/app/data'},
  'library': {
    'songs': 22765,
    'albums': 2668,
    'artists': 1230,
    'genres': 25,
    'playlists': 0,
    'users': 3,
    'duration': 4824876,
    'lastScan': 1782912781,
  },
  'database': {'bytes': 12304384, 'name': 'gullify'},
  'system': {
    'php': '8.2.33',
    'server': 'Apache/2.4.68 (Debian)',
    'os': 'Debian GNU/Linux 13 (trixie)',
    'kernel': '6.8.0-134-generic',
    'cpus': 4,
    'load': [0, 0.22, 0.55],
    'memTotal': 8254554112,
    'memFree': 3489517568,
    'uptime': 2764575,
    'time': '04/08 02:18',
    'timezone': 'UTC',
    'apiVersion': 'v2',
  },
};

class _FakeAuth extends AuthController {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        serverUrl: 'https://gullify.app',
      );
}

void main() {
  test('les infos du serveur se lisent depuis la réponse v2', () {
    final info = ServerInfo.fromJson(_payload);

    expect(info.disks, hasLength(1));
    expect(info.disks.single.label, 'Musique et données');
    expect(info.disks.single.usedRatio, closeTo(0.902, 0.005));
    expect(info.music.bytes, 183279523976);
    expect(info.music.computedAt, isNotNull);
    expect(info.library.songs, 22765);
    expect(info.library.lastScan, isNotNull);
    expect(info.databaseBytes, 12304384);
    expect(info.system.php, '8.2.33');
    expect(info.system.load, [0, 0.22, 0.55]);
    expect(info.system.uptime, const Duration(seconds: 2764575));
  });

  test('une réponse incomplète ne casse rien', () {
    final info = ServerInfo.fromJson(const {});

    expect(info.disks, isEmpty);
    expect(info.music.bytes, isNull);
    expect(info.library.songs, 0);
    expect(info.library.lastScan, isNull);
    expect(info.system.load, isEmpty);
    expect(info.system.uptime, isNull);
  });

  test('un disque de taille inconnue ne divise pas par zéro', () {
    final disk = ServerDisk.fromJson(const {'label': 'X'});
    expect(disk.usedRatio, 0);
  });

  testWidgets('l\'écran affiche l\'espace libre et la bibliothèque',
      (tester) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(_FakeAuth.new),
          serverInfoProvider
              .overrideWith((ref) async => ServerInfo.fromJson(_payload)),
        ],
        child: MaterialApp(
          theme: gullifyThemeFor(GullifyAccent.indigo, dark: false),
          home: const ServerInfoScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('22.6 Go libres'), findsOneWidget);
    expect(find.text('https://gullify.app'), findsOneWidget);
    expect(find.text('170.7 Go'), findsOneWidget); // musique

    // Le bas de la liste : bibliothèque puis système.
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();

    // Milliers séparés par une espace fine insécable (U+202F).
    expect(find.text('22\u202f765'), findsOneWidget); // titres
    expect(find.text('55 j 20 h'), findsOneWidget); // durée cumulée
    expect(find.textContaining('Debian GNU/Linux'), findsOneWidget);

    // Les playlists absentes ne prennent pas de ligne pour rien.
    expect(find.text('Playlists'), findsNothing);
  });
}
