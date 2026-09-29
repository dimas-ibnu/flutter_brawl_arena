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

  /// Hitstun ticks per unit of knockback speed.
  static const Fx hitstunPerKnockback = Fx.ratio(8, 5);

  /// Advances [state] by one tick. [inputs] holds one frame per fighter.
  void step(GameState state, List<InputFrame> inputs) {
    assert(inputs.length == state.fighters.length);
    for (var i = 0; i < state.fighters.length; i++) {
      _stepFighter(state.fighters[i], fighterDefs[i], inputs[i], i);
    }
    _resolveHits(state);
    state.frame++;
  }

  /// Knockback speed for [attack] on a target that has [damage] percent
  /// (after this hit) and [weight]. Formula from the PRD:
  /// (base + growth × damage / 100) × 100 / weight.
  static Fx knockback(AttackDef attack, int damage, int weight) {
    final raw =
        attack.baseKnockback +
        attack.knockbackGrowth.mulInt(damage).divInt(100);
    return raw.mulInt(100).divInt(weight);
  }

  // Movement, attacks and hitstun for one fighter.
  void _stepFighter(
    FighterState f,
    FighterDef def,
    InputFrame input,
    int slot,
  ) {
    final canAct = f.hitstun == 0;
    if (f.hitstun > 0) f.hitstun--;

    // Attack timing.
    if (f.attackFrame > 0) {
      f.attackFrame++;
      if (f.attackFrame > def.lightAttack.totalFrames) f.attackFrame = 0;
    }
    if (canAct &&
        f.attackFrame == 0 &&
        input.wasPressed(Button.light, f.lastInput)) {
      f.attackFrame = 1;
      f.attackHit = false;
    }
    final attacking = f.attackFrame > 0;

    // Horizontal speed moves toward a target instead of snapping to it, so a
    // launched fighter keeps flying.
    final dir = canAct ? input.horizontal : 0;
    final Fx targetVx;
    final Fx accel;
    if (!canAct) {
      targetVx = Fx.zero;
      accel = f.grounded ? def.groundAccel : def.knockbackDrag;
    } else if (attacking && f.grounded) {
      targetVx = Fx.zero;
      accel = def.groundAccel;
    } else {
      targetVx = def.walkSpeed.mulInt(dir);
      accel = f.grounded ? def.groundAccel : def.airAccel;
    }
    f.vx = _approach(f.vx, targetVx, accel);
    if (canAct && !attacking && dir != 0) f.facing = dir;

    final jumpPressed =
        input.wasPressed(Button.jump, f.lastInput) ||
        input.wasPressed(Button.up, f.lastInput);
    if (canAct && !attacking && jumpPressed) {
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
    if (canAct &&
        !f.grounded &&
        input.isHeld(Button.down) &&
        !f.vy.isNegative) {
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

  // Finds every hit first, then applies them, so two fighters that hit each
  // other on the same tick both get hit (a trade), whatever the slot order.
  void _resolveHits(GameState state) {
    final fighters = state.fighters;
    final hits = <(int, int)>[];
    for (var a = 0; a < fighters.length; a++) {
      final attacker = fighters[a];
      final attack = fighterDefs[a].lightAttack;
      if (attacker.attackHit || !attack.isActiveOn(attacker.attackFrame)) {
        continue;
      }
      final hitbox = hitboxOf(attacker, attack);
      for (var t = 0; t < fighters.length; t++) {
        if (t != a && hitbox.overlaps(hurtboxOf(fighters[t], fighterDefs[t]))) {
          hits.add((a, t));
        }
      }
    }

    for (final (a, t) in hits) {
      final attacker = fighters[a];
      final target = fighters[t];
      final attack = fighterDefs[a].lightAttack;
      attacker.attackHit = true;

      target.damage += attack.damage;
      final speed = knockback(attack, target.damage, fighterDefs[t].weight);
      target.vx = (attack.launchX * speed).mulInt(attacker.facing);
      target.vy = attack.launchY * speed;
      target.hitstun = (speed * hitstunPerKnockback).floorToInt();
      target.attackFrame = 0;
      target.grounded = false;
    }
  }

  /// World-space hitbox of [attack] for [f] (used for hits and debug drawing).
  static Box hitboxOf(FighterState f, AttackDef attack) {
    final cx = f.x + attack.forward.mulInt(f.facing);
    final cy = f.y - attack.up;
    final hw = attack.width.divInt(2);
    final hh = attack.height.divInt(2);
    return Box(cx - hw, cy - hh, cx + hw, cy + hh);
  }

  static Box hurtboxOf(FighterState f, FighterDef def) {
    final hw = def.width.divInt(2);
    return Box(f.x - hw, f.y - def.height, f.x + hw, f.y);
  }

  static Fx _approach(Fx value, Fx target, Fx step) {
    if (value < target) return Fx.min(value + step, target);
    if (value > target) return Fx.max(value - step, target);
    return value;
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
    f.attackFrame = 0;
    f.hitstun = 0;
  }
}

/// Axis-aligned box in world units (y grows downward).
class Box {
  const Box(this.left, this.top, this.right, this.bottom);

  final Fx left;
  final Fx top;
  final Fx right;
  final Fx bottom;

  bool overlaps(Box other) =>
      left < other.right &&
      other.left < right &&
      top < other.bottom &&
      other.top < bottom;
}
