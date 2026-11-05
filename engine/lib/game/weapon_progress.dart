import 'dart:math' as math;

import 'game_int.dart';

enum FireMode {
  focused,
  burst,
  fan,
  piercing,
  duplex,
  helix,
  ricochet,
  explosive,
  nova,
  chain,
}

enum ShotPattern { aimed, burst, fan, parallel, helix, radial }

enum HitEffect { direct, piercing, ricochet, explosive, chain }

/// Stable save IDs live in FireMode; all tunable content lives in this catalog.
class FireModeSpec {
  const FireModeSpec(
    this.level,
    this.title,
    this.shots,
    this.powerPercent,
    this.pattern,
    this.effect,
    this.detail,
  );
  final int level, shots, powerPercent;
  final String title, detail;
  final ShotPattern pattern;
  final HitEffect effect;
  // Every mode uses the champion's full firing cadence. Pattern/effect supply
  // its identity; higher unlocks no longer pay a hidden fire-rate penalty.
  double get intervalFactor => 1;
  double get damageFactor => 1.15 * powerPercent / 100 / shots;
}

abstract final class WeaponModeCatalog {
  static const revision = 3;
  static const minimumGainPercent = 115;
  static const entries = <FireMode, FireModeSpec>{
    FireMode.focused: FireModeSpec(
      1,
      'FOCUSED',
      1,
      100,
      ShotPattern.aimed,
      HitEffect.direct,
      'Focused damage on one target.',
    ),
    FireMode.burst: FireModeSpec(
      3,
      'BURST',
      3,
      115,
      ShotPattern.burst,
      HitEffect.direct,
      'Rapid consecutive shots with increased total power.',
    ),
    FireMode.fan: FireModeSpec(
      6,
      'FAN',
      5,
      133,
      ShotPattern.fan,
      HitEffect.direct,
      'A stronger spread that converges on reachable enemies.',
    ),
    FireMode.piercing: FireModeSpec(
      10,
      'PIERCING',
      1,
      153,
      ShotPattern.aimed,
      HitEffect.piercing,
      'Stronger direct hits that pass through monsters.',
    ),
    FireMode.duplex: FireModeSpec(
      15,
      'DUPLEX',
      2,
      222,
      ShotPattern.parallel,
      HitEffect.piercing,
      'Two stronger piercing paths that track the target.',
    ),
    FireMode.helix: FireModeSpec(
      20,
      'HELIX',
      2,
      256,
      ShotPattern.helix,
      HitEffect.piercing,
      'Stronger piercing waves converge on the target.',
    ),
    FireMode.ricochet: FireModeSpec(
      25,
      'RICOCHET',
      1,
      295,
      ShotPattern.aimed,
      HitEffect.ricochet,
      'Powerful hits bounce to up to 3 additional reachable targets.',
    ),
    FireMode.explosive: FireModeSpec(
      30,
      'EXPLOSIVE',
      1,
      340,
      ShotPattern.aimed,
      HitEffect.explosive,
      'Stronger direct hits plus full splash damage to up to 6 nearby enemies.',
    ),
    FireMode.nova: FireModeSpec(
      40,
      'NOVA',
      8,
      391,
      ShotPattern.radial,
      HitEffect.explosive,
      'A powerful homing ring with full splash damage on impact.',
    ),
    FireMode.chain: FireModeSpec(
      50,
      'CHAIN',
      1,
      450,
      ShotPattern.aimed,
      HitEffect.chain,
      'Strongest direct power; arcs to up to 6 nearby enemies without damage decay.',
    ),
  };
  static FireModeSpec spec(FireMode mode) => entries[mode]!;
}

enum WeaponMastery { impact, cadence, multishot }

abstract final class WeaponRules {
  // Every five levels after the initial modes, repeat three useful unlocks.
  // Extra shots have a render budget; later multishot ranks become damage.
  static int masteryRanks(int level) => math.max(0, (level - 10) ~/ 5);
  static int masteryRank(int level, WeaponMastery mastery) =>
      (masteryRanks(level) + 2 - mastery.index) ~/ 3;
  static GameInt masteryRanksExact(Object level) =>
      (GameInt.parse(level) - 10).max(0) ~/ 5;
  static GameInt masteryRankExact(Object level, WeaponMastery mastery) =>
      (masteryRanksExact(level) + 2 - mastery.index) ~/ 3;
  static int nextMilestone(int level) => nextMilestoneExact(level).toInt();
  static GameInt nextMilestoneExact(Object level) {
    final current = GameInt.parse(level);
    var next = masteryRanksExact(level) * 5 + 15;
    for (final mode in FireMode.values) {
      if (current < unlock(mode)) next = next.min(unlock(mode));
    }
    return next;
  }

  static String milestone(Object level) {
    final rewards = <String>[
      for (final mode in FireMode.values)
        if (GameInt.parse(level).compareTo(unlock(mode)) == 0) name(mode),
    ];
    if (GameInt.parse(level) >= 15 &&
        ((GameInt.parse(level) - 10) % 5).compareTo(0) == 0) {
      final kind =
          WeaponMastery.values[((masteryRanksExact(level) - 1) % 3).toInt()];
      final rank = masteryRankExact(level, kind);
      rewards.add(switch (kind) {
        WeaponMastery.impact => 'IMPACT $rank · PERMANENT POWER',
        WeaponMastery.cadence => 'CADENCE $rank · FIRE RATE AND POWER',
        WeaponMastery.multishot =>
          'MULTISHOT $rank · EXTRA SHOTS AND PERMANENT POWER',
      });
    }
    return rewards.join(' + ');
  }

  static int baseShots(FireMode mode) => WeaponModeCatalog.spec(mode).shots;
  static int shots(int level, FireMode mode, [int upgrades = 0]) => math.min(
    9,
    baseShots(mode) +
        masteryRank(level, WeaponMastery.multishot) +
        (mode == FireMode.fan ? upgrades : 0),
  );
  static double masteryDamage(int level, FireMode mode) =>
      1 +
      .1 *
          (masteryRank(level, WeaponMastery.impact) +
              math.max(
                0,
                baseShots(mode) +
                    masteryRank(level, WeaponMastery.multishot) -
                    9,
              ));
  static double masteryHaste(int level) {
    final rank = masteryRank(level, WeaponMastery.cadence);
    return 1 + .5 * rank / (rank + 8);
  }

  static String equippedDescription(int level, FireMode mode) =>
      '${shots(level, mode)} ${shots(level, mode) == 1 ? 'projectile' : 'projectiles'} / ${WeaponModeCatalog.spec(mode).pattern == ShotPattern.burst ? 'burst' : 'shot'} · ${name(mode)}';

  static GameInt infusionCost(Object nextRank) {
    final rank = GameInt.parse(nextRank).max(1);
    return rank * rank * 120;
  }

  static int requiredLevel(int forgeRank) => (GameInt(forgeRank) * 2).toInt();
  static GameInt xpForNext(Object level) =>
      const GameInt(80) +
      GameInt.parse(level) * 60 +
      GameInt.parse(level) * GameInt.parse(level) * 20;
  static GameInt xpForLevel(Object level) {
    final n = (GameInt.parse(level) - 1).max(0);
    return n * 80 + n * (n + 1) * 30 + n * (n + 1) * (n * 2 + 1) * 20 ~/ 6;
  }

  static int level(Object xp) => levelValue(xp).toInt();
  static GameInt levelValue(Object xp) {
    final value = GameInt.parse(xp).exact;
    var low = BigInt.one, high = BigInt.two;
    BigInt threshold(BigInt level) {
      final n = level - BigInt.one;
      return n * BigInt.from(80) +
          n * (n + BigInt.one) * BigInt.from(30) +
          n *
              (n + BigInt.one) *
              (n * BigInt.two + BigInt.one) *
              BigInt.from(20) ~/
              BigInt.from(6);
    }

    while (threshold(high) <= value) {
      high *= BigInt.two;
    }
    while (high - low > BigInt.one) {
      final middle = (low + high) ~/ BigInt.two;
      if (threshold(middle) <= value) {
        low = middle;
      } else {
        high = middle;
      }
    }
    return GameInt.parse(low);
  }

  static int unlock(FireMode mode) => WeaponModeCatalog.spec(mode).level;
  static String name(FireMode mode) => WeaponModeCatalog.spec(mode).title;
  static String description(FireMode mode, {int level = 1}) =>
      '${shots(level, mode)} ${shots(level, mode) == 1 ? 'projectile' : 'projectiles'}. ${WeaponModeCatalog.spec(mode).detail}';
  static GameInt forgeCost(int nextRank) => GameInt(nextRank) * nextRank * 300;
  static int runPoints(int xp) {
    var count = ((math.sqrt(225 + 20.0 * math.max(0, xp)) - 15) / 10).floor();
    GameInt cost(int n) => GameInt(n) * n * 5 + GameInt(n) * 15;
    while (count > 0 && cost(count) > xp) {
      count--;
    }
    while (cost(count + 1) <= xp) {
      count++;
    }
    return count;
  }
}

class WeaponState {
  GameInt _xp = GameInt.zero;
  GameInt get xp => _xp;
  set xp(Object value) => _xp = GameInt.parse(value).max(0);
  int forge = 0;
  GameInt _infusion = GameInt.zero;
  GameInt get infusion => _infusion;
  set infusion(Object value) => _infusion = GameInt.parse(value).max(0);
  FireMode _mode = FireMode.focused;
  String? _futureMode;
  FireMode get mode => _mode;
  set mode(FireMode value) {
    _mode = value;
    _futureMode = null;
  }

  GameInt get levelExact => WeaponRules.levelValue(xp);
  int get level => levelExact.toInt();
  GameInt get xpInLevel => xp - WeaponRules.xpForLevel(levelExact);

  Map<String, dynamic> toJson() => {
    'xp': xp,
    'forge': forge,
    'infusion': infusion,
    'mode': _futureMode ?? mode.name,
  };
  static WeaponState decode(dynamic raw) {
    final result = WeaponState();
    if (raw is! Map) return result;
    int value(String key) => raw[key] is num ? (raw[key] as num).toInt() : 0;
    result.xp = GameInt.parse(raw['xp']).max(0);
    result.forge = value('forge').clamp(0, result.level ~/ 2);
    result.infusion = GameInt.parse(raw['infusion']).max(0);
    if (raw['mode'] is String &&
        !FireMode.values.any((m) => m.name == raw['mode'])) {
      result._futureMode = raw['mode'] as String;
    }
    for (final mode in FireMode.values) {
      if (mode.name == raw['mode'] &&
          result.level >= WeaponRules.unlock(mode)) {
        result.mode = mode;
      }
    }
    return result;
  }
}
