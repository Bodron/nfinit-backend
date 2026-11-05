/// Public, fixed world objects. Interaction never accepts client coordinates.
class DistractionSite {
  const DistractionSite(
    this.id,
    this.title,
    this.label,
    this.kind,
    this.wallIndex,
    this.x,
    this.y,
  );
  final String id, title, label, kind;
  final int wallIndex;
  // Legal approach point at the object's base, outside its solid footprint.
  final double x, y;
  static const cooldown = 12.0, pulseSeconds = 2.5, reach = .78;
  Map<String, dynamic> toJson({required double remaining, double? pulse}) => {
    'id': id,
    'title': title,
    'label': label,
    'kind': kind,
    'wallIndex': wallIndex,
    'x': x,
    'y': y,
    'cooldown': remaining,
    'pulse': pulse,
  };
}
