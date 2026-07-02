import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/radio_repository.dart';
import 'auth.dart';

final radioRepositoryProvider = Provider<RadioRepository>(
  (ref) => RadioRepository(ref.watch(apiClientProvider)),
);

final radioStationsProvider = FutureProvider<List<RadioStation>>(
  (ref) => ref.watch(radioRepositoryProvider).stations(),
);
