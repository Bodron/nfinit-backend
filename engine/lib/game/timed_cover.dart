/// Staying on a settled side reactivates cloak as soon as its cooldown ends.
abstract final class CoverRules {
  static const duration = 3.0, cooldown = 12.0, settleTime = .25;
  static int side(double x, double y, List<double> wall) {
    if (y >= wall[1] && y <= wall[1] + wall[3]) {
      if (x < wall[0]) return 3;
      if (x > wall[0] + wall[2]) return 1;
    }
    if (x >= wall[0] && x <= wall[0] + wall[2]) {
      if (y < wall[1]) return 0;
      if (y > wall[1] + wall[3]) return 2;
    }
    final distances = [
      (y - wall[1]).abs(),
      (x - wall[0] - wall[2]).abs(),
      (y - wall[1] - wall[3]).abs(),
      (x - wall[0]).abs(),
    ];
    var closest = 0;
    for (var i = 1; i < 4; i++) {
      if (distances[i] < distances[closest]) closest = i;
    }
    return closest;
  }
}

class CoverTimers {
  final readyAt = <int, double>{};
  int? current, active;
  double until = -100, enteredAt = 0;
  void update(int? side, double now) {
    if (active != side || now >= until) active = null;
    if (side != current) {
      current = side;
      enteredAt = now;
    }
    // Brief contact still needs to settle, but an occupant who has already
    // settled must not leave/re-enter when the side finishes cooling down.
    if (side != null &&
        active == null &&
        now - enteredAt >= CoverRules.settleTime &&
        now >= (readyAt[side] ?? 0)) {
      active = side;
      until = now + CoverRules.duration;
      readyAt[side] = until + CoverRules.cooldown;
    }
    readyAt.removeWhere((id, time) => time <= now && id != current);
  }

  bool hidden(int? side, double now) =>
      side != null && active == side && now < until;
  void reset() {
    readyAt.clear();
    current = active = null;
    until = -100;
    enteredAt = 0;
  }

  List<Map<String, dynamic>> snapshot(double now) => [
    for (final entry in readyAt.entries)
      if (entry.value > now)
        {
          'id': entry.key,
          'state': active == entry.key && now < until ? 'active' : 'cooldown',
          'left': active == entry.key && now < until
              ? until - now
              : entry.value - now,
        },
  ];
}
