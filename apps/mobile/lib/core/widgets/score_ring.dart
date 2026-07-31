import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:cohyve/core/branding/branding.g.dart';
import 'package:cohyve/core/theme/app_theme.dart';

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
    this.showBorder = false,
    super.key,
  });

  final String name;
  final String niche;
  final String? imageUrl;
  final String? platform;
  final double size;
  final bool showBorder;

  static const _palette = [
    BrandingExtended.gradientStart, // Violet
    BrandingExtended.gradientMid,   // Pink
    BrandingExtended.gradientEnd,   // Orange
    BrandingExtended.success,       // Green
    BrandingExtended.warning,       // Amber
    BrandingExtended.danger,        // Red
    const Color(0xFF0891B2),        // Cyan
    const Color(0xFF7C3AED),        // Purple
  ];

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    final color =
        _palette[(niche.isEmpty ? name : niche).hashCode.abs() % _palette.length];

    // Gradient monogram
    final monogram = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withValues(alpha: 0.7)],
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

    // Final avatar with optional gradient border
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

    final Widget result = (platform == null)
        ? (showBorder
            ? Container(
                width: size + 4,
                height: size + 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      BrandingExtended.gradientStart,
                      BrandingExtended.gradientMid,
                      BrandingExtended.gradientEnd,
                    ],
                  ),
                ),
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).scaffoldBackgroundColor,
                  ),
                  child: avatar,
                ),
              )
            : avatar)
        : Stack(
            clipBehavior: Clip.none,
            children: [
              avatar,
              Positioned(right: -1, bottom: -1, child: _PlatformBadge(platform!, size)),
            ],
          );

    return result;
  }
}

class _PlatformBadge extends StatelessWidget {
  const _PlatformBadge(this.platform, this.avatarSize);

  final String platform;
  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (platform) {
      'youtube' => (LucideIcons.circlePlay, const Color(0xFFFF0000)),
      'instagram' => (LucideIcons.camera, const Color(0xFFE1306C)),
      'tiktok' => (LucideIcons.music, const Color(0xFF010101)),
      _ => (LucideIcons.link, Colors.grey),
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

/// Animated circular fit-score indicator (0–100) with gradient fill.
/// Colour reflects strength:
///   - green (≥80) — BrandingExtended.success
///   - amber (≥60) — BrandingExtended.warning
///   - gradient otherwise
class ScoreRing extends StatefulWidget {
  const ScoreRing({required this.score, this.size = 46, super.key});

  final int score;
  final double size;

  @override
  State<ScoreRing> createState() => _ScoreRingState();
}

class _ScoreRingState extends State<ScoreRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pct = (widget.score.clamp(0, 100)) / 100;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: widget.size,
            height: widget.size,
            child: AnimatedBuilder(
              animation: _animation,
              builder: (_, __) {
                final value = _animation.value * pct;
                return CustomPaint(
                  size: Size(widget.size, widget.size),
                  painter: _GradientScorePainter(
                    progress: value,
                    score: widget.score,
                  ),
                );
              },
            ),
          ),
          Text(
            '${widget.score}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: widget.size * 0.3,
              color: widget.score >= 80
                  ? BrandingExtended.success
                  : widget.score >= 60
                      ? BrandingExtended.warning
                      : Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _GradientScorePainter extends CustomPainter {
  _GradientScorePainter({
    required this.progress,
    required this.score,
  });

  final double progress;
  final int score;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    final center = Offset(radius, radius);
    final strokeWidth = 4.0;

    // Background circle
    final bgPaint = Paint()
      ..color = score >= 80
          ? BrandingExtended.success.withValues(alpha: 0.15)
          : score >= 60
              ? BrandingExtended.warning.withValues(alpha: 0.15)
              : const Color(0xFF9E9E9E).withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius - strokeWidth / 2, bgPaint);

    // Gradient progress arc
    if (progress > 0) {
      final gradient = LinearGradient(
        colors: score >= 80
            ? [BrandingExtended.success, BrandingExtended.success]
            : score >= 60
                ? [BrandingExtended.warning, BrandingExtended.warning]
                : [BrandingExtended.gradientStart, BrandingExtended.gradientMid],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      );

      final rect = Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);
      final shader = gradient.createShader(rect);

      final progressPaint = Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        rect,
        -math.pi / 2,
        progress * 2 * math.pi,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_GradientScorePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.score != score;
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
