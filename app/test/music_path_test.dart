// Le chemin de la musique : ce qu'on montre et ce qu'on laisse choisir.
//
// Dans Docker, le serveur lit « /music » — un nom qui n'existe que dans le
// conteneur. La machine, elle, appelle ce dossier autrement (MUSIC_HOST_PATH).
// C'est ce chemin-là qu'il faut montrer, sans quoi l'écran annonce un chemin
// qui ne mène nulle part, et c'est celui-là qu'on doit pouvoir recopier.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gullify/api/admin_repository.dart';
import 'package:gullify/api/api_client.dart';
import 'package:gullify/models/user.dart';
import 'package:gullify/screens/admin/user_edit_screen.dart';
import 'package:gullify/state/admin.dart';
import 'package:gullify/state/auth.dart';

const _maxime = AdminUser(
  id: 1,
  username: 'maxime',
  fullName: 'Maxime',
  isAdmin: true,
  musicDirectory: 'maxime',
);

class _FakeClient extends Fake implements ApiClient {
  _FakeClient({this.hostPath = '/media/musique'});

  final String? hostPath;

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async => {
        'success': true,
        'data': ['maxime', 'maxime/Flac'],
        'base_path': '/music',
        if (hostPath != null) 'host_path': hostPath,
      };
}

class _FakeAdmin extends Fake implements AdminRepository {
  final List<String> enregistres = [];

  @override
  Future<List<AdminUser>> users() async => [_maxime];

  @override
  Future<MusicDirectories> directories() async => const MusicDirectories(
        basePath: '/music',
        hostPath: '/media/musique',
        directories: ['maxime', 'maxime/Flac'],
      );

  @override
  Future<void> updateDirectory(int userId, String musicDirectory) async =>
      enregistres.add(musicDirectory);
}

class _FixedAuth extends AuthController {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        user: User(id: 1, username: 'maxime', isAdmin: true),
      );
}

Widget _host(Widget child, _FakeAdmin admin) => ProviderScope(
      overrides: [
        adminRepositoryProvider.overrideWithValue(admin),
        authProvider.overrideWith(_FixedAuth.new),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/',
          routes: [GoRoute(path: '/', builder: (_, _) => child)],
        ),
      ),
    );

void main() {
  group('ce que le serveur dit de ses dossiers', () {
    test('le vrai chemin de la machine est celui qu\'on retient', () async {
      final dirs = await AdminRepository(_FakeClient()).directories();

      expect(dirs.basePath, '/music');
      expect(dirs.hostPath, '/media/musique');
      expect(dirs.chemin('maxime'), '/media/musique/maxime');
      expect(dirs.chemin('maxime/Flac'), '/media/musique/maxime/Flac');
      // Sans dossier, c'est la racine elle-même.
      expect(dirs.chemin(''), '/media/musique');
    });

    test('un serveur qui ne connaît que son conteneur reste utilisable',
        () async {
      // Vieux serveur, ou installation sans Docker : « host_path » manque, et
      // le chemin interne est alors le vrai.
      final dirs =
          await AdminRepository(_FakeClient(hostPath: null)).directories();

      expect(dirs.hostPath, '/music');
      expect(dirs.chemin('maxime'), '/music/maxime');
    });

    test('« . » est la racine elle-même', () {
      const dirs = MusicDirectories(
        basePath: '/music',
        hostPath: '/media/musique',
        directories: [],
      );
      expect(dirs.chemin('.'), '/media/musique');
    });
  });

  testWidgets('la fiche montre le vrai chemin, pas celui du conteneur',
      (tester) async {
    final admin = _FakeAdmin();
    await tester.pumpWidget(
      _host(const AdminUserScreen(user: _maxime), admin),
    );
    await tester.pumpAndSettle();

    expect(find.text('/media/musique/maxime'), findsOneWidget);
    expect(find.text('/music/maxime'), findsNothing);
    // Et on dit où ça se change, plutôt que de laisser chercher.
    expect(
      find.textContaining('Infos du serveur → Dossier de musique'),
      findsOneWidget,
    );
  });

  testWidgets('un compte peut lire tout le dossier', (tester) async {
    // Une bibliothèque à un seul occupant n'a pas de dossier à son nom : il
    // fallait pouvoir revenir à la racine, que l'API refusait.
    final admin = _FakeAdmin();
    await tester.pumpWidget(
      _host(const AdminUserScreen(user: _maxime), admin),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.folder_open));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tout le dossier (/media/musique)'));
    await tester.pumpAndSettle();

    expect(find.text('/media/musique'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Enregistrer le dossier'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Enregistrer le dossier'));
    await tester.pumpAndSettle();

    expect(admin.enregistres, ['.']);
  });

  testWidgets('le chemin voulu se saisit, et part tel quel au serveur',
      (tester) async {
    final admin = _FakeAdmin();
    await tester.pumpWidget(
      _host(const AdminUserScreen(user: _maxime), admin),
    );
    await tester.pumpAndSettle();

    // Le champ n'est plus une liste fermée : on écrit le chemin voulu, même
    // complet — le serveur le ramène au relatif.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Dossier de musique'),
      '/media/musique/maxime/Flac',
    );
    await tester.pump();

    // L'aperçu suit la saisie : un chemin déjà complet se montre tel quel.
    expect(find.text('/media/musique/maxime/Flac'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Enregistrer le dossier'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Enregistrer le dossier'));
    await tester.pumpAndSettle();

    expect(admin.enregistres, ['/media/musique/maxime/Flac']);
  });
}
