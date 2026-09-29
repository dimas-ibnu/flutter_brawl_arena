import 'package:brawl_arena/sim/defs.dart';
import 'package:brawl_arena/sim/fixed.dart';
import 'package:brawl_arena/sim/game_state.dart';
import 'package:brawl_arena/sim/input_frame.dart';
import 'package:brawl_arena/sim/match_simulation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fighters.dart';

const _idle = [InputFrame.none, InputFrame.none];
final _jab = [
  InputFrame.of([Button.light]),
  InputFrame.none,
];

(MatchSimulation, GameState) _setup({int timeLimitTicks = 4 * 60 * 60}) {
  final sim = MatchSimulation(
    stage: StageDef.flatArena,
    fighterDefs: [knightDef, rangerDef],
    timeLimitTicks: timeLimitTicks,
  );
  final state = sim.initialState(seed: 1);
  _run(sim, state, 120);
  return (sim, state);
}

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

/// Drops [f] below the blast zone so it loses a stock on the next tick.
void _knockOut(FighterState f, MatchSimulation sim) {
  f
    ..y = sim.stage.blastBottom + Fx.fromInt(10)
    ..grounded = false;
}

/// Moves the Knight next to the Ranger, facing it, both on the ground.
void _faceOff(GameState state) {
  state.fighters[0]
    ..x = state.fighters[1].x - Fx.fromInt(60)
    ..y = Fx.zero
    ..facing = 1;
}

void main() {
  group('stocks', () {
    test('losing a stock respawns you with 2 s of invincibility', () {
      final (sim, state) = _setup();
      final ranger = state.fighters[1];
      _knockOut(ranger, sim);
      sim.step(state, _idle);
      expect(ranger.stocks, sim.startingStocks - 1);
      expect(ranger.invincible, sim.respawnInvincibleTicks);
      expect(ranger.damage, 0);
    });

    test('hits pass through a respawning fighter', () {
      final (sim, state) = _setup();
      final ranger = state.fighters[1];
      _knockOut(ranger, sim);
      sim.step(state, _idle);
      _run(sim, state, 60); // land on the stage, still invincible
      _faceOff(state);
      sim.step(state, _jab);
      _run(sim, state, 10);
      expect(ranger.invincible, greaterThan(0));
      expect(ranger.damage, 0);
    });

    test('once invincibility ends, hits land again', () {
      final (sim, state) = _setup();
      final ranger = state.fighters[1];
      _knockOut(ranger, sim);
      sim.step(state, _idle);
      _run(sim, state, sim.respawnInvincibleTicks);
      expect(ranger.invincible, 0);
      _faceOff(state);
      sim.step(state, _jab);
      _run(sim, state, 10);
      expect(ranger.damage, greaterThan(0));
    });
  });

  group('winning', () {
    test('losing the last stock ends the match; the other fighter wins', () {
      final (sim, state) = _setup();
      final ranger = state.fighters[1];
      for (var i = 0; i < sim.startingStocks; i++) {
        _knockOut(ranger, sim);
        sim.step(state, _idle);
      }
      expect(ranger.stocks, 0);
      expect(ranger.eliminated, isTrue);
      expect(state.finished, isTrue);
      expect(state.winner, 0);
    });

    test('the state stops changing after the match ends', () {
      final (sim, state) = _setup();
      state.fighters[1].stocks = 1;
      _knockOut(state.fighters[1], sim);
      sim.step(state, _idle);
      expect(state.finished, isTrue);

      final before = state.checksum();
      _run(sim, state, 30, [
        InputFrame.of([Button.right, Button.jump]),
        InputFrame.none,
      ]);
      expect(state.checksum(), before);
    });

    test('both losing their last stock on the same tick is a draw', () {
      final (sim, state) = _setup();
      for (final f in state.fighters) {
        f.stocks = 1;
        _knockOut(f, sim);
      }
      sim.step(state, _idle);
      expect(state.finished, isTrue);
      expect(state.winner, -1);
    });
  });

  group('time limit', () {
    test('the default match is 4 minutes', () {
      final sim = MatchSimulation(
        stage: StageDef.flatArena,
        fighterDefs: [knightDef, rangerDef],
      );
      expect(sim.timeLimitTicks, 4 * 60 * MatchSimulation.ticksPerSecond);
    });

    test('the clock counts down to zero', () {
      final (sim, state) = _setup(timeLimitTicks: 300);
      expect(sim.ticksLeft(state), 180);
      _run(sim, state, 500);
      expect(sim.ticksLeft(state), 0);
    });

    test('at time up, more stocks wins', () {
      final (sim, state) = _setup(timeLimitTicks: 200);
      state.fighters[0].stocks = 2;
      state.fighters[1].damage = 150; // damage only breaks stock ties
      _run(sim, state, 100);
      expect(state.finished, isTrue);
      expect(state.winner, 1);
    });

    test('at time up with equal stocks, lower damage wins', () {
      final (sim, state) = _setup(timeLimitTicks: 200);
      state.fighters[0].damage = 40;
      state.fighters[1].damage = 55;
      _run(sim, state, 100);
      expect(state.winner, 0);
    });

    test('equal stocks and damage at time up is a draw', () {
      final (sim, state) = _setup(timeLimitTicks: 200);
      state.fighters[0].damage = 30;
      state.fighters[1].damage = 30;
      _run(sim, state, 100);
      expect(state.finished, isTrue);
      expect(state.winner, -1);
    });

    test('the match does not end before time is up', () {
      final (sim, state) = _setup(timeLimitTicks: 200);
      _run(sim, state, 79);
      expect(state.finished, isFalse);
      sim.step(state, _idle);
      expect(state.finished, isTrue);
    });
  });

  test('the result is part of the saved state', () {
    final (sim, state) = _setup();
    state.fighters[1].stocks = 1;
    _knockOut(state.fighters[1], sim);
    sim.step(state, _idle);
    final saved = state.copy();
    expect(saved.finished, isTrue);
    expect(saved.winner, 0);
    expect(saved.checksum(), state.checksum());
  });
}
