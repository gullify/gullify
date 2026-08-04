// Les notifications ne servaient à rien : rien n'en créait, et la liste ne
// menait nulle part. Une idée réalisée par Claude en pose une, et la carte
// ouvre le carnet d'idées.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/notifications_repository.dart';
import 'package:gullify/screens/notifications_screen.dart';
import 'package:gullify/state/notifications.dart';

class _FakeNotificationsRepo extends Fake implements NotificationsRepository {
  _FakeNotificationsRepo(this.page);

  NotificationsPage page;
  final List<int> markedRead = [];
  final List<int> cleared = [];

  @override
  Future<NotificationsPage> list({int limit = 30}) async => page;

  @override
  Future<void> markRead(int id) async => markedRead.add(id);

  @override
  Future<void> clear(int id) async => cleared.add(id);
}

AppNotification _n({
  int id = 1,
  String type = 'idea_done',
  String title = 'Idée réalisée',
  String? message = 'une notification serait bien',
  String? readAt,
}) =>
    AppNotification(
      id: id,
      type: type,
      title: title,
      message: message,
      readAt: readAt,
      createdAt: DateTime.now()
          .subtract(const Duration(minutes: 5))
          .toString()
          .split('.')
          .first,
    );

Future<void> _pump(WidgetTester tester, _FakeNotificationsRepo repo) async {
  tester.view.physicalSize = const Size(412, 892);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        notificationsRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: NotificationsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('une idée réalisée se lit, et renvoie au carnet d\'idées',
      (tester) async {
    final repo = _FakeNotificationsRepo(
      NotificationsPage(items: [_n()], unread: 1),
    );
    await _pump(tester, repo);

    expect(find.text('Idée réalisée'), findsOneWidget);
    expect(find.text('une notification serait bien'), findsOneWidget);
    expect(find.text('Voir le carnet d\'idées'), findsOneWidget);
    expect(find.text('il y a 5 min'), findsOneWidget);

    // Le tap la marque lue (la navigation, elle, demande un routeur : le test
    // s'arrête à ce qui part vers le serveur).
    await tester.tap(find.text('Idée réalisée'));
    await tester.pump();
    expect(repo.markedRead, [1]);
  });

  testWidgets('une notification déjà lue ne repart pas au serveur',
      (tester) async {
    final repo = _FakeNotificationsRepo(
      NotificationsPage(
        items: [_n(readAt: '2026-08-04 10:00:00')],
        unread: 0,
      ),
    );
    await _pump(tester, repo);

    await tester.tap(find.text('Idée réalisée'));
    await tester.pump();
    expect(repo.markedRead, isEmpty);
  });

  testWidgets('un type inconnu reste lisible, sans lien vers les idées',
      (tester) async {
    final repo = _FakeNotificationsRepo(
      NotificationsPage(
        items: [_n(type: 'scan', title: 'Scan terminé', message: '42 titres')],
        unread: 1,
      ),
    );
    await _pump(tester, repo);

    expect(find.text('Scan terminé'), findsOneWidget);
    expect(find.text('Voir le carnet d\'idées'), findsNothing);
  });

  testWidgets('sans notification, la mascotte le dit', (tester) async {
    final repo = _FakeNotificationsRepo(
      const NotificationsPage(items: [], unread: 0),
    );
    await _pump(tester, repo);

    expect(find.text('Aucune notification'), findsOneWidget);
  });
}
