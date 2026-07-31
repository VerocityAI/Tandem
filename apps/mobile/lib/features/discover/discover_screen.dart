import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:cohyve/core/api/api.dart';
import 'package:cohyve/core/data/collections.dart';
import 'package:cohyve/core/util/format.dart';
import 'package:cohyve/core/widgets/score_ring.dart';
import 'package:cohyve/core/theme/app_theme.dart';

/// "My Channels" — the home/Discover tab. Lists the channels the user has
/// analysed and routes into their matches. First-run shows guided onboarding.
class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelsAsync = ref.watch(connectedChannelsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Discover',
          style: TextStyle(
            foreground: Paint()
              ..shader = LinearGradient(
                colors: [BrandingExtended.gradientStart, BrandingExtended.gradientMid],
              ).createShader(const Rect.fromLTWH(0, 0, 300, 70)),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus),
            tooltip: 'Analyse a channel',
            onPressed: () => context.push('/connect'),
          ),
        ],
      ),
      body: channelsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (channels) {
          if (channels.isEmpty) return const _Onboarding();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SectionHeader(
                title: 'Your channels',
                subtitle: 'Tap a channel to find collaborators.',
              ),
              ...channels.asMap().entries.map(
                    (e) => _ChannelCard(channel: e.value)
                        .animate()
                        .fadeIn(delay: (60 * e.key).ms, duration: 280.ms)
                        .slideY(begin: 0.08, end: 0, curve: Curves.easeOut),
                  ),
            ],
          );
        },
      ),
      floatingActionButton: channelsAsync.valueOrNull?.isNotEmpty ?? false
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/connect'),
              icon: const Icon(LucideIcons.plus),
              label: const Text('Analyse channel'),
            )
          : null,
    );
  }
}

class _ChannelCard extends ConsumerWidget {
  const _ChannelCard({required this.channel});
  final Map<String, dynamic> channel;

  Future<void> _reanalyse(BuildContext context, WidgetRef ref, String key) async {
    final platform = channel['platform'] as String? ?? 'youtube';
    // channelKey == "<platform>_<externalId>"
    final externalId =
        key.startsWith('${platform}_') ? key.substring(platform.length + 1) : '';
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Re-analysing…')),
    );
    try {
      await ref
          .read(apiProvider)
          .analyzeChannel({'platform': platform, 'externalId': externalId},
              force: true);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Channel re-analysed.')),
        );
      }
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Re-analyse failed: $e')),
        );
      }
    }
  }

  Future<bool> _confirmRemove(BuildContext context, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove channel?'),
        content: Text(
          'Remove "$name" from your channels? You can add it again anytime by '
          'analysing it. Your shortlist is not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _openProfile(BuildContext context, String key) async {
    context.push('/profile/$key');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final key = channel['channelKey'] as String? ?? channel['id'] as String? ?? '';
    final name = channel['name'] as String? ?? key;
    final followers = (channel['followers'] as num? ?? 0).toInt();
    final score = (channel['score'] as num? ?? 0).toInt();
    final platform = channel['platform'] as String? ?? 'youtube';
    final niche = (channel['niche'] as String? ?? '').trim();

    return Card(
      child: InkWell(
        onTap: () => _openProfile(context, key),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              ChannelAvatar(
                name: name,
                niche: niche,
                imageUrl: channel['thumbnailUrl'] as String?,
                platform: platform,
                size: 54,
                showBorder: true,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
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
              if (score > 0) ScoreRing(score: score, size: 40),
              IconButton(
                icon: const Icon(LucideIcons.chevronRight),
                onPressed: () => _openProfile(context, key),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Onboarding extends StatelessWidget {
  const _Onboarding();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Gradient orb with icon
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    BrandingExtended.gradientStart.withValues(alpha: 0.3),
                    BrandingExtended.gradientMid.withValues(alpha: 0.15),
                  ],
                ),
              ),
              child: const Icon(
                LucideIcons.radio,
                size: 56,
                color: BrandingExtended.gradientStart,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No channels yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Analyse your first YouTube, Instagram, or TikTok channel '
              'to start discovering high-fit collaborators with transparent scoring.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            Container(
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
                  onTap: () => context.push('/connect'),
                  borderRadius: BorderRadius.circular(16),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.scan, size: 18, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'Analyse your first channel',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const _OnboardingSteps(),
          ],
        ),
      ),
    );
  }
}

class _OnboardingSteps extends StatelessWidget {
  const _OnboardingSteps();

  @override
  Widget build(BuildContext context) {
    const steps = [
      (LucideIcons.link, 'Connect', 'Paste your channel URL or @handle'),
      (LucideIcons.flaskConical, 'Analyse', 'AI profiles your niche & audience'),
      (LucideIcons.users, 'Match', 'Get ranked, explained collaborators'),
    ];
    return Column(
      children: [
        for (final s in steps)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        BrandingExtended.gradientStart.withValues(alpha: 0.15),
                        BrandingExtended.gradientMid.withValues(alpha: 0.08),
                      ],
                    ),
                  ),
                  child: Icon(s.$1, size: 20, color: BrandingExtended.gradientStart),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        s.$3,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.6),
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
