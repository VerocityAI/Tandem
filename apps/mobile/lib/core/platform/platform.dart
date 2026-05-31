// Mirror of packages/shared-types/src/platform.ts — keep field names in sync.

enum Platform { youtube, instagram, tiktok }

extension PlatformX on Platform {
  String get id => switch (this) {
    Platform.youtube => 'youtube',
    Platform.instagram => 'instagram',
    Platform.tiktok => 'tiktok',
  };

  String get label => switch (this) {
    Platform.youtube => 'YouTube',
    Platform.instagram => 'Instagram',
    Platform.tiktok => 'TikTok',
  };

  static Platform fromId(String id) =>
      Platform.values.firstWhere((p) => p.id == id);
}

class ChannelRef {

  factory ChannelRef.fromMap(Map<String, dynamic> m) => ChannelRef(
    platform: PlatformX.fromId(m['platform'] as String),
    externalId: m['externalId'] as String,
    handle: m['handle'] as String,
    url: m['url'] as String,
  );
  const ChannelRef({
    required this.platform,
    required this.externalId,
    required this.handle,
    required this.url,
  });
  final Platform platform;
  final String externalId;
  final String handle;
  final String url;

  String get channelKey => '${platform.id}_$externalId';
}
