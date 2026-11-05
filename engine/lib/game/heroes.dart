enum HeroRole { ninja, tank, healer, mage }

/// Shared by Flutter and the authoritative Dart server.
class HeroSpec {
  const HeroSpec(
    this.name,
    this.title,
    this.power,
    this.description,
    this.cooldown,
    this.duration,
    this.color, {
    this.role = HeroRole.ninja,
    this.passive = 'Shadowstep: +20% ranged damage for 2s after a dash.',
  });
  final String name, title, power, description;
  final double cooldown, duration;
  final int color;
  final HeroRole role;
  final String passive;
}

/// Offensive Nyx kit used in single-player combat; tag retains Veil.
const nyxEclipse = HeroSpec(
  'NYX',
  'Shadow Ninja',
  'ECLIPSE',
  'Two spectral cuts and a crushing shadow burst. Scales with weapon power; the final hit interrupts nearby monsters.',
  20,
  1.1,
  0xffbc94f0,
);
HeroSpec heroForMode(int skin, {bool combat = false}) =>
    combat && skin == 0 ? nyxEclipse : heroes[skin];

// Progress identities stay stable when the visual cast changes.
const heroLegacySlots = [0, 1, 5, 3];
const heroArtSlots = [0, 1, 5, 4];
const heroAssetNames = ['nyx', 'auron', 'brum', 'noctis'];
int heroArtIndex(int skin) => heroArtSlots[heroIndex(skin)];
int heroFromLegacy(int skin) {
  final index = heroLegacySlots.indexOf(skin);
  return index < 0 ? 0 : index;
}

const heroes = [
  HeroSpec(
    'NYX',
    'Shadow Ninja',
    'VEIL',
    'Invisibility and silent footsteps for 3s.',
    20,
    3,
    0xffbc94f0,
  ),
  HeroSpec(
    'AURON',
    'Guardian Tank',
    'BASTION',
    'A 4s sanctuary: nearby allies take 60% less contact damage. Draws nearby monsters and interrupts their charge.',
    22,
    4,
    0xffffce7b,
    role: HeroRole.tank,
    passive: 'Iron resolve: take 20% less contact damage.',
  ),
  HeroSpec(
    'BRUM',
    'Spirit Healer',
    'SPIRIT GROVE',
    'Plant a spirit tree for 5s. Five pulses heal nearby allies for 6% maximum health each and damage nearby monsters.',
    24,
    5,
    0xff9edda0,
    role: HeroRole.healer,
    passive: 'Living spirit: ranged hits restore 1% health, at most once per second.',
  ),
  HeroSpec(
    'NOCTIS',
    'Storm Mage',
    'TEMPEST',
    'Create a 4s storm at the nearest visible enemy. Four lightning pulses damage and slow monsters inside.',
    20,
    4,
    0xff79baff,
    role: HeroRole.mage,
    passive: 'Static charge: ranged hits slow monsters by 15% for 0.6s.',
  ),
];

int heroIndex(int index) => index.clamp(0, heroes.length - 1);

/// Each champion carries a distinct ranged weapon in survival waves.
class WeaponSpec {
  const WeaponSpec(
    this.name,
    this.damage,
    this.interval,
    this.speed, {
    this.shots = 1,
    this.piercing = false,
  });
  final String name;
  final int damage, shots;
  final double interval, speed;
  final bool piercing;
}

const championWeapons = [
  WeaponSpec('Shadow Daggers', 2, .65, .62, piercing: true),
  WeaponSpec('Light Disc', 4, 1.1, .46, piercing: true),
  WeaponSpec('Spirit Thorns', 2, .75, .56, shots: 3),
  WeaponSpec('Storm Staff', 8, 1.1, .58),
];
