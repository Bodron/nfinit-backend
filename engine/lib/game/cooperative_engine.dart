part of 'engine.dart';

/// Co-op changes are opt-in; offline survival and infection retain their rules.
extension CooperativeEngine on Room {
  bool _downCoopChampion(Player enemy, Player hero) {
    hero.health = 0;
    hero.setMovement(0, 0);
    hero.dashLeft = hero.powerLeft = 0;
    hero.voiceRun = false;
    hero.abilities.reset();
    hero.tally.caught();
    tags++;
    enemy.catches++;
    lastCatcher = enemy.id;
    final living = players.where((p) => !p.isBot && !p.hunter && p.health > 0);
    if (living.isEmpty) {
      winner = 'hunters';
      endRound(
        'Both champions fell on wave $wave. Cleared $completedWaves waves.',
      );
    } else {
      message =
          '${hero.name} is down. Survive to the next wave to bring them back!';
    }
    return true;
  }

  void _reviveCoopTeammates() {
    final living = players
        .where((p) => !p.isBot && !p.hunter && p.health > 0)
        .firstOrNull;
    if (living == null) return;
    for (final hero in players.where(
      (p) => !p.isBot && !p.hunter && p.health <= 0,
    )) {
      hero.health = ((hero.maxHealth * 40 + 99) ~/ 100).max(1);
      hero.hurtLeft = hero.tagLock = 3;
      hero.setMovement(0, 0);
      hero.x = living.x;
      hero.y = living.y;
      hero.cover.reset();
    }
  }
}
