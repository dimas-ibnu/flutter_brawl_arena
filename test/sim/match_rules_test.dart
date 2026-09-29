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
  group('stocks and respawning', () {
    test('losing a stock takes you out of play for the respawn delay', () {
      final (sim, state) = _setup();
      final ranger = state.fighters[1];
      _knockOut(ranger, sim);
      sim.step(state, _idle);
      expect(ranger.stocks, sim.startingStocks - 1);
      expect(ranger.damage, 0);
      expect(ranger.inPlay, isFalse);
      expect(ranger.respawnTimer, sim.respawnDelayTicks);
      expect(sim.respawnDelayTicks, inInclusiveRange(60, 120), reason: '1-2 s');
    });

    test('while waiting, the fighter ignores input and cannot lose stocks', () {
      final (sim, state) = _setup();
      final ranger = state.fighters[1];
      _knockOut(ranger, sim);
      sim.step(state, _idle);
      final parked = (ranger.x, ranger.y);
      _run(sim, state, sim.respawnDelayTicks - 1, [
        InputFrame.none,
        InputFrame.of([Button.right, Button.jump]),
      ]);
      expect((ranger.x, ranger.y), parked);
      expect(ranger.stocks, sim.startingStocks - 1);
      expect(ranger.inPlay, isFalse);
    });

    test('after the delay it drops in above the stage, invincible', () {
      final (sim, state) = _setup();
      final ranger = state.fighters[1];
      _knockOut(ranger, sim);
      sim.step(state, _idle);
      _run(sim, state, sim.respawnDelayTicks);
      expect(ranger.inPlay, isTrue);
      expect(ranger.invincible, greaterThan(0));
      expect(ranger.y < sim.stage.groundY, isTrue, reason: 'above the stage');
      expect(
        ranger.x >= sim.stage.groundLeft + MatchSimulation.spawnEdgeMargin,
        isTrue,
      );
      expect(
        ranger.x <= sim.stage.groundRight - MatchSimulation.spawnEdgeMargin,
        isTrue,
      );
    });

    Fx dropX(int seed, {int opponentX = 0}) {
      final sim = MatchSimulation(
        stage: StageDef.flatArena,
        fighterDefs: [knightDef, rangerDef],
      );
      final state = sim.initialState(seed: seed);
      _run(sim, state, 120);
      state.fighters[0].x = Fx.fromInt(opponentX);
      _knockOut(state.fighters[1], sim);
      sim.step(state, _idle);
      _run(sim, state, sim.respawnDelayTicks);
      return state.fighters[1].x;
    }

    test('the drop point is random', () {
      final spots = {for (var seed = 1; seed <= 20; seed++) dropX(seed)};
      expect(spots.length, greaterThan(10));
    });

    test('the drop point is never right above the opponent', () {
      for (var seed = 1; seed <= 60; seed++) {
        for (final opponentX in [-300, 0, 300]) {
          final gap =
              (dropX(seed, opponentX: opponentX) - Fx.fromInt(opponentX)).abs();
          expect(
            gap >= MatchSimulation.minSpawnDistance,
            isTrue,
            reason: 'seed $seed, opponent at $opponentX, gap ${gap.toDouble()}',
          );
        }
      }
    });

    test('the same seed always drops at the same spot (replays agree)', () {
      expect(dropX(7), dropX(7));
    });

    test('hits pass through a fighter that just dropped in', () {
      final (sim, state) = _setup();
      final ranger = state.fighters[1];
      _knockOut(ranger, sim);
      sim.step(state, _idle);
      _run(sim, state, sim.respawnDelayTicks + 60); // drop and land
      expect(ranger.invincible, greaterThan(0));
      _faceOff(state);
      sim.step(state, _jab);
      _run(sim, state, 10);
      expect(ranger.damage, 0);
    });

    test('once invincibility ends, hits land again', () {
      final (sim, state) = _setup();
      final ranger = state.fighters[1];
      _knockOut(ranger, sim);
      sim.step(state, _idle);
      _run(sim, state, sim.respawnDelayTicks + sim.respawnInvincibleTicks);
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
        _run(sim, state, sim.respawnDelayTicks + 1);
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
