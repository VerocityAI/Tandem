import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:tandem/core/data/collections.dart';
import 'package:tandem/core/util/format.dart';
import 'package:tandem/core/widgets/score_ring.dart';

/// Pipeline stages for the lightweight collaborator CRM.
const _statuses = <String, ({String label, IconData icon, Color color})>{
  'new': (label: 'New', icon: Icons.fiber_new, color: Colors.blue),
  'contacted': (label: 'Contacted', icon: Icons.send, color: Colors.orange),
  'replied': (
    label: 'Replied',
    icon: Icons.mark_chat_read,
    color: Colors.green
  ),
  'passed': (
    label: 'Passed',
    icon: Icons.do_not_disturb_on,
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
      appBar: AppBar(title: const Text('Shortlist')),
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
              Icon(Icons.bookmark_border,
                  size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text('No saved collaborators yet',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                'Save promising matches from a channel’s results to track '
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
            onSelected: (_) => ref.read(_filterProvider.notifier).state = null,
          ),
          const SizedBox(width: 8),
          for (final entry in _statuses.entries) ...[
            ChoiceChip(
              avatar:
                  Icon(entry.value.icon, size: 16, color: entry.value.color),
              label: Text('${entry.value.label} (${count(entry.key)})'),
              selected: filter == entry.key,
              onSelected: (_) =>
                  ref.read(_filterProvider.notifier).state = entry.key,
            ),
            const SizedBox(width: 8),
          ],
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
    final repo = ref.read(shortlistRepoProvider);
    final key = entry['channelKey'] as String? ?? '';
    final name = entry['name'] as String? ?? key;
    final niche = entry['niche'] as String? ?? '';
    final followers = entry['followers'] as num? ?? 0;
    final score = entry['score'] as num?;
    final status = entry['status'] as String? ?? 'new';
    final fromKey = entry['fromChannelKey'] as String?;
    final thumbnailUrl = entry['thumbnailUrl'] as String?;
    final meta = _statuses[status] ?? _statuses['new']!;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ChannelAvatar(
                    name: name, niche: niche, imageUrl: thumbnailUrl, size: 40),
                const SizedBox(width: 12),
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
                if (score != null) ScoreRing(score: score.toInt(), size: 40),
              ],
            ),
            const SizedBox(height: 10),
            // Pipeline status selector.
            Wrap(
              spacing: 6,
              children: _statuses.entries.map((e) {
                final sel = e.key == status;
                return ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(e.value.icon,
                      size: 14, color: sel ? Colors.white : e.value.color),
                  label: Text(e.value.label,
                      style: TextStyle(
                          fontSize: 11, color: sel ? Colors.white : null)),
                  selected: sel,
                  selectedColor: meta.color,
                  onSelected: (_) => repo.setStatus(key, e.key),
                );
              }).toList(),
            ),
            const Divider(height: 20),
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.person_outline, size: 16),
                  label: const Text('Profile'),
                  onPressed: () => context.push('/profile/$key'),
                ),
                if (fromKey != null)
                  TextButton.icon(
                    icon: const Icon(Icons.mail_outline, size: 16),
                    label: const Text('Outreach'),
                    onPressed: () => context.push('/outreach/$fromKey/$key'),
                  ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: 'Remove',
                  onPressed: () => repo.remove(key),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
