import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:cohyve/core/api/api.dart';
import 'package:cohyve/core/data/collections.dart';
import 'package:cohyve/core/theme/app_theme.dart';

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen>
    with SingleTickerProviderStateMixin {
  final _urlController = TextEditingController();
  bool _analyzing = false;
  String? _error;
  String? _selectedPlatform;
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
    _urlController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _analyse() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _analyzing = true;
      _error = null;
    });

    try {
      final api = ref.read(apiProvider);
      final channelRef = await api.detectChannel(url);
      if (channelRef == null) {
        if (mounted) {
          setState(() => _error =
              "Couldn't find that channel. Check the handle or URL and try again.");
        }
        return;
      }
      await api.analyzeChannel(channelRef);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(LucideIcons.checkCircle, size: 18, color: Colors.white),
                SizedBox(width: 10),
                Text('Channel analysed!'),
              ],
            ),
          ),
        );
        if (mounted) context.pop();
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  String _detectPlatform(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('youtube') || lower.contains('youtu.be')) return 'youtube';
    if (lower.contains('instagram')) return 'instagram';
    if (lower.contains('tiktok')) return 'tiktok';
    return 'youtube'; // default
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect Channel'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(24),
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
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              BrandingExtended.gradientStart,
                              BrandingExtended.gradientMid,
                            ],
                          ),
                        ),
                        child: const Icon(LucideIcons.link, size: 32, color: Colors.white),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Connect a Channel',
                        style: theme.textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Paste a YouTube, Instagram, or TikTok URL to analyse a creator channel.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Platform selector
                Text(
                  'Platform',
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _PlatformChip(
                      label: 'YouTube',
                      icon: LucideIcons.circlePlay,
                      selected: _selectedPlatform == 'youtube',
                      onTap: () => setState(() => _selectedPlatform = 'youtube'),
                    ),
                    const SizedBox(width: 8),
                    _PlatformChip(
                      label: 'Instagram',
                      icon: LucideIcons.camera,
                      selected: _selectedPlatform == 'instagram',
                      onTap: () => setState(() => _selectedPlatform = 'instagram'),
                    ),
                    const SizedBox(width: 8),
                    _PlatformChip(
                      label: 'TikTok',
                      icon: LucideIcons.music,
                      selected: _selectedPlatform == 'tiktok',
                      onTap: () => setState(() => _selectedPlatform = 'tiktok'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // URL input
                Text(
                  'Channel URL or Handle',
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    hintText: 'https://youtube.com/@channel or @handle',
                    prefixIcon: Icon(
                      LucideIcons.search,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    suffixIcon: _urlController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(LucideIcons.x, color: theme.colorScheme.onSurfaceVariant),
                            onPressed: () => _urlController.clear(),
                          )
                        : null,
                  ),
                  onChanged: (value) {
                    if (_selectedPlatform == null && value.isNotEmpty) {
                      setState(() => _selectedPlatform = _detectPlatform(value));
                    }
                  },
                ),
                const SizedBox(height: 16),

                // Analyse button
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
                      onTap: _analyzing ? null : _analyse,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: _analyzing
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(LucideIcons.scan, size: 18, color: Colors.white),
                                    SizedBox(width: 10),
                                    Text(
                                      'Analyse Channel',
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
                ),

                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: BrandingExtended.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: BrandingExtended.danger.withValues(alpha: 0.2),
                      ),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlatformChip extends StatelessWidget {
  const _PlatformChip({
    required this.label,
    required this.icon,
    required this.selected,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? BrandingExtended.gradientStart
              : Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? BrandingExtended.gradientStart
                : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
