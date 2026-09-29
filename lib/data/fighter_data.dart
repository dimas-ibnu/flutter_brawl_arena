import 'dart:convert';

import '../sim/defs.dart';
import '../sim/fixed.dart';

/// Path of the fighter data inside the app bundle.
const fightersAsset = 'assets/data/fighters.json';

/// Parses assets/data/fighters.json into fighter definitions, keyed by id
/// ("knight", "ranger").
///
/// JSON numbers become [Fx] here, once, at load time. Dart parses decimals
/// the same way on every platform, so the resulting values are identical
/// everywhere.
Map<String, FighterDef> parseFighters(String json) {
  final root = jsonDecode(json) as Map<String, dynamic>;
  return {
    for (final entry in root.entries)
      entry.key: _fighter(entry.key, entry.value as Map<String, dynamic>),
  };
}

FighterDef _fighter(String id, Map<String, dynamic> j) {
  final dodge = j['dodge'] as Map<String, dynamic>;
  final moveJson = j['moves'] as Map<String, dynamic>;
  final moves = <MoveKind, AttackDef>{};
  for (final kind in MoveKind.values) {
    final m = moveJson[kind.name];
    if (m == null) {
      throw FormatException('Fighter "$id" is missing move "${kind.name}"');
    }
    moves[kind] = _attack(m as Map<String, dynamic>);
  }
  return FighterDef(
    name: j['name'] as String,
    width: _fx(j['width']),
    height: _fx(j['height']),
    weight: j['weight'] as int,
    walkSpeed: _fx(j['walkSpeed']),
    groundAccel: _fx(j['groundAccel']),
    airAccel: _fx(j['airAccel']),
    attackFriction: _fx(j['attackFriction']),
    knockbackDrag: _fx(j['knockbackDrag']),
    gravity: _fx(j['gravity']),
    maxFallSpeed: _fx(j['maxFallSpeed']),
    jumpSpeed: _fx(j['jumpSpeed']),
    airJumpSpeed: _fx(j['airJumpSpeed']),
    fastFallSpeed: _fx(j['fastFallSpeed']),
    airJumps: j['airJumps'] as int,
    dodgeFrames: dodge['frames'] as int,
    dodgeSpeed: _fx(dodge['speed']),
    dodgeCooldown: dodge['cooldown'] as int,
    moves: moves,
  );
}

AttackDef _attack(Map<String, dynamic> m) {
  final knockback = m['knockback'] as Map<String, dynamic>;
  final launch = m['launch'] as List<dynamic>;
  final hitbox = m['hitbox'] as Map<String, dynamic>;
  final self = m['selfVelocity'] as List<dynamic>?;
  return AttackDef(
    startup: m['startup'] as int,
    active: m['active'] as int,
    recovery: m['recovery'] as int,
    damage: m['damage'] as int,
    baseKnockback: _fx(knockback['base']),
    knockbackGrowth: _fx(knockback['growth']),
    launchX: _fx(launch[0]),
    launchY: _fx(launch[1]),
    launchAway: m['launchAway'] as bool? ?? false,
    forward: _fx(hitbox['forward']),
    up: _fx(hitbox['up']),
    width: _fx(hitbox['width']),
    height: _fx(hitbox['height']),
    selfVx: self == null ? Fx.zero : _fx(self[0]),
    selfVy: self == null ? Fx.zero : _fx(self[1]),
    endsOnLanding: m['endsOnLanding'] as bool? ?? false,
  );
}

Fx _fx(Object? value) => Fx.fromDouble((value as num).toDouble());
