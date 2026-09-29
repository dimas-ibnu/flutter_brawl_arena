import 'defs.dart';
import 'fixed.dart';
import 'game_state.dart';
import 'input_frame.dart';

/// Runs the match one fixed tick at a time.
///
/// [step] is the only way the game state changes. It depends only on the
/// state and the inputs, so feeding the same inputs always gives the same
/// result.
class MatchSimulation {
  MatchSimulation({
    required this.stage,
    required this.fighterDefs,
    this.startingStocks = 3,
  });

  static const int ticksPerSecond = 60;

  final StageDef stage;

  /// One entry per player slot.
  final List<FighterDef> fighterDefs;
  final int startingStocks;

  GameState initialState({required int seed}) => GameState(
    seed: seed,
    fighters: [
      for (var i = 0; i < fighterDefs.length; i++)
        FighterState(
          x: stage.spawnX[i],
          y: stage.spawnY,
          facing: i.isEven ? 1 : -1,
          airJumpsLeft: fighterDefs[i].airJumps,
          stocks: startingStocks,
        ),
    ],
  );

  /// Advances [state] by one tick. [inputs] holds one frame per fighter.
  void step(GameState state, List<InputFrame> inputs) {
    assert(inputs.length == state.fighters.length);
    for (var i = 0; i < state.fighters.length; i++) {
      _stepFighter(state.fighters[i], fighterDefs[i], inputs[i], i);
    }
    state.frame++;
  }

  // Movement: walk, jump (1 ground + air jumps), fast fall, land on the main
  // platform, lose a stock in the blast zone. Attacks and knockback come next.
  void _stepFighter(
    FighterState f,
    FighterDef def,
    InputFrame input,
    int slot,
  ) {
    final dir = input.horizontal;
    f.vx = def.walkSpeed.mulInt(dir);
    if (dir != 0) f.facing = dir;

    final jumpPressed =
        input.wasPressed(Button.jump, f.lastInput) ||
        input.wasPressed(Button.up, f.lastInput);
    if (jumpPressed) {
      if (f.grounded) {
        f.vy = -def.jumpSpeed;
        f.grounded = false;
      } else if (f.airJumpsLeft > 0) {
        f.vy = -def.airJumpSpeed;
        f.airJumpsLeft--;
      }
    }

    f.vy = Fx.min(f.vy + def.gravity, def.maxFallSpeed);
    // Holding down past the top of a jump drops at fast-fall speed.
    if (!f.grounded && input.isHeld(Button.down) && !f.vy.isNegative) {
      f.vy = def.fastFallSpeed;
    }

    final previousY = f.y;
    f.x += f.vx;
    f.y += f.vy;

    final overGround = f.x >= stage.groundLeft && f.x <= stage.groundRight;
    final crossedGround = previousY <= stage.groundY && f.y >= stage.groundY;
    if (overGround && crossedGround && !f.vy.isNegative) {
      f.y = stage.groundY;
      f.vy = Fx.zero;
      f.grounded = true;
      f.airJumpsLeft = def.airJumps;
    } else {
      f.grounded = false;
    }

    if (_inBlastZone(f)) _loseStock(f, def, slot);

    f.lastInput = input;
  }

  bool _inBlastZone(FighterState f) =>
      f.x < stage.blastLeft ||
      f.x > stage.blastRight ||
      f.y < stage.blastTop ||
      f.y > stage.blastBottom;

  void _loseStock(FighterState f, FighterDef def, int slot) {
    f.stocks--;
    f.damage = 0;
    f.x = stage.spawnX[slot];
    f.y = stage.spawnY;
    f.vx = Fx.zero;
    f.vy = Fx.zero;
    f.grounded = false;
    f.airJumpsLeft = def.airJumps;
  }
}
