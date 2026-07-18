import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:tandem/features/auth/sign_in_screen.dart';
import 'package:tandem/features/connect/connect_screen.dart';
import 'package:tandem/features/discover/discover_screen.dart';
import 'package:tandem/features/matches/matches_screen.dart';
import 'package:tandem/features/outreach/outreach_screen.dart';
import 'package:tandem/features/profile/profile_screen.dart';
import 'package:tandem/features/settings/settings_screen.dart';
import 'package:tandem/features/shell/app_shell.dart';
import 'package:tandem/features/shortlist/shortlist_screen.dart';

final authStateProvider = StreamProvider<User?>(
  (ref) => FirebaseAuth.instance.authStateChanges(),
);

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authStateProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/discover',
    refreshListenable: _AuthRefresh(auth),
    redirect: (context, state) {
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
  _AuthRefresh(AsyncValue<User?> initial) {
    _last = initial;
  }
  AsyncValue<User?>? _last;
  void update(AsyncValue<User?> next) {
    if (next != _last) {
      _last = next;
      notifyListeners();
    }
  }
}
