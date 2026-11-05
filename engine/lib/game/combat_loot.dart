import 'game_int.dart';

/// Normalized world distances shared by simulation and collection feedback.
abstract final class LootRules {
  static const magnetRadius = .105;
  static const collectRadius = .012;
  static const settleSeconds = .25;
  static const maxDrops = 512;
}

enum LootKind { xp, essence }

class CombatLoot {
  CombatLoot({
    required this.id,
    required this.owner,
    required this.kind,
    required this.x,
    required this.y,
    required Object amount,
    this.combatXp = 0,
  }) : _amount = GameInt.parse(amount);
  final int id;
  final String owner;
  final LootKind kind;
  double x, y;
  GameInt _amount;
  GameInt get amount => _amount;
  set amount(Object value) => _amount = GameInt.parse(value).max(0);
  int combatXp;
  double age = 0, speed = .12, vx = 0, vy = 0;
  bool attracted = false;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'x': x,
    'y': y,
    'amount': amount.toJson(),
    'age': age,
    'attracted': attracted,
    'vx': vx,
    'vy': vy,
  };
}
