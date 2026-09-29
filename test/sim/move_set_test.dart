import 'package:brawl_arena/sim/defs.dart';
import 'package:brawl_arena/sim/fixed.dart';
import 'package:brawl_arena/sim/game_state.dart';
import 'package:brawl_arena/sim/input_frame.dart';
import 'package:brawl_arena/sim/match_simulation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fighters.dart';

const _none = InputFrame.none;
const _idle = [_none, _none];

InputFrame _in(List<Button> buttons) => InputFrame.of(buttons);

/// Knight (slot 0) at x = 0 facing right, Ranger (slot 1) at [rangerX],
/// both standing on the ground.
(MatchSimulation, GameState) _setup({int rangerX = 400}) {
  final sim = MatchSimulation(
    stage: StageDef.flatArena,
    fighterDefs: [knightDef, rangerDef],
  );
  final state = sim.initialState(seed: 1);
  _run(sim, state, 120);
  state.fighters[0]
    ..x = Fx.zero
    ..facing = 1;
  state.fighters[1]
    ..x = Fx.fromInt(rangerX)
    ..facing = -1;
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

/// Puts the Knight in the air, [height] above the ground, not moving.
void _lift(FighterState f, int height) {
  f
    ..y = Fx.fromInt(-height)
    ..vy = Fx.zero
    ..grounded = false;
}

MoveKind _moveOf(FighterState f) => MoveKind.values[f.attackMove];

void main() {
  group('choosing a move', () {
    final ground = {
      MoveKind.neutralLight: [Button.light],
      MoveKind.sideLight: [Button.light, Button.right],
      MoveKind.downLight: [Button.light, Button.down],
      MoveKind.neutralHeavy: [Button.heavy],
      MoveKind.sideHeavy: [Button.heavy, Button.right],
      MoveKind.downHeavy: [Button.heavy, Button.down],
    };
    ground.forEach((kind, buttons) {
      test('on the ground: ${buttons.map((b) => b.name).join(' + ')} '
          '= ${kind.name}', () {
        final (sim, state) = _setup();
        sim.step(state, [_in(buttons), _none]);
        expect(state.fighters[0].attackFrame, 1);
        expect(_moveOf(state.fighters[0]), kind);
      });
    });

    final air = {
      MoveKind.neutralAir: [Button.light],
      MoveKind.sideAir: [Button.light, Button.right],
      MoveKind.downAir: [Button.light, Button.down],
      MoveKind.recovery: [Button.heavy],
      MoveKind.groundPound: [Button.heavy, Button.down],
    };
    air.forEach((kind, buttons) {
      test('in the air: ${buttons.map((b) => b.name).join(' + ')} '
          '= ${kind.name}', () {
        final (sim, state) = _setup();
        _lift(state.fighters[0], 300);
        sim.step(state, [_in(buttons), _none]);
        expect(_moveOf(state.fighters[0]), kind);
      });
    });

    test('a side attack turns to face the pressed direction', () {
      final (sim, state) = _setup();
      sim.step(state, [
        _in([Button.light, Button.left]),
        _none,
      ]);
      expect(state.fighters[0].facing, -1);
    });
  });

  group('move effects', () {
    test('side light lunges forward', () {
      final (sim, state) = _setup();
      final lunge = knightDef.move(MoveKind.sideLight);
      sim.step(state, [
        _in([Button.light, Button.right]),
        _none,
      ]);
      _run(sim, state, lunge.startup + 3);
      expect(state.fighters[0].x > Fx.fromInt(10), isTrue);
    });

    test('recovery rises, and only once per trip into the air', () {
      final (sim, state) = _setup();
      final knight = state.fighters[0];
      final recovery = knightDef.move(MoveKind.recovery);
      _lift(knight, 400);

      sim.step(state, [
        _in([Button.heavy]),
        _none,
      ]);
      _run(sim, state, recovery.startup);
      expect(knight.vy.isNegative, isTrue, reason: 'rising');

      _run(sim, state, recovery.totalFrames);
      expect(knight.grounded, isFalse);
      expect(knight.attackFrame, 0);
      sim.step(state, [
        _in([Button.heavy]),
        _none,
      ]);
      expect(knight.attackFrame, 0, reason: 'recovery already used');
    });

    test('landing gives the recovery back', () {
      final (sim, state) = _setup();
      final knight = state.fighters[0];
      _lift(knight, 400);
      sim.step(state, [
        _in([Button.heavy]),
        _none,
      ]);
      while (!knight.grounded) {
        sim.step(state, _idle);
      }
      expect(knight.recoveryUsed, isFalse);
    });

    test('ground pound drops fast and ends on landing', () {
      final (sim, state) = _setup();
      final knight = state.fighters[0];
      final pound = knightDef.move(MoveKind.groundPound);
      _lift(knight, 300);
      sim.step(state, [
        _in([Button.heavy, Button.down]),
        _none,
      ]);
      _run(sim, state, pound.startup);
      expect(knight.vy >= knightDef.maxFallSpeed, isTrue);

      var ticks = pound.startup + 1;
      while (!knight.grounded) {
        sim.step(state, _idle);
        ticks++;
      }
      expect(ticks, lessThan(pound.totalFrames));
      expect(knight.attackFrame, 0, reason: 'ended on landing');
    });

    test('an aerial ends when you land', () {
      final (sim, state) = _setup();
      final knight = state.fighters[0];
      _lift(knight, 10);
      sim.step(state, [
        _in([Button.light]),
        _none,
      ]);
      expect(_moveOf(knight), MoveKind.neutralAir);
      while (!knight.grounded) {
        sim.step(state, _idle);
      }
      expect(knight.attackFrame, 0);
    });

    test('a ground attack keeps going when you walk off an edge', () {
      final (sim, state) = _setup();
      final knight = state.fighters[0];
      knight.x = sim.stage.groundRight - Fx.fromInt(2);
      knight.vx = knightDef.walkSpeed;
      sim.step(state, [
        _in([Button.light]),
        _none,
      ]);
      _run(sim, state, 4);
      expect(knight.grounded, isFalse);
      expect(knight.attackFrame, greaterThan(0));
    });
  });

  group('hits from the move set', () {
    test('down heavy launches a target behind you backwards', () {
      final (sim, state) = _setup(rangerX: -60);
      final dHeavy = knightDef.move(MoveKind.downHeavy);
      sim.step(state, [
        _in([Button.heavy, Button.down]),
        _none,
      ]);
      _run(sim, state, dHeavy.startup);
      final ranger = state.fighters[1];
      expect(ranger.damage, dHeavy.damage);
      expect(ranger.vx.isNegative, isTrue, reason: 'away from the Knight');
    });

    test('down air spikes downward', () {
      final (sim, state) = _setup(rangerX: 10);
      final knight = state.fighters[0];
      final dair = knightDef.move(MoveKind.downAir);
      // Holding down also fast-falls, so start high enough that the hitbox
      // comes out before landing.
      _lift(knight, 190);
      sim.step(state, [
        _in([Button.light, Button.down]),
        _none,
      ]);
      var hit = false;
      for (var i = 0; i < dair.startup + dair.active && !hit; i++) {
        sim.step(state, _idle);
        hit = state.fighters[1].damage > 0;
      }
      expect(hit, isTrue);
      expect(state.fighters[1].vy > Fx.zero, isTrue, reason: 'launched down');
    });

    test('heavies hit harder than lights', () {
      for (final def in [knightDef, rangerDef]) {
        final light = def.move(MoveKind.neutralLight);
        for (final heavy in [
          MoveKind.neutralHeavy,
          MoveKind.sideHeavy,
          MoveKind.downHeavy,
        ]) {
          final h = def.move(heavy);
          expect(h.damage, greaterThan(light.damage), reason: heavy.name);
          expect(
            MatchSimulation.knockback(h, 100, 100) >
                MatchSimulation.knockback(light, 100, 100),
            isTrue,
            reason: heavy.name,
          );
          expect(h.startup, greaterThan(light.startup), reason: heavy.name);
        }
      }
    });
  });

  group('dodge', () {
    test('a dodging fighter cannot be hit', () {
      final (sim, state) = _setup(rangerX: 60);
      sim.step(state, [
        _in([Button.light]),
        _in([Button.dodge]),
      ]);
      _run(sim, state, knightDef.move(MoveKind.neutralLight).totalFrames);
      expect(state.fighters[1].damage, 0);
    });

    test('after the dodge ends, hits land again', () {
      final (sim, state) = _setup(rangerX: 60);
      sim.step(state, [
        _none,
        _in([Button.dodge]),
      ]);
      _run(sim, state, rangerDef.dodgeFrames);
      sim.step(state, [
        _in([Button.light]),
        _none,
      ]);
      _run(sim, state, knightDef.move(MoveKind.neutralLight).startup);
      expect(state.fighters[1].damage, greaterThan(0));
    });

    test('dodge has a cooldown', () {
      final (sim, state) = _setup();
      final knight = state.fighters[0];
      final dodge = [
        _in([Button.dodge]),
        _none,
      ];
      sim.step(state, dodge);
      _run(sim, state, knightDef.dodgeFrames);
      expect(knight.dodgeFrame, 0);

      sim.step(state, dodge);
      expect(knight.dodgeFrame, 0, reason: 'still cooling down');

      _run(sim, state, knightDef.dodgeCooldown);
      sim.step(state, dodge);
      expect(knight.dodgeFrame, 1);
    });

    test('dodge with a direction rolls; without one it stays in place', () {
      final (sim, state) = _setup();
      final knight = state.fighters[0];
      sim.step(state, [
        _in([Button.dodge]),
        _none,
      ]);
      _run(sim, state, 5);
      expect(knight.x, Fx.zero);

      final (sim2, state2) = _setup();
      sim2.step(state2, [
        _in([Button.dodge, Button.right]),
        _none,
      ]);
      _run(sim2, state2, 5);
      expect(state2.fighters[0].x > Fx.fromInt(40), isTrue);
    });

    test('air dodge pauses gravity and works once per trip into the air', () {
      final (sim, state) = _setup();
      final knight = state.fighters[0];
      _lift(knight, 500);
      final dodge = [
        _in([Button.dodge]),
        _none,
      ];
      sim.step(state, dodge);
      _run(sim, state, 5);
      expect(knight.vy, Fx.zero, reason: 'hovering');

      _run(sim, state, knightDef.dodgeFrames);
      knight.dodgeCooldown = 0; // test the once-per-jump rule on its own
      expect(knight.grounded, isFalse);
      sim.step(state, dodge);
      expect(knight.dodgeFrame, 0, reason: 'air dodge used');
    });

    test('getting hit gives the air dodge and recovery back', () {
      final (sim, state) = _setup(rangerX: 60);
      state.fighters[1]
        ..airDodgeUsed = true
        ..recoveryUsed = true;
      sim.step(state, [
        _in([Button.light]),
        _none,
      ]);
      _run(sim, state, knightDef.move(MoveKind.neutralLight).startup);
      expect(state.fighters[1].damage, greaterThan(0));
      expect(state.fighters[1].airDodgeUsed, isFalse);
      expect(state.fighters[1].recoveryUsed, isFalse);
    });
  });
}
