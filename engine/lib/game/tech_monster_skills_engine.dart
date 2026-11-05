part of 'engine.dart';

/// Tech attacks use the same damage, cover, collision and pause rules as spells.
/// Their warnings and active geometry are published from this simulation.
extension TechMonsterSkillsEngine on Room {
  void _monsterImpact(MonsterSkill skill, double x, double y) {
    if (monsterSkillImpacts.length >= 24) monsterSkillImpacts.removeAt(0);
    monsterSkillImpacts.add((skill: skill, x: x, y: y, time: elapsed));
  }

  void _prepareTechCast(MonsterCast cast) {
    if (cast.skill == MonsterSkill.railBeam) {
      cast.beamX = cast.originX;
      cast.beamY = cast.originY;
      final steps = (MonsterCast.beamReach / .003).ceil();
      for (var i = 1; i <= steps; i++) {
        final length = MonsterCast.beamReach * i / steps;
        final x = cast.originX + cos(cast.angle) * length;
        final y = cast.originY + sin(cast.angle) * length;
        if (!valid(x, y)) break;
        cast.beamX = x;
        cast.beamY = y;
      }
    } else if (cast.skill == MonsterSkill.proximityMines &&
        cast.placedCenters == null) {
      cast.placedCenters = cast.centers
          .where(
            (point) =>
                valid(point.$1, point.$2) &&
                _monsterLine(cast.originX, cast.originY, point.$1, point.$2),
          )
          .toList();
    }
  }

  double _beamDistance(MonsterCast cast, Player hero) {
    final dx = cast.beamX - cast.originX, dy = cast.beamY - cast.originY;
    final lengthSquared = dx * dx + dy * dy;
    final t = lengthSquared == 0
        ? 0.0
        : (((hero.x - cast.originX) * dx + (hero.y - cast.originY) * dy) /
                  lengthSquared)
              .clamp(0.0, 1.0);
    return sqrt(
      pow(hero.x - cast.originX - dx * t, 2) +
          pow(hero.y - cast.originY - dy * t, 2),
    );
  }

  bool _tickTechCast(
    MonsterCast cast,
    List<Player> champions,
    double delta,
    double activeAge,
  ) {
    switch (cast.skill) {
      case MonsterSkill.railBeam:
        for (final hero in champions) {
          if (_beamDistance(cast, hero) <=
                  MonsterCast.beamHalfWidth + playerRadius &&
              _monsterLine(cast.originX, cast.originY, hero.x, hero.y)) {
            if (_damageChampion(cast.owner, hero, cast.damage.max(1))) {
              _monsterImpact(cast.skill, hero.x, hero.y);
            }
          }
          if (!running) return true;
        }
        return true;
      case MonsterSkill.magneticWell:
        if (!_monsterLine(cast.originX, cast.originY, cast.x, cast.y)) {
          return true;
        }
        for (final hero in champions) {
          var distance = sqrt(
            pow(hero.x - cast.x, 2) + pow(hero.y - cast.y, 2),
          );
          if (distance > cast.radius ||
              !_monsterLine(cast.x, cast.y, hero.x, hero.y)) {
            continue;
          }
          // Normal movement beats the pull. Dashes and Eclipse retain control.
          if (distance > .001 &&
              hero.dashLeft <= 0 &&
              _eclipseMotion(hero) == null) {
            final pull = min(distance, .04 / arenaScale * delta);
            final nx = hero.x + (cast.x - hero.x) / distance * pull;
            final ny = hero.y + (cast.y - hero.y) / distance * pull;
            if (valid(nx, ny) && _monsterLine(hero.x, hero.y, nx, ny)) {
              hero.combatVx += (nx - hero.x) / delta;
              hero.combatVy += (ny - hero.y) / delta;
              hero.x = nx;
              hero.y = ny;
            }
          }
          distance = sqrt(pow(hero.x - cast.x, 2) + pow(hero.y - cast.y, 2));
          if (distance <= MonsterCast.magnetCore + playerRadius &&
              _damageChampion(cast.owner, hero, cast.damage.max(1))) {
            _monsterImpact(cast.skill, hero.x, hero.y);
          }
          if (!running) return true;
        }
        return true;
      case MonsterSkill.proximityMines:
        for (var i = 0; i < cast.centers.length; i++) {
          final point = cast.centers[i];
          if (!cast.mineTriggeredAt.containsKey(i) &&
              activeAge <= 3.5 &&
              champions.any(
                (hero) =>
                    sqrt(
                          pow(hero.x - point.$1, 2) + pow(hero.y - point.$2, 2),
                        ) <=
                        MonsterCast.mineTrigger + playerRadius &&
                    _monsterLine(point.$1, point.$2, hero.x, hero.y),
              )) {
            cast.mineTriggeredAt[i] = elapsed;
          }
          final triggered = cast.mineTriggeredAt[i];
          if (triggered == null) continue;
          final age = elapsed - triggered;
          if (age < MonsterCast.mineFuse || age > MonsterCast.mineFuse + .25) {
            continue;
          }
          if (cast.mineExploded.add(i)) {
            _monsterImpact(cast.skill, point.$1, point.$2);
          }
          for (final hero in champions) {
            if (sqrt(pow(hero.x - point.$1, 2) + pow(hero.y - point.$2, 2)) <=
                    cast.radius + playerRadius &&
                _monsterLine(point.$1, point.$2, hero.x, hero.y)) {
              _damageChampion(cast.owner, hero, cast.damage.max(1));
            }
            if (!running) return true;
          }
        }
        return true;
      case MonsterSkill.hunterDrones:
        return true; // Projectiles own their steering and collision lifetime.
      default:
        return false;
    }
  }

  void _steerTechShot(MonsterShot shot, List<Player> champions, double delta) {
    if (shot.cast.skill != MonsterSkill.hunterDrones || shot.lostLock) return;
    if (shot.homingTarget == null) {
      final candidates =
          champions
              .where(
                (hero) =>
                    !hidden(hero) &&
                    _monsterLine(shot.x, shot.y, hero.x, hero.y),
              )
              .toList()
            ..sort(
              (a, b) => (pow(a.x - shot.x, 2) + pow(a.y - shot.y, 2)).compareTo(
                pow(b.x - shot.x, 2) + pow(b.y - shot.y, 2),
              ),
            );
      if (candidates.isNotEmpty) shot.homingTarget = candidates.first;
    }
    final target = shot.homingTarget;
    if (target == null ||
        !champions.contains(target) ||
        hidden(target) ||
        !_monsterLine(shot.x, shot.y, target.x, target.y)) {
      shot.lostLock = true;
      return;
    }
    final angle = atan2(shot.vy, shot.vx),
        wanted = atan2(target.y - shot.y, target.x - shot.x);
    final error = atan2(sin(wanted - angle), cos(wanted - angle));
    final turned = angle + error.clamp(-1.35 * delta, 1.35 * delta);
    final speed = .24 / arenaScale;
    shot.vx = cos(turned) * speed;
    shot.vy = sin(turned) * speed;
  }
}
