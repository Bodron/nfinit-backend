/// Optional hold-to-open objective. Progress decays when the player retreats.
class TreasureChest {
  TreasureChest({
    required this.id,
    required this.wave,
    required this.x,
    required this.y,
  });
  static const channelSeconds = 2.5;
  static const radius = .045;
  final int id, wave;
  final double x, y;
  double progress = 0;
  double? openedAt;
  bool get opened => openedAt != null;

  /// Returns true exactly once, when the lid opens and loot should be spawned.
  bool advance(double delta, double now, {required bool channeling}) {
    if (opened) return false;
    progress =
        (progress +
                (channeling ? delta / channelSeconds : -delta / channelSeconds))
            .clamp(0.0, 1.0);
    if (progress < 1) return false;
    openedAt = now;
    return true;
  }

  Map<String, dynamic> snapshot(double now) => {
    'id': id,
    'x': x,
    'y': y,
    'progress': progress,
    'opened': opened,
    'openAge': openedAt == null ? null : now - openedAt!,
  };
}
