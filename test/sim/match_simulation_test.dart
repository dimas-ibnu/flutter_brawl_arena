import 'package:brawl_arena/sim/defs.dart';
import 'package:brawl_arena/sim/fixed.dart';
import 'package:brawl_arena/sim/game_state.dart';
import 'package:brawl_arena/sim/input_frame.dart';
import 'package:brawl_arena/sim/match_simulation.dart';
import 'package:flutter_test/flutter_test.dart';

MatchSimulation _sim() => MatchSimulation(
  stage: StageDef.flatArena,
  fighterDefs: const [FighterDef.knight, FighterDef.ranger],
);

const _idle = [InputFrame.none, InputFrame.none];

void _run(
  MatchSimulation sim,
  GameState state,
  int ticks, [
  List<InputFrame> inputs = _idle,
]) {
  for (var i = 0; i < ticks; i++) {
    sim.step(state, inputs);
  }
}

/// Deterministic pseudo-random inputs so tests cover mixed play.
List<InputFrame> _scriptedInputs(int frame) {
  final a = (frame * 7919) % 5;
  final b = (frame * 104729) % 7;
  return [
    InputFrame.of([
      if (a == 1) Button.left,
      if (a >= 3) Button.right,
      if (a == 2) Button.jump,
    ]),
    InputFrame.of([
      if (b <= 2) Button.left,
      if (b == 5) Button.right,
      if (b == 6) Button.light,
    ]),
  ];
}

int _checksumAfter(int ticks, {required int seed}) {
  final sim = _sim();
  final state = sim.initialState(seed: seed);
  for (var i = 0; i < ticks; i++) {
    sim.step(state, _scriptedInputs(i));
    state.nextRandom(100); // exercise the RNG as gameplay will
  }
  return state.checksum();
}

void main() {
  group('movement', () {
    test('fighters fall and land on the ground', () {
      final sim = _sim();
      final state = sim.initialState(seed: 1);
      _run(sim, state, 120);
      for (final f in state.fighters) {
        expect(f.grounded, isTrue);
        expect(f.y, sim.stage.groundY);
        expect(f.vy, Fx.zero);
      }
    });

    test('holding right walks right and faces right', () {
      final sim = _sim();
      final state = sim.initialState(seed: 1);
      _run(sim, state, 120);
      final startX = state.fighters[1].x;
      _run(sim, state, 10, [
        InputFrame.none,
        InputFrame.of([Button.right]),
      ]);
      final ranger = state.fighters[1];
      expect(ranger.x, startX + FighterDef.ranger.walkSpeed.mulInt(10));
      expect(ranger.facing, 1);
    });

    test('jump leaves the ground and lands again', () {
      final sim = _sim();
      final state = sim.initialState(seed: 1);
      _run(sim, state, 120);
      sim.step(state, [
        InputFrame.of([Button.jump]),
        InputFrame.none,
      ]);
      final knight = state.fighters[0];
      expect(knight.grounded, isFalse);
      expect(knight.y < sim.stage.groundY, isTrue);
      _run(sim, state, 120);
      expect(knight.grounded, isTrue);
      expect(knight.airJumpsLeft, FighterDef.knight.airJumps);
    });

    test('up also jumps', () {
      final sim = _sim();
      final state = sim.initialState(seed: 1);
      _run(sim, state, 120);
      sim.step(state, [
        InputFrame.of([Button.up]),
        InputFrame.none,
      ]);
      expect(state.fighters[0].grounded, isFalse);
    });

    test(
      'holding jump does not jump again; each new press uses an air jump',
      () {
        final sim = _sim();
        final state = sim.initialState(seed: 1);
        _run(sim, state, 120);
        final knight = state.fighters[0];
        final jump = [
          InputFrame.of([Button.jump]),
          InputFrame.none,
        ];

        _run(sim, state, 5, jump); // held: only the ground jump
        expect(knight.airJumpsLeft, 2);

        for (var used = 1; used <= 3; used++) {
          sim.step(state, _idle);
          sim.step(state, jump);
          expect(knight.airJumpsLeft, used <= 2 ? 2 - used : 0);
        }
      },
    );

    test('holding down fast falls and lands sooner', () {
      int ticksToLand(List<InputFrame> fallInput) {
        final sim = _sim();
        final state = sim.initialState(seed: 1);
        _run(sim, state, 120);
        sim.step(state, [
          InputFrame.of([Button.jump]),
          InputFrame.none,
        ]);
        var ticks = 0;
        while (!state.fighters[0].grounded) {
          sim.step(state, fallInput);
          ticks++;
        }
        return ticks;
      }

      final normal = ticksToLand(_idle);
      final fast = ticksToLand([
        InputFrame.of([Button.down]),
        InputFrame.none,
      ]);
      expect(fast, lessThan(normal));
    });

    test('walking off the stage loses a stock and respawns', () {
      final sim = _sim();
      final state = sim.initialState(seed: 1);
      _run(sim, state, 600, [
        InputFrame.of([Button.left]),
        InputFrame.none,
      ]);
      final knight = state.fighters[0];
      expect(knight.stocks, lessThan(sim.startingStocks));
      expect(state.fighters[1].stocks, sim.startingStocks);
    });
  });

  group('state', () {
    test('frame counts ticks', () {
      final sim = _sim();
      final state = sim.initialState(seed: 1);
      _run(sim, state, 42);
      expect(state.frame, 42);
    });

    test('copy is independent of the original', () {
      final sim = _sim();
      final state = sim.initialState(seed: 1);
      final saved = state.copy();
      _run(sim, state, 30, [
        InputFrame.of([Button.right]),
        InputFrame.none,
      ]);
      expect(saved.frame, 0);
      expect(saved.fighters[0].x, sim.stage.spawnX[0]);
      expect(saved.checksum(), isNot(state.checksum()));
    });

    test('same seed gives the same random sequence', () {
      final a = GameState(fighters: [], seed: 42);
      final b = GameState(fighters: [], seed: 42);
      final c = GameState(fighters: [], seed: 43);
      final seqA = [for (var i = 0; i < 20; i++) a.nextRandom(1000)];
      final seqB = [for (var i = 0; i < 20; i++) b.nextRandom(1000)];
      final seqC = [for (var i = 0; i < 20; i++) c.nextRandom(1000)];
      expect(seqA, seqB);
      expect(seqA, isNot(seqC));
      expect(seqA.every((v) => v >= 0 && v < 1000), isTrue);
    });

    test('seed 0 still produces random values', () {
      final s = GameState(fighters: [], seed: 0);
      final values = {for (var i = 0; i < 10; i++) s.nextRandom(1000)};
      expect(values.length, greaterThan(1));
    });
  });

  group('determinism', () {
    test('same seed and inputs give the same checksum', () {
      expect(_checksumAfter(3600, seed: 7), _checksumAfter(3600, seed: 7));
    });

    test('a different seed gives a different checksum', () {
      expect(_checksumAfter(600, seed: 7), isNot(_checksumAfter(600, seed: 8)));
    });

    test('restoring a saved state and replaying matches (rollback)', () {
      final sim = _sim();
      final live = sim.initialState(seed: 3);
      GameState? snapshot;
      for (var i = 0; i < 600; i++) {
        if (i == 300) snapshot = live.copy();
        sim.step(live, _scriptedInputs(i));
      }

      final replay = snapshot!;
      for (var i = 300; i < 600; i++) {
        sim.step(replay, _scriptedInputs(i));
      }
      expect(replay.checksum(), live.checksum());
    });
  });
}
