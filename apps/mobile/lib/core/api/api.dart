import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final functionsProvider = Provider<FirebaseFunctions>(
  (_) => FirebaseFunctions.instanceFor(region: 'us-central1'),
);

final apiProvider = Provider<TandemApi>(
  (ref) => TandemApi(ref.watch(functionsProvider)),
);

class TandemApi {
  TandemApi(this._fns);
  final FirebaseFunctions _fns;

  Future<Map<String, dynamic>?> detectChannel(String input) async {
    final r = await _fns
        .httpsCallable('detectChannel')
        .call<Map<String, dynamic>>({'text': input});
    final data = Map<String, dynamic>.from(r.data);
    if (data['ref'] == null) return null;
    return Map<String, dynamic>.from(data['ref'] as Map);
  }

  Future<Map<String, dynamic>> analyzeChannel(
    Map<String, dynamic> ref, {
    bool force = false,
  }) async {
    final r = await _fns
        .httpsCallable('analyzeChannel')
        .call<Map<String, dynamic>>({'ref': ref, 'force': force});
    return Map<String, dynamic>.from(r.data);
  }

  Future<Map<String, dynamic>> findMatches({
    required String channelKey,
    int limit = 24,
    bool refresh = false,
  }) async {
    final r =
        await _fns.httpsCallable('findMatches').call<Map<String, dynamic>>({
      'profileChannelKey': channelKey,
      'filters': {
        'limit': limit,
        'enableAiRerank': true,
        'refresh': refresh,
      },
    });
    return Map<String, dynamic>.from(r.data);
  }

  Future<Map<String, dynamic>> draftOutreach({
    required String fromKey,
    required String toKey,
    String? angle,
  }) async {
    final r =
        await _fns.httpsCallable('draftOutreach').call<Map<String, dynamic>>({
      'fromKey': fromKey,
      'toKey': toKey,
      if (angle != null) 'angle': angle,
    });
    return Map<String, dynamic>.from(r.data);
  }

  Future<void> deleteAccount() async {
    await _fns.httpsCallable('deleteAccount').call<void>(null);
  }
}
