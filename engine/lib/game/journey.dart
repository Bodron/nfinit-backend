import 'dart:convert';
import 'dart:math' as math;

import 'champion_progress.dart';
import 'heroes.dart' as roster;

class JourneyBadge {
  const JourneyBadge(this.id, this.title, this.description, this.target);
  final String id, title, description;
  final int target;
}

const journeyBadges = [
  JourneyBadge('first', 'First Steps', 'Finish your first active round.', 1),
  JourneyBadge('catch', 'Found You!', 'Make 3 captures.', 3),
  JourneyBadge('power', 'Magic Under Control', 'Use your power 10 times.', 10),
  JourneyBadge(
    'active',
    'Always Moving',
    'Stay active for 60s in one round.',
    60,
  ),
  JourneyBadge(
    'heroes',
    'Four Destinies',
    'Finish a round with every hero.',
    4,
  ),
  JourneyBadge('rounds', 'One More!', 'Finish 5 active rounds.', 5),
];

/// Personal, device-local accomplishments. They never alter match rules.
class Journey {
  int rounds = 0, catches = 0, powers = 0, bestActive = 0;
  final heroes = <int>{};
  final claimed = <String>[];

  static Journey decode(String? raw) {
    final result = Journey();
    if (raw == null) return result;
    try {
      final data = jsonDecode(raw) as Map;
      int count(String key) => math.max(0, (data[key] as num? ?? 0).toInt());
      result.rounds = count('rounds');
      result.catches = count('catches');
      result.powers = count('powers');
      result.bestActive = count('active');
      result.heroes.addAll(
        (data['heroes'] as List? ?? [])
            .whereType<int>()
            .where(
              (i) => data['heroRosterVersion'] == 2
                  ? i >= 0 && i < roster.heroes.length
                  : roster.heroLegacySlots.contains(i),
            )
            .map(
              (i) =>
                  data['heroRosterVersion'] == 2 ? i : roster.heroFromLegacy(i),
            ),
      );
      result.claimed.addAll(
        (data['claimed'] as List? ?? []).whereType<String>().take(32),
      );
    } on Object {
      return Journey();
    }
    return result;
  }

  String encode() => jsonEncode({
    'heroRosterVersion': 2,
    'rounds': rounds,
    'catches': catches,
    'powers': powers,
    'active': bestActive,
    'heroes': heroes.toList(),
    'claimed': claimed,
  });

  int count(JourneyBadge badge) => switch (badge.id) {
    'first' || 'rounds' => rounds,
    'catch' => catches,
    'power' => powers,
    'active' => bestActive,
    'heroes' => heroes.length,
    _ => 0,
  };
  bool earned(JourneyBadge badge) => count(badge) >= badge.target;
  int get earnedCount => journeyBadges.where(earned).length;

  List<JourneyBadge> complete(String roundId, Map state) {
    if (claimed.contains(roundId) || !ChampionRules.eligible(state)) {
      return [];
    }
    final me = state['myScore'] as Map;
    final active = (me['activeSeconds'] as num? ?? 0).toDouble();
    if (active < 15) return [];
    final before = journeyBadges.where(earned).map((b) => b.id).toSet();
    rounds++;
    catches += math.max(0, (me['catches'] as num? ?? 0).toInt());
    powers += math.max(0, (state['self']['powerSerial'] as num? ?? 0).toInt());
    bestActive = math.max(bestActive, (active + .00001).floor());
    final hero = state['self']['skin'] as int? ?? 0;
    if (hero >= 0 && hero < roster.heroes.length) heroes.add(hero);
    claimed.add(roundId);
    if (claimed.length > 32) claimed.removeAt(0);
    return journeyBadges
        .where((b) => earned(b) && !before.contains(b.id))
        .toList();
  }
}
