import 'fixed.dart';

/// Tuning values for one fighter. Units: world units and ticks (1/60 s).
///
/// Placeholder numbers for now; these move to JSON once the move set exists.
class FighterDef {
  const FighterDef({
    required this.name,
    required this.width,
    required this.height,
    required this.walkSpeed,
    required this.gravity,
    required this.maxFallSpeed,
    required this.jumpSpeed,
    required this.airJumpSpeed,
    required this.fastFallSpeed,
    this.airJumps = 2,
  });

  final String name;
  final Fx width;
  final Fx height;
  final Fx walkSpeed;
  final Fx gravity;
  final Fx maxFallSpeed;

  /// Upward speed of the ground jump and of each air jump.
  final Fx jumpSpeed;
  final Fx airJumpSpeed;

  /// Fall speed while holding down in the air.
  final Fx fastFallSpeed;

  /// Extra jumps allowed before landing again.
  final int airJumps;

  static const knight = FighterDef(
    name: 'Knight',
    width: Fx.fromInt(48),
    height: Fx.fromInt(96),
    walkSpeed: Fx.fromInt(6),
    gravity: Fx.ratio(3, 5),
    maxFallSpeed: Fx.fromInt(16),
    jumpSpeed: Fx.fromInt(15),
    airJumpSpeed: Fx.fromInt(13),
    fastFallSpeed: Fx.fromInt(24),
  );

  static const ranger = FighterDef(
    name: 'Ranger',
    width: Fx.fromInt(40),
    height: Fx.fromInt(88),
    walkSpeed: Fx.fromInt(8),
    gravity: Fx.ratio(1, 2),
    maxFallSpeed: Fx.fromInt(14),
    jumpSpeed: Fx.fromInt(14),
    airJumpSpeed: Fx.fromInt(12),
    fastFallSpeed: Fx.fromInt(21),
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
