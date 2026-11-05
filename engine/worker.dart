import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'lib/game/engine.dart';
import 'lib/game/champion_progress.dart';
import 'lib/game/journey.dart';

import 'dart:math' as math;

void emit(Map<String, dynamic> event) => stdout.writeln(jsonEncode(event));

class Match {
  Match(this.room);
  Room room;
  String? runId;
  bool reported = false;
  int progressSequence = 0, savedCompleted = -1;
  bool finalProgressSent = false;

  int idleTicks = 0;
  void tick({bool force = false}) {
    if (!force && (!room.running || room.paused) && ++idleTicks % 20 != 0) {
      return;
    }
    room.tick();
    if (room.cooperative &&
        runId != null &&
        (room.completedWaves > savedCompleted ||
            (room.ended && !finalProgressSent))) {
      savedCompleted = room.completedWaves;
      finalProgressSent = room.ended;
      emit({
        'event': 'progress',
        'code': room.code,
        'id': runId,
        'sequence': ++progressSequence,
        'states': [
          for (final p in room.players.where((p) => !p.isBot))
            {
              'id': p.id,
              'state': {
                'mode': 'survival',
                'demo': true,
                'completedWaves': room.completedWaves,
                'startWave': room.initialWave,
                'combatXp': p.combatXp,
                'damageUpgrades': p.damageUpgrades,
                'hasteUpgrades': p.hasteUpgrades,
                'volleyUpgrades': p.volleyUpgrades,
                'weaponXpEarned': p.weaponXpEarned.toJson(),
                'lootEssenceEarned': p.lootEssenceEarned.toJson(),
                'self': {'skin': p.skin},
              },
            },
        ],
      });
    }
    if (room.ended && runId != null && !reported) {
      reported = true;
      emit({
        'event': 'result',
        'code': room.code,
        'result': {
          'id': runId,
          'mode': room.pvp ? 'pvp' : 'coop',
          if (room.pvp) 'winnerId': room.winner,
          'roomCode': room.code,
          'outcome': room.winner ?? 'abandoned',
          'wave': room.wave,
          'completedWaves': room.completedWaves,
          'startWave': room.initialWave,
          'elapsed': room.elapsed,
          'players': [
            for (final p in room.players.where((p) => !p.isBot))
              {
                'id': p.id,
                'name': p.name,
                'skin': p.skin,
                'kills': p.kills,
                'weaponXp': p.weaponXpEarned.toString(),
                'essence': p.lootEssenceEarned.toString(),
              },
          ],
        },
      });
    }
  }
}

Future<void> main() async {
  final matches = <String, Match>{};
  final samples = <int>[];
  final watch = Stopwatch()..start();
  var lastCallback = 0, callbackMax = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
    final start = watch.elapsedMicroseconds;
    if (lastCallback > 0) {
      callbackMax = math.max(callbackMax, start - lastCallback);
    }
    lastCallback = start;
    for (final match in matches.values.toList()) {
      try {
        match.tick();
      } catch (_) {
        emit({'event': 'engineError', 'code': match.room.code});
        matches.remove(match.room.code);
      }
    }
    samples.add(watch.elapsedMicroseconds - start);
    if (samples.length >= 200) {
      samples.sort();
      emit({
        'event': 'metrics',
        'tickMeanMs': samples.reduce((a, b) => a + b) / samples.length / 1000,
        'tickP95Ms': samples[(samples.length * .95).floor()] / 1000,
        'tickMaxMs': samples.last / 1000,
        'callbackMaxMs': callbackMax / 1000,
        'roomCount': matches.length,
      });
      samples.clear();
      callbackMax = 0;
    }
  });
  emit({'event': 'ready', 'protocol': 2});
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    Map<String, dynamic>? command;
    try {
      command = (jsonDecode(line) as Map).cast<String, dynamic>();
      final op = command['op'];
      if (op == 'rewardProgress') {
        final progress = ChampionProgress.decode(
          command['champions'] as String?,
        );
        final state = command['state'] as Map,
            runId = command['runId'] as String;
        progress.completeSurvival(runId, state);
        progress.rewardCombatLoot(runId, state);
        final completed = state['completedWaves'] as int? ?? 0;
        if (completed > 0)
          progress.bestWave = math.max(
            progress.bestWave,
            (state['startWave'] as int? ?? 1) + completed - 1,
          );
        emit({
          'rid': command['rid'],
          'ok': true,
          'champions': progress.encode(),
          'journey': Journey().encode(),
        });
        continue;
      }
      final code = command['code'] as String;
      final playerId = command['playerId'] as String?;
      var match = matches[code];
      if (op == 'join') {
        match ??= matches[code] = Match(
          Room(
            code,
            false,
            mode: command['mode'] == 'pvp' ? MatchMode.pvp : MatchMode.survival,
            cooperative: command['mode'] != 'pvp',
            duration: command['mode'] == 'pvp' ? 120 : 90,
          ),
        );
        if (match.room.running ||
            match.room.players.length >= 2 ||
            match.room.players.any((p) => p.id == playerId))
          throw StateError('room_unavailable');
        final player = Player(
          playerId!,
          false,
          false,
          .5,
          .15,
          name: command['name'] as String,
          skin: command['skin'] as int,
          onMessage: (message) => emit({
            'event': 'message',
            'code': code,
            'to': playerId,
            'message': message,
          }),
        );
        match.room.players.add(player);
        match.tick(force: true);
      } else {
        if (match == null) throw StateError('room_not_found');
        final room = match.room;
        final player = room.players
            .where((p) => p.id == playerId && !p.isBot)
            .firstOrNull;
        switch (op) {
          case 'start':
            if (room.players.first.id != playerId ||
                room.players.where((p) => !p.isBot).length != 2 ||
                room.running) {
              throw StateError('cannot_start');
            }
            match.runId = command['runId'] as String;
            match.reported = false;
            match.progressSequence = 0;
            match.savedCompleted = 0;
            match.finalProgressSent = false;
            if (room.pvp) {
              room.paused = false;
              room.start();
              match.tick(force: true);
              break;
            }
            final saved = command['progress'] as Map? ?? {};
            final champions = {
              for (final p in room.players.where((p) => !p.isBot))
                p.id: ChampionProgress.decode(saved[p.id] as String?),
            };
            final shared = room.players
                .where((p) => !p.isBot)
                .map((p) => champions[p.id]!.hero(p.skin).checkpoint?.wave ?? 0)
                .reduce(math.min);
            final prepared = Room(
              code,
              false,
              mode: MatchMode.survival,
              cooperative: true,
              startWave: shared + 1,
            )..round = room.round;
            for (final old in room.players.where((p) => !p.isBot)) {
              final progress = champions[old.id]!,
                  hero = progress.hero(old.skin);
              final checkpoint = hero.checkpoint;
              prepared.players.add(
                Player(
                  old.id,
                  false,
                  false,
                  .5,
                  .15,
                  name: old.name,
                  skin: old.skin,
                  onMessage: old.onMessage,
                  upgrades: hero.loadout,
                  tool: progress.selectedTool,
                  checkpoint: checkpoint == null
                      ? null
                      : DungeonCheckpoint(
                          shared,
                          xp: checkpoint.xp,
                          damage: checkpoint.damage,
                          haste: checkpoint.haste,
                          volley: checkpoint.volley,
                        ),
                ),
              );
            }
            match.room = prepared;
            prepared.start();
            match.tick(force: true);
          case 'input':
            if (player == null) throw StateError('not_joined');
            if (room.paused || room.ended || player.health <= 0) break;
            final input = command['input'] as Map;
            switch (input['type']) {
              case 'move':
                player.setMovement(
                  (input['dx'] as num).toDouble(),
                  (input['dy'] as num).toDouble(),
                );
              case 'voice':
                player.voiceRun = input['running'] == true;
              case 'action':
                room.action(
                  player,
                  input['action'] as String,
                  targetX: (input['targetX'] as num?)?.toDouble(),
                  targetY: (input['targetY'] as num?)?.toDouble(),
                );
            }
          case 'pause':
            room.paused = command['paused'] == true;
            for (final p in room.players.where((p) => !p.isBot)) {
              p.setMovement(0, 0);
              p.voiceRun = false;
            }
            match.tick(force: true);
          case 'snapshot':
            match.tick(force: true);
          case 'finish':
            if (room.running) {
              final forfeitId = command['forfeitId'];
              room.winner = room.pvp && forfeitId is String
                  ? room.players
                            .where((p) => p.id != forfeitId)
                            .firstOrNull
                            ?.id ??
                        'abandoned'
                  : 'abandoned';
              room.endRound(
                command['reason'] as String? ?? 'Co-op session ended.',
              );
            }
            match.tick(force: true);
          case 'destroy':
            matches.remove(code);
          default:
            throw StateError('invalid_command');
        }
      }
      emit({'rid': command['rid'], 'ok': true});
    } catch (_) {
      emit({
        'rid': command?['rid'],
        'ok': false,
        'error': 'engine_command_failed',
      });
    }
  }
  timer.cancel();
}
