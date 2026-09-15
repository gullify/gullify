// L'administration des comptes, portée du site web dans l'app (une seule
// interface à entretenir).
//
// Deux pièges valent des tests : MySQL rend ses booléens en 0/1 — parfois en
// chaîne selon le pilote — et `admin.php` teste ses drapeaux avec `!empty()`,
// si bien qu'envoyer « false » les ACTIVERAIT.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gullify/api/admin_repository.dart';
import 'package:gullify/models/user.dart';
import 'package:gullify/screens/admin/users_screen.dart';
import 'package:gullify/state/admin.dart';
import 'package:gullify/state/auth.dart';

const _maxime = AdminUser(
  id: 1,
  username: 'maxime',
  fullName: 'Maxime',
  isAdmin: true,
  musicDirectory: 'maxime',
);
// Dossier volontairement différent de l'identifiant : sinon le même texte
// apparaît deux fois dans la ligne et les recherches deviennent ambiguës.
const _mylene = AdminUser(
  id: 2,
  username: 'mylene',
  musicDirectory: 'musique-mylene',
);
const _suspendu = AdminUser(
  id: 3,
  username: 'frederique',
  isActive: false,
  storageType: 'sftp',
  sftpHost: 'nas.local',
);

class _FakeAdmin extends Fake implements AdminRepository {
  @override
  Future<List<AdminUser>> users() async => [_maxime, _mylene, _suspendu];

  @override
  Future<MusicDirectories> directories() async =>
      const MusicDirectories(basePath: '/music', directories: ['maxime']);
}

class _FixedAuth extends AuthController {
  @override
  AuthState build() => const AuthState(
    status: AuthStatus.authenticated,
    user: User(id: 1, username: 'maxime', isAdmin: true),
  );
}

Widget _host(Widget child) => ProviderScope(
  overrides: [
    adminRepositoryProvider.overrideWithValue(_FakeAdmin()),
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
  group('AdminUser.fromJson', () {
    test('les booléens de MySQL, en 0/1 comme en chaîne', () {
      final entier = AdminUser.fromJson({
        'id': 4,
        'username': 'a',
        'is_admin': 1,
        'is_active': 0,
      });
      expect(entier.isAdmin, isTrue);
      expect(entier.isActive, isFalse);

      final chaine = AdminUser.fromJson({
        'id': 5,
        'username': 'b',
        'is_admin': '1',
        'is_active': '0',
      });
      expect(chaine.isAdmin, isTrue);
      expect(
        chaine.isActive,
        isFalse,
        reason: '« 0 » est une chaîne non vide : elle ne doit pas passer '
            'pour vraie',
      );
    });

    test('une chaîne vide vaut « pas de valeur »', () {
      final u = AdminUser.fromJson({
        'id': 6,
        'username': 'c',
        'full_name': '',
        'music_directory': '   ',
        'sftp_host': '',
      });
      expect(u.fullName, isNull);
      expect(u.musicDirectory, isNull, reason: 'des espaces ne sont pas un dossier');
      expect(u.sftpHost, isNull);
      expect(u.displayName, 'c', reason: 'sans nom complet, l\'identifiant');
    });

    test('un compte absent de la réponse ne fait pas tout échouer', () {
      final u = AdminUser.fromJson(const {});
      expect(u.id, 0);
      expect(u.username, '');
      expect(u.storageType, 'local');
      expect(u.sftpPort, 22);
      expect(u.isActive, isFalse);
    });
  });

  group('la liste des comptes', () {
    testWidgets('montre le rôle, la suspension, le stockage et soi-même', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const AdminUsersScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Maxime'), findsOneWidget);
      expect(find.text('mylene'), findsOneWidget);
      expect(find.text('frederique'), findsOneWidget);

      expect(find.text('Administrateur'), findsOneWidget);
      expect(find.text('Suspendu'), findsOneWidget);
      expect(find.text('SFTP'), findsOneWidget);
      // Son propre compte est marqué : le serveur y refuse la suppression,
      // la suspension et le changement de rôle.
      expect(find.text('Vous'), findsOneWidget);
    });

    testWidgets('un compte sans dossier de musique le dit', (tester) async {
      await tester.pumpWidget(_host(const AdminUsersScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Aucun dossier de musique'), findsOneWidget);
    });
  });
}
