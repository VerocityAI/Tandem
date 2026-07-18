import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:tandem/core/api/api.dart';
import 'package:tandem/core/data/collections.dart';
import 'package:tandem/core/util/format.dart';
import 'package:tandem/core/widgets/score_ring.dart';

/// "My Channels" — the home/Discover tab. Lists the channels the user has
/// analysed and routes into their matches. First-run shows guided onboarding.
class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelsAsync = ref.watch(connectedChannelsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
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
              icon: const Icon(Icons.add),
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
        key.startsWith('${platform}_') ? key.substring(platform.length + 1) : key;
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
    return ok ?? false;
  }

  /// Removes the channel and shows an Undo snackbar that restores it.
  Future<void> _removeWithUndo(
      BuildContext context, WidgetRef ref, String key, String name) async {
    final repo = ref.read(channelsRepoProvider);
    final snapshot = Map<String, dynamic>.from(channel);
    await repo.removeChannel(key);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Removed "$name"'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => repo.restoreChannel(snapshot),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final key =
        channel['channelKey'] as String? ?? channel['id'] as String? ?? '';
    final name = channel['name'] as String? ?? key;
    final niche = channel['niche'] as String? ?? '';
    final followers = channel['followers'] as num? ?? 0;
    final thumbnailUrl = channel['thumbnailUrl'] as String?;
    final platform = channel['platform'] as String?;
    return Dismissible(
      key: ValueKey('channel_$key'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmRemove(context, name),
      onDismissed: (_) => _removeWithUndo(context, ref, key, name),
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: theme.colorScheme.error.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Remove', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            SizedBox(width: 8),
            Icon(Icons.delete_outline, color: Colors.white),
          ],
        ),
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: ChannelAvatar(
            name: name,
            niche: niche,
            imageUrl: thumbnailUrl,
            platform: platform,
          ),
          title:
              Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            '${fmtCount(followers)} subscribers${niche.isNotEmpty ? ' • $niche' : ''}',
          ),
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              switch (value) {
                case 'matches':
                  context.push('/matches/$key');
                case 'profile':
                  context.push('/profile/$key');
                case 'reanalyse':
                  await _reanalyse(context, ref, key);
                case 'remove':
                  if (await _confirmRemove(context, name) && context.mounted) {
                    await _removeWithUndo(context, ref, key, name);
                  }
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'matches',
                child: ListTile(
                  leading: Icon(Icons.diversity_3),
                  title: Text('Find collaborators'),
                ),
              ),
              PopupMenuItem(
                value: 'profile',
                child: ListTile(
                  leading: Icon(Icons.person_outline),
                  title: Text('View profile'),
                ),
              ),
              PopupMenuItem(
                value: 'reanalyse',
                child: ListTile(
                  leading: Icon(Icons.refresh),
                  title: Text('Re-analyse'),
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'remove',
                child: ListTile(
                  leading: Icon(Icons.delete_outline, color: Colors.red),
                  title: Text('Remove', style: TextStyle(color: Colors.red)),
                ),
              ),
            ],
          ),
          onTap: () => context.push('/matches/$key'),
        ),
      ),
    );
  }
}

/// Guided first-run empty state.
class _Onboarding extends StatelessWidget {
  const _Onboarding();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.travel_explore,
                  size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                'Find your next collab',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Paste any YouTube channel to analyse it, then get a ranked list '
                'of compatible collaborators — each with an explainable fit score.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              const _OnboardingSteps(),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.push('/connect'),
                icon: const Icon(Icons.analytics_outlined),
                label: const Text('Analyse your first channel'),
              ),
            ],
          ),
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
      (Icons.link, 'Connect', 'Paste your channel URL or @handle'),
      (Icons.auto_awesome, 'Analyse', 'AI profiles your niche & audience'),
      (Icons.diversity_3, 'Match', 'Get ranked, explained collaborators'),
    ];
    return Column(
      children: [
        for (final s in steps)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.12),
                  child: Icon(s.$1,
                      size: 18, color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.$2,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
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
