import 'package:brawl_arena/sim/defs.dart';
import 'package:brawl_arena/sim/fixed.dart';
import 'package:brawl_arena/sim/game_state.dart';
import 'package:brawl_arena/sim/input_frame.dart';
import 'package:brawl_arena/sim/match_simulation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fighters.dart';

const _idle = [InputFrame.none, InputFrame.none];
final _light = InputFrame.of([Button.light]);
final _jab = AttackDef(
  startup: 5,
  active: 3,
  recovery: 12,
  damage: 7,
  baseKnockback: Fx.fromInt(5),
  knockbackGrowth: Fx.fromInt(14),
  launchX: Fx.ratio(4, 5),
  launchY: Fx.ratio(-3, 5),
  forward: Fx.fromInt(50),
  up: Fx.fromInt(60),
  width: Fx.fromInt(60),
  height: Fx.fromInt(32),
);

/// Knight (slot 0) at x = 0 facing right, Ranger (slot 1) standing at
/// [rangerX], both on the ground.
(MatchSimulation, GameState) _faceOff({int rangerX = 60}) {
  final sim = MatchSimulation(
    stage: StageDef.flatArena,
    fighterDefs: [knightDef, rangerDef],
  );
  final state = sim.initialState(seed: 1);
  for (var i = 0; i < 120; i++) {
    sim.step(state, _idle);
  }
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

void main() {
  group('attack timing', () {
    test('pressing light starts an attack that ends after its frames', () {
      final (sim, state) = _faceOff(rangerX: 400);
      final knight = state.fighters[0];
      sim.step(state, [_light, InputFrame.none]);
      expect(knight.attackFrame, 1);

      _run(sim, state, knightDef.move(MoveKind.neutralLight).totalFrames - 1);
      expect(
        knight.attackFrame,
        knightDef.move(MoveKind.neutralLight).totalFrames,
      );
      sim.step(state, _idle);
      expect(knight.attackFrame, 0);
    });

    test('holding light does not restart the attack', () {
      final (sim, state) = _faceOff(rangerX: 400);
      final total = knightDef.move(MoveKind.neutralLight).totalFrames;
      _run(sim, state, total + 5, [_light, InputFrame.none]);
      expect(state.fighters[0].attackFrame, 0);
    });

    test('attacking on the ground stops walking and turning', () {
      final (sim, state) = _faceOff(rangerX: 400);
      final knight = state.fighters[0];
      sim.step(state, [_light, InputFrame.none]);
      _run(sim, state, 3, [
        InputFrame.of([Button.left]),
        InputFrame.none,
      ]);
      expect(knight.vx, Fx.zero);
      expect(knight.facing, 1);
    });

    test('the hitbox is only active after startup', () {
      expect(_jab.isActiveOn(5), isFalse);
      expect(_jab.isActiveOn(6), isTrue);
      expect(_jab.isActiveOn(8), isTrue);
      expect(_jab.isActiveOn(9), isFalse);
    });
  });

  group('hits', () {
    test('a jab in range damages, launches and stuns the target', () {
      final (sim, state) = _faceOff();
      final ranger = state.fighters[1];
      final attack = knightDef.move(MoveKind.neutralLight);
      sim.step(state, [_light, InputFrame.none]);
      _run(sim, state, attack.startup);

      expect(ranger.damage, attack.damage);
      expect(ranger.hitstun, greaterThan(0));
      expect(ranger.vx > Fx.zero, isTrue, reason: 'pushed away (right)');
      expect(ranger.vy.isNegative, isTrue, reason: 'launched upward');
    });

    test('a jab hits only once per swing', () {
      final (sim, state) = _faceOff();
      sim.step(state, [_light, InputFrame.none]);
      _run(sim, state, knightDef.move(MoveKind.neutralLight).totalFrames);
      expect(
        state.fighters[1].damage,
        knightDef.move(MoveKind.neutralLight).damage,
      );
    });

    test('out of range misses', () {
      final (sim, state) = _faceOff(rangerX: 200);
      sim.step(state, [_light, InputFrame.none]);
      _run(sim, state, knightDef.move(MoveKind.neutralLight).totalFrames);
      expect(state.fighters[1].damage, 0);
    });

    test('facing left launches to the left', () {
      final (sim, state) = _faceOff(rangerX: -60);
      state.fighters[0].facing = -1;
      sim.step(state, [_light, InputFrame.none]);
      _run(sim, state, knightDef.move(MoveKind.neutralLight).startup);
      expect(state.fighters[1].vx.isNegative, isTrue);
    });

    test('attacks on the same tick trade', () {
      final (sim, state) = _faceOff();
      // Ranger's jab is faster; delay its press so both go active together.
      final knightStartup = knightDef.move(MoveKind.neutralLight).startup;
      final rangerStartup = rangerDef.move(MoveKind.neutralLight).startup;
      sim.step(state, [_light, InputFrame.none]);
      _run(sim, state, knightStartup - rangerStartup - 1, [
        _light,
        InputFrame.none,
      ]);
      sim.step(state, [_light, _light]);
      _run(sim, state, rangerStartup, [_light, _light]);

      expect(
        state.fighters[0].damage,
        rangerDef.move(MoveKind.neutralLight).damage,
      );
      expect(
        state.fighters[1].damage,
        knightDef.move(MoveKind.neutralLight).damage,
      );
    });

    test('getting hit cancels your attack', () {
      final (sim, state) = _faceOff();
      final ranger = state.fighters[1];
      // Knight (5 startup) swings first. Ranger (3 startup) presses 3 ticks
      // later, so it is still winding up when the Knight's jab comes out.
      sim.step(state, [_light, InputFrame.none]);
      _run(sim, state, 2, [_light, InputFrame.none]);
      _run(sim, state, 2, [_light, _light]);
      expect(ranger.attackFrame, greaterThan(0));
      sim.step(state, [_light, _light]);
      expect(ranger.hitstun, greaterThan(0));
      expect(ranger.attackFrame, 0);
    });
  });

  group('knockback', () {
    test('grows with damage', () {
      final low = MatchSimulation.knockback(_jab, 0, 100);
      final high = MatchSimulation.knockback(_jab, 100, 100);
      expect(low, _jab.baseKnockback);
      expect(high, _jab.baseKnockback + _jab.knockbackGrowth);
    });

    test('heavier targets fly less', () {
      final light = MatchSimulation.knockback(_jab, 80, 90);
      final heavy = MatchSimulation.knockback(_jab, 80, 115);
      expect(heavy < light, isTrue);
    });

    test('is the same wherever the hitbox touches (no sweet spot)', () {
      double travel(int rangerX) {
        final (sim, state) = _faceOff(rangerX: rangerX);
        final startX = state.fighters[1].x;
        sim.step(state, [_light, InputFrame.none]);
        _run(sim, state, 60);
        expect(state.fighters[1].damage, greaterThan(0));
        return (state.fighters[1].x - startX).toDouble();
      }

      final close = travel(30);
      expect(travel(60), close);
      expect(travel(99), close, reason: 'tip of the hitbox');
    });

    test('a target at high damage flies farther', () {
      double distanceAfterHit(int startDamage) {
        final (sim, state) = _faceOff();
        state.fighters[1].damage = startDamage;
        final startX = state.fighters[1].x;
        sim.step(state, [_light, InputFrame.none]);
        _run(sim, state, 60);
        return (state.fighters[1].x - startX).toDouble();
      }

      expect(distanceAfterHit(120), greaterThan(distanceAfterHit(0)));
    });
  });

  group('hitstun', () {
    test('input is ignored until hitstun ends, then control returns', () {
      final (sim, state) = _faceOff();
      final ranger = state.fighters[1];
      sim.step(state, [_light, InputFrame.none]);
      _run(sim, state, knightDef.move(MoveKind.neutralLight).startup);
      final stun = ranger.hitstun;
      expect(stun, greaterThan(1));

      final walkLeft = [
        InputFrame.none,
        InputFrame.of([Button.left]),
      ];
      sim.step(state, walkLeft);
      expect(ranger.facing, -1, reason: 'unchanged: it was already -1');
      expect(ranger.vx > Fx.zero, isTrue, reason: 'still flying right');

      _run(sim, state, stun + 30, walkLeft);
      expect(ranger.hitstun, 0);
      expect(ranger.vx.isNegative, isTrue, reason: 'now walking left');
    });

    test('hitstun can be neither jumped nor attacked out of', () {
      final (sim, state) = _faceOff();
      final ranger = state.fighters[1];
      sim.step(state, [_light, InputFrame.none]);
      _run(sim, state, knightDef.move(MoveKind.neutralLight).startup);
      final jumpsBefore = ranger.airJumpsLeft;
      sim.step(state, [
        InputFrame.none,
        InputFrame.of([Button.jump]),
      ]);
      sim.step(state, [InputFrame.none, _light]);
      expect(ranger.airJumpsLeft, jumpsBefore);
      expect(ranger.attackFrame, 0);
    });
  });

  group('hit-freeze', () {
    test('weak hits do not freeze the match', () {
      final (sim, state) = _faceOff();
      sim.step(state, [_light, InputFrame.none]);
      _run(sim, state, knightDef.move(MoveKind.neutralLight).startup);
      expect(state.fighters[1].damage, greaterThan(0));
      expect(state.hitFreeze, 0);
    });

    test('strong hits freeze everything briefly, clock included', () {
      final (sim, state) = _faceOff();
      state.fighters[1].damage = 150;
      sim.step(state, [_light, InputFrame.none]);
      _run(sim, state, knightDef.move(MoveKind.neutralLight).startup);
      final freeze = state.hitFreeze;
      expect(freeze, inInclusiveRange(1, MatchSimulation.maxHitFreeze));

      final frame = state.frame;
      final x = state.fighters[1].x;
      _run(sim, state, freeze);
      expect(state.frame, frame, reason: 'clock stopped');
      expect(state.fighters[1].x, x, reason: 'nobody moved');
      sim.step(state, _idle);
      expect(state.frame, frame + 1);
    });
  });

  test('boxes overlap only when they share area', () {
    const a = Box(Fx.zero, Fx.zero, Fx.fromInt(10), Fx.fromInt(10));
    const touching = Box(
      Fx.fromInt(10),
      Fx.zero,
      Fx.fromInt(20),
      Fx.fromInt(10),
    );
    const inside = Box(
      Fx.fromInt(2),
      Fx.fromInt(2),
      Fx.fromInt(4),
      Fx.fromInt(4),
    );
    expect(a.overlaps(touching), isFalse);
    expect(a.overlaps(inside), isTrue);
  });
}
