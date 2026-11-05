import 'dart:math' as math;

/// Purely visual fractions; actual HP and applied damage remain exact integers.
/// Simulation owns timing, so pause and repeated hits preserve the visible edge.
class MonsterDamageTrail {
  static const holdSeconds = .12, drainSeconds = .4;
  double fromFraction = 0, startsAt = -100, _holdUntil = -100;

  static double fractionAt(double health, double from, double age) {
    final current = health.clamp(0.0, 1.0);
    final remaining = (1 - age / drainSeconds).clamp(0.0, 1.0);
    return (current + math.max(0, from - current) * remaining).clamp(
      current,
      1.0,
    );
  }

  double value(double health, double now) =>
      fractionAt(health, fromFraction, now - startsAt);

  /// Called before subtracting a hit. Continuous damage does not restart hold.
  void hit(double beforeFraction, double now) {
    final before = beforeFraction.clamp(0.0, 1.0);
    final visible = value(before, now);
    if (visible <= before + 1e-9) _holdUntil = now + holdSeconds;
    fromFraction = math.max(visible, before);
    startsAt = math.max(now, _holdUntil);
  }

  void reset() {
    fromFraction = 0;
    startsAt = _holdUntil = -100;
  }
}
