import 'dart:math' as math;

/// Hero-neutral, authoritative goals. Merely pressing an ability is not progress.
enum CampaignMedal { moving, shadow, decoy, dash, dodge, cover }

extension CampaignMedalText on CampaignMedal {
  String get title => switch (this) {
    CampaignMedal.moving => 'Always Moving',
    CampaignMedal.shadow => 'Shadow Steps',
    CampaignMedal.decoy => 'False Trail',
    CampaignMedal.dash => 'Dash Escape',
    CampaignMedal.dodge => 'Narrow Dodge',
    CampaignMedal.cover => 'Change Your Cover',
  };
}

class CampaignGoal {
  const CampaignGoal(this.medal, this.target);
  final CampaignMedal medal;
  final int target;
  String get description => switch (medal) {
    CampaignMedal.moving => 'Move for $target seconds during the stage.',
    CampaignMedal.shadow =>
      'Move through shadows for $target seconds. Standing still does not count.',
    CampaignMedal.decoy =>
      'Get a seeker to follow $target ${target == 1 ? 'decoy' : 'decoys'}.',
    CampaignMedal.dash =>
      'Dash away from a nearby seeker $target ${target == 1 ? 'time' : 'times'}.',
    CampaignMedal.dodge =>
      'Avoid $target ${target == 1 ? 'telegraphed charge' : 'telegraphed charges'} by moving out of its path.',
    CampaignMedal.cover => 'Cross $target different shadow zones.',
  };
  double value(CampaignRunStats stats) =>
      stats.value(medal).clamp(0, target).toDouble();
  bool achieved(CampaignRunStats stats) => stats.value(medal) + 1e-7 >= target;
  String progress(CampaignRunStats stats) =>
      '${(value(stats) + 1e-7).floor()}/$target${medal == CampaignMedal.moving || medal == CampaignMedal.shadow ? 's' : ''}';
}

class CampaignRunStats {
  double movingSeconds = 0, shadowSeconds = 0;
  int decoys = 0, dashEscapes = 0, chargeDodges = 0;
  final coverZones = <int>{};
  final _rewardedLures = <int>{};
  double value(CampaignMedal medal) => switch (medal) {
    CampaignMedal.moving => movingSeconds,
    CampaignMedal.shadow => shadowSeconds,
    CampaignMedal.decoy => decoys.toDouble(),
    CampaignMedal.dash => dashEscapes.toDouble(),
    CampaignMedal.dodge => chargeDodges.toDouble(),
    CampaignMedal.cover => coverZones.length.toDouble(),
  };
  void reset() {
    movingSeconds = shadowSeconds = 0;
    decoys = dashEscapes = chargeDodges = 0;
    coverZones.clear();
    _rewardedLures.clear();
  }

  void move(double seconds, Iterable<int> shadows) {
    if (!seconds.isFinite || seconds <= 0) return;
    movingSeconds += seconds;
    if (shadows.isNotEmpty) {
      shadowSeconds += seconds;
      coverZones.addAll(shadows);
    }
  }

  bool followedLure(int token) {
    if (!_rewardedLures.add(token)) return false;
    decoys++;
    return true;
  }

  Map<String, dynamic> toJson() => {
    'moving': movingSeconds,
    'shadow': shadowSeconds,
    'decoy': decoys,
    'dash': dashEscapes,
    'dodge': chargeDodges,
    'cover': coverZones.toList(),
  };
  static CampaignRunStats fromJson(dynamic raw) {
    final result = CampaignRunStats();
    if (raw is! Map) return result;
    double number(String key) {
      final value = raw[key];
      return value is num && value.isFinite
          ? value.toDouble().clamp(0, 100000)
          : 0;
    }

    result.movingSeconds = number('moving');
    result.shadowSeconds = number('shadow');
    result.decoys = number('decoy').floor();
    result.dashEscapes = number('dash').floor();
    result.chargeDodges = number('dodge').floor();
    if (raw['cover'] is List) {
      result.coverZones.addAll(
        (raw['cover'] as List)
            .whereType<int>()
            .where((id) => id >= -4 && id < 1000)
            .take(64),
      );
    }
    return result;
  }
}

const _m = CampaignMedal.moving,
    _s = CampaignMedal.shadow,
    _l = CampaignMedal.decoy,
    _d = CampaignMedal.dash,
    _n = CampaignMedal.dodge,
    _c = CampaignMedal.cover;
const campaignGoals = <List<CampaignGoal>>[
  [CampaignGoal(_m, 15), CampaignGoal(_s, 5), CampaignGoal(_l, 1)],
  [CampaignGoal(_s, 8), CampaignGoal(_c, 3), CampaignGoal(_d, 1)],
  [CampaignGoal(_n, 1), CampaignGoal(_m, 18), CampaignGoal(_l, 1)],
  [CampaignGoal(_n, 2), CampaignGoal(_d, 1), CampaignGoal(_s, 8)],
  [CampaignGoal(_c, 4), CampaignGoal(_l, 1), CampaignGoal(_m, 30)],
  [CampaignGoal(_m, 20), CampaignGoal(_l, 1), CampaignGoal(_s, 8)],
  [CampaignGoal(_d, 1), CampaignGoal(_l, 2), CampaignGoal(_c, 3)],
  [CampaignGoal(_n, 1), CampaignGoal(_s, 10), CampaignGoal(_m, 30)],
  [CampaignGoal(_c, 4), CampaignGoal(_n, 1), CampaignGoal(_l, 2)],
  [CampaignGoal(_n, 2), CampaignGoal(_d, 2), CampaignGoal(_s, 12)],
  [CampaignGoal(_l, 2), CampaignGoal(_m, 35), CampaignGoal(_d, 1)],
  [CampaignGoal(_n, 2), CampaignGoal(_c, 4), CampaignGoal(_s, 10)],
  [CampaignGoal(_s, 12), CampaignGoal(_l, 2), CampaignGoal(_m, 35)],
  [CampaignGoal(_d, 2), CampaignGoal(_n, 2), CampaignGoal(_c, 4)],
  [CampaignGoal(_n, 3), CampaignGoal(_l, 2), CampaignGoal(_s, 15)],
  [CampaignGoal(_m, 35), CampaignGoal(_d, 2), CampaignGoal(_c, 4)],
  [CampaignGoal(_l, 2), CampaignGoal(_s, 15), CampaignGoal(_n, 2)],
  [CampaignGoal(_n, 3), CampaignGoal(_c, 5), CampaignGoal(_m, 40)],
  [CampaignGoal(_d, 3), CampaignGoal(_l, 3), CampaignGoal(_s, 16)],
  [CampaignGoal(_n, 3), CampaignGoal(_d, 3), CampaignGoal(_c, 5)],
];

int campaignMedalXp(int level) => 12 + math.min(20, level);
int campaignMedalEssence(int level) => 15 + math.min(20, level);
