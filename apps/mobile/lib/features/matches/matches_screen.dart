import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:tandem/core/api/api.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sourceProfile = await _loadSourceProfile();
      final api = ref.read(apiProvider);
      final result = await api.findMatches(channelKey: widget.channelKey);
      final raw = result['matches'] as List<dynamic>? ?? [];
      final allMatches =
          raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final ranked = sourceProfile == null
          ? (kept: allMatches, hidden: <Map<String, dynamic>>[])
          : _rankMatches(sourceProfile, allMatches);
      if (!mounted) return;
      setState(() {
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
    if (kept.length < 3) {
      threshold = 0.3;
      kept = scored.where((e) => e.score >= threshold).toList();
    }
    final keptSet = kept.map((e) => e.match).toSet();
    for (final e in scored) {
      if (keptSet.contains(e.match)) continue;
      e.match['_filterReason'] =
          'Low relevance score (${(e.score * 100).round()}%, below ${(threshold * 100).round()}% cutoff)';
      e.match['_filterScore'] = e.score;
      hidden.add(e);
    }
    hidden.sort((a, b) => b.score.compareTo(a.score));

    return (
      kept: kept.map((e) => e.match).toList(),
      hidden: hidden.map((e) => e.match).toList(),
    );
  }

  // Computes the relevance score and the reason it was rejected (if any).
  ({double? score, String reason}) _relevanceResult(
    Map<String, dynamic> source,
    Map<String, dynamic> candidate,
  ) {
    final name = (candidate['name'] ?? '').toString().trim();
    if (name.isEmpty) {
      return (score: null, reason: 'Incomplete channel data (no name)');
    }

    final audience = _audienceParity(source, candidate);
    if (audience == null) {
      return (
        score: null,
        reason: 'Audience size too far apart (outside 0.1×–10× of your reach)',
      );
    }

    final sourceCats = _categories(source);
    final candidateCats = _categories(candidate);
    final familyScore = _familyScore(sourceCats, candidateCats);
    if (familyScore == null) {
      return (
        score: null,
        reason: 'Different, non-adjacent niche family — little audience overlap',
      );
    }

    final sourceVocab = _identityVocab(source);
    final candidateVocab = _identityVocab(candidate);
    double identity;
    if (sourceVocab.isEmpty || candidateVocab.isEmpty) {
      identity = 0.0;
    } else {
      final inter = sourceVocab.intersection(candidateVocab).length;
      final union = sourceVocab.union(candidateVocab).length;
      identity = union == 0 ? 0.0 : inter / union;
    }

    final region = _regionScore(source, candidate);

    final score = 0.45 * familyScore +
        0.30 * audience +
        0.15 * (identity > 0 ? 0.5 + 0.5 * identity : 0.0) +
        0.10 * region;
    return (score: score.clamp(0.0, 1.0), reason: '');
  }

  // Audience-tier parity: peak at equal size, decaying with log-distance.
  // Returns null when the gap is extreme (outside 0.1x..10x), or a score in
  // [0,1] where 1.0 is identical reach. Within the preferred 0.3x..3x band the
  // score stays high (>= ~0.6).
  double? _audienceParity(
    Map<String, dynamic> source,
    Map<String, dynamic> candidate,
  ) {
    final src = (source['followers'] as num?)?.toDouble() ?? 0;
    final cand = (candidate['followers'] as num?)?.toDouble() ?? 0;
    // For sizable sources, a 0-follower candidate is junk.
    if (src >= 1000 && cand <= 0) return null;
    if (src <= 0 || cand <= 0) return 0.5; // unknown — neutral
    final ratio = cand / src;
    if (ratio < 0.1 || ratio > 10) return null; // extreme mismatch
    // log10 distance: 0 at parity, 1 at 10x/0.1x.
    final dist = _log10(ratio).abs();
    return (1.0 - dist).clamp(0.0, 1.0);
  }

  double _log10(double x) => (x <= 0) ? 0 : (math.log(x) / math.ln10);

  // Family score: 1.0 same family, 0.7 adjacent, null disjoint+non-adjacent.
  // If either side has no detected family, treat as neutral 0.5 (can't judge).
  double? _familyScore(Set<String> sourceCats, Set<String> candidateCats) {
    if (sourceCats.isEmpty || candidateCats.isEmpty) return 0.5;
    if (sourceCats.intersection(candidateCats).isNotEmpty) return 1;
    // Check adjacency between any source/candidate family pair.
    for (final s in sourceCats) {
      final adj = _adjacentFamilies[s] ?? const <String>{};
      if (candidateCats.any(adj.contains)) return 0.7;
    }
    return null; // disjoint and not adjacent
  }

  // Adjacency graph: families whose audiences plausibly cross-pollinate.
  static const Map<String, Set<String>> _adjacentFamilies = {
    'tech': {'gaming', 'education', 'finance'},
    'gaming': {'tech', 'music', 'education'},
    'education': {'tech', 'finance', 'gaming'},
    'finance': {'tech', 'education'},
    'beauty': {'fitness', 'cooking'},
    'fitness': {'beauty', 'cooking'},
    'cooking': {'travel', 'fitness', 'beauty'},
    'travel': {'cooking', 'music'},
    'music': {'gaming', 'travel'},
    'kids': {},
    'drama': {'music'},
  };

  double _regionScore(
    Map<String, dynamic> source,
    Map<String, dynamic> candidate,
  ) {
    final src = (source['region'] ?? '').toString().trim().toLowerCase();
    final cand = (candidate['region'] ?? '').toString().trim().toLowerCase();
    if (src.isEmpty || cand.isEmpty) return 0.5;
    if (src == cand) return 1;
    if (src == 'global' || cand == 'global') return 0.8;
    return 0.3;
  }

  // belong to zero, one, or several families. Used as a hard incompatibility
  // gate when source and candidate live in disjoint families.
  Set<String> _categories(Map<String, dynamic> profile) {
    final text = '${profile['name'] ?? ''} ${profile['description'] ?? ''}'
        .toLowerCase();
    const families = <String, List<String>>{
      'kids': [
        'nursery',
        'rhyme',
        'rhymes',
        'baby',
        'babies',
        'toddler',
        'preschool',
        'kids',
        'kid',
        'children',
        'cartoon',
        'cartoons',
        'lullaby',
      ],
      'tech': [
        'tech',
        'technology',
        'smartphone',
        'iphone',
        'android',
        'gadget',
        'gadgets',
        'laptop',
        'review',
        'reviews',
        'unboxing',
        'mkbhd',
      ],
      'gaming': [
        'gaming',
        'gamer',
        'gameplay',
        'minecraft',
        'fortnite',
        'esports',
        'speedrun',
      ],
      'beauty': [
        'makeup',
        'beauty',
        'skincare',
        'cosmetic',
        'haircare',
      ],
      'fitness': [
        'fitness',
        'workout',
        'gym',
        'bodybuilding',
        'yoga',
      ],
      'cooking': [
        'cooking',
        'recipe',
        'recipes',
        'baking',
        'chef',
        'kitchen',
      ],
      'travel': [
        'travel',
        'traveling',
        'nomad',
        'wanderlust',
        'backpack',
        'itinerary',
      ],
      'music': [
        'music',
        'song',
        'songs',
        'singer',
        'band',
        'album',
        'concert',
      ],
      'finance': [
        'finance',
        'invest',
        'investing',
        'stocks',
        'crypto',
        'trading',
        'money',
      ],
      'education': [
        'education',
        'tutorial',
        'tutorials',
        'learn',
        'science',
        'history',
        'physics',
        'math',
      ],
      'drama': [
        'drama',
        'soap',
        'telenovela',
      ],
    };
    final out = <String>{};
    families.forEach((family, terms) {
      for (final term in terms) {
        if (RegExp('\\b$term\\b').hasMatch(text)) {
          out.add(family);
          break;
        }
      }
    });
    return out;
  }

  Set<String> _identityVocab(Map<String, dynamic> profile) {
    final buffer = StringBuffer()
      ..write(profile['name'] ?? '')
      ..write(' ')
      ..write(profile['description'] ?? '');
    return _tokenize(buffer.toString());
  }

  Set<String> _tokenize(String text) {
    const stop = <String>{
      'with', 'from', 'this', 'that', 'your', 'about', 'over', 'into',
      'were', 'have', 'will', 'just', 'they', 'them', 'their', 'there',
      'what', 'when', 'where', 'which', 'while', 'video', 'videos',
      'channel', 'youtube', 'tiktok', 'instagram', 'content', 'subscribe',
      'subscribers', 'watch', 'official', 'best', 'more', 'every', 'make',
      'made', 'shorts', 'long', 'live', 'series', 'guest', 'collab',
      'creator', 'creators', 'audience', 'people', 'general', 'world',
      'welcome', 'check', 'follow', 'click', 'here', 'http', 'https',
      'www', 'com', 'new', 'all',
    };
    final out = <String>{};
    for (final raw in text.toLowerCase().split(RegExp('[^a-z0-9]+'))) {
      if (raw.length < 4) continue;
      if (stop.contains(raw)) continue;
      out.add(raw);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Profiling home',
          onPressed: () => context.go('/connect'),
          icon: const Icon(Icons.home_rounded),
        ),
        title: const Text('Collaborator Discovery'),
        actions: [
          IconButton(
            tooltip: 'View channel profile',
            onPressed: () => context.go('/profile/${widget.channelKey}'),
            icon: const Icon(Icons.account_circle_outlined),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.primary.withValues(alpha: 0.06),
              theme.scaffoldBackgroundColor,
            ],
          ),
        ),
        child: _loading
            ? const _LoadingState()
            : _error != null
                ? _ErrorState(error: _error!, onRetry: _load)
                : _matches == null || _matches!.isEmpty
                    ? const _EmptyState()
                    : CustomScrollView(
                        slivers: [
                          SliverToBoxAdapter(
                            child: _DiscoveryHero(
                              channelKey: widget.channelKey,
                              total: _matches!.length,
                              filteredOut: _filteredOut,
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                            sliver: SliverList.builder(
                              itemCount: _matches!.length,
                              itemBuilder: (context, i) => _MatchCard(
                                match: _matches![i],
                                sourceKey: widget.channelKey,
                              ),
                            ),
                          ),
                          if (_hiddenMatches.isNotEmpty) ...[
                            SliverToBoxAdapter(
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                child: OutlinedButton.icon(
                                  onPressed: () => setState(
                                      () => _showHidden = !_showHidden),
                                  icon: Icon(_showHidden
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined),
                                  label: Text(_showHidden
                                      ? 'Hide filtered-out collaborators'
                                      : 'Show ${_hiddenMatches.length} filtered-out collaborators'),
                                ),
                              ),
                            ),
                            if (_showHidden)
                              SliverPadding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 0, 12, 24),
                                sliver: SliverList.builder(
                                  itemCount: _hiddenMatches.length,
                                  itemBuilder: (context, i) => _MatchCard(
                                    match: _hiddenMatches[i],
                                    sourceKey: widget.channelKey,
                                    filterReason: _hiddenMatches[i]
                                        ['_filterReason'] as String?,
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
      ),
    );
  }
}

class _DiscoveryHero extends StatelessWidget {
  const _DiscoveryHero({
    required this.channelKey,
    required this.total,
    required this.filteredOut,
  });

  final String channelKey;
  final int total;
  final int filteredOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.22),
          ),
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.surface,
              theme.colorScheme.primary.withValues(alpha: 0.05),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MVP Discovery Feed',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                letterSpacing: 0.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Ranked collaborators for your channel',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Channel key: $channelKey',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatPill(
                  icon: Icons.radar_rounded,
                  label: '$total candidates',
                ),
                const _StatPill(
                  icon: Icons.analytics_outlined,
                  label: 'Explainable scoring',
                ),
                const _StatPill(
                  icon: Icons.auto_awesome,
                  label: 'AI rationale',
                ),
                if (filteredOut > 0)
                  _StatPill(
                    icon: Icons.filter_alt_off,
                    label: '$filteredOut filtered out',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Scanning channels and ranking fit…',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'We are discovering candidates, blending rule score + AI rationale, and preparing outreach-ready cards.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.68),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry discovery'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.travel_explore_outlined,
              size: 34,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 10),
            Text(
              'No collaborators found yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Try another source channel or broaden your niche and region filters.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.match,
    required this.sourceKey,
    this.filterReason,
  });
  final Map<String, dynamic> match;
  final String sourceKey;
  final String? filterReason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = match['name'] as String? ?? 'Unknown';
    final channelKey = match['channelKey'] as String? ?? '';
    final followers = match['followers'] as num? ?? 0;
    final niche = match['niche'] as String? ?? '';
    final subNiche = match['subNiche'] as String?;
    final region = match['region'] as String? ?? '';
    final score = match['score'] as num? ?? 0;
    final reason = match['reason'] as String? ?? '';
    final mutualTag = match['mutualBenefitTag'] as String? ?? '';
    final aiRationale = match['aiRationale'] as String?;
    final aiCollab = match['aiCollab'] as String?;
    final aiRisks = (match['aiRisks'] as List<dynamic>?)?.cast<String>() ?? [];
    final topics = (match['topics'] as List<dynamic>?)?.cast<String>() ?? [];
    final breakdown = (match['breakdown'] as List<dynamic>?)
        ?.map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final scoreColor = score >= 80
        ? Colors.green
        : score >= 60
            ? Colors.orange
            : Colors.grey;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (filterReason != null) ...[
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer
                      .withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.filter_alt_off_outlined,
                        size: 16, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Filtered out: $filterReason',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Header row: name + score
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_fmtNum(followers)} subscribers • $niche${subNiche != null ? ' → $subNiche' : ''} • $region',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: scoreColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: scoreColor.withValues(alpha: 0.36)),
                  ),
                  child: Text(
                    '${score.toInt()}%',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: scoreColor,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),

            // Mutual benefit tag
            if (mutualTag.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.handshake,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        mutualTag,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Reason
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(reason, style: theme.textTheme.bodySmall),
            ],

            // AI rationale
            if (aiRationale != null) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.auto_awesome, size: 14, color: Colors.amber[700]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      aiRationale,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ),
            ],

            // Suggested collab
            if (aiCollab != null) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.lightbulb_outline,
                    size: 14,
                    color: Colors.teal,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Collab idea: $aiCollab',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],

            // Topics
            if (topics.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: topics
                    .take(6)
                    .map(
                      (t) => Chip(
                        label: Text(t, style: const TextStyle(fontSize: 10)),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    )
                    .toList(),
              ),
            ],

            // Score breakdown
            if (breakdown != null && breakdown.isNotEmpty) ...[
              const SizedBox(height: 10),
              _ScoreBreakdown(breakdown: breakdown),
            ],

            // Risks
            if (aiRisks.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: aiRisks
                    .map(
                      (r) => Chip(
                        avatar: const Icon(Icons.warning_amber, size: 12),
                        label: Text(r, style: const TextStyle(fontSize: 10)),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        backgroundColor: Colors.orange.withValues(alpha: 0.1),
                      ),
                    )
                    .toList(),
              ),
            ],

            // Actions
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.person, size: 16),
                    label: const Text('View Profile'),
                    onPressed: () => context.go('/profile/$channelKey'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.mail_outline, size: 16),
                    label: const Text('Draft Outreach'),
                    onPressed: () =>
                        context.go('/outreach/$sourceKey/$channelKey'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtNum(num value) {
    if (value >= 1e9) return '${(value / 1e9).toStringAsFixed(1)}B';
    if (value >= 1e6) return '${(value / 1e6).toStringAsFixed(1)}M';
    if (value >= 1e3) return '${(value / 1e3).toStringAsFixed(1)}K';
    return value.toStringAsFixed(0);
  }
}

class _ScoreBreakdown extends StatelessWidget {
  const _ScoreBreakdown({required this.breakdown});
  final List<Map<String, dynamic>> breakdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: breakdown.map((b) {
        final label = b['label'] as String? ?? '';
        final value = (b['value'] as num? ?? 0).toDouble();
        final weight = (b['weight'] as num? ?? 0).toInt();
        final barColor = value >= 80
            ? Colors.green
            : value >= 50
                ? Colors.orange
                : Colors.red.shade300;
        return Padding(
          padding: const EdgeInsets.only(bottom: 5),
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
      }).toList(),
    );
  }
}
