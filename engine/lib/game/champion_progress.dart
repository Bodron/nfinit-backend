import 'dart:convert';
import 'dart:math' as math;

import 'heroes.dart';
import 'game_int.dart';
import 'endless_balance.dart';
import 'weapon_progress.dart';
import 'survival.dart';
import 'campaign.dart';
import 'campaign_mastery.dart';
import 'solo_tools.dart';

enum UpgradeTrack { mobility, endurance, focus }

enum UpgradeResult {
  purchased,
  insufficientEssence,
  levelLocked,
  maxed,
  saveFailed,
}

// Native saves retain their existing 64-bit counter range. On the web, counters
// use exact JS integers; growing currencies and XP continue to use GameInt.
final _maxSavedCounter = const bool.fromEnvironment('dart.library.js_interop')
    ? 9007199254740991
    : int.parse('9223372036854775807');

abstract final class ChampionRules {
  static const startingEssence = 60;
  static const legacyCosts = [40, 80, 140, 220, 320];
  static GameInt xpForNext(Object level) =>
      const GameInt(200) +
      GameInt.parse(level) * 120 +
      GameInt.parse(level) * GameInt.parse(level) * 40;
  static GameInt cost(int currentRank) =>
      const GameInt(40) +
      GameInt(currentRank) * 100 +
      GameInt(currentRank) * currentRank * 60;
  static int requiredLevel(int rank) => (GameInt(rank) * 2 - 1).toInt();
  static GameInt xpForLevel(Object level) {
    final n = (GameInt.parse(level) - 1).max(0);
    return n * 200 + n * (n + 1) * 60 + n * (n + 1) * (n * 2 + 1) * 40 ~/ 6;
  }

  static int levelForXp(Object xp) => levelValue(xp).toInt();
  static GameInt levelValue(Object xp) {
    final value = GameInt.parse(xp).exact;
    var low = BigInt.one, high = BigInt.two;
    BigInt threshold(BigInt level) {
      final n = level - BigInt.one;
      return n * BigInt.from(200) +
          n * (n + BigInt.one) * BigInt.from(60) +
          n *
              (n + BigInt.one) *
              (n * BigInt.two + BigInt.one) *
              BigInt.from(40) ~/
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

  static GameInt migrateLegacyXp(int xp) {
    var level = 1, remaining = xp.clamp(0, 2520);
    while (level < 10 && remaining >= 80 + 40 * level) {
      remaining -= 80 + 40 * level++;
    }
    return xpForLevel(level) +
        (xpForNext(level) * remaining ~/ (80 + 40 * level));
  }

  static double effectiveRank(int rank) =>
      math.min(5, math.max(0, rank)).toDouble() +
      2 * math.log(1 + math.max(0, rank - 5) / 2);
  static bool eligible(Map state) =>
      state['mode'] != 'survival' &&
      state['ended'] == true &&
      state['duration'] == 90 &&
      (state['elapsed'] as num? ?? 0) >= 89.999 &&
      ((state['myScore'] as Map?)?['activeSeconds'] as num? ?? 0) >= 15;
}

/// Permanent champion preparation for local runs. Online always selects [base].
class ChampionLoadout {
  const ChampionLoadout({
    this.level = 1,
    this.mobility = 0,
    this.endurance = 0,
    this.focus = 0,
    this.weaponLevel = 1,
    this.weaponForge = 0,
    this.weaponInfusion = 0,
    this.fireMode = FireMode.focused,
    this.exactLevel,
    this.exactWeaponLevel,
  });
  static const base = ChampionLoadout();
  final int level, mobility, endurance, focus, weaponLevel, weaponForge;
  final Object weaponInfusion;
  final FireMode fireMode;
  final GameInt? exactLevel, exactWeaponLevel;
  GameInt get progressionLevel => exactLevel ?? GameInt(level);
  GameInt get progressionWeaponLevel =>
      exactWeaponLevel ?? GameInt(weaponLevel);
  int get ascension => math.max(0, level - 1) ~/ 10;
  double get powerDurationFactor => 1 + .2 * (1 - 1 / (1 + ascension * .1));
  int get weaponCapacity =>
      (const GameInt(2) + progressionLevel + GameInt(focus) * 2)
          .min(progressionWeaponLevel + weaponForge)
          .toInt();
  GameInt get powerIndexTenths => EndlessBalance.championIndex(
    level: progressionLevel,
    weaponLevel: progressionWeaponLevel,
    focus: focus,
    mobility: mobility,
    endurance: endurance,
    forge: weaponForge,
    infusion: weaponInfusion,
    mastery: WeaponRules.masteryRanksExact(progressionWeaponLevel),
  );
  GameInt get powerScore =>
      EndlessBalance.scaled(const GameInt(100), powerIndexTenths);
  double get weaponDamageFactor =>
      EndlessBalance.powerNumerator(powerIndexTenths) /
      EndlessBalance.powerDenominator;
  double get weaponHasteFactor {
    final rank =
        mobility + WeaponRules.masteryRank(weaponLevel, WeaponMastery.cadence);
    return 1 + 1.5 * rank / (rank + 20);
  }

  int get totalRanks => (GameInt(mobility) + endurance + focus).toInt();
  double get speedFactor =>
      1 +
      math.min(5, mobility) * .03 +
      .2 * (1 - math.exp(-math.max(0, mobility - 5) / 20));
  double get maxEnergy => 100 + ChampionRules.effectiveRank(endurance) * 8;
  double get regenFactor => 1 + ChampionRules.effectiveRank(endurance) * .04;
  double get powerCooldownFactor => focus <= 5
      ? 1 - math.max(0, focus) * .03
      : .35 + .5 / (1 + (focus - 5) * .03);
  double get dashCooldownFactor => focus <= 5
      ? 1 - math.max(0, focus) * .04
      : .45 + .35 / (1 + (focus - 5) * .03);
  bool get boosted => level > 1 || mobility > 0 || endurance > 0 || focus > 0;
}

/// Local dungeon milestone; never stores intermediate waves or campaign runs.
class DungeonCheckpoint {
  const DungeonCheckpoint(
    this.wave, {
    this.xp = 0,
    this.damage = 0,
    this.haste = 0,
    this.volley = 0,
  });
  final int wave, xp, damage, haste, volley;
  int get resumeWave => wave + 1;
  Map<String, int> toJson() => {
    'wave': wave,
    'xp': xp,
    'damage': damage,
    'haste': haste,
    'volley': volley,
  };
  static DungeonCheckpoint? decode(dynamic raw) {
    if (raw is! Map) return null;
    int value(String key) => GameInt.parse(raw[key]).max(0).toInt();
    final wave = value('wave');
    if (wave < 25 || wave % 25 != 0) return null;
    final xp = value('xp'),
        damage = value('damage'),
        haste = value('haste'),
        volley = value('volley');
    if (damage + haste + volley > xp ~/ 5) return DungeonCheckpoint(wave);
    return DungeonCheckpoint(
      wave,
      xp: xp,
      damage: damage,
      haste: haste,
      volley: volley,
    );
  }
}

class ChampionState {
  WeaponState weapon = WeaponState();
  DungeonCheckpoint? checkpoint;
  GameInt _xp = GameInt.zero, _investedEssence = GameInt.zero;
  GameInt get xp => _xp;
  set xp(Object value) => _xp = GameInt.parse(value).max(0);
  GameInt get investedEssence => _investedEssence;
  set investedEssence(Object value) =>
      _investedEssence = GameInt.parse(value).max(0);
  final ranks = {for (final track in UpgradeTrack.values) track: 0};
  GameInt get levelExact => ChampionRules.levelValue(xp);
  int get level => levelExact.toInt();
  int get ascension => (level - 1) ~/ 10;
  GameInt get ascensionExact => (levelExact - 1) ~/ 10;
  GameInt get xpInLevel => xp - ChampionRules.xpForLevel(levelExact);
  GameInt get nextLevelXp => ChampionRules.xpForNext(levelExact);
  double get levelProgress => xpInLevel / nextLevelXp;
  int rank(UpgradeTrack track) => ranks[track] ?? 0;
  ChampionLoadout get loadout => ChampionLoadout(
    level: level,
    exactLevel: levelExact,
    weaponLevel: weapon.level,
    exactWeaponLevel: weapon.levelExact,
    weaponForge: weapon.forge,
    weaponInfusion: weapon.infusion,
    fireMode: weapon.mode,
    mobility: rank(UpgradeTrack.mobility),
    endurance: rank(UpgradeTrack.endurance),
    focus: rank(UpgradeTrack.focus),
  );
  GameInt get refund => investedEssence;
}

class ChampionReward {
  ChampionReward({
    required this.hero,
    required Object xp,
    required Object essence,
    required this.oldLevel,
    required this.newLevel,
    this.medals = const [],
    this.unlockedTools = const [],
    this.checkpointWave,
  }) : xp = GameInt.parse(xp),
       essence = GameInt.parse(essence);
  final GameInt xp, essence;
  final int hero, oldLevel, newLevel;
  final List<CampaignMedal> medals;
  final List<SoloTool> unlockedTools;

  /// Set only when this reward advances the champion's dungeon checkpoint.
  final int? checkpointWave;
  bool get leveledUp => newLevel > oldLevel;
}

class ChampionProgress {
  GameInt _essence = const GameInt(ChampionRules.startingEssence);
  GameInt get essence => _essence;
  set essence(Object value) => _essence = GameInt.parse(value).max(0);
  final champions = List.generate(heroes.length, (_) => ChampionState());
  final retiredChampions = <String, dynamic>{};
  final claimed = <String>[];
  final survivalClaims = <String, int>{};
  final weaponClaims = <String, GameInt>{};
  final lootEssenceClaims = <String, GameInt>{};
  int bestWave = 0;
  GameInt bestSurvivalScore = GameInt.zero;
  CampaignProgress campaign = CampaignProgress();
  SoloTool selectedTool = SoloTool.decoy;
  bool toolUnlocked(SoloTool tool) =>
      tool.unlockLevel == 0 || campaign.completed.contains(tool.unlockLevel);
  bool selectTool(SoloTool tool) {
    if (!toolUnlocked(tool)) return false;
    selectedTool = tool;
    return true;
  }

  ChampionState hero(int index) => champions[heroIndex(index)];

  static ChampionProgress decode(String? raw) {
    final result = ChampionProgress();
    if (raw == null) return result;
    try {
      final data = jsonDecode(raw) as Map;
      final legacy = (data['championProgressVersion'] as num? ?? 1) < 2;
      result.essence = GameInt.parse(
        data['essence'] ?? ChampionRules.startingEssence,
      ).max(0);
      final list = data['champions'] as List? ?? [];
      final oldRoster = data['heroRosterVersion'] != 2;
      result.retiredChampions.addAll(
        Map<String, dynamic>.from(data['retiredChampions'] as Map? ?? {}),
      );
      if (oldRoster) {
        for (final slot in [2, 4]) {
          if (slot < list.length) {
            result.retiredChampions['$slot'] = list[slot];
          }
        }
      }
      for (var i = 0; i < result.champions.length; i++) {
        final slot = oldRoster ? heroLegacySlots[i] : i;
        if (slot >= list.length) continue;
        final saved = list[slot] as Map, champion = result.champions[i];
        champion.weapon = WeaponState.decode(saved['weapon']);
        champion.checkpoint = DungeonCheckpoint.decode(
          saved['dungeonCheckpoint'],
        );
        final savedXp = GameInt.parse(saved['xp']).max(0);
        champion.xp = legacy
            ? ChampionRules.migrateLegacyXp(savedXp.toInt())
            : savedXp;
        final ranks = saved['ranks'] as Map? ?? {};
        for (final track in UpgradeTrack.values) {
          champion.ranks[track] = ((ranks[track.name] as num?)?.toInt() ?? 0)
              .clamp(0, ((champion.levelExact + 1) ~/ 2).toInt());
        }
        if (legacy) {
          champion.investedEssence = 0;
          for (final rank in champion.ranks.values) {
            for (var r = 0; r < math.min(5, rank); r++) {
              champion.investedEssence += ChampionRules.legacyCosts[r];
            }
          }
        } else {
          champion.investedEssence = GameInt.parse(saved['investedEssence'])
              .max(0);
        }
      }
      result.campaign = CampaignProgress.decode(data['campaign']);
      final tool = parseSoloTool(data['selectedTool']);
      if (result.toolUnlocked(tool)) result.selectedTool = tool;
      result.bestWave = math.max(0, (data['bestWave'] as num?)?.toInt() ?? 0);
      result.bestSurvivalScore = SurvivalRules.totalPoints(result.bestWave);
      final kills = data['weaponClaims'] as Map? ?? {};
      for (final entry in kills.entries.take(32)) {
        if (entry.key is String) {
          result.weaponClaims[entry.key as String] = GameInt.parse(entry.value)
              .max(0);
        }
      }
      final lootClaims = data['lootEssenceClaims'] as Map? ?? {};
      for (final entry in lootClaims.entries.take(32)) {
        if (entry.key is String) {
          result.lootEssenceClaims[entry.key as String] = GameInt.parse(
            entry.value,
          ).max(0);
        }
      }
      final waves = data['survivalClaims'] as Map? ?? {};
      for (final entry in waves.entries.take(32)) {
        if (entry.key is String && entry.value is int) {
          result.survivalClaims[entry.key as String] = (entry.value as int)
              .clamp(0, _maxSavedCounter);
        }
      }
      result.claimed.addAll(
        (data['claimed'] as List? ?? []).whereType<String>().take(64),
      );
    } on Object {
      return ChampionProgress();
    }
    return result;
  }

  String encode() => jsonEncode({
    'championProgressVersion': 3,
    'heroRosterVersion': 2,
    'retiredChampions': retiredChampions,
    'essence': essence,
    'claimed': claimed,
    'bestWave': bestWave,
    'campaign': campaign.toJson(),
    'selectedTool': selectedTool.name,
    'survivalClaims': survivalClaims,
    'weaponClaims': weaponClaims,
    'lootEssenceClaims': lootEssenceClaims,
    'champions': [
      for (final champion in champions)
        {
          'xp': champion.xp,
          'investedEssence': champion.investedEssence,
          'weapon': champion.weapon.toJson(),
          if (champion.checkpoint != null)
            'dungeonCheckpoint': champion.checkpoint!.toJson(),
          'ranks': {
            for (final track in UpgradeTrack.values)
              track.name: champion.rank(track),
          },
        },
    ],
  });

  ({GameInt weaponXp, GameInt essence}) rewardCombatLoot(
    String runId,
    Map state,
  ) {
    if (state['mode'] != 'survival' || state['demo'] != true) {
      return (weaponXp: GameInt.zero, essence: GameInt.zero);
    }
    final weaponXp = rewardWeapon(runId, state);
    final earned = GameInt.parse(state['lootEssenceEarned']).max(0);
    final previous = lootEssenceClaims[runId] ?? GameInt.zero;
    final gained = (earned - previous).max(0);
    essence += gained;
    if (earned > previous) lootEssenceClaims[runId] = earned;
    if (lootEssenceClaims.length > 32) {
      lootEssenceClaims.remove(lootEssenceClaims.keys.first);
    }
    return (weaponXp: weaponXp, essence: gained);
  }

  GameInt rewardWeapon(String runId, Map state) {
    if (state['mode'] != 'survival' || state['demo'] != true) {
      return GameInt.zero;
    }
    final earned = GameInt.parse(state['weaponXpEarned']).max(0);
    final previous = weaponClaims[runId] ?? GameInt.zero;
    if (earned <= previous) return GameInt.zero;
    final weapon = hero((state['self'] as Map)['skin'] as int? ?? 0).weapon;
    final gained = earned - previous;
    weapon.xp += gained;
    weaponClaims[runId] = earned;
    if (weaponClaims.length > 32) weaponClaims.remove(weaponClaims.keys.first);
    return gained;
  }

  bool forgeWeapon(int index) {
    final weapon = hero(index).weapon;
    final next = weapon.forge + 1;
    if (weapon.level < WeaponRules.requiredLevel(next) ||
        essence < WeaponRules.forgeCost(next)) {
      return false;
    }
    essence -= WeaponRules.forgeCost(next);
    weapon.forge = next;
    return true;
  }

  bool infuseWeapon(int index) {
    final weapon = hero(index).weapon;
    final next = weapon.infusion + 1;
    if (essence < WeaponRules.infusionCost(next)) {
      return false;
    }
    essence -= WeaponRules.infusionCost(next);
    weapon.infusion = next;
    return true;
  }

  bool selectFireMode(int index, FireMode mode) {
    final weapon = hero(index).weapon;
    if (weapon.level < WeaponRules.unlock(mode)) return false;
    weapon.mode = mode;
    return true;
  }

  UpgradeResult canUpgrade(int index, UpgradeTrack track) {
    final champion = hero(index), rank = champion.rank(track);
    if (champion.level < ChampionRules.requiredLevel(rank + 1)) {
      return UpgradeResult.levelLocked;
    }
    if (essence < ChampionRules.cost(rank)) {
      return UpgradeResult.insufficientEssence;
    }
    return UpgradeResult.purchased;
  }

  UpgradeResult upgrade(int index, UpgradeTrack track) {
    final outcome = canUpgrade(index, track);
    if (outcome != UpgradeResult.purchased) return outcome;
    final champion = hero(index), rank = champion.rank(track);
    essence -= ChampionRules.cost(rank);
    champion.investedEssence += ChampionRules.cost(rank);
    champion.ranks[track] = rank + 1;
    return UpgradeResult.purchased;
  }

  GameInt respec(int index) {
    final champion = hero(index), amount = champion.refund;
    essence += amount;
    champion.investedEssence = 0;
    for (final track in UpgradeTrack.values) {
      champion.ranks[track] = 0;
    }
    return amount;
  }

  ChampionReward? completeSurvival(String runId, Map state) {
    if (state['mode'] != 'survival' || state['demo'] != true) return null;
    final levelId = state['campaignLevel'] as int?;
    if (levelId != null && !campaign.isUnlocked(levelId)) return null;
    final level = levelId == null ? null : campaignLevel(levelId);
    final completed = (state['completedWaves'] as int? ?? 0).clamp(
      0,
      level?.waves.length ?? _maxSavedCounter,
    );
    final startWave = level == null
        ? (state['startWave'] as int? ?? 1).clamp(1, _maxSavedCounter)
        : 1;
    final previous = survivalClaims[runId] ?? 0;
    if (completed < previous) return null;
    final medals = <CampaignMedal>[];
    final unlockedTools = <SoloTool>[];
    int? checkpointWave;
    final index = heroIndex(state['self']['skin'] as int? ?? 0),
        champion = hero(index);
    if (level == null && completed > 0) {
      final lastCompleted = startWave + completed - 1;
      final milestone = lastCompleted ~/ 25 * 25;
      if (milestone >= 25 && milestone > (champion.checkpoint?.wave ?? 0)) {
        champion.checkpoint = DungeonCheckpoint.decode({
          'wave': milestone,
          'xp': state['combatXp'] ?? 0,
          'damage': state['damageUpgrades'] ?? 0,
          'haste': state['hasteUpgrades'] ?? 0,
          'volley': state['volleyUpgrades'] ?? 0,
        });
        checkpointWave = champion.checkpoint?.wave;
      }
    }
    final oldLevel = champion.level;
    var gained = GameInt.zero, currency = GameInt.zero;
    if (level == null) {
      gained = EndlessBalance.rewardSum(
        startWave + previous,
        completed - previous,
      );
      currency = EndlessBalance.rewardSum(
        startWave + previous,
        completed - previous,
        essence: true,
      );
    } else {
      for (var wave = previous + 1; wave <= completed; wave++) {
        gained += level.waveXp(wave);
        currency += level.waveEssence(wave);
      }
    }
    if (level != null &&
        state['campaignWon'] == true &&
        completed == level.waves.length) {
      if (campaign.complete(level.id, level.points(completed))) {
        unlockedTools.addAll(
          SoloTool.values.where((tool) => tool.unlockLevel == level.id),
        );
        gained += level.firstClearXp;
        currency += level.firstClearEssence;
      }
      medals.addAll(
        campaign.awardMedals(
          level.id,
          CampaignRunStats.fromJson(state['campaignStats']),
        ),
      );
      gained += medals.length * campaignMedalXp(level.id);
      currency += medals.length * campaignMedalEssence(level.id);
    }
    if (completed == previous &&
        gained <= 0 &&
        currency <= 0 &&
        medals.isEmpty) {
      return null;
    }
    champion.xp += gained;
    essence += currency;
    if (level == null && startWave == 1) {
      bestWave = math.max(bestWave, completed);
      bestSurvivalScore = SurvivalRules.totalPoints(bestWave);
    }
    survivalClaims[runId] = completed;
    if (survivalClaims.length > 32) {
      survivalClaims.remove(survivalClaims.keys.first);
    }
    return ChampionReward(
      hero: index,
      xp: gained,
      essence: currency,
      oldLevel: oldLevel,
      newLevel: champion.level,
      medals: medals,
      unlockedTools: unlockedTools,
      checkpointWave: checkpointWave,
    );
  }

  ChampionReward? complete(String roundId, Map state) {
    if (claimed.contains(roundId) || !ChampionRules.eligible(state)) {
      return null;
    }
    final score = state['myScore'] as Map;
    final active = (score['activeSeconds'] as num).toDouble().clamp(15.0, 90.0);
    final points = (score['score'] as num? ?? 0).toInt().clamp(0, 270);
    final catches = (score['catches'] as num? ?? 0).toInt().clamp(0, 5);
    final index = heroIndex(state['self']['skin'] as int? ?? 0),
        champion = hero(index);
    final oldLevel = champion.level;
    final gained = GameInt(25 + active.floor() + points ~/ 6);
    final currency = 25 + active.floor() ~/ 3 + catches * 3;
    champion.xp += gained;
    essence += currency;
    claimed.add(roundId);
    if (claimed.length > 64) claimed.removeAt(0);
    return ChampionReward(
      hero: index,
      xp: gained,
      essence: currency,
      oldLevel: oldLevel,
      newLevel: champion.level,
    );
  }
}
