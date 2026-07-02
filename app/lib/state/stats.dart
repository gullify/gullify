import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/stats_repository.dart';
import 'auth.dart';

final statsRepositoryProvider = Provider<StatsRepository>(
  (ref) => StatsRepository(ref.watch(apiClientProvider)),
);

final statsProvider = FutureProvider<ListeningStats>(
  (ref) => ref.watch(statsRepositoryProvider).stats(),
);
