import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'screens/album_screen.dart';
import 'screens/artist_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/equalizer_screen.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/login_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/now_playing_screen.dart';
import 'screens/playlist_screen.dart';
import 'screens/radio_screen.dart';
import 'screens/search_screen.dart';
import 'screens/server_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/shell_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/yt_downloads_screen.dart';
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
            GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/radio', builder: (_, _) => const RadioScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/library',
              builder: (_, _) => const LibraryScreen(),
            ),
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
      GoRoute(
        path: '/playlist/:id',
        builder: (_, state) => PlaylistScreen(
          playlistId: int.parse(state.pathParameters['id']!),
          name: state.uri.queryParameters['name'] ?? 'Playlist',
        ),
      ),
      GoRoute(
        path: '/now-playing',
        builder: (_, _) => const NowPlayingScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (_, _) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/settings/equalizer',
        builder: (_, _) => const EqualizerScreen(),
      ),
      GoRoute(
        path: '/settings/downloads',
        builder: (_, _) => const DownloadsScreen(),
      ),
      GoRoute(
        path: '/yt-downloads',
        builder: (_, _) => const YtDownloadsScreen(),
      ),
      GoRoute(
        path: '/stats',
        builder: (_, _) => const StatsScreen(),
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
