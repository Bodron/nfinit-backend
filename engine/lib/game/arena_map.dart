import 'distractions.dart';
import 'hazards.dart';

/// Visual props use the exact same footprint list as collision and cover.
/// Logical prop IDs select matching footprints; the renderer chooses depth-facing atlas variants.
class ArenaMap {
  const ArenaMap(
    this.id,
    this.title,
    this.subtitle,
    this.walls,
    this.props, {
    this.spawn = const [.5, .15],
    this.widthUnits = 1,
    this.steamVents = const [],
    this.distractions = const [],
    this.noisyGround = const [],
  });
  final String id, title, subtitle;

  /// Width in original arena units. Gameplay distances keep the same scale.
  final double widthUnits;
  final List<List<double>> walls;
  final List<int> props;
  final List<double> spawn;
  final List<SteamVent> steamVents;
  final List<DistractionSite> distractions;
  final List<List<double>> noisyGround;
  bool noisyAt(double x, double y) => noisyGround.any(
    (r) => x >= r[0] && x <= r[0] + r[2] && y >= r[1] && y <= r[1] + r[3],
  );
}
