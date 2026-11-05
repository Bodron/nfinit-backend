import 'dart:collection';
import 'dart:math';

/// Shared navigation geometry. It contains walls and cover, never secret actors.
class NavigationGrid {
  NavigationGrid(this.valid, this.cover, {double widthUnits = 1})
    : columns = (n * widthUnits).round() {
    walk = List.generate(columns * n, (i) => valid(x(i), y(i)));
    covers = [
      for (var i = 0; i < columns * n; i++)
        if (walk[i] && cover(x(i), y(i)) && i % 3 == 0) i,
    ];
  }
  static const n = 64;
  final bool Function(double, double) valid, cover;
  final int columns;
  late final List<bool> walk;
  late final List<int> covers;
  final _routes = <(int, int), List<int>>{};
  int routeSearches = 0;
  double x(int c) => (c % columns + .5) / n;
  double y(int c) => (c ~/ columns + .5) / n;
  Iterable<int> neighbors(int c) sync* {
    final x = c % columns, y = c ~/ columns;
    if (x > 0 && walk[c - 1]) yield c - 1;
    if (x < columns - 1 && walk[c + 1]) yield c + 1;
    if (y > 0 && walk[c - columns]) yield c - columns;
    if (y < n - 1 && walk[c + columns]) yield c + columns;
  }

  int nearest(double px, double py) {
    final c =
        (py * n).floor().clamp(0, n - 1) * columns +
        (px * n).floor().clamp(0, columns - 1);
    if (walk[c]) return c;
    var result = c, best = double.infinity;
    for (var i = 0; i < walk.length; i++) {
      if (!walk[i]) continue;
      final d = pow(x(i) - px, 2) + pow(y(i) - py, 2);
      if (d < best) {
        best = d.toDouble();
        result = i;
      }
    }
    return result;
  }

  List<int> distances(double px, double py) => distancesFrom([(px, py)]);

  /// One traversal gives the closest path distance to any threat, even when
  /// many hunters share a cell. No hidden actor positions are stored here.
  List<int> distancesFrom(Iterable<(double, double)> sources) {
    final d = List<int>.filled(columns * n, -1), q = Queue<int>();
    for (final point in sources) {
      final source = nearest(point.$1, point.$2);
      if (d[source] == 0) continue;
      d[source] = 0;
      q.add(source);
    }
    while (q.isNotEmpty) {
      final c = q.removeFirst();
      for (final next in neighbors(c)) {
        if (d[next] < 0) {
          d[next] = d[c] + 1;
          q.add(next);
        }
      }
    }
    return d;
  }

  List<int> route(
    double px,
    double py,
    double tx,
    double ty, {
    double? threatX,
    double? threatY,
    double Function(double, double)? traversalPenalty,
  }) {
    final start = nearest(px, py), goal = nearest(tx, ty);
    final cacheable =
        threatX == null && threatY == null && traversalPenalty == null;
    final key = (start, goal);
    final cached = cacheable ? _routes[key] : null;
    if (cached != null) return cached;
    final parent = List<int>.filled(columns * n, -1),
        cost = List<double>.filled(columns * n, double.infinity),
        open = _Heap();
    double heuristic(int c) =>
        ((c % columns - goal % columns).abs() +
                (c ~/ columns - goal ~/ columns).abs())
            .toDouble();
    routeSearches++;
    List<int> finish(List<int> result) {
      if (!cacheable) return result;
      if (_routes.length >= 256) _routes.remove(_routes.keys.first);
      return _routes[key] = List<int>.unmodifiable(result);
    }

    cost[start] = 0;
    open.add(start, heuristic(start));
    while (open.isNotEmpty) {
      final entry = open.take();
      final c = entry.$1;
      if (entry.$2 > cost[c] + heuristic(c) + .0001) continue;
      if (c == goal) break;
      for (final next in neighbors(c)) {
        var step = 1.0 + (traversalPenalty?.call(x(next), y(next)) ?? 0);
        if (threatX != null && threatY != null) {
          final distance = sqrt(
            pow(x(next) - threatX, 2) + pow(y(next) - threatY, 2),
          );
          step +=
              (cover(x(next), y(next)) ? 0 : .6) + max(0, .27 - distance) * 25;
        }
        final nextCost = cost[c] + step;
        if (nextCost < cost[next]) {
          cost[next] = nextCost;
          parent[next] = c;
          open.add(next, nextCost + heuristic(next));
        }
      }
    }
    if (goal != start && parent[goal] < 0) return finish([]);
    final path = <int>[goal];
    while (path.last != start) {
      path.add(parent[path.last]);
    }
    return finish(path.reversed.toList());
  }
}

class _Heap {
  final _items = <(int, double)>[];
  bool get isNotEmpty => _items.isNotEmpty;
  void add(int c, double priority) {
    _items.add((c, priority));
    var i = _items.length - 1;
    while (i > 0) {
      final parent = (i - 1) ~/ 2;
      if (_items[parent].$2 <= priority) break;
      _items[i] = _items[parent];
      i = parent;
    }
    _items[i] = (c, priority);
  }

  (int, double) take() {
    final first = _items.first, last = _items.removeLast();
    if (_items.isEmpty) return first;
    var i = 0;
    while (i * 2 + 1 < _items.length) {
      var child = i * 2 + 1;
      if (child + 1 < _items.length &&
          _items[child + 1].$2 < _items[child].$2) {
        child++;
      }
      if (_items[child].$2 >= last.$2) break;
      _items[i] = _items[child];
      i = child;
    }
    _items[i] = last;
    return first;
  }
}
