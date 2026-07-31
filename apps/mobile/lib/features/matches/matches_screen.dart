import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:cohyve/core/api/api.dart';
import 'package:cohyve/core/data/collections.dart';
import 'package:cohyve/core/util/format.dart';
import 'package:cohyve/core/widgets/score_ring.dart';
import 'package:cohyve/core/theme/app_theme.dart';

class MatchesScreen extends ConsumerStatefulWidget {
  const MatchesScreen({required this.channelKey, super.key});
  final String channelKey;

  @override
  ConsumerState<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends ConsumerState<MatchesScreen> {
  List<Map<String, dynamic>>? _matches;
  List<Map<String, dynamic>> _hiddenMatches = [];
  bool _showHidden = false;
  int _filteredOut = 0;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _sourceProfile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sourceProfile = await _loadSourceProfile();
      final api = ref.read(apiProvider);
      final result =
          await api.findMatches(channelKey: widget.channelKey, refresh: refresh);
      final raw = result['matches'] as List<dynamic>? ?? [];
      final allMatches =
          raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final ranked = sourceProfile == null
          ? (kept: allMatches, hidden: <Map<String, dynamic>>[])
          : _rankMatches(sourceProfile, allMatches);
      if (!mounted) return;
      setState(() {
        _sourceProfile = sourceProfile;
        _matches = ranked.kept;
        _hiddenMatches = ranked.hidden;
        _filteredOut = ranked.hidden.length;
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<Map<String, dynamic>?> _loadSourceProfile() async {
    final snap = await FirebaseFirestore.instance
        .collection('channels')
        .doc(widget.channelKey)
        .get();
    final data = snap.data();
    if (data == null) return null;
    return Map<String, dynamic>.from(data);
  }

  // Ranks candidates by a client-side relevance score and drops poor matches.
  // This is a guardrail on top of the backend score: it enforces audience-tier
  // parity, topical adjacency, and identity overlap, since cached niche/topic
  // metadata is unreliable. Returns kept candidates (sorted best-first) plus the
  // dropped candidates, each annotated with a human-readable filter reason so
  // the user can review who was excluded and why.
  ({List<Map<String, dynamic>> kept, List<Map<String, dynamic>> hidden})
      _rankMatches(
    Map<String, dynamic> source,
    List<Map<String, dynamic>> candidates,
  ) {
    final scored = <({Map<String, dynamic> match, double score})>[];
    final hidden = <({Map<String, dynamic> match, double score})>[];
    for (final c in candidates) {
      final result = _relevanceResult(source, c);
      if (result.score == null) {
        c['_filterReason'] = result.reason;
        c['_filterScore'] = null;
        hidden.add((match: c, score: -1));
        continue;
      }
      scored.add((match: c, score: result.score!));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));

    // Keep strong matches (>= 0.5). If too few survive, relax to 0.3 so the
    // user still sees the best available options rather than an empty list.
    var threshold = 0.5;
    var kept = scored.where((e) => e.score >= threshold).toList();
    if (kept.length < 2 && scored.where((e) => e.score >= 0.3).isNotEmpty) {
      threshold = 0.3;
      kept = scored.where((e) => e.score >= threshold).toList();
    }

    return (kept: kept.map((e) => e.match).toList(), hidden: hidden.map((e) => e.match).toList());
  }

  ({double? score, String? reason}) _relevanceResult(
    Map<String, dynamic> source,
    Map<String, dynamic> candidate,
  ) {
    final sourceTier = _audienceTier(source);
    final candidateTier = _audienceTier(candidate);

    // Audience tier mismatch is a hard filter.
    if ((sourceTier - candidateTier).abs() > 1) {
      return (score: null, reason: 'Audience tier mismatch');
    }

    // Topical adjacency: both should share at least one content pillar or niche.
    final sourcePillars = (source['contentPillars'] as List<dynamic>?)
        ?.map((e) => (e as String).toLowerCase())
        .toSet()
        .toSet();
    final candidatePillars = (candidate['contentPillars'] as List<dynamic>?)
        ?.map((e) => (e as String).toLowerCase())
        .toSet()
        .toSet();

    if (sourcePillars != null && candidatePillars != null) {
      final overlap = sourcePillars.intersection(candidatePillars);
      if (overlap.isEmpty) {
        return (score: null, reason: 'No topical overlap');
      }
    }

    // Identity overlap: channel names should not be identical (would indicate
    // the same creator).
    final sourceName = (source['name'] as String? ?? '').toLowerCase().trim();
    final candidateName = (candidate['name'] as String? ?? '').toLowerCase().trim();
    if (sourceName == candidateName) {
      return (score: null, reason: 'Same creator');
    }

    // Compute a soft relevance score (0–1) from audience proximity and topical
    // overlap for ranking purposes.
    final audienceProximity = 1 - (sourceTier - candidateTier).abs() / 3;
    int? pillarOverlap;
    if (sourcePillars != null && candidatePillars != null) {
      pillarOverlap = sourcePillars.intersection(candidatePillars).length;
    }
    final topicalScore = pillarOverlap == null || sourcePillars == null
        ? 0.3
        : pillarOverlap / sourcePillars.length;

    final score = (audienceProximity * 0.6 + topicalScore * 0.4);
    return (score: score, reason: null);
  }

  double _audienceTier(Map<String, dynamic> channel) {
    final followers = (channel['followers'] as num? ?? 0).toInt();
    if (followers < 10000) return 0;
    if (followers < 100000) return 1;
    if (followers < 500000) return 2;
    if (followers < 1000000) return 3;
    return 4;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Matches'),
        actions: [
          if (_matches != null && _matches!.isNotEmpty)
            IconButton(
              icon: const Icon(LucideIcons.refreshCw),
              tooltip: 'Refresh matches',
              onPressed: () => _load(refresh: true),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : RefreshIndicator(
                  onRefresh: () => _load(refresh: true),
                  child: (_matches?.isEmpty ?? true)
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 100,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [
                                        BrandingExtended.gradientStart.withValues(alpha: 0.2),
                                        BrandingExtended.gradientMid.withValues(alpha: 0.1),
                                      ],
                                    ),
                                  ),
                                  child: const Icon(
                                    LucideIcons.search,
                                    size: 48,
                                    color: BrandingExtended.gradientStart,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  'No matches found',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Try refreshing or analyse another channel to discover collaborators.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _matches!.length + (_showHidden ? _hiddenMatches.length : 0),
                          itemBuilder: (context, index) {
                            if (index < _matches!.length) {
                              return _MatchCard(
                                match: _matches![index],
                                sourceKey: widget.channelKey,
                              );
                            }
                            final hiddenIndex = index - _matches!.length;
                            if (hiddenIndex < _hiddenMatches.length && _showHidden) {
                              final hidden = _hiddenMatches[hiddenIndex];
                              return _HiddenMatchCard(match: hidden);
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                ),
      floatingActionButton: (_matches?.isNotEmpty ?? false)
          ? FloatingActionButton.extended(
              onPressed: () => _load(refresh: true),
              icon: const Icon(LucideIcons.refreshCw),
              label: const Text('Refresh'),
            )
          : null,
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.match, required this.sourceKey});
  final Map<String, dynamic> match;
  final String sourceKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fromKey = sourceKey;
    final toKey = match['channelKey'] as String? ?? '';
    final name = match['name'] as String? ?? toKey;
    final followers = (match['followers'] as num? ?? 0).toInt();
    final score = (match['score'] as num? ?? 0).toInt();
    final platform = match['platform'] as String? ?? 'youtube';
    final niche = (match['niche'] as String? ?? '').trim();
    final breakdown = (match['breakdown'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        [];
    final reasoning = (match['whyMatch'] as String? ??
            match['aiRationale'] as String? ??
            match['reason'] as String? ??
            '')
        .trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with avatar, name, and score
              Row(
                children: [
                  ChannelAvatar(
                    name: name,
                    niche: niche,
                    imageUrl: match['thumbnailUrl'] as String?,
                    platform: platform,
                    size: 56,
                    showBorder: true,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${fmtCount(followers)} subs'
                          '${niche.isNotEmpty ? ' • $niche' : ''}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ScoreRing(score: score, size: 48),
                ],
              ),

              // Score breakdown bars
              if (breakdown.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 14),
                Text(
                  'Score Breakdown',
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                ...breakdown.map((b) {
                  final label = b['label'] as String? ?? '';
                  final value = (b['value'] as num? ?? 0).toDouble();
                  final weight = (b['weight'] as num? ?? 0).toInt();
                  final barColor = value >= 80
                      ? BrandingExtended.success
                      : value >= 50
                          ? BrandingExtended.warning
                          : BrandingExtended.danger;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 92,
                          child: Text(
                            '$label ($weight%)',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: value / 100,
                              backgroundColor:
                                  theme.colorScheme.onSurface.withValues(alpha: 0.08),
                              color: barColor,
                              minHeight: 7,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 30,
                          child: Text(
                            '${value.toInt()}',
                            textAlign: TextAlign.right,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],

              // AI reasoning
              if (reasoning.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: BrandingExtended.gradientStart.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: BrandingExtended.gradientStart.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.lightbulb, size: 18, color: BrandingExtended.gradientStart),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          reasoning,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Action buttons
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/profile/$toKey'),
                      icon: const Icon(LucideIcons.user, size: 16),
                      label: const Text('Profile'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(
                          colors: [
                            BrandingExtended.gradientStart,
                            BrandingExtended.gradientMid,
                          ],
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => context.push('/outreach/$fromKey/$toKey'),
                          borderRadius: BorderRadius.circular(14),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(LucideIcons.mail, size: 16, color: Colors.white),
                                SizedBox(width: 6),
                                Text(
                                  'Outreach',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HiddenMatchCard extends StatelessWidget {
  const _HiddenMatchCard({required this.match});
  final Map<String, dynamic> match;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = match['name'] as String? ?? '';
    final filterReason = match['_filterReason'] as String? ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(LucideIcons.eyeOff, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
            Text(
              filterReason,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
