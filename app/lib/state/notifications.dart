import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/notifications_repository.dart';
import 'auth.dart';

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => NotificationsRepository(ref.watch(apiClientProvider)),
);

final notificationsProvider = FutureProvider<NotificationsPage>(
  (ref) => ref.watch(notificationsRepositoryProvider).list(),
);
