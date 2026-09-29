import 'fixed.dart';

/// Which attack a button press turns into, from the button, the stick
/// direction and whether the fighter is on the ground.
enum MoveKind {
  // Ground, light button.
  neutralLight,
  sideLight,
  downLight,
  // Air, light button.
  neutralAir,
  sideAir,
  downAir,
  // Ground, heavy button: the strong finishers.
  neutralHeavy,
  sideHeavy,
  downHeavy,
  // Air, heavy button.
  recovery,
  groundPound,
}

/// One attack's timing, hitbox and knockback. Frame counts are ticks.
class AttackDef {
  const AttackDef({
    required this.startup,
    required this.active,
    required this.recovery,
    required this.damage,
    required this.baseKnockback,
    required this.knockbackGrowth,
    required this.launchX,
    required this.launchY,
    required this.forward,
    required this.up,
    required this.width,
    required this.height,
    this.launchAway = false,
    this.selfVx = Fx.zero,
    this.selfVy = Fx.zero,
    this.endsOnLanding = false,
  });

  /// Wind-up ticks before the hitbox appears.
  final int startup;

  /// Ticks the hitbox can hit.
  final int active;

  /// Ticks after the hitbox ends before the fighter can act again.
  final int recovery;

  /// Damage percent added to the target.
  final int damage;

  /// Knockback speed at 0% damage, plus the extra speed added per 100%.
  final Fx baseKnockback;
  final Fx knockbackGrowth;

  /// Launch direction for an attacker facing right (roughly unit length).
  /// Mirrored when the attacker faces left. Negative y is up.
  final Fx launchX;
  final Fx launchY;

  /// For hitboxes around the whole body: launch away from the attacker
  /// instead of in the facing direction.
  final bool launchAway;

  /// Hitbox center, measured from the attacker's feet: [forward] in the
  /// facing direction, [up] above the feet.
  final Fx forward;
  final Fx up;
  final Fx width;
  final Fx height;

  /// Velocity the attacker gets when the hitbox comes out (a lunge, the
  /// recovery's rise, the ground pound's drop). Zero = unchanged.
  final Fx selfVx;
  final Fx selfVy;

  /// Air attacks stop when the fighter lands.
  final bool endsOnLanding;

  int get totalFrames => startup + active + recovery;

  /// [frame] counts from 1 on the tick the attack starts.
  bool isActiveOn(int frame) => frame > startup && frame <= startup + active;
}

/// Tuning values for one fighter. Units: world units and ticks (1/60 s).
///
/// Loaded from assets/data/fighters.json (see lib/data/fighter_data.dart).
class FighterDef {
  const FighterDef({
    required this.name,
    required this.width,
    required this.height,
    required this.weight,
    required this.walkSpeed,
    required this.groundAccel,
    required this.airAccel,
    required this.attackFriction,
    required this.knockbackDrag,
    required this.gravity,
    required this.maxFallSpeed,
    required this.jumpSpeed,
    required this.airJumpSpeed,
    required this.fastFallSpeed,
    required this.airJumps,
    required this.dodgeFrames,
    required this.dodgeSpeed,
    required this.dodgeCooldown,
    required this.moves,
  });

  final String name;
  final Fx width;
  final Fx height;

  /// 100 = average. Heavier fighters take less knockback.
  final int weight;

  final Fx walkSpeed;

  /// How much horizontal speed can change per tick, on the ground and in the
  /// air. Low air acceleration keeps momentum after being launched.
  final Fx groundAccel;
  final Fx airAccel;

  /// Slow-down per tick while attacking on the ground, so a lunge slides.
  final Fx attackFriction;

  /// Slow-down per tick while flying from a hit.
  final Fx knockbackDrag;

  final Fx gravity;
  final Fx maxFallSpeed;

  /// Upward speed of the ground jump and of each air jump.
  final Fx jumpSpeed;
  final Fx airJumpSpeed;

  /// Fall speed while holding down in the air.
  final Fx fastFallSpeed;

  /// Extra jumps allowed before landing again.
  final int airJumps;

  /// Invincible ticks per dodge, travel speed of a directional dodge, and
  /// ticks before the next dodge.
  final int dodgeFrames;
  final Fx dodgeSpeed;
  final int dodgeCooldown;

  /// Every [MoveKind] must be present.
  final Map<MoveKind, AttackDef> moves;

  AttackDef move(MoveKind kind) => moves[kind]!;
}

/// Stage layout. Screen coordinates: y grows downward.
class StageDef {
  const StageDef({
    required this.name,
    required this.groundLeft,
    required this.groundRight,
    required this.groundY,
    required this.blastLeft,
    required this.blastRight,
    required this.blastTop,
    required this.blastBottom,
    required this.spawnX,
    required this.spawnY,
  });

  final String name;

  /// Top surface of the main platform.
  final Fx groundLeft;
  final Fx groundRight;
  final Fx groundY;

  /// Crossing any of these loses a stock.
  final Fx blastLeft;
  final Fx blastRight;
  final Fx blastTop;
  final Fx blastBottom;

  /// Spawn point per player slot.
  final List<Fx> spawnX;
  final Fx spawnY;

  static const flatArena = StageDef(
    name: 'Flat Arena',
    groundLeft: Fx.fromInt(-500),
    groundRight: Fx.fromInt(500),
    groundY: Fx.zero,
    blastLeft: Fx.fromInt(-1100),
    blastRight: Fx.fromInt(1100),
    blastTop: Fx.fromInt(-900),
    blastBottom: Fx.fromInt(600),
    spawnX: [Fx.fromInt(-200), Fx.fromInt(200)],
    spawnY: Fx.fromInt(-300),
  );
}
