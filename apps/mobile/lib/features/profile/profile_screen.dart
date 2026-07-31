import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:cohyve/core/api/api.dart';
import 'package:cohyve/core/widgets/contact_links.dart';
import 'package:cohyve/core/widgets/score_ring.dart';
import 'package:cohyve/core/theme/app_theme.dart';

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

class _ProfileViewState extends ConsumerState<_ProfileView>
    with SingleTickerProviderStateMixin {
  bool _reprofiling = false;
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
          .analyzeChannel(Map<String, dynamic>.from(channelRef), force: true);
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
    final followers = (data['followers'] as num? ?? 0).toInt();
    final views = (data['views'] as num? ?? 0).toInt();
    final posts = (data['posts'] as num? ?? 0).toInt();
    final engagementPct = (data['engagementPct'] as num? ?? 0).toDouble();
    final niche = data['niche'] as String? ?? 'Unknown';
    final subNiche = data['subNiche'] as String?;
    final format = data['format'] as String? ?? 'Unknown';
    final region = data['region'] as String? ?? 'Unknown';
    final platform = data['platform'] as String? ?? 'youtube';
    final imageUrl = data['thumbnailUrl'] as String?;
    final contentPillars = (data['contentPillars'] as List<dynamic>?)
        ?.map((e) => e as String)
        .toList()
        .where((e) => e.isNotEmpty)
        .toList()
        .take(5)
        .toList();
    final insights = (data['insights'] as List<dynamic>?)
        ?.map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final score = (data['score'] as num? ?? 0).toInt();
    final confidence = (data['confidence'] as String? ?? '').toLowerCase();
    final idealCollaborator =
        (data['idealCollaboratorProfile'] as String? ?? '').trim();
    final audiencePersona = (data['audiencePersona'] as String? ?? '').trim();
    final brandSafetyNotes = (data['brandSafetyNotes'] as String? ?? '').trim();
    final language = (data['language'] as String? ?? '').trim();
    final uploadsPerMonth = (data['uploadsPerMonth'] as num?)?.toDouble();
    final topics = (data['topics'] as List<dynamic>?)
        ?.map((e) => e as String)
        .where((e) => e.isNotEmpty)
        .take(8)
        .toList();
    final toneTags = (data['toneTags'] as List<dynamic>?)
        ?.map((e) => e as String)
        .where((e) => e.isNotEmpty)
        .take(6)
        .toList();
    final contacts = (data['contacts'] as Map?)
        ?.map((k, v) => MapEntry(k.toString(), v));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Channel Profile'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            tooltip: 'Re-profile',
            onPressed: _reprofiling ? null : _reprofile,
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
              children: [
                // Header with gradient border avatar
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        BrandingExtended.gradientStart.withValues(alpha: 0.1),
                        BrandingExtended.gradientMid.withValues(alpha: 0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    children: [
                      ChannelAvatar(
                        name: name,
                        niche: niche,
                        imageUrl: imageUrl,
                        platform: platform,
                        size: 80,
                        showBorder: true,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        name,
                        style: theme.textTheme.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (subNiche?.isNotEmpty ?? false) ...[
                            Chip(
                              avatar: Icon(LucideIcons.hash, size: 12, color: BrandingExtended.gradientStart),
                              label: Text(subNiche!),
                              visualDensity: VisualDensity.compact,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Chip(
                            avatar: Icon(
                              platform == 'youtube'
                                  ? LucideIcons.circlePlay
                                  : platform == 'instagram'
                                      ? LucideIcons.camera
                                      : LucideIcons.music,
                              size: 12,
                              color: platform == 'youtube'
                                  ? const Color(0xFFFF0000)
                                  : platform == 'instagram'
                                      ? const Color(0xFFE1306C)
                                      : Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            label: Text(platform),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      if (confidence.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _ConfidenceBadge(confidence),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Primary action — the whole point of the app.
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: [
                        BrandingExtended.gradientStart,
                        BrandingExtended.gradientMid,
                        BrandingExtended.gradientEnd,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: BrandingExtended.gradientStart.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => context.push('/matches/$channelKey'),
                      borderRadius: BorderRadius.circular(16),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(LucideIcons.sparkles, size: 18, color: Colors.white),
                            SizedBox(width: 10),
                            Text(
                              'Find Collaborators',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Stats grid with gradient cards
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Key Metrics',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 2.4,
                          children: [
                            _StatCard(
                              icon: LucideIcons.users,
                              label: 'Followers',
                              value: _fmtCount(followers),
                              color: BrandingExtended.gradientStart,
                            ),
                            _StatCard(
                              icon: LucideIcons.play,
                              label: 'Views',
                              value: _fmtCount(views),
                              color: BrandingExtended.gradientMid,
                            ),
                            _StatCard(
                              icon: LucideIcons.video,
                              label: 'Posts',
                              value: _fmtCount(posts),
                              color: BrandingExtended.gradientEnd,
                            ),
                            _StatCard(
                              icon: LucideIcons.heart,
                              label: 'Engagement',
                              value: '${engagementPct.toStringAsFixed(1)}%',
                              color: BrandingExtended.success,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Score ring with gradient
                if (score > 0) ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          BrandingExtended.gradientStart.withValues(alpha: 0.1),
                          BrandingExtended.gradientMid.withValues(alpha: 0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Overall Score',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(width: 16),
                        ScoreRing(score: score, size: 56),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Content info
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Content Details',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        _InfoRow(
                          icon: LucideIcons.tag,
                          label: 'Niche',
                          value: niche,
                          color: BrandingExtended.gradientStart,
                        ),
                        _InfoRow(
                          icon: LucideIcons.layoutTemplate,
                          label: 'Format',
                          value: format,
                          color: BrandingExtended.gradientMid,
                        ),
                        _InfoRow(
                          icon: LucideIcons.globe,
                          label: 'Region',
                          value: region,
                          color: BrandingExtended.gradientEnd,
                        ),
                        if (language.isNotEmpty)
                          _InfoRow(
                            icon: LucideIcons.languages,
                            label: 'Language',
                            value: language.toUpperCase(),
                            color: BrandingExtended.gradientStart,
                          ),
                        if (uploadsPerMonth != null && uploadsPerMonth > 0)
                          _InfoRow(
                            icon: LucideIcons.calendarClock,
                            label: 'Cadence',
                            value: '${uploadsPerMonth.toStringAsFixed(1)} posts/mo',
                            color: BrandingExtended.gradientMid,
                          ),
                        if (contentPillars != null && contentPillars.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _ChipSection(
                            title: 'Content Pillars',
                            items: contentPillars,
                            color: BrandingExtended.gradientStart,
                          ),
                        ],
                        if (topics != null && topics.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _ChipSection(
                            title: 'Topics',
                            items: topics,
                            color: BrandingExtended.gradientMid,
                          ),
                        ],
                        if (toneTags != null && toneTags.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _ChipSection(
                            title: 'Tone',
                            items: toneTags,
                            color: BrandingExtended.gradientEnd,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Public contact points parsed from the channel/video descriptions.
                if (ContactLinks.hasAny(contacts)) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(LucideIcons.contact, size: 18,
                                  color: BrandingExtended.gradientStart),
                              const SizedBox(width: 8),
                              Text('Contact', style: theme.textTheme.titleMedium),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ContactLinks(contacts: contacts!),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Ideal collaborator — who this creator should partner with.
                if (idealCollaborator.isNotEmpty) ...[
                  _HighlightCard(
                    icon: LucideIcons.users,
                    title: 'Ideal Collaborator',
                    text: idealCollaborator,
                    color: BrandingExtended.gradientStart,
                  ),
                  const SizedBox(height: 16),
                ],

                // Audience persona.
                if (audiencePersona.isNotEmpty) ...[
                  _HighlightCard(
                    icon: LucideIcons.userCheck,
                    title: 'Audience',
                    text: audiencePersona,
                    color: BrandingExtended.gradientMid,
                  ),
                  const SizedBox(height: 16),
                ],

                // Brand safety notes.
                if (brandSafetyNotes.isNotEmpty) ...[
                  _HighlightCard(
                    icon: LucideIcons.shieldCheck,
                    title: 'Brand Safety',
                    text: brandSafetyNotes,
                    color: BrandingExtended.success,
                  ),
                  const SizedBox(height: 16),
                ],

                // AI Insights
                if (insights != null && insights.isNotEmpty) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'AI Insights',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          ...insights.map((i) => _InsightBlock(
                                icon: LucideIcons.sparkles,
                                title: i['title'] as String? ?? '',
                                text: i['text'] as String? ?? '',
                              )),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Description
                if (description.isNotEmpty) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'About',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            description,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _fmtCount(int value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toString();
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text('$label: ', style: TextStyle(fontWeight: FontWeight.w600)),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({
    required this.icon,
    required this.title,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(text, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _ConfidenceBadge extends StatelessWidget {
  const _ConfidenceBadge(this.confidence);
  final String confidence;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon) = switch (confidence) {
      'high' => (BrandingExtended.success, LucideIcons.verified),
      'medium' => (BrandingExtended.warning, LucideIcons.check),
      'demo' => (BrandingExtended.gradientStart, LucideIcons.flaskConical),
      _ => (Theme.of(context).colorScheme.onSurfaceVariant, LucideIcons.helpCircle),
    };
    return Chip(
      avatar: Icon(icon, size: 14, color: color),
      label: Text(confidence, style: TextStyle(color: color, fontSize: 11)),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ChipSection extends StatelessWidget {
  const _ChipSection({
    required this.title,
    required this.items,
    required this.color,
  });

  final String title;
  final List<String> items;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
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
    );
  }
}

class _InsightBlock extends StatelessWidget {
  const _InsightBlock({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: BrandingExtended.gradientStart),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(text, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
