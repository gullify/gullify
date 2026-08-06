import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/share_repository.dart';
import 'auth.dart';

final shareRepositoryProvider = Provider<ShareRepository>(
  (ref) => ShareRepository(ref.watch(apiClientProvider)),
);
