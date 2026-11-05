part of 'engine.dart';

/// A target is locked at the beginning of the warning; casts never track the
/// champion during their windup. Fired ground hazards can outlive their caster.
class MonsterCast {
  MonsterCast(this.owner, this.skill, this.time, this.x, this.y)
    : originX = owner.x,
      originY = owner.y,
      damage = (owner.contactDamage() * 65 + 99) ~/ 100 {
    beamX = originX + cos(angle) * beamReach;
    beamY = originY + sin(angle) * beamReach;
  }
  final Player owner;
  final MonsterSkill skill;
  final double time, originX, originY, x, y;
  final GameInt damage;
  bool fired = false;
  double beamX = 0, beamY = 0;
  final mineTriggeredAt = <int, double>{};
  final mineExploded = <int>{};
  List<(double, double)>? placedCenters;
  static const beamReach = .34 / arenaScale, beamHalfWidth = .012 / arenaScale;
  static const magnetCore = .027 / arenaScale;
  static const mineTrigger = .035 / arenaScale, mineFuse = .35;
  double get angle => atan2(y - originY, x - originX);
  double get radius => switch (skill) {
    MonsterSkill.thornRing => .095 / arenaScale,
    MonsterSkill.riftOrbs => .09 / arenaScale,
    MonsterSkill.magneticWell => .11 / arenaScale,
    MonsterSkill.proximityMines => .06 / arenaScale,
    _ => .055 / arenaScale,
  };
  List<(double, double)> get centers =>
      placedCenters ??
      switch (skill) {
        MonsterSkill.thornRing || MonsterSkill.riftOrbs => [(originX, originY)],
        MonsterSkill.proximityMines => [
          (x, y),
          for (final side in [-1, 1])
            (
              x - sin(angle) * side * .09 / arenaScale,
              y + cos(angle) * side * .09 / arenaScale,
            ),
        ],
        MonsterSkill.meteorLine => [
          for (var i = -1; i <= 1; i++)
            (
              x + cos(angle) * i * .075 / arenaScale,
              y + sin(angle) * i * .075 / arenaScale,
            ),
        ],
        _ => [(x, y)],
      };
  Map<String, dynamic> snapshot(double now) => {
    'caster': owner.id,
    'skill': skill.index,
    'age': now - time,
    'windup': skill.windup,
    'duration': skill.windup + skill.activeSeconds,
    'x': originX,
    'y': originY,
    'targetX': x,
    'targetY': y,
    'radius': radius,
    'angle': angle,
    if (skill == MonsterSkill.railBeam) ...{
      'beamX': beamX,
      'beamY': beamY,
      'beamHalfWidth': beamHalfWidth,
    },
    if (skill == MonsterSkill.magneticWell) 'coreRadius': magnetCore,
    if (skill == MonsterSkill.proximityMines) ...{
      'mineTrigger': mineTrigger,
      'mineFuse': mineFuse,
      'mines': [
        for (var i = 0; i < centers.length; i++)
          {
            'x': centers[i].$1,
            'y': centers[i].$2,
            'triggerAge': mineTriggeredAt[i] == null
                ? null
                : now - mineTriggeredAt[i]!,
            'exploded': mineExploded.contains(i),
          },
      ],
    },
    'centers': [
      for (final c in centers) [c.$1, c.$2],
    ],
  };
}

class MonsterShot {
  MonsterShot(this.cast, double angle)
    : x = cast.originX,
      y = cast.originY,
      vx =
          cos(angle) *
          (cast.skill == MonsterSkill.hunterDrones ? .24 : .28) /
          arenaScale,
      vy =
          sin(angle) *
          (cast.skill == MonsterSkill.hunterDrones ? .24 : .28) /
          arenaScale {
    if (cast.skill == MonsterSkill.hunterDrones) life = 2.6;
  }
  final MonsterCast cast;
  double x, y, vx, vy, life = 1.7;
  Player? homingTarget;
  bool lostLock = false;
  Map<String, dynamic> snapshot() => {
    'skill': cast.skill.index,
    'x': x,
    'y': y,
    'vx': vx,
    'vy': vy,
    'angle': atan2(vy, vx),
  };
}

extension MonsterSkillsEngine on Room {
  bool _monsterLine(double x, double y, double tx, double ty) {
    final steps = max(1, (sqrt(pow(tx - x, 2) + pow(ty - y, 2)) / .006).ceil());
    for (var i = 1; i <= steps; i++) {
      if (!valid(x + (tx - x) * i / steps, y + (ty - y) * i / steps)) {
        return false;
      }
    }
    return true;
  }

  void _tickMonsterSkills(double delta) {
    if (!combat || !running || delta <= 0) return;
    final champions = players
        .where((p) => !p.hunter && !p.isBot && p.health > 0)
        .toList();
    monsterSkillImpacts.removeWhere((hit) => elapsed - hit.time >= .4);
    monsterCasts.removeWhere(
      (cast) =>
          elapsed - cast.time >= cast.skill.windup + cast.skill.activeSeconds ||
          ((!cast.fired || cast.skill.holdsCaster) &&
              (!players.contains(cast.owner) ||
                  cast.owner.health <= 0 ||
                  cast.owner.stunLeft > 0)),
    );
    for (final cast in monsterCasts) {
      _prepareTechCast(cast);
      final activeAge = elapsed - cast.time - cast.skill.windup;
      if (activeAge < 0) continue;
      if (!cast.fired) {
        cast.fired = true;
        final angles = cast.skill.shotAngles(cast.angle);
        for (final angle in angles) {
          if (monsterShots.length < 64) {
            monsterShots.add(MonsterShot(cast, angle));
          }
        }
      }
      if (_tickTechCast(cast, champions, delta, activeAge)) {
        if (!running) return;
        continue;
      }
      for (final hero in champions) {
        var hit = false;
        if (cast.skill == MonsterSkill.riftOrbs) {
          for (var i = 0; i < 3; i++) {
            final a = activeAge * 2.4 + i * 2 * pi / 3;
            final ox = cast.originX + cos(a) * cast.radius;
            final oy = cast.originY + sin(a) * cast.radius;
            if (sqrt(pow(hero.x - ox, 2) + pow(hero.y - oy, 2)) <
                    .026 / arenaScale &&
                _monsterLine(cast.originX, cast.originY, ox, oy) &&
                _monsterLine(ox, oy, hero.x, hero.y)) {
              hit = true;
            }
          }
        } else if (cast.skill == MonsterSkill.thornRing) {
          final d = sqrt(
            pow(hero.x - cast.originX, 2) + pow(hero.y - cast.originY, 2),
          );
          hit =
              (d - cast.radius).abs() < .022 / arenaScale &&
              _monsterLine(cast.originX, cast.originY, hero.x, hero.y);
        } else if (const [
          MonsterSkill.stormStrike,
          MonsterSkill.venomPool,
          MonsterSkill.meteorLine,
        ].contains(cast.skill)) {
          for (var i = 0; i < cast.centers.length; i++) {
            final center = cast.centers[i];
            final localAge =
                activeAge -
                (cast.skill == MonsterSkill.meteorLine ? i * .25 : 0);
            final lifetime = cast.skill == MonsterSkill.venomPool ? 3.0 : .4;
            if (localAge < 0 || localAge > lifetime) continue;
            if (sqrt(pow(hero.x - center.$1, 2) + pow(hero.y - center.$2, 2)) <=
                    cast.radius + playerRadius &&
                _monsterLine(
                  cast.originX,
                  cast.originY,
                  center.$1,
                  center.$2,
                ) &&
                _monsterLine(center.$1, center.$2, hero.x, hero.y)) {
              hit = true;
            }
          }
        }
        if (hit) {
          _damageChampion(cast.owner, hero, cast.damage.max(1));
        }
        if (!running) return;
      }
    }
    for (final shot in monsterShots) {
      _steerTechShot(shot, champions, delta);
      shot.life -= delta;
      for (var step = 0; step < 8 && shot.life > 0; step++) {
        shot.x += shot.vx * delta / 8;
        shot.y += shot.vy * delta / 8;
        if (!valid(shot.x, shot.y)) {
          _monsterImpact(shot.cast.skill, shot.x, shot.y);
          shot.life = 0;
          break;
        }
        for (final hero in champions) {
          if (sqrt(pow(hero.x - shot.x, 2) + pow(hero.y - shot.y, 2)) >
              .024 / arenaScale) {
            continue;
          }
          final before = hero.health;
          final hit = _damageChampion(
            shot.cast.owner,
            hero,
            shot.cast.damage.max(1),
          );
          if (hit &&
              hero.health < before &&
              shot.cast.skill == MonsterSkill.frostLance) {
            hero.slowLeft = max(hero.slowLeft, .6);
          }
          _monsterImpact(shot.cast.skill, shot.x, shot.y);
          shot.life = 0;
          break;
        }
      }
      if (!running) return;
    }
    monsterShots.removeWhere((shot) => shot.life <= 0);
    if (elapsed < _nextMonsterCast || monsterCasts.length >= 3) return;
    for (final enemy in players) {
      if (!enemy.isBot ||
          !enemy.hunter ||
          enemy.monsterForm == null ||
          enemy.health <= 0 ||
          enemy.entryLeft > 0 ||
          enemy.stunLeft > 0 ||
          enemy.chargeWindup > 0 ||
          enemy.chargeLeft > 0 ||
          enemy.chargeRecovery > 0 ||
          enemy.monsterSkillCooldown > 0 ||
          monsterCasts.any((c) => c.owner == enemy)) {
        continue;
      }
      final skill = enemy.monsterForm!.skill;
      final range = skill == MonsterSkill.railBeam
          ? MonsterCast.beamReach
          : skill == MonsterSkill.thornRing || skill == MonsterSkill.riftOrbs
          ? .13 / arenaScale
          : .38 / arenaScale;
      final targets =
          champions
              .where(
                (hero) =>
                    distance(enemy, hero) < range &&
                    canSeeRunner(enemy, hero) &&
                    _monsterLine(enemy.x, enemy.y, hero.x, hero.y),
              )
              .toList()
            ..sort((a, b) => distance(enemy, a).compareTo(distance(enemy, b)));
      if (targets.isEmpty) continue;
      final target = targets.first;
      final cast = MonsterCast(enemy, skill, elapsed, target.x, target.y);
      _prepareTechCast(cast);
      monsterCasts.add(cast);
      enemy.monsterSkillCooldown = skill.cooldown;
      enemy.dx = enemy.dy = 0;
      _nextMonsterCast = elapsed + .65;
      break;
    }
  }
}
