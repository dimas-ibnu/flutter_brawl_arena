import 'dart:io';

import 'package:brawl_arena/ai/bot.dart';
import 'package:brawl_arena/replay/replay.dart';
import 'package:brawl_arena/sim/input_frame.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fighters.dart';

/// Records a full bot-vs-bot match.
Replay _recordMatch() {
  final replay = Replay(
    seed: 42,
    fighterIds: ['knight', 'ranger'],
    stage: 'flatArena',
  );
  final sim = Replay.simulationFor(replay, testFighters);
  final state = sim.initialState(seed: replay.seed);
  final a = Bot(sim: sim, slot: 0, seed: 3);
  final b = Bot(sim: sim, slot: 1, seed: 4);
  while (!state.finished) {
    final inputs = [a.think(state), b.think(state)];
    replay.record(inputs);
    sim.step(state, inputs);
  }
  replay.finalChecksum = state.checksum();
  return replay;
}

void main() {
  test('replaying the recorded inputs rebuilds the same match', () {
    final replay = _recordMatch();
    final sim = Replay.simulationFor(replay, testFighters);
    expect(replay.ticks, isNotEmpty);
    expect(replay.verify(sim), isTrue);
    expect(replay.play(sim).finished, isTrue);
  });

  test('survives a round trip through a file', () {
    final replay = _recordMatch();
    final dir = Directory.systemTemp.createTempSync('replay_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/match.json')
      ..writeAsStringSync(replay.toJson());

    final loaded = Replay.fromJson(file.readAsStringSync());
    expect(loaded.fighterIds, replay.fighterIds);
    expect(loaded.ticks.length, replay.ticks.length);
    expect(loaded.verify(Replay.simulationFor(loaded, testFighters)), isTrue);
  });

  test('a changed input is caught by the checksum', () {
    final replay = _recordMatch();
    // Player 1 stops playing for two seconds.
    for (var i = 100; i < 220; i++) {
      replay.ticks[i] = [InputFrame.none.bits, replay.ticks[i][1]];
    }
    expect(replay.verify(Replay.simulationFor(replay, testFighters)), isFalse);
  });

  test('unknown versions are rejected', () {
    expect(
      () => Replay.fromJson(
        '{"version": 99, "seed": 1, "stage": "x", "fighters": [], "ticks": []}',
      ),
      throwsFormatException,
    );
  });
}
