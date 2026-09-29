import 'fixed.dart';
import 'input_frame.dart';

/// Everything that changes during a match. Only plain data: no Flutter, no
/// timers, no references to rendering, so the state can be copied, restored
/// and hashed. Rollback netcode needs all three.
class FighterState {
  FighterState({
    required this.x,
    required this.y,
    this.vx = Fx.zero,
    this.vy = Fx.zero,
    this.facing = 1,
    this.grounded = false,
    this.airJumpsLeft = 0,
    this.attackFrame = 0,
    this.attackMove = 0,
    this.attackHit = false,
    this.hitstun = 0,
    this.dodgeFrame = 0,
    this.dodgeCooldown = 0,
    this.airDodgeUsed = false,
    this.recoveryUsed = false,
    this.invincible = 0,
    this.damage = 0,
    required this.stocks,
    this.lastInput = InputFrame.none,
  });

  /// Feet position (bottom center), in world units.
  Fx x;
  Fx y;
  Fx vx;
  Fx vy;

  /// 1 = facing right, -1 = facing left.
  int facing;
  bool grounded;
  int airJumpsLeft;

  /// Ticks into the current attack, counting from 1; 0 = not attacking.
  int attackFrame;

  /// Index into MoveKind of the current attack (valid while attacking).
  int attackMove;

  /// True once the current attack has connected, so it hits only once.
  bool attackHit;

  /// Ticks left where this fighter can't act after being hit.
  int hitstun;

  /// Ticks into the current dodge, counting from 1; 0 = not dodging.
  /// Dodging fighters can't be hit.
  int dodgeFrame;

  /// Ticks before the next dodge is allowed.
  int dodgeCooldown;

  /// Air dodge and recovery work once per trip into the air. Landing or
  /// getting hit gives them back.
  bool airDodgeUsed;
  bool recoveryUsed;

  /// Ticks of respawn invincibility left. Can't be hit while above 0.
  int invincible;

  /// Out of stocks: no longer in the match.
  bool get eliminated => stocks <= 0;

  /// Damage percent. Higher damage means bigger knockback.
  int damage;
  int stocks;

  /// Input from the previous tick, used to detect button presses.
  InputFrame lastInput;

  FighterState copy() => FighterState(
    x: x,
    y: y,
    vx: vx,
    vy: vy,
    facing: facing,
    grounded: grounded,
    airJumpsLeft: airJumpsLeft,
    attackFrame: attackFrame,
    attackMove: attackMove,
    attackHit: attackHit,
    hitstun: hitstun,
    dodgeFrame: dodgeFrame,
    dodgeCooldown: dodgeCooldown,
    airDodgeUsed: airDodgeUsed,
    recoveryUsed: recoveryUsed,
    invincible: invincible,
    damage: damage,
    stocks: stocks,
    lastInput: lastInput,
  );

  void _hashInto(_Fnv hash) => hash
    ..add(x.raw)
    ..add(y.raw)
    ..add(vx.raw)
    ..add(vy.raw)
    ..add(facing)
    ..add(grounded ? 1 : 0)
    ..add(airJumpsLeft)
    ..add(attackFrame)
    ..add(attackMove)
    ..add(attackHit ? 1 : 0)
    ..add(hitstun)
    ..add(dodgeFrame)
    ..add(dodgeCooldown)
    ..add(airDodgeUsed ? 1 : 0)
    ..add(recoveryUsed ? 1 : 0)
    ..add(invincible)
    ..add(damage)
    ..add(stocks)
    ..add(lastInput.bits);
}

class GameState {
  GameState({required this.fighters, required int seed, this.frame = 0})
    : rngState = _seedToRng(seed);

  GameState._copy({
    required this.fighters,
    required this.rngState,
    required this.frame,
    required this.finished,
    required this.winner,
    required this.hitFreeze,
  });

  final List<FighterState> fighters;

  /// Ticks since the match started (60 per second).
  int frame;

  /// True once someone is out of stocks or time runs out. The state stops
  /// changing after that.
  bool finished = false;

  /// Slot of the winner, or -1 for a draw (only meaningful when [finished]).
  int winner = -1;

  /// Ticks left of the short pause after a strong hit (hit-freeze). The whole
  /// match stands still, the clock included, to make big hits feel heavy.
  int hitFreeze = 0;

  /// Xorshift32 state. Kept inside the game state so restoring a saved state
  /// also restores the random sequence.
  int rngState;

  GameState copy() => GameState._copy(
    fighters: [for (final f in fighters) f.copy()],
    rngState: rngState,
    frame: frame,
    finished: finished,
    winner: winner,
    hitFreeze: hitFreeze,
  );

  /// A value in `[0, maxExclusive)` from the seeded generator.
  int nextRandom(int maxExclusive) {
    var x = rngState;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    rngState = x;
    return x % maxExclusive;
  }

  /// 32-bit hash of the whole state. Two games that received the same inputs
  /// must have the same checksum on every tick; a mismatch means a desync.
  int checksum() {
    final hash = _Fnv()
      ..add(frame)
      ..add(rngState)
      ..add(finished ? 1 : 0)
      ..add(winner)
      ..add(hitFreeze);
    for (final f in fighters) {
      f._hashInto(hash);
    }
    return hash.value;
  }

  static int _seedToRng(int seed) {
    // Xorshift gets stuck at 0, so replace it with a fixed non-zero value.
    final s = seed & 0xFFFFFFFF;
    return s == 0 ? 0x9E3779B9 : s;
  }
}

/// FNV-1a over 32-bit words.
class _Fnv {
  int value = 0x811C9DC5;

  void add(int v) {
    _word(v & 0xFFFFFFFF);
    _word((v >> 32) & 0xFFFFFFFF);
  }

  void _word(int w) {
    value = ((value ^ w) * 0x01000193) & 0xFFFFFFFF;
  }
}
