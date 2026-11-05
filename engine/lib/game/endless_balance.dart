import 'dart:math' as math;

import 'game_int.dart';

/// One revisioned power curve for preparation, dungeon depth and economy.
/// P(x) = 1 + .08x + .002x². Indices use tenths, avoiding floating overflow.
abstract final class EndlessBalance {
  static const revision = 2;
  static const championXpBonusDivisor = 6, essenceBonusDivisor = 7;

  /// New class kits add damage, control and sustain. Increase encounter demand
  /// gradually after onboarding, using depth alone rather than player power.
  static int skillPressurePercent(int wave) =>
      100 + math.min(20, math.max(0, wave - 10) ~/ 2);
  static GameInt encounterHealth(GameInt base, int wave) =>
      (base * skillPressurePercent(wave) + 99) ~/ 100;
  static const powerDenominator = 50000;
  static const maxActiveMonsters = 48, maxNewMonsters = 24;
  static GameInt powerNumerator(GameInt indexTenths) {
    final n = indexTenths.max(0);
    return const GameInt(powerDenominator) + n * 400 + n * n;
  }

  static GameInt waveIndex(int wave) => GameInt(wave).max(1) * 10 - 10;
  static GameInt championIndex({
    required Object level,
    required Object weaponLevel,
    int focus = 0,
    int mobility = 0,
    int endurance = 0,
    int forge = 0,
    Object infusion = 0,
    Object mastery = 0,
    int damage = 0,
    int haste = 0,
    int volley = 0,
  }) =>
      (GameInt.parse(level).max(1) - 1) * 20 +
      (GameInt.parse(weaponLevel).max(1) - 1) * 48 +
      GameInt(focus).max(0) * 12 +
      GameInt(forge).max(0) * 12 +
      GameInt(mobility).max(0) * 2 +
      GameInt(endurance).max(0) * 2 +
      GameInt.parse(infusion).max(0) * 10 +
      GameInt.parse(mastery).max(0) * 10 +
      GameInt(damage).max(0) * 10 +
      GameInt(haste).max(0) * 3 +
      GameInt(volley).max(0) * 3;
  static GameInt scaled(GameInt base, GameInt indexTenths) =>
      (base * powerNumerator(indexTenths) + powerDenominator - 1) ~/
      powerDenominator;
  static GameInt championWaveXp(int wave) {
    final w = GameInt(wave).max(1), d = (w - 20).max(0);
    return const GameInt(20) + (w - 1) * 5 + d * d ~/ championXpBonusDivisor;
  }

  static GameInt waveEssence(int wave) {
    final w = GameInt(wave).max(1), d = (w - 20).max(0);
    return const GameInt(15) + (w - 1) * 5 + d * d ~/ essenceBonusDivisor;
  }

  static GameInt killXp(int wave, bool elite) {
    final d = (GameInt(wave) - 20).max(0);
    return (GameInt.one + d * d ~/ 1000) * (elite ? 5 : 1);
  }

  static GameInt killEssence(int wave, bool elite) {
    final d = (GameInt(wave) - 20).max(0);
    return (GameInt.one + d * d ~/ 3000) * (elite ? 5 : 1);
  }

  // Closed-form sums keep reward catch-up independent of the skipped range.
  static GameInt squareSum(GameInt n) =>
      n <= 0 ? GameInt.zero : n * (n + 1) * (n * 2 + 1) ~/ 6;
  static GameInt _floorSquareSum(GameInt n, int divisor) {
    if (n <= 0) return GameInt.zero;
    final count = n ~/ divisor;
    final remainder = (n - count * divisor).toInt();
    var sum = GameInt.zero;
    // Group residues: floor((q*d+r)²/d)=q²*d+2qr+floor(r²/d).
    for (var r = 1; r <= divisor; r++) {
      final terms = count + (r <= remainder ? 1 : 0);
      final last = terms - 1;
      if (terms > 0) {
        sum +=
            squareSum(last) * divisor +
            last * terms * r +
            terms * (r * r ~/ divisor);
      }
    }
    return sum;
  }

  static GameInt rewardSum(int start, int count, {bool essence = false}) {
    if (count <= 0) return GameInt.zero;
    final first = GameInt(start).max(1),
        n = GameInt(count),
        last = first + n - 1;
    final linear = n * (essence ? 15 : 20) + (first + last - 2) * n * 5 ~/ 2;
    final divisor = essence ? essenceBonusDivisor : championXpBonusDivisor;
    return linear +
        _floorSquareSum((last - 20).max(0), divisor) -
        _floorSquareSum((first - 21).max(0), divisor);
  }

  static int arrivals(int wave) =>
      math.min(maxNewMonsters, 1 + math.max(0, wave - 1) ~/ 5);
}
