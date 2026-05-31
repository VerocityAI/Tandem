import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tandem/core/api/api.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: const Text('Signed in as'),
            subtitle: Text(user?.email ?? user?.uid ?? '—'),
          ),
          const Divider(),
          ListTile(
            title: const Text('Sign out'),
            onTap: () => FirebaseAuth.instance.signOut(),
          ),
          ListTile(
            title: const Text(
              'Delete account',
              style: TextStyle(color: Colors.red),
            ),
            onTap: () async {
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
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (ok ?? false) {
                await ref.read(apiProvider).deleteAccount();
              }
            },
          ),
        ],
      ),
    );
  }
}
