import 'dart:math' as math;

import 'campaign.dart';
import 'game_int.dart';
import 'endless_balance.dart';
import 'heroes.dart';
import 'weapon_progress.dart';
import 'champion_progress.dart';

/// Dungeon depth raises demand; champion level and workshop upgrades set capacity.
abstract final class CombatRules {
  static const attackRange = .42, projectileRadius = .012;
  static double projectileSpeed(WeaponSpec weapon) => weapon.speed * 1.35;

  /// Positive interception time for a target moving at its measured velocity.
  static double interceptTime(
    double rx,
    double ry,
    double vx,
    double vy,
    double speed,
  ) {
    final a = vx * vx + vy * vy - speed * speed;
    final b = 2 * (rx * vx + ry * vy);
    final c = rx * rx + ry * ry;
    if (a.abs() < .000001) {
      return b < -.000001 ? (-c / b).clamp(0.0, .9) : 0;
    }
    final discriminant = b * b - 4 * a * c;
    if (discriminant < 0) return 0;
    final root = math.sqrt(discriminant);
    final times = [
      (-b - root) / (2 * a),
      (-b + root) / (2 * a),
    ].where((t) => t > 0);
    return times.isEmpty ? 0 : times.reduce(math.min).clamp(0.0, .9);
  }

  static int rank(int wave) => 1 + math.max(0, wave - 1) ~/ 4;
  static int effectiveRank(int wave, ChampionLoadout loadout) =>
      math.min(rank(wave), loadout.weaponCapacity);
  static int recommendedLevel(int wave) => math.max(1, 1 + wave ~/ 5);
  static int requiredWeaponLevel(int wave) => math.max(1, 1 + wave ~/ 12);
  static int requiredFocus(int wave) =>
      math.min(math.max(0, wave ~/ 8), recommendedLevel(wave) ~/ 2);
  static int requiredRanks(int wave) => math.max(0, wave ~/ 4);
  static bool canEnter(int wave, ChampionLoadout loadout) =>
      wave <= 1 ||
      loadout.level >= recommendedLevel(wave) &&
          loadout.focus >= requiredFocus(wave) &&
          loadout.totalRanks >= requiredRanks(wave) &&
          loadout.weaponLevel >= requiredWeaponLevel(wave);
  static String entryRequirement(int wave) =>
      'LV. ${recommendedLevel(wave)} · FOCUS ${requiredFocus(wave)} · ${requiredRanks(wave)} UPGRADES · WEAPON LV. ${requiredWeaponLevel(wave)}';
  static double cadenceFactor(ChampionLoadout loadout, int upgrades) {
    final rank =
        loadout.mobility +
        upgrades +
        WeaponRules.masteryRank(loadout.weaponLevel, WeaponMastery.cadence);
    return 1 + 1.5 * rank / (rank + 20);
  }

  static GameInt damage(
    WeaponSpec weapon,
    int wave,
    int upgrades, {
    ChampionLoadout loadout = ChampionLoadout.base,
    int hasteUpgrades = 0,
    int volleyUpgrades = 0,
  }) {
    final index = EndlessBalance.championIndex(
      level: loadout.progressionLevel,
      weaponLevel: loadout.progressionWeaponLevel,
      focus: loadout.focus,
      mobility: loadout.mobility,
      endurance: loadout.endurance,
      forge: loadout.weaponForge,
      infusion: loadout.weaponInfusion,
      mastery: WeaponRules.masteryRanksExact(loadout.progressionWeaponLevel),
      damage: upgrades,
      haste: hasteUpgrades,
      volley: volleyUpgrades,
    );
    // Saved volley ranks retain their offensive contribution in every mode.
    final multiRank =
        GameInt(
          WeaponRules.masteryRank(loadout.weaponLevel, WeaponMastery.multishot),
        ) +
        math.max(0, volleyUpgrades);
    final multi = (multiRank + 1).min(9).toInt();
    final common =
        GameInt(weapon.damage) *
        EndlessBalance.powerNumerator(index) *
        multi *
        115;
    const denominator = EndlessBalance.powerDenominator * 100 * 100;
    var previousVolley = GameInt.zero;
    for (final mode in FireMode.values) {
      final spec = WeaponModeCatalog.spec(mode);
      final nominal =
          (common * spec.powerPercent + denominator - 1) ~/ denominator;
      final minimum =
          (previousVolley * WeaponModeCatalog.minimumGainPercent + 99) ~/ 100;
      final count = WeaponRules.shots(
        loadout.weaponLevel,
        mode,
        volleyUpgrades,
      );
      final perShot = ((nominal.max(minimum) + count - 1) ~/ count).max(1);
      if (mode == loadout.fireMode) return perShot;
      // Include actual integer rounding in the next tier's floor: changing the
      // number of visible projectiles can never quietly reduce total power.
      previousVolley = perShot * count;
    }
    throw StateError('Missing fire mode');
  }

  static GameInt volleyDamage(
    WeaponSpec weapon,
    int wave,
    int upgrades, {
    ChampionLoadout loadout = ChampionLoadout.base,
    int hasteUpgrades = 0,
    int volleyUpgrades = 0,
  }) =>
      damage(
        weapon,
        wave,
        upgrades,
        loadout: loadout,
        hasteUpgrades: hasteUpgrades,
        volleyUpgrades: volleyUpgrades,
      ) *
      shots(weapon, volleyUpgrades, loadout: loadout);

  static GameInt directDps(
    WeaponSpec weapon,
    int wave,
    int upgrades, {
    ChampionLoadout loadout = ChampionLoadout.base,
    int hasteUpgrades = 0,
    int volleyUpgrades = 0,
  }) {
    final volley = volleyDamage(
      weapon,
      wave,
      upgrades,
      loadout: loadout,
      hasteUpgrades: hasteUpgrades,
      volleyUpgrades: volleyUpgrades,
    );
    final seconds = interval(weapon, wave, hasteUpgrades, loadout: loadout);
    return volley * (1000000 / seconds).round() ~/ 1000000;
  }

  static double burstSpacing(double attackInterval, int shots) =>
      math.min(.08, attackInterval / (shots + 1));

  static double interval(
    WeaponSpec weapon,
    int wave,
    int upgrades, {
    ChampionLoadout loadout = ChampionLoadout.base,
  }) =>
      weapon.interval *
      WeaponModeCatalog.spec(loadout.fireMode).intervalFactor /
      cadenceFactor(loadout, upgrades);
  static int shots(
    WeaponSpec weapon,
    int upgrades, {
    ChampionLoadout loadout = ChampionLoadout.base,
  }) => WeaponRules.shots(loadout.weaponLevel, loadout.fireMode, upgrades);
  static GameInt health(
    MonsterKind kind,
    int wave,
    bool elite, {
    bool endless = true,
  }) {
    final base = switch (kind) {
      MonsterKind.blind => 6,
      MonsterKind.tracker => 8,
      MonsterKind.charger => 10,
      MonsterKind.warden => 16,
    };
    final expectedWeaponLevel = requiredWeaponLevel(wave);
    final reference = ChampionLoadout(
      weaponLevel: expectedWeaponLevel,
      mobility: wave ~/ 12,
    );
    final expectedShots = 1 + ((expectedWeaponLevel - 10) / 15).clamp(0.0, 8.0);
    final referenceDps = cadenceFactor(reference, 0) * expectedShots;
    final baseHealth =
        EndlessBalance.scaled(
          GameInt(base * (elite ? 2 : 1)),
          EndlessBalance.waveIndex(wave),
        ) *
        referenceDps;
    return endless
        ? EndlessBalance.encounterHealth(baseHealth, wave)
        : baseHealth;
  }

  static int earnedUpgrades(int xp) => WeaponRules.runPoints(xp);
}
