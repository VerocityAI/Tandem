import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cohyve/features/auth/sign_in_screen.dart';
import 'package:cohyve/features/connect/connect_screen.dart';
import 'package:cohyve/features/discover/discover_screen.dart';
import 'package:cohyve/features/matches/matches_screen.dart';
import 'package:cohyve/features/outreach/outreach_screen.dart';
import 'package:cohyve/features/profile/profile_screen.dart';
import 'package:cohyve/features/settings/settings_screen.dart';
import 'package:cohyve/features/shell/app_shell.dart';
import 'package:cohyve/features/shortlist/shortlist_screen.dart';

final authStateProvider = StreamProvider<User?>(
  (ref) => FirebaseAuth.instance.authStateChanges(),
);

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  // Refresh the router's redirect logic on auth changes WITHOUT rebuilding the
  // whole GoRouter (rebuilding resets navigation to initialLocation and can
  // bounce the user off the current screen mid-operation).
  final refresh = _AuthRefresh();
  ref.onDispose(refresh.dispose);
  ref.listen<AsyncValue<User?>>(authStateProvider, (_, __) => refresh.notify());

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/discover',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authStateProvider);
      // While auth is still resolving, don't make a routing decision — treating
      // the loading state as "logged out" would wrongly kick the user to /signin.
      if (auth.isLoading) return null;
      final loggedIn = auth.valueOrNull != null;
      final atSignIn = state.matchedLocation == '/signin';
      if (!loggedIn) return atSignIn ? null : '/signin';
      if (loggedIn && atSignIn) return '/discover';
      return null;
    },
    routes: [
      GoRoute(path: '/signin', builder: (_, __) => const SignInScreen()),
      GoRoute(path: '/connect', builder: (_, __) => const ConnectScreen()),
      GoRoute(
        path: '/profile/:channelKey',
        builder: (_, s) =>
            ProfileScreen(channelKey: s.pathParameters['channelKey']!),
      ),
      GoRoute(
        path: '/matches/:channelKey',
        builder: (_, s) =>
            MatchesScreen(channelKey: s.pathParameters['channelKey']!),
      ),
      GoRoute(
        path: '/outreach/:fromKey/:toKey',
        builder: (_, s) => OutreachScreen(
          fromKey: s.pathParameters['fromKey']!,
          toKey: s.pathParameters['toKey']!,
        ),
      ),
      // Bottom-nav shell: Discover / Shortlist / Settings.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/discover',
                builder: (_, __) => const DiscoverScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/shortlist',
                builder: (_, __) => const ShortlistScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, __) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class _AuthRefresh extends ChangeNotifier {
  void notify() => notifyListeners();
}
