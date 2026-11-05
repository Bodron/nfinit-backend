import 'game_int.dart';

class ChampionAbility {
  const ChampionAbility(
    this.name,
    this.label,
    this.description,
    this.cooldown,
    this.duration, {
    this.targeted = false,
  });
  final String name, label, description;
  final double cooldown, duration;
  final bool targeted;
}

/// Three small abilities per champion; ultimate and common dash are separate.
const championAbilities = [
  [
    ChampionAbility(
      'Charged Blade',
      'BLADE',
      'Your next ranged volley within 4s deals 50% more damage.',
      6,
      4,
    ),
    ChampionAbility(
      'Shadow Echo',
      'ECHO',
      'Leave a shadow double that distracts nearby monsters for 1.2s.',
      10,
      1.2,
    ),
    ChampionAbility(
      'Hunt',
      'HUNT',
      'Gain 20% movement speed for 1.5s.',
      8,
      1.5,
    ),
  ],
  [
    ChampionAbility(
      'Impact Disc',
      'IMPACT',
      'Your next volley pushes the first monster hit a short distance. Guardians resist the push.',
      7,
      4,
    ),
    ChampionAbility(
      'Light Shield',
      'SHIELD',
      'Absorb damage up to 10% of maximum health for 2s.',
      10,
      2,
    ),
    ChampionAbility(
      'Oath',
      'OATH',
      'Reduce contact damage to the nearest nearby ally by 20% for 2s. Protects you when solo.',
      12,
      2,
    ),
  ],
  [
    ChampionAbility(
      'Living Seed',
      'SEED',
      'Your next volley plants a seed on the first monster hit. After 1s it bursts for 75% of the hit damage in a small area.',
      7,
      4,
    ),
    ChampionAbility(
      'Bloom',
      'BLOOM',
      'Heal yourself and the nearby ally with the lowest health percentage for 6% maximum health.',
      8,
      .65,
    ),
    ChampionAbility(
      'Gentle Wind',
      'WIND',
      'Grant yourself and nearby allies 20% movement speed for 1s.',
      10,
      1,
    ),
  ],
  [
    ChampionAbility(
      'Forked Bolt',
      'BOLT',
      'Your next volley arcs from the first monster hit to one nearby monster for 50% damage.',
      8,
      4,
    ),
    ChampionAbility(
      'Crystal Ward',
      'WARD',
      'Absorb damage up to 8% of maximum health for 2s.',
      10,
      2,
    ),
    ChampionAbility(
      'Electric Sigil',
      'SIGIL',
      'Place a small sigil that slows monsters by 35% for 2s. Hold and drag to aim.',
      10,
      2,
      targeted: true,
    ),
  ],
];

abstract final class MinorSkillRules {
  static const castRange = .32 / 1.3;
  static const sigilRadius = .075 / 1.3;
  static const supportRange = .18 / 1.3;
  static const atlasPaths = {
    0: 'assets/art/nyx_basic_skills_atlas_v1.png',
    1: 'assets/art/auron_basic_skills_atlas_v1.png',
    2: 'assets/art/brum_basic_skills_atlas_v1.png',
    3: 'assets/art/noctis_basic_skills_atlas_v1.png',
  };
}

class ChampionAbilityState {
  final cooldowns = [0.0, 0.0, 0.0];
  final active = [0.0, 0.0, 0.0];
  int serial = 0, chargeSerial = 0, consumedSerial = 0;
  double empoweredAt = -100;
  bool lastShotEmpowered = false;
  double shieldLeft = 0, protectionLeft = 0, speedLeft = 0, sigilSlowLeft = 0;
  GameInt shield = GameInt.zero;

  void reset() {
    for (var i = 0; i < 3; i++) {
      cooldowns[i] = active[i] = 0;
    }
    serial = chargeSerial = consumedSerial = 0;
    empoweredAt = -100;
    lastShotEmpowered = false;
    shieldLeft = protectionLeft = speedLeft = sigilSlowLeft = 0;
    shield = GameInt.zero;
  }

  void tick(double delta) {
    double down(double value) => (value - delta).clamp(0.0, double.infinity);
    for (var i = 0; i < 3; i++) {
      cooldowns[i] = down(cooldowns[i]);
      active[i] = down(active[i]);
    }
    shieldLeft = down(shieldLeft);
    protectionLeft = down(protectionLeft);
    speedLeft = down(speedLeft);
    sigilSlowLeft = down(sigilSlowLeft);
    if (shieldLeft == 0) shield = GameInt.zero;
  }
}
