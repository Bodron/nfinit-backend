import '../game/arena_map.dart';
import '../game/arena_ids.dart';
import '../game/campaign.dart';

class ContentMonster {
  const ContentMonster({
    required this.id,
    required this.name,
    required this.kind,
    required this.health,
    required this.speed,
    this.damage = 1,
    this.atlas,
  });
  final String id, name;
  final MonsterKind kind;
  final double health, speed, damage;
  final String? atlas;
}

/// Replaced only in the lobby. Rooms retain their immutable roster and map.
abstract final class RuntimeCatalog {
  static String? releaseId;
  static List<ArenaMap>? maps;
  static List<ContentMonster> monsters = const [];
  static void install(
    String id,
    List<ArenaMap> nextMaps,
    List<ContentMonster> nextMonsters,
  ) {
    maps = List.unmodifiable(
      nextMaps.where((map) => !retiredArenaIds.contains(map.id)),
    );
    monsters = List.unmodifiable(nextMonsters);
    releaseId = id;
  }
}
