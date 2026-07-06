import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/ideas_repository.dart';
import 'auth.dart';

final ideasRepositoryProvider = Provider<IdeasRepository>(
  (ref) => IdeasRepository(ref.watch(apiClientProvider)),
);

final ideasProvider = FutureProvider<List<Idea>>(
  (ref) => ref.watch(ideasRepositoryProvider).list(),
);
