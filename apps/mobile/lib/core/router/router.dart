import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/sign_in_screen.dart';
import '../../features/connect/connect_screen.dart';
import '../../features/matches/matches_screen.dart';
import '../../features/outreach/outreach_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/shortlist/shortlist_screen.dart';

final authStateProvider = StreamProvider<User?>(
  (ref) => FirebaseAuth.instance.authStateChanges(),
);

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/connect',
    refreshListenable: _AuthRefresh(auth),
    redirect: (context, state) {
      final loggedIn = auth.valueOrNull != null;
      final atSignIn = state.matchedLocation == '/signin';
      if (!loggedIn) return atSignIn ? null : '/signin';
      if (loggedIn && atSignIn) return '/connect';
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
      GoRoute(path: '/shortlist', builder: (_, __) => const ShortlistScreen()),
      GoRoute(
        path: '/outreach/:fromKey/:toKey',
        builder: (_, s) => OutreachScreen(
          fromKey: s.pathParameters['fromKey']!,
          toKey: s.pathParameters['toKey']!,
        ),
      ),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
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
