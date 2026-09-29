import 'fixed.dart';

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

  /// Hitbox center, measured from the attacker's feet: [forward] in the
  /// facing direction, [up] above the feet.
  final Fx forward;
  final Fx up;
  final Fx width;
  final Fx height;

  int get totalFrames => startup + active + recovery;

  /// [frame] counts from 1 on the tick the attack starts.
  bool isActiveOn(int frame) => frame > startup && frame <= startup + active;
}

/// Tuning values for one fighter. Units: world units and ticks (1/60 s).
///
/// Placeholder numbers for now; these move to JSON once the move set exists.
class FighterDef {
  const FighterDef({
    required this.name,
    required this.width,
    required this.height,
    required this.weight,
    required this.walkSpeed,
    required this.groundAccel,
    required this.airAccel,
    required this.knockbackDrag,
    required this.gravity,
    required this.maxFallSpeed,
    required this.jumpSpeed,
    required this.airJumpSpeed,
    required this.fastFallSpeed,
    required this.lightAttack,
    this.airJumps = 2,
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

  final AttackDef lightAttack;

  static const knight = FighterDef(
    name: 'Knight',
    width: Fx.fromInt(48),
    height: Fx.fromInt(96),
    weight: 115,
    walkSpeed: Fx.fromInt(6),
    groundAccel: Fx.fromInt(6),
    airAccel: Fx.ratio(2, 5),
    knockbackDrag: Fx.ratio(1, 4),
    gravity: Fx.ratio(3, 5),
    maxFallSpeed: Fx.fromInt(16),
    jumpSpeed: Fx.fromInt(15),
    airJumpSpeed: Fx.fromInt(13),
    fastFallSpeed: Fx.fromInt(24),
    lightAttack: AttackDef(
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
    ),
  );

  static const ranger = FighterDef(
    name: 'Ranger',
    width: Fx.fromInt(40),
    height: Fx.fromInt(88),
    weight: 90,
    walkSpeed: Fx.fromInt(8),
    groundAccel: Fx.fromInt(8),
    airAccel: Fx.ratio(1, 2),
    knockbackDrag: Fx.ratio(1, 4),
    gravity: Fx.ratio(1, 2),
    maxFallSpeed: Fx.fromInt(14),
    jumpSpeed: Fx.fromInt(14),
    airJumpSpeed: Fx.fromInt(12),
    fastFallSpeed: Fx.fromInt(21),
    lightAttack: AttackDef(
      startup: 3,
      active: 3,
      recovery: 9,
      damage: 5,
      baseKnockback: Fx.fromInt(4),
      knockbackGrowth: Fx.fromInt(12),
      launchX: Fx.ratio(4, 5),
      launchY: Fx.ratio(-3, 5),
      forward: Fx.fromInt(44),
      up: Fx.fromInt(56),
      width: Fx.fromInt(52),
      height: Fx.fromInt(28),
    ),
  );
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
