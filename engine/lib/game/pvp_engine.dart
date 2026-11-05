part of 'engine.dart';

extension PvpEngine on Room {
  bool _hostile(Player owner, Player target) => pvp
      ? !target.isBot && !identical(owner, target) && target.health > 0
      : target.hunter;

  bool _canAutoTarget(Player owner, Player target) =>
      _hostile(owner, target) && (!pvp || !hidden(target));

  bool _canProjectileHit(CombatProjectile shot, Player target) =>
      _hostile(shot.owner, target) &&
      (!pvp || !hidden(target) || shot.manuallyTargeted);

  void _finishPvpTimer() {
    if (!running || !pvp) return;
    final living = players.where((p) => !p.isBot && p.health > 0).toList();
    if (living.length < 2) {
      winner = living.firstOrNull?.id ?? 'draw';
    } else {
      final comparison = (living[0].health * living[1].maxHealth).compareTo(
        living[1].health * living[0].maxHealth,
      );
      winner = comparison == 0 ? 'draw' : living[comparison > 0 ? 0 : 1].id;
    }
    final champion = players.where((p) => p.id == winner).firstOrNull;
    endRound(
      champion == null ? 'Duel drawn.' : '${champion.name} wins the duel!',
    );
  }
}
