import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cohyve/core/theme/app_theme.dart';

/// Renders the public contact points that were parsed from a creator's
/// channel / video descriptions. Each row is tappable (opens the link or a
/// mailto:) and long-press / trailing button copies the value.
///
/// [preferredMethod] (from `draftOutreach`) is highlighted as the recommended
/// way to reach the creator, e.g. `{ method: "email", destination: "..." }`.
class ContactLinks extends StatelessWidget {
  const ContactLinks({required this.contacts, this.preferredMethod, super.key});

  final Map<String, dynamic> contacts;
  final Map<String, dynamic>? preferredMethod;

  /// Which contact key (email/instagram/...) the backend recommended.
  String? get _preferredKey {
    final method = preferredMethod?['method'] as String?;
    if (method == null) return null;
    // preferredMethod uses e.g. "instagram_dm" — take the leading segment.
    return method.split('_').first;
  }

  @override
  Widget build(BuildContext context) {
    final preferred = _preferredKey;
    final rows = <Widget>[];

    void add(String key, IconData icon, String label, String value, String uri) {
      if (value.isEmpty) return;
      rows.add(
        _ContactRow(
          icon: icon,
          label: label,
          value: value,
          uri: uri,
          highlighted: key == preferred,
        ),
      );
    }

    final email = contacts['email'] as String? ?? '';
    add('email', LucideIcons.mail, 'Email', email, 'mailto:$email');

    add(
      'website',
      LucideIcons.globe,
      'Website',
      contacts['website'] as String? ?? '',
      contacts['website'] as String? ?? '',
    );
    add(
      'instagram',
      LucideIcons.camera,
      'Instagram',
      _pretty(contacts['instagram'] as String? ?? ''),
      contacts['instagram'] as String? ?? '',
    );
    add(
      'tiktok',
      LucideIcons.music,
      'TikTok',
      _pretty(contacts['tiktok'] as String? ?? ''),
      contacts['tiktok'] as String? ?? '',
    );
    add(
      'twitter',
      LucideIcons.atSign,
      'Twitter / X',
      _pretty(contacts['twitter'] as String? ?? ''),
      contacts['twitter'] as String? ?? '',
    );
    add(
      'discord',
      LucideIcons.messageCircle,
      'Discord',
      contacts['discord'] as String? ?? '',
      contacts['discord'] as String? ?? '',
    );

    final other = (contacts['other'] as List<dynamic>?)
            ?.map((e) => e as String)
            .where((e) => e.isNotEmpty)
            .toList() ??
        const [];
    for (final url in other) {
      add('other', LucideIcons.link, 'Link', _pretty(url), url);
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          rows[i],
        ],
      ],
    );
  }

  /// Whether any contact point was actually found.
  static bool hasAny(Map<String, dynamic>? contacts) {
    if (contacts == null) return false;
    for (final k in const [
      'email',
      'website',
      'instagram',
      'tiktok',
      'twitter',
      'discord',
    ]) {
      final v = contacts[k];
      if (v is String && v.isNotEmpty) return true;
    }
    final other = contacts['other'];
    return other is List && other.isNotEmpty;
  }

  static String _pretty(String url) {
    var s = url.replaceFirst(RegExp(r'^https?://(www\.)?'), '');
    if (s.endsWith('/')) s = s.substring(0, s.length - 1);
    return s;
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.uri,
    required this.highlighted,
  });

  final IconData icon;
  final String label;
  final String value;
  final String uri;
  final bool highlighted;

  Future<void> _open() async {
    final parsed = Uri.tryParse(uri);
    if (parsed == null) return;
    await launchUrl(parsed, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = BrandingExtended.gradientStart;
    return Material(
      color: highlighted
          ? accent.withValues(alpha: 0.1)
          : theme.colorScheme.surfaceContainer.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _open,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          label,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                        if (highlighted) ...[
                          const SizedBox(width: 6),
                          Icon(LucideIcons.star, size: 12, color: accent),
                          const SizedBox(width: 2),
                          Text(
                            'Recommended',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Copy',
                visualDensity: VisualDensity.compact,
                icon: const Icon(LucideIcons.copy, size: 16),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: value));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$label copied')),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
