import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:cohyve/core/api/api.dart';
import 'package:cohyve/core/data/collections.dart';
import 'package:cohyve/core/widgets/contact_links.dart';
import 'package:cohyve/core/widgets/score_ring.dart';
import 'package:cohyve/core/theme/app_theme.dart';

class OutreachScreen extends ConsumerStatefulWidget {
  const OutreachScreen({required this.fromKey, required this.toKey, super.key});
  final String fromKey;
  final String toKey;

  @override
  ConsumerState<OutreachScreen> createState() => _OutreachScreenState();
}

class _OutreachScreenState extends ConsumerState<OutreachScreen>
    with SingleTickerProviderStateMixin {
  final _angleController = TextEditingController();
  final _emailController = TextEditingController();
  Map<String, dynamic>? _from;
  Map<String, dynamic>? _to;
  Map<String, dynamic>? _draft;
  bool _loading = true;
  bool _generating = false;
  bool _contacted = false;
  String? _error;
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _init();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _angleController.dispose();
    _emailController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final db = FirebaseFirestore.instance;
      final results = await Future.wait([
        db.collection('channels').doc(widget.fromKey).get(),
        db.collection('channels').doc(widget.toKey).get(),
      ]);
      _from = results[0].data();
      _to = results[1].data();
      if (mounted) {
        setState(() => _loading = false);
        _controller.forward();
      }
      await _generate();
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final angle = _angleController.text.trim();
      final result = await ref.read(apiProvider).draftOutreach(
            fromKey: widget.fromKey,
            toKey: widget.toKey,
            angle: angle.isEmpty ? null : angle,
          );
      if (mounted) {
        setState(() => _draft = result);
        // Pre-fill the email field if we extracted one from their descriptions.
        final email =
            (result['contacts'] as Map?)?['email'] as String? ?? '';
        if (email.isNotEmpty && _emailController.text.trim().isEmpty) {
          _emailController.text = email;
        }
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _copy(String label, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied')),
    );
  }

  /// The creator's YouTube channel URL (About tab lists their business contact).
  Uri? _channelAboutUrl() {
    final ref = _to?['ref'] as Map<String, dynamic>?;
    final handle = ref?['handle'] as String?;
    final externalId = ref?['externalId'] as String?;
    if (handle != null && handle.startsWith('@')) {
      return Uri.parse('https://www.youtube.com/$handle/about');
    }
    if (externalId != null && externalId.startsWith('UC')) {
      return Uri.parse('https://www.youtube.com/channel/$externalId/about');
    }
    final url = _to?['ref']?['url'] as String?;
    return url != null ? Uri.tryParse(url) : null;
  }

  Future<void> _openChannel() async {
    final url = _channelAboutUrl();
    if (url == null) {
      _snack('Channel link unavailable');
      return;
    }
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      _snack('Could not open the channel');
    }
  }

  String _fullMessage() {
    final d = _draft ?? {};
    final subject = d['subject'] as String? ?? '';
    final message = d['message'] as String? ?? '';
    return 'Subject: $subject\n\n$message';
  }

  Future<void> _emailNow() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _snack('Please enter an email address');
      return;
    }
    // TODO: Implement actual email sending when backend supports it.
    _snack('Email feature coming soon!');
  }

  Future<void> _markContacted() async {
    final repo = ref.read(shortlistRepoProvider);
    await repo.setStatus(
      widget.toKey,
      'contacted',
      fromKey: widget.fromKey,
    );
    setState(() => _contacted = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(LucideIcons.checkCircle, size: 18, color: Colors.white),
              SizedBox(width: 10),
              Text('Marked as contacted'),
            ],
          ),
        ),
      );
    }
  }

  void _shareMessage() {
    final message = _fullMessage();
    Share.share(message);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fromName = _from?['name'] as String? ?? widget.fromKey;
    final toName = _to?['name'] as String? ?? widget.toKey;
    final platform = _to?['platform'] as String? ?? 'youtube';
    final niche = (_to?['niche'] as String? ?? '').trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Outreach'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : FadeTransition(
              opacity: _fadeAnimation,
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Creator info card
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              ChannelAvatar(
                                name: toName,
                                niche: niche,
                                imageUrl: _to?['thumbnailUrl'] as String?,
                                platform: platform,
                                size: 50,
                                showBorder: true,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      toName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                    Text(
                                      niche.isNotEmpty ? niche : platform,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Outreach angle input
                      Text(
                        'Suggested Angle (optional)',
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _angleController,
                        decoration: InputDecoration(
                          hintText: 'e.g., "Gaming setup review"',
                          prefixIcon: Icon(
                            LucideIcons.messageCircle,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 10),

                      // Generate button
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: LinearGradient(
                            colors: [
                              BrandingExtended.gradientStart,
                              BrandingExtended.gradientMid,
                            ],
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _generating ? null : _generate,
                            borderRadius: BorderRadius.circular(14),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: _generating
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: const [
                                          Icon(LucideIcons.sparkles, size: 16, color: Colors.white),
                                          SizedBox(width: 8),
                                          Text(
                                            'Generate Outreach',
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
                      ),

                      if (_error != null && _draft == null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: BrandingExtended.danger.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(LucideIcons.alertTriangle, size: 18, color: BrandingExtended.danger),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: TextStyle(color: BrandingExtended.danger),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      if (_draft != null) ...[
                        const SizedBox(height: 20),
                        // Email preview card
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'AI-Drafted Outreach',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 12),
                                _fieldWithCopy(
                                  context,
                                  'Subject',
                                  _draft!['subject'] as String? ?? '',
                                  () => _copy('Subject', _draft!['subject']),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surfaceContainer,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    _draft!['message'] as String? ?? '',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => _copy('Message', _fullMessage()),
                                        icon: const Icon(LucideIcons.copy, size: 16),
                                        label: const Text('Copy All'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: _shareMessage,
                                        icon: const Icon(LucideIcons.share, size: 16),
                                        label: const Text('Share'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Action buttons
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Builder(
                                  builder: (context) {
                                    final draftContacts =
                                        (_draft?['contacts'] as Map?)?.map(
                                      (k, v) => MapEntry(k.toString(), v),
                                    );
                                    final preferredMethod =
                                        (_draft?['preferredMethod'] as Map?)?.map(
                                      (k, v) => MapEntry(k.toString(), v),
                                    );
                                    final hasContacts =
                                        ContactLinks.hasAny(draftContacts);
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              hasContacts
                                                  ? LucideIcons.contact
                                                  : LucideIcons.mail,
                                              size: 18,
                                              color: theme.colorScheme.primary,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              hasContacts
                                                  ? 'Reach Out'
                                                  : 'Next Steps',
                                              style: theme.textTheme.titleMedium,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        if (hasContacts) ...[
                                          Text(
                                            'Contacts we found in their channel & video '
                                            'descriptions — the recommended one is highlighted.',
                                            style:
                                                theme.textTheme.bodySmall?.copyWith(
                                              color: theme.colorScheme.onSurface
                                                  .withValues(alpha: 0.65),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          ContactLinks(
                                            contacts: draftContacts!,
                                            preferredMethod: preferredMethod,
                                          ),
                                        ] else
                                          Text(
                                            "We couldn't find public contact details in their "
                                            'descriptions. Open their channel to check their About '
                                            'tab, or share the message directly.',
                                            style:
                                                theme.textTheme.bodySmall?.copyWith(
                                              color: theme.colorScheme.onSurface
                                                  .withValues(alpha: 0.65),
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(14),
                                        gradient: LinearGradient(
                                          colors: [
                                            BrandingExtended.gradientStart,
                                            BrandingExtended.gradientMid,
                                          ],
                                        ),
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: _openChannel,
                                          borderRadius: BorderRadius.circular(14),
                                          child: const Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(LucideIcons.externalLink, size: 16, color: Colors.white),
                                                SizedBox(width: 6),
                                                Text(
                                                  'Open channel',
                                                  style: TextStyle(color: Colors.white),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: _shareMessage,
                                      icon: const Icon(LucideIcons.share, size: 16),
                                      label: const Text('Share'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                TextField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: InputDecoration(
                                    labelText: 'Their email (if you have it)',
                                    hintText: 'name@example.com',
                                    prefixIcon: Icon(
                                      LucideIcons.atSign,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                if (!_contacted)
                                  TextButton.icon(
                                    onPressed: _markContacted,
                                    icon: const Icon(LucideIcons.checkCircle, size: 18),
                                    label: const Text('Mark as contacted'),
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
    );
  }

  Widget _fieldWithCopy(
    BuildContext context,
    String label,
    String text,
    VoidCallback onCopy,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: theme.textTheme.labelLarge),
            TextButton.icon(
              onPressed: onCopy,
              icon: const Icon(LucideIcons.copy, size: 14),
              label: const Text('Copy'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            text,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  ThemeData get theme => Theme.of(context);
}
