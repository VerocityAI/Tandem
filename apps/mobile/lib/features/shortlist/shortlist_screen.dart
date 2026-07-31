import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:cohyve/core/data/collections.dart';
import 'package:cohyve/core/util/format.dart';
import 'package:cohyve/core/widgets/score_ring.dart';
import 'package:cohyve/core/theme/app_theme.dart';

/// Pipeline stages for the lightweight collaborator CRM.
const _statuses = <String, ({String label, IconData icon, Color color})>{
  'new': (label: 'New', icon: LucideIcons.sparkles, color: BrandingExtended.gradientStart),
  'contacted': (label: 'Contacted', icon: LucideIcons.send, color: BrandingExtended.gradientMid),
  'replied': (
    label: 'Replied',
    icon: LucideIcons.messageCircle,
    color: BrandingExtended.success
  ),
  'passed': (
    label: 'Passed',
    icon: LucideIcons.xCircle,
    color: Colors.grey
  ),
};

final _filterProvider = StateProvider.autoDispose<String?>((ref) => null);

class ShortlistScreen extends ConsumerWidget {
  const ShortlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(shortlistProvider);
    final filter = ref.watch(_filterProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Shortlist',
          style: TextStyle(
            foreground: Paint()
              ..shader = LinearGradient(
                colors: [BrandingExtended.gradientStart, BrandingExtended.gradientMid],
              ).createShader(const Rect.fromLTWH(0, 0, 300, 70)),
          ),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (all) {
          if (all.isEmpty) {
            return _empty(theme);
          }
          final items = filter == null
              ? all
              : all.where((e) => (e['status'] ?? 'new') == filter).toList();
          return Column(
            children: [
              _FilterBar(all: all),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child:
                            Text('No ${_statuses[filter]?.label ?? ''} items'),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                        children:
                            items.map((e) => _ShortlistCard(entry: e)).toList(),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _empty(ThemeData theme) => Center(
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
                  LucideIcons.heart,
                  size: 48,
                  color: BrandingExtended.gradientStart,
                ),
              ),
              const SizedBox(height: 12),
              Text('No saved collaborators yet',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                'Save promising matches from a channel\'s results to track '
                'your outreach here.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      );
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.all});
  final List<Map<String, dynamic>> all;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(_filterProvider);
    int count(String s) => all.where((e) => (e['status'] ?? 'new') == s).length;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          ChoiceChip(
            label: Text('All (${all.length})'),
            selected: filter == null,
            onSelected:
                (selected) => ref.read(_filterProvider.notifier).state = null,
            avatar: Icon(LucideIcons.list, size: 14),
          ),
          const SizedBox(width: 6),
          for (final entry in _statuses.entries)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(entry.value.label),
                selected: filter == entry.key,
                onSelected: (selected) =>
                    ref.read(_filterProvider.notifier).state = entry.key,
                avatar: Icon(entry.value.icon, size: 14, color: entry.value.color),
                selectedColor: entry.value.color,
              ),
            ),
        ],
      ),
    );
  }
}

class _ShortlistCard extends ConsumerWidget {
  const _ShortlistCard({required this.entry});
  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final key = entry['channelKey'] as String? ?? entry['id'] as String? ?? '';
    final fromKey = entry['fromChannelKey'] as String?;
    final name = entry['name'] as String? ?? key;
    final followers = (entry['followers'] as num? ?? 0).toInt();
    final score = (entry['score'] as num? ?? 0).toInt();
    final status = entry['status'] as String? ?? 'new';
    final niche = (entry['niche'] as String? ?? '').trim();
    final platform = entry['platform'] as String? ?? 'youtube';

    final meta = _statuses[status];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ChannelAvatar(
                  name: name,
                  niche: niche,
                  imageUrl: entry['thumbnailUrl'] as String?,
                  platform: platform,
                  size: 48,
                  showBorder: true,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(
                        '${fmtCount(followers)} subs'
                        '${niche.isNotEmpty ? ' • $niche' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                if (score != null) ScoreRing(score: score, size: 40),
              ],
            ),
            const SizedBox(height: 10),
            // Pipeline status selector.
            Wrap(
              spacing: 6,
              children: _statuses.entries.map((e) {
                final sel = e.key == status;
                return FilterChip(
                  label: Text(e.value.label),
                  selected: sel,
                  selectedColor: e.value.color,
                  onSelected: (_) => ref.read(shortlistRepoProvider).setStatus(key, e.key),
                  avatar: Icon(e.value.icon, size: 14, color: sel ? Colors.white : e.value.color),
                  checkmarkColor: Colors.white,
                );
              }).toList(),
            ),
            const Divider(height: 20),
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(LucideIcons.user, size: 16),
                  label: const Text('Profile'),
                  onPressed: () => context.push('/profile/$key'),
                ),
                if (fromKey != null)
                  TextButton.icon(
                    icon: const Icon(LucideIcons.mail, size: 16),
                    label: const Text('Outreach'),
                    onPressed: () => context.push('/outreach/$fromKey/$key'),
                  ),
                const Spacer(),
                IconButton(
                  icon: const Icon(LucideIcons.trash2, size: 20),
                  tooltip: 'Remove',
                  onPressed: () => ref.read(shortlistRepoProvider).remove(key),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
