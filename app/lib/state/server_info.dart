import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/server_info_repository.dart';
import 'auth.dart';

final serverInfoRepositoryProvider = Provider<ServerInfoRepository>(
  (ref) => ServerInfoRepository(ref.watch(apiClientProvider)),
);

final serverInfoProvider = FutureProvider<ServerInfo>(
  (ref) => ref.watch(serverInfoRepositoryProvider).info(),
);
