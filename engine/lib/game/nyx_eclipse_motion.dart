import 'dart:math' as math;

/// Shared simulation and presentation timing for Eclipse's two cuts and landing.
abstract final class NyxEclipseMotion {
  static const duration = .70;

  /// Local forward/side offsets. Short bursts settle before each damage beat.
  static (double, double) offset(double age) {
    const times = [0.0, .06, .14, .24, .34, .44, .70];
    const points = [
      (0.0, 0.0),
      (0.0, 0.0),
      (.025, .065),
      (.025, .065),
      (.025, -.065),
      (.025, -.065),
      (0.0, 0.0),
    ];
    if (age <= 0 || age >= duration) return (0, 0);
    for (var i = 1; i < times.length; i++) {
      if (age > times[i]) continue;
      final t = ((age - times[i - 1]) / (times[i] - times[i - 1])).clamp(
        0.0,
        1.0,
      );
      final ease = t * t * (3 - 2 * t);
      return (
        points[i - 1].$1 + (points[i].$1 - points[i - 1].$1) * ease,
        points[i - 1].$2 + (points[i].$2 - points[i - 1].$2) * ease,
      );
    }
    return (0, 0);
  }

  static double approach(double age) {
    final t = ((age - .06) / .08).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  static bool dashing(double age) =>
      age >= .06 && age < .14 || age >= .24 && age < .34;

  /// A stable beat number lets the existing dash renderer emit one burst per cut.
  static int cut(double age) => age < .06
      ? 0
      : age < .24
      ? 1
      : 2;

  static double dashEnvelope(double age) {
    final phase = age >= .06 && age < .14
        ? (age - .06) / .08
        : age >= .24 && age < .34
        ? (age - .24) / .10
        : 0.0;
    return math.sin(phase * math.pi).clamp(0.0, 1.0);
  }

  /// Brief visual dissolution; it never grants invisibility or invulnerability.
  static double visibility(double age) => 1 - .94 * dashEnvelope(age);

  static double jump(double age) => age > .44 && age < duration
      ? math.sin((age - .44) / (duration - .44) * math.pi) * .30
      : 0;
  static double lean(double age) => dashing(age) ? (age < .2 ? -.16 : .16) : 0;
}
