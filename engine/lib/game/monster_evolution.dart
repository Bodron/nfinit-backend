import 'dart:math' as math;

import 'campaign.dart';

enum MonsterSkill {
  fireFan(
    'Ember Fan',
    'Three fire bolts. Dodge sideways after the warning.',
    0xffff965c,
  ),
  frostLance(
    'Frost Lance',
    'An ice bolt briefly slows you. Sidestep before it fires.',
    0xff78d9f2,
  ),
  stormStrike(
    'Storm Strike',
    'Lightning hits the glowing ground. Move away before it strikes.',
    0xffbe9aff,
  ),
  thornRing(
    'Thorn Ring',
    'A ring of thorns surrounds the caster. Retreat beyond it.',
    0xffa2df78,
  ),
  venomPool(
    'Venom Pool',
    'A toxic pool lingers on marked ground. Keep moving.',
    0xff74df91,
  ),
  meteorLine(
    'Meteor Trail',
    'Three meteor impacts follow a line. Dodge across it.',
    0xffffa15b,
  ),
  riftOrbs(
    'Rift Orbs',
    'Three orbiting spheres surround the oracle. Keep your distance.',
    0xffd58bff,
  ),
  tempestBurst(
    'Tempest Burst',
    'Four lightning bolts fire outward. Dodge between the bolts.',
    0xff72d7ff,
  ),
  railBeam(
    'Prism Rail',
    'A fixed laser fires after the cyan warning. Sidestep the line or take cover.',
    0xff72e8f2,
  ),
  magneticWell(
    'Gravity Well',
    'A gravity field pulls toward its core. Move away before it activates.',
    0xffce98ff,
  ),
  proximityMines(
    'Proximity Mines',
    'Three mines arm on marked ground. A blinking mine explodes after a short fuse.',
    0xffffbd65,
  ),
  hunterDrones(
    'Hunter Drones',
    'Two drones turn toward you. Break line of sight to make them lose their lock.',
    0xffbbf478,
  );

  const MonsterSkill(this.title, this.hint, this.color);
  final String title, hint;
  final int color;
  bool get tech => index >= MonsterSkill.railBeam.index;
  bool get holdsCaster =>
      this == MonsterSkill.riftOrbs || this == MonsterSkill.railBeam;
  List<double> shotAngles(double angle) => switch (this) {
    MonsterSkill.fireFan => [angle - .22, angle, angle + .22],
    MonsterSkill.frostLance => [angle],
    MonsterSkill.tempestBurst => [
      for (var i = 0; i < 4; i++) angle + i * math.pi / 2,
    ],
    MonsterSkill.hunterDrones => [angle - .45, angle + .45],
    _ => const [],
  };
  double get windup => switch (this) {
    MonsterSkill.frostLance => .8,
    MonsterSkill.railBeam || MonsterSkill.hunterDrones => 1.1,
    MonsterSkill.magneticWell || MonsterSkill.proximityMines => 1.2,
    _ => 1.0,
  };
  double get cooldown => switch (this) {
    MonsterSkill.venomPool ||
    MonsterSkill.magneticWell ||
    MonsterSkill.hunterDrones => 9,
    MonsterSkill.railBeam || MonsterSkill.proximityMines => 8,
    _ => 7,
  };
  double get activeSeconds => switch (this) {
    MonsterSkill.venomPool => 3,
    MonsterSkill.railBeam => .65,
    MonsterSkill.magneticWell => 2,
    MonsterSkill.proximityMines => 4.4,
    MonsterSkill.riftOrbs => 2.4,
    MonsterSkill.meteorLine => 1.05,
    _ => .55,
  };
}

enum MonsterAdornment { embers, crystals, sparks, thorns }

/// A content entry can replace a procedural form with its own atlas later,
/// while retaining an existing AI archetype until bespoke behavior is added.
class MonsterForm {
  const MonsterForm({
    required this.ordinal,
    required this.kind,
    required this.name,
    required this.color,
    required this.adornment,
    this.atlasKey,
    this.ability,
  });
  final int ordinal;
  final MonsterKind kind;
  final String name;
  final int color;
  final MonsterAdornment adornment;
  final String? atlasKey;
  final MonsterSkill? ability;
  String get badge => skill.tech
      ? 'TECH · M$generation'
      : '${switch (adornment) {
          MonsterAdornment.embers => 'EMBER',
          MonsterAdornment.crystals => 'FROST',
          MonsterAdornment.sparks => 'STORM',
          MonsterAdornment.thorns => 'THORNS',
        }} · M$generation';
  MonsterSkill get skill => ability ?? MonsterSkill.values[(ordinal - 1) % 8];
  bool get nativePalette => ordinal <= MonsterEvolution.authoredCount;
  int get unlockWave => 1 + (ordinal - 1) * MonsterEvolution.interval;
  int get generation => 1 + (ordinal - 1) ~/ MonsterEvolution.baseKinds.length;
}

abstract final class MonsterEvolution {
  static const interval = 25;
  static const wavesPerMap = 100, formsPerMap = 4;
  static const chapterMapIds = ['courtyard', 'volcano', 'tech'];
  static const atlasPaths = {
    'lantern_wraith': 'assets/art/monster_lantern_wraith_v2.png',
    'frostfang': 'assets/art/monster_frostfang_v1.png',
    'stormwing_moth': 'assets/art/monster_stormwing_moth_v1.png',
    'thornshell': 'assets/art/monster_thornshell_v1.png',
    'venom': 'assets/art/monster_venom_v2.png',
    'golem': 'assets/art/monster_golem_v1.png',
    'oracle': 'assets/art/monster_oracle_v1.png',
    'wyvern': 'assets/art/monster_wyvern_v1.png',
    'rail_sentinel': 'assets/art/monster_rail_sentinel_v1.png',
    'magnetron': 'assets/art/monster_magnetron_v1.png',
    'siege_crawler': 'assets/art/monster_siege_crawler_v1.png',
    'hive_overseer': 'assets/art/monster_hive_overseer_v1.png',
  };
  // Keep existing form identities stable when the AI enum gains new kinds.
  static const baseKinds = [
    MonsterKind.blind,
    MonsterKind.charger,
    MonsterKind.tracker,
    MonsterKind.warden,
  ];
  // Authored monsters go here with stable ordinals and optional dedicated art.
  static const authoredCount = 12;
  static const authoredForms = <int, MonsterForm>{
    1: MonsterForm(
      ordinal: 1,
      kind: MonsterKind.blind,
      name: 'Lantern Wraith',
      color: 0xffff965c,
      adornment: MonsterAdornment.embers,
      atlasKey: 'lantern_wraith',
      ability: MonsterSkill.fireFan,
    ),
    2: MonsterForm(
      ordinal: 2,
      kind: MonsterKind.charger,
      name: 'Frostfang Prowler',
      color: 0xff78d9f2,
      adornment: MonsterAdornment.crystals,
      atlasKey: 'frostfang',
      ability: MonsterSkill.frostLance,
    ),
    3: MonsterForm(
      ordinal: 3,
      kind: MonsterKind.tracker,
      name: 'Stormwing Moth',
      color: 0xffbe9aff,
      adornment: MonsterAdornment.sparks,
      atlasKey: 'stormwing_moth',
      ability: MonsterSkill.stormStrike,
    ),
    4: MonsterForm(
      ordinal: 4,
      kind: MonsterKind.warden,
      name: 'Thornshell Ancient',
      color: 0xffa2df78,
      adornment: MonsterAdornment.thorns,
      atlasKey: 'thornshell',
      ability: MonsterSkill.thornRing,
    ),
    5: MonsterForm(
      ordinal: 5,
      kind: MonsterKind.blind,
      name: 'Venom Spitter',
      color: 0xff74df91,
      adornment: MonsterAdornment.thorns,
      atlasKey: 'venom',
    ),
    6: MonsterForm(
      ordinal: 6,
      kind: MonsterKind.warden,
      name: 'Cinder Golem',
      color: 0xffffa15b,
      adornment: MonsterAdornment.embers,
      atlasKey: 'golem',
    ),
    7: MonsterForm(
      ordinal: 7,
      kind: MonsterKind.tracker,
      name: 'Rift Oracle',
      color: 0xffd58bff,
      adornment: MonsterAdornment.sparks,
      atlasKey: 'oracle',
    ),
    8: MonsterForm(
      ordinal: 8,
      kind: MonsterKind.charger,
      name: 'Tempest Wyvern',
      color: 0xff72d7ff,
      adornment: MonsterAdornment.crystals,
      atlasKey: 'wyvern',
    ),
    9: MonsterForm(
      ordinal: 9,
      kind: MonsterKind.tracker,
      name: 'Rail Sentinel',
      color: 0xff72e8f2,
      adornment: MonsterAdornment.sparks,
      atlasKey: 'rail_sentinel',
      ability: MonsterSkill.railBeam,
    ),
    10: MonsterForm(
      ordinal: 10,
      kind: MonsterKind.warden,
      name: 'Magnetron',
      color: 0xffce98ff,
      adornment: MonsterAdornment.crystals,
      atlasKey: 'magnetron',
      ability: MonsterSkill.magneticWell,
    ),
    11: MonsterForm(
      ordinal: 11,
      kind: MonsterKind.blind,
      name: 'Siege Crawler',
      color: 0xffffbd65,
      adornment: MonsterAdornment.embers,
      atlasKey: 'siege_crawler',
      ability: MonsterSkill.proximityMines,
    ),
    12: MonsterForm(
      ordinal: 12,
      kind: MonsterKind.charger,
      name: 'Hive Overseer',
      color: 0xffbbf478,
      adornment: MonsterAdornment.thorns,
      atlasKey: 'hive_overseer',
      ability: MonsterSkill.hunterDrones,
    ),
  };
  static const _colors = [0xffff965c, 0xff78d9f2, 0xffbe9aff, 0xffa2df78];

  static int _generationColor(int palette, int generation) {
    if (generation == 1) return _colors[palette];
    final h = (palette * 90 + (generation - 1) * 137.508) % 360 / 60;
    const chroma = .55, minimum = .40;
    final x = chroma * (1 - (h % 2 - 1).abs());
    final rgb = switch (h.floor()) {
      0 => (chroma, x, 0.0),
      1 => (x, chroma, 0.0),
      2 => (0.0, chroma, x),
      3 => (0.0, x, chroma),
      4 => (x, 0.0, chroma),
      _ => (chroma, 0.0, x),
    };
    int channel(double value) => ((value + minimum) * 255).round();
    return 0xff000000 |
        channel(rgb.$1) << 16 |
        channel(rgb.$2) << 8 |
        channel(rgb.$3);
  }

  /// The last authored chapter continues indefinitely with its own four forms.
  static int chapter(int wave) => ((math.max(1, wave) - 1) ~/ wavesPerMap)
      .clamp(0, chapterMapIds.length - 1);
  static int unlocked(int wave) =>
      (1 + (math.max(1, wave) - 1) ~/ interval).clamp(1, authoredCount);
  static int? nextUnlockWave(int wave) =>
      unlocked(wave) < authoredCount ? 1 + unlocked(wave) * interval : null;
  static bool isDebut(int wave) =>
      wave >= 1 &&
      wave <= form(authoredCount).unlockWave &&
      (wave - 1) % interval == 0;

  /// Map previews use local waves 1–100, while normal runs use global depth.
  /// Their roster never rolls back when global depth catches up to that map.
  static int rosterWave(int wave, String mapId, {bool preview = false}) {
    final index = chapterMapIds.indexOf(mapId);
    if (index < 0) return math.max(1, wave);
    final local = preview ? wave : wave - index * wavesPerMap;
    return index * wavesPerMap + local.clamp(1, wavesPerMap);
  }

  static MonsterForm form(int ordinal) {
    assert(ordinal > 0);
    if (authoredForms[ordinal] case final authored?) return authored;
    if (ordinal > authoredCount) {
      final base = form(1 + (ordinal - 1) % authoredCount);
      return MonsterForm(
        ordinal: ordinal,
        kind: base.kind,
        name:
            '${base.name} · Mutation ${1 + (ordinal - 1) ~/ baseKinds.length}',
        color: _generationColor(
          (ordinal - 1) % 4,
          1 + (ordinal - 1) ~/ authoredCount,
        ),
        adornment: base.adornment,
        atlasKey: base.atlasKey,
        ability: base.skill,
      );
    }
    throw RangeError.range(ordinal, 1, null, 'ordinal');
  }

  /// Every arrival belongs to this chapter. Previously introduced forms from
  /// the same map remain in the mix; earlier maps and base guardians do not.
  static MonsterForm forSpawn(int wave, int index) {
    final first = chapter(wave) * formsPerMap + 1;
    final count = unlocked(wave) - first + 1;
    if (index == 0 && isDebut(wave)) return form(first + count - 1);
    return form(first + (math.max(1, wave) - 1 + index) % count);
  }

  static MonsterForm? fromSnapshot(Map actor) {
    final ordinal = (actor['monsterForm'] as num?)?.toInt() ?? 0;
    return ordinal > 0 ? form(ordinal) : null;
  }
}
