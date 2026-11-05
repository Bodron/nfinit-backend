import 'dart:math';

/// Both roles can earn at most 3 points per active second. A capture cashes
/// earned hunting credit, rather than minting a fixed, farmable reward.
abstract final class ScoreRules {
  static const version = 2;
  static const runnerRate = 2.0, hunterRate = 1.0, catchRate = 2.0;
  static const survivalInterval = 10.0, maxCatchBonus = 40.0;
  static const activityGrace = 6.0;
  static const maxRate = 3.0;
}

class RoundScore {
  double flight = 0, survival = 0, search = 0, capture = 0;
  double runnerSeconds = 0, hunterSeconds = 0;
  double activeRunnerSeconds = 0, activeHunterSeconds = 0;
  double pendingSurvival = 0, pendingCapture = 0;
  int timesCaught = 0;
  double? _lastActivity;
  bool? _hunter;
  bool _finished = false;
  double get total => flight + survival + search + capture;
  double get activeSeconds => activeRunnerSeconds + activeHunterSeconds;

  void reset() {
    flight = survival = search = capture = 0;
    runnerSeconds = hunterSeconds = 0;
    activeRunnerSeconds = activeHunterSeconds = 0;
    pendingSurvival = pendingCapture = 0;
    timesCaught = 0;
    _lastActivity = null;
    _hunter = null;
    _finished = false;
  }

  void activity(double now) {
    if (!_finished) _lastActivity = now;
  }

  void assignRole(bool hunter) {
    if (_hunter == hunter || _finished) return;
    // A forced assignment (e.g. hunter disconnect) isn't a failed escape.
    // An actual capture calls caught() first, forfeiting only the pending bonus.
    if (hunter) {
      survival += pendingSurvival;
      pendingSurvival = 0;
    } else {
      pendingCapture = 0;
    }
    _hunter = hunter;
  }

  void advance(
    double elapsed,
    double now, {
    required bool hunter,
    required bool moved,
  }) {
    if (_finished || elapsed <= 0) return;
    assignRole(hunter);
    if (hunter) {
      hunterSeconds += elapsed;
    } else {
      runnerSeconds += elapsed;
    }
    if (moved) activity(now);
    final active = _lastActivity == null
        ? 0.0
        : (min(now, _lastActivity! + ScoreRules.activityGrace) -
                  (now - elapsed))
              .clamp(0.0, elapsed);
    if (active <= 0) return;
    if (hunter) {
      activeHunterSeconds += active;
      search += active * ScoreRules.hunterRate;
      pendingCapture = min(
        ScoreRules.maxCatchBonus,
        pendingCapture + active * ScoreRules.catchRate,
      );
    } else {
      activeRunnerSeconds += active;
      flight += active * ScoreRules.runnerRate;
      pendingSurvival += active;
      while (pendingSurvival + 1e-9 >= ScoreRules.survivalInterval) {
        survival += ScoreRules.survivalInterval;
        pendingSurvival = max(0, pendingSurvival - ScoreRules.survivalInterval);
      }
    }
  }

  double caughtSomeone() {
    if (_finished) return 0;
    final bonus = pendingCapture;
    capture += bonus;
    pendingCapture = 0;
    return bonus;
  }

  void caught() {
    if (_finished) return;
    timesCaught++;
    pendingSurvival = 0;
  }

  void finish(bool hunter) {
    if (_finished) return;
    assignRole(hunter);
    if (!hunter) survival += pendingSurvival;
    pendingSurvival = pendingCapture = 0;
    _finished = true;
  }

  /// Whole points reconcile exactly with the displayed total. Largest-remainder
  /// allocation avoids separately rounding four categories into bonus points.
  Map<String, dynamic> snapshot() {
    final values = [flight, survival, search, capture];
    final parts = [for (final value in values) value.floor()];
    final points = (total + 1e-8).floor();
    final fractions = [0, 1, 2, 3]
      ..sort((a, b) {
        final comparison = (values[b] - parts[b]).compareTo(
          values[a] - parts[a],
        );
        return comparison == 0 ? a.compareTo(b) : comparison;
      });
    final remainder = points - parts.fold<int>(0, (sum, value) => sum + value);
    for (var i = 0; i < remainder; i++) {
      parts[fractions[i]]++;
    }
    return {
      'score': points,
      'runnerScore': parts[0] + parts[1],
      'hunterScore': parts[2] + parts[3],
      'breakdown': {
        'flight': parts[0],
        'survival': parts[1],
        'search': parts[2],
        'capture': parts[3],
      },
      'runnerSeconds': runnerSeconds,
      'hunterSeconds': hunterSeconds,
      'activeSeconds': activeSeconds,
      'timesCaught': timesCaught,
      'pendingSurvival': pendingSurvival,
      'pendingCapture': pendingCapture,
    };
  }
}
