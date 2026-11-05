import 'dart:math';

import 'arena_map.dart';
import 'arena_ids.dart';
import '../content/runtime_catalog.dart';
export 'arena_map.dart';

import 'navigation.dart';
import 'timed_cover.dart';
import 'weapon_progress.dart';
import 'combat_loot.dart';
import 'champion_health.dart';
import 'treasure_chest.dart';
import 'monster_evolution.dart';
import 'combat.dart';
import 'combat_feedback.dart';
import 'monster_damage_trail.dart';
import 'survival.dart';
import 'game_int.dart';
import 'endless_balance.dart';
import 'campaign.dart';
import 'campaign_mastery.dart';

import 'heroes.dart';
import 'scoring.dart';
import 'moments.dart';
import 'manor_layout.dart';
import 'volcano_layout.dart';
import 'tech_layout.dart';
import 'nyx_eclipse_motion.dart';
import 'skill_targeting.dart';
import 'monster_remains.dart';
import 'distractions.dart';
import 'hazards.dart';
import 'chapter_finales.dart';
import 'solo_tools.dart';
import 'champion_progress.dart';
import 'champion_abilities.dart';

part 'champion_abilities_engine.dart';
part 'monster_skills_engine.dart';
part 'tech_monster_skills_engine.dart';
part 'cooperative_engine.dart';

enum MatchMode { infection, survival }

final rng = Random();

List<ArenaMap> get arenaMaps {
  final maps = RuntimeCatalog.maps;
  if (maps == null) return builtinArenaMaps;
  final current = maps
      .where((map) => !retiredArenaIds.contains(map.id))
      .toList();
  return [
    ...current,
    for (final map in builtinArenaMaps)
      if (!current.any((candidate) => candidate.id == map.id)) map,
  ];
}

const builtinArenaMaps = <ArenaMap>[
  ArenaMap(
    'courtyard',
    ManorLayout.title,
    'A courtyard, shaded terraces and garden paths.',
    ManorLayout.walls,
    ManorLayout.props,
  ),
  ArenaMap(
    VolcanoLayout.id,
    VolcanoLayout.title,
    'Ruby spires, obsidian shrines and a living caldera.',
    VolcanoLayout.walls,
    VolcanoLayout.props,
    steamVents: VolcanoLayout.steamVents,
  ),
  ArenaMap(
    TechLayout.id,
    TechLayout.title,
    'Two connected rooms: robot assembly and reactor control.',
    TechLayout.walls,
    TechLayout.props,
    widthUnits: TechLayout.widthUnits,
    spawn: TechLayout.spawn,
  ),
];
// Coordinates remain normalized; a larger arena reduces actor size and travel
// per tick by the same factor, preserving movement in world units.
const arenaScale = 1.3;
const dt = .05, shadowWidth = .040, boundaryShadowWidth = .065;
const playerRadius = .014 / arenaScale;

bool arenaPositionValid(
  double x,
  double y,
  List<List<double>> walls,
  List<int> props, {
  double widthUnits = 1,
}) =>
    x > .04 &&
    x < widthUnits - .04 &&
    y > .04 &&
    y < .96 &&
    !walls.indexed.any(
      (entry) =>
          obstacleDistance(
            x,
            y,
            entry.$2,
            rounded: roundedProp(props[entry.$1]),
          ) <
          playerRadius,
    );

class Player {
  Player(
    this.id,
    this.isBot,
    this.hunter,
    this.x,
    this.y, {
    this.name = 'Player',
    int skin = 0,
    this.onMessage,
    this.upgrades = ChampionLoadout.base,
    this.monster,
    this.monsterForm,
    this.contentMonster,
    this.tool = SoloTool.decoy,
    this.checkpoint,
  }) : skin = heroIndex(skin);
  final String id;
  final bool isBot;
  final String name;
  final int skin;
  final ChampionLoadout upgrades;
  final MonsterKind? monster;
  final MonsterForm? monsterForm;
  final ContentMonster? contentMonster;
  final SoloTool tool;
  final DungeonCheckpoint? checkpoint;
  double toolLeft = 0;
  double stunLeft = 0;
  double ambushHeld = 0, ambushUntil = -100, ambushAt = -100;
  double dodgeAt = -100;

  void updateAmbush(bool concealed, double delta, double now) {
    if (concealed) {
      ambushHeld += delta;
      ambushUntil = -100;
    } else {
      if (ambushHeld >= .5) ambushUntil = now + 3;
      ambushHeld = 0;
    }
  }

  final mastery = CampaignRunStats();
  int decoySerial = 0;
  _DashAttempt? _dashAttempt;
  Player? _chargeTarget;
  double _chargeStartX = 0, _chargeStartY = 0;
  double distractionAt = -100;
  int distractionSerial = 0;
  double terrainNoiseLeft = 0;
  double monsterSkillCooldown = 1.5;
  double entryLeft = 0;
  double chargeWindup = 0,
      chargeLeft = 0,
      chargeRecovery = 0,
      chargeX = 1,
      chargeY = 0;
  bool combatPowers = false;
  HeroSpec get hero => heroForMode(skin, combat: combatPowers);
  double powerCooldown = 0, powerLeft = 0, slowLeft = 0;
  int powerSerial = 0, lootPickupSerial = 0;
  MatchMoment? moment;
  bool get cloaked => skin == 0 && !combatPowers && powerLeft > 0;
  bool get guarded => skin == 1 && !combatPowers && powerLeft > 0;
  bool get rushing => false;
  double get powerSpeed => abilities.speedLeft > 0 ? 1.2 : 1.0;
  final abilities = ChampionAbilityState();
  double shadowEchoUntil = -100, shadowEchoX = 0, shadowEchoY = 0;
  double passiveHealAt = -100, staticLeft = 0, classDashAt = -100;
  double tauntUntil = -100;
  Player? tauntedBy;
  void Function(Map<String, dynamic>)? onMessage;
  final tally = RoundScore();
  double get score => tally.total;
  int catches = 0;
  final cover = CoverTimers();
  GameInt _weaponXpEarned = GameInt.zero, _lootEssenceEarned = GameInt.zero;
  GameInt get weaponXpEarned => _weaponXpEarned;
  set weaponXpEarned(Object value) =>
      _weaponXpEarned = GameInt.parse(value).max(0);
  GameInt get lootEssenceEarned => _lootEssenceEarned;
  set lootEssenceEarned(Object value) =>
      _lootEssenceEarned = GameInt.parse(value).max(0);
  GameInt _health = const GameInt(6), _maxHealth = const GameInt(6);
  GameInt get health => _health;
  set health(Object value) => _health = GameInt.parse(value).max(0);
  GameInt get maxHealth => _maxHealth;
  set maxHealth(Object value) => _maxHealth = GameInt.parse(value).max(1);
  int kills = 0;
  int combatXp = 0, damageUpgrades = 0, hasteUpgrades = 0, volleyUpgrades = 0;
  int spawnWave = 1;
  int? campaignThreatDepth;
  int get threatDepth => campaignThreatDepth ?? spawnWave;
  GameInt contactDamage({bool charging = false}) =>
      ChampionHealthRules.incoming(
        kind: monster ?? MonsterKind.blind,
        depth: threatDepth,
        elite: elite,
        charging: charging,
        variantDamage: contentMonster?.damage ?? 1,
      );
  bool elite = false;
  final healthTrail = MonsterDamageTrail();
  double hitAt = -100;
  double hurtLeft = 0, hurtAt = -100;
  int damageSerial = 0;
  GameInt _lastDamage = GameInt.zero;
  GameInt get lastDamage => _lastDamage;
  set lastDamage(Object value) => _lastDamage = GameInt.parse(value).max(0);
  int get upgradePoints => max(
    0,
    CombatRules.earnedUpgrades(combatXp) -
        damageUpgrades -
        hasteUpgrades -
        volleyUpgrades,
  );
  double fireCooldown = 0;
  double shotX = 1, shotY = 0, shotAt = -100;
  double combatVx = 0, combatVy = 0;
  String? combatTargetId;
  int shotSerial = 0;
  int facing = 1;
  double _lookX = 0, _lookY = 1;
  bool _hasLook = false;
  Player? _visualTarget;
  bool hunter, sprint = false, exhausted = false;
  double x, y, dx = 0, dy = 0, cooldown = 0, tagLock = 0, energy = 100;
  double aimX = 1, aimY = 0;

  void setMovement(double x, double y) {
    dx = x.isFinite ? x.clamp(-1.0, 1.0) : 0;
    dy = y.isFinite ? y.clamp(-1.0, 1.0) : 0;
    rememberDirection();
  }

  void rememberDirection() {
    final length = sqrt(dx * dx + dy * dy);
    if (length <= .01) return;
    aimX = dx / length;
    aimY = dy / length;
    if (dx.abs() > .01) facing = dx < 0 ? -1 : 1;
  }

  double goalX = .1, goalY = .1, aiClock = 0, planAge = 0, waitTime = 0;
  double dashLeft = 0,
      dashCooldown = 0,
      dashFx = 0,
      dashX = 1,
      dashY = 0,
      regenDelay = 0;
  double heardX = .5, heardY = .5, heardAge = 100, heardVx = 0, heardVy = 0;
  int dashSerial = 0, searchStep = 0;
  bool voiceRun = false;
  bool _hadVisualTarget = false;

  void send(Map<String, dynamic> m) => onMessage?.call(m);
}

class Room {
  Room(
    this.code,
    this.demo, {
    String mapId = 'courtyard',
    ArenaMap? arena,
    this.duration = 90,
    this.mode = MatchMode.infection,
    this.campaign,
    this.startWave = 1,
    this.cooperative = false,
  }) : content = demo && campaign == null ? RuntimeCatalog.monsters : const [],
       contentRelease = demo && campaign == null
           ? RuntimeCatalog.releaseId
           : null,
       _initialMap =
           arena ??
           (demo && campaign == null ? arenaMaps : builtinArenaMaps).firstWhere(
             (m) => m.id == mapId,
             orElse: () => demo && campaign == null
                 ? arenaMaps.first
                 : builtinArenaMaps.first,
           );
  final ArenaMap _initialMap;
  ArenaMap? _activeMap;
  ArenaMap get map => _activeMap ?? _initialMap;
  int mapTransitionSerial = 0;
  final List<ContentMonster> content;
  final String? contentRelease;
  final int duration;
  final MatchMode mode;
  final CampaignLevel? campaign;
  final int startWave;
  final bool cooperative;
  int get initialWave => survival && campaign == null ? max(1, startWave) : 1;
  int get _endlessMapIndex => max(
    max(0, MonsterEvolution.chapterMapIds.indexOf(_initialMap.id)),
    MonsterEvolution.chapter(wave),
  );
  bool get _chapterRoster => MonsterEvolution.chapterMapIds.contains(map.id);
  bool get _mapPreview =>
      map.id == _initialMap.id &&
      initialWave <=
          MonsterEvolution.chapterMapIds.indexOf(_initialMap.id) *
              MonsterEvolution.wavesPerMap;
  int get monsterRosterWave =>
      MonsterEvolution.rosterWave(wave, map.id, preview: _mapPreview);
  int? get _nextMonsterWave {
    final next = MonsterEvolution.nextUnlockWave(monsterRosterWave);
    if (next == null) return null;
    if (_mapPreview &&
        MonsterEvolution.chapter(next) >
            MonsterEvolution.chapter(monsterRosterWave)) {
      return next;
    }
    return wave + next - monsterRosterWave;
  }

  int get waveSeconds =>
      campaign?.waves[wave - 1].seconds ?? SurvivalRules.seconds(wave);
  bool get campaignWon => campaign != null && ended && winner == 'runners';
  bool get survival => mode == MatchMode.survival;
  int wave = 1, completedWaves = 0, round = 0;
  double intermission = 0;
  GameInt get survivalPoints => campaign != null
      ? GameInt(campaign!.points(completedWaves))
      : SurvivalRules.pointsFrom(initialWave, completedWaves);
  int get hunterCount => players.where((p) => p.hunter).length;
  int get runnerCount => players.length - hunterCount;
  String? winner;

  void _prepareWave({bool fresh = false}) {
    final runner = players.first;
    if (fresh) players.removeWhere((p) => p.isBot);
    final monsters =
        campaign?.waves[wave - 1].monsters ?? SurvivalRules.incoming(wave);
    _spawnWaveMonsters(monsters, offset: hunterCount);
    left = waveSeconds.toDouble();
    if ((demo || cooperative) &&
        treasureChest == null &&
        wave >= _nextChestWave) {
      _spawnChest(runner);
    }
    if (!fresh) {
      _threatClock = 0;
      return;
    }
    runner.energy = loadoutFor(runner).maxEnergy;
    runner.dashLeft = runner.dashFx = runner.dashCooldown = 0;
    runner._dashAttempt = null;
    runner.terrainNoiseLeft = 0;
    runner.toolLeft = 0;
    runner.fireCooldown = 0;
    projectiles.clear();
    monsterCasts.clear();
    monsterShots.clear();
    monsterSkillImpacts.clear();
    _nextMonsterCast = 0;
    runner.powerLeft = runner.powerCooldown = runner.slowLeft = 0;
    _lures.clear();
    _heardHistory.clear();
    _threatField = null;
    _threatClock = 0;
    message = 'Wave $wave • $hunterCount seekers. Survive ${left.ceil()}s!';
  }

  void _spawnWaveMonsters(List<MonsterKind> monsters, {int offset = 0}) {
    final runner = players.first;
    final slots = campaign == null
        ? max(0, EndlessBalance.maxActiveMonsters - hunterCount)
        : monsters.length;
    for (var index = 0; index < min(monsters.length, slots); index++) {
      final i = offset + index;
      final form = campaign == null
          ? MonsterEvolution.forSpawn(monsterRosterWave, index)
          : null;
      // A room captures its catalog at creation; updates cannot alter a run.
      final baseKind = form?.kind ?? monsters[index];
      // A generic downloaded guardian must not replace chapter art or remove
      // its skill. Explicit form IDs can still receive signed content updates.
      final availableContent = form != null && _chapterRoster
          ? content.where(
              (m) =>
                  m.kind == form.kind &&
                  (m.id == form.atlasKey ||
                      m.id == form.kind.name && m.atlas == null),
            )
          : content;
      final candidatesForKind = availableContent
          .where((m) => m.kind == baseKind)
          .toList();
      final roster = candidatesForKind.isEmpty
          ? availableContent.toList()
          : candidatesForKind;
      final variant = roster.isEmpty
          ? null
          : roster[(wave + i) % roster.length];
      final kind = variant?.kind ?? baseKind;
      final keepForm =
          form != null && _chapterRoster ||
          variant == null ||
          (variant.id == kind.name &&
              variant.atlas == null &&
              form?.kind == kind);
      final bot = Player(
        'W${wave}H$i',
        true,
        true,
        .5,
        .15,
        name: keepForm
            ? form?.name ?? variant?.name ?? kind.title
            : variant.name,
        monster: kind,
        monsterForm: keepForm ? form : null,
        contentMonster: variant,
      );
      // Spread incoming hunters around legal map edges, away from the runner.
      final candidates = <List<double>>[
        for (final radius in [.41, .34, .27])
          for (var n = 0; n < 64; n++)
            [
              (map.widthUnits > 1 ? (runner.x < 1 ? .5 : 1.5) : .5) +
                  radius * cos((n + i * 7) * pi / 32),
              .5 + radius * sin((n + i * 7) * pi / 32),
            ],
      ];
      final spawn = candidates.firstWhere(
        (c) =>
            valid(c[0], c[1]) &&
            sqrt(pow(c[0] - runner.x, 2) + pow(c[1] - runner.y, 2)) >= .30 &&
            players.every(
              (p) => sqrt(pow(c[0] - p.x, 2) + pow(c[1] - p.y, 2)) >= .06,
            ),
        orElse: () {
          final legal = candidates.where((c) => valid(c[0], c[1])).toList();
          if (legal.isEmpty) return map.spawn;
          final far = legal
              .where(
                (c) =>
                    sqrt(pow(c[0] - runner.x, 2) + pow(c[1] - runner.y, 2)) >=
                    .30,
              )
              .toList();
          double clearance(List<double> c) => players
              .map((p) => sqrt(pow(c[0] - p.x, 2) + pow(c[1] - p.y, 2)))
              .reduce(min);
          return (far.isNotEmpty ? far : legal).reduce(
            (a, b) => clearance(a) > clearance(b) ? a : b,
          );
        },
      );
      bot.monsterSkillCooldown = 1.5 + index * .37 % 3;
      bot.spawnWave = wave;
      bot.campaignThreatDepth = campaign == null
          ? null
          : campaign!.id + wave - 1;
      bot.elite = wave % 5 == 0 && index == 0;
      bot.health = bot.maxHealth =
          (CombatRules.health(
                    kind,
                    wave,
                    bot.elite,
                    endless: campaign == null,
                  ) *
                  (variant?.health ?? 1) *
                  (cooperative ? 1.65 : 1.0))
              .max(1);
      bot.x = bot.goalX = spawn[0];
      bot.y = bot.goalY = spawn[1];
      bot.tagLock = 3;
      bot.entryLeft = SurvivalRules.entrySeconds;
      bot.searchStep = i * 3;
      players.add(bot);
    }
  }

  void _advanceEndlessWave({bool cleared = false}) {
    wave++;
    if (cooperative) _reviveCoopTeammates();
    final nextMap = MonsterEvolution.chapterMapIds[_endlessMapIndex];
    if (_endlessMapIndex > 0 && map.id != nextMap) {
      _enterEndlessMap(nextMap);
    }
    left = waveSeconds.toDouble();
    _spawnWaveMonsters(SurvivalRules.incoming(wave), offset: hunterCount);
    if ((demo || cooperative) &&
        treasureChest == null &&
        wave >= _nextChestWave) {
      _spawnChest(players.first);
    }
    // Within a map, surviving actors retain movement, sound clues, powers,
    // energy, cooldowns and their stable presentation IDs.
    _threatClock = 0;
    message = cleared
        ? 'Wave cleared! Wave $wave • $hunterCount new enemies!'
        : 'Wave $wave • +${SurvivalRules.hunters(wave)} enemies. Survivors keep chasing!';
  }

  void _enterEndlessMap(String mapId) {
    _activeMap = builtinArenaMaps.firstWhere((map) => map.id == mapId);
    // The new map has its own population. Retired enemies grant no kill loot.
    players.removeWhere((p) => p.hunter);
    _navigation = null;
    mapTransitionSerial++;
    _threatField = null;
    _threatClock = 0;
    // Wall IDs, projectiles and paths belong to the old arena; run progress stays.
    _lures.clear();
    _heardHistory.clear();
    _distractionsStarted.clear();
    projectiles.clear();
    monsterCasts.clear();
    monsterShots.clear();
    monsterSkillImpacts.clear();
    _nextMonsterCast = 0;
    eclipses.clear();
    championFields.clear();
    minorSkillEffects.clear();
    livingSeeds.clear();
    combatImpacts.clear();
    monsterRemains.clear();
    combatSecondaryEffects.clear();
    (double, double) legal(double x, double y) {
      if (valid(x, y)) return (x, y);
      final cell = navigation.nearest(x, y);
      return (navigation.x(cell), navigation.y(cell));
    }

    for (final player in players) {
      final point = legal(player.x, player.y);
      player.x = player.goalX = point.$1;
      player.y = player.goalY = point.$2;
      player.cover.reset();
      player.planAge = 100;
      player.combatVx = player.combatVy = 0;
    }
    for (final drop in loot) {
      final point = legal(drop.x, drop.y);
      drop.x = point.$1;
      drop.y = point.$2;
    }
    if (treasureChest case final chest?) {
      final point = legal(chest.x, chest.y);
      treasureChest =
          TreasureChest(
              id: chest.id,
              wave: chest.wave,
              x: point.$1,
              y: point.$2,
            )
            ..progress = chest.progress
            ..openedAt = chest.openedAt;
    }
  }

  bool get dungeonBossAlive =>
      survival &&
      campaign == null &&
      players.any((p) => p.hunter && p.elite && p.spawnWave == wave);
  bool get combat => survival;
  final projectiles = <CombatProjectile>[];
  int _shotSerial = 0;
  final combatFeedback = CombatFeedback();
  final combatSecondaryEffects = <Map<String, dynamic>>[];
  final monsterRemains = <MonsterRemains>[];
  final combatImpacts = <({int skin, double x, double y, double time})>[];

  TreasureChest? treasureChest;
  int _chestSerial = 0, _nextChestWave = 1;

  void _spawnChest(Player runner) {
    final paths = navigation.distances(runner.x, runner.y);
    final candidates = <int>[];
    for (var i = 0; i < paths.length; i++) {
      final x = navigation.x(i), y = navigation.y(i);
      if (paths[i] >= 8 &&
          paths[i] <= 26 &&
          x > .1 &&
          x < map.widthUnits - .1 &&
          y > .1 &&
          y < .9 &&
          valid(x - .025, y) &&
          valid(x + .025, y) &&
          valid(x, y - .025) &&
          valid(x, y + .025)) {
        candidates.add(i);
      }
    }
    if (candidates.isEmpty) return;
    // Seeded by depth/round: reproducible, while different runs use other sites.
    final cell =
        candidates[Random(wave * 37 + round * 17).nextInt(candidates.length)];
    treasureChest = TreasureChest(
      id: ++_chestSerial,
      wave: wave,
      x: navigation.x(cell),
      y: navigation.y(cell),
    );
    _nextChestWave = wave + 5;
  }

  void _tickChest(double delta) {
    final chest = treasureChest;
    if ((!demo && !cooperative) ||
        !combat ||
        !running ||
        paused ||
        chest == null) {
      return;
    }
    if (chest.opened) {
      if (elapsed - chest.openedAt! > 2) treasureChest = null;
      return;
    }
    final candidates = players
        .where((p) => !p.hunter && !p.isBot && (!cooperative || p.health > 0))
        .toList();
    if (cooperative) {
      candidates.sort(
        (a, b) => (pow(a.x - chest.x, 2) + pow(a.y - chest.y, 2)).compareTo(
          pow(b.x - chest.x, 2) + pow(b.y - chest.y, 2),
        ),
      );
    }
    final owner = candidates.firstOrNull;
    if (owner == null) return;
    final close =
        pow(owner.x - chest.x, 2) + pow(owner.y - chest.y, 2) <=
        TreasureChest.radius * TreasureChest.radius;
    final still =
        owner.dashLeft <= 0 &&
        owner.combatVx.abs() + owner.combatVy.abs() < .02;
    if (!chest.advance(
      delta,
      elapsed,
      channeling: close && still && segment(owner.x, owner.y, chest.x, chest.y),
    )) {
      return;
    }
    owner.health =
        (owner.health + ChampionHealthRules.chestHealing(owner.maxHealth)).min(
          owner.maxHealth,
        );
    // Physical rewards use the normal collection/persistence path exactly once.
    for (final kind in LootKind.values) {
      final amount =
          (kind == LootKind.xp
              ? EndlessBalance.killXp(chest.wave, true)
              : EndlessBalance.killEssence(chest.wave, true)) *
          3;
      _addLoot(
        owner,
        kind,
        chest.x,
        chest.y,
        amount,
        kind == LootKind.xp ? 8 : 0,
      );
    }
  }

  final eclipses = <NyxEclipseCast>[];
  final monsterCasts = <MonsterCast>[];
  final monsterShots = <MonsterShot>[];
  final monsterSkillImpacts =
      <({MonsterSkill skill, double x, double y, double time})>[];
  double _nextMonsterCast = 0;
  final championFields = <ChampionField>[];
  final minorSkillEffects = <MinorSkillEffect>[];
  final livingSeeds = <_LivingSeed>[];
  final loot = <CombatLoot>[];
  int _lootSerial = 0;
  final lootCollections =
      <
        ({
          String owner,
          String kind,
          GameInt amount,
          double x,
          double y,
          double age,
        })
      >[];

  void _dropLoot(Player owner, Player monster) {
    for (final kind in LootKind.values) {
      var x = monster.x + (kind == LootKind.xp ? -.008 : .008);
      var y = monster.y;
      if (!valid(x, y) || !segment(monster.x, monster.y, x, y)) {
        x = monster.x;
        y = monster.y;
      }
      final amount = kind == LootKind.xp
          ? EndlessBalance.killXp(monster.spawnWave, monster.elite)
          : EndlessBalance.killEssence(monster.spawnWave, monster.elite);
      _addLoot(
        owner,
        kind,
        x,
        y,
        amount,
        kind == LootKind.xp ? (monster.elite ? 3 : 1) : 0,
      );
    }
  }

  void _addLoot(
    Player owner,
    LootKind kind,
    double x,
    double y,
    GameInt amount,
    int combatXp,
  ) {
    CombatLoot? merged;
    var nearest = double.infinity;
    for (final drop in loot) {
      if (drop.owner != owner.id || drop.kind != kind) continue;
      final range = sqrt(pow(drop.x - x, 2) + pow(drop.y - y, 2));
      if (range < nearest &&
          (loot.length >= LootRules.maxDrops ||
              range < .02 &&
                  !drop.attracted &&
                  segment(x, y, drop.x, drop.y))) {
        merged = drop;
        nearest = range;
      }
    }
    if (merged != null) {
      merged.amount += amount;
      merged.combatXp += combatXp;
    } else {
      loot.add(
        CombatLoot(
          id: ++_lootSerial,
          owner: owner.id,
          kind: kind,
          x: x,
          y: y,
          amount: amount,
          combatXp: combatXp,
        ),
      );
    }
  }

  void _tickLoot(double delta) {
    for (var i = lootCollections.length - 1; i >= 0; i--) {
      final effect = lootCollections[i];
      lootCollections[i] = (
        owner: effect.owner,
        kind: effect.kind,
        amount: effect.amount,
        x: effect.x,
        y: effect.y,
        age: effect.age + delta,
      );
    }
    lootCollections.removeWhere((effect) => effect.age > .7);
    final collected = <CombatLoot>{};
    for (final drop in loot) {
      drop.age += delta;
      drop.vx = drop.vy = 0;
      final collectors = players
          .where(
            (p) =>
                !p.hunter &&
                !p.isBot &&
                (cooperative
                    ? p.health > 0 && segment(drop.x, drop.y, p.x, p.y)
                    : p.id == drop.owner),
          )
          .toList();
      if (cooperative) {
        collectors.sort(
          (a, b) => (pow(a.x - drop.x, 2) + pow(a.y - drop.y, 2)).compareTo(
            pow(b.x - drop.x, 2) + pow(b.y - drop.y, 2),
          ),
        );
      }
      final owner = collectors.firstOrNull;
      if (owner == null || drop.age < LootRules.settleSeconds) continue;
      final dx = owner.x - drop.x, dy = owner.y - drop.y;
      final range = sqrt(dx * dx + dy * dy);
      final clear = segment(drop.x, drop.y, owner.x, owner.y);
      if (!clear) continue;
      if (range <= LootRules.magnetRadius || campaignWon) drop.attracted = true;
      if (!drop.attracted) continue;
      drop.speed = min(.7, drop.speed + delta * 1.8);
      final step = min(range, drop.speed * delta);
      if (range > .000001) {
        drop.vx = dx / range * drop.speed;
        drop.vy = dy / range * drop.speed;
        drop.x += dx / range * step;
        drop.y += dy / range * step;
      }
      if (range - step <= LootRules.collectRadius) {
        final recipients = cooperative
            ? players.where((p) => !p.isBot && !p.hunter)
            : [owner];
        for (final recipient in recipients) {
          if (drop.kind == LootKind.xp) {
            recipient.weaponXpEarned += drop.amount;
            recipient.combatXp += drop.combatXp;
          } else {
            recipient.lootEssenceEarned += drop.amount;
          }
          recipient.lootPickupSerial++;
          lootCollections.add((
            owner: recipient.id,
            kind: drop.kind.name,
            amount: drop.amount,
            x: owner.x,
            y: owner.y,
            age: 0,
          ));
        }
        collected.add(drop);
      }
    }
    loot.removeWhere(collected.contains);
  }

  bool tryShoot(Player p, {bool manual = false}) {
    if (!combat ||
        !running ||
        paused ||
        intermission > 0 ||
        p.hunter ||
        (cooperative && p.health <= 0) ||
        p.isBot ||
        !players.contains(p) ||
        p.fireCooldown > 0) {
      return false;
    }
    final candidates =
        players
            .where(
              (enemy) =>
                  enemy.hunter &&
                  enemy.health > 0 &&
                  enemy.entryLeft <= 0 &&
                  distance(p, enemy) <= CombatRules.attackRange &&
                  clearPath(p, enemy),
            )
            .toList()
          ..sort((a, b) => distance(p, a).compareTo(distance(p, b)));
    final reserved = <Player, GameInt>{};
    for (final shot in projectiles) {
      final enemy = shot.target;
      if (enemy == null ||
          !identical(shot.owner, p) ||
          shot.life <= 0 ||
          shot.hits.contains(enemy.id)) {
        continue;
      }
      final range = sqrt(pow(enemy.x - shot.x, 2) + pow(enemy.y - shot.y, 2));
      final speed = sqrt(shot.vx * shot.vx + shot.vy * shot.vy);
      if (range <= speed * shot.life &&
          segment(shot.x, shot.y, enemy.x, enemy.y)) {
        reserved[enemy] = (reserved[enemy] ?? GameInt.zero) + shot.damage;
      }
    }
    double priority(Player enemy) {
      final range = distance(p, enemy);
      final closing =
          ((enemy.combatVx - p.combatVx) * (p.x - enemy.x) +
              (enemy.combatVy - p.combatVy) * (p.y - enemy.y)) /
          max(.001, range);
      return range /
          (1 + max(0, closing) * 2) *
          (enemy.chargeLeft > 0 || enemy.chargeWindup > 0 ? .6 : 1);
    }

    final available =
        candidates
            .where(
              (enemy) =>
                  (reserved[enemy] ?? GameInt.zero) < enemy.health ||
                  distance(p, enemy) < .075,
            )
            .toList()
          ..sort((a, b) => priority(a).compareTo(priority(b)));
    Player? target = available.isEmpty
        ? (manual && candidates.isNotEmpty ? candidates.first : null)
        : available.first;
    for (final enemy in available) {
      if (enemy.id == p.combatTargetId &&
          target != null &&
          priority(enemy) <= priority(target) * 1.12 + .008 &&
          distance(p, target) > .09) {
        target = enemy;
        break;
      }
    }
    p.combatTargetId =
        target?.id ?? (candidates.isEmpty ? null : candidates.first.id);
    if (target == null && !manual) return false;
    final chargedMinor = p.abilities.active[0] > 0;
    p.abilities.lastShotEmpowered = chargedMinor;
    final minorSerial = p.abilities.chargeSerial;
    final weapon = championWeapons[p.skin];
    final speed = CombatRules.projectileSpeed(weapon);
    final aim = target == null ? null : _intercept(p.x, p.y, target, speed);
    final angle = aim == null
        ? atan2(p.aimY, p.aimX)
        : atan2(aim.$2 - p.y, aim.$1 - p.x);
    p.shotX = cos(angle);
    p.shotY = sin(angle);
    p.shotAt = elapsed;
    p.shotSerial++;
    p.fireCooldown = CombatRules.interval(
      weapon,
      wave,
      p.hasteUpgrades,
      loadout: loadoutFor(p),
    );
    final shots = CombatRules.shots(
      weapon,
      p.volleyUpgrades,
      loadout: loadoutFor(p),
    );
    final ambush = p.ambushUntil > elapsed;
    var damage =
        CombatRules.damage(
          weapon,
          wave,
          p.damageUpgrades,
          loadout: loadoutFor(p),
          hasteUpgrades: p.hasteUpgrades,
          volleyUpgrades: p.volleyUpgrades,
        ) *
        (ambush ? 2 : 1);
    if (chargedMinor && p.skin == 0) {
      damage = (damage * 150 + 99) ~/ 100;
    }
    if (p.skin == 0 && elapsed - p.classDashAt < 2) {
      damage = (damage * 120 + 99) ~/ 100;
    }
    if (ambush) {
      p.ambushUntil = -100;
      p.ambushAt = elapsed;
    }
    final modeSpec = WeaponModeCatalog.spec(loadoutFor(p).fireMode);
    for (var i = 0; i < shots; i++) {
      var destination = target;
      if (destination != null &&
          (reserved[destination] ?? GameInt.zero) >= destination.health) {
        final others =
            candidates
                .where(
                  (enemy) => (reserved[enemy] ?? GameInt.zero) < enemy.health,
                )
                .toList()
              ..sort((a, b) => priority(a).compareTo(priority(b)));
        if (others.isNotEmpty) destination = others.first;
      }
      final intercept = destination == null
          ? null
          : _intercept(p.x, p.y, destination, speed);
      final direction = intercept == null
          ? angle
          : atan2(intercept.$2 - p.y, intercept.$1 - p.x);
      final spread = switch (modeSpec.pattern) {
        ShotPattern.burst => .015,
        ShotPattern.parallel || ShotPattern.helix => 0.0,
        _ => .16,
      };
      var a = modeSpec.pattern == ShotPattern.radial
          ? angle + i * pi * 2 / shots
          : direction + (i - (shots - 1) / 2) * spread;
      if (destination != null && modeSpec.pattern != ShotPattern.radial) {
        final range = distance(p, destination);
        if (!segment(p.x, p.y, p.x + cos(a) * range, p.y + sin(a) * range)) {
          a = direction;
        }
      }
      var guidanceDelay = modeSpec.pattern == ShotPattern.radial
          ? .04
          : shots > 1 && modeSpec.pattern != ShotPattern.burst
          ? .12
          : 0.0;
      if (destination != null && modeSpec.pattern == ShotPattern.radial) {
        final launchRange = min(
          distance(p, destination),
          speed * (guidanceDelay + dt),
        );
        if (!segment(
          p.x,
          p.y,
          p.x + cos(a) * launchRange,
          p.y + sin(a) * launchRange,
        )) {
          a = direction;
          guidanceDelay = 0;
        }
      }
      var originX = p.x, originY = p.y;
      if (modeSpec.pattern == ShotPattern.parallel ||
          modeSpec.pattern == ShotPattern.helix) {
        final offset = (i - (shots - 1) / 2) * .009;
        final ox = p.x - sin(angle) * offset, oy = p.y + cos(angle) * offset;
        if (valid(ox, oy) && segment(p.x, p.y, ox, oy)) {
          originX = ox;
          originY = oy;
        }
      }
      projectiles.add(
        CombatProjectile(
          ++_shotSerial,
          p,
          originX,
          originY,
          cos(a) * speed,
          sin(a) * speed,
          damage: damage,
          volley: p.shotSerial,
          minorCharged: chargedMinor,
          minorSerial: minorSerial,
          target: destination,
          piercing: modeSpec.effect == HitEffect.piercing,
          pattern: modeSpec.pattern,
          effect: modeSpec.effect,
          weavePhase: i * pi,
          ricochetsLeft: modeSpec.effect == HitEffect.ricochet ? 3 : 0,
          guidanceDelay: guidanceDelay,
          delay: modeSpec.pattern == ShotPattern.burst
              ? i * CombatRules.burstSpacing(p.fireCooldown, shots)
              : 0,
        )..life = CombatRules.attackRange / speed + .45,
      );
      if (destination != null) {
        reserved[destination] =
            (reserved[destination] ?? GameInt.zero) + damage;
      }
    }
    if (chargedMinor) p.abilities.active[0] = 0;
    return true;
  }

  (double, double) _intercept(double x, double y, Player target, double speed) {
    final time = CombatRules.interceptTime(
      target.x - x,
      target.y - y,
      target.combatVx,
      target.combatVy,
      speed,
    );
    final aimX = target.x + target.combatVx * time;
    final aimY = target.y + target.combatVy * time;
    return valid(aimX, aimY) && segment(x, y, aimX, aimY)
        ? (aimX, aimY)
        : (target.x, target.y);
  }

  void _steerShot(CombatProjectile shot, double delta) {
    if (shot.guidanceDelay > 0) {
      shot.guidanceDelay = max(0, shot.guidanceDelay - delta);
      return;
    }
    // Piercing continues along the impact trajectory; it never chains sideways.
    if (shot.hits.isNotEmpty && shot.effect != HitEffect.ricochet) {
      shot.target = null;
      return;
    }
    bool eligible(Player p) =>
        p.hunter &&
        p.health > 0 &&
        p.entryLeft <= 0 &&
        !shot.hits.contains(p.id) &&
        players.contains(p) &&
        segment(shot.x, shot.y, p.x, p.y);
    if (shot.target == null || !eligible(shot.target!)) {
      shot.target = null;
      var nearest = .32;
      for (final enemy in players) {
        final range = sqrt(pow(enemy.x - shot.x, 2) + pow(enemy.y - shot.y, 2));
        if (range <= nearest && eligible(enemy)) {
          shot.target = enemy;
          nearest = range;
        }
      }
    }
    final target = shot.target;
    if (target == null) return;
    final speed = sqrt(shot.vx * shot.vx + shot.vy * shot.vy);
    final aim = _intercept(shot.x, shot.y, target, speed);
    var wanted = atan2(aim.$2 - shot.y, aim.$1 - shot.x);
    if (shot.pattern == ShotPattern.helix) {
      final distanceToTarget = sqrt(
        pow(target.x - shot.x, 2) + pow(target.y - shot.y, 2),
      );
      wanted +=
          sin(shot.age * 35 + shot.weavePhase) *
          .32 *
          min(1, distanceToTarget / .12);
    }
    final angle = atan2(shot.vy, shot.vx);
    final error = atan2(sin(wanted - angle), cos(wanted - angle));
    final range = sqrt(pow(target.x - shot.x, 2) + pow(target.y - shot.y, 2));
    final turnRate = shot.pattern == ShotPattern.radial
        ? 72.0
        : range < .10
        ? 32.0
        : 22.0;
    final turn = error.clamp(-turnRate * delta, turnRate * delta);
    shot.vx = cos(angle + turn) * speed;
    shot.vy = sin(angle + turn) * speed;
  }

  void _damageMonster(
    CombatProjectile shot,
    Player target,
    GameInt damage,
    Set<Player> dead,
  ) {
    if (dead.contains(target) || target.health <= 0) return;
    final before = target.health;
    target.healthTrail.hit(before / target.maxHealth, elapsed);
    final effectiveDamage = target.stunLeft > 0 ? damage * 1.5 : damage;
    target.health = (before - effectiveDamage).max(0);
    final appliedDamage = before - target.health;
    target.lastDamage = appliedDamage;
    combatFeedback.record(
      owner: shot.owner.id,
      target: target.id,
      volley: shot.volley == 0 ? -shot.id : shot.volley,
      damage: appliedDamage,
      x: target.x,
      y: target.y,
      time: elapsed,
    );
    target.hitAt = elapsed;
    combatImpacts.add((
      skin: shot.owner.skin,
      x: target.x,
      y: target.y,
      time: elapsed,
    ));
    target.slowLeft = max(target.slowLeft, .18);
    // Only actual ranged hits trigger class passives, never area pulses.
    if (shot.id > 0 && shot.owner.combatPowers && appliedDamage > 0) {
      if (shot.owner.skin == 2 && elapsed - shot.owner.passiveHealAt >= 1) {
        final healer = shot.owner;
        healer.passiveHealAt = elapsed;
        healer.health = (healer.health + ((healer.maxHealth + 99) ~/ 100)).min(
          healer.maxHealth,
        );
      }
      if (shot.owner.skin == 3) target.staticLeft = max(target.staticLeft, .6);
    }
    if (target.health <= 0) {
      dead.add(target);
      monsterRemains.add(
        MonsterRemains(
          target.x,
          target.y,
          elapsed,
          (target.monster?.index ?? 0) % 3,
          elite: target.elite,
        ),
      );
      if (monsterRemains.length > MonsterRemains.limit) {
        monsterRemains.removeRange(
          0,
          monsterRemains.length - MonsterRemains.limit,
        );
      }
      shot.owner.kills++;
      _dropLoot(shot.owner, target);
    }
    if (shot.id > 0) _minorProjectileImpact(shot, target, dead);
  }

  List<Player> _secondaryTargets(
    CombatProjectile shot,
    double x,
    double y,
    double radius,
    Set<Player> dead,
  ) {
    final result = players
        .where(
          (p) =>
              p.hunter &&
              p.entryLeft <= 0 &&
              p.health > 0 &&
              !dead.contains(p) &&
              !shot.hits.contains(p.id) &&
              sqrt(pow(p.x - x, 2) + pow(p.y - y, 2)) <= radius &&
              segment(x, y, p.x, p.y),
        )
        .toList();
    result.sort(
      (a, b) => (pow(a.x - x, 2) + pow(a.y - y, 2)).compareTo(
        pow(b.x - x, 2) + pow(b.y - y, 2),
      ),
    );
    return result;
  }

  void _secondaryImpact(CombatProjectile shot, Player hit, Set<Player> dead) {
    if (shot.effect == HitEffect.explosive) {
      combatSecondaryEffects.add({
        'kind': 'blast',
        'x': hit.x,
        'y': hit.y,
        'radius': .065,
        'skin': shot.owner.skin,
        'time': elapsed,
      });
      for (final other in _secondaryTargets(
        shot,
        hit.x,
        hit.y,
        .065,
        dead,
      ).take(6)) {
        shot.hits.add(other.id);
        _damageMonster(shot, other, shot.damage, dead);
      }
    } else if (shot.effect == HitEffect.chain) {
      var from = hit;
      final damage = shot.damage;
      for (var hop = 0; hop < 6; hop++) {
        final targets = _secondaryTargets(shot, from.x, from.y, .14, dead);
        if (targets.isEmpty) break;
        final other = targets.first;
        shot.hits.add(other.id);
        combatSecondaryEffects.add({
          'kind': 'chain',
          'x': from.x,
          'y': from.y,
          'toX': other.x,
          'toY': other.y,
          'skin': shot.owner.skin,
          'time': elapsed,
        });
        _damageMonster(shot, other, damage, dead);
        from = other;
      }
    }
  }

  void _tickCombat(double delta) {
    if (!combat || !running) return;
    combatImpacts.removeWhere((impact) => elapsed - impact.time > .35);
    monsterRemains.removeWhere(
      (bones) => elapsed - bones.time >= MonsterRemains.lifetime,
    );
    combatFeedback.expire(elapsed);
    combatSecondaryEffects.removeWhere(
      (e) => elapsed - (e['time'] as double) > .4,
    );
    for (final p in players.where((p) => !p.hunter && !p.isBot)) {
      p.fireCooldown = max(0, p.fireCooldown - delta);
      tryShoot(p);
    }
    final dead = <Player>{};
    _tickEclipses(dead);
    _tickChampionFields(dead);
    _tickMinorSkills(dead);
    for (final shot in projectiles) {
      if (shot.delay > 0) {
        shot.delay = max(0, shot.delay - delta);
        continue;
      }
      shot.life -= delta;
      shot.age += delta;
      _steerShot(shot, delta);
      // Sweep in small steps so fast needles cannot pass through targets/walls.
      for (var step = 0; step < 8 && shot.life > 0; step++) {
        shot.x += shot.vx * delta / 8;
        shot.y += shot.vy * delta / 8;
        if (!valid(shot.x, shot.y)) {
          shot.life = 0;
          break;
        }
        for (final target in players.where(
          (p) => p.hunter && p.entryLeft <= 0,
        )) {
          if (dead.contains(target) ||
              shot.hits.contains(target.id) ||
              sqrt(pow(target.x - shot.x, 2) + pow(target.y - shot.y, 2)) >
                  playerRadius + CombatRules.projectileRadius) {
            continue;
          }
          shot.hits.add(target.id);
          _damageMonster(shot, target, shot.damage, dead);
          _secondaryImpact(shot, target, dead);
          if (shot.effect == HitEffect.ricochet && shot.ricochetsLeft > 0) {
            final targets = _secondaryTargets(
              shot,
              target.x,
              target.y,
              .20,
              dead,
            );
            if (targets.isNotEmpty) {
              final next = targets.first;
              final speed = sqrt(shot.vx * shot.vx + shot.vy * shot.vy);
              final angle = atan2(next.y - shot.y, next.x - shot.x);
              shot.target = next;
              shot.vx = cos(angle) * speed;
              shot.vy = sin(angle) * speed;
              shot.ricochetsLeft--;
              shot.guidanceDelay = 0;
              shot.life = max(shot.life, .3);
              combatSecondaryEffects.add({
                'kind': 'ricochet',
                'x': target.x,
                'y': target.y,
                'toX': next.x,
                'toY': next.y,
                'skin': shot.owner.skin,
                'time': elapsed,
              });
              break;
            }
          }
          if (!shot.piercing) {
            shot.life = 0;
            break;
          }
        }
      }
    }
    projectiles.removeWhere((s) => s.life <= 0);
    for (final target in dead) {
      players.remove(target);
      _lures.remove(target.id);
      _heardHistory.remove(target.id);
    }
    if (dead.isNotEmpty) _threatClock = 0;
  }

  NyxEclipseCast? _eclipseMotion(Player player, {double trailing = 0}) {
    if (!running || player.health <= 0) return null;
    for (final cast in eclipses) {
      final age = elapsed - cast.time;
      if (identical(cast.owner, player) &&
          !cast.motionCancelled &&
          age >= 0 &&
          age < NyxEclipseMotion.duration + trailing) {
        return cast;
      }
    }
    return null;
  }

  void _tickEclipses(Set<Player> dead) {
    const beats = [.14, .34, .70];
    const percentages = [60, 60, 180];
    for (final cast in eclipses) {
      final age = elapsed - cast.time;
      while (cast.nextPulse < beats.length && age >= beats[cast.nextPulse]) {
        final pulse = cast.nextPulse++;
        if (!players.contains(cast.owner) || cast.owner.health <= 0) break;
        final damage = ((cast.damage * percentages[pulse] + 99) ~/ 100).max(1);
        final shot = CombatProjectile(
          -cast.serial,
          cast.owner,
          cast.x,
          cast.y,
          0,
          0,
          volley: -1000000 - cast.serial,
        );
        for (final target in players.where(
          (p) => p.hunter && p.entryLeft <= 0,
        )) {
          if (dead.contains(target) ||
              target.health <= 0 ||
              sqrt(pow(target.x - cast.x, 2) + pow(target.y - cast.y, 2)) >
                  NyxEclipseCast.radius ||
              !segment(cast.x, cast.y, target.x, target.y)) {
            continue;
          }
          _damageMonster(shot, target, damage, dead);
          if (pulse == 2 && target.health > 0) {
            target.stunLeft = max(target.stunLeft, .55);
            target.chargeWindup = target.chargeLeft = 0;
            target.chargeRecovery = max(target.chargeRecovery, .55);
            target._chargeTarget = null;
            target.dx = target.dy = 0;
          }
        }
      }
    }
    eclipses.removeWhere((cast) => elapsed - cast.time > 1.2);
  }

  void _tickChampionFields(Set<Player> dead) {
    for (final field in championFields) {
      final owner = field.owner;
      if (!players.contains(owner) || owner.hunter || owner.health <= 0) {
        continue;
      }
      final age = elapsed - field.time;
      while (field.nextPulse < field.pulses &&
          age >= field.duration * field.nextPulse / field.pulses + .05) {
        field.nextPulse++;
        bool inside(Player p) =>
            sqrt(pow(p.x - field.x, 2) + pow(p.y - field.y, 2)) <=
                field.radius &&
            segment(field.x, field.y, p.x, p.y);
        if (owner.skin == 2) {
          for (final ally in players.where(
            (p) => !p.hunter && !p.isBot && p.health > 0 && inside(p),
          )) {
            final healing = (ally.maxHealth * 6 + 99) ~/ 100;
            ally.health = (ally.health + healing).min(ally.maxHealth);
          }
        }
        final shot = CombatProjectile(
          -owner.powerSerial,
          owner,
          field.x,
          field.y,
          0,
          0,
          volley: -2000000 - owner.powerSerial,
        );
        final damage = owner.skin == 2
            ? ((field.damage + 1) ~/ 2).max(1)
            : field.damage;
        for (final enemy in players.where(
          (p) =>
              p.hunter &&
              p.entryLeft <= 0 &&
              !dead.contains(p) &&
              p.health > 0 &&
              inside(p),
        )) {
          _damageMonster(shot, enemy, damage, dead);
          if (owner.skin == 3) enemy.slowLeft = max(enemy.slowLeft, .8);
        }
      }
    }
    championFields.removeWhere(
      (field) =>
          elapsed - field.time >= field.duration ||
          !players.contains(field.owner) ||
          field.owner.hunter ||
          field.owner.health <= 0,
    );
  }

  List<List<double>> get walls => map.walls;
  bool paused = false;
  NavigationGrid? _navigation;
  NavigationGrid get navigation => _navigation ??= NavigationGrid(
    valid,
    inShadow,
    widthUnits: map.widthUnits,
  );
  List<int>? _threatField;
  double _threatClock = 0;
  final String code;
  final bool demo;
  ChampionLoadout loadoutFor(Player p) =>
      demo && !p.isBot ? p.upgrades : ChampionLoadout.base;
  final players = <Player>[];
  int _momentSerial = 0;
  final _lures = <String, _Lure>{};
  final _heardHistory = <String, List<({double time, double x, double y})>>{};
  int _finaleEvent = 0;
  FinaleState? get finaleState => campaign?.finalRule?.at(elapsed);
  void _tickFinale() {
    final finale = finaleState;
    if (finale == null ||
        finale.phase != FinalePhase.active ||
        finale.event <= _finaleEvent) {
      return;
    }
    _finaleEvent = finale.event;
    if (finale.rule.kind != FinaleKind.echoes) return;
    for (final h in players.where((p) => p.hunter && p.entryLeft <= 0)) {
      final lure = _lures[h.id];
      if (lure != null && elapsed - lure.time <= 2.5) continue;
      final history = _heardHistory[h.id] ?? const [];
      final old = history
          .where((e) => e.time <= elapsed - 3 && e.time >= elapsed - 8)
          .toList();
      if (old.isEmpty) continue;
      final echo = old.last;
      final range = sqrt(pow(echo.x - h.x, 2) + pow(echo.y - h.y, 2));
      hear(
        h,
        atan2(echo.y - h.y, echo.x - h.x),
        range,
        label: 'a delayed echo',
        falseTrail: true,
      );
      h.cooldown = max(h.cooldown, .7);
      h.aiClock = 0;
    }
  }

  final _distractionsStarted = <String, double>{};
  double distractionCooldown(DistractionSite site) => max(
    0,
    (_distractionsStarted[site.id] ?? -100) +
        DistractionSite.cooldown -
        elapsed,
  );

  DistractionSite? nearbyDistraction(Player p) {
    if (p.hunter || !players.contains(p)) return null;
    DistractionSite? nearest;
    var closest = .085 / arenaScale;
    for (final site in map.distractions) {
      final d = sqrt(pow(p.x - site.x, 2) + pow(p.y - site.y, 2));
      if (d <= closest && segment(p.x, p.y, site.x, site.y)) {
        nearest = site;
        closest = d;
      }
    }
    return nearest;
  }

  bool tryDistraction(Player p) {
    if (!running || paused || intermission > 0) return false;
    final site = nearbyDistraction(p);
    if (site == null || distractionCooldown(site) > 0) return false;
    _distractionsStarted[site.id] = elapsed;
    p.distractionAt = elapsed;
    p.distractionSerial++;
    p.tally.activity(elapsed);
    final token = ++p.decoySerial;
    for (final h in players.where((q) => q.hunter && q.entryLeft <= 0)) {
      final d = sqrt(pow(h.x - site.x, 2) + pow(h.y - site.y, 2));
      final reach = h.monster == MonsterKind.warden
          ? .30
          : DistractionSite.reach;
      if (d > reach) continue;
      hear(
        h,
        atan2(site.y - h.y, site.x - h.x),
        d,
        label: site.title,
        falseTrail: true,
      );
      _lures[h.id] = _Lure(
        p,
        h,
        site.x,
        site.y,
        elapsed,
        token,
        environment: true,
      );
      h.aiClock =
          0; // React on the next AI step, while committed attacks keep running.
    }
    return true;
  }

  List<SteamHazard> get hazards => SteamHazard.states(
    map.steamVents,
    elapsed,
    activeDuration: campaign?.finalRule?.kind == FinaleKind.siege
        ? 5
        : SteamHazard.activeSeconds,
  );
  bool inSteam(Player p) => hazards.any((h) => h.affects(p.x, p.y));

  SoloTool toolFor(Player p) =>
      demo && survival && !p.isBot && !p.hunter ? p.tool : SoloTool.decoy;
  (double, double)? stoneTarget(Player p) {
    for (var step = 22; step >= 7; step--) {
      final x = p.x + p.aimX * step * .01 / arenaScale,
          y = p.y + p.aimY * step * .01 / arenaScale;
      if (valid(x, y)) return (x, y);
    }
    return null;
  }

  void celebrate(Player p, MomentKind kind) {
    p.moment = MatchMoment(++_momentSerial, kind, elapsed);
  }

  bool running = false, ended = false;
  double elapsed = 0;
  int tags = 0;
  String? lastCatcher;
  double left = 90, soundClock = 0;
  String message =
      'Every captured runner becomes a seeker until the round ends.';
  void start() {
    if (players.isEmpty || (!survival && players.length < 2)) return;
    wave = initialWave;
    final nextMap = MonsterEvolution.chapterMapIds[_endlessMapIndex];
    _activeMap =
        survival &&
            campaign == null &&
            _endlessMapIndex > 0 &&
            _initialMap.id != nextMap
        ? builtinArenaMaps.firstWhere((map) => map.id == nextMap)
        : null;
    _navigation = null;
    mapTransitionSerial = 0;
    running = true;
    ended = false;
    round++;
    elapsed = 0;
    soundClock = 0;
    left = duration.toDouble();
    tags = 0;
    lastCatcher = null;
    winner = null;
    wave = initialWave;
    completedWaves = 0;
    intermission = 0;
    _threatClock = 0;
    _threatField = null;
    _momentSerial = 0;
    projectiles.clear();
    monsterCasts.clear();
    monsterShots.clear();
    monsterSkillImpacts.clear();
    _nextMonsterCast = 0;
    _shotSerial = 0;
    combatImpacts.clear();
    monsterRemains.clear();
    combatFeedback.clear();
    combatSecondaryEffects.clear();
    loot.clear();
    lootCollections.clear();
    eclipses.clear();
    championFields.clear();
    minorSkillEffects.clear();
    livingSeeds.clear();
    _lootSerial = 0;
    treasureChest = null;
    _chestSerial = 0;
    _nextChestWave = initialWave;
    _lures.clear();
    _distractionsStarted.clear();
    _heardHistory.clear();
    _finaleEvent = 0;
    for (var i = 0; i < players.length; i++) {
      final p = players[i];
      p.hunter = survival ? (cooperative ? p.isBot : i > 0) : i == 0;
      p.cooldown = 0;
      p.tagLock = cooperative && !p.isBot
          ? 3
          : i == 0
          ? 3
          : 0;
      p.dx = 0;
      p.dy = 0;
      p.aimX = 1;
      p.aimY = 0;
      p.facing = 1;
      p._lookX = 0;
      p._lookY = 1;
      p._hasLook = false;
      p._visualTarget = null;
      p.energy = loadoutFor(p).maxEnergy;
      p.dashLeft = 0;
      p.dashCooldown = 0;
      p.dashFx = 0;
      p.regenDelay = 0;
      p.dashSerial = 0;
      p.powerCooldown = p.powerLeft = p.slowLeft = 0;
      p.powerSerial = p.lootPickupSerial = 0;
      p.combatPowers = combat && !p.hunter && !p.isBot;
      p.entryLeft = 0;
      p.terrainNoiseLeft = 0;
      p.toolLeft = 0;
      p.stunLeft = p.ambushHeld = p.staticLeft = 0;
      p.passiveHealAt = p.classDashAt = p.tauntUntil = -100;
      p.tauntedBy = null;
      p.abilities.reset();
      p.shadowEchoUntil = -100;
      p.ambushUntil = p.ambushAt = p.dodgeAt = -100;
      p.distractionAt = -100;
      p.distractionSerial = 0;
      p.chargeWindup = p.chargeLeft = p.chargeRecovery = 0;
      p.moment = null;
      p.voiceRun = false;
      p._hadVisualTarget = false;
      p.heardAge = 100;
      p.heardVx = 0;
      p.heardVy = 0;
      p.waitTime = 0;
      p.planAge = 100;
      p.searchStep = 0;

      p.mastery.reset();
      p.decoySerial = 0;
      p._dashAttempt = null;
      p._chargeTarget = null;
      p.tally.reset();
      p.catches = 0;
      p.kills = 0;
      p.weaponXpEarned = p.lootEssenceEarned = 0;
      p.cover.reset();
      p.health = p.maxHealth = combat && !p.isBot && !p.hunter
          ? ChampionHealthRules.maximum(loadoutFor(p))
          : 6;
      p.hurtLeft = 0;
      p.hurtAt = -100;
      p.damageSerial = 0;
      p.combatXp = p.damageUpgrades = p.hasteUpgrades = p.volleyUpgrades = 0;
      p.hitAt = -100;
      p.healthTrail.reset();
      p.lastDamage = 0;
      p.fireCooldown = 0;
      p.shotX = 1;
      p.shotY = 0;
      p.shotAt = -100;
      p.shotSerial = 0;
      p.combatVx = p.combatVy = 0;
      p.combatTargetId = null;
      p.sprint = false;
      p.exhausted = false;
      final spawn = [
        [.5, .15],
        [.09, .30],
        [.91, .70],
        [.40, .91],
        [.90, .12],
      ][i % 5];
      p.x = i == 0 ? map.spawn[0] : spawn[0];
      p.y = i == 0 ? map.spawn[1] : spawn[1];
      if (cooperative && !p.isBot) {
        p.x = map.spawn[0] + .035 * i;
        p.y = map.spawn[1];
      }
      if (!valid(p.x, p.y)) {
        p.x = map.spawn[0];
        p.y = map.spawn[1];
      }
      p.goalX = p.x;
      p.goalY = p.y;
      p.aiClock = 0;
    }
    if (survival) {
      _prepareWave(fresh: true);
      final runner = players.first;
      final checkpoint = runner.checkpoint;
      if (campaign == null &&
          checkpoint != null &&
          checkpoint.resumeWave == initialWave) {
        runner.combatXp = checkpoint.xp;
        runner.damageUpgrades = checkpoint.damage;
        runner.hasteUpgrades = checkpoint.haste;
        runner.volleyUpgrades = min(
          checkpoint.volley,
          9 - championWeapons[runner.skin].shots,
        );
      }
    } else {
      message =
          'Survive until the end! Every captured runner becomes a seeker.';
    }
  }

  bool valid(double x, double y) =>
      arenaPositionValid(x, y, walls, map.props, widthUnits: map.widthUnits);
  Set<int> shadowZonesAt(double x, double y) {
    final zones = <int>{};
    if (x <= boundaryShadowWidth) zones.add(-1);
    if (map.widthUnits - x <= boundaryShadowWidth) zones.add(-2);
    if (y <= boundaryShadowWidth) zones.add(-3);
    if (1 - y <= boundaryShadowWidth) zones.add(-4);
    for (var i = 0; i < walls.length; i++) {
      if (!providesCover(map.props[i])) continue;
      if (obstacleDistance(
            x,
            y,
            walls[i],
            rounded: roundedProp(map.props[i]),
          ) <=
          shadowWidth) {
        zones.add(i);
      }
    }
    return zones;
  }

  int? coverSideAt(Player p) {
    int? result;
    var nearest = double.infinity;
    double? currentDistance;
    void consider(int id, double distance) {
      if (id == p.cover.current) currentDistance = distance;
      if (distance < nearest) {
        nearest = distance;
        result = id;
      }
    }

    if (p.x <= boundaryShadowWidth) consider(-1, p.x);
    if (map.widthUnits - p.x <= boundaryShadowWidth) {
      consider(-2, map.widthUnits - p.x);
    }
    if (p.y <= boundaryShadowWidth) consider(-3, p.y);
    if (1 - p.y <= boundaryShadowWidth) consider(-4, 1 - p.y);
    for (var i = 0; i < walls.length; i++) {
      if (!providesCover(map.props[i])) continue;
      final distance = obstacleDistance(
        p.x,
        p.y,
        walls[i],
        rounded: roundedProp(map.props[i]),
      );
      if (distance <= shadowWidth) {
        consider(i * 4 + CoverRules.side(p.x, p.y, walls[i]), distance);
      }
    }
    // Keep the selected side through tiny distance changes at a corner.
    if (currentDistance != null && currentDistance! <= nearest + .012) {
      return p.cover.current;
    }
    return result;
  }

  bool sideHidden(Player p) =>
      survival && !p.hunter && p.cover.hidden(coverSideAt(p), elapsed);

  bool inShadow(double x, double y) => shadowZonesAt(x, y).isNotEmpty;

  bool sharesShadow(Player a, Player b) {
    final zones = shadowZonesAt(a.x, a.y);
    return shadowZonesAt(b.x, b.y).any(
      (zone) =>
          zones.contains(zone) &&
          // A map edge is long: entering it reveals only the local stretch.
          (zone >= 0 || distance(a, b) <= .20 / arenaScale),
    );
  }

  bool canSeeRunner(Player viewer, Player runner) =>
      !runner.hunter &&
      (!cooperative || runner.health > 0) &&
      !runner.cloaked &&
      !sideHidden(runner) &&
      // Bots cannot see through solid props, even outside a shadow zone.
      (!viewer.isBot || clearPath(viewer, runner)) &&
      (!hidden(runner) ||
          sharesShadow(viewer, runner) &&
              (!viewer.isBot ||
                  distance(viewer, runner) <= .055 / arenaScale) &&
              clearPath(viewer, runner));

  bool hidden(Player p) =>
      !p.hunter && (survival ? sideHidden(p) : inShadow(p.x, p.y));
  bool clearPath(Player a, Player b) => List.generate(
    16,
    (i) => valid(a.x + (b.x - a.x) * i / 15, a.y + (b.y - a.y) * i / 15),
  ).every((v) => v);
  List<Player> visibleTo(Player viewer) => viewer.hunter
      ? players.where((p) => p.hunter || canSeeRunner(viewer, p)).toList()
      : players.where((p) => identical(p, viewer) || !p.cloaked).toList();

  void hear(
    Player h,
    double angle,
    double range, {
    bool active = false,
    String? label,
    bool falseTrail = false,
  }) {
    if (!falseTrail) _lures.remove(h.id);
    final x = (h.x + cos(angle) * range).clamp(.05, map.widthUnits - .05),
        y = (h.y + sin(angle) * range).clamp(.05, .95);
    if (h.heardAge < 1.6 && !falseTrail) {
      h.heardVx = ((x - h.heardX) / max(.3, h.heardAge)).clamp(-.14, .14);
      h.heardVy = ((y - h.heardY) / max(.3, h.heardAge)).clamp(-.14, .14);
      h.heardX = h.heardX * .25 + x * .75;
      h.heardY = h.heardY * .25 + y * .75;
    } else {
      h.heardX = x;
      h.heardY = y;
      h.heardVx = 0;
      h.heardVy = 0;
    }
    h.heardAge = 0;
    h.searchStep = 0;
    h.planAge = 100;
    if (campaign?.finalRule?.kind == FinaleKind.echoes && !falseTrail) {
      final history = _heardHistory.putIfAbsent(h.id, () => []);
      history.add((time: elapsed, x: h.heardX, y: h.heardY));
      history.removeWhere((e) => e.time < elapsed - 8);
      if (history.length > 32) history.removeRange(0, history.length - 32);
    }
    h.send({
      'type': 'sound',
      'angle': angle,
      'range':
          label ??
          (range < .18
              ? 'very close'
              : range < .35
              ? 'aproape'
              : 'departe'),
      'volume': range < .18
          ? .85
          : range < .35
          ? .55
          : .28,
      'pan': cos(angle) * .85,
      'active': active,
    });
  }

  void sound(Player h, {bool active = false}) {
    final candidates = players.where((p) {
      if (p.hunter || p.cloaked) return false;
      // Hidden means hidden to monsters for every kind of movement.
      if (h.isBot && hidden(p)) return false;
      final moving = p.dx.abs() + p.dy.abs() > .1 || p.dashFx > 0 || p.voiceRun;
      final reach = p.terrainNoiseLeft > 0
          ? .78
          : active
          ? .75
          : (p.dashFx > 0 || p.voiceRun)
          ? .68
          : hidden(p)
          ? .28
          : .48;
      if (!active && p.toolLeft > 0 && !p.voiceRun) return false;
      return (active || moving || p.terrainNoiseLeft > 0) &&
          distance(h, p) <= reach;
    }).toList()..sort((a, b) => distance(h, a).compareTo(distance(h, b)));
    if (candidates.isEmpty) {
      if (active) h.send({'type': 'quiet'});
      return;
    }
    final p = candidates.first, d = distance(h, p);
    final angle = (atan2(p.y - h.y, p.x - h.x) / (pi / 4)).round() * pi / 4;
    final estimate = d < .18
        ? .12
        : d < .35
        ? .26
        : .44;
    hear(
      h,
      angle,
      estimate,
      active: active,
      label: p.terrainNoiseLeft > 0
          ? 'crunching gravel'
          : p.dashFx > 0
          ? 'a dash'
          : p.voiceRun
          ? 'a voice'
          : hidden(p) && !active
          ? 'footsteps in the shadows'
          : null,
    );
  }

  bool tryDash(Player p) {
    if (!running ||
        paused ||
        intermission > 0 ||
        (cooperative && p.health <= 0) ||
        p.dashCooldown > 0 ||
        p.energy < 30) {
      return false;
    }
    // A manual dodge immediately takes control back from the skill combo.
    final eclipse = _eclipseMotion(p);
    if (eclipse != null) eclipse.motionCancelled = true;
    p._dashAttempt = null;
    if (campaign != null && !p.isBot && !p.hunter) {
      final threats =
          players
              .where(
                (h) =>
                    h.hunter &&
                    h.tagLock <= 0 &&
                    h.entryLeft <= 0 &&
                    distance(h, p) <= .16 / arenaScale &&
                    clearPath(h, p),
              )
              .toList()
            ..sort((a, b) => distance(a, p).compareTo(distance(b, p)));
      if (threats.isNotEmpty) {
        p._dashAttempt = _DashAttempt(
          threats.first,
          distance(threats.first, p),
        );
      }
    }
    p.rememberDirection();
    p.dashX = p.aimX;
    p.dashY = p.aimY;
    p.dashLeft = .22;
    p.dashFx = .42;
    p.dashCooldown = p.isBot ? 4.5 : 1.15 * loadoutFor(p).dashCooldownFactor;
    p.regenDelay = .6;
    p.energy -= 30;
    p.dashSerial++;
    p.classDashAt = elapsed;
    return true;
  }

  GameInt _protectedContactDamage(Player player, GameInt damage) {
    if (player.skin == 1) damage = (damage * 80 + 99) ~/ 100;
    final protected = players.any(
      (tank) =>
          tank.skin == 1 &&
          tank.combatPowers &&
          !tank.hunter &&
          tank.health > 0 &&
          tank.powerLeft > 0 &&
          distance(tank, player) <= ChampionField.bastionRadius &&
          clearPath(tank, player),
    );
    return (protected ? (damage * 40 + 99) ~/ 100 : damage).max(1);
  }

  bool tryTag(Player h) {
    if (!running ||
        paused ||
        intermission > 0 ||
        !players.contains(h) ||
        !h.hunter ||
        h.tagLock > 0 ||
        h.stunLeft > 0) {
      return false;
    }
    final targets =
        players
            .where(
              (p) =>
                  !p.hunter &&
                  (!h.isBot || canSeeRunner(h, p)) &&
                  distance(h, p) <
                      (h.monster == MonsterKind.warden ? .060 : .052) /
                          arenaScale &&
                  clearPath(h, p),
            )
            .toList()
          ..sort((a, b) => distance(h, a).compareTo(distance(h, b)));
    if (targets.isEmpty) return false;
    final p = targets.first;
    if (combat && !p.isBot && p.hurtLeft > 0) return false;
    if (p.guarded) {
      p.powerLeft = 0;
      h.tagLock = .8;
      celebrate(p, MomentKind.shield);
      message = '${p.hero.name} blocked a capture with ${p.hero.power}!';
      return false;
    }
    if (combat && !p.isBot) {
      return _damageChampion(h, p, h.contactDamage(charging: h.chargeLeft > 0));
    }
    return _capture(h, p);
  }

  // All hostile hits share shields, Bastion, grace time and defeat bookkeeping.
  bool _damageChampion(Player h, Player p, GameInt incoming) {
    if (!running || p.hunter || p.health <= 0 || p.hurtLeft > 0) return false;
    final damage = _absorbMinorShield(p, _protectedContactDamage(p, incoming));
    final before = p.health;
    p.healthTrail.hit(before / p.maxHealth, elapsed);
    p.health = (p.health - damage).max(0);
    p.lastDamage = before - p.health;
    p.hurtAt = p.hitAt = elapsed;
    p.damageSerial++;
    p.hurtLeft = ChampionHealthRules.protectionSeconds;
    if (p.health > 0) return true;
    return _capture(h, p);
  }

  bool _capture(Player h, Player p) {
    if (cooperative && survival && !p.isBot) return _downCoopChampion(h, p);
    final captureBonus = h.tally.caughtSomeone();
    p.tally.caught();
    p.tally.assignRole(true);
    p.hunter = true;
    p.tagLock = 3;
    p.cooldown = 0;
    p.heardAge = 100;
    p.planAge = 100;
    p.waitTime = 0;
    p.dashLeft = 0;
    p.energy = max(p.energy, 65);
    tags++;
    h.catches++;
    lastCatcher = h.id;
    message =
        'Caught! +${captureBonus.floor()} bonus for ${h.name}. ${p.name} is now seeking.';
    if (survival && !p.isBot) {
      winner = 'hunters';
      endRound('Defeated on wave $wave. You cleared $completedWaves waves.');
    } else if (runnerCount == 0) {
      winner = 'hunters';
      endRound('All runners were converted. Seekers win!');
    }
    return true;
  }

  bool upgradeWeapon(Player p, String upgrade) {
    if (!combat ||
        !running ||
        paused ||
        !players.contains(p) ||
        p.hunter ||
        p.isBot ||
        p.upgradePoints <= 0) {
      return false;
    }
    switch (upgrade) {
      case 'damage':
        p.damageUpgrades++;
      case 'haste':
        p.hasteUpgrades++;
      case 'volley':
        if (loadoutFor(p).fireMode != FireMode.fan) return false;
        p.volleyUpgrades++;
      default:
        return false;
    }
    return true;
  }

  void action(Player p, String a, {double? targetX, double? targetY}) {
    if (cooperative && p.health <= 0) return;
    if (a.startsWith('upgrade:')) {
      upgradeWeapon(p, a.substring(8));
      return;
    }
    if (!running || paused || intermission > 0 || !players.contains(p)) return;
    if (a.startsWith('skill:')) {
      final slot = int.tryParse(a.substring(6));
      if (slot != null) {
        tryMinorSkill(p, slot, targetX: targetX, targetY: targetY);
      }
      return;
    }
    if (a == 'shoot') {
      tryShoot(p, manual: true);
      return;
    }
    if (a == 'interact') {
      tryDistraction(p);
      return;
    }
    if (a == 'power') {
      tryPower(p, targetX: targetX, targetY: targetY);
      return;
    }
    if (a == 'dash') {
      tryDash(p);
      return;
    }
    if (a == 'catch') {
      tryTag(p);
      return;
    }
    if (p.cooldown > 0) return;
    if (a == 'listen' && p.hunter) {
      p.cooldown = 6;
      p.tally.activity(elapsed);
      sound(p, active: true);
    }
    if (a == 'decoy' && !p.hunter) {
      final tool = toolFor(p);
      final target = tool == SoloTool.stone ? stoneTarget(p) : null;
      if (tool == SoloTool.stone && target == null) return;
      p.cooldown = tool.cooldown;
      p.tally.activity(elapsed);
      if (tool == SoloTool.quietStep) {
        p.toolLeft = 4;
        p.terrainNoiseLeft = 0;
        return;
      }
      final token = ++p.decoySerial;
      for (final h in players.where((q) => q.hunter)) {
        if (target == null) {
          _sendLure(p, h, token);
        } else {
          final d = sqrt(pow(target.$1 - h.x, 2) + pow(target.$2 - h.y, 2));
          if (d > .78 ||
              h.entryLeft > 0 ||
              h.monster == MonsterKind.warden && d > .30) {
            continue;
          }
          hear(
            h,
            atan2(target.$2 - h.y, target.$1 - h.x),
            d,
            label: 'a stone',
            falseTrail: true,
          );
          _lures[h.id] = _Lure(
            p,
            h,
            target.$1,
            target.$2,
            elapsed,
            token,
            environment: true,
          );
        }
      }
      message = 'A sound in the courtyard. Footsteps or a decoy?';
    }
  }

  bool tryPower(Player p, {double? targetX, double? targetY}) {
    if (cooperative && p.health <= 0) return false;
    if (!running ||
        paused ||
        intermission > 0 ||
        !players.contains(p) ||
        p.powerCooldown > 0) {
      return false;
    }
    final targeted = targetX != null || targetY != null;
    if (targeted &&
        (p.skin == 1 ||
            !combat ||
            p.hunter ||
            p.isBot ||
            targetX == null ||
            targetY == null ||
            !EclipseTargeting.valid(
              p.x,
              p.y,
              targetX,
              targetY,
              range: p.skin == 0
                  ? NyxEclipseCast.castRange
                  : ChampionField.castRange,
              canStand: valid,
            ))) {
      return false;
    }
    p.combatPowers = combat && !p.hunter && !p.isBot;
    // Freeze only information the monster actually had before Nyx vanished.
    // Never give a searching monster the position of an unseen runner.
    if (p.skin == 0 && !p.hunter && !p.combatPowers) {
      for (final h in players.where((h) => h.isBot && h.hunter)) {
        final sawRunner =
            canSeeRunner(h, p) &&
            (h.monster != MonsterKind.warden || distance(h, p) < .22);
        if (sawRunner) {
          h.heardX = p.x;
          h.heardY = p.y;
          h.heardAge = 0;
          h.heardVx = h.heardVy = 0;
          h.searchStep = 0;
          h.planAge = 100;
        }
        // Losing the target breaks the pack's synchronized movement too.
        // A short, staggered hesitation gives the runner a real escape window.
        if (sawRunner && h.chargeLeft <= 0) {
          h.dx = h.dy = 0;
          h.aiClock = .35 + (players.indexOf(h) % 4) * .12;
          h._hadVisualTarget = false;
        }
      }
    }
    p.powerCooldown = p.hero.cooldown * loadoutFor(p).powerCooldownFactor;
    p.powerLeft = p.hero.duration * loadoutFor(p).powerDurationFactor;
    p.powerSerial++;
    if (p.skin == 0 && p.combatPowers) {
      final damage = CombatRules.volleyDamage(
        championWeapons[p.skin],
        wave,
        p.damageUpgrades,
        loadout: loadoutFor(p),
        hasteUpgrades: p.hasteUpgrades,
        volleyUpgrades: p.volleyUpgrades,
      );
      p.dashLeft = 0;
      p._dashAttempt = null;
      final cast = NyxEclipseCast(
        p,
        elapsed,
        damage,
        targetX: targetX,
        targetY: targetY,
      );
      if (targeted) {
        // Tight spaces shorten the flourish, never the selected landing or walls.
        for (final scale in [1.0, .75, .5, .25, 0.0]) {
          cast.sweepScale = scale;
          var clear = true;
          var previous = (p.x, p.y);
          for (var i = 1; i <= 84; i++) {
            final offset = cast.displacement(
              NyxEclipseMotion.duration * i / 84,
            );
            final point = (p.x + offset.$1, p.y + offset.$2);
            if (!valid(point.$1, point.$2) ||
                !segment(previous.$1, previous.$2, point.$1, point.$2)) {
              clear = false;
              break;
            }
            previous = point;
          }
          if (clear) break;
        }
      }
      eclipses.add(cast);
      p.hurtLeft = max(p.hurtLeft, .35);
    }
    p.tally.activity(elapsed);
    if (p.skin == 1) {
      p.slowLeft = 0;
      if (p.combatPowers) {
        for (final enemy in players.where((q) => q.isBot && q.hunter)) {
          if (distance(p, enemy) > ChampionField.bastionRadius ||
              !clearPath(p, enemy)) {
            continue;
          }
          enemy.tauntedBy = p;
          enemy.tauntUntil = elapsed + p.powerLeft;
          enemy.chargeLeft = enemy.chargeWindup = 0;
          enemy._chargeTarget = null;
          enemy.chargeRecovery = max(enemy.chargeRecovery, .5);
          enemy.aiClock = 0;
        }
      }
    }
    if (p.combatPowers && (p.skin == 2 || p.skin == 3)) {
      var x = targetX ?? p.x, y = targetY ?? p.y;
      if (p.skin == 3 && !targeted) {
        final targets =
            players
                .where(
                  (q) =>
                      q.hunter &&
                      q.entryLeft <= 0 &&
                      distance(p, q) <= ChampionField.castRange &&
                      clearPath(p, q),
                )
                .toList()
              ..sort((a, b) => distance(p, a).compareTo(distance(p, b)));
        if (targets.isNotEmpty) {
          x = targets.first.x;
          y = targets.first.y;
        }
      }
      final damage = CombatRules.volleyDamage(
        championWeapons[p.skin],
        wave,
        p.damageUpgrades,
        loadout: loadoutFor(p),
        hasteUpgrades: p.hasteUpgrades,
        volleyUpgrades: p.volleyUpgrades,
      );
      championFields.add(ChampionField(p, elapsed, x, y, p.powerLeft, damage));
    } else if (p.skin == 2 || p.skin == 3) {
      // Tag mode has no health: support/control buys an escape window instead.
      for (final q in players) {
        if (q.hunter != p.hunter &&
            !q.guarded &&
            distance(p, q) <= .20 / arenaScale &&
            clearPath(p, q)) {
          q.slowLeft = max(q.slowLeft, 2);
        }
      }
    }
    return true;
  }

  void _sendLure(Player owner, Player hunter, int token) {
    final angles = List.generate(8, (i) => i * pi / 4)..shuffle(rng);
    for (final angle in angles) {
      final x = hunter.x + cos(angle) * .18, y = hunter.y + sin(angle) * .18;
      if (!valid(x, y) ||
          sqrt(pow(x - owner.x, 2) + pow(y - owner.y, 2)) < .20) {
        continue;
      }
      hear(hunter, angle, .18, label: 'misleading footsteps', falseTrail: true);
      _lures[hunter.id] = _Lure(
        owner,
        hunter,
        hunter.heardX,
        hunter.heardY,
        elapsed,
        token,
      );
      break;
    }
  }

  void _checkDashEscapes() {
    for (final p in players) {
      final attempt = p._dashAttempt;
      if (attempt == null || p.dashLeft > 0) continue;
      p._dashAttempt = null;
      if (p.hunter || !players.contains(attempt.hunter)) continue;
      final separation = distance(p, attempt.hunter);
      if (separation >= .16 / arenaScale &&
          separation - attempt.distance >= .04 / arenaScale) {
        p.mastery.dashEscapes++;
      }
    }
  }

  void _checkChargeDodge(Player hunter) {
    final target = hunter._chargeTarget;
    hunter._chargeTarget = null;
    if (!combat ||
        target == null ||
        target.hunter ||
        target.isBot ||
        !players.contains(target)) {
      return;
    }
    final travel = sqrt(
      pow(hunter.x - hunter._chargeStartX, 2) +
          pow(hunter.y - hunter._chargeStartY, 2),
    );
    final sideways =
        ((target.x - hunter._chargeStartX) * hunter.chargeY -
                (target.y - hunter._chargeStartY) * hunter.chargeX)
            .abs();
    if (travel >= .06 / arenaScale &&
        sideways >= .045 / arenaScale &&
        distance(target, hunter) > .060 / arenaScale) {
      if (campaign != null) target.mastery.chargeDodges++;
      target.energy = min(loadoutFor(target).maxEnergy, target.energy + 20);
      target.dashCooldown = max(0, target.dashCooldown - .5);
      target.dodgeAt = elapsed;
    }
  }

  void _checkLures() {
    _lures.removeWhere((_, lure) {
      final p = lure.owner, h = lure.hunter;
      if (elapsed - lure.time > 2.5 ||
          p.hunter ||
          !h.hunter ||
          !players.contains(p) ||
          !players.contains(h)) {
        return true;
      }
      final toward =
          lure.initialDistance -
          sqrt(pow(h.x - lure.x, 2) + pow(h.y - lure.y, 2));
      final away = distance(p, h) - lure.initialSeparation;
      final misdirected =
          sqrt(pow(h.x - lure.runnerX, 2) + pow(h.y - lure.runnerY, 2)) -
          lure.initialSeparation;
      if (toward >= .035 &&
          away >= .025 &&
          (lure.environment || misdirected >= .025)) {
        if (p.mastery.followedLure(lure.token)) celebrate(p, MomentKind.trick);
        return !lure.environment;
      }
      return false;
    });
  }

  bool segment(double x, double y, double tx, double ty) {
    final steps = max(2, (sqrt(pow(tx - x, 2) + pow(ty - y, 2)) / .009).ceil());
    for (var i = 1; i <= steps; i++) {
      if (!valid(x + (tx - x) * i / steps, y + (ty - y) * i / steps)) {
        return false;
      }
    }
    return true;
  }

  void steer(Player p, {Player? avoid}) {
    final danger = hazards
        .where((h) => h.phase != HazardPhase.dormant)
        .toList();
    double penalty(double x, double y) =>
        danger.any((h) => h.vent.contains(x, y)) ? 12 : 0;
    final path = navigation.route(
      p.x,
      p.y,
      p.goalX,
      p.goalY,
      threatX: avoid?.x,
      threatY: avoid?.y,
      traversalPenalty: danger.isEmpty ? null : penalty,
    );
    if (path.length < 2) {
      p.dx = 0;
      p.dy = 0;
      return;
    }
    var next = path[1];
    for (final cell in path.skip(1).take(5)) {
      final x = navigation.x(cell), y = navigation.y(cell);
      final cutsDanger =
          danger.isNotEmpty &&
          penalty(p.x, p.y) == 0 &&
          List.generate(
            12,
            (i) => penalty(
              p.x + (x - p.x) * (i + 1) / 12,
              p.y + (y - p.y) * (i + 1) / 12,
            ),
          ).any((cost) => cost > 0);
      if (!cutsDanger && segment(p.x, p.y, x, y)) {
        next = cell;
      } else {
        break;
      }
    }
    final x = navigation.x(next) - p.x,
        y = navigation.y(next) - p.y,
        length = sqrt(x * x + y * y);
    p.dx = length > .002 ? x / length : 0;
    p.dy = length > .002 ? y / length : 0;
  }

  void chooseEscape(Player p, Player hunter) {
    final threats = _threatField ?? navigation.distances(hunter.x, hunter.y);
    var best = -double.infinity, target = navigation.nearest(p.x, p.y);
    for (final cell in navigation.covers) {
      if (threats[cell] < 0) continue;
      final x = navigation.x(cell),
          y = navigation.y(cell),
          own = sqrt(pow(x - p.x, 2) + pow(y - p.y, 2));
      if (own < .10) continue;
      var score =
          threats[cell] / NavigationGrid.n * 1.7 -
          own * .65 +
          navigation.neighbors(cell).length * .035;
      for (final q in players.where((q) => !q.hunter && !identical(q, p))) {
        if (sqrt(pow(x - q.x, 2) + pow(y - q.y, 2)) < .14) score -= .28;
      }
      if (segment(hunter.x, hunter.y, x, y) &&
          sqrt(pow(x - hunter.x, 2) + pow(y - hunter.y, 2)) < .30) {
        score -= .8;
      }
      if (score > best) {
        best = score;
        target = cell;
      }
    }
    p.goalX = navigation.x(target);
    p.goalY = navigation.y(target);
    p.planAge = 0;
  }

  void bot(Player p, Player hunter, {double delta = dt}) {
    p.aiClock -= delta;
    if (p.aiClock > 0) return;
    p.aiClock = .55;
    // Bots keep the forgiving reaction speed and only occasionally use powers.
    if (!p.hunter &&
        left < duration - 5 &&
        p.powerCooldown <= 0 &&
        distance(p, hunter) < .24 &&
        rng.nextDouble() < .06) {
      tryPower(p);
    }
    if (p.hunter) {
      final packIndex = players
          .where((q) => q.isBot && q.hunter)
          .toList()
          .indexOf(p);
      final searchPhase = max(0, packIndex) * 2.39996;
      // Bots use the same open-ground and shared-cover visibility as humans.
      final seen =
          visibleTo(p)
              .where(
                (q) =>
                    !q.hunter &&
                    (p.monster != MonsterKind.warden || distance(p, q) < .22),
              )
              .toList()
            ..sort((a, b) => distance(p, a).compareTo(distance(p, b)));
      final taunt = p.tauntedBy;
      if (combat &&
          taunt != null &&
          p.tauntUntil > elapsed &&
          players.contains(taunt) &&
          !taunt.hunter &&
          taunt.health > 0 &&
          clearPath(p, taunt)) {
        seen.remove(taunt);
        seen.insert(0, taunt);
      }
      final lostTarget = p._hadVisualTarget && seen.isEmpty;
      p._hadVisualTarget = seen.isNotEmpty;
      p._visualTarget = null;
      if (lostTarget) {
        p.dx = p.dy = 0;
        p.aiClock = .35 + max(0, packIndex) % 4 * .12;
        p.planAge = 100;
        return;
      }
      final lure = _lures[p.id];
      final distracted =
          lure != null &&
          lure.environment &&
          elapsed - lure.time <= DistractionSite.pulseSeconds &&
          (seen.isEmpty || distance(p, seen.first) > .14);
      (double, double)? finalGoal;
      final finale = finaleState;
      final closePrey = seen.isNotEmpty && distance(p, seen.first) <= .14;
      if (finale != null && !closePrey && lure == null) {
        if ((finale.rule.kind == FinaleKind.bell ||
                finale.rule.kind == FinaleKind.siege) &&
            finale.phase == FinalePhase.active) {
          finalGoal = finale.goal;
        } else if (finale.rule.kind == FinaleKind.patrol &&
            p.monster == MonsterKind.warden &&
            seen.isEmpty &&
            !(p.heardAge < 2.2 &&
                sqrt(pow(p.heardX - p.x, 2) + pow(p.heardY - p.y, 2)) < .26)) {
          finalGoal = finale.goal;
        }
      }
      if (combat &&
          taunt != null &&
          p.tauntUntil > elapsed &&
          players.contains(taunt) &&
          !taunt.hunter &&
          taunt.health > 0 &&
          clearPath(p, taunt)) {
        p.goalX = taunt.x;
        p.goalY = taunt.y;
        p._visualTarget = taunt;
      } else if (combat && p.shadowEchoUntil > elapsed) {
        p.goalX = p.shadowEchoX;
        p.goalY = p.shadowEchoY;
      } else if (distracted) {
        p.goalX = lure.x;
        p.goalY = lure.y;
      } else if (finalGoal != null) {
        p.goalX = finalGoal.$1;
        p.goalY = finalGoal.$2;
      } else if (seen.isNotEmpty) {
        p.goalX = seen.first.x;
        p.goalY = seen.first.y;
        p._visualTarget = seen.first;
        // A last-seen position is a fixed clue, never a live target reference.
        p.heardX = p.goalX;
        p.heardY = p.goalY;
        p.heardAge = 0;
        p.heardVx = p.heardVy = 0;
        p.searchStep = 0;
      } else if (p.heardAge < (p.monster == MonsterKind.tracker ? 4.5 : 2.2) &&
          p.searchStep == 0 &&
          sqrt(pow(p.heardX - p.x, 2) + pow(p.heardY - p.y, 2)) > .035 &&
          (p.monster != MonsterKind.warden ||
              sqrt(pow(p.heardX - p.x, 2) + pow(p.heardY - p.y, 2)) < .26)) {
        // Only the lead searcher checks the exact clue. Others inspect distinct
        // approaches instead of forming a queue on the same navigation route.
        final spread = packIndex <= 0 ? 0.0 : .075;
        final cell = navigation.nearest(
          p.heardX + cos(searchPhase) * spread,
          p.heardY + sin(searchPhase) * spread,
        );
        p.goalX = navigation.x(cell);
        p.goalY = navigation.y(cell);
      } else if (p.planAge > 2.4 ||
          sqrt(pow(p.x - p.goalX, 2) + pow(p.y - p.goalY, 2)) < .055) {
        if (p.heardAge < (p.monster == MonsterKind.tracker ? 11 : 7) &&
            p.monster != MonsterKind.warden) {
          final angle = searchPhase + p.searchStep * 2.39996,
              radius = .08 + ((p.searchStep + max(0, packIndex)) % 3) * .055;
          final cell = navigation.nearest(
            p.heardX + cos(angle) * radius,
            p.heardY + sin(angle) * radius,
          );
          p.goalX = navigation.x(cell);
          p.goalY = navigation.y(cell);
        } else {
          final cell =
              navigation.covers[(p.searchStep * 37 + max(0, packIndex) * 53) %
                  navigation.covers.length];
          p.goalX = navigation.x(cell);
          p.goalY = navigation.y(cell);
        }
        p.searchStep++;
        p.planAge = 0;
      }
      if (p.monster == MonsterKind.charger &&
          p.shadowEchoUntil <= elapsed &&
          seen.isNotEmpty &&
          !distracted &&
          finalGoal == null &&
          p.chargeRecovery <= 0 &&
          distance(p, seen.first) > .10 &&
          distance(p, seen.first) < .38 &&
          clearPath(p, seen.first)) {
        final target = seen.first, length = distance(p, target);
        p.chargeX = (target.x - p.x) / length;
        p.chargeY = (target.y - p.y) / length;
        p._chargeTarget = target;
        p.chargeWindup = .75;
        p.dx = p.dy = 0;
        return;
      }
      steer(p);
      // Give the human runner breathing room: walk toward old sound clues,
      // without sprinting or chaining dashes into an immediate catch.
      p.voiceRun = false;
    } else {
      final danger = distance(p, hunter),
          approaching =
              (hunter.dx * (p.x - hunter.x) + hunter.dy * (p.y - hunter.y)) > 0;
      if (p.waitTime > 0 && danger > .22) {
        p.dx = 0;
        p.dy = 0;
        return;
      }
      if (p.planAge > (danger < .30 ? 1.0 : 3.0) ||
          sqrt(pow(p.x - p.goalX, 2) + pow(p.y - p.goalY, 2)) < .05) {
        if (hidden(p) &&
            danger > .27 &&
            danger < .50 &&
            rng.nextDouble() < .40) {
          p.waitTime = .55 + rng.nextDouble() * .55;
          p.dx = 0;
          p.dy = 0;
          p.planAge = 0;
          return;
        }
        chooseEscape(p, hunter);
      }
      steer(p, avoid: hunter);
      p.voiceRun = danger < .16 && p.energy > 35;
      final away = p.dx * (hunter.x - p.x) + p.dy * (hunter.y - p.y) < .02;
      if (danger < .24 &&
          approaching &&
          away &&
          segment(p.x, p.y, p.x + p.dx * .16, p.y + p.dy * .16)) {
        tryDash(p);
      }
      if (danger < .38 && p.cooldown <= 0 && (hidden(p) || danger < .20)) {
        action(p, 'decoy');
      }
    }
  }

  void _updateMonsterFacing(Player p) {
    if (!p.isBot || !p.hunter || p.health <= 0 || p.stunLeft > 0) return;
    void look(double x, double y) {
      final length = sqrt(x * x + y * y);
      if (length < .001) return;
      p._lookX = x / length;
      p._lookY = y / length;
      p._hasLook = true;
    }

    if (p.chargeWindup > 0 || p.chargeLeft > 0) {
      look(p.chargeX, p.chargeY);
      return;
    }
    for (final cast in monsterCasts) {
      if (cast.owner == p && (!cast.fired || cast.skill.holdsCaster)) {
        look(cos(cast.angle), sin(cast.angle));
        return;
      }
    }
    final taunt = p.tauntedBy;
    final taunted =
        combat &&
        taunt != null &&
        p.tauntUntil > elapsed &&
        players.contains(taunt) &&
        !taunt.hunter &&
        taunt.health > 0 &&
        clearPath(p, taunt);
    if (combat && p.shadowEchoUntil > elapsed && !taunted) {
      look(p.shadowEchoX - p.x, p.shadowEchoY - p.y);
      return;
    }
    final target = p._visualTarget;
    if (target != null) {
      final followsTaunt = taunted && identical(target, taunt);
      if (players.contains(target) &&
          !target.hunter &&
          target.health > 0 &&
          (followsTaunt ||
              (canSeeRunner(p, target) &&
                  (p.monster != MonsterKind.warden ||
                      distance(p, target) < .22)))) {
        look(target.x - p.x, target.y - p.y);
        return;
      }
      // Do not turn toward the current position of a concealed/lost target.
      p._visualTarget = null;
    }
    if (p.combatVx.abs() + p.combatVy.abs() > .001) {
      look(p.combatVx, p.combatVy);
    } else if (p.dx.abs() + p.dy.abs() > .01) {
      look(p.dx, p.dy);
    }
  }

  bool _monsterAction(Player p, double delta) {
    if (p.stunLeft > 0) {
      monsterCasts.removeWhere((cast) => cast.owner == p && !cast.fired);
      p.stunLeft = max(0, p.stunLeft - delta);
      p.dx = p.dy = 0;
      return true;
    }
    if (p.entryLeft > 0) {
      p.entryLeft = max(0, p.entryLeft - delta);
      p.setMovement(0, 0);
      return true;
    }
    if (monsterCasts.any(
      (cast) => cast.owner == p && (!cast.fired || cast.skill.holdsCaster),
    )) {
      p.dx = p.dy = 0;
      return true;
    }
    if (p.chargeWindup > 0) {
      if (p._chargeTarget?.cloaked ?? false) {
        p._chargeTarget = null;
        p.chargeWindup = 0;
        p.chargeRecovery = .4;
        p.dx = p.dy = 0;
        return true;
      }
      p.chargeWindup = max(0, p.chargeWindup - delta);
      p.dx = p.dy = 0;
      if (p.chargeWindup == 0) {
        p._chargeStartX = p.x;
        p._chargeStartY = p.y;
        p.chargeLeft = .55;
        p.dx = p.chargeX;
        p.dy = p.chargeY;
      }
      return true;
    }
    if (p.chargeLeft > 0) {
      p.chargeLeft = max(0, p.chargeLeft - delta);
      p.dx = p.chargeX;
      p.dy = p.chargeY;
      if (p.chargeLeft == 0) {
        _checkChargeDodge(p);
        p.chargeRecovery = 1.35;
        p.dx = p.dy = 0;
      }
      return true;
    }
    if (p.chargeRecovery > 0) {
      p.chargeRecovery = max(0, p.chargeRecovery - delta);
      p.dx = p.dy = 0;
      return true;
    }
    return false;
  }

  void endRound(String reason) {
    if (ended) return;
    running = false;
    ended = true;
    for (final p in players) {
      p.tally.finish(p.hunter);
    }
    message = reason;
  }

  List<Map<String, dynamic>> scoreboard() {
    final scores = [
      for (final p in players)
        {
          'id': p.id,
          'name': p.name,
          'skin': p.skin,
          'catches': p.catches,
          ...p.tally.snapshot(),
        },
    ];
    scores.sort((a, b) {
      final difference = (b['score'] as int).compareTo(a['score'] as int);
      return difference == 0
          ? players
                .indexWhere((p) => p.id == a['id'])
                .compareTo(players.indexWhere((p) => p.id == b['id']))
          : difference;
    });
    for (var i = 0; i < scores.length; i++) {
      scores[i]['rank'] = i > 0 && scores[i]['score'] == scores[i - 1]['score']
          ? scores[i - 1]['rank']
          : i + 1;
    }
    return scores;
  }

  void tick() {
    if (running && !survival && players.isNotEmpty && runnerCount == 0) {
      winner = 'hunters';
      endRound('No runners remain. Seekers win!');
    }
    if (running && !survival && players.length < 2) {
      endRound('Round ended: only one player remains.');
    }
    if (running && !paused && intermission > 0) {
      intermission = max(0, intermission - dt);
      if (intermission == 0) {
        wave++;
        _prepareWave();
      }
    } else if (running && !paused) {
      final delta = min(dt, left);
      left = max(0, left - delta);
      soundClock += delta;
      if (!survival && !players.any((p) => p.hunter)) {
        players.last.hunter = true;
        players.last.tagLock = 3;
      }
      final hunters = players.where((p) => p.hunter).toList();
      _threatClock -= delta;
      if (!players.any((p) => p.isBot && !p.hunter)) {
        _threatField = null;
      } else if (_threatClock <= 0) {
        _threatClock = .3;
        _threatField = navigation.distancesFrom(hunters.map((h) => (h.x, h.y)));
      }
      for (final p in players) {
        if (cooperative && !p.isBot && p.health <= 0) {
          p.setMovement(0, 0);
          p.voiceRun = false;
        }
        p.cooldown = max(0, p.cooldown - delta);
        p.powerCooldown = max(0, p.powerCooldown - delta);
        p.powerLeft = max(0, p.powerLeft - delta);
        p.slowLeft = max(0, p.slowLeft - delta);
        p.staticLeft = max(0, p.staticLeft - delta);
        p.abilities.tick(delta);
        p.monsterSkillCooldown = max(0, p.monsterSkillCooldown - delta);
        p.hurtLeft = max(0, p.hurtLeft - delta);
        p.tagLock = max(0, p.tagLock - delta);
        p.dashCooldown = max(0, p.dashCooldown - delta);
        p.dashFx = max(0, p.dashFx - delta);
        p.regenDelay = max(0, p.regenDelay - delta);
        p.heardAge += delta;
        p.planAge += delta;
        p.waitTime = max(0, p.waitTime - delta);
        p.terrainNoiseLeft = max(0, p.terrainNoiseLeft - delta);
        p.toolLeft = max(0, p.toolLeft - delta);
        if (p.isBot && !_monsterAction(p, delta)) {
          final nearest = p.hunter
              ? p
              : hunters.reduce(
                  (a, b) => distance(p, a) < distance(p, b) ? a : b,
                );
          bot(p, nearest, delta: delta);
        }
        if (survival && !p.hunter) p.cover.update(coverSideAt(p), elapsed);
        p.rememberDirection();
        if (p.voiceRun &&
            !p.rushing &&
            p.dx.abs() + p.dy.abs() > .1 &&
            p.dashLeft <= 0) {
          p.energy = max(0, p.energy - 8 * delta);
        } else if (p.regenDelay == 0 && p.dashLeft <= 0) {
          p.energy = min(
            loadoutFor(p).maxEnergy,
            p.energy + 19 * loadoutFor(p).regenFactor * delta,
          );
        }
      }
      final combatPositions = {for (final p in players) p: (p.x, p.y)};
      // Small substeps preserve wall collision and contact throughout a dash.
      const substeps = 6;
      for (var step = 0; step < substeps; step++) {
        elapsed += delta / substeps;
        final activeSteam = map.steamVents.isEmpty
            ? const <SteamHazard>[]
            : hazards.where((h) => h.phase == HazardPhase.active).toList();
        for (final p in players) {
          final oldX = p.x, oldY = p.y;
          final dashing = p.dashLeft > 0;
          final mag = max(1, sqrt(p.dx * p.dx + p.dy * p.dy));
          final burst = dashing
              ? 2.1 + 2.9 * (p.dashLeft / .22)
              : p.powerSpeed * (p.voiceRun && p.energy > 0 ? 1.36 : 1.0);
          final speed =
              (p.hunter ? .202 : .188) *
              burst *
              loadoutFor(p).speedFactor *
              (p.contentMonster?.speed ?? 1) *
              (p.chargeLeft > 0
                  ? 2.5
                  : p.monster == MonsterKind.warden
                  ? .72
                  : 1.0) *
              delta /
              arenaScale /
              substeps;
          final vx = dashing ? p.dashX : p.dx / mag,
              vy = dashing ? p.dashY : p.dy / mag;
          final botPace =
              (p.isBot
                  ? (p.hunter
                        ? (survival
                              ? SurvivalRules.botPace(
                                  (campaign?.id ?? 1) ~/ 3 + wave,
                                )
                              : .78)
                        : .88)
                  : 1.0) *
              min(
                p.slowLeft > 0
                    ? .55
                    : p.abilities.sigilSlowLeft > 0
                    ? .65
                    : p.staticLeft > 0
                    ? .85
                    : 1.0,
                activeSteam.any((h) => h.vent.contains(p.x, p.y))
                    ? SteamHazard.speedFactor
                    : 1.0,
              );
          final eclipse = _eclipseMotion(p, trailing: delta / substeps);
          var nx = p.x + vx * speed * botPace, ny = p.y + vy * speed * botPace;
          if (eclipse != null) {
            final age = elapsed - eclipse.time;
            final before = eclipse.displacement(age - delta / substeps);
            final after = eclipse.displacement(age);
            nx = p.x + after.$1 - before.$1;
            ny = p.y + after.$2 - before.$2;
          }
          // A committed charge hits the whole obstacle instead of sliding along it.
          if (combat && p.chargeLeft > 0 && !valid(nx, ny)) {
            _checkChargeDodge(p);
            p.chargeLeft = p.chargeWindup = p.chargeRecovery = 0;
            p.stunLeft = 1.8;
            p.dx = p.dy = 0;
          } else if (eclipse != null &&
              valid(nx, ny) &&
              segment(p.x, p.y, nx, ny)) {
            p.x = nx;
            p.y = ny;
          } else {
            if (valid(nx, p.y) &&
                (eclipse == null || segment(p.x, p.y, nx, p.y))) {
              p.x = nx;
            }
            if (valid(p.x, ny) &&
                (eclipse == null || segment(p.x, p.y, p.x, ny))) {
              p.y = ny;
            }
          }
          p.dashLeft = max(0, p.dashLeft - delta / substeps);
          if (survival && !p.hunter) {
            p.cover.update(coverSideAt(p), elapsed);
            p.updateAmbush(
              sideHidden(p) || p.cloaked,
              delta / substeps,
              elapsed,
            );
          }
          if (!p.hunter &&
              !p.cloaked &&
              p.toolLeft <= 0 &&
              map.noisyAt(p.x, p.y) &&
              (p.x - oldX).abs() + (p.y - oldY).abs() > 1e-7) {
            p.terrainNoiseLeft = .65;
          }
          if (campaign != null &&
              !p.isBot &&
              !p.hunter &&
              (p.x - oldX).abs() + (p.y - oldY).abs() > 1e-7) {
            p.mastery.move(delta / substeps, shadowZonesAt(p.x, p.y));
          }
          p.tally.advance(
            delta / substeps,
            elapsed,
            hunter: p.hunter,
            moved: (p.x - oldX).abs() + (p.y - oldY).abs() > 1e-7,
          );
        }
        for (final hunter in players.where((p) => p.hunter).toList()) {
          tryTag(hunter);
          if (!running) break;
        }
        if (!running) break;
      }
      if (delta > 0) {
        for (final p in players) {
          final before = combatPositions[p]!;
          p.combatVx = (p.x - before.$1) / delta;
          p.combatVy = (p.y - before.$2) / delta;
        }
      }
      _tickChest(delta);
      _tickCombat(delta);
      _tickMonsterSkills(delta);
      for (final p in players) {
        _updateMonsterFacing(p);
      }
      _tickFinale();
      _checkDashEscapes();
      _checkLures();
      if (soundClock >= .5) {
        soundClock = 0;
        for (final hunter in players.where((p) => p.hunter)) {
          sound(hunter);
        }
      }
      final cleared = combat && hunterCount == 0;
      final hasWaveSlot =
          campaign != null ||
          !survival ||
          hunterCount < EndlessBalance.maxActiveMonsters;
      if (running && (cleared || left <= 0 && hasWaveSlot)) {
        if (survival) {
          if (campaign == null) {
            completedWaves++;
            _advanceEndlessWave(cleared: cleared);
          } else {
            completedWaves = wave;
            if (completedWaves == campaign!.waves.length) {
              winner = 'runners';
              endRound('Stage ${campaign!.id} complete!');
            } else if (cleared) {
              wave++;
              _prepareWave();
            } else {
              intermission = SurvivalRules.breakSeconds;
            }
            if (cleared && running) {
              message = 'Wave cleared! Wave $wave starts now!';
            } else if (running) {
              message =
                  'Wave cleared! +${campaign!.wavePoints(wave)} pts • +${campaign!.waveEssence(wave)} essence';
              for (final p in players) {
                p.dashLeft = 0;
                // The break suspends simulation, not the held movement input.
              }
            }
          }
        } else {
          winner = 'runners';
          endRound('Time is up. Remaining runners win!');
        }
      }
    }
    if (combat && !paused && (running || campaignWon)) _tickLoot(dt);
    final standings = scoreboard();
    for (final p in players) {
      if (p.onMessage == null) continue;
      Map<String, dynamic> view(Player q) => {
        'id': q.id,
        if (cooperative) 'downed': !q.isBot && q.health <= 0,
        'name': q.name,
        'skin': q.skin,
        'monster': q.monster?.name,
        if (q.contentMonster != null) 'contentMonster': q.contentMonster!.id,
        if (q.monsterForm != null) 'monsterForm': q.monsterForm!.ordinal,
        'entryLeft': q.entryLeft,
        'health': q.health.toJson(),
        'maxHealth': q.maxHealth.toJson(),
        'shotX': q.shotX,
        'shotY': q.shotY,
        'shotAge': elapsed - q.shotAt,
        'shotSerial': q.shotSerial,
        'shotEmpowered': q.abilities.lastShotEmpowered,
        'empoweredAge': elapsed - q.abilities.empoweredAt,
        'empoweredLeft': q.abilities.active[0],
        'combatTargetId': q.combatTargetId,
        'elite': q.elite,
        'spawnWave': q.spawnWave,
        if (combat && q.hunter) ...{
          'threatDepth': q.threatDepth,
          'contactDamage': q.contactDamage().toJson(),
          'chargeDamage': q.contactDamage(charging: true).toJson(),
        },
        'hurtLeft': q.hurtLeft,
        'hurtAge': elapsed - q.hurtAt,
        'damageSerial': q.damageSerial,
        'hitAge': elapsed - q.hitAt,
        if (combat) ...{
          'healthTrailFraction': q.healthTrail.fromFraction,
          'healthTrailAge': elapsed - q.healthTrail.startsAt,
        },
        'lastDamage': q.lastDamage.toJson(),
        'stunLeft': q.stunLeft,
        'ambushReady': q.ambushUntil > elapsed,
        'ambushCharging': q.ambushHeld >= .5,
        'ambushAge': elapsed - q.ambushAt,
        'dodgeAge': elapsed - q.dodgeAt,
        'chargeWindup': q.chargeWindup,
        'charging': q.chargeLeft > 0,
        'chargeX': q.chargeX,
        'chargeY': q.chargeY,
        'powerLeft': q.powerLeft,
        'powerSerial': q.powerSerial,
        'combatPowers': q.combatPowers,
        if (_eclipseMotion(q) case final cast?) ...{
          'eclipseAge': elapsed - cast.time,
          'eclipseCut': NyxEclipseMotion.cut(elapsed - cast.time),
          'eclipseDash': NyxEclipseMotion.dashing(elapsed - cast.time),
          'eclipseVx': q.combatVx,
          'eclipseVy': q.combatVy,
        },
        'lootPickupSerial': q.lootPickupSerial,
        'cloaked': q.cloaked,
        'guarded': q.guarded,
        'slowed': q.slowLeft > 0,
        'vx': q.dashLeft > 0 ? q.dashX : q.dx,
        'vy': q.dashLeft > 0 ? q.dashY : q.dy,
        'facing': q.facing,
        if (q.isBot && q.hunter && q._hasLook) ...{
          'lookX': q._lookX,
          'lookY': q._lookY,
        },
        'x': q.x,
        'y': q.y,
        'hunter': q.hunter,
        'hidden': hidden(q),
        'revealed': p.hunter && !q.hunter && canSeeRunner(p, q),
        'moving': q.dx.abs() + q.dy.abs() > .1 || q.dashLeft > 0,
        'sprint':
            q.dashLeft > 0 ||
            (q.voiceRun && q.energy > 0 || q.powerSpeed > 1) &&
                q.dx.abs() + q.dy.abs() > .1,
        'voice': q.voiceRun,
        'dash': q.dashLeft > 0,
        'dashFx': q.dashFx,
        'dashX': q.dashX,
        'dashY': q.dashY,
        'dashSerial': q.dashSerial,
        'shield': q.tagLock > 0,
      };
      final nearby = nearbyDistraction(p);
      final aim = toolFor(p) == SoloTool.stone ? stoneTarget(p) : null;
      p.send({
        'type': 'state',
        'combat': combat,
        'nyxEclipses': [
          for (final cast in eclipses)
            {
              'x': cast.x,
              'y': cast.y,
              'age': elapsed - cast.time,
              'radius': NyxEclipseCast.radius,
            },
        ],
        'timedCover': survival,
        'coverSides': survival ? p.cover.snapshot(elapsed) : const [],
        'coverActive': sideHidden(p),
        'coverRemaining': sideHidden(p) ? max(0, p.cover.until - elapsed) : 0,
        'kills': p.kills,
        'weaponXpEarned': p.weaponXpEarned.toJson(),
        'lootEssenceEarned': p.lootEssenceEarned.toJson(),
        if ((demo || cooperative) && combat && treasureChest != null)
          'treasureChest': treasureChest!.snapshot(elapsed),
        'loot': [
          for (final drop in loot)
            if (cooperative || drop.owner == p.id) drop.toJson(),
        ],
        'lootCollections': [
          for (final effect in lootCollections)
            if (effect.owner == p.id)
              {
                'kind': effect.kind,
                'amount': effect.amount,
                'x': effect.x,
                'y': effect.y,
                'age': effect.age,
              },
        ],
        'weaponLevel': loadoutFor(p).weaponLevel,
        'fireMode': WeaponRules.name(loadoutFor(p).fireMode),
        'volleyUnlocked': loadoutFor(p).fireMode == FireMode.fan,
        'fireCooldown': p.fireCooldown,
        'dungeon': survival && campaign == null,
        'dungeonBossAlive': dungeonBossAlive,
        'awaitingWaveSlot':
            campaign == null &&
            survival &&
            left <= 0 &&
            hunterCount >= EndlessBalance.maxActiveMonsters,
        'dungeonIncoming': SurvivalRules.hunters(wave),
        'dungeonCarried': players
            .where((q) => q.hunter && q.spawnWave < wave)
            .length,
        'championLevel': loadoutFor(p).level,
        'weaponCapacity': loadoutFor(p).weaponCapacity,
        'recommendedLevel': CombatRules.recommendedLevel(wave),
        'powerLimited': CombatRules.rank(wave) > loadoutFor(p).weaponCapacity,
        'combatRank': CombatRules.effectiveRank(wave, loadoutFor(p)),
        'combatDamage': CombatRules.damage(
          championWeapons[p.skin],
          wave,
          p.damageUpgrades,
          loadout: loadoutFor(p),
          hasteUpgrades: p.hasteUpgrades,
          volleyUpgrades: p.volleyUpgrades,
        ).toJson(),
        'combatInterval': CombatRules.interval(
          championWeapons[p.skin],
          wave,
          p.hasteUpgrades,
          loadout: loadoutFor(p),
        ),
        'combatShots': CombatRules.shots(
          championWeapons[p.skin],
          p.volleyUpgrades,
          loadout: loadoutFor(p),
        ),
        'combatXp': p.combatXp,
        'upgradePoints': p.upgradePoints,
        'damageUpgrades': p.damageUpgrades,
        'hasteUpgrades': p.hasteUpgrades,
        'volleyUpgrades': p.volleyUpgrades,
        'heroRole': p.hero.role.name,
        'heroPassive': p.hero.passive,
        'minorSkillSerial': p.abilities.serial,
        'minorShield': p.abilities.shield.toJson(),
        'minorSkills': [
          for (var slot = 0; slot < 3; slot++)
            {
              'slot': slot,
              'name': championAbilities[p.skin][slot].name,
              'cooldown': p.abilities.cooldowns[slot],
              'cooldownTotal':
                  championAbilities[p.skin][slot].cooldown *
                  loadoutFor(p).powerCooldownFactor,
              'active': p.abilities.active[slot],
            },
        ],
        'monsterCasts': [
          for (final cast in monsterCasts) cast.snapshot(elapsed),
        ],
        'monsterShots': [for (final shot in monsterShots) shot.snapshot()],
        'monsterSkillImpacts': [
          for (final hit in monsterSkillImpacts)
            {
              'skill': hit.skill.index,
              'x': hit.x,
              'y': hit.y,
              'age': elapsed - hit.time,
              'radius':
                  (hit.skill == MonsterSkill.proximityMines ? .06 : .04) /
                  arenaScale,
            },
        ],
        'minorSkillEffects': [
          for (final effect in minorSkillEffects) effect.snapshot(elapsed),
        ],
        'championFields': [
          for (final field in championFields) field.snapshot(elapsed),
          for (final tank in players)
            if (tank.skin == 1 &&
                tank.combatPowers &&
                !tank.hunter &&
                tank.health > 0 &&
                tank.powerLeft > 0)
              {
                'skin': 1,
                'x': tank.x,
                'y': tank.y,
                'radius': ChampionField.bastionRadius,
                'age':
                    tank.hero.duration * loadoutFor(tank).powerDurationFactor -
                    tank.powerLeft,
                'duration':
                    tank.hero.duration * loadoutFor(tank).powerDurationFactor,
              },
        ],
        'weapon': championWeapons[p.skin].name,
        'combatSecondaryEffects': [
          for (final effect in combatSecondaryEffects)
            {...effect, 'age': elapsed - (effect['time'] as double)},
        ],
        'combatDamageNumbers': [
          for (final number in combatFeedback.numbers) number.snapshot(elapsed),
        ],
        'monsterRemains': [
          for (final bones in monsterRemains) bones.snapshot(elapsed),
        ],
        'combatImpacts': [
          for (final hit in combatImpacts)
            {
              'skin': hit.skin,
              'x': hit.x,
              'y': hit.y,
              'age': elapsed - hit.time,
            },
        ],
        'projectiles': [
          for (final shot in projectiles)
            if (shot.delay <= 0)
              {
                'id': shot.id,
                'x': shot.x,
                'y': shot.y,
                'vx': shot.vx,
                'vy': shot.vy,
                'skin': shot.owner.skin,
                'empowered': shot.minorCharged,
              },
        ],
        'map': map.id,
        if (contentRelease != null) 'contentRelease': contentRelease,
        'mapTitle': map.title,
        'mapTransitionSerial': mapTransitionSerial,
        if (map.steamVents.isNotEmpty)
          'hazards': hazards.map((h) => h.toJson()).toList(),
        'hazardContact': inSteam(p),
        if (map.distractions.isNotEmpty)
          'distractions': [
            for (final site in map.distractions)
              site.toJson(
                remaining: distractionCooldown(site),
                pulse:
                    _distractionsStarted.containsKey(site.id) &&
                        elapsed - _distractionsStarted[site.id]! <
                            DistractionSite.pulseSeconds
                    ? (elapsed - _distractionsStarted[site.id]!) /
                          DistractionSite.pulseSeconds
                    : null,
              ),
          ],
        'interaction': nearby?.toJson(remaining: distractionCooldown(nearby)),
        'distractionSerial': p.distractionSerial,
        'distractionFeedback': elapsed - p.distractionAt < 1.2,

        'terrainNoise': !p.hunter && p.terrainNoiseLeft > 0 && !p.cloaked,
        'tool': toolFor(p).name,
        'toolLeft': p.toolLeft,
        if (toolFor(p) == SoloTool.stone)
          'toolAim': aim == null ? null : {'x': aim.$1, 'y': aim.$2},
        'duration': duration,
        'mode': mode.name,
        'round': round,
        'winner': winner,
        'hunters': hunterCount,
        'runners': runnerCount,
        'wave': wave,
        'completedWaves': completedWaves,
        'startWave': initialWave,
        'waveSeconds': survival ? waveSeconds : duration,
        'campaignLevel': campaign?.id,
        'campaignTitle': campaign?.title,
        if (finaleState case final finale?) 'finale': finale.toJson(),
        if (campaign != null) 'campaignStats': p.mastery.toJson(),
        'campaignWon': campaignWon,
        'waveTotal': campaign?.waves.length,
        'waveMonster': survival && campaign == null
            ? MonsterEvolution.forSpawn(monsterRosterWave, 0).kind.name
            : null,
        if (survival && campaign == null) ...{
          'evolutionCount': MonsterEvolution.unlocked(monsterRosterWave),
          'nextMonsterWave': _nextMonsterWave,
          if (MonsterEvolution.isDebut(monsterRosterWave) &&
              (MonsterEvolution.isDebut(wave) || wave == initialWave))
            'newMonsterForm': MonsterEvolution.unlocked(monsterRosterWave),
        },
        'monsterKinds': players
            .where((p) => p.monster != null)
            .map((p) => p.monster!.name)
            .toSet()
            .toList(),
        'intermission': intermission.ceil(),
        'survivalPoints': survivalPoints.toJson(),
        'ended': ended,
        'paused': paused,
        'scores': standings,
        'scoreVersion': ScoreRules.version,
        'elapsed': elapsed,
        'myScore': standings.firstWhere((q) => q['id'] == p.id),
        'moment': p.moment?.toJson(),
        'code': code,
        'demo': demo,
        if (cooperative) ...{
          'coop': true,
          'maxPlayers': 2,
          'humanCount': players.where((q) => !q.isBot).length,
          'party': [
            for (final q in players.where((q) => !q.isBot))
              {
                'id': q.id,
                'name': q.name,
                'skin': q.skin,
                'health': q.health.toJson(),
                'maxHealth': q.maxHealth.toJson(),
                'downed': q.health <= 0,
              },
          ],
        },
        'id': p.id,
        'hunter': p.hunter,
        'owner': identical(p, players.first),
        'tags': tags,
        'lastCatcher': lastCatcher,
        'running': running,
        'left': left.ceil(),
        'cooldown': p.cooldown.ceil(),
        'powerCooldown': p.powerCooldown,
        'powerCooldownTotal':
            p.hero.cooldown * loadoutFor(p).powerCooldownFactor,
        'powerLeft': p.powerLeft,
        'powerDurationTotal':
            p.hero.duration * loadoutFor(p).powerDurationFactor,
        'powerReady': p.powerCooldown <= 0,
        'hero': p.hero.name,
        'powerName': p.hero.power,
        'shield': p.tagLock.ceil(),
        'energy': p.energy.round(),
        'maxEnergy': loadoutFor(p).maxEnergy,
        'championBoosted': loadoutFor(p).boosted,
        'dashCooldown': p.dashCooldown,
        'dashReady': p.dashCooldown <= 0 && p.energy >= 30,
        'hidden': hidden(p),
        'spotted':
            hidden(p) && players.any((h) => h.hunter && canSeeRunner(h, p)),
        'message': message,
        'walls': walls,
        'self': view(p),
        'total': players.length,
        'players': visibleTo(p)
            .where((q) => !identical(q, p))
            .map(view)
            .toList(),
      });
    }
  }
}

double distance(Player a, Player b) =>
    sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2));

// Water features and trees have round silhouettes, rather than invisible
// rectangular corners. Shared by collision, cover contours and navigation.
bool roundedProp(int sprite) =>
    sprite == 0 ||
    sprite == 4 ||
    sprite == 5 ||
    sprite == 12 ||
    (sprite >= 16 && sprite <= 18);
double obstacleDistance(
  double x,
  double y,
  List<double> rect, {
  bool rounded = false,
}) {
  final radius = rounded ? min(rect[2], rect[3]) / 2 : 0.0;
  final dx = (x - rect[0] - rect[2] / 2).abs() - (rect[2] / 2 - radius);
  final dy = (y - rect[1] - rect[3] / 2).abs() - (rect[3] / 2 - radius);
  return sqrt(pow(max(dx, 0), 2) + pow(max(dy, 0), 2)) +
      min(max(dx, dy), 0) -
      radius;
}

class _Lure {
  _Lure(
    this.owner,
    this.hunter,
    this.x,
    this.y,
    this.time,
    this.token, {
    this.environment = false,
  }) : initialDistance = sqrt(pow(hunter.x - x, 2) + pow(hunter.y - y, 2)),
       initialSeparation = distance(owner, hunter),
       runnerX = owner.x,
       runnerY = owner.y;
  final int token;
  final bool environment;
  final Player owner, hunter;
  final double x, y, time, initialDistance, initialSeparation, runnerX, runnerY;
}

/// Solid scenery includes the caldera machinery and relay buildings. Slender
/// lights, open basins and chains remain non-cover ornaments. Simulation,
/// cover ribbons and shadow contours must all use this same rule.
bool providesCover(int sprite) =>
    sprite < 12 || sprite >= 15 && sprite <= 18 || sprite >= 20 && sprite <= 25;

class _DashAttempt {
  _DashAttempt(this.hunter, this.distance);
  final Player hunter;
  final double distance;
}

/// Grounded support/control zones. The owner remains free to move and dash.
class ChampionField {
  ChampionField(
    this.owner,
    this.time,
    this.x,
    this.y,
    this.duration,
    this.damage,
  );
  static const bastionRadius = .18 / arenaScale;
  static const castRange = .32 / arenaScale;
  final Player owner;
  final double time, x, y, duration;
  final GameInt damage;
  int nextPulse = 0;
  int get pulses => owner.skin == 2 ? 5 : 4;
  double get radius => (owner.skin == 2 ? .16 : .20) / arenaScale;
  Map<String, dynamic> snapshot(double now) => {
    'skin': owner.skin,
    'x': x,
    'y': y,
    'radius': radius,
    'age': now - time,
    'duration': duration,
  };
}

class NyxEclipseCast {
  NyxEclipseCast(
    this.owner,
    this.time,
    this.damage, {
    double? targetX,
    double? targetY,
  }) : x = targetX ?? owner.x,
       y = targetY ?? owner.y,
       serial = owner.powerSerial {
    final dx = x - owner.x, dy = y - owner.y;
    travel = sqrt(dx * dx + dy * dy);
    directionX = travel > .00001 ? dx / travel : owner.aimX;
    directionY = travel > .00001 ? dy / travel : owner.aimY;
  }
  // Shared by damage, the cast perimeter and the aim preview.
  static const radius = .14 / arenaScale;
  static const castRange = EclipseTargeting.reach / arenaScale;
  final Player owner;
  final double time, x, y;
  late final double travel, directionX, directionY;
  double sweepScale = 1;
  (double, double) displacement(double age) {
    final local = NyxEclipseMotion.offset(age);
    final forward =
        local.$1 / arenaScale * sweepScale +
        NyxEclipseMotion.approach(age) * travel;
    final side = local.$2 / arenaScale * sweepScale;
    return (
      forward * directionX - side * directionY,
      forward * directionY + side * directionX,
    );
  }

  final GameInt damage;
  final int serial;
  int nextPulse = 0;
  bool motionCancelled = false;
}

class CombatProjectile {
  CombatProjectile(
    this.id,
    this.owner,
    this.x,
    this.y,
    this.vx,
    this.vy, {
    Object damage = 1,
    this.volley = 0,
    this.target,
    this.piercing = false,
    this.delay = 0,
    this.guidanceDelay = 0,
    this.pattern = ShotPattern.aimed,
    this.effect = HitEffect.direct,
    this.weavePhase = 0,
    this.ricochetsLeft = 0,
    this.minorCharged = false,
    this.minorSerial = 0,
  }) : damage = GameInt.parse(damage);
  final GameInt damage;
  final bool minorCharged;
  final int minorSerial;
  final int volley;
  final ShotPattern pattern;
  final HitEffect effect;
  final double weavePhase;
  int ricochetsLeft;
  double age = 0;
  final bool piercing;
  double delay, guidanceDelay;
  final int id;
  final Player owner;
  double x, y;
  double vx, vy;
  Player? target;
  double life = .8;
  final hits = <String>{};
}
