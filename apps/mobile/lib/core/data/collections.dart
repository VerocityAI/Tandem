import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Current signed-in user's uid (null when signed out).
final uidProvider = Provider<String?>(
  (ref) => FirebaseAuth.instance.currentUser?.uid,
);

CollectionReference<Map<String, dynamic>>? _userCol(String sub) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;
  return FirebaseFirestore.instance.collection('users/$uid/$sub');
}

List<Map<String, dynamic>> _mapDocs(QuerySnapshot<Map<String, dynamic>> s) =>
    s.docs.map((d) => {...d.data(), 'id': d.id}).toList();

/// The channels the user has analysed / connected (their own + watched).
final connectedChannelsProvider =
    StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  final col = _userCol('connectedChannels');
  if (col == null) return const Stream.empty();
  return col.orderBy('addedAt', descending: true).snapshots().map(_mapDocs);
});

/// The user's saved collaborators (shortlist / CRM).
final shortlistProvider =
    StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  final col = _userCol('shortlists');
  if (col == null) return const Stream.empty();
  return col.orderBy('savedAt', descending: true).snapshots().map(_mapDocs);
});

/// Saved discovery searches (for quick re-runs and alerts).
final savedSearchesProvider =
    StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  final col = _userCol('searches');
  if (col == null) return const Stream.empty();
  return col.orderBy('savedAt', descending: true).snapshots().map(_mapDocs);
});

/// Set of channelKeys currently shortlisted, for quick "is saved" checks.
final shortlistKeysProvider = Provider.autoDispose<Set<String>>((ref) {
  final list = ref.watch(shortlistProvider).valueOrNull ?? const [];
  return list.map((e) => e['channelKey'] as String? ?? '').toSet();
});

final shortlistRepoProvider = Provider<ShortlistRepository>(
  (ref) => ShortlistRepository(),
);

/// Writes for the shortlist / CRM pipeline.
class ShortlistRepository {
  CollectionReference<Map<String, dynamic>> _col() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance.collection('users/$uid/shortlists');
  }

  Future<void> save(Map<String, dynamic> match,
      {String? fromChannelKey}) async {
    final key = match['channelKey'] as String;
    await _col().doc(key).set({
      'channelKey': key,
      'platform': match['platform'] ?? 'youtube',
      'name': match['name'],
      'niche': match['niche'],
      'followers': match['followers'],
      'thumbnailUrl': match['thumbnailUrl'],
      'score': match['score'],
      if (fromChannelKey != null) 'fromChannelKey': fromChannelKey,
      'status': 'new',
      'savedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<void> setStatus(String channelKey, String status, {String? fromKey}) =>
      _col().doc(channelKey).set({
        'status': status,
        if (fromKey != null) 'fromChannelKey': fromKey,
      }, SetOptions(merge: true));

  Future<void> setNote(String channelKey, String note) =>
      _col().doc(channelKey).set({'note': note}, SetOptions(merge: true));

  Future<void> remove(String channelKey) => _col().doc(channelKey).delete();
}

final channelsRepoProvider = Provider<ChannelsRepository>(
  (ref) => ChannelsRepository(),
);

/// Manages the user's connected channels (add happens via analyzeChannel).
class ChannelsRepository {
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  /// Remove a single connected channel from the user's list (the shared
  /// `channels/` cache is untouched; re-analysing re-adds it).
  Future<void> removeChannel(String channelKey) =>
      _db.doc('users/$_uid/connectedChannels/$channelKey').delete();

  /// Re-add a previously removed connected channel (for undo). Strips the
  /// synthetic `id` field added when reading.
  Future<void> restoreChannel(Map<String, dynamic> data) {
    final key = data['channelKey'] as String? ?? data['id'] as String;
    final payload = Map<String, dynamic>.from(data)..remove('id');
    return _db
        .doc('users/$_uid/connectedChannels/$key')
        .set(payload, SetOptions(merge: true));
  }

  /// Wipe the user's channels, shortlist and saved searches for a fresh start.
  /// Does not delete the account or the shared channel cache.
  Future<void> resetOnboarding() async {
    for (final sub in ['connectedChannels', 'shortlists', 'searches']) {
      final snap = await _db.collection('users/$_uid/$sub').get();
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }
}
