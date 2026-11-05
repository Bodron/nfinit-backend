/// Two full-size rooms share continuous world coordinates: no loading or warp.
/// Every machine belongs to a work bay; marked aisles stay clear for combat.
abstract final class TechLayout {
  static const id = 'tech';
  static const title = 'Clockwork Foundry';
  static const widthUnits = 2.0;
  static const spawn = [.50, .15];
  static const doorways = <List<double>>[
    [.975, .22, .05, .14],
    [.975, .64, .05, .14],
  ];
  // Matching indices in the atlas (reactor, dock, arm, server, cargo,
  // coolant, console, wall) deliberately preserve existing collision rules.
  static const spriteKinds = {
    0: 0,
    1: 1,
    6: 2,
    7: 3,
    8: 4,
    10: 5,
    11: 6,
    15: 7,
  };
  static const walls = <List<double>>[
    [.975, .04, .05, .18], // divider: two wide, permanently open passages
    [.975, .36, .05, .28],
    [.975, .78, .05, .18],
    [.23, .34, .17, .085], // left: paired assembly work bays
    [.63, .34, .15, .085],
    [.23, .69, .07, .065], // charging docks behind the assembly stations
    [.69, .69, .07, .065],
    [.34, .70, .07, .045], // parts storage beside each dock
    [.59, .70, .07, .045],
    [1.435, .43, .15, .14], // right: central reactor, circuit around it
    [1.23, .26, .15, .065], // paired server and cooling bays
    [1.67, .26, .10, .075],
    [1.23, .71, .15, .065],
    [1.67, .71, .10, .075],
    [1.47, .19, .08, .05], // reactor monitoring console on its own plinth
  ];
  static const props = [15, 15, 15, 6, 6, 1, 1, 8, 8, 0, 7, 10, 7, 10, 11];
  static const bays = <List<double>>[
    [.20, .29, .23, .18],
    [.60, .29, .21, .18],
    [.20, .65, .24, .15],
    [.56, .65, .23, .15],
    [1.40, .39, .22, .22],
    [1.20, .22, .21, .14],
    [1.64, .22, .16, .14],
    [1.20, .67, .21, .15],
    [1.64, .67, .16, .15],
    [1.44, .16, .14, .10],
  ];
  static const laneHalfWidth = .023;
  static const routes = <List<List<double>>>[
    [
      [.14, .15],
      [.86, .15],
      [.86, .86],
      [.14, .86],
      [.14, .15],
    ],
    [
      [.50, .15],
      [.50, .86],
    ],
    [
      [.14, .54],
      [.86, .54],
    ],
    [
      [.86, .29],
      [1.13, .29],
      [1.13, .50],
    ],
    [
      [.86, .71],
      [1.13, .71],
      [1.13, .50],
    ],
    [
      [1.13, .14],
      [1.86, .14],
      [1.86, .86],
      [1.13, .86],
      [1.13, .14],
    ],
    [
      [1.13, .50],
      [1.32, .50],
      [1.32, .62],
      [1.72, .62],
      [1.72, .50],
      [1.86, .50],
    ],
    [
      [1.32, .50],
      [1.32, .38],
      [1.72, .38],
      [1.72, .50],
    ],
  ];
}
