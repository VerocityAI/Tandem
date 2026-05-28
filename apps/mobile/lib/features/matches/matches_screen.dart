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
      final api = ref.read(apiProvider);
      final result = await api.findMatches(channelKey: widget.channelKey);
      final raw = result['matches'] as List<dynamic>? ?? [];
      if (!mounted) return;
      setState(() {
        _matches = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mutual Collaborators')),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Searching YouTube for collaborators…'),
                  SizedBox(height: 8),
                  Text(
                    'Discovering channels, scoring mutual fit,\nand AI-ranking results',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : _matches == null || _matches!.isEmpty
                  ? const Center(child: Text('No collaborators found.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _matches!.length,
                      itemBuilder: (context, i) => _MatchCard(
                        match: _matches![i],
                        sourceKey: widget.channelKey,
                      ),
                    ),
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
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: name + score
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(
                        '${_fmtNum(followers)} subscribers • $niche${subNiche != null ? ' → $subNiche' : ''} • $region',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: scoreColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: scoreColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    '${score.toInt()}%',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: scoreColor, fontSize: 16),
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
                    Icon(Icons.handshake, size: 14, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(mutualTag,
                          style: TextStyle(
                              fontSize: 12, color: theme.colorScheme.primary)),
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
                    child: Text(aiRationale,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontStyle: FontStyle.italic)),
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
                  const Icon(Icons.lightbulb_outline, size: 14, color: Colors.teal),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text('Collab idea: $aiCollab',
                        style: theme.textTheme.bodySmall),
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
                children: topics.take(6).map((t) => Chip(
                  label: Text(t, style: const TextStyle(fontSize: 10)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                )).toList(),
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
                children: aiRisks.map((r) => Chip(
                  avatar: const Icon(Icons.warning_amber, size: 12),
                  label: Text(r, style: const TextStyle(fontSize: 10)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: Colors.orange.withValues(alpha: 0.1),
                )).toList(),
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
                    onPressed: () => context.go('/outreach/$sourceKey/$channelKey'),
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
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(
            children: [
              SizedBox(
                width: 70,
                child: Text('$label ($weight%)',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: value / 100,
                    backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                    color: barColor,
                    minHeight: 6,
                  ),
                ),
              ),
              SizedBox(
                width: 30,
                child: Text('${value.toInt()}',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
