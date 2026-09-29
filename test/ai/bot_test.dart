import 'package:brawl_arena/ai/bot.dart';
import 'package:brawl_arena/sim/defs.dart';
import 'package:brawl_arena/sim/fixed.dart';
import 'package:brawl_arena/sim/game_state.dart';
import 'package:brawl_arena/sim/input_frame.dart';
import 'package:brawl_arena/sim/match_simulation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fighters.dart';

const _none = InputFrame.none;

MatchSimulation _sim() => MatchSimulation(
  stage: StageDef.flatArena,
  fighterDefs: [knightDef, rangerDef],
);

/// Both fighters landed, the Knight (slot 0) at [knightX], the Ranger (the
/// bot, slot 1) at [botX].
GameState _landed(MatchSimulation sim, {int knightX = -200, int botX = 200}) {
  final state = sim.initialState(seed: 1);
  for (var i = 0; i < 120; i++) {
    sim.step(state, const [_none, _none]);
  }
  state.fighters[0].x = Fx.fromInt(knightX);
  state.fighters[1].x = Fx.fromInt(botX);
  return state;
}

/// Normal, with overrides for one behavior at a time.
BotProfile _profile({
  int reactionTicks = 15,
  int dodgeChance = 35,
  int edgeGuardChance = 50,
  int heavyChance = 15,
  int finisherHeavyChance = 80,
  int minThinkTicks = 6,
  int maxThinkTicks = 16,
}) => BotProfile(
  name: 'test',
  reactionTicks: reactionTicks,
  dodgeChance: dodgeChance,
  edgeGuardChance: edgeGuardChance,
  heavyChance: heavyChance,
  finisherHeavyChance: finisherHeavyChance,
  finisherDamage: 120,
  minThinkTicks: minThinkTicks,
  maxThinkTicks: maxThinkTicks,
  comboHits: 2,
);

/// Runs bot (slot 1) against a Knight that sends [knightInput] every tick.
void _play(
  MatchSimulation sim,
  GameState state,
  Bot bot,
  int ticks, [
  InputFrame knightInput = _none,
]) {
  for (var i = 0; i < ticks && !state.finished; i++) {
    sim.step(state, [knightInput, bot.think(state)]);
  }
}

void main() {
  test('the Normal profile matches the PRD', () {
    const n = BotProfile.normal;
    expect(n.reactionTicks, 15);
    expect(n.dodgeChance, 35);
    expect(n.comboHits, 2);
    expect(n.finisherDamage, 120);
  });

  group('fighting', () {
    test('walks over and hits a player who stands still', () {
      final sim = _sim();
      final state = _landed(sim);
      final knight = state.fighters[0];
      final bot = Bot(sim: sim, slot: 1);
      var hit = false;
      for (var i = 0; i < 3 * 60 && !hit; i++) {
        sim.step(state, [_none, bot.think(state)]);
        // A knockout resets damage, so count a lost stock as a hit too.
        hit = knight.damage > 0 || knight.stocks < sim.startingStocks;
      }
      expect(hit, isTrue);
    });

    test('wins against a player who never moves', () {
      final sim = _sim();
      final state = _landed(sim);
      _play(sim, state, Bot(sim: sim, slot: 1), 90 * 60);
      expect(state.finished, isTrue);
      expect(state.winner, 1);
    });

    test('picks heavies to finish once the target is past 120%', () {
      MoveKind firstAttack(int targetDamage) {
        final sim = _sim();
        final state = _landed(sim, knightX: 0, botX: 60);
        state.fighters[0].damage = targetDamage;
        final bot = Bot(
          sim: sim,
          slot: 1,
          profile: _profile(heavyChance: 0, finisherHeavyChance: 100),
        );
        while (state.fighters[1].attackFrame == 0) {
          sim.step(state, [_none, bot.think(state)]);
        }
        return MoveKind.values[state.fighters[1].attackMove];
      }

      const heavies = [
        MoveKind.neutralHeavy,
        MoveKind.sideHeavy,
        MoveKind.downHeavy,
      ];
      expect(heavies, contains(firstAttack(150)));
      expect(heavies, isNot(contains(firstAttack(0))));
    });

    test('taps buttons instead of holding them', () {
      final sim = _sim();
      final state = _landed(sim);
      final bot = Bot(sim: sim, slot: 1);
      var previous = _none;
      const tapped = [Button.light, Button.heavy, Button.jump, Button.dodge];
      for (var i = 0; i < 20 * 60 && !state.finished; i++) {
        final input = bot.think(state);
        for (final b in tapped) {
          expect(
            input.isHeld(b) && previous.isHeld(b),
            isFalse,
            reason: '${b.name} held two ticks in a row at tick $i',
          );
        }
        previous = input;
        sim.step(state, [_none, input]);
      }
    });
  });

  group('recovery', () {
    for (final side in [-1, 1]) {
      for (final (out, height, jumps) in [
        (100, 0, 2),
        (260, -150, 1),
        (200, 80, 0),
        (360, 60, 2),
      ]) {
        final where = side == 1 ? 'right' : 'left';
        test('gets back from $out units off the $where edge '
            '(y $height, $jumps jumps left)', () {
          final sim = _sim();
          final state = _landed(sim, knightX: -side * 300);
          final edge = side == 1 ? sim.stage.groundRight : sim.stage.groundLeft;
          state.fighters[1]
            ..x = edge + Fx.fromInt(side * out)
            ..y = Fx.fromInt(height)
            ..vx = Fx.fromInt(side * 4)
            ..vy = Fx.zero
            ..grounded = false
            ..airJumpsLeft = jumps;

          _play(sim, state, Bot(sim: sim, slot: 1), 400);
          expect(state.fighters[1].stocks, sim.startingStocks);
        });
      }
    }
  });

  group('reaction and defense', () {
    test('reacts to where the opponent was 15 ticks ago', () {
      final sim = _sim();
      // Far enough apart that the bot never gets in range to attack.
      final state = _landed(sim, knightX: -400, botX: 300);
      final bot = Bot(sim: sim, slot: 1);
      _play(sim, state, bot, 20);
      expect(state.fighters[1].vx.isNegative, isTrue, reason: 'heading left');

      state.fighters[0].x = Fx.fromInt(450); // teleport to the other side
      for (var i = 0; i < 14; i++) {
        final input = bot.think(state);
        expect(input.horizontal, isNot(1), reason: 'too early at tick $i');
        sim.step(state, [_none, input]);
      }
      var turned = false;
      for (var i = 0; i < 5 && !turned; i++) {
        final input = bot.think(state);
        turned = input.horizontal == 1;
        sim.step(state, [_none, input]);
      }
      expect(turned, isTrue);
    });

    int damageFromHeavy(int dodgeChance) {
      final sim = _sim();
      final state = _landed(sim, knightX: 0, botX: 60);
      final bot = Bot(
        sim: sim,
        slot: 1,
        // React almost at once and never attack, to test dodging alone.
        profile: _profile(
          reactionTicks: 1,
          dodgeChance: dodgeChance,
          minThinkTicks: 10000,
          maxThinkTicks: 10000,
        ),
      );
      sim.step(state, [
        InputFrame.of([Button.heavy]),
        bot.think(state),
      ]);
      _play(sim, state, bot, 40);
      return state.fighters[1].damage;
    }

    test('dodges an incoming attack it has time to see', () {
      expect(damageFromHeavy(100), 0);
    });

    test('with a 0% dodge chance it gets hit', () {
      expect(damageFromHeavy(0), greaterThan(0));
    });

    test('edge-guards: waits at the ledge while the opponent is off stage', () {
      Fx botXAfter(int edgeGuardChance) {
        final sim = _sim();
        final state = _landed(sim, knightX: 0, botX: 0);
        state.fighters[0]
          ..x = sim.stage.groundRight + Fx.fromInt(300)
          ..y = Fx.fromInt(-400)
          ..vy = Fx.zero
          ..grounded = false;
        final bot = Bot(
          sim: sim,
          slot: 1,
          profile: _profile(edgeGuardChance: edgeGuardChance),
        );
        _play(sim, state, bot, 70);
        return state.fighters[1].x;
      }

      expect(botXAfter(100) > Fx.fromInt(350), isTrue);
      expect(botXAfter(0).abs() < Fx.fromInt(60), isTrue);
    });
  });

  group('determinism', () {
    (int, int) botMatch() {
      final sim = _sim();
      final state = sim.initialState(seed: 5);
      final a = Bot(sim: sim, slot: 0, seed: 11);
      final b = Bot(sim: sim, slot: 1, seed: 22);
      while (!state.finished) {
        sim.step(state, [a.think(state), b.think(state)]);
      }
      return (state.frame, state.checksum());
    }

    test('a bot-vs-bot match finishes and plays out the same every time', () {
      final first = botMatch();
      expect(first.$1, lessThan(4 * 60 * 60 + 1));
      expect(botMatch(), first);
    });

    test('reset starts the bot over', () {
      final sim = _sim();
      List<InputFrame> record(Bot bot) {
        final state = _landed(sim);
        return [
          for (var i = 0; i < 300; i++)
            () {
              final input = bot.think(state);
              sim.step(state, [_none, input]);
              return input;
            }(),
        ];
      }

      final bot = Bot(sim: sim, slot: 1, seed: 9);
      final first = record(bot);
      bot.reset();
      expect(record(bot), first);
    });

    test('does nothing once the match is over', () {
      final sim = _sim();
      final state = _landed(sim, knightX: 0, botX: 60)..finished = true;
      expect(Bot(sim: sim, slot: 1).think(state), _none);
    });
  });
}
