import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:tandem/core/api/api.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({required this.channelKey, super.key});
  final String channelKey;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('channels')
          .doc(channelKey)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Error')),
            body: Center(child: Text('Error: ${snapshot.error}')),
          );
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Scaffold(
            appBar: AppBar(title: const Text('Loading…')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final data = snapshot.data!.data()! as Map<String, dynamic>;
        return _ProfileView(channelKey: channelKey, data: data);
      },
    );
  }
}

class _ProfileView extends ConsumerStatefulWidget {
  const _ProfileView({required this.channelKey, required this.data});
  final String channelKey;
  final Map<String, dynamic> data;

  @override
  ConsumerState<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends ConsumerState<_ProfileView> {
  bool _reprofiling = false;

  Future<void> _reprofile() async {
    final channelRef = widget.data['ref'];
    if (channelRef is! Map) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset & re-profile?'),
        content: const Text(
          'This clears the current AI analysis for this channel and re-runs it '
          'from scratch using the latest data. It may take a moment.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Re-profile'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _reprofiling = true);
    try {
      await ref
          .read(apiProvider)
          .analyzeChannel(Map<String, dynamic>.from(channelRef));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Channel re-profiled.')),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Re-profile failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _reprofiling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final channelKey = widget.channelKey;
    final data = widget.data;
    final name = data['name'] as String? ?? channelKey;
    final description = data['description'] as String? ?? '';
    final followers = data['followers'] as num? ?? 0;
    final views = data['views'] as num?;
    final posts = data['posts'] as num?;
    final engagementPct = data['engagementPct'] as num?;
    final niche = data['niche'] as String? ?? 'Unknown';
    final subNiche = data['subNiche'] as String?;
    final format = data['format'] as String? ?? 'Unknown';
    final region = data['region'] as String? ?? 'Unknown';
    final confidence = data['confidence'] as String? ?? 'low';
    final topics = _toStringList(data['topics']);
    final toneTags = _toStringList(data['toneTags']);
    final contentPillars = _toStringList(data['contentPillars']);
    final audiencePersona = data['audiencePersona'] as String?;
    final brandSafetyNotes = data['brandSafetyNotes'] as String?;
    final idealCollaborator = data['idealCollaboratorProfile'] as String?;
    final redFlags = _toStringList(data['redFlags']);
    final ref = data['ref'] as Map<String, dynamic>?;
    final platform = ref?['platform'] as String? ?? 'youtube';
    final lastProfiled = _formatTimestamp(
      (data['sourceSnapshotAt'] ?? data['updatedAt']) as String?,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          IconButton(
            icon: _reprofiling
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Reset & re-profile',
            onPressed: _reprofiling ? null : _reprofile,
          ),
          IconButton(
            icon: const Icon(Icons.group_add),
            tooltip: 'Find collaborators',
            onPressed: () => context.go('/matches/$channelKey'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_platformIcon(platform), size: 28),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          name,
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      _ConfidenceBadge(confidence: confidence),
                    ],
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.7),),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Stats row
          Row(
            children: [
              Expanded(
                  child: _StatCard(
                      label: 'Subscribers', value: _formatNumber(followers),),),
              const SizedBox(width: 8),
              if (views != null)
                Expanded(
                    child:
                        _StatCard(label: 'Views', value: _formatNumber(views)),),
              if (views != null) const SizedBox(width: 8),
              if (posts != null)
                Expanded(
                    child: _StatCard(
                        label: 'Videos', value: _formatNumber(posts),),),
              if (engagementPct != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _StatCard(
                    label: 'Engagement',
                    value: '${engagementPct.toStringAsFixed(1)}%',
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          // Classification card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Classification',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),),
                  const SizedBox(height: 12),
                  _InfoRow(
                      label: 'Niche',
                      value: subNiche != null ? '$niche → $subNiche' : niche,),
                  _InfoRow(label: 'Format', value: format),
                  _InfoRow(label: 'Region', value: region),
                  if (lastProfiled != null)
                    _InfoRow(label: 'Last profiled', value: lastProfiled),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Topics
          if (topics.isNotEmpty)
            _ChipSection(
                title: 'Topics',
                items: topics,
                color: theme.colorScheme.primary,),

          // Tone tags
          if (toneTags.isNotEmpty)
            _ChipSection(title: 'Tone', items: toneTags, color: Colors.teal),

          // Content pillars
          if (contentPillars.isNotEmpty)
            _ChipSection(
                title: 'Content Pillars',
                items: contentPillars,
                color: Colors.deepPurple,),

          // AI insights
          if (audiencePersona != null ||
              brandSafetyNotes != null ||
              idealCollaborator != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI Insights',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),),
                    if (audiencePersona != null) ...[
                      const SizedBox(height: 12),
                      _InsightBlock(
                          icon: Icons.people,
                          title: 'Audience Persona',
                          text: audiencePersona,),
                    ],
                    if (idealCollaborator != null) ...[
                      const SizedBox(height: 12),
                      _InsightBlock(
                          icon: Icons.handshake,
                          title: 'Ideal Collaborator',
                          text: idealCollaborator,),
                    ],
                    if (brandSafetyNotes != null) ...[
                      const SizedBox(height: 12),
                      _InsightBlock(
                          icon: Icons.shield,
                          title: 'Brand Safety',
                          text: brandSafetyNotes,),
                    ],
                  ],
                ),
              ),
            ),
          ],

          // Red flags
          if (redFlags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              color: theme.colorScheme.error.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber,
                            color: theme.colorScheme.error, size: 20,),
                        const SizedBox(width: 8),
                        Text('Red Flags',
                            style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.error,),),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...redFlags.map((f) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('• ',
                                  style: TextStyle(
                                      color: theme.colorScheme.error,),),
                              Expanded(child: Text(f)),
                            ],
                          ),
                        ),),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Find collaborators CTA
          FilledButton.icon(
            onPressed: () => context.go('/matches/$channelKey'),
            icon: const Icon(Icons.group_add),
            label: const Text('Find collaborators'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  static List<String> _toStringList(dynamic value) {
    if (value is List) return value.map((e) => e.toString()).toList();
    return [];
  }

  static String? _formatTimestamp(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return null;
    final diff = DateTime.now().difference(parsed.toLocal());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    final local = parsed.toLocal();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    return '${local.year}-$mm-$dd';
  }

  static String _formatNumber(num value) {
    if (value >= 1e9) return '${(value / 1e9).toStringAsFixed(1)}B';
    if (value >= 1e6) return '${(value / 1e6).toStringAsFixed(1)}M';
    if (value >= 1e3) return '${(value / 1e3).toStringAsFixed(1)}K';
    return value.toStringAsFixed(0);
  }

  static IconData _platformIcon(String platform) {
    switch (platform) {
      case 'youtube':
        return Icons.play_circle_fill;
      case 'instagram':
        return Icons.camera_alt;
      case 'tiktok':
        return Icons.music_note;
      default:
        return Icons.public;
    }
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Text(value,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),),
            const SizedBox(height: 4),
            Text(label,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),),),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),),),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _ConfidenceBadge extends StatelessWidget {
  const _ConfidenceBadge({required this.confidence});
  final String confidence;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (confidence.toLowerCase()) {
      'high' => (Colors.green, Icons.verified),
      'medium' => (Colors.orange, Icons.check_circle_outline),
      'demo' => (Colors.blue, Icons.science_outlined),
      _ => (Colors.grey, Icons.help_outline),
    };
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(confidence, style: TextStyle(color: color, fontSize: 12)),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ChipSection extends StatelessWidget {
  const _ChipSection(
      {required this.title, required this.items, required this.color,});
  final String title;
  final List<String> items;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: items
                .map((t) => Chip(
                      label: Text(t, style: const TextStyle(fontSize: 12)),
                      backgroundColor: color.withValues(alpha: 0.1),
                      side: BorderSide(color: color.withValues(alpha: 0.3)),
                      visualDensity: VisualDensity.compact,
                    ),)
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _InsightBlock extends StatelessWidget {
  const _InsightBlock(
      {required this.icon, required this.title, required this.text,});
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),),
              const SizedBox(height: 4),
              Text(text, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
