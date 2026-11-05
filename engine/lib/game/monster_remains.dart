/// Short-lived visual ground decal, independent of removed monster actors.
class MonsterRemains {
  const MonsterRemains(
    this.x,
    this.y,
    this.time,
    this.variant, {
    this.elite = false,
  });
  static const holdSeconds = 1.6, lifetime = 2.0, limit = 48;
  final double x, y, time;
  final int variant;
  final bool elite;

  static double opacity(double age) => age < 0
      ? 0
      : ((lifetime - age) / (lifetime - holdSeconds)).clamp(0.0, 1.0);

  Map<String, dynamic> snapshot(double now) => {
    'x': x,
    'y': y,
    'age': now - time,
    'variant': variant,
    'elite': elite,
  };
}
