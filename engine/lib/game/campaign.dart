import 'dart:convert';
import 'dart:math' as math;

import 'campaign_mastery.dart';
import 'chapter_finales.dart';

/// Monster mechanics are shared by simulation, stage previews and HUD cues.
enum MonsterKind { blind, charger, tracker, warden }

extension MonsterDescription on MonsterKind {
  String get title => switch (this) {
    MonsterKind.blind => 'The Blind One',
    MonsterKind.charger => 'The Charger',
    MonsterKind.tracker => 'The Tracker',
    MonsterKind.warden => 'The Warden',
  };
  String get hint => switch (this) {
    MonsterKind.blind => 'Tracks footsteps. Shadows and decoys buy you time.',
    MonsterKind.charger =>
      'Dodge its charge into a wall: stunned enemies take 50% more damage!',
    MonsterKind.tracker => 'Remembers the last echo longer. Change your route.',
    MonsterKind.warden =>
      'Slow, but guards passages. Lure it away from your route.',
  };
}

class CampaignWave {
  const CampaignWave(this.seconds, this.monsters);
  final int seconds;
  final List<MonsterKind> monsters;
}

class CampaignLevel {
  const CampaignLevel(this.id, this.title, this.mapId, this.waves);
  final int id;
  final String title, mapId;
  final List<CampaignWave> waves;
  int get chapter => (id - 1) ~/ 5;
  List<CampaignGoal> get goals => campaignGoals[id - 1];
  bool get finale => id % 5 == 0;
  ChapterFinale? get finalRule => chapterFinales[id];
  int get seconds => waves.fold(0, (sum, wave) => sum + wave.seconds);
  int get firstClearEssence => 40 + id * 6;
  int get firstClearXp => 30 + id * 4;
  int waveXp(int wave) => 15 + id * 2 + wave * 3;
  int waveEssence(int wave) => 10 + id + wave * 2;
  int wavePoints(int wave) => 75 + id * 15 + wave * 25;
  int points(int clearedWaves) => List.generate(
    clearedWaves.clamp(0, waves.length),
    (i) => wavePoints(i + 1),
  ).fold(0, (a, b) => a + b);
  Set<MonsterKind> get monsters => waves.expand((w) => w.monsters).toSet();
}

const campaignChapters = [
  'Shadow Estate',
  'Echoes of the Manor',
  'Midnight Courtyard',
  'The Final Watch',
];
const campaignChapterArt = ['manor', 'manor', 'manor', 'manor'];
const b = MonsterKind.blind,
    c = MonsterKind.charger,
    t = MonsterKind.tracker,
    g = MonsterKind.warden;

/// Twenty authored stages: timed encounters introduce and then combine enemies.
const campaignLevels = <CampaignLevel>[
  CampaignLevel(1, 'First Echo', 'courtyard', [
    CampaignWave(18, [b]),
    CampaignWave(20, [b]),
  ]),
  CampaignLevel(2, 'Two Steps Behind', 'courtyard', [
    CampaignWave(20, [b]),
    CampaignWave(22, [b, b]),
  ]),
  CampaignLevel(3, 'The Red Line', 'courtyard', [
    CampaignWave(20, [c]),
    CampaignWave(24, [c, b]),
  ]),
  CampaignLevel(4, 'Courtyard on Alert', 'courtyard', [
    CampaignWave(24, [b, c]),
    CampaignWave(26, [c, c]),
  ]),
  CampaignLevel(5, 'Gatekeeper', 'courtyard', [
    CampaignWave(22, [g]),
    CampaignWave(25, [g, b]),
    CampaignWave(28, [g, c, b]),
  ]),
  CampaignLevel(6, 'Scent of Danger', 'courtyard', [
    CampaignWave(22, [t]),
    CampaignWave(25, [t, b]),
  ]),
  CampaignLevel(7, 'Among the Roses', 'courtyard', [
    CampaignWave(25, [t, b]),
    CampaignWave(27, [t, c]),
  ]),
  CampaignLevel(8, 'Tracks in the Mist', 'courtyard', [
    CampaignWave(24, [t, t]),
    CampaignWave(27, [t, c]),
    CampaignWave(28, [t, t, b]),
  ]),
  CampaignLevel(9, 'The Living Maze', 'courtyard', [
    CampaignWave(26, [g, t]),
    CampaignWave(28, [t, c, b]),
    CampaignWave(30, [g, t, c]),
  ]),
  CampaignLevel(10, 'Heart of the Estate', 'courtyard', [
    CampaignWave(28, [g, t]),
    CampaignWave(30, [t, t, c]),
    CampaignWave(32, [g, g, t, c]),
  ]),
  CampaignLevel(11, 'Steps in Darkness', 'courtyard', [
    CampaignWave(26, [c, t]),
    CampaignWave(28, [c, c, b]),
    CampaignWave(30, [t, c, g]),
  ]),
  CampaignLevel(12, 'Lantern Chase', 'courtyard', [
    CampaignWave(28, [c, c]),
    CampaignWave(30, [t, c, c]),
    CampaignWave(32, [c, c, g, b]),
  ]),
  CampaignLevel(13, 'Echoes Between Walls', 'courtyard', [
    CampaignWave(28, [t, t, b]),
    CampaignWave(32, [t, t, g]),
    CampaignWave(34, [t, c, g, b]),
  ]),
  CampaignLevel(14, 'No Shortcuts', 'courtyard', [
    CampaignWave(30, [g, g, t]),
    CampaignWave(32, [c, t, t]),
    CampaignWave(35, [g, t, c, c]),
  ]),
  CampaignLevel(15, 'The Midnight Bell', 'courtyard', [
    CampaignWave(28, [c, t, g]),
    CampaignWave(30, [c, c, t]),
    CampaignWave(32, [g, g, t]),
    CampaignWave(36, [g, c, c, t, b]),
  ]),
  CampaignLevel(16, 'Beyond the Gate', 'courtyard', [
    CampaignWave(30, [t, c, g]),
    CampaignWave(32, [t, t, c, b]),
    CampaignWave(35, [g, c, c, t]),
  ]),
  CampaignLevel(17, 'Whispers in the Courtyard', 'courtyard', [
    CampaignWave(32, [t, t, c]),
    CampaignWave(34, [g, t, t, c]),
    CampaignWave(36, [t, t, c, c, b]),
  ]),
  CampaignLevel(18, 'Shadow Siege', 'courtyard', [
    CampaignWave(30, [g, g, c]),
    CampaignWave(32, [t, c, c, b]),
    CampaignWave(34, [g, t, t, c]),
    CampaignWave(36, [g, g, t, c, c]),
  ]),
  CampaignLevel(19, 'The Last Passage', 'courtyard', [
    CampaignWave(32, [t, t, c, g]),
    CampaignWave(34, [c, c, c, b]),
    CampaignWave(36, [g, g, t, t]),
    CampaignWave(38, [g, t, t, c, c]),
  ]),
  CampaignLevel(20, 'Master of the Hunt', 'courtyard', [
    CampaignWave(32, [g, t, c, b]),
    CampaignWave(35, [t, t, c, c]),
    CampaignWave(38, [g, g, t, c, c]),
    CampaignWave(40, [g, g, t, t, c, c]),
  ]),
];

CampaignLevel campaignLevel(int id) {
  if (id < 1 || id > campaignLevels.length) {
    throw RangeError.range(id, 1, campaignLevels.length, 'level');
  }
  return campaignLevels[id - 1];
}

class CampaignProgress {
  final completed = <int>{};
  final bestPoints = <int, int>{};
  final medals = <int, Set<CampaignMedal>>{};
  Set<CampaignMedal> medalsFor(int id) =>
      Set.unmodifiable(medals[id] ?? const <CampaignMedal>{});
  int get medalCount =>
      medals.values.fold(0, (sum, earned) => sum + earned.length);
  List<CampaignMedal> awardMedals(int id, CampaignRunStats stats) {
    if (!completed.contains(id)) return [];
    final earned = medals.putIfAbsent(id, () => <CampaignMedal>{});
    return [
      for (final goal in campaignLevel(id).goals)
        if (goal.achieved(stats) && earned.add(goal.medal)) goal.medal,
    ];
  }

  int get nextLevel => List.generate(
    20,
    (i) => i + 1,
  ).firstWhere((id) => !completed.contains(id), orElse: () => 20);
  bool get finished => completed.length == 20;
  bool isUnlocked(int id) =>
      id >= 1 && id <= 20 && (completed.contains(id) || id == nextLevel);

  static CampaignProgress decode(dynamic raw) {
    final result = CampaignProgress();
    if (raw is! Map) return result;
    final cleared = (raw['completed'] as List? ?? []).whereType<int>().toSet();
    // Only a contiguous path can unlock later stages, including after reload.
    for (var id = 1; id <= 20 && cleared.contains(id); id++) {
      result.completed.add(id);
    }
    final points = raw['bestPoints'] as Map? ?? {};
    for (final entry in points.entries) {
      final id = int.tryParse(entry.key.toString());
      if (id != null && result.completed.contains(id) && entry.value is num) {
        result.bestPoints[id] = math.max(0, (entry.value as num).toInt());
      }
    }
    final savedMedals = raw['medals'];
    if (savedMedals is Map) {
      for (final entry in savedMedals.entries) {
        final id = int.tryParse(entry.key.toString());
        if (id == null ||
            !result.completed.contains(id) ||
            entry.value is! List) {
          continue;
        }
        final names = (entry.value as List).whereType<String>().toSet();
        result.medals[id] = {
          for (final goal in campaignLevel(id).goals)
            if (names.contains(goal.medal.name)) goal.medal,
        };
      }
    }
    return result;
  }

  Map<String, dynamic> toJson() => {
    'completed': completed.toList()..sort(),
    'medals': {
      for (final entry in medals.entries)
        '${entry.key}': entry.value.map((m) => m.name).toList(),
    },
    'bestPoints': {
      for (final entry in bestPoints.entries) '${entry.key}': entry.value,
    },
  };
  String encode() => jsonEncode(toJson());

  bool complete(int id, int points) {
    if (!isUnlocked(id)) return false;
    bestPoints[id] = math.max(bestPoints[id] ?? 0, points);
    return completed.add(id);
  }
}
