part of 'engine.dart';

class MinorSkillEffect {
  MinorSkillEffect(
    this.owner,
    this.slot,
    this.x,
    this.y,
    this.time,
    this.duration, {
    this.follow,
    this.radius = 0,
    this.phase = 'cast',
    this.manuallyTargeted = false,
  });
  final bool manuallyTargeted;
  final Player owner;
  final int slot;
  final double x, y, time, duration, radius;
  final Player? follow;
  final String phase;
  Map<String, dynamic> snapshot(double now) => {
    'skin': owner.skin,
    'slot': slot,
    'x': follow?.x ?? x,
    'y': follow?.y ?? y,
    'age': now - time,
    'duration': duration,
    'radius': radius,
    'phase': phase,
  };
}

class _LivingSeed {
  _LivingSeed(this.owner, this.target, this.damage, this.time);
  final Player owner, target;
  final GameInt damage;
  final double time;
}

extension ChampionAbilitySimulation on Room {
  bool _livingChampion(Player p) =>
      players.contains(p) && !p.hunter && !p.isBot && p.health > 0;

  List<Player> _abilityAllies(Player p) => players
      .where(
        (q) =>
            _livingChampion(q) &&
            (!pvp || identical(p, q)) &&
            distance(p, q) <= MinorSkillRules.supportRange &&
            clearPath(p, q),
      )
      .toList();

  void _minorEffect(
    Player p,
    int slot,
    double duration, {
    Player? at,
    bool follow = false,
    double? x,
    double? y,
    double radius = 0,
    String phase = 'cast',
    bool manuallyTargeted = false,
  }) {
    final target = at ?? p;
    minorSkillEffects.add(
      MinorSkillEffect(
        p,
        slot,
        x ?? target.x,
        y ?? target.y,
        elapsed,
        duration,
        follow: follow ? target : null,
        radius: radius,
        phase: phase,
        manuallyTargeted: manuallyTargeted,
      ),
    );
    if (minorSkillEffects.length > 64) minorSkillEffects.removeAt(0);
  }

  bool tryMinorSkill(Player p, int slot, {double? targetX, double? targetY}) {
    if (!combat ||
        !running ||
        paused ||
        intermission > 0 ||
        !_livingChampion(p) ||
        slot < 0 ||
        slot >= 3 ||
        p.abilities.cooldowns[slot] > 0) {
      return false;
    }
    final spec = championAbilities[p.skin][slot];
    final targeted = targetX != null || targetY != null;
    if (targeted &&
        (!spec.targeted ||
            targetX == null ||
            targetY == null ||
            !EclipseTargeting.valid(
              p.x,
              p.y,
              targetX,
              targetY,
              range: MinorSkillRules.castRange,
              canStand: valid,
            ))) {
      return false;
    }
    var x = targetX ?? p.x, y = targetY ?? p.y;
    if (spec.targeted && !targeted) {
      final targets =
          players
              .where(
                (q) =>
                    _canAutoTarget(p, q) &&
                    q.health > 0 &&
                    q.entryLeft <= 0 &&
                    distance(p, q) <= MinorSkillRules.castRange &&
                    clearPath(p, q),
              )
              .toList()
            ..sort((a, b) => distance(p, a).compareTo(distance(p, b)));
      if (targets.isNotEmpty) {
        x = targets.first.x;
        y = targets.first.y;
      }
    }
    p.abilities.cooldowns[slot] =
        spec.cooldown * loadoutFor(p).powerCooldownFactor;
    p.abilities.active[slot] = spec.duration;
    p.abilities.serial++;
    p.tally.activity(elapsed);
    if (slot == 0) {
      p.abilities.chargeSerial = p.abilities.serial;
      p.abilities.empoweredAt = elapsed;
      _minorEffect(p, slot, .55, follow: true);
      return true;
    }
    if (p.skin == 0 && slot == 1) {
      _minorEffect(p, slot, spec.duration);
      for (final enemy in players.where(
        (q) => q.isBot && q.hunter && q.entryLeft <= 0,
      )) {
        if (distance(p, enemy) <= MinorSkillRules.supportRange &&
            clearPath(p, enemy)) {
          enemy.shadowEchoUntil = elapsed + spec.duration;
          enemy.shadowEchoX = p.x;
          enemy.shadowEchoY = p.y;
          enemy.aiClock = 0;
        }
      }
    } else if (p.skin == 0 && slot == 2) {
      p.abilities.speedLeft = spec.duration;
      _minorEffect(p, slot, spec.duration, follow: true);
    } else if ((p.skin == 1 || p.skin == 3) && slot == 1) {
      final percent = p.skin == 1 ? 10 : 8;
      p.abilities.shield = (p.maxHealth * percent + 99) ~/ 100;
      p.abilities.shieldLeft = spec.duration;
      _minorEffect(p, slot, spec.duration, follow: true);
    } else if (p.skin == 1 && slot == 2) {
      final allies = _abilityAllies(p)..remove(p);
      allies.sort((a, b) => distance(p, a).compareTo(distance(p, b)));
      final target = allies.isEmpty ? p : allies.first;
      target.abilities.protectionLeft = spec.duration;
      _minorEffect(p, slot, spec.duration, at: target, follow: true);
    } else if (p.skin == 2 && slot == 1) {
      final allies = _abilityAllies(p)..remove(p);
      allies.sort(
        (a, b) => (a.health / a.maxHealth).compareTo(b.health / b.maxHealth),
      );
      for (final ally in [p, if (allies.isNotEmpty) allies.first]) {
        ally.health = (ally.health + ((ally.maxHealth * 6 + 99) ~/ 100)).min(
          ally.maxHealth,
        );
        _minorEffect(p, slot, spec.duration, at: ally, follow: true);
      }
    } else if (p.skin == 2 && slot == 2) {
      for (final ally in _abilityAllies(p)) {
        ally.abilities.speedLeft = max(ally.abilities.speedLeft, spec.duration);
        _minorEffect(p, slot, spec.duration, at: ally, follow: true);
      }
    } else if (p.skin == 3 && slot == 2) {
      _minorEffect(
        p,
        slot,
        spec.duration,
        x: x,
        y: y,
        radius: MinorSkillRules.sigilRadius,
        manuallyTargeted: targeted,
      );
    }
    return true;
  }

  GameInt _absorbMinorShield(Player p, GameInt damage) {
    if (p.abilities.protectionLeft > 0) damage = (damage * 80 + 99) ~/ 100;
    final absorbed = p.abilities.shieldLeft > 0
        ? damage.min(p.abilities.shield)
        : GameInt.zero;
    p.abilities.shield = (p.abilities.shield - absorbed).max(0);
    if (p.abilities.shield <= 0) {
      p.abilities.shieldLeft = 0;
      if (p.skin == 1 || p.skin == 3) p.abilities.active[1] = 0;
    }
    return (damage - absorbed).max(0);
  }

  void _minorProjectileImpact(
    CombatProjectile shot,
    Player target,
    Set<Player> dead,
  ) {
    if (!shot.minorCharged ||
        shot.minorSerial <= 0 ||
        !_livingChampion(shot.owner)) {
      return;
    }
    _minorEffect(shot.owner, 0, .55, at: target, phase: 'impact');
    if (shot.owner.abilities.consumedSerial >= shot.minorSerial) return;
    shot.owner.abilities.consumedSerial = shot.minorSerial;
    final owner = shot.owner;
    if (owner.skin == 1 && !target.elite && target.health > 0) {
      final length = distance(owner, target);
      if (length > .001) {
        final dx = (target.x - owner.x) / length;
        final dy = (target.y - owner.y) / length;
        for (var i = 0; i < 8; i++) {
          final x = target.x + dx * .005 / arenaScale;
          final y = target.y + dy * .005 / arenaScale;
          if (!valid(x, y) || !segment(target.x, target.y, x, y)) break;
          target.x = x;
          target.y = y;
        }
      }
    } else if (owner.skin == 2) {
      livingSeeds.add(
        _LivingSeed(owner, target, (shot.damage * 75 + 99) ~/ 100, elapsed),
      );
    } else if (owner.skin == 3) {
      final others =
          players
              .where(
                (q) =>
                    _canAutoTarget(owner, q) &&
                    q.health > 0 &&
                    !dead.contains(q) &&
                    q != target &&
                    q.entryLeft <= 0 &&
                    distance(q, target) <= .14 / arenaScale &&
                    clearPath(q, target),
              )
              .toList()
            ..sort(
              (a, b) => distance(a, target).compareTo(distance(b, target)),
            );
      if (others.isNotEmpty) {
        final next = others.first;
        combatSecondaryEffects.add({
          'kind': 'chain',
          'skin': owner.skin,
          'x': target.x,
          'y': target.y,
          'toX': next.x,
          'toY': next.y,
          'time': elapsed,
        });
        _damageMonster(
          CombatProjectile(
            -shot.id,
            owner,
            target.x,
            target.y,
            0,
            0,
            volley: -3000000 - shot.minorSerial,
          ),
          next,
          ((shot.damage + 1) ~/ 2).max(1),
          dead,
        );
      }
    }
  }

  void _tickMinorSkills(Set<Player> dead) {
    for (final field in minorSkillEffects) {
      if (field.radius <= 0 ||
          elapsed - field.time >= field.duration ||
          !_livingChampion(field.owner)) {
        continue;
      }
      for (final enemy in players.where(
        (q) =>
            _hostile(field.owner, q) &&
            (!pvp || !hidden(q) || field.manuallyTargeted) &&
            q.health > 0 &&
            q.entryLeft <= 0,
      )) {
        if (sqrt(pow(enemy.x - field.x, 2) + pow(enemy.y - field.y, 2)) <=
                field.radius &&
            segment(field.x, field.y, enemy.x, enemy.y)) {
          enemy.abilities.sigilSlowLeft = max(
            enemy.abilities.sigilSlowLeft,
            .12,
          );
        }
      }
    }
    for (final seed
        in livingSeeds.where((s) => elapsed - s.time >= 1).toList()) {
      livingSeeds.remove(seed);
      if (!_livingChampion(seed.owner) || (pvp && hidden(seed.target))) {
        continue;
      }
      _minorEffect(seed.owner, 0, .65, at: seed.target, phase: 'burst');
      final shot = CombatProjectile(
        -seed.owner.abilities.serial,
        seed.owner,
        seed.target.x,
        seed.target.y,
        0,
        0,
        volley: -4000000 - seed.owner.abilities.serial,
      );
      for (final enemy in players.where(
        (q) =>
            _canAutoTarget(seed.owner, q) &&
            q.health > 0 &&
            !dead.contains(q) &&
            q.entryLeft <= 0 &&
            distance(q, seed.target) <= .075 / arenaScale &&
            segment(seed.target.x, seed.target.y, q.x, q.y),
      )) {
        _damageMonster(shot, enemy, seed.damage, dead);
      }
    }
    livingSeeds.removeWhere((s) => !_livingChampion(s.owner));
    minorSkillEffects.removeWhere(
      (e) =>
          elapsed - e.time >= e.duration ||
          !_livingChampion(e.owner) ||
          (e.slot == 1 &&
              (e.owner.skin == 1 || e.owner.skin == 3) &&
              e.owner.abilities.shieldLeft <= 0) ||
          (e.follow != null && !_livingChampion(e.follow!)),
    );
  }
}
