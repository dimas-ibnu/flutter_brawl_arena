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
    this.timeLimitTicks = 4 * 60 * ticksPerSecond,
    this.respawnInvincibleTicks = 2 * ticksPerSecond,
  });

  static const int ticksPerSecond = 60;

  final StageDef stage;

  /// One entry per player slot.
  final List<FighterDef> fighterDefs;
  final int startingStocks;

  /// Match length (4 minutes by default).
  final int timeLimitTicks;

  /// Invincibility after respawning (2 seconds by default).
  final int respawnInvincibleTicks;

  /// Ticks left on the match clock.
  int ticksLeft(GameState state) =>
      (timeLimitTicks - state.frame).clamp(0, timeLimitTicks);

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
  /// Does nothing once the match is finished.
  void step(GameState state, List<InputFrame> inputs) {
    assert(inputs.length == state.fighters.length);
    if (state.finished) return;
    for (var i = 0; i < state.fighters.length; i++) {
      final f = state.fighters[i];
      if (!f.eliminated) _stepFighter(f, fighterDefs[i], inputs[i], i);
    }
    _resolveHits(state);
    state.frame++;
    _checkForEnd(state);
  }

  // PRD rules: the last fighter with stocks wins. When time runs out, more
  // stocks wins, then lower damage; a full tie is a draw.
  void _checkForEnd(GameState state) {
    final alive = [
      for (var i = 0; i < state.fighters.length; i++)
        if (!state.fighters[i].eliminated) i,
    ];
    if (alive.length <= 1) {
      state.finished = true;
      state.winner = alive.length == 1 ? alive.first : -1;
      return;
    }
    if (state.frame < timeLimitTicks) return;

    state.finished = true;
    state.winner = -1;
    var best = alive.first;
    var tied = false;
    for (final i in alive.skip(1)) {
      final a = state.fighters[i];
      final b = state.fighters[best];
      final better =
          a.stocks > b.stocks || (a.stocks == b.stocks && a.damage < b.damage);
      final same = a.stocks == b.stocks && a.damage == b.damage;
      if (better) {
        best = i;
        tied = false;
      } else if (same) {
        tied = true;
      }
    }
    if (!tied) state.winner = best;
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

  // Movement, dodges, attacks and hitstun for one fighter.
  void _stepFighter(
    FighterState f,
    FighterDef def,
    InputFrame input,
    int slot,
  ) {
    final canAct = f.hitstun == 0;
    if (f.hitstun > 0) f.hitstun--;
    if (f.invincible > 0) f.invincible--;
    if (f.dodgeCooldown > 0) f.dodgeCooldown--;

    // Dodge and attack timing.
    if (f.dodgeFrame > 0 && ++f.dodgeFrame > def.dodgeFrames) {
      f.dodgeFrame = 0;
      f.dodgeCooldown = def.dodgeCooldown;
    }
    if (f.attackFrame > 0 && ++f.attackFrame > _moveOf(f, def).totalFrames) {
      f.attackFrame = 0;
    }

    // Start a dodge or an attack. Dodge wins if both are pressed.
    final free = canAct && f.attackFrame == 0 && f.dodgeFrame == 0;
    if (free && input.wasPressed(Button.dodge, f.lastInput)) {
      _startDodge(f, def, input);
    } else if (free && input.wasPressed(Button.light, f.lastInput)) {
      _startAttack(f, _chooseMove(f, input, heavy: false), input);
    } else if (free && input.wasPressed(Button.heavy, f.lastInput)) {
      _startAttack(f, _chooseMove(f, input, heavy: true), input);
    }
    final attacking = f.attackFrame > 0;
    final dodging = f.dodgeFrame > 0;

    if (attacking) {
      final move = _moveOf(f, def);
      if (f.attackFrame == move.startup + 1) {
        if (move.selfVx != Fx.zero) f.vx = move.selfVx.mulInt(f.facing);
        if (move.selfVy != Fx.zero) f.vy = move.selfVy;
      }
    }

    // Horizontal speed moves toward a target instead of snapping to it, so a
    // launched fighter keeps flying. A dodge keeps its own speed.
    if (!dodging) {
      final dir = canAct ? input.horizontal : 0;
      final Fx targetVx;
      final Fx accel;
      if (!canAct) {
        targetVx = Fx.zero;
        accel = f.grounded ? def.groundAccel : def.knockbackDrag;
      } else if (attacking && f.grounded) {
        targetVx = Fx.zero;
        accel = def.attackFriction;
      } else {
        targetVx = def.walkSpeed.mulInt(dir);
        accel = f.grounded ? def.groundAccel : def.airAccel;
      }
      f.vx = _approach(f.vx, targetVx, accel);
      if (canAct && !attacking && dir != 0) f.facing = dir;
    }

    final jumpPressed =
        input.wasPressed(Button.jump, f.lastInput) ||
        input.wasPressed(Button.up, f.lastInput);
    if (canAct && !attacking && !dodging && jumpPressed) {
      if (f.grounded) {
        f.vy = -def.jumpSpeed;
        f.grounded = false;
      } else if (f.airJumpsLeft > 0) {
        f.vy = -def.airJumpSpeed;
        f.airJumpsLeft--;
      }
    }

    if (!dodging) {
      f.vy = Fx.min(f.vy + def.gravity, def.maxFallSpeed);
      // Holding down past the top of a jump drops at fast-fall speed.
      if (canAct &&
          !f.grounded &&
          input.isHeld(Button.down) &&
          !f.vy.isNegative) {
        f.vy = Fx.max(f.vy, def.fastFallSpeed);
      }
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
      f.airDodgeUsed = false;
      f.recoveryUsed = false;
      if (attacking && _moveOf(f, def).endsOnLanding) f.attackFrame = 0;
    } else {
      f.grounded = false;
    }

    if (_inBlastZone(f)) _loseStock(f, def, slot);

    f.lastInput = input;
  }

  /// Picks the attack for a button press. Null = nothing (recovery used up).
  static MoveKind? _chooseMove(
    FighterState f,
    InputFrame input, {
    required bool heavy,
  }) {
    final down = input.vertical > 0;
    final side = input.horizontal != 0;
    if (f.grounded) {
      if (down) return heavy ? MoveKind.downHeavy : MoveKind.downLight;
      if (side) return heavy ? MoveKind.sideHeavy : MoveKind.sideLight;
      return heavy ? MoveKind.neutralHeavy : MoveKind.neutralLight;
    }
    if (heavy) {
      if (down) return MoveKind.groundPound;
      return f.recoveryUsed ? null : MoveKind.recovery;
    }
    if (down) return MoveKind.downAir;
    if (side) return MoveKind.sideAir;
    return MoveKind.neutralAir;
  }

  static void _startAttack(FighterState f, MoveKind? kind, InputFrame input) {
    if (kind == null) return;
    f.attackMove = kind.index;
    f.attackFrame = 1;
    f.attackHit = false;
    // Side attacks turn toward the pressed direction.
    if (input.horizontal != 0) f.facing = input.horizontal;
    if (kind == MoveKind.recovery) f.recoveryUsed = true;
  }

  /// On the ground: dodge in place, or roll left/right. In the air: dodge in
  /// the pressed direction (or hover in place), once per trip into the air.
  static void _startDodge(FighterState f, FighterDef def, InputFrame input) {
    if (f.dodgeCooldown > 0 || (!f.grounded && f.airDodgeUsed)) return;
    final h = input.horizontal;
    final v = f.grounded ? 0 : input.vertical;
    // Diagonals travel at ~0.7 of full speed on each axis.
    final speed = (h != 0 && v != 0)
        ? def.dodgeSpeed * const Fx.ratio(7, 10)
        : def.dodgeSpeed;
    f.vx = speed.mulInt(h);
    f.vy = speed.mulInt(v);
    f.dodgeFrame = 1;
    if (!f.grounded) f.airDodgeUsed = true;
  }

  static AttackDef _moveOf(FighterState f, FighterDef def) =>
      def.move(MoveKind.values[f.attackMove]);

  // Finds every hit first, then applies them, so two fighters that hit each
  // other on the same tick both get hit (a trade), whatever the slot order.
  void _resolveHits(GameState state) {
    final fighters = state.fighters;
    final hits = <(int, int)>[];
    for (var a = 0; a < fighters.length; a++) {
      final attacker = fighters[a];
      if (attacker.eliminated ||
          attacker.attackFrame == 0 ||
          attacker.attackHit) {
        continue;
      }
      final attack = _moveOf(attacker, fighterDefs[a]);
      if (!attack.isActiveOn(attacker.attackFrame)) continue;
      final hitbox = hitboxOf(attacker, attack);
      for (var t = 0; t < fighters.length; t++) {
        final target = fighters[t];
        if (t == a ||
            target.eliminated ||
            target.dodgeFrame > 0 ||
            target.invincible > 0) {
          continue;
        }
        if (hitbox.overlaps(hurtboxOf(target, fighterDefs[t]))) {
          hits.add((a, t));
        }
      }
    }

    for (final (a, t) in hits) {
      final attacker = fighters[a];
      final target = fighters[t];
      final attack = _moveOf(attacker, fighterDefs[a]);
      attacker.attackHit = true;

      target.damage += attack.damage;
      final speed = knockback(attack, target.damage, fighterDefs[t].weight);
      final side = attack.launchAway && target.x != attacker.x
          ? (target.x > attacker.x ? 1 : -1)
          : attacker.facing;
      target.vx = (attack.launchX * speed).mulInt(side);
      target.vy = attack.launchY * speed;
      target.hitstun = (speed * hitstunPerKnockback).floorToInt();
      target.attackFrame = 0;
      target.grounded = false;
      // Getting hit gives the air dodge and recovery back.
      target.airDodgeUsed = false;
      target.recoveryUsed = false;
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

  /// The hitbox of [f]'s current attack, or null when not attacking.
  Box? currentHitbox(int slot, FighterState f) =>
      f.attackFrame == 0 ? null : hitboxOf(f, _moveOf(f, fighterDefs[slot]));

  /// The current attack's definition, or null when not attacking.
  AttackDef? currentMove(int slot, FighterState f) =>
      f.attackFrame == 0 ? null : _moveOf(f, fighterDefs[slot]);

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
    f.invincible = f.eliminated ? 0 : respawnInvincibleTicks;
    f.damage = 0;
    f.x = stage.spawnX[slot];
    f.y = stage.spawnY;
    f.vx = Fx.zero;
    f.vy = Fx.zero;
    f.grounded = false;
    f.airJumpsLeft = def.airJumps;
    f.attackFrame = 0;
    f.hitstun = 0;
    f.dodgeFrame = 0;
    f.dodgeCooldown = 0;
    f.airDodgeUsed = false;
    f.recoveryUsed = false;
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
