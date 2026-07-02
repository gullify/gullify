import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'screens/album_screen.dart';
import 'screens/albums_screen.dart';
import 'screens/artist_screen.dart';
import 'screens/artists_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/search_screen.dart';
import 'screens/server_screen.dart';
import 'screens/shell_screen.dart';
import 'screens/splash_screen.dart';
import 'state/auth.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/server', builder: (_, _) => const ServerScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => ShellScreen(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/artists',
              builder: (_, _) => const ArtistsScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/albums', builder: (_, _) => const AlbumsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
          ]),
        ],
      ),
      GoRoute(
        path: '/artist/:id',
        builder: (_, state) =>
            ArtistScreen(artistId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/album/:id',
        builder: (_, state) =>
            AlbumScreen(albumId: int.parse(state.pathParameters['id']!)),
      ),
    ],
    redirect: (context, state) {
      final status = ref.read(authProvider).status;
      final loc = state.matchedLocation;
      final onAuthScreen =
          loc == '/splash' || loc == '/server' || loc == '/login';
      switch (status) {
        case AuthStatus.unknown:
          return loc == '/splash' ? null : '/splash';
        case AuthStatus.needsServer:
          return loc == '/server' ? null : '/server';
        case AuthStatus.needsLogin:
          return loc == '/login' ? null : '/login';
        case AuthStatus.authenticated:
          return onAuthScreen ? '/' : null;
      }
    },
  );

  // Re-run redirect whenever auth state changes.
  ref.listen(authProvider, (_, _) => router.refresh());
  ref.onDispose(router.dispose);
  return router;
});
