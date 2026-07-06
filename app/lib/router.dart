import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'screens/aa_diagnostic_screen.dart';
import 'screens/album_screen.dart';
import 'screens/artist_screen.dart';
import 'screens/changelog_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/equalizer_screen.dart';
import 'screens/favorites_screen.dart';
import 'screens/genres_screen.dart';
import 'screens/home_screen.dart';
import 'screens/ideas_screen.dart';
import 'screens/library_screen.dart';
import 'screens/login_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/now_playing_screen.dart';
import 'screens/playlist_screen.dart';
import 'screens/popular_screen.dart';
import 'screens/radio_edit_screen.dart';
import 'screens/radio_screen.dart';
import 'api/radio_repository.dart';
import 'screens/search_screen.dart';
import 'screens/server_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/shell_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/user_library_screen.dart';
import 'screens/yt_downloads_screen.dart';
import 'models/server_user.dart';
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
        // Ordre = index du dock : 0 Accueil, 1 Bibliothèque, 2 Recherche,
        // 3 Radio, 4 Favoris.
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/library',
              builder: (_, _) => const LibraryScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/radio', builder: (_, _) => const RadioScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/favorites',
              builder: (_, _) => const FavoritesScreen(),
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
        // Glisse depuis le bas, cohérent avec la fermeture par swipe.
        pageBuilder: (_, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const NowPlayingScreen(),
          transitionDuration: const Duration(milliseconds: 250),
          transitionsBuilder: (_, animation, _, child) => SlideTransition(
            position: animation.drive(
              Tween(begin: const Offset(0, 1), end: Offset.zero)
                  .chain(CurveTween(curve: Curves.easeOutCubic)),
            ),
            child: child,
          ),
        ),
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
      GoRoute(
        path: '/popular',
        builder: (_, _) => const PopularScreen(),
      ),
      GoRoute(
        path: '/radio/edit',
        builder: (_, state) =>
            RadioEditScreen(station: state.extra as RadioStation?),
      ),
      GoRoute(
        path: '/settings/changelog',
        builder: (_, _) => const ChangelogScreen(),
      ),
      GoRoute(
        path: '/settings/ideas',
        builder: (_, _) => const IdeasScreen(),
      ),
      GoRoute(
        path: '/genres',
        builder: (_, _) => const GenresScreen(),
      ),
      GoRoute(
        path: '/settings/aa-diagnostic',
        builder: (_, _) => const AaDiagnosticScreen(),
      ),
      GoRoute(
        path: '/user-library',
        builder: (_, state) =>
            UserLibraryScreen(user: state.extra as ServerUser),
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
