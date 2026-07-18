import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Circular channel avatar: shows the platform thumbnail when available, with a
/// niche-tinted gradient monogram as the placeholder/fallback. Optionally shows
/// a small platform badge (YouTube / Instagram / TikTok) in the corner.
class ChannelAvatar extends StatelessWidget {
  const ChannelAvatar({
    required this.name,
    this.niche = '',
    this.imageUrl,
    this.platform,
    this.size = 46,
    super.key,
  });

  final String name;
  final String niche;
  final String? imageUrl;
  final String? platform;
  final double size;

  static const _palette = [
    Color(0xFFB11F4B),
    Color(0xFF2563EB),
    Color(0xFF059669),
    Color(0xFFD97706),
    Color(0xFF7C3AED),
    Color(0xFF0891B2),
    Color(0xFFDB2777),
    Color(0xFF4F46E5),
  ];

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    final color =
        _palette[(niche.isEmpty ? name : niche).hashCode.abs() % _palette.length];

    final monogram = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.9), color.withValues(alpha: 0.55)],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.42,
        ),
      ),
    );

    final Widget avatar = (imageUrl == null || imageUrl!.isEmpty)
        ? monogram
        : ClipOval(
            child: CachedNetworkImage(
              imageUrl: imageUrl!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (_, __) => monogram,
              errorWidget: (_, __, ___) => monogram,
            ),
          );

    if (platform == null) return avatar;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(right: -1, bottom: -1, child: _PlatformBadge(platform!, size)),
      ],
    );
  }
}

class _PlatformBadge extends StatelessWidget {
  const _PlatformBadge(this.platform, this.avatarSize);

  final String platform;
  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (platform) {
      'youtube' => (Icons.smart_display, const Color(0xFFFF0000)),
      'instagram' => (Icons.photo_camera, const Color(0xFFE1306C)),
      'tiktok' => (Icons.music_note, const Color(0xFF010101)),
      _ => (Icons.public, Colors.grey),
    };
    final s = (avatarSize * 0.44).clamp(14.0, 22.0);
    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.surface, width: 1.6),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: s * 0.58, color: Colors.white),
    );
  }
}

/// Animated circular fit-score indicator (0–100). Colour reflects strength:
/// green ≥ 80, amber ≥ 60, muted otherwise.
class ScoreRing extends StatelessWidget {
  const ScoreRing({required this.score, this.size = 46, super.key});

  final int score;
  final double size;

  Color _color(BuildContext context) {
    if (score >= 80) return const Color(0xFF16A34A);
    if (score >= 60) return const Color(0xFFF59E0B);
    return Theme.of(context).colorScheme.outline;
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(context);
    final pct = (score.clamp(0, 100)) / 100;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: pct),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, value, __) => CircularProgressIndicator(
                value: value,
                strokeWidth: 4,
                strokeCap: StrokeCap.round,
                backgroundColor: color.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ),
          Text(
            '$score',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: size * 0.3,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small section header used to structure list screens.
class SectionHeader extends StatelessWidget {
  const SectionHeader({required this.title, this.subtitle, this.trailing, super.key});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
