import 'game_int.dart';

/// A floating number contains HP actually removed by one attack from one target.
/// It lives independently of the target so lethal hits remain visible.
class CombatDamageNumber {
  CombatDamageNumber({
    required this.id,
    required this.owner,
    required this.target,
    required this.volley,
    required Object damage,
    required this.x,
    required this.y,
    required this.time,
  }) : damage = GameInt.parse(damage);
  final int id, volley;
  final String owner, target;
  GameInt damage;
  int hits = 1;
  double x, y, time;
  Map<String, dynamic> snapshot(double now) => {
    'id': id,
    'owner': owner,
    'target': target,
    'volley': volley,
    'damage': damage.toJson(),
    'hits': hits,
    'x': x,
    'y': y,
    'age': now - time,
  };
}

class CombatFeedback {
  static const lifetime = .8;
  int _serial = 0;
  final numbers = <CombatDamageNumber>[];

  void record({
    required String owner,
    required String target,
    required int volley,
    required GameInt damage,
    required double x,
    required double y,
    required double time,
  }) {
    if (damage <= 0) return;
    final existing = numbers
        .where(
          (n) => n.owner == owner && n.target == target && n.volley == volley,
        )
        .firstOrNull;
    if (existing == null) {
      numbers.add(
        CombatDamageNumber(
          id: ++_serial,
          owner: owner,
          target: target,
          volley: volley,
          damage: damage,
          x: x,
          y: y,
          time: time,
        ),
      );
    } else {
      existing.damage += damage;
      existing.hits++;
      existing.x = x;
      existing.y = y;
      existing.time = time;
    }
  }

  void expire(double now) =>
      numbers.removeWhere((n) => now - n.time > lifetime);
  void clear() {
    numbers.clear();
    _serial = 0;
  }
}
