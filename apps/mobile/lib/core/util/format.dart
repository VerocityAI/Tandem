/// Compact number formatting shared across screens (e.g. 15500 -> "15.5K").
String fmtCount(num value) {
  if (value >= 1e9) return '${(value / 1e9).toStringAsFixed(1)}B';
  if (value >= 1e6) return '${(value / 1e6).toStringAsFixed(1)}M';
  if (value >= 1e3) return '${(value / 1e3).toStringAsFixed(1)}K';
  return value.toStringAsFixed(0);
}

/// Relative "time ago" from an ISO timestamp, or null when unparseable.
String? timeAgo(String? iso) {
  if (iso == null) return null;
  final dt = DateTime.tryParse(iso);
  if (dt == null) return null;
  final d = DateTime.now().difference(dt);
  if (d.inDays >= 365) return '${(d.inDays / 365).floor()}y ago';
  if (d.inDays >= 30) return '${(d.inDays / 30).floor()}mo ago';
  if (d.inDays >= 1) return '${d.inDays}d ago';
  if (d.inHours >= 1) return '${d.inHours}h ago';
  return 'just now';
}
