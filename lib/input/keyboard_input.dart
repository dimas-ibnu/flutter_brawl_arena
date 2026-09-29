import 'package:flutter/services.dart';

import '../sim/input_frame.dart';

/// Default keyboard layout from the PRD: WASD to move, Space jump,
/// J light, K heavy, L dodge, H weapon.
final Map<LogicalKeyboardKey, Button> defaultKeyboardLayout = {
  LogicalKeyboardKey.keyA: Button.left,
  LogicalKeyboardKey.keyD: Button.right,
  LogicalKeyboardKey.keyW: Button.up,
  LogicalKeyboardKey.keyS: Button.down,
  LogicalKeyboardKey.space: Button.jump,
  LogicalKeyboardKey.keyJ: Button.light,
  LogicalKeyboardKey.keyK: Button.heavy,
  LogicalKeyboardKey.keyL: Button.dodge,
  LogicalKeyboardKey.keyH: Button.weapon,
};

InputFrame inputFromKeys(
  Set<LogicalKeyboardKey> pressed, [
  Map<LogicalKeyboardKey, Button>? layout,
]) {
  final keys = layout ?? defaultKeyboardLayout;
  return InputFrame.of([for (final key in pressed) ?keys[key]]);
}
