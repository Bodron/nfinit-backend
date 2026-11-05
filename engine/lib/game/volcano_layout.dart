import 'hazards.dart';

/// Authored sanctuary plan. Four landmarks and two connecting rooms have
/// distinct scenery; two escape loops keep their combat lanes open.
abstract final class VolcanoLayout {
  static const id = 'volcano';
  static const title = 'Crimson Caldera';
  static const unlockWave = 100;
  static bool unlocked(int bestWave) => bestWave >= unlockWave;

  // Landmarks sit on their own foundations. The two middle rooms fill pockets
  // between the roads without narrowing any combat lane.
  static const terraces = <List<double>>[
    [.18, .23, .20, .17], // memorial: skull, column, offering flame
    [.64, .23, .20, .17], // forge: furnace, ore, slag cart
    [.18, .70, .20, .15], // ossuary: fallen dragon, dead tree, vigil flame
    [.64, .70, .20, .15], // spring: basin and its two mineral outcrops
  ];
  static const walls = <List<double>>[
    [.45, .465, .12, .105], // single central landmark
    [.22, .285, .115, .065], // memorial faces the bell court
    [.19, .235, .026, .032],
    [.335, .35, .022, .025],
    [.668, .275, .105, .065], // forge: furnace, ore, delivery cart
    [.79, .25, .035, .045],
    [.765, .355, .055, .030],
    [.225, .765, .115, .055], // ossuary: remains, dead tree, vigil flame
    [.185, .715, .035, .040],
    [.345, .805, .020, .025],
    [.66, .775, .110, .055], // spring: basin below its regulator
    [.665, .705, .032, .040],
    [.805, .705, .030, .025], // crystals cluster behind the basin, not its exit
    [.39, .095, .030, .030], // entrance sentinels, clear of the main axis
    [.58, .095, .030, .030],
    [.335, .245, .026, .035], // memorial's charred witness tree
    [.805, .230, .025, .020], // slag stacked behind the ore
    [.338, .710, .035, .030], // ossuary's basalt fragments
    [.80, .735, .030, .025], // spring's weathered cooling stone
    [.215, .525, .070, .045], // bell: focal point of the western court
    [.310, .555, .046, .030], // relay beside the bell, with a clear approach
    [.665, .490, .055, .035], // manifold: upper left of the service yard
    [.780, .495, .052, .035], // turbine: upper right of the same yard
    [.705, .560, .090, .030], // exchanger: across the yard's southern edge
    [.728, .724, .063, .040], // regulator: visible behind the spring basin
    [.205, .095, .185, .025], // western gate wall joins its sentinel
    [.610, .095, .195, .025], // eastern gate wall joins its sentinel
    [.185, .486, .140, .022], // broken screen behind the bell
    [.680, .213, .120, .018], // furnace retaining wall
    [.205, .840, .130, .015], // ossuary's southern shelter
    [.730, .842, .100, .014], // basin retaining wall, open on the west
  ];
  // These IDs preserve the normal collision and cover rules.
  static const props = [
    0,
    6,
    7,
    12,
    8,
    2,
    17,
    15,
    11,
    12,
    13,
    2,
    2,
    4,
    4,
    11,
    5,
    5,
    5,
    21,
    22,
    20,
    25,
    24,
    23,
    1,
    1,
    1,
    1,
    1,
    1,
  ];

  static const ramparts = [25, 26, 27, 28, 29, 30];

  // Named anchors keep the painted infrastructure attached to actual props.
  static const bell = 19, relay = 20, manifold = 21, turbine = 22;
  static const exchanger = 23, regulator = 24;

  // A single service circuit: furnace -> manifold -> exchanger -> spring.
  // The turbine feeds the exchanger; the caldera feeds the manifold.
  static const serviceLinks = <(int, int, List<(double, double)>)>[
    (4, manifold, [(.7205, .385), (.6925, .385)]),
    (0, manifold, [(.595, .5175), (.595, .5075)]),
    (manifold, exchanger, [(.6925, .575)]),
    (turbine, exchanger, [(.806, .575)]),
    (exchanger, regulator, [(.75, .675), (.7595, .675)]),
    (regulator, 10, [(.7595, .8025)]),
    (bell, relay, [(.25, .578)]),
  ];

  // Three staggered, walkable steam mouths tie the forge, ossuary and central
  // approach into the same living volcanic system. Only one warns at a time.
  static const steamVents = <SteamVent>[
    SteamVent('forge-flue', .715, .420, .070, .026),
    SteamVent('ossuary-fissure', .225, .615, .070, .026),
    SteamVent('caldera-exhale', .465, .735, .070, .026),
  ];

  /// Guaranteed clear lane half-width, in normalized world coordinates.
  /// Tests sweep this width using the actual champion collision radius.
  static const laneHalfWidth = .025;

  /// Decorative cliffs live entirely beyond the playable boundary.
  static const rimScenery = <(double, double, double, double, int)>[
    (-.105, .18, .10, .08, 5),
    (-.12, .39, .11, .09, 5),
    (-.09, .69, .085, .065, 5),
    (-.12, .96, .105, .08, 5),
    (1.005, .25, .11, .075, 5),
    (1.01, .54, .10, .08, 5),
    (1.015, .84, .10, .08, 5),
    (.09, 1.08, .12, .065, 5),
    (.30, 1.105, .10, .07, 5),
    (.67, 1.095, .13, .07, 5),
    (.88, 1.08, .10, .07, 5),
  ];

  // Every side avenue meets the outer circuit instead of ending in the ash.
  // Ground paving and navigation checks use these exact same centerlines.
  static const routes = <List<List<double>>>[
    [
      [.12, .17],
      [.88, .17],
      [.88, .90],
      [.12, .90],
      [.12, .17],
    ],
    [
      [.41, .42],
      [.62, .42],
      [.62, .64],
      [.41, .64],
      [.41, .42],
    ],
    [
      [.5, .07],
      [.5, .42],
    ],
    [
      [.5, .64],
      [.5, .90],
    ],
    [
      [.12, .43],
      [.41, .43],
    ],
    [
      [.62, .43],
      [.88, .43],
    ],
    [
      [.12, .64],
      [.41, .64],
    ],
    [
      [.62, .64],
      [.88, .64],
    ],
    [
      [.41, .17],
      [.41, .90],
    ],
    [
      [.62, .17],
      [.62, .90],
    ],
  ];
}
