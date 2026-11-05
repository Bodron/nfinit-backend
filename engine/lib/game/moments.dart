/// Only the authoritative room decides whether a highlight was earned.
enum MomentKind {
  escape('CLOSE CALL'),
  shield('PERFECT SHIELD'),
  trick('TRICKED');

  const MomentKind(this.label);
  final String label;
}

class MatchMoment {
  const MatchMoment(this.serial, this.kind, this.time);
  final int serial;
  final MomentKind kind;
  final double time;

  Map<String, dynamic> toJson() => {
    'serial': serial,
    'kind': kind.name,
    'time': time,
  };

  static MatchMoment? parse(dynamic value) {
    if (value is! Map) return null;
    final kind = MomentKind.values.where((k) => k.name == value['kind']);
    if (kind.isEmpty || value['serial'] is! int || value['time'] is! num) {
      return null;
    }
    return MatchMoment(
      value['serial'],
      kind.first,
      (value['time'] as num).toDouble(),
    );
  }
}

class MomentClip {
  MomentClip(this.moment, Iterable<Map<String, dynamic>> before)
    : frames = List.of(before);
  final MatchMoment moment;
  final List<Map<String, dynamic>> frames;
}

/// Keeps only snapshots this client was allowed to see. No omniscient replay.
class MomentRecorder {
  final _recent = <Map<String, dynamic>>[];
  final clips = <MomentClip>[];
  MatchMoment? latest;
  int _serial = 0;
  double _elapsed = -1;

  bool add(Map<String, dynamic> state) {
    final time = (state['elapsed'] as num? ?? 0).toDouble();
    if (time < _elapsed) clear();
    final advanced = time > _elapsed;
    _elapsed = time;
    if (advanced) {
      _recent.add(state);
      _recent.removeWhere((frame) => time - (frame['elapsed'] as num) > 2);
      for (final clip in clips) {
        if (time > clip.moment.time && time <= clip.moment.time + 1) {
          clip.frames.add(state);
        }
      }
    }
    final moment = MatchMoment.parse(state['moment']);
    if (moment == null || moment.serial <= _serial) return false;
    _serial = moment.serial;
    latest = moment;
    clips.add(MomentClip(moment, _recent));
    if (clips.length > 3) clips.removeAt(0);
    return true;
  }

  void clear() {
    _recent.clear();
    clips.clear();
    latest = null;
    _serial = 0;
    _elapsed = -1;
  }
}
