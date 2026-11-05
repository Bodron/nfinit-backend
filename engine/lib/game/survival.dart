import 'dart:math' as math;

import 'campaign.dart';
import 'game_int.dart';
import 'endless_balance.dart';
import 'monster_evolution.dart';

/// Continuous endless waves; only campaign encounters use preparation breaks.
abstract final class SurvivalRules {
  static const breakSeconds = 4.0;
  static const entrySeconds = 1.0;

  /// The canonical map chapter owns the roster, including preview metadata.
  static MonsterKind monsterForWave(int wave) =>
      MonsterEvolution.forSpawn(wave, 0).kind;

  /// New arrivals per wave, added on top of surviving enemies.
  static int hunters(int wave) => EndlessBalance.arrivals(wave);
  static List<MonsterKind> incoming(int wave) => List.generate(
    hunters(wave),
    (i) => MonsterEvolution.forSpawn(wave, i).kind,
  );
  static int seconds(int wave) => 12 + math.min(8, math.max(0, wave - 1));
  static double botPace(int wave) => math.min(1.0, .72 + (wave - 1) * .035);
  static int points(int wave) => 100 + math.min(19, wave - 1) * 25;
  static GameInt xp(int wave) => EndlessBalance.championWaveXp(wave);
  static GameInt essence(int wave) => EndlessBalance.waveEssence(wave);
  static GameInt pointsFrom(int start, int count) =>
      totalPoints(start + count - 1) - totalPoints(start - 1);
  static GameInt totalPoints(int waves) {
    final rising = math.min(20, math.max(0, waves));
    return GameInt(rising) * 100 +
        rising * (rising - 1) ~/ 2 * 25 +
        GameInt(waves - 20).max(0) * points(20);
  }
}
