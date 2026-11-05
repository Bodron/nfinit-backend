import 'dart:math' as math;

/// Public environmental timing. Waves never reset this round clock.
enum HazardPhase { dormant, warning, active }

class SteamVent {
  const SteamVent(this.id, this.x, this.y, this.width, this.height);
  final String id;
  final double x, y, width, height;
  bool contains(double px, double py) =>
      px >= x && px <= x + width && py >= y && py <= y + height;
}

class SteamHazard {
  const SteamHazard(this.vent, this.phase, this.remaining, this.progress);
  final SteamVent vent;
  final HazardPhase phase;
  final double remaining, progress;
  static const initialDelay = 6.0,
      warningSeconds = 2.0,
      activeSeconds = 3.0,
      restSeconds = 5.0;
  static const cycleSeconds = warningSeconds + activeSeconds + restSeconds;
  static const speedFactor = .60;
  static List<SteamHazard> states(
    List<SteamVent> vents,
    double elapsed, {
    double activeDuration = activeSeconds,
  }) {
    if (vents.isEmpty) return const [];
    final time = math.max(0, elapsed - initialDelay);
    final selected = (time / cycleSeconds).floor() % vents.length;
    final local = time % cycleSeconds;
    return [
      for (var i = 0; i < vents.length; i++)
        if (elapsed < initialDelay ||
            i != selected ||
            local >= warningSeconds + activeDuration)
          SteamHazard(vents[i], HazardPhase.dormant, 0, 0)
        else if (local < warningSeconds)
          SteamHazard(
            vents[i],
            HazardPhase.warning,
            warningSeconds - local,
            local / warningSeconds,
          )
        else
          SteamHazard(
            vents[i],
            HazardPhase.active,
            warningSeconds + activeDuration - local,
            (local - warningSeconds) / activeDuration,
          ),
    ];
  }

  bool affects(double x, double y) =>
      phase == HazardPhase.active && vent.contains(x, y);
  Map<String, dynamic> toJson() => {
    'id': vent.id,
    'x': vent.x,
    'y': vent.y,
    'width': vent.width,
    'height': vent.height,
    'phase': phase.name,
    'remaining': remaining,
    'progress': progress,
  };
}
