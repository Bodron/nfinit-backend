/// The manor is one authored place: its paved terraces, planting and collision
/// footprints share these coordinates. Ground decoration never invents walls.
class ManorLayout {
  static const title = 'Manor Courtyard';
  static const walls = <List<double>>[
    [.22, .2375, .055, .105], // west reading terrace
    [.725, .2375, .055, .105], // east reading terrace
    [.44, .43, .13, .13], // fountain at the crossing of the two main axes
    [.22, .69, .055, .105], // southwest terrace: keep the arrival avenue clear
    [.725, .69, .055, .105], // southeast terrace
    [
      .32,
      .235,
      .065,
      .105,
    ], // paired lavender planters inside the north gardens
    [.615, .235, .065, .105],
    [.32, .66, .065, .105], // paired lavender planters inside the south gardens
    [.615, .66, .065, .105],
    [.185, .17, .20, .04], // clipped hedges frame the garden, not the crossings
    [.615, .17, .20, .04],
    [.185, .80, .20, .04],
    [.615, .80, .20, .04],
    [.215, .35, .06, .025], // tree trunks; crowns overhang the shady terraces
    [.78, .35, .035, .025],
    [.185, .655, .035, .025],
    [.78, .655, .035, .025],
    [.32, .895, .065, .035], // pots mark the two ends of the arrival avenue
    [.615, .895, .065, .035],
    [.42, .085, .045, .03],
    [.545, .085, .045, .03],
    [.165, .23, .026, .026], // urns welcome players to each shaded terrace
    [.815, .23, .026, .026],
    [.165, .72, .026, .026],
    [.815, .72, .026, .026],
    [.81, .41, .028, .028], // sundial in the sunny east viewing alcove
    [.267, .415, .026, .022], // lanterns frame the four plaza approaches
    [.707, .415, .026, .022],
    [.267, .565, .026, .022],
    [.707, .565, .026, .022],
    [
      .075,
      .575,
      .025,
      .028,
    ], // west rose arbour, two solid piers and open passage
    [.18, .575, .025, .028],
  ];
  static const props = [
    1,
    1,
    0,
    1,
    1,
    2,
    2,
    2,
    2,
    3,
    3,
    3,
    3,
    5,
    16,
    17,
    18,
    2,
    2,
    2,
    2,
    12,
    12,
    12,
    12,
    13,
    14,
    14,
    14,
    14,
    15,
    15,
  ];
  static const arbourSupports = [30, 31];
  static const arbourBase = [.075, .555, .13, .048];
  static const urns = [21, 22, 23, 24];
  static const sundial = 25;
  static const lanterns = [26, 27, 28, 29];
  static const benches = [0, 1, 3, 4];
  static const planters = [5, 6, 7, 8, 17, 18, 19, 20];
  static const trees = [13, 14, 15, 16];
  static const gardens = <List<double>>[
    [.18, .17, .23, .235],
    [.59, .17, .23, .235],
    [.18, .595, .23, .245],
    [.59, .595, .23, .245],
  ];
  // Every loop has two exits. Narrow, legible alternatives to the central plaza.
  static const shortcuts = <List<List<double>>>[
    [
      [.295, .26],
      [.295, .365],
      [.37, .42],
    ],
    [
      [.705, .26],
      [.705, .365],
      [.64, .42],
    ],
    [
      [.295, .75],
      [.295, .635],
      [.37, .58],
    ],
    [
      [.705, .75],
      [.705, .635],
      [.64, .58],
    ],
  ];
}
