import '../sim/defs.dart';
import '../sim/fixed.dart';
import '../sim/game_state.dart';
import '../sim/int_math.dart';
import '../sim/input_frame.dart';
import '../sim/match_simulation.dart';

/// How a bot plays. Numbers from the PRD's difficulty table; the MVP ships
/// [normal] only (Easy and Hard come in Phase 2).
class BotProfile {
  const BotProfile({
    required this.name,
    required this.reactionTicks,
    required this.dodgeChance,
    required this.edgeGuardChance,
    required this.heavyChance,
    required this.finisherHeavyChance,
    required this.finisherDamage,
    required this.minThinkTicks,
    required this.maxThinkTicks,
    required this.comboHits,
  });

  final String name;

  /// How many ticks late the bot sees its opponent.
  final int reactionTicks;

  /// Percent chance to dodge an attack that is about to hit.
  final int dodgeChance;

  /// Percent chance to wait at the ledge when the opponent is off stage.
  final int edgeGuardChance;

  /// Percent chance to pick a heavy attack, normally and once the opponent
  /// has at least [finisherDamage] percent.
  final int heavyChance;
  final int finisherHeavyChance;
  final int finisherDamage;

  /// Pause between attacks (random in this range), so it doesn't spam.
  final int minThinkTicks;
  final int maxThinkTicks;

  /// Longest string of hits thrown without pausing.
  final int comboHits;

  static const normal = BotProfile(
    name: 'Normal',
    reactionTicks: 15,
    dodgeChance: 35,
    edgeGuardChance: 50,
    heavyChance: 15,
    finisherHeavyChance: 80,
    finisherDamage: 120,
    minThinkTicks: 6,
    maxThinkTicks: 16,
    comboHits: 2,
  );
}

/// A computer opponent for a 1v1 match.
///
/// It plays through [InputFrame]s exactly like a human, so it follows the same
/// rules, and any bot slot can later become a local or online player. It
/// sees its opponent [BotProfile.reactionTicks] late and only reads what a
/// player could see on screen. Its randomness comes from its own seeded
/// generator, so the same match always plays out the same way.
///
/// No Flutter and no `double`, like the simulation.
class Bot {
  Bot({
    required this.sim,
    required this.slot,
    this.profile = BotProfile.normal,
    this.seed = 1,
  }) {
    reset();
  }

  final MatchSimulation sim;
  final int slot;
  final BotProfile profile;
  final int seed;

  late int _rng;
  final List<FighterState> _seen = [];
  InputFrame _last = InputFrame.none;
  int _thinkTimer = 0;
  int _comboCount = 0;
  bool _hitLastTick = false;

  // Rolled once per opponent attack / trip off stage, not every tick.
  int _oppFrameSeen = 0;
  bool _dodgeRolled = false;
  bool _willDodge = false;
  bool _edgeGuardRolled = false;
  bool _willEdgeGuard = false;

  static const _lights = [
    MoveKind.neutralLight,
    MoveKind.sideLight,
    MoveKind.downLight,
  ];
  static const _heavies = [
    MoveKind.neutralHeavy,
    MoveKind.sideHeavy,
    MoveKind.downHeavy,
  ];
  static const _aerials = [
    MoveKind.neutralAir,
    MoveKind.sideAir,
    MoveKind.downAir,
  ];

  void reset() {
    _rng = lo32(seed) == 0 ? 0x2545F491 : lo32(seed);
    _seen.clear();
    _last = InputFrame.none;
    _thinkTimer =
        profile.minThinkTicks; // a short pause before the first attack
    _comboCount = 0;
    _hitLastTick = false;
    _oppFrameSeen = 0;
    _dodgeRolled = false;
    _edgeGuardRolled = false;
  }

  int get _oppSlot => 1 - slot;
  FighterDef get _myDef => sim.fighterDefs[slot];
  FighterDef get _oppDef => sim.fighterDefs[_oppSlot];
  StageDef get _stage => sim.stage;
  Fx get _center => (_stage.groundLeft + _stage.groundRight).divInt(2);

  /// Decides this tick's input. Call once per tick, before [MatchSimulation.step].
  InputFrame think(GameState state) {
    final me = state.fighters[slot];
    _seen.add(state.fighters[_oppSlot].copy());
    if (_seen.length > profile.reactionTicks + 1) _seen.removeAt(0);

    final out = _Out(_last);
    if (!state.finished && me.inPlay) _decide(me, _seen.first, out);
    _last = out.frame;
    return _last;
  }

  void _decide(FighterState me, FighterState them, _Out out) {
    _trackCombo(me);
    if (_thinkTimer > 0) _thinkTimer--;

    // 1. Get back to the stage.
    if (_isOffStage(me)) {
      _recover(me, out);
      return;
    }
    final busy = me.hitstun > 0 || me.attackFrame > 0 || me.dodgeFrame > 0;
    if (busy || them.eliminated) return;

    // The opponent is waiting to respawn at an unknown spot: head to the
    // middle instead of camping where they fell.
    if (them.respawnTimer > 0) {
      _walkTo(me, _center, out);
      return;
    }

    final toward = them.x > me.x ? 1 : (them.x < me.x ? -1 : me.facing);

    // 2. Dodge an attack that is about to land.
    if (_shouldDodge(me, them)) {
      out.hold(toward == 1 ? Button.left : Button.right);
      out.tap(Button.dodge);
      return;
    }

    // 3. Edge-guard: wait at the ledge while the opponent tries to come back.
    if (_isOffStage(them)) {
      if (!_edgeGuardRolled) {
        _edgeGuardRolled = true;
        _willEdgeGuard = _chance(profile.edgeGuardChance);
      }
      if (_tryAttack(me, them, toward, out)) return;
      final ledge = them.x > _center
          ? _stage.groundRight - Fx.fromInt(50)
          : _stage.groundLeft + Fx.fromInt(50);
      _walkTo(me, _willEdgeGuard ? ledge : _center, out);
      return;
    }
    _edgeGuardRolled = false;

    // 4. Attack when a move would connect.
    if (_tryAttack(me, them, toward, out)) return;

    // 5. Otherwise close the distance.
    _approach(me, them, toward, out);
  }

  // ---- 1. Recovery ----

  bool _isOffStage(FighterState f) =>
      !f.grounded &&
      (f.x < _stage.groundLeft ||
          f.x > _stage.groundRight ||
          f.y > _stage.groundY);

  void _recover(FighterState me, _Out out) {
    final toward = me.x < _center ? 1 : -1;
    out.hold(toward == 1 ? Button.right : Button.left);
    if (me.hitstun > 0 || me.attackFrame > 0 || me.dodgeFrame > 0) return;

    final edge = toward == 1 ? _stage.groundLeft : _stage.groundRight;
    final far = (me.x - edge).abs() > Fx.fromInt(250);
    final low = me.y > _stage.groundY - Fx.fromInt(120);
    if (me.vy.isNegative || !(low || far)) return;

    if (me.airJumpsLeft > 0) {
      out.tap(Button.jump);
    } else if (!me.recoveryUsed) {
      out.tap(Button.heavy); // heavy in the air without down = recovery
    } else if (!me.airDodgeUsed && me.dodgeCooldown == 0) {
      out.hold(Button.up);
      out.tap(Button.dodge);
    }
  }

  // ---- 2. Defense ----

  bool _shouldDodge(FighterState me, FighterState them) {
    final frame = them.attackFrame;
    final newAttack = frame > 0 && frame < _oppFrameSeen;
    _oppFrameSeen = frame;
    if (frame == 0 || newAttack) _dodgeRolled = false;
    if (frame == 0) return false;

    final move = sim.currentMove(_oppSlot, them)!;
    if (frame > move.startup + move.active) return false;
    final danger = MatchSimulation.hitboxOf(them, move);
    final body = MatchSimulation.hurtboxOf(me, _myDef).inflate(Fx.fromInt(24));
    if (!danger.overlaps(body)) return false;

    if (!_dodgeRolled) {
      _dodgeRolled = true;
      _willDodge = _chance(profile.dodgeChance);
    }
    return _willDodge &&
        me.dodgeCooldown == 0 &&
        (me.grounded || !me.airDodgeUsed);
  }

  // ---- 4. Attacks ----

  void _trackCombo(FighterState me) {
    final hit = me.attackFrame > 0 && me.attackHit;
    if (hit && !_hitLastTick) {
      // Our attack just connected: follow up at once, up to comboHits.
      if (_comboCount + 1 < profile.comboHits) {
        _comboCount++;
        _thinkTimer = 0;
      } else {
        _comboCount = 0;
      }
    }
    _hitLastTick = hit;
  }

  bool _tryAttack(FighterState me, FighterState them, int toward, _Out out) {
    if (_thinkTimer > 0) return false;
    final MoveKind? kind;
    if (me.grounded) {
      final heavyPct = them.damage >= profile.finisherDamage
          ? profile.finisherHeavyChance
          : profile.heavyChance;
      final heavies = _inRange(me, them, toward, _heavies);
      final lights = _inRange(me, them, toward, _lights);
      if (heavies.isNotEmpty && (lights.isEmpty || _chance(heavyPct))) {
        kind = _pick(heavies);
      } else {
        kind = lights.isEmpty ? null : _pick(lights);
      }
    } else {
      final aerials = _inRange(me, them, toward, _aerials);
      kind = aerials.isEmpty ? null : _pick(aerials);
    }
    if (kind == null) return false;

    switch (kind) {
      case MoveKind.sideLight || MoveKind.sideHeavy || MoveKind.sideAir:
        out.hold(toward == 1 ? Button.right : Button.left);
      case MoveKind.downLight || MoveKind.downHeavy || MoveKind.downAir:
        out.hold(Button.down);
      default:
        break;
    }
    out.tap(_heavies.contains(kind) ? Button.heavy : Button.light);
    if (_comboCount == 0) {
      _thinkTimer =
          profile.minThinkTicks +
          _rand(profile.maxThinkTicks - profile.minThinkTicks + 1);
    }
    return true;
  }

  List<MoveKind> _inRange(
    FighterState me,
    FighterState them,
    int toward,
    List<MoveKind> kinds,
  ) => [
    for (final k in kinds)
      if (_wouldHit(me, them, toward, k)) k,
  ];

  /// Would [kind] connect, if the opponent keeps moving the way it was?
  bool _wouldHit(
    FighterState me,
    FighterState them,
    int toward,
    MoveKind kind,
  ) {
    final move = _myDef.move(kind);
    final side =
        kind == MoveKind.sideLight ||
        kind == MoveKind.sideHeavy ||
        kind == MoveKind.sideAir;
    final facing = side ? toward : me.facing;
    final lead = move.startup + 1;

    final myY = me.grounded ? me.y : me.y + me.vy.mulInt(lead);
    var theirY = them.grounded ? them.y : them.y + them.vy.mulInt(lead);
    if (theirY > _stage.groundY) theirY = _stage.groundY;
    final theirX = them.x + them.vx.mulInt(lead);

    return MatchSimulation.hitboxAt(
      me.x,
      myY,
      facing,
      move,
    ).overlaps(MatchSimulation.hurtboxAt(theirX, theirY, _oppDef));
  }

  // ---- 5. Movement ----

  void _approach(FighterState me, FighterState them, int toward, _Out out) {
    final margin = Fx.fromInt(30);
    final target = them.x.clamp(
      _stage.groundLeft + margin,
      _stage.groundRight - margin,
    );
    if (!_walkTo(me, target, out) && me.facing != toward) {
      out.hold(toward == 1 ? Button.right : Button.left); // turn around
    }

    // Jump after an opponent that is above us.
    final above = them.y < me.y - Fx.fromInt(100);
    final near = (them.x - me.x).abs() < Fx.fromInt(220);
    if (above && near && (me.grounded || me.airJumpsLeft > 0)) {
      if (me.grounded || !me.vy.isNegative) out.tap(Button.jump);
    }
  }

  /// Holds a direction toward [x]; false once close enough.
  bool _walkTo(FighterState me, Fx x, _Out out) {
    final dx = x - me.x;
    if (dx.abs() <= Fx.fromInt(24)) return false;
    out.hold(dx.isNegative ? Button.left : Button.right);
    return true;
  }

  // ---- Randomness (xorshift32, separate from the game state) ----

  int _rand(int maxExclusive) {
    final x = xorshift32(_rng);
    _rng = x;
    return x % maxExclusive;
  }

  bool _chance(int percent) => _rand(100) < percent;

  MoveKind _pick(List<MoveKind> kinds) => kinds[_rand(kinds.length)];
}

/// Builds one tick of input. A tap only goes through if the button was up
/// last tick, because the simulation acts on presses, not on held buttons.
class _Out {
  _Out(this._previous);

  final InputFrame _previous;
  int _bits = 0;

  void hold(Button b) => _bits |= b.bit;

  void tap(Button b) {
    if (!_previous.isHeld(b)) _bits |= b.bit;
  }

  InputFrame get frame => InputFrame(_bits);
}
