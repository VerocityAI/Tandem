import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:cohyve/core/api/api.dart';
import 'package:cohyve/core/data/collections.dart';
import 'package:cohyve/core/theme/app_theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Settings',
          style: TextStyle(
            foreground: Paint()
              ..shader = LinearGradient(
                colors: [BrandingExtended.gradientStart, BrandingExtended.gradientMid],
              ).createShader(const Rect.fromLTWH(0, 0, 300, 70)),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Account info card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          BrandingExtended.gradientStart,
                          BrandingExtended.gradientMid,
                        ],
                      ),
                    ),
                    child: const Icon(LucideIcons.user, size: 26, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Signed in as',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user?.email ?? user?.uid ?? '—',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Account settings
          Text('Account', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(LucideIcons.logOut, color: BrandingExtended.danger),
                  title: const Text('Sign out'),
                  onTap: () => FirebaseAuth.instance.signOut(),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(LucideIcons.rotateCcw, color: BrandingExtended.warning),
                  title: const Text('Reset onboarding'),
                  subtitle: const Text(
                    'Clear your channels, shortlist and saved searches for a '
                    'fresh start. Keeps your account.',
                  ),
                  isThreeLine: true,
                  onTap: () => _resetOnboarding(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Danger zone
          Text('Danger Zone', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: Icon(LucideIcons.trash2, color: BrandingExtended.danger),
              title: const Text(
                'Delete account',
                style: TextStyle(color: BrandingExtended.danger),
              ),
              subtitle: const Text('Permanently removes your data.'),
              onTap: () => _deleteAccount(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _resetOnboarding(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset onboarding?'),
        content: const Text(
          'This removes all your connected channels, shortlist entries and '
          'saved searches so you can start fresh. Your account stays. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      try {
        await ref.read(channelsRepoProvider).resetOnboarding();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Reset complete — starting fresh.')),
          );
        }
      } on Object catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Reset failed: $e')),
          );
        }
      }
    }
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text('This permanently removes your data.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: BrandingExtended.danger)),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await ref.read(apiProvider).deleteAccount();
    }
  }
}
