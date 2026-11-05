import 'dart:math' as math;

/// The same reach and swept landing checks serve preview and simulation.
abstract final class EclipseTargeting {
  static const reach = .24;
  static const dragRadius = 96.0;

  static (double, double) fromDrag(
    double x,
    double y,
    double dx,
    double dy, {
    required double range,
    required double perspective,
  }) {
    final vx = dx / dragRadius, vy = dy / dragRadius / perspective;
    final length = math.sqrt(vx * vx + vy * vy);
    final divisor = math.max(1.0, length);
    return (x + vx / divisor * range, y + vy / divisor * range);
  }

  static bool valid(
    double fromX,
    double fromY,
    double x,
    double y, {
    required double range,
    required bool Function(double, double) canStand,
  }) {
    if (![fromX, fromY, x, y].every((value) => value.isFinite)) return false;
    final dx = x - fromX, dy = y - fromY;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance > range + 1e-9 || !canStand(fromX, fromY)) return false;
    final steps = math.max(1, (distance / .004).ceil());
    for (var i = 1; i <= steps; i++) {
      if (!canStand(fromX + dx * i / steps, fromY + dy * i / steps)) {
        return false;
      }
    }
    return true;
  }
}
