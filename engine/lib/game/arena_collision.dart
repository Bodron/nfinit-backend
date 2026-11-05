part of 'engine.dart';

/// Static broad phase: only nearby footprints need an exact rounded SDF check.
/// A map change replaces the index. Physics keeps its existing exact boundary.
class _CollisionGrid {
  _CollisionGrid(ArenaMap map)
    : columns = (map.widthUnits * resolution).ceil() {
    cells = List.generate(columns * resolution, (_) => <int>[]);
    for (var i = 0; i < map.walls.length; i++) {
      final rect = map.walls[i];
      final left = ((rect[0] - playerRadius) * resolution).floor().clamp(
        0,
        columns - 1,
      );
      final right = ((rect[0] + rect[2] + playerRadius) * resolution)
          .floor()
          .clamp(0, columns - 1);
      final top = ((rect[1] - playerRadius) * resolution).floor().clamp(
        0,
        resolution - 1,
      );
      final bottom = ((rect[1] + rect[3] + playerRadius) * resolution)
          .floor()
          .clamp(0, resolution - 1);
      for (var y = top; y <= bottom; y++) {
        for (var x = left; x <= right; x++) {
          cells[y * columns + x].add(i);
        }
      }
    }
  }
  static const resolution = 32;
  final int columns;
  late final List<List<int>> cells;

  bool valid(double x, double y, ArenaMap map) {
    final cell = (y * resolution).floor() * columns + (x * resolution).floor();
    for (final i in cells[cell]) {
      if (obstacleDistance(
            x,
            y,
            map.walls[i],
            rounded: roundedProp(map.props[i]),
          ) <
          playerRadius) {
        return false;
      }
    }
    return true;
  }
}
