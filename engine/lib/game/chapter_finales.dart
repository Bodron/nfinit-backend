import 'dart:math' as math;

enum FinaleKind { patrol, echoes, bell, siege }

enum FinalePhase { quiet, warning, active }

class ChapterFinale {
  const ChapterFinale(this.kind, this.title, this.description, this.tactic);
  final FinaleKind kind;
  final String title, description, tactic;
  String get intro => switch (kind) {
    FinaleKind.patrol =>
      'The guard changes lanes. Watch the marker and take the clear side.',
    FinaleKind.echoes =>
      'Old echoes return. Change your hiding place after making noise.',
    FinaleKind.bell =>
      'The bell draws them to the center. Go around or use a decoy.',
    FinaleKind.siege => 'Seekers gather at the fountain when signaled. Keep an escape route open.',
  };
  static const firstWarning = 6.0,
      warningSeconds = 2.0,
      activeSeconds = 3.0,
      cycle = 10.0;
  FinaleState at(double elapsed) {
    final t = math.max(0, elapsed - firstWarning) % cycle;
    final phase = elapsed < firstWarning
        ? FinalePhase.quiet
        : t < warningSeconds
        ? FinalePhase.warning
        : t < warningSeconds + activeSeconds
        ? FinalePhase.active
        : FinalePhase.quiet;
    final event = elapsed < firstWarning + warningSeconds
        ? 0
        : ((elapsed - firstWarning - warningSeconds) / cycle).floor() + 1;
    final remaining = phase == FinalePhase.warning
        ? warningSeconds - t
        : phase == FinalePhase.active
        ? warningSeconds + activeSeconds - t
        : 0.0;
    return FinaleState(this, phase, event, remaining);
  }
}

class FinaleState {
  const FinaleState(this.rule, this.phase, this.event, this.remaining);
  final ChapterFinale rule;
  final FinalePhase phase;
  final int event;
  final double remaining;
  static const patrolPosts = [(.4, .395), (.61, .60)];
  (double, double)? get goal => switch (rule.kind) {
    FinaleKind.patrol => patrolPosts[event % 2],
    FinaleKind.bell => (.4, .395),
    FinaleKind.siege => (.5325, .59),
    FinaleKind.echoes => null,
  };
  (double, double)? get marker =>
      rule.kind == FinaleKind.patrol && phase == FinalePhase.warning
      ? patrolPosts[(event + 1) % 2]
      : goal;
  String? get hint {
    if (phase == FinalePhase.warning) {
      final seconds = remaining.ceil();
      return switch (rule.kind) {
        FinaleKind.patrol => 'NEW PATROL IN ${seconds}s · CHANGE LANES',
        FinaleKind.echoes => 'ECHO IN ${seconds}s · CHANGE COVER',
        FinaleKind.bell => 'BELL IN ${seconds}s · AVOID THE CENTER',
        FinaleKind.siege => 'SIEGE IN ${seconds}s · FIND A CLEAR PATH',
      };
    }
    if (phase != FinalePhase.active) return null;
    return switch (rule.kind) {
      FinaleKind.patrol => 'THE GUARD IS CHANGING PATROL',
      FinaleKind.echoes => 'ECHOES RETURN · LEAVE YOUR OLD ROUTE',
      FinaleKind.bell => 'THE BELL RINGS · SEEKERS APPROACH THE CENTER',
      FinaleKind.siege => 'SIEGE · SEEKERS APPROACH THE FOUNTAIN',
    };
  }

  Map<String, dynamic> toJson() => {
    'kind': rule.kind.name,
    'title': rule.title,
    'intro': rule.intro,
    'phase': phase.name,
    'event': event,
    'remaining': remaining,
    'hint': hint,
    if (marker case final point?) ...{'x': point.$1, 'y': point.$2},
  };
}

const chapterFinales = <int, ChapterFinale>{
  5: ChapterFinale(
    FinaleKind.patrol,
    'Guard Patrol',
    'Guards periodically change the lane they patrol. Their next post is marked two seconds ahead.',
    'Cross the side they leave. Nearby footsteps and decoys can distract them from patrol.',
  ),
  10: ChapterFinale(
    FinaleKind.echoes,
    'Delayed Echoes',
    'When signaled, seekers investigate sounds they heard at least three seconds earlier. The echo does not reveal your current position.',
    'Change cover after making noise. A fresh decoy still takes priority.',
  ),
  15: ChapterFinale(
    FinaleKind.bell,
    'Manor Bell',
    'After the warning, the bell draws seekers to the center for three seconds. Charges already in progress keep their direction.',
    'Avoid the center while the bell rings. Decoys can distract seekers; those already close to you keep chasing.',
  ),
  20: ChapterFinale(
    FinaleKind.siege,
    'Courtyard Siege',
    'When signaled, seekers gather at the fountain. The two-second warning gives you time to find another route.',
    'Go around the fountain, dodge charges into walls and use decoys to split the group.',
  ),
};
