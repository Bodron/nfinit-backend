enum SoloTool { decoy, stone, quietStep }

extension SoloToolInfo on SoloTool {
  String get title => switch (this) {
    SoloTool.decoy => 'Decoy',
    SoloTool.stone => 'Stone',
    SoloTool.quietStep => 'Quiet Step',
  };
  String get button => switch (this) {
    SoloTool.decoy => 'DECOY',
    SoloTool.stone => 'STONE',
    SoloTool.quietStep => 'QUIET STEP',
  };
  int get unlockLevel => switch (this) {
    SoloTool.decoy => 0,
    SoloTool.stone => 5,
    SoloTool.quietStep => 10,
  };
  double get cooldown => switch (this) {
    SoloTool.decoy => 8,
    SoloTool.stone => 12,
    SoloTool.quietStep => 14,
  };
  String get description => switch (this) {
    SoloTool.decoy => 'Sends false clues near seekers. No aiming needed.',
    SoloTool.stone => 'Throw in your current or last movement direction. The marker shows where the stone will land.',
    SoloTool.quietStep =>
      'For 4s, footsteps and gravel produce no passive sound clues.',
  };
  String get tradeoff => switch (this) {
    SoloTool.decoy =>
      '8s cooldown. The false clue chooses its own destination.',
    SoloTool.stone =>
      '12s cooldown. Choose a clear spot, then change direction to escape.',
    SoloTool.quietStep => '14s cooldown. You remain visible in open spaces; voice and Listen can still reveal you.',
  };
}

SoloTool parseSoloTool(dynamic name) => SoloTool.values.firstWhere(
  (t) => t.name == name,
  orElse: () => SoloTool.decoy,
);
